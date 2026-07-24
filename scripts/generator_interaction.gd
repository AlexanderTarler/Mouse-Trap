extends Area3D

## Generator refill interaction point.
## Attach this script to an Area3D node placed on the physical generator model.
##
## HOLD-TO-REFUEL MECHANIC:
##   PhysicalGrab (physical_grab.gd) detects when the player looks at this
##   generator and holds E. On E press, PhysicalGrab calls start_refuel().
##   On E release, PhysicalGrab calls stop_refuel(). The continuous fuel
##   transfer runs in _process() while _is_refueling is true.
##
##   This mirrors how the door's toggle_lock works: PhysicalGrab tracks the
##   hold, and the target object responds to start/stop signals.
##
##   Fuel scaling:
##     - One fuel can holds FUEL_PER_CAN (50.0) units of generator fuel.
##     - The NightManager's max_fuel is 100.0 (two full cans = full tank).
##     - Hold E for 10 seconds = one full can consumed = 50 units transferred.
##     - Hold E for 2 seconds = 20% of a can = 10 units = 20% of generator.

## How many seconds the player must hold E to fully drain one fuel can.
## Default: 10.0 seconds (2s hold = 20% of a can = 10 fuel units).
@export var refuel_duration_per_can: float = 10.0

## How many fuel units one fuel can contains (matches NightManager's fuel scale).
const FUEL_PER_CAN: float = 50.0

## Cached reference to the NightManager.
var _nm: Node = null

## Accumulated hold time for the current fuel can transfer (seconds).
## Resets to 0.0 when a new can is selected or refueling stops.
var _hold_time: float = 0.0

## The fuel can ItemData currently being drained from inventory.
var _active_fuel_can = null

## Whether the player is currently holding E and refueling is active.
## Set to true by start_refuel(), set to false by stop_refuel().
## The _process() loop transfers fuel while this is true.
var _is_refueling: bool = false

## Progress from 0.0 to 1.0 within the current fuel can.
## Shown to the player via UI to indicate how much of the current can has been used.
var _can_progress: float = 0.0

## Whether on_generator_refilled() has been called for this refuel session.
## Ensures the objective notification fires only once per session (on first
## successful fuel transfer), not every frame or only when the tank is full.
var _refuel_notified: bool = false


func _ready() -> void:
	add_to_group("xray_generator")
	_nm = get_node_or_null("/root/NightManager")
	collision_layer = 1


func _process(delta: float) -> void:
	if not _is_refueling or not _active_fuel_can:
		return
	if not _nm:
		stop_refuel()
		return
	
	# ─── GENERATOR FULL CHECK ─────────────────────────────────────────
	if _nm.generator_fuel >= _nm.max_fuel:
		print("[Generator] Generator is full. Refuel complete.")
		stop_refuel()
		return
	
	# ─── CALCULATE FUEL TRANSFER FOR THIS FRAME ───────────────────────
	# Bug 2 Fix: Track how much of the can has been consumed via hold_time
	# and use EXACT values when the can is fully drained. Per-frame float
	# accumulation drifts by ~1% due to the minf() clamp on every frame.
	# When the can is fully consumed, we add exactly FUEL_PER_CAN (50.0)
	# to the generator instead of relying on per-frame deltas.
	var transfer_rate: float = FUEL_PER_CAN / refuel_duration_per_can
	var new_hold_time: float = _hold_time + delta
	var new_can_progress: float = new_hold_time / refuel_duration_per_can
	
	# Check if this frame finishes draining the current can
	if new_can_progress >= 1.0:
		# ─── CAN FULLY CONSUMED: Add only the remaining fuel ──────────
		# The per-frame loop already added ~49.x units via transfer_rate * delta.
		# We only add the remainder to reach exactly FUEL_PER_CAN (50.0),
		# preventing the double-count that would fill 100% from one can.
		var remaining: float = FUEL_PER_CAN - (_hold_time * transfer_rate)
		_nm.generator_fuel = minf(_nm.generator_fuel + remaining, _nm.max_fuel)
		_nm.fuel_changed.emit(_nm.generator_fuel)
		
		Inventory.remove_item(_active_fuel_can)
		print("[Generator] One fuel can fully consumed (%.1f units transferred)." % FUEL_PER_CAN)
		
		# Look for another can to continue
		_active_fuel_can = _find_fuel_can_in_inventory()
		if _active_fuel_can:
			_hold_time = 0.0
			_can_progress = 0.0
			print("[Generator] Found another fuel can. Continuing refuel...")
		else:
			print("[Generator] No more fuel cans. Refuel stopped.")
			stop_refuel()
			return
	else:
		# Normal per-frame transfer (can not yet fully consumed)
		var fuel_to_add: float = transfer_rate * delta
		
		# Clamp to remaining generator capacity
		var gen_space: float = _nm.max_fuel - _nm.generator_fuel
		fuel_to_add = minf(fuel_to_add, gen_space)
		
		# Clamp to remaining fuel in the current can
		var can_remaining: float = FUEL_PER_CAN - (_hold_time * transfer_rate)
		fuel_to_add = minf(fuel_to_add, can_remaining)
		
		if fuel_to_add <= 0.0:
			_hold_time = new_hold_time
			_can_progress = new_can_progress
			return
		
		_nm.generator_fuel = minf(_nm.generator_fuel + fuel_to_add, _nm.max_fuel)
		_nm.fuel_changed.emit(_nm.generator_fuel)
		_hold_time = new_hold_time
		_can_progress = new_can_progress
	
	# ─── RESTART GENERATOR IF OFF ─────────────────────────────────────
	if not _nm.is_generator_on and _nm.generator_fuel > 0.0:
		_nm.is_generator_on = true
		_nm.generator_state_changed.emit(true)
		print("[Generator] Generator restarted during refuel!")
		
		# ─── DAY 1 POWER FEEDBACK: Auto-light the first interior light ──
		# When the generator powers on for the first time, give the player
		# immediate visual feedback by turning on one of the cabin lights.
		# We find the first non-faulty interior light that's currently off
		# and toggle it on. The CabinLight's _on_generator_state_changed
		# handler will play the power-on flicker animation automatically.
		var cabin_lights = get_tree().get_nodes_in_group("CabinLights")
		for light in cabin_lights:
			if "is_faulty" in light and light.is_faulty:
				continue  # Skip the faulty porch light
			if "is_switched_on" in light and not light.is_switched_on:
				if light.has_method("toggle_light"):
					light.toggle_light()
					print("[Generator] Auto-turned on '%s' for power feedback." % light.name)
					break  # Only turn on one light
	
	# ─── NOTIFY ROUTINE MANAGER AT 40% FUEL ──────────────────────────
	# The objective "Refuel the generator" should complete when the
	# generator has received at least 40 units (40% of max_fuel).
	# This prevents the notification from firing on the first frame of
	# refueling when only 0.05 units have been transferred.
	var _forty_pct_threshold: float = 40.0  # 40% of max_fuel
	if not _refuel_notified and _nm.generator_fuel >= _forty_pct_threshold:
		_refuel_notified = true
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_generator_refilled"):
			rm.on_generator_refilled()
			print("[Generator] Notified RoutineManager: generator refueled (%.1f units >= 40.0 threshold)." % _nm.generator_fuel)
	
	# ─── NOTIFY IF GENERATOR IS NOW FULL ─────────────────────────────
	if _nm.generator_fuel >= _nm.max_fuel:
		print("[Generator] Generator is now full!")
		stop_refuel()


## Called by PhysicalGrab when the player presses E while looking at this generator.
## Starts the continuous fuel transfer. Does NOT check inventory — if no fuel can
## is available, _process() does nothing and returns harmlessly.
func start_refuel() -> void:
	if not _nm:
		print("[Generator] ERROR: NightManager not found!")
		return
	
	if _is_refueling:
		return
	
	if _nm.generator_fuel >= _nm.max_fuel:
		print("[Generator] Generator is already full.")
		return
	
	_active_fuel_can = _find_fuel_can_in_inventory()
	if not _active_fuel_can:
		print("[Generator] I need a Fuel Can to refill the generator.")
		return
	
	_is_refueling = true
	_hold_time = 0.0
	_can_progress = 0.0
	print("[Generator] Refuel started. Rate: %.1f units/sec (%.1fs per can)." % [FUEL_PER_CAN / refuel_duration_per_can, refuel_duration_per_can])


## Called by PhysicalGrab when the player releases E while refueling.
## Also called by _process() when refueling completes.
## The current fuel can is preserved (not partially consumed) in inventory.
func stop_refuel() -> void:
	if not _is_refueling:
		return
	_is_refueling = false
	_active_fuel_can = null
	_hold_time = 0.0
	_can_progress = 0.0
	print("[Generator] Refuel stopped. Partial can preserved in inventory.")


## Called by PhysicalGrab when the player quick-taps E.
## Legacy fallback — quick-tap does nothing for the generator; the player must
## hold E to refuel. This method exists so the InteractionManager can display
## the prompt via get_interact_text().
func interact() -> void:
	pass


## Returns the current fuel percentage from NightManager, or 0 if unavailable.
func _get_fuel_percent() -> int:
	if _nm and _nm.max_fuel > 0:
		return int((_nm.generator_fuel / _nm.max_fuel) * 100.0)
	return 0

## Called by the InteractionManager to display the HUD prompt.
func get_interact_text() -> String:
	var fuel_pct: int = _get_fuel_percent()
	if _nm and _nm.generator_fuel >= _nm.max_fuel:
		return "[E] Generator (Full)"
	if _is_refueling:
		var pct: int = int(_can_progress * 100.0)
		return "[E] Refueling... %d%%" % pct
	if not _find_fuel_can_in_inventory():
		return "[E] Refill Generator (No Fuel Can — %d%% Remaining)" % fuel_pct
	return "[E] Hold to Refill Generator (%d%% Fuel Remaining)" % fuel_pct


## Searches the player's inventory for a Fuel Can item.
func _find_fuel_can_in_inventory():
	for item in Inventory.items:
		if item != null and "item_name" in item and item.item_name == "Fuel Can":
			return item
	return null