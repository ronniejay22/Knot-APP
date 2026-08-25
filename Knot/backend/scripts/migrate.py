#!/usr/bin/env python
"""
Apply pending Supabase migrations from backend/supabase/migrations/.

Why this exists
---------------
Migrations were applied by hand, by pasting SQL into the Supabase SQL Editor.
Nothing recorded what had actually been run, so the database silently drifted
from the repo: by August 2026 three migrations (00022, 00023, 00027) had never
been applied. Both of the older two fail *quietly* — briefing inserts are
wrapped in try/except and plan-type recommendations are rejected by a CHECK
constraint the code never checks — so the drift produced no error anyone would
notice, only features that mysteriously did nothing.

This runner keeps a `schema_migrations` ledger in the database, so "what is
live" is a question with an answer.

Usage
-----
    python backend/scripts/migrate.py status
    python backend/scripts/migrate.py apply [--dry-run]
    python backend/scripts/migrate.py baseline --all-except 00022,00023,00027

`baseline` marks migrations as applied *without running them* — needed exactly
once, to adopt a database whose schema predates this ledger. Everything after
that is `status` / `apply`.

Requires DATABASE_URL in backend/.env (Supabase dashboard → Settings →
Database → Connection string → URI).
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

BACKEND_DIR = Path(__file__).resolve().parent.parent
MIGRATIONS_DIR = BACKEND_DIR / "supabase" / "migrations"

load_dotenv(dotenv_path=BACKEND_DIR / ".env")

#: Files are `NNNNN_description.sql`; the numeric prefix defines apply order.
_FILENAME_RE = re.compile(r"^(\d+)_.*\.sql$")

_LEDGER_DDL = """
CREATE TABLE IF NOT EXISTS public.schema_migrations (
    version     TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    baselined   BOOLEAN NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE public.schema_migrations IS
    'Ledger of applied migrations, maintained by backend/scripts/migrate.py. '
    'baselined = adopted without executing (schema predated the ledger).';

-- Anything in `public` is exposed through PostgREST once the schema cache
-- reloads, and the anon key is shipped inside the iOS app. Without this, a
-- forged row could mark a real migration applied and it would be skipped
-- forever. RLS with no policies denies everyone; service_role (this script)
-- bypasses RLS. Both statements are idempotent, so they also repair a ledger
-- created before this hardening.
ALTER TABLE public.schema_migrations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.schema_migrations FROM anon, authenticated;
"""


@dataclass(frozen=True)
class Migration:
    version: str
    name: str
    path: Path

    @property
    def sql(self) -> str:
        return self.path.read_text()


def discover_migrations(directory: Path = MIGRATIONS_DIR) -> list[Migration]:
    """All migrations on disk, in apply order."""
    found = []
    for path in directory.glob("*.sql"):
        match = _FILENAME_RE.match(path.name)
        if match is None:
            continue
        found.append(Migration(version=match.group(1), name=path.stem, path=path))
    # Sort numerically, not lexicographically: the regex accepts any run of
    # digits, so an unpadded `9_hotfix.sql` would otherwise sort after
    # `00010_...` and run out of order.
    return sorted(found, key=lambda m: int(m.version))


def pending(migrations: list[Migration], applied: set[str]) -> list[Migration]:
    """Migrations not yet in the ledger, in apply order."""
    return [m for m in migrations if m.version not in applied]


def parse_version_list(raw: str) -> set[str]:
    """`"00022, 00023"` -> `{"00022", "00023"}`."""
    return {part.strip() for part in raw.split(",") if part.strip()}


# ======================================================================
# Database
# ======================================================================

def connect():
    dsn = os.getenv("DATABASE_URL", "")
    if not dsn:
        sys.exit(
            "DATABASE_URL is not set in backend/.env.\n"
            "Supabase dashboard -> Settings -> Database -> Connection string -> URI"
        )
    return psycopg2.connect(dsn, connect_timeout=15)


def ensure_ledger(conn) -> None:
    with conn.cursor() as cur:
        cur.execute(_LEDGER_DDL)
    conn.commit()


def applied_versions(conn) -> set[str]:
    with conn.cursor() as cur:
        cur.execute("SELECT version FROM public.schema_migrations")
        return {row[0] for row in cur.fetchall()}


def record(conn, migration: Migration, *, baselined: bool) -> None:
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO public.schema_migrations (version, name, baselined) "
            "VALUES (%s, %s, %s) ON CONFLICT (version) DO NOTHING",
            (migration.version, migration.name, baselined),
        )


def reload_postgrest(conn) -> None:
    """
    PostgREST caches the schema. Without this a freshly added column 500s on
    every request until the cache expires — the failure mode that broke vault
    creation in Step 15.5.
    """
    with conn.cursor() as cur:
        cur.execute("NOTIFY pgrst, 'reload schema'")
    conn.commit()


# ======================================================================
# Commands
# ======================================================================

def cmd_status(args) -> int:
    migrations = discover_migrations()
    conn = connect()
    try:
        ensure_ledger(conn)
        applied = applied_versions(conn)
    finally:
        conn.close()

    outstanding = pending(migrations, applied)
    for m in migrations:
        mark = "." if m.version in applied else "PENDING"
        print(f"  {mark:8} {m.name}")
    print(f"\n{len(migrations) - len(outstanding)}/{len(migrations)} applied.")
    if outstanding:
        print(f"{len(outstanding)} pending — run: migrate.py apply")
    return 0


def cmd_apply(args) -> int:
    migrations = discover_migrations()
    conn = connect()
    try:
        ensure_ledger(conn)
        applied = applied_versions(conn)
        outstanding = pending(migrations, applied)

        if not outstanding:
            print("Nothing pending — schema matches the repo.")
            return 0

        print(f"{len(outstanding)} pending:")
        for m in outstanding:
            print(f"  {m.name}")

        if args.dry_run:
            print("\n--dry-run: nothing executed.")
            return 0

        print()
        succeeded = 0
        failure: Migration | None = None
        for m in outstanding:
            # One transaction per migration: a failure rolls back that
            # migration only, and the ledger never claims a partial apply.
            try:
                with conn.cursor() as cur:
                    cur.execute(m.sql)
                record(conn, m, baselined=False)
                conn.commit()
                succeeded += 1
                print(f"  applied  {m.name}")
            except Exception as exc:
                conn.rollback()
                failure = m
                print(f"  FAILED   {m.name}\n           {exc}")
                break

        # Reload even on failure. Whatever committed before the break is live
        # in Postgres but absent from PostgREST's cached schema, and that gap
        # 500s every request touching it — the failure this reload exists to
        # prevent does not care that the run ended badly.
        if succeeded:
            reload_postgrest(conn)
            print("\nPostgREST schema cache reloaded.")

        if failure is not None:
            print(
                f"Stopped at {failure.name}. "
                f"{succeeded} migration(s) before it are committed; "
                f"fix the SQL and re-run — they will not be re-applied."
            )
            return 1
    finally:
        conn.close()
    return 0


def count_public_tables(conn) -> int:
    """How many tables exist in `public`, excluding the ledger itself."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT count(*) FROM information_schema.tables "
            "WHERE table_schema = 'public' AND table_type = 'BASE TABLE' "
            "AND table_name <> 'schema_migrations'"
        )
        return cur.fetchone()[0]


def cmd_baseline(args) -> int:
    """Adopt an existing database: record migrations as applied, run nothing."""
    migrations = discover_migrations()
    skip = parse_version_list(args.all_except or "")

    unknown = skip - {m.version for m in migrations}
    if unknown:
        sys.exit(f"--all-except names unknown versions: {sorted(unknown)}")

    to_mark = [m for m in migrations if m.version not in skip]

    conn = connect()
    try:
        ensure_ledger(conn)

        # Two guards, because baseline is the one command that can hide the
        # very drift this tool exists to surface. Marking migrations applied
        # without running them is only ever correct for a database that
        # already has the schema.
        if applied_versions(conn):
            sys.exit(
                "The ledger already has entries — this database has already "
                "been adopted.\nBaseline is a one-time command; use `apply`."
            )
        if count_public_tables(conn) == 0:
            sys.exit(
                "Refusing to baseline: `public` has no tables, so this looks "
                "like a fresh database.\nBaselining it would mark every "
                "migration applied against an empty schema. Use `apply`."
            )

        for m in to_mark:
            record(conn, m, baselined=True)
        conn.commit()
    finally:
        conn.close()

    print(f"Baselined {len(to_mark)} migrations (marked applied, not executed).")
    if skip:
        print(f"Left pending: {', '.join(sorted(skip))}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status", help="Show applied vs pending migrations")

    apply_parser = sub.add_parser("apply", help="Run all pending migrations")
    apply_parser.add_argument(
        "--dry-run", action="store_true", help="List what would run, execute nothing"
    )

    baseline_parser = sub.add_parser(
        "baseline", help="Mark migrations applied without running them (one-time)"
    )
    baseline_parser.add_argument(
        "--all-except",
        metavar="VERSIONS",
        help="Comma-separated versions to leave pending, e.g. 00022,00023,00027",
    )

    args = parser.parse_args(argv)
    return {
        "status": cmd_status,
        "apply": cmd_apply,
        "baseline": cmd_baseline,
    }[args.command](args)


if __name__ == "__main__":
    raise SystemExit(main())
