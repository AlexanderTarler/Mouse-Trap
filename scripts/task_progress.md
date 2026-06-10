# Master Behavior Director - Bug Fix Plan

## Root Cause

11 rogue `set_state()` calls in `entity_controller.gd` bypass the Director, causing the FLINCH/OBSERVE loop.

## Fix Strategy

1. Add `_pending_state` variable to entity_controller.gd
2. Add `request_state()` method that sets `_pending_state`
3. Update Director to read `_pending_state` at the top of `evaluate_master_state()`
4. Convert all 11 rogue `set_state()` calls to `request_state()`
5. Add Director rules for all transitions that were previously handled by rogue calls
6. Keep `state_locked` mechanism intact
