# Mouse Trap — Development Task Progress

## Day 2 Sequential Nest Tutorial — Implementation Complete ✅

### Summary of Changes

| File                                          | What Changed                                                                                                                                                                                                                          |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/routine_manager.gd`                  | Added Day 2 sequential step machine (`day2_step` 1-6), 5 objectives, per-step lore hints (`DAY2_NEST_HINTS`), cabin door lock/unlock on Step 1, terminal upload gating                                                                |
| `scripts/hasselmus_nest.gd`                   | Added interaction lock system (`lock_type`: "overcharge"/"stealth"/"stillness"/"none"), proximity tutorials via `TutorialManager.trigger()`, contextual clue prompt swapping                                                          |
| `scripts/door.gd`                             | Added public `lock()` and `unlock()` methods (door stays closed, player must interact to open)                                                                                                                                        |
| `scripts/ui/notebook_ui.gd`                   | Notifies `RoutineManager.on_notebook_opened()` (Step 1 gate), connects `objective_hint_changed` signal, renders Day 2 hint in To-Do list                                                                                              |
| `scripts/managers/tutorial_manager.gd`        | Registered 3 new tutorial resources: `tutorial_overcharge`, `tutorial_stealth`, `tutorial_stillness`                                                                                                                                  |
| `resources/tutorial/tutorial_overcharge.tres` | NEW — "Hold [F] to OVERCHARGE your flashlight..."                                                                                                                                                                                     |
| `resources/tutorial/tutorial_stealth.tres`    | NEW — "Hold [CTRL] to crouch..."                                                                                                                                                                                                      |
| `resources/tutorial/tutorial_stillness.tres`  | NEW — "Stand completely still to listen."                                                                                                                                                                                             |
| `scenes/cottage_horror.tscn`                  | Nest Alpha: `lock_type="overcharge"`, `lock_duration=1.5`, `tutorial_id="overcharge"`; Nest Beta: `lock_type="stealth"`, `tutorial_id="stealth"`; Nest Gamma: `lock_type="stillness"`, `lock_duration=3.0`, `tutorial_id="stillness"` |

### Day 2 Objective Flow

1. **Step 1** — "Review the previous researcher's Nest Logs in your Notebook."
   - Cabin door is LOCKED at Day 2 start
   - Opening the notebook calls `RoutineManager.on_notebook_opened()` → unlocks door

2. **Step 2** — "Locate and document Nest Alpha."
   - Hint: "I may need a high-intensity beam to provoke them."
   - Tutorial on approach: "Hold [F] to OVERCHARGE your flashlight..."
   - Requires `is_overcharged == true` for 1.5s to interact

3. **Step 3** — "Locate and document Nest Beta."
   - Hint: "I should sneak when approaching the nest."
   - Tutorial on approach: "Hold [CTRL] to crouch..."
   - Requires crouching AND flashlight off to interact

4. **Step 4** — "Locate and document Nest Gamma."
   - Hint: "I must remain perfectly still to hear them."
   - Tutorial on approach: "Stand completely still to listen."
   - Requires velocity near zero for 3.0s to interact

5. **Step 5** — "Log the collected nest data into the cabin's computer terminal."
   - FIELD_LOG.EXE dropdown validation success calls `RoutineManager.on_nest_data_uploaded()`
   - Gated: only completes if all 3 nests documented first

### Interaction Lock Clue Prompts (while lock NOT satisfied)

| Nest  | Lock Type  | Clue Text                             |
| ----- | ---------- | ------------------------------------- |
| Alpha | overcharge | "Nest Dormant - Requires Provocation" |
| Beta  | stealth    | "Nest Hidden - Too Visible"           |
| Gamma | stillness  | "Nest Silent - Too Much Noise"        |

### Validation Status

- ✅ All modified scripts parse without new errors
- ⚠️ Remaining pre-existing issues unrelated to this task:
  - Integer division warnings in tutorial_manager/horror_hud
  - Invalid UID `uid://cable_spool_scene` in `cable_spool_resource.tres`
  - `set_deferred` warnings in `cabin_approach_trigger.gd`
  - Missing audio files in `computer_ui.gd` (`win98_error.ogg`, `ui_click_success.ogg`)
  - `window_peeker.gd` `get_global_transform()` during exit
  - Empty `xray_key` group at highlight time

---

## Bug Fixes + Implementations (2026-08-28) — Complete ✅

### Bug 1 — Flashlight tutorial fires when Night 1 + has flashlight coincide

- `scripts/managers/tutorial_manager.gd`: added `try_trigger_flashlight()`; `_on_night_started()` now routes through it (gated on `current_night == 1` AND player `has_flashlight()`).
- `scripts/player_controller.gd`: added `has_flashlight()` accessor.
- `scripts/flashlight_pickup.gd`: pickups now call `TutorialManager.try_trigger_flashlight()` so a pickup during Night 1 still fires the hint.

### Bug 2 — Generator highlight targets `generator_1`, not the switch

- `scripts/routine_manager.gd` `_should_highlight_mesh()`: for `xray_generator`, now EXCLUDES `button`/`switch` meshes and highlights the generator body. The switch remains on its own `xray_generator_switch` group (post-refuel).

### Bug 3 — "Hold [SHIFT] to RUN" hint missing during Night 2.2

- `resources/tutorial/tutorial_sprint.tres`: explicitly set `day_one_only = false` (the script default is `true`).

### Bug 4 — Bed re-triggers Night 2.2

- `scripts/night_manager.gd`: added persistent `van_sequence_started` flag; reset in the `night == 1` block.
- `scripts/bed_interactable.gd`: CONDITION 2 now requires `not van_sequence_started`; sets the flag when starting Night 2.2.

### Impl 1 — Fuel can % in inventory

- `scripts/inventory/inventory_ui.gd`: added `_build_item_display_name()` (appends `(X%)` for fuel cans using `fuel_amount`). Used by the detail label and hover tooltip.

### Impl 2 — Cable spool physics

- `scenes/cable_spool.tscn`: BoxShape3D corrected to `(0.104, 0.104, 0.03)` to match `electrical_tape_etx_1_1.glb` bounds (Y/Z were previously swapped/mismatched).

### Impl 3 — Nest highlight timers +15s

- `scripts/routine_manager.gd`: Nest Alpha `20.0 → 35.0`, Beta `35.0 → 50.0`, Gamma `35.0 → 50.0`. Alpha scheduling confirmed to fire in `on_previous_reports_read()` (step 1→2 transition = start of "Document nest alpha"), not `on_day2_started()`.
