# Task Progress: AI State Machine Refactor

## Todo List

### 1. Fix Circular Dependency

- [x] Delete `const EntityAI := preload("entity_ai.gd")` from entity_controller.gd line 13
- [x] Update entity_controller.gd to use `EntityAI.State.X` via class_name (already works since entity_ai.gd has `class_name EntityAI`)
- [x] Fix entity_director.gd's preload of entity_ai.gd (line 62) - use class_name instead

### 2. Implement State Persistence Guard (entity_director.gd)

- [x] Add `_state_timer` float to entity_controller.gd (Blackboard)
- [x] Add getter/setter for state_timer in entity_controller.gd
- [x] Add state persistence guard in entity_director.gd's evaluate_master_state()

### 3. Implement Room-Center Investigation

- [x] Update entity_sensory.gd to store `last_heard_room` when noise occurs
- [x] Update entity_controller.gd to expose `last_heard_room` on Blackboard
- [x] Update entity_ai.gd's `_indoor_search_state()` to pathfind to room center when no LOS
- [x] Add scan timer logic (4-second rotate + scan) when arriving at room center

### 4. Zero-Animation Stun

- [x] Add stare-based stun logic in entity_ai.gd's main state loop
- [x] Force velocity = Vector3.ZERO when is_being_stared_at and not CHARGE/RETREAT
- [x] Force animation tree to travel("Idle") when stunned
- [x] Implement `_stare_timer` that resets if player looks away, triggers enrage at 1.5s
