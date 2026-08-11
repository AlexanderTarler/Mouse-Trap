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
| `resources/tutorial/tutorial_stealth.tres`    | NEW — "Press [F] to turn off your flashlight. Hold [CTRL] to crouch..."                                                                                                                                                               |
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
   - Tutorial on approach: "Press [F] to turn off your flashlight. Hold [CTRL] to crouch..."
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
- ⚠️ Remaining 7 errors are pre-existing issues unrelated to this task (integer division warnings in tutorial_manager/horror_hud, invalid UIDs in cable_spool/light_switch scenes, set_deferred issue in cabin_approach_trigger)
