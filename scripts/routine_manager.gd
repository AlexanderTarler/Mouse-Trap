extends Node

## RoutineManager — Day 1 Onboarding Phase System.
## A global singleton that tracks the player's progress through the
## Day 1 cabin setup using a 3-Phase boolean system.
##
## Phase 1: Entry — "Get inside the cabin."
##   - Approach cabin → Try locked door → Find key → Unlock & enter
##
## Phase 2: Power & Log — "Restore power and log into the terminal."
##   - Fix fuse box + Refill generator (any order) → Use computer
##
## Phase 3: Lockdown — "Lock the front door and go to bed."
##   - Lock door → Go to bed → Transition to Day 2

signal routine_step_changed(step: int, objective_text: String)

# ─── PHASE 1: ENTRY ─────────────────────────────────────────────────────
var phase1_approached_cabin: bool = false   # Walked near the cabin
var phase1_tried_door: bool = false          # Tried the locked door
var phase1_found_key: bool = false           # Picked up the Cabin Key
var phase1_entered_cabin: bool = false       # Stepped inside the cabin
var phase1_complete: bool = false            # All Phase 1 done

# ─── PHASE 2: POWER & LOG ───────────────────────────────────────────────
var phase2_computer_tried_no_power: bool = false  # Tried computer without power
var phase2_fuse_box_interacted: bool = false      # First interaction with fuse box
var phase2_fuse_picked_up: bool = false           # Picked up a fuse item
var phase2_fuse_inserted: bool = false            # Fuse inserted into box (but switch not thrown yet)
var phase2_fuse_fixed: bool = false               # Fuse inserted + switch thrown
var phase2_fuel_can_picked_up: bool = false       # Picked up a fuel can
var phase2_gen_refilled: bool = false             # Generator refueled
var phase2_computer_used: bool = false            # Logged into computer
var phase2_complete: bool = false                 # All Phase 2 done

# ─── PHASE 2B: PLANK & WINDOW ───────────────────────────────────────────
# After using the computer, the player must get planks and patch the
# broken tutorial window before they can lock the door and go to bed.
var phase2b_plank_picked_up: bool = false    # Picked up a Wooden Plank
var phase2b_window_patched: bool = false     # Barricaded the broken window
var phase2b_complete: bool = false           # All Phase 2B done

# ─── PHASE 3: LOCKDOWN ──────────────────────────────────────────────────
var phase3_door_locked: bool = false         # Front door locked
var phase3_bed_used: bool = false            # Went to bed
var phase3_complete: bool = false            # All Phase 3 done (→ Day 2)

# ─── NEST DOCUMENTATION (Day 2) ─────────────────────────────────────────
## Number of nests the player has documented via photograph or direct interact.
## Incremented by document_nest(). Used by hasselmus_nest.gd to display
## progress (e.g., "Nest documented! (1/3)").
var nests_documented: int = 0

## Reference to NightManager for setting the completion flag.
var _night_manager: Node = null


func _ready() -> void:
	_night_manager = get_node_or_null("/root/NightManager")
	print("[RoutineManager] Initialized. Waiting for Phase 1 triggers.")


## Returns the current objective text based on the Phase state.
## Called by HorrorHUD to initialize the objective label on startup.
func get_current_objective() -> String:
	# Phase 3
	if phase3_complete:
		return "Day 1 complete. Rest well."
	if phase3_door_locked:
		return "Go to bed."
	if phase3_bed_used:
		return "Day 1 complete. Rest well."
	
	# Phase 2B — Plank & Window (after computer used)
	if phase2b_complete:
		return "Lock the front door and go to bed."
	if phase2b_window_patched:
		return "Lock the front door and go to bed."
	if phase2b_plank_picked_up:
		return "Patch the window as well as you can."
	
	# Phase 2 — Granular steps
	if phase2_complete:
		return "Get some planks."
	if phase2_computer_used:
		return "Get some planks."
	if phase2_fuse_fixed and phase2_gen_refilled:
		return "Log into the computer, second try."
	if phase2_gen_refilled:
		return "Log into the computer, second try."
	if phase2_fuse_fixed:
		return "I need to refill the generator, I think."
	if phase2_fuel_can_picked_up:
		return "Refill the generator."
	if phase2_fuse_inserted:
		return "Find a fuel can."
	if phase2_fuse_picked_up:
		return "Replace the broken fuse in the fuse box."
	if phase2_fuse_box_interacted:
		return "Find a fuse inside the cabin."
	if phase2_computer_tried_no_power:
		return "Check the fuse box. It's always the god damn fuse box."
	
	# Phase 1
	if phase1_complete:
		return "Log into the computer."
	if phase1_entered_cabin:
		return "Log into the computer."
	if phase1_found_key:
		return "Unlock the front door."
	if phase1_tried_door:
		return "The door is locked. I need to find a key."
	if phase1_approached_cabin:
		return "Go inside the cabin."
	
	# Default start
	return "Go to the cabin."


## Emits the current objective to the HUD.
func _update_hud() -> void:
	var text = get_current_objective()
	# Determine step number for the signal
	var step = 0
	if phase3_complete:
		step = 16
	elif phase3_door_locked:
		step = 15
	elif phase2b_complete:
		step = 14
	elif phase2b_window_patched:
		step = 14
	elif phase2b_plank_picked_up:
		step = 13
	elif phase2_complete:
		step = 12
	elif phase2_computer_used:
		step = 12
	elif phase2_fuse_fixed and phase2_gen_refilled:
		step = 11
	elif phase2_gen_refilled:
		step = 11
	elif phase2_fuse_fixed:
		step = 10
	elif phase2_fuel_can_picked_up:
		step = 9
	elif phase2_fuse_inserted:
		step = 8
	elif phase2_fuse_picked_up:
		step = 7
	elif phase2_fuse_box_interacted:
		step = 6
	elif phase2_computer_tried_no_power:
		step = 5
	elif phase1_complete:
		step = 4
	elif phase1_entered_cabin:
		step = 4
	elif phase1_found_key:
		step = 3
	elif phase1_tried_door:
		step = 2
	elif phase1_approached_cabin:
		step = 1
	
	routine_step_changed.emit(step, text)
	print("[RoutineManager] HUD updated: Step %d — '%s'" % [step, text])


# ═══════════════════════════════════════════════════════════════════════
# PHASE 1 TRIGGERS
# ═══════════════════════════════════════════════════════════════════════

## Called by CabinApproachTrigger when the player walks near the cabin.
## Unpauses time — the clock starts running from 4 minutes into the day
## (1 minute until night).
func on_cabin_approached() -> void:
	if phase1_approached_cabin:
		return
	phase1_approached_cabin = true
	print("[RoutineManager] Phase 1: Player approached the cabin.")
	
	# Unpause time — the clock starts running from 4 minutes into the day
	if _night_manager and _night_manager.has_method("unpause_time"):
		_night_manager.unpause_time()
	
	_update_hud()


## Called by door.gd when the player tries the locked front door.
func on_door_tried_locked() -> void:
	if phase1_tried_door:
		return
	phase1_tried_door = true
	print("[RoutineManager] Phase 1: Player tried the locked door.")
	_update_hud()


## Called by Inventory when the player picks up the Cabin Key.
func on_key_picked_up() -> void:
	if phase1_found_key:
		return
	phase1_found_key = true
	print("[RoutineManager] Phase 1: Player found the Cabin Key.")
	_update_hud()


## Called by door.gd when the player unlocks the front door with the key.
func on_door_unlocked() -> void:
	if phase1_entered_cabin:
		return
	# Mark both entered_cabin and complete Phase 1
	phase1_entered_cabin = true
	phase1_complete = true
	print("[RoutineManager] Phase 1 COMPLETE! Player unlocked and entered the cabin.")
	_update_hud()


## Called by player_controller.gd when the player is detected inside the cabin.
## This is a fallback in case the player enters through a different path.
func on_player_entered_cabin() -> void:
	if phase1_entered_cabin:
		return
	phase1_entered_cabin = true
	phase1_complete = true
	print("[RoutineManager] Phase 1 COMPLETE! Player entered the cabin (detected by room check).")
	_update_hud()


# ═══════════════════════════════════════════════════════════════════════
# PHASE 2 TRIGGERS
# ═══════════════════════════════════════════════════════════════════════

## Called by FuseBox when the player first interacts with it (any state).
## Sets the flag so the HUD shows "Find a fuse inside the cabin."
func on_fuse_box_interacted() -> void:
	if phase2_fuse_box_interacted:
		return
	phase2_fuse_box_interacted = true
	print("[RoutineManager] Phase 2: Player interacted with fuse box.")
	_update_hud()


## Called by Inventory when the player picks up a Fuse item.
func on_fuse_picked_up() -> void:
	if phase2_fuse_picked_up:
		return
	phase2_fuse_picked_up = true
	print("[RoutineManager] Phase 2: Player picked up a fuse.")
	_update_hud()


## Called by FuseBox when the player inserts a fuse into the box (HAS_FUSE state).
func on_fuse_inserted() -> void:
	if phase2_fuse_inserted:
		return
	phase2_fuse_inserted = true
	print("[RoutineManager] Phase 2: Fuse inserted into fuse box.")
	_update_hud()


## Called by FuseBox when the player inserts a fuse and throws the switch.
func on_fuse_fixed() -> void:
	if phase2_fuse_fixed:
		return
	phase2_fuse_fixed = true
	print("[RoutineManager] Phase 2: Fuse box fixed.")
	_check_phase2_complete()


## Called by Inventory when the player picks up a Fuel Can.
func on_fuel_can_picked_up() -> void:
	if phase2_fuel_can_picked_up:
		return
	phase2_fuel_can_picked_up = true
	print("[RoutineManager] Phase 2: Player picked up a fuel can.")
	_update_hud()


## Called by GeneratorInteraction when the player refills the generator.
func on_generator_refilled() -> void:
	if phase2_gen_refilled:
		return
	phase2_gen_refilled = true
	print("[RoutineManager] Phase 2: Generator refilled.")
	_check_phase2_complete()


## Checks if both Phase 2 tasks are done, and if so, updates the HUD.
func _check_phase2_complete() -> void:
	if phase2_fuse_fixed and phase2_gen_refilled:
		print("[RoutineManager] Phase 2: Both tasks done! Player can now use the computer.")
		_update_hud()


## Called by PCInteractable when the player tries the computer without power.
## Sets the flag so the HUD shows "Check the fuse box. It's always the god damn fuse box."
func on_computer_tried_no_power() -> void:
	if phase2_computer_tried_no_power:
		return
	phase2_computer_tried_no_power = true
	print("[RoutineManager] Phase 2: Player tried computer without power.")
	_update_hud()


## Called by PCInteractable when the player successfully uses the computer.
func on_computer_used() -> void:
	if phase2_computer_used:
		return
	phase2_computer_used = true
	phase2_complete = true
	print("[RoutineManager] Phase 2 COMPLETE! Player logged into the computer.")
	_update_hud()


# ═══════════════════════════════════════════════════════════════════════
# PHASE 2B TRIGGERS (Plank & Window)
# ═══════════════════════════════════════════════════════════════════════

## Called by Inventory when the player picks up a Wooden Plank.
## Sets the flag so the HUD shows "Patch the window as well as you can."
func on_plank_picked_up() -> void:
	if phase2b_plank_picked_up:
		return
	phase2b_plank_picked_up = true
	print("[RoutineManager] Phase 2B: Player picked up a Wooden Plank.")
	_update_hud()


## Called by CabinWindow when the player barricades the broken tutorial window.
## Sets the flag so the HUD shows "Lock the front door and go to bed."
func on_window_patched() -> void:
	if phase2b_window_patched:
		return
	phase2b_window_patched = true
	phase2b_complete = true
	print("[RoutineManager] Phase 2B COMPLETE! Player patched the broken window.")
	_update_hud()


# ═══════════════════════════════════════════════════════════════════════
# PHASE 3 TRIGGERS
# ═══════════════════════════════════════════════════════════════════════

## Called by door.gd when the player locks the front door.
func on_door_locked() -> void:
	if phase3_door_locked:
		return
	phase3_door_locked = true
	print("[RoutineManager] Phase 3: Front door locked.")
	_update_hud()


## Called by bed_interactable.gd when the player interacts with the bed.
## Returns true if the bed interaction should proceed (Phase 2 complete).
func on_bed_interacted() -> bool:
	# Can only go to bed if Phase 2 is complete (power restored, computer used)
	if not phase2_complete:
		print("[RoutineManager] Phase 3: Player tried bed but Phase 2 is not complete.")
		return false
	
	phase3_bed_used = true
	phase3_complete = true
	print("[RoutineManager] Phase 3 COMPLETE! Player went to bed. Transitioning to Day 2.")
	_update_hud()
	return true


## Called by hasselmus_nest.gd when the player documents a nest.
## Increments the nests_documented counter so the HUD can display progress.
func document_nest(nest_id: String) -> void:
	nests_documented += 1
	print("[RoutineManager] Nest '%s' documented! (%d/3)" % [nest_id, nests_documented])


## Resets all phase state (for new game / restart).
func reset_all_phases() -> void:
	phase1_approached_cabin = false
	phase1_tried_door = false
	phase1_found_key = false
	phase1_entered_cabin = false
	phase1_complete = false
	
	phase2_computer_tried_no_power = false
	phase2_fuse_box_interacted = false
	phase2_fuse_picked_up = false
	phase2_fuse_inserted = false
	phase2_fuse_fixed = false
	phase2_fuel_can_picked_up = false
	phase2_gen_refilled = false
	phase2_computer_used = false
	phase2_complete = false
	
	phase2b_plank_picked_up = false
	phase2b_window_patched = false
	phase2b_complete = false
	
	phase3_door_locked = false
	phase3_bed_used = false
	phase3_complete = false
	
	print("[RoutineManager] All phases reset.")
	_update_hud()
