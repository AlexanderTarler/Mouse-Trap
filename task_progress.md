# Day 1 Onboarding Implementation

## Phase-Based Boolean System

### Phase 1: Entry — "Get inside the cabin."

- [x] 1. Refactor `routine_manager.gd` with Phase-based boolean system
- [x] 2. Add `_apply_dev_mode_settings()` to `night_manager.gd`
- [x] 3. Modify `door.gd` to call RoutineManager for locked/unlocked
- [x] 4. Modify `inventory/inventory.gd` to detect key pickup
- [x] 5. Modify `player_controller.gd` to detect cabin entry
- [x] 6. Create CabinApproachTrigger in `cottage_horror.tscn`
- [x] 7. Modify `fuse_box.gd` to call RoutineManager
- [x] 8. Modify `generator_interaction.gd` to call RoutineManager
- [x] 9. Modify `pc_interactable.gd` to call RoutineManager
- [x] 10. Modify `bed_interactable.gd` for Phase 3 + Day 2 transition
- [x] 11. Update `night_manager.gd` time management (4:00 PM start, pause/unpause)
- [x] 12. Update `horror_hud.gd` to work with new RoutineManager signals
- [x] 13. Modify `cabin_light.gd` to notify RoutineManager when lights are toggled off
- [x] 14. Add `start_in_dev_mode` export to `player_controller.gd` and `player.tscn`
- [x] 15. Fix: `current_night` starts at 0 (Day 1) instead of 1 (Night 1)
- [x] 16. Fix: Cabin entry detection only triggers on "Outside" → inside transition
- [x] 17. Fix: `_find_game_time()` no longer auto-starts night when `current_night == 0`
- [x] 18. Fix: `_on_scene_ready()` waits for player to exist before setting spawn/dev mode
- [x] 19. Fix: `setup_player_spawn()` searches for "PlayerSpawn" under "PlayerSpawnpoints" Node3D
- [x] 20. Fix: `_set_initial_time()` triggers `night_started` signal via `set_progress()` — use direct assignment instead
- [x] 21. Fix: `_on_scene_ready()` 60-frame wait loop exits before player appears — use `_process()` polling instead
- [x] 22. Fix: Cabin entry `_previous_room` starts as "Outside" causing false trigger — use `""` calibration frame instead
