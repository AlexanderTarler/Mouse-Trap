extends StaticBody3D
class_name FuseBox

## FuseBox — Power restoration puzzle.
## Three-state interaction: BROKEN (needs fuse) → HAS_FUSE (throw switch) → POWER_ON (done).
## Communicates with the NightManager autoload to restore generator power.
##
## The player must find a "Fuse" item in their inventory and insert it,
## then throw the switch to restore power to the cabin.

signal fuse_inserted
signal power_restored

enum BoxState { BROKEN, HAS_FUSE, POWER_ON }

## The item_name to search for in the player's inventory.
@export var required_item_name: String = "Fuse"

## Whether the fuse box should start the game in a BROKEN state.
## When true, the generator is OFF and the player must find a Fuse item
## and insert it before they can throw the switch to restore power.
## When false (default), the generator starts ON for development convenience.
## Toggle this in the inspector to control the initial state.
@export var start_broken: bool = false

var current_state: BoxState = BoxState.POWER_ON

# ─── HOLD-TO-INTERACT: Fuse Repair ────────────────────────────────────────
## Whether the player is currently holding E to repair the fuse box.
## Set by start_hold_interact(), cleared by stop_hold_interact().
var _is_repairing: bool = false

## Accumulated hold progress (seconds) for inserting a fuse.
## Counts up from 0.0 to REPAIR_TIME (3.0s), then the fuse is inserted.
## Saved on release so the player can continue from where they left off.
var _repair_progress: float = 0.0

## How long the player must hold E to insert a fuse.
const REPAIR_TIME: float = 3.0

## Internal health for the brute-force sabotage (frustration-based FUSE_SABOTAGE).
## The Entity strikes the fuse box repeatedly until health reaches 0.
## The door-prerequisite SABOTAGE_FUSE state calls break_fuse() directly.
var _health: int = 3

# ─── SOUND EFFECTS (Assign in Inspector) ────────────────────────────────
## Sound played when the player inspects the broken fuse box (no fuse inserted).
@export var check_fusebox_sfx: AudioStream = null

## Sound played when the fuse box is successfully repaired (fuse inserted + power restored).
@export var repair_fusebox_sfx: AudioStream = null


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("xray_fuse_box")
	
	# Ensure this StaticBody3D is on collision layer 1 so the
	# InteractionManager's center-screen raycast can detect it.
	collision_layer = 1
	
	# ─── START BROKEN TOGGLE ───────────────────────────────────────
	# If start_broken is true, initialize the fuse box in BROKEN state
	# with the generator OFF. The player must find a Fuse item and insert
	# it, then throw the switch to restore power.
	# If start_broken is false (default), the generator starts ON for
	# development convenience.
	if start_broken:
		current_state = BoxState.BROKEN
		_set_generator_state(false)
		print("[FuseBox] Starting BROKEN (start_broken=true). Generator is OFF.")
	else:
		current_state = BoxState.POWER_ON
		_set_generator_state(true)
		print("[FuseBox] Starting POWER_ON (start_broken=false). Generator is ON.")
	
	print("[FuseBox] _ready() complete. State: ", BoxState.keys()[current_state])


# ─── HOLD-TO-INTERACT: Fuse Repair ────────────────────────────────────────
## Called by PhysicalGrab when the player presses E while looking at the fuse box.
## Starts accumulating hold progress for inserting a fuse.
func start_hold_interact() -> void:
	if current_state != BoxState.BROKEN:
		return
	# Check if player has a fuse
	if not _find_fuse_in_inventory():
		return
	_is_repairing = true
	print("[FuseBox] Start repairing at progress %.1f/%.1fs" % [_repair_progress, REPAIR_TIME])


## Called by PhysicalGrab when the player releases E.
## Saves progress so the player can continue from where they left off.
func stop_hold_interact() -> void:
	if not _is_repairing:
		return
	_is_repairing = false
	print("[FuseBox] Released at progress %.1f/%.1fs" % [_repair_progress, REPAIR_TIME])


## Called by PhysicalGrab every frame while E is held.
## Accumulates hold progress for inserting the fuse.
func _process_hold_interact(delta: float) -> void:
	if not _is_repairing:
		return
	
	_repair_progress += delta
	
	if _repair_progress >= REPAIR_TIME:
		_repair_progress = 0.0
		_is_repairing = false
		
		# Insert the fuse
		attempt_fuse_insertion()


## Override interact to allow quick-tap fuse insertion (backwards compatible).
## The hold-to-interact system uses start/stop/_process instead, but quick-tap
## still works via _fire_interact() for players who prefer it.
func interact() -> void:
	print("[FuseBox] interact() called! Current state: ", BoxState.keys()[current_state])
	
	# ─── DAY 1 ONBOARDING: PHASE 2 — FUSE BOX INTERACTED ────────────────
	# Notify RoutineManager that the player first interacted with the fuse box.
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("on_fuse_box_interacted"):
		rm.on_fuse_box_interacted()
	
	match current_state:
		BoxState.BROKEN:
			# Play broken fuse box inspection sound
			_play_sfx(check_fusebox_sfx)
			attempt_fuse_insertion()
		BoxState.POWER_ON:
			print("[FuseBox] The power is already humming softly.")


## Searches the player's Inventory autoload for a Fuse item.
## If found, removes it and immediately throws the switch (auto-restores
## power). The intermediate HAS_FUSE state has been removed — the player
## no longer needs to "pull the lever" after inserting the fuse.
func attempt_fuse_insertion() -> void:
	var fuse_item = _find_fuse_in_inventory()
	if fuse_item:
		Inventory.remove_item(fuse_item)
		
		# Notify RoutineManager that the fuse has been inserted.
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_fuse_inserted"):
			rm.on_fuse_inserted()
		
		# Immediately throw the switch — no separate lever-pull step.
		_throw_switch()
	else:
		print("[FuseBox] The fuse block is empty. The main circuit breaker is completely dead.")


## Throws the switch immediately after fuse insertion — restores generator
## power via NightManager. No longer called from interact() as a separate
## step; it fires automatically when the fuse is inserted.
##
## ORDER OF OPERATIONS FIX (Generator restart bug):
## The old implementation set `current_state = POWER_ON` BEFORE starting
## the generator. When the generator had 0 fuel, _set_generator_state()
## silently returned, but is_powered() then reported true anyway — so the
## GeneratorSwitch's fuel check ("The generator is out of fuel...") blocked
## the player FOREVER: fuse box said "repaired" yet the generator could
## never start. The fuse box now only enters POWER_ON after the generator
## actually starts successfully.
func _throw_switch() -> void:
	# ─── FIX: FUSE INSERTION REPAIRS THE BOX — GENERATOR START IS SEPARATE ──
	# Previously this auto-started the generator via _set_generator_state(true).
	# If the generator had no fuel, that returned false and the fuse box STAYED
	# BROKEN while the fuse was consumed — the player was then hard-locked:
	# GeneratorSwitch's fuse check ("The fuse box needs to be repaired first...")
	# never passed, so pressing E on the switch appeared to do nothing.
	#
	# The repair is now DECOUPLED from generator start:
	#   1. Insert fuse  → fuse box POWER_ON (repaired), generator stays OFF
	#   2. Refuel       → if needed
	#   3. Toggle GeneratorSwitch → generator ON (gated by fuel in generator.gd)
	# This matches the intended design: after sabotage the generator is OFF,
	# and the player restarts it via the switch.
	current_state = BoxState.POWER_ON
	power_restored.emit()
	
	# ─── REPAIR SOUND ──────────────────────────────────────────────
	_play_sfx(repair_fusebox_sfx)
	
	_show_hud_msg("Fuse repaired! Turn on the generator to restore power.")
	print("[FuseBox] Fuse inserted! Fuse box repaired (POWER_ON). Start the generator at the switch.")
	
	# ─── DAY 1 ONBOARDING: PHASE 2 — FUSE FIXED ────────────────────────
	# Notify RoutineManager that the fuse box has been fixed.
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("on_fuse_fixed"):
		rm.on_fuse_fixed()



## Sets the NightManager generator state and emits the state change signal
## so all CabinLight nodes update their visibility automatically.
## Returns true if the state was applied successfully, false if the
## request was blocked (e.g., no fuel).
func _set_generator_state(enabled: bool) -> bool:
	var nm = get_node_or_null("/root/NightManager")
	if not nm:
		print("[FuseBox] Warning: NightManager not found at /root/NightManager")
		return false
	
	# ─── FUEL GUARD (Bug 3 Fix) ──────────────────────────────────────────
	# Power can ONLY be restored if BOTH conditions are met:
	#   A. The fuse box is repaired (is_powered() == true when not BROKEN)
	#   B. The generator has fuel (generator_fuel > 0)
	#
	# If the generator has 0 fuel, setting is_generator_on=true is pointless
	# — the power still won't work because the generator can't run without fuel.
	# This fixes the bug where inserting the fuse restores power even when
	# the generator has 0.0% fuel.
	#
	# RETURN FALSE (new): The caller (e.g. _throw_switch) uses the return
	# value to decide whether the fuse box repair actually succeeded. If
	# this returns false, the FuseBox stays BROKEN and the player is told
	# to refuel, instead of the FuseBox lying that it is repaired.
	if enabled and nm.generator_fuel <= 0.0:
		print("[FuseBox] Cannot enable generator — fuel is at 0.0. Refuel the generator first.")
		return false
	
	nm.is_generator_on = enabled
	nm.generator_state_changed.emit(enabled)
	if enabled:
		nm.recalculate_fuel_drain()
	print("[FuseBox] Generator state set to: ", enabled)
	return true

## Shows a transient HUD message via the hud group, or prints if unavailable.
func _show_hud_msg(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(msg)
	else:
		print("[FuseBox HUD]: ", msg)


## Iterates the Inventory autoload's items array looking for an item
## whose item_name matches required_item_name.
## Returns the ItemData resource if found, or null if not.
func _find_fuse_in_inventory():
	print("[FuseBox] Searching inventory for '", required_item_name, "'. Inventory has ", Inventory.items.size(), " items:")
	for i in range(Inventory.items.size()):
		var item = Inventory.items[i]
		if item != null:
			print("  [", i, "] item_name='", item.item_name, "' type=", item.item_type if "item_type" in item else "?")
		else:
			print("  [", i, "] null")
	for item in Inventory.items:
		if item != null and "item_name" in item and item.item_name == required_item_name:
			print("[FuseBox] Found matching item: ", item.item_name)
			return item
	print("[FuseBox] No item named '", required_item_name, "' found in inventory.")
	return null


## Plays a sound effect via a transient AudioStreamPlayer3D attached to self.
## The player is auto-freed when the sound finishes.
## Accepts an AudioStream resource (assignable in the Inspector).
func _play_sfx(stream: AudioStream) -> void:
	if not stream:
		return
	var player := AudioStreamPlayer.new()
	player.bus = "SFX"
	player.stream = stream
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


## Returns whether the fuse box is currently powered (generator ON).
## Used by the Entity Director to check if the porch light is active,
## which prevents door approach until the fuse box is sabotaged.
##
## ─── FIX: Any non-BROKEN state counts as "power-capable" ─────────
## The fuse box is repaired as long as it isn't BROKEN (sabotaged).
## Whether the generator actually RUNS is governed by fuel + the
## GeneratorSwitch toggle in generator.gd. This lets the player repair
## the box even with an empty tank, then refuel and start the generator
## from the switch (previously the empty-tank case deadlocked the box
## in BROKEN with the fuse consumed).
func is_powered() -> bool:
	return current_state != BoxState.BROKEN


## Breaks the fuse box — sets state to BROKEN and shuts down the generator.
## This kills ALL cabin lights including the porch light.
## Called by the Entity's SABOTAGE_FUSE state (door-prerequisite sabotage).
## Also called by take_damage() when internal health reaches 0.
func break_fuse() -> void:
	if current_state == BoxState.BROKEN:
		return  # Already broken — no-op
	
	current_state = BoxState.BROKEN
	_health = 0
	_set_generator_state(false)
	
	# ─── SABOTAGE SOUND ───────────────────────────────────────────
	# The Entity's sabotage sound uses the repair sound (electric spark).
	_play_sfx(repair_fusebox_sfx)
	
	print("[FuseBox] BREAK! The fuse box is shattered. Generator is OFF. All lights die.")


## Applies damage to the fuse box. When internal health reaches 0,
## calls break_fuse() to shut down the generator.
## Used by the frustration-based FUSE_SABOTAGE state (brute-force attack).
func take_damage(amount: int) -> void:
	if current_state == BoxState.BROKEN:
		return  # Already broken — no-op
	
	_health -= amount
	print("[FuseBox] Took %d damage. Health=%d/%d." % [amount, maxf(0, _health), 3])
	
	if _health <= 0:
		break_fuse()


## Returns the context-sensitive interaction prompt shown in the HUD.
func get_interact_text() -> String:
	match current_state:
		BoxState.BROKEN:
			return "[E] Insert Fuse"
		BoxState.HAS_FUSE:
			return "[E] Throw Switch"
		BoxState.POWER_ON:
			return "[E] Fuse Box (Active)"
		_:
			return ""
