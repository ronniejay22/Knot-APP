"""
Tests for backend/scripts/migrate.py.

Covers the pure logic — discovery, ordering, pending computation, version
parsing. The database-touching commands are deliberately not exercised here:
they need a live Postgres, and this suite is offline by default.
"""

import importlib.util
import sys
from pathlib import Path

import pytest

# `scripts/` is not a package, so load the module by path. It must be in
# sys.modules *before* exec_module: @dataclass resolves annotations through
# sys.modules[cls.__module__], which is None for an unregistered module.
_SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "migrate.py"
_spec = importlib.util.spec_from_file_location("migrate", _SCRIPT)
migrate = importlib.util.module_from_spec(_spec)
sys.modules["migrate"] = migrate
_spec.loader.exec_module(migrate)


def _write(directory: Path, name: str, sql: str = "SELECT 1;") -> Path:
    path = directory / name
    path.write_text(sql)
    return path


# ===================================================================
# 1. Discovery
# ===================================================================

class TestDiscovery:

    def test_orders_by_numeric_prefix(self, tmp_path):
        """Ordering is the whole contract — 00009 must precede 00010."""
        _write(tmp_path, "00010_ten.sql")
        _write(tmp_path, "00009_nine.sql")
        _write(tmp_path, "00002_two.sql")

        versions = [m.version for m in migrate.discover_migrations(tmp_path)]

        assert versions == ["00002", "00009", "00010"]

    def test_unpadded_versions_sort_numerically_not_lexicographically(self, tmp_path):
        """
        The regex accepts any run of digits, so zero-padding is a convention
        rather than a guarantee. Under a string sort `9_hotfix` would run
        after `00010`, silently applying migrations out of order.
        """
        _write(tmp_path, "00010_ten.sql")
        _write(tmp_path, "9_hotfix.sql")

        versions = [m.version for m in migrate.discover_migrations(tmp_path)]

        assert versions == ["9", "00010"]

    def test_ignores_files_without_a_version_prefix(self, tmp_path):
        _write(tmp_path, "00001_real.sql")
        _write(tmp_path, "README.sql")
        _write(tmp_path, "notes.txt")

        found = migrate.discover_migrations(tmp_path)

        assert [m.name for m in found] == ["00001_real"]

    def test_name_excludes_the_sql_extension(self, tmp_path):
        _write(tmp_path, "00005_create_partner_milestones_table.sql")

        assert (
            migrate.discover_migrations(tmp_path)[0].name
            == "00005_create_partner_milestones_table"
        )

    def test_sql_is_read_lazily_from_disk(self, tmp_path):
        _write(tmp_path, "00001_thing.sql", "ALTER TABLE t ADD COLUMN c TEXT;")

        assert "ADD COLUMN c TEXT" in migrate.discover_migrations(tmp_path)[0].sql

    def test_empty_directory_is_not_an_error(self, tmp_path):
        assert migrate.discover_migrations(tmp_path) == []


# ===================================================================
# 2. Pending computation
# ===================================================================

class TestPending:

    def test_returns_only_unapplied_in_order(self, tmp_path):
        for n in ("00001_a.sql", "00002_b.sql", "00003_c.sql"):
            _write(tmp_path, n)
        migrations = migrate.discover_migrations(tmp_path)

        result = migrate.pending(migrations, applied={"00001"})

        assert [m.version for m in result] == ["00002", "00003"]

    def test_gap_in_the_middle_is_still_reported(self, tmp_path):
        """
        The exact shape of the real drift: 00022/00023 unapplied while later
        migrations are live. A runner that assumed a contiguous prefix would
        silently skip them.
        """
        for n in ("00021_a.sql", "00022_b.sql", "00023_c.sql", "00024_d.sql"):
            _write(tmp_path, n)
        migrations = migrate.discover_migrations(tmp_path)

        result = migrate.pending(migrations, applied={"00021", "00024"})

        assert [m.version for m in result] == ["00022", "00023"]

    def test_nothing_pending_when_all_applied(self, tmp_path):
        _write(tmp_path, "00001_a.sql")
        migrations = migrate.discover_migrations(tmp_path)

        assert migrate.pending(migrations, applied={"00001"}) == []

    def test_ledger_entries_with_no_file_are_ignored(self, tmp_path):
        """A deleted migration file must not crash the runner."""
        _write(tmp_path, "00002_b.sql")
        migrations = migrate.discover_migrations(tmp_path)

        result = migrate.pending(migrations, applied={"00001", "00099"})

        assert [m.version for m in result] == ["00002"]


# ===================================================================
# 3. Version list parsing
# ===================================================================

class TestParseVersionList:

    @pytest.mark.parametrize(
        "raw,expected",
        [
            ("00022,00023,00027", {"00022", "00023", "00027"}),
            ("00022, 00023 , 00027", {"00022", "00023", "00027"}),
            ("00022", {"00022"}),
            ("", set()),
            ("  ", set()),
            ("00022,,00023", {"00022", "00023"}),
        ],
    )
    def test_parses(self, raw, expected):
        assert migrate.parse_version_list(raw) == expected


# ===================================================================
# 4. Ledger hardening
# ===================================================================

class TestLedgerHardening:
    """
    The ledger lives in `public`, which PostgREST exposes once the schema
    cache reloads — and the anon key ships inside the iOS app.
    """

    def test_rls_is_enabled_on_the_ledger(self):
        assert "ENABLE ROW LEVEL SECURITY" in migrate._LEDGER_DDL

    def test_anon_and_authenticated_are_revoked(self):
        assert "REVOKE ALL ON public.schema_migrations FROM anon, authenticated" \
            in migrate._LEDGER_DDL

    def test_ledger_ddl_is_idempotent(self):
        """It runs on every command, so it must repair rather than fail."""
        assert "CREATE TABLE IF NOT EXISTS" in migrate._LEDGER_DDL


# ===================================================================
# 5. The real migrations directory
# ===================================================================

class TestRepoMigrations:

    def test_every_migration_file_is_discoverable(self):
        """
        A file the runner can't parse is a file that never gets applied — and
        would drift silently, which is the failure this script exists to end.
        """
        on_disk = sorted(p.name for p in migrate.MIGRATIONS_DIR.glob("*.sql"))
        discovered = sorted(m.path.name for m in migrate.discover_migrations())

        assert discovered == on_disk

    def test_versions_are_unique(self):
        versions = [m.version for m in migrate.discover_migrations()]

        assert len(versions) == len(set(versions))

    def test_migrations_are_non_empty(self):
        for m in migrate.discover_migrations():
            assert m.sql.strip(), f"{m.name} is empty"
