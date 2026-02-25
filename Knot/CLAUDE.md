# Knot — Project Rules

## Memory Bank (Read First)

Before starting ANY work, read the memory bank files in `memory-bank/`:

1. `memory-bank/progress.md` — Implementation history and current status
2. `memory-bank/architecture.md` — Full architecture reference for all files and modules
3. `memory-bank/IMPLEMENTATION_PLAN.md` — Step-by-step build roadmap
4. `memory-bank/PRD.md` — Product requirements and personas
5. `memory-bank/techstack.md` — Technology stack decisions

This is mandatory for every new session or agent task. Do not skip this step.

## Testing Requirements

Every new feature must include tests before it is considered complete:

- **Backend (Python/FastAPI):** Write tests in `backend/tests/` and run `cd backend && python -m pytest`
- **iOS (Swift/SwiftUI):** Write tests in `iOS/KnotTests/` and run via `xcodebuild test` or Xcode

A feature is not done until all new and existing tests pass.

## Documentation Updates

After completing a new feature, update the following documentation:

### progress.md
- Add a new `### Step X.Y` entry under `## Completed Steps`
- Insert it BEFORE `## Next Steps` (never append to end of file)
- Follow the existing format: Step title with checkmark, date, status, and detailed description
- Strict section order: `## Completed Steps` → `## Next Steps` → `## Notes for Future Developers`

### architecture.md
- Update relevant sections to reflect any new or modified files, modules, or patterns
- Follow the existing table/description format
