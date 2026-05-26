# 3D Game Experiment - Comprehensive Analysis & Improvement Plan

## Project Overview

A first-person horror game set in a Swedish forest cabin (Tiveden National Park). The player survives nights while being stalked by an entity, manages resources (flashlight batteries, fuel for generator), boards up windows, and uncovers lore through a computer terminal.

---

## PART 1: CODE EFFICIENCY IMPROVEMENTS

### 1.1 Duplicate Crosshair Code in `player_controller.gd`

**File:** `scripts/player_controller.gd`
**Issue:** Lines 116-153 (`_create_crosshair`) and lines 155-190 (`_rebuild_crosshair`) contain nearly identical code for creating crosshair segments. This violates DRY (Don't Repeat Yourself).
**Fix:** Extract crosshair creation into a helper function that both methods call.
**Risk:** Low. Pure refactor, no behavioral change.

### 1.2 Duplicate Raycast Logic in `physical_grab.gd`

**File:** `scripts/physical_grab.gd`
**Issue:** `_try_grab()` (lines 140-182) and `_find_grabbable_target()` (lines 234-263) perform nearly identical raycast queries. The only difference is what they do with the result.
**Fix:** Extract a shared `_raycast_center()` helper method.
**Risk:** Low. Pure refactor.

### 1.3 Hardcoded Scene Paths in Multiple Files

**Files:** `scripts/player_controller.gd`, `scripts/computer_ui.gd`, `scripts/inventory/inventory.gd`, etc.
**Issue:** Multiple scripts use hardcoded absolute paths like `/root/CottageHorror/Player` and `/root/Main/Player` to find nodes. This is fragile — if the scene structure changes, these break silently.
**Fix:** Use `get_tree().get_first_node_in_group("player")` (player is already added to "player" group in `_ready()`). For other nodes, use autoloads (singletons) or groups.
**Risk:** Low-Medium. Requires verifying that all relevant nodes are in the correct groups.

### 1.4 Redundant Player Lookup in `computer_ui.gd`

**File:** `scripts/computer_ui.gd`
**Issue:** Lines 39-41 try two hardcoded paths to find the player. This is brittle.
**Fix:** Use `get_tree().get_first_node_in_group("player")` instead.
**Risk:** Low.

### 1.5 `interaction_manager.gd` - Player Reference via Parent Traversal

**File:** `scripts/interaction_manager.gd`
**Issue:** Line 68 uses `get_parent().get_parent()` to find the player. This assumes a specific scene tree structure.
**Fix:** Use `get_tree().get_first_node_in_group("player")` or pass player reference via `set_camera()`.
**Risk:** Low.

### 1.6 `night_manager.gd` - Potential Signal Connection Issues

**File:** `scripts/night_manager.gd`
**Issue:** If `horror_event` signal is emitted before the NightManager is ready, connections may be missed. The signal is emitted from `computer_ui.gd` via `nm.horror_event.emit("nest_data_uploaded")`.
**Fix:** Use a deferred call or ensure proper initialization order. Consider using an autoload EventBus pattern.
**Risk:** Low. Currently works because computer is interacted with after night starts.

### 1.7 `entity_ai.gd` - State Machine Could Be More Explicit

**File:** `scripts/entity/entity_ai.gd`
**Issue:** The entity AI uses string-based state tracking. A proper state machine pattern (using enums or state objects) would be more maintainable and performant.
**Fix:** Replace string states with an enum and use match statements.
**Risk:** Medium. Requires careful refactoring of all state transitions.

### 1.8 `inventory/inventory.gd` - Array-Based Inventory Could Use Dictionary

**File:** `scripts/inventory/inventory.gd`
**Issue:** If items are frequently looked up by ID, a Dictionary would be O(1) instead of O(n) for array iteration.
**Fix:** Maintain both an array (for ordering) and a dictionary (for fast lookup).
**Risk:** Low-Medium. Depends on how inventory is queried.

### 1.9 `player_controller.gd` - Stamina System Magic Numbers

**File:** `scripts/player_controller.gd`
**Issue:** Stamina drain/regen rates are hardcoded (lines 74-78). These should be `@export` variables for easier tuning.
**Fix:** Convert to `@export var` with current values as defaults.
**Risk:** Low.

### 1.10 `player_controller.gd` - Input Handling in `_physics_process`

**File:** `scripts/player_controller.gd`
**Issue:** Input checks like `Input.is_key_pressed(KEY_SPACE)` in `_physics_process` (line 248) can miss inputs if the frame rate is low. Godot's `_input()` is more reliable for action presses.
**Fix:** Move jump and crouch toggles to `_input()` with state flags.
**Risk:** Medium. Jump behavior may feel different; needs testing.

---

## PART 2: GAMEPLAY IMPROVEMENTS

### 2.1 Add Visual Feedback for Stamina

**Current:** Stamina is tracked internally but only emitted via `stamina_changed` signal (line 282). No HUD element displays it.
**Suggestion:** Add a simple stamina bar to the HUD (`horror_hud.gd`). Connect to `stamina_changed` signal.
**Benefit:** Players can see when they're about to be exhausted, adding strategic depth to chase sequences.
**Risk:** Low. Pure UI addition.

### 2.2 Add Audio/Visual Cue When Entity is Nearby

**Current:** The entity can approach silently. Players may not know they're in danger until the jumpscare.
**Suggestion:** Add subtle audio cues (distant breathing, radio static) or visual effects (screen flicker, vignette darkening) when the entity is within a certain range.
**Benefit:** Builds tension and gives players a chance to react.
**Risk:** Low. Can be tuned via export variables.

### 2.3 Flashlight Battery UI Indicator

**Current:** The flashlight has a battery system (`flashlight.gd`) but there's no UI indicator showing remaining battery.
**Suggestion:** Add a battery icon/percentage to the HUD that reflects the flashlight's current battery level.
**Benefit:** Players can manage battery usage strategically.
**Risk:** Low.

### 2.4 Boarding Windows Should Have Audio Feedback

**Current:** `cabin_window.gd` handles boarding up windows but there's no sound effect for hammering/placing planks.
**Suggestion:** Add a hammering/wooden plank sound effect when boarding a window.
**Benefit:** Satisfying feedback for player actions.
**Risk:** Low.

### 2.5 Generator Fuel Level Indicator

**Current:** The generator runs on fuel but there's no way to check remaining fuel level without walking up to it.
**Suggestion:** Add a fuel gauge on the generator model or in the HUD when looking at it.
**Benefit:** Better resource management.
**Risk:** Low.

### 2.6 Entity Path Visualization (Optional/Debug)

**Current:** The entity's patrol path is invisible to the player.
**Suggestion:** (Optional) Add a subtle visual effect (dust motes, disturbed leaves) that hints at the entity's patrol route. Could be toggled for difficulty.
**Benefit:** Helps new players learn avoidance patterns.
**Risk:** Low. Optional feature.

### 2.7 Pause Menu / Save System

**Current:** ESC toggles mouse capture but there's no pause menu or save system.
**Suggestion:** Add a proper pause menu with "Continue", "Save", "Load", "Settings", "Quit" options.
**Benefit:** Essential for a complete game experience.
**Risk:** Medium. Save system requires serialization of game state.

### 2.8 Footstep Audio Surface Detection Enhancement

**Current:** `player_controller.gd` uses groups ("wood", "grass") for footstep sounds. This requires every surface to be manually grouped.
**Suggestion:** Use physics material detection instead, or add a fallback based on the collider's node name/path.
**Benefit:** More robust surface detection without manual setup.
**Risk:** Low.

---

## PART 3: POTENTIAL BUGS & EDGE CASES

### 3.1 Computer UI Instantiated But Never Freed

**File:** `scripts/pc_interactable.gd`
**Issue:** The ComputerUI is instantiated in `_ready()` and added to the root viewport. It's never freed when the PC interactable is removed or the scene changes. This is a memory leak.
**Fix:** Override `_exit_tree()` to queue_free() the computer UI node.
**Risk:** Low.

### 3.2 Multiple PC Interactables = Multiple Computer UIs

**File:** `scripts/pc_interactable.gd`
**Issue:** If there are multiple PC monitors in the scene, each one instantiates its own ComputerUI overlay. They would stack on top of each other.
**Fix:** Make ComputerUI a singleton (autoload) or use a static check to ensure only one instance exists.
**Risk:** Low. Only one PC exists currently, but future-proofing is good.

### 3.3 Player Input Not Disabled During Computer UI

**File:** `scripts/computer_ui.gd`
**Issue:** `open_computer()` disables `set_process_input(false)` and `set_physics_process(false)` on the player. However, `_input()` events (like ESC toggling mouse mode) still fire because `_input()` is called on the player node directly.
**Fix:** Also disable `set_process(false)` or add a check in `_input()` for whether the computer UI is open.
**Risk:** Low. Player could accidentally toggle mouse mode while in the computer UI.

### 3.4 Entity AI - `_target_position` May Be Invalid

**File:** `scripts/entity/entity_ai.gd`
**Issue:** If the navigation mesh doesn't cover the target position, `NavigationAgent3D.target_position` may cause errors or the entity may get stuck.
**Fix:** Check `NavigationServer3D.map_get_closest_point()` validity before setting target.
**Risk:** Low.

### 3.5 `game_time.gd` - Time Scale Not Reset on Scene Reload

**File:** `scripts/game_time.gd`
**Issue:** If the scene is reloaded, `time_scale` may retain its previous value if not properly reset in `_ready()`.
**Fix:** Ensure `time_scale` is initialized to 1.0 in `_ready()`.
**Risk:** Low.

### 3.6 `inventory/inventory.gd` - Adding Items Beyond Capacity

**File:** `scripts/inventory/inventory.gd`
**Issue:** If the inventory has a max size, adding items beyond it should either reject or return the excess.
**Fix:** Add a capacity check in `add_item()`.
**Risk:** Low.

### 3.7 `entity_sensory.gd` - Hearing Noise Through Walls

**File:** `scripts/entity/entity_sensory.gd`
**Issue:** The noise detection system may hear the player through walls if there's no line-of-sight check.
**Fix:** Add a raycast check between noise source and entity before reacting.
**Risk:** Medium. Changes entity behavior; needs testing.

---

## PART 4: ARCHITECTURAL SUGGESTIONS

### 4.1 Event Bus Pattern (Autoload)

**Suggestion:** Create an `EventBus` autoload singleton for global events (nest_data_uploaded, night_started, entity_chase, etc.). This replaces the current pattern of `get_node("/root/NightManager")` and calling methods directly.
**Benefit:** Decouples systems, makes testing easier, and prevents null reference errors.

### 4.2 Resource-Based Item System

**Suggestion:** The current item system uses individual scripts for each item type (battery_pickup.gd, note_pickup.gd, plank_pickup.gd). Consider using Godot's Resource system to define item types as data, with a single pickup script that reads from the resource.
**Benefit:** Adding new items becomes data-driven (no new scripts needed).

### 4.3 State Machine for Player Controller

**Suggestion:** The player controller handles movement, crouching, stamina, flashlight, interaction, and inventory in one file. Consider splitting into a state machine (Normal, Crouching, InMenu, Dead).
**Benefit:** Cleaner code, easier to add new states, prevents state conflicts.

---

## Implementation Priority

### Immediate (Low Risk, High Impact):

1. ✅ Fix computer UI memory leak (3.1)
2. ✅ Fix computer UI multiple instance issue (3.2)
3. ✅ Fix player input during computer UI (3.3)
4. ✅ Refactor duplicate crosshair code (1.1)
5. ✅ Refactor duplicate raycast code (1.2)
6. ✅ Make stamina rates exportable (1.9)
7. ✅ Use groups instead of hardcoded paths (1.3, 1.4, 1.5)

### Short-term (Medium Risk):

8. ✅ Add stamina HUD indicator (2.1)
9. ✅ Add flashlight battery UI indicator (2.3)
10. ✅ Add entity proximity audio cues (2.2)
11. Add window boarding sound effects (2.4)

### Long-term (Higher Risk/Effort):

12. Event Bus autoload (4.1)
13. Resource-based item system (4.2)
14. Player state machine (4.3)
15. Pause menu / save system (2.7)
16. Entity AI state machine refactor (1.7)

---

## PART 5: STANDOFF / CHARGE MECHANIC (NEW)

### Overview

A new gameplay mechanic where the player can stare down the Entity using the flashlight. If the player holds the flashlight on the Entity for too long (~1.5 seconds), the Entity charges at 3x speed. This creates a high-risk, high-reward "standoff" dynamic.

### Files Modified

1. **`scripts/player_controller.gd`** — Added `_process(delta)` with `look_timer`, camera shake, and `_is_flashlight_on_entity()` raycast detection
2. **`scripts/entity/entity_controller.gd`** — Added `STANDOFF` and `CHARGE` states, `on_player_stare()` method
3. **`scripts/entity/entity_ai.gd`** — Added `_charge_state()` for 3x speed sprint behavior
4. **`scripts/ui/standoff_effect.gd`** — New script for HUD overlay with Swedish hallucination text
5. **`scenes/horror_hud.tscn`** — Added StandoffText CanvasLayer with 6 Label nodes

### How It Works

- **Detection:** `player_controller._is_flashlight_on_entity()` fires a raycast from screen center to check if the player is looking at the Entity with the flashlight on
- **Look Timer:** Accumulates while staring (max 2.0s), decays 2x faster when looking away
- **Camera Shake:** Intensity scales with look_timer (0 to ~1 degree shake at 1.5s)
- **STANDOFF (0.1s - 1.5s):** Entity freezes in place, oriented toward the player. HUD shows Swedish hallucination text ("DE LYSSNAR", "INTE SE", "KOMMER", "VÄNTA", "HITTA MIG")
- **CHARGE (≥1.5s):** Entity sprints at 3x speed directly at the player with a screech sound
- **State Recovery:** When player looks away, Entity returns to its previous state (OBSERVE, APPROACH_WINDOW, or PATROL)
