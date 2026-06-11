# Tactical Retreat Implementation

## Progress

- [x] Analyze existing codebase — found `_indoor_breach_window`, `is_indoor_retreat`, and `_indoor_retreat_handler` already exist
- [x] STEP 1: Store `_indoor_breach_window` during normal INDOOR_SEARCH transition (Phase A of `_indoor_search_state`)
- [x] STEP 2: Update Director to handle CHASE indoors + expand indoor retreat to cover CHASE state
- [x] STEP 3: Modify indoor retreat Phase 2 to transition to FLINCH state after escaping outside (instead of Phase 3 treeline pathfinding)
- [x] Verify all changes are consistent and complete
