---
description: Keep an API contract in sync across the two hand-maintained layers — the backend Pydantic model in backend/app/models/*.py and the iOS Swift Codable DTO in iOS/Knot/Models/DTOs.swift (plus any SwiftData *Local.swift mirror). Use whenever you add/rename/retype a field on a request or response model. Closes the gap that otherwise only surfaces at runtime JSON decode.
argument-hint: [model or endpoint name]
---

# /sync-dto

Every Knot API contract is maintained twice by hand: a Pydantic model (snake_case) in
`backend/app/models/*.py` and a Swift `Codable, Sendable` struct (camelCase + `CodingKeys`) in
`iOS/Knot/Models/DTOs.swift`. There is no codegen, so a field added on one side and forgotten on
the other decodes to a runtime error, not a compile error. This skill regenerates the matching
side (and flags the SwiftData mirror) from whichever side you changed.

Works in either direction. Run from the `Knot/` directory.

## Phase 1 — Identify the source of truth

1. Determine the changed model and direction from the `[model or endpoint name]` argument and the
   diff (`git diff`).
   - **Backend-first (common):** a `class X(BaseModel)` in `backend/app/models/<area>.py` gained,
     renamed, or retyped a field → regenerate the Swift DTO.
   - **Swift-first:** a `struct X` in `DTOs.swift` changed → regenerate the Pydantic model.
2. Find the counterpart. Swift DTOs name their peer explicitly in a doc comment
   (`/// ... matches the backend Pydantic \`VaultCreateRequest\``). Otherwise
   `grep -rn "class <Name>" backend/app/models/` and `grep -n "struct <Name>" iOS/Knot/Models/DTOs.swift`.

## Phase 2 — Map the fields

Snake_case (Pydantic) ⇄ camelCase (Swift), field by field, with these type mappings:

| Pydantic | Swift | Notes |
|----------|-------|-------|
| `str` | `String` | |
| `int` | `Int` | cents stay `Int` (e.g. `price_cents` → `priceCents`) |
| `float` | `Double` | non-optional floats (e.g. scores) are always present in JSON — Swift decodes a required `Double`, no default needed |
| `bool` | `Bool` | |
| `Optional[X]` / `X \| None` | `X?` | nullable ⇄ optional both directions |
| `Literal["a","b"]` | `String` | Swift stays `String`; note the allowed values (see Phase 4) |
| `list[X]` | `[X]` | |
| `dict[str, str]` | `[String: String]` | e.g. `love_languages` |
| nested `BaseModel` | matching Swift `struct` | recurse — sync the sub-model too |

## Phase 3 — Regenerate the counterpart

**Swift DTO** (in `iOS/Knot/Models/DTOs.swift`), matching the existing structs exactly:
- `struct <Name>: Codable, Sendable { ... }` with camelCase `let` properties.
- An explicit `enum CodingKeys: String, CodingKey` mapping **every** property whose JSON key
  isn't identical to its Swift name to the snake_case Pydantic field (identical names can share
  one `case a, b, c` line).
- A doc comment naming the peer: `/// Matches the backend Pydantic \`<Name>\`.` and the endpoint.
- Place it under the correct `// MARK: - <Area>` section.
- Append a line to the file-header changelog block referencing the step
  (e.g. `//  Step X.Y: Added <field/struct> to <Name>.`).

**Pydantic model** (Swift-first): add the field with its `Literal`/type, snake_case name, and any
`@field_validator`/`@model_validator` the contract needs; keep `VALID_*` constants and docstrings
in the file's style.

## Phase 4 — SwiftData mirror + validation parity

1. **SwiftData local model.** If the contract has a persisted mirror in `iOS/Knot/Models/*Local.swift`
   (`RecommendationLocal`, `SavedRecommendation`, `PartnerVaultLocal`, `MilestoneLocal`, `HintLocal`)
   or a `PreviewRecommendations` fixture, patch it too — add the property, its `init` parameter (with
   a default), and its "Database columns mapped" doc line. Watch the known gotchas:
   - `description` is stored as `descriptionText` in Swift models (avoids
     `CustomStringConvertible.description`).
   - Server-only fields are deliberately excluded from local models (e.g. `hint_embedding` /
     768-dim vectors are never persisted on-device). Don't add them.
2. **Validation parity (note, don't port).** Pydantic validators (counts, `Literal` sets, length
   caps) have no Swift equivalent, but the Swift side must *send* valid values — record the allowed
   `Literal` values as a comment on the Swift property so callers pick from the right set.

## Phase 5 — Verify

- The Swift struct's JSON keys (property name or its `CodingKeys` raw value) equal the Pydantic
  field names one-for-one — no field on either side without a counterpart.
- Reproduce an already-synced struct from its Pydantic peer and diff against the committed
  version — it should match, confirming the mapping rules.
- Build/tests still pass: `xcodebuild build` for the iOS side; the backend model's tests
  (`backend/tests/test_<area>_api.py`, `RecommendationDTOTests` / vault decode tests on iOS) should
  stay green. Run them via the project's worktree test commands (CLAUDE.md) before handing to
  `/ship-pr`.
