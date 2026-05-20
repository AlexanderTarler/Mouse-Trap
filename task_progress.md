# Tree Spawner, HUD Clock, & Message Fade - Task Progress

## Todo List

- [x] Task 1: Fix HUD clock freeze after phone drop
  - [x] game_time.gd: Add time_changed.emit() inside unpause_time()
  - [x] horror_hud.gd: Connect to time_changed signal for immediate refresh
- [x] Task 2: UI Message Fade Out - Set event_timer.wait_time = 3.0
- [x] Task 3: Rewrite tree_spawner.gd with Grid Blanket Spawner
