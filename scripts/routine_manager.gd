extends Node

## RoutineManager — Day 1 Onboarding Phase System.
## A global singleton that tracks the player's progress through the
## Day 1 cabin setup using a **gated main-objective** architecture.
##
## MAIN OBJECTIVES (fixed order):
##   0  — Go to the cabin
##   1  — Unlock the front door
##   2  — Log into the computer (first try — fails, auto-advances)
##   3  — Replace the broken fuse in the fuse box
##   4  — Refuel the generator
##   5  — Log into the computer (successfully)
##   6  — Board up the broken window
##   7  — Lock the front door
##   8  — Go to bed
##
## MINOR OBJECTIVES (dynamic — only shown if not already completed):
##   - Find the key to the cabin
##   - Find a fuse in the cabin
##   - Check the fuse box
##   - Find a fuel can to refill the generator
##   - Get some planks to patch the broken window
##
## Mains 3 and 4 can be done in either order. Once BOTH are done,
## the system advances to main 5.

signal routine_step_changed(step: int, objective_text: String)

# ═══════════════════════════════════════════════════════════════════════
# MAIN OBJECTIVE TRACKING
# ═══════════════════════════════════════════════════════════════════════

## Current main objective index (0–8). See docstring above for mapping.
## This is the single source of truth for where the player is in Day 1.
var main_objective: int = 0

# ═══════════════════════════════════════════════════════════════════════
# PHASE 1: ENTRY FLAGS
# ═══════════════════════════════════════════════════════════════════════

var phase1_approached_cabin: bool = false   # Walked near the cabin
var phase1_tried_door: bool = false          # Tried the locked door
var phase1_found_key: bool = false           # Picked up the Cabin Key
var phase1_entered_cabin: bool = false       # Stepped inside the cabin

# ═══════════════════════════════════════════════════════════════════════
# PHASE 2: POWER & LOG FLAGS
# ═══════════════════════════════════════════════════════════════════════

var phase2_computer_tried_no_power: bool = false  # Tried computer without power
var phase2_fuse_box_interacted: bool = false      # First interaction with fuse box
var phase2_fuse_picked_up: bool = false           # Picked up a fuse item
var phase2_fuse_inserted: bool = false            # Fuse inserted into box (switch not thrown yet)
var phase2_fuse_fixed: bool = false               # Fuse inserted + switch thrown
var phase2_fuel_can_picked_up: bool = false       # Picked up a fuel can
var phase2_gen_refilled: bool = false             # Generator refueled
var phase2_computer_used: bool = false            # Logged into computer

# ═══════════════════════════════════════════════════════════════════════
# PHASE 2B: PLANK & WINDOW FLAGS
# ═══════════════════════════════════════════════════════════════════════

var phase2b_plank_picked_up: bool = false    # Picked up a Wooden Plank
var phase2b_window_patched: bool = false     # Barricaded the broken window

# ═══════════════════════════════════════════════════════════════════════
# PHASE 3: LOCKDOWN FLAGS
# ═══════════════════════════════════════════════════════════════════════

var phase3_door_locked: bool = false         # Front door locked
var phase3_bed_used: bool = false            # Went to bed

# ═══════════════════════════════════════════════════════════════════════
# NEST DOCUMENTATION (Day 2)
# ═══════════════════════════════════════════════════════════════════════

var nests_documented: int = 0
var nests_uploaded: bool = false

# ═══════════════════════════════════════════════════════════════════════
# INTERNAL
# ═══════════════════════════════════════════════════════════════════════

var _night_manager: Node = null
var _notebook_ui: Node = null

# ─── TUTORIAL / LEARNED MECHANICS ──────────────────────────────────────
## Tracks which mechanics the player has learned (e.g. "sprint", "interact").
## TutorialManager calls these to check if prompts should still show.
var _learned_mechanics: Dictionary = {}


func _ready() -> void:
	_night_manager = get_node_or_null("/root/NightManager")
	print("[RoutineManager] Initialized. Main-objective gating active. Waiting for Phase 1 triggers.")


## ─── INVENTORY HELPERS ──────────────────────────────────────────────

## Checks whether the player has an item with the given name in their inventory.
func _player_has_item(item_name: String) -> bool:
	var inv = get_node_or_null("/root/Inventory")
	if not inv:
		return false
	for item in inv.items:
		if item and "item_name" in item and item.item_name == item_name:
			return true
	return false


## ─── MAIN OBJECTIVE ADVANCEMENT ─────────────────────────────────────

## Advances main_objective to the given value, but only if it's higher than
## the current one (never moves backwards).
func _advance_main_objective(target: int) -> void:
	if target > main_objective:
		main_objective = target
		print("[RoutineManager] Main objective advanced to %d." % main_objective)

## Called after fuse or generator completion to check if BOTH are done.
## If so, advances from whichever was last (3 or 4) to main 5.
func _check_power_restored() -> void:
	if phase2_fuse_fixed and phase2_gen_refilled:
		print("[RoutineManager] Power restored! Both fuse and generator are done.")
		_advance_main_objective(5)
		_update_hud()


## ─── OBJECTIVE TEXT ─────────────────────────────────────────────────

## Returns the current objective text based on main_objective + flags.
## Called by HorrorHUD and on every state change.
func get_current_objective() -> String:
	# ─── DAY 2+ NEST DOCUMENTATION ──────────────────────────────────
	if nests_uploaded:
		return "Lock the door and go to bed."
	if nests_documented >= 3:
		return "Upload nest data on the computer."
	if nests_documented > 0:
		return "Document the nests."
	
	# ─── DAY 1 ONBOARDING ──────────────────────────────────────────
	match main_objective:
		0:
			return "Go to the cabin."
		
		1:
			# Minor: find key, try door, unlock
			if phase1_entered_cabin:
				_advance_main_objective(2)
				return get_current_objective()
			if _player_has_item("Cabin Key"):
				return "Unlock the front door."
			if phase1_tried_door:
				return "Find the key to the cabin."
			if phase1_approached_cabin:
				return "Go inside the cabin."
			return "Go to the cabin."
		
		2:
			# First try at the computer — just show the prompt
			# Player tries computer → _on_computer_tried_no_power auto-advances
			return "Log into the computer."
		
		3:
			# Minor: find fuse, check fuse box, insert fuse, throw switch
			if phase2_fuse_fixed:
				_advance_main_objective(4)
				_check_power_restored()
				return get_current_objective()
			if phase2_fuse_inserted:
				return "Throw the switch to restore power."
			if _player_has_item("Fuse"):
				if phase2_fuse_box_interacted:
					return "Replace the broken fuse with the new fuse."
				else:
					return "Check the fuse box. You have a new fuse."
			if phase2_fuse_box_interacted:
				return "Find a fuse in the cabin."
			if phase2_computer_tried_no_power:
				return "Check the fuse box. It's always the god damn fuse box."
			return "Check the fuse box. It's always the god damn fuse box."
		
		4:
			# Minor: find fuel can, refill generator
			if phase2_gen_refilled:
				_check_power_restored()
				return get_current_objective()
			if _player_has_item("Fuel Can"):
				return "Refill the generator."
			return "Find a fuel can to refill the generator."
		
		5:
			# Second try at the computer — power is restored
			if phase2_computer_used:
				_advance_main_objective(6)
				return get_current_objective()
			return "Log into the computer."
		
		6:
			# Minor: find planks, patch window
			if phase2b_window_patched:
				_advance_main_objective(7)
				return get_current_objective()
			if _player_has_item("Wooden Plank"):
				return "Patch the window as well as you can."
			if phase2b_plank_picked_up:
				return "Patch the window as well as you can."
			return "Get some planks to patch the broken window."
		
		7:
			# Lock the door
			if phase3_door_locked:
				_advance_main_objective(8)
				return get_current_objective()
			return "Lock the front door."
		
		8:
			# Go to bed
			if phase3_bed_used:
				return "Day 1 complete. Rest well."
			return "Go to bed."
	
	return "Go to the cabin."


## Emits the current objective to the HUD.
func _update_hud() -> void:
	var text = get_current_objective()
	
	# Compute a human-readable step number for the HUD signal.
	# This is purely cosmetic — the HUD uses it for debug display.
	var step: int = 0
	
	# Day 2 steps
	if nests_uploaded:
		step = 19
	elif nests_documented >= 3:
		step = 18
	elif nests_documented > 0:
		step = 17
	else:
		# Day 1 steps mapped from main_objective + completion depth
		match main_objective:
			0: step = 0
			1:
				if _player_has_item("Cabin Key"): step = 3
				elif phase1_tried_door: step = 2
				else: step = 1
			2: step = 4
			3:
				if phase2_fuse_fixed: step = 7
				elif phase2_fuse_inserted: step = 7
				elif _player_has_item("Fuse"): step = 7
				elif phase2_fuse_box_interacted: step = 6
				else: step = 5
			4:
				if phase2_gen_refilled: step = 10
				elif _player_has_item("Fuel Can"): step = 9
				else: step = 8
			5: step = 11
			6:
				if _player_has_item("Wooden Plank") or phase2b_plank_picked_up: step = 13
				else: step = 12
			7: step = 14
			8: step = 15
	
	routine_step_changed.emit(step, text)
	print("[RoutineManager] HUD updated: Step %d — '%s'" % [step, text])


# ═══════════════════════════════════════════════════════════════════════
# PHASE 1 TRIGGERS
# ═══════════════════════════════════════════════════════════════════════

func on_cabin_approached() -> void:
	if phase1_approached_cabin:
		return
	phase1_approached_cabin = true
	_advance_main_objective(1)
	print("[RoutineManager] Phase 1: Player approached the cabin.")
	if _night_manager and _night_manager.has_method("unpause_time"):
		_night_manager.unpause_time()
	_update_hud()
	_trigger_interact_tutorial()


func on_door_tried_locked() -> void:
	if phase1_tried_door:
		return
	phase1_tried_door = true
	print("[RoutineManager] Phase 1: Player tried the locked door.")
	_update_hud()


func on_key_picked_up() -> void:
	if phase1_found_key:
		return
	phase1_found_key = true
	print("[RoutineManager] Phase 1: Player found the Cabin Key.")
	_update_hud()


func _trigger_notebook_tutorial() -> void:
	var tm := get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("trigger"):
		tm.trigger("notebook")


func _trigger_interact_tutorial() -> void:
	var tm := get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("trigger"):
		tm.trigger("interact")


func on_door_unlocked() -> void:
	if phase1_entered_cabin:
		return
	phase1_entered_cabin = true
	_advance_main_objective(2)
	print("[RoutineManager] Phase 1 COMPLETE! Player unlocked and entered the cabin.")
	_update_hud()
	_trigger_notebook_tutorial()


func on_player_entered_cabin() -> void:
	if phase1_entered_cabin:
		return
	phase1_entered_cabin = true
	_advance_main_objective(2)
	print("[RoutineManager] Phase 1 COMPLETE! Player entered the cabin (detected by room check).")
	_update_hud()
	_trigger_notebook_tutorial()


# ═══════════════════════════════════════════════════════════════════════
# PHASE 2 TRIGGERS
# ═══════════════════════════════════════════════════════════════════════

func on_fuse_box_interacted() -> void:
	if phase2_fuse_box_interacted:
		return
	phase2_fuse_box_interacted = true
	print("[RoutineManager] Phase 2: Player interacted with fuse box.")
	_update_hud()


func on_fuse_picked_up() -> void:
	if phase2_fuse_picked_up:
		return
	phase2_fuse_picked_up = true
	print("[RoutineManager] Phase 2: Player picked up a fuse.")
	_update_hud()


func on_fuse_inserted() -> void:
	if phase2_fuse_inserted:
		return
	phase2_fuse_inserted = true
	print("[RoutineManager] Phase 2: Fuse inserted into fuse box.")
	_update_hud()


func on_fuse_fixed() -> void:
	if phase2_fuse_fixed:
		return
	phase2_fuse_fixed = true
	print("[RoutineManager] Phase 2: Fuse box fixed.")
	_update_hud()
	_check_power_restored()


func on_fuel_can_picked_up() -> void:
	if phase2_fuel_can_picked_up:
		return
	phase2_fuel_can_picked_up = true
	print("[RoutineManager] Phase 2: Player picked up a fuel can.")
	_update_hud()


func on_generator_refilled() -> void:
	if phase2_gen_refilled:
		return
	phase2_gen_refilled = true
	print("[RoutineManager] Phase 2: Generator refilled.")
	_update_hud()
	_check_power_restored()


func on_computer_tried_no_power() -> void:
	if phase2_computer_tried_no_power:
		return
	phase2_computer_tried_no_power = true
	# Auto-advance to main 3 (fuse objective) since the computer is dead
	_advance_main_objective(3)
	print("[RoutineManager] Phase 2: Player tried computer without power. Advancing to fuse objective.")
	_update_hud()


func on_computer_used() -> void:
	if phase2_computer_used:
		return
	phase2_computer_used = true
	_advance_main_objective(6)
	print("[RoutineManager] Phase 2 COMPLETE! Player logged into the computer.")
	_update_hud()


# ═══════════════════════════════════════════════════════════════════════
# PHASE 2B TRIGGERS (Plank & Window)
# ═══════════════════════════════════════════════════════════════════════

func on_plank_picked_up() -> void:
	if phase2b_plank_picked_up:
		return
	phase2b_plank_picked_up = true
	print("[RoutineManager] Phase 2B: Player picked up a Wooden Plank.")
	_update_hud()


func on_window_patched() -> void:
	if phase2b_window_patched:
		return
	phase2b_window_patched = true
	_advance_main_objective(7)
	print("[RoutineManager] Phase 2B COMPLETE! Player patched the broken window.")
	_update_hud()


# ═══════════════════════════════════════════════════════════════════════
# PHASE 3 TRIGGERS
# ═══════════════════════════════════════════════════════════════════════

func on_door_locked() -> void:
	if phase3_door_locked:
		return
	phase3_door_locked = true
	_advance_main_objective(8)
	print("[RoutineManager] Phase 3: Front door locked.")
	_update_hud()


func on_bed_interacted() -> bool:
	# Can only go to bed if window is patched
	if not phase2b_window_patched:
		print("[RoutineManager] Phase 3: Player tried bed but window is not patched.")
		return false
	
	# Door lock check — must be locked
	if not phase3_door_locked:
		var door_nodes = get_tree().get_nodes_in_group("Door")
		var door_is_locked = false
		for d in door_nodes:
			if "is_locked" in d and d.is_locked:
				door_is_locked = true
				phase3_door_locked = true
				break
		if not door_is_locked:
			print("[RoutineManager] Phase 3: Player tried bed but front door is NOT locked.")
			return false
	
	phase3_bed_used = true
	print("[RoutineManager] Phase 3 COMPLETE! Player went to bed. Transitioning to Day 2.")
	_update_hud()
	return true


# ═══════════════════════════════════════════════════════════════════════
# NEST DOCUMENTATION (Day 2)
# ═══════════════════════════════════════════════════════════════════════

func document_nest(nest_id: String) -> void:
	nests_documented += 1
	print("[RoutineManager] Nest '%s' documented! (%d/3)" % [nest_id, nests_documented])
	if nests_documented >= 3:
		print("[RoutineManager] All 3 nests documented! Player should upload data on the computer.")
		_update_hud()


func on_nest_data_uploaded() -> void:
	if nests_uploaded:
		return
	nests_uploaded = true
	print("[RoutineManager] Nest data uploaded on computer! Player should go to bed.")
	_update_hud()


# ═══════════════════════════════════════════════════════════════════════
# UTILITY
# ═══════════════════════════════════════════════════════════════════════

func get_current_day_string() -> String:
	var nm = get_node_or_null("/root/NightManager")
	if not nm:
		return "Day ?"
	var night: int = nm.current_night
	if night <= 0:
		return "Day 1"
	if nm.is_night_active:
		return "Night " + str(night)
	return "Day " + str(night)


## Deprecated compatibility stub for door.gd and totem_anchor.gd.
## These scripts call advance_step() but the new main-objective system
## handles advancement through specific trigger methods (on_door_locked, etc.).
## This stub prevents runtime errors without changing behavior.
func advance_step() -> void:
	print("[RoutineManager] advance_step() called (deprecated). Using main-objective system instead.")
	_update_hud()


## Marks a mechanic as learned. Once learned, the corresponding tutorial
## prompt is permanently hidden for the rest of this session/save.
func mark_mechanic_learned(mechanic_id: String) -> void:
	_learned_mechanics[mechanic_id] = true


## Returns true if the mechanic has already been learned.
func is_mechanic_learned(mechanic_id: String) -> bool:
	return _learned_mechanics.get(mechanic_id, false)


func reset_all_phases() -> void:
	main_objective = 0
	
	phase1_approached_cabin = false
	phase1_tried_door = false
	phase1_found_key = false
	phase1_entered_cabin = false
	
	phase2_computer_tried_no_power = false
	phase2_fuse_box_interacted = false
	phase2_fuse_picked_up = false
	phase2_fuse_inserted = false
	phase2_fuse_fixed = false
	phase2_fuel_can_picked_up = false
	phase2_gen_refilled = false
	phase2_computer_used = false
	
	phase2b_plank_picked_up = false
	phase2b_window_patched = false
	
	phase3_door_locked = false
	phase3_bed_used = false
	
	print("[RoutineManager] All phases reset.")
	_update_hud()