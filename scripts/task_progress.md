# Fix 1: STALK vs PATROL - Visual Confirmation Gate in Director

- [x] Update `_tier_3_active_aggression()` in entity_director.gd: When `thinks_player_is_inside == false` AND `is_hunting()`, check `can_entity_see_player()` — if NOT visible, return OBSERVE_FROM_TREELINE instead of STALK

# Fix 2: Revamp Belief Deduction (3-Waypoint Miss Rule)

- [x] Update `_observe_from_treeline_state()` in entity_ai.gd: Replace `set_thinks_player_is_inside(false)` with confidence boost + impatience mechanic
- [x] Update `hear_noise()` in entity_controller.gd: Add outdoor noise detection → `set_thinks_player_is_inside(false)`

# Fix 3: Fix Sensory Blindness through Windows

- [x] Update `_calculate_vision_range()` in entity_sensory.gd: Add dynamic vision range for OBSERVE_FROM_TREELINE and WINDOW_PEEK states (30-40m)
- [x] Update `can_entity_see_player()` in entity_sensory.gd: Add belief system updates (reset misses on indoor sight, set thinks_player_is_inside=false on outdoor sight)
