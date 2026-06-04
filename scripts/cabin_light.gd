extends Node3D
class_name CabinLight

## CabinLight — Individual cabin light fixture with power-grid awareness.
##
## Each light belongs to the "CabinLights" group and is managed by the
## NightManager power grid system.
##
## POWER-ON FLICKER:
## When the generator transitions from OFF to ON, the light performs a
## dramatic startup flicker sequence (6-10 rapid visibility toggles with
## random delays) to simulate an old power grid surging back to life.
##
## POWER-OFF:
## When the generator turns OFF, the light snaps off instantly — no flicker.
## This creates a more dramatic contrast: chaotic surge on, instant death off.

@export var light_name: String = "Room Light"
@export var start_on: bool = false
@export var energy_drain_rate: float = 1.0  # Fuel units consumed per second

## If true, this light is short-circuited and cannot be toggled off by any switch.
## The light is permanently stuck ON whenever the generator has power.
@export var is_faulty: bool = false

## If true, this light is the designated overload target for the endgame trap.
## When the Overload event triggers, this light's drain rate will spike
## dramatically to burn through the generator fuel and trigger a blackout.
@export var is_overload_target: bool = false

@onready var light_node: Light3D = $OmniLight3D
@onready var mesh_on: Node3D = $LightMeshOn if has_node("LightMeshOn") else null
@onready var mesh_off: Node3D = $LightMeshOff if has_node("LightMeshOff") else null

var is_switched_on: bool = false

## If true, this light is currently in the Overload state — blinding glare,
## catastrophic fuel drain, and the light cannot be turned off until the
## generator dies or the overload is manually reset.
var is_overloaded: bool = false

## The original energy_drain_rate before the overload spike.
## Used to restore the normal drain rate if the overload is ever reset.
var _original_drain_rate: float = 0.0

## Tween used for the power-on flicker sequence.
## Stored so we can kill it if the generator state changes mid-flicker.
var _flicker_tween: Tween = null


func _ready() -> void:
	add_to_group("CabinLights")

	is_switched_on = start_on
	_update_light_state()

	# Connect to the central power grid if it exists
	var nm = get_node_or_null("/root/NightManager")
	if nm and nm.has_signal("generator_state_changed"):
		nm.generator_state_changed.connect(_on_generator_state_changed)


func toggle_light() -> void:
	# FAULTY LIGHT GUARD: Short-circuited lights cannot be toggled off.
	# The faulty porch light is permanently stuck ON whenever the generator
	# has power, simulating a wiring fault that drains fuel passively.
	if is_faulty:
		print("[%s] Short-circuited! The switch sparks but does nothing. This light cannot be toggled off." % light_name)
		return

	is_switched_on = !is_switched_on

	if not is_generator_running():
		print("[%s] Click... Switch toggled mechanically, but house has no power." % light_name)
	else:
		print("[%s] Light state changed to: %s" % [light_name, "ON" if is_switched_on else "OFF"])

	_update_light_state()

	# Force power grid load calculation update
	var nm = get_node_or_null("/root/NightManager")
	if nm and nm.has_method("recalculate_fuel_drain"):
		nm.recalculate_fuel_drain()


## Updates the light's visibility based on the switch state and generator power.
## This is the core state function — it sets the light and mesh visibility
## to match whether the light should be physically emitting.
func _set_light_visible(visible: bool) -> void:
	# 1. Handle the physical light emitter casting shadows
	if light_node:
		light_node.visible = visible

	# 2. Swap mesh visibility based on power and switch state
	if mesh_on and mesh_off:
		mesh_on.visible = visible
		mesh_off.visible = not visible


## Evaluates whether the light should be on based on switch state and generator.
## Returns true only if BOTH the switch is ON AND the generator is running.
func _should_be_lit() -> bool:
	return is_switched_on and is_generator_running()


## Updates the light state immediately without any flicker animation.
## Used for instant transitions (power-off, initial state, toggle).
func _update_light_state() -> void:
	# Kill any in-progress flicker tween
	_cancel_flicker()

	_set_light_visible(_should_be_lit())


## Cancels any in-progress flicker tween safely.
func _cancel_flicker() -> void:
	if _flicker_tween and _flicker_tween.is_valid():
		_flicker_tween.kill()
		_flicker_tween = null


## Plays a dramatic startup flicker sequence when the generator turns on.
## Rapidly toggles the light visibility 6-10 times with random delays
## between 0.03 and 0.15 seconds to simulate an old power grid surging
## back to life. After the sequence completes, the light settles to ON.
func _play_power_on_flicker() -> void:
	# Cancel any existing flicker first
	_cancel_flicker()

	# If the light is switched off by the player, don't flicker — just stay off
	if not is_switched_on:
		_set_light_visible(false)
		return

	print("[%s] Power-on flicker STARTING! Generator restored." % light_name)

	# Create a new tween for the flicker sequence
	_flicker_tween = create_tween()
	_flicker_tween.set_parallel(false)

	# Random number of flickers between 8 and 12
	var flicker_count: int = randi_range(8, 12)

	for i in range(flicker_count):
		# Random delay between 0.1 and 0.35 seconds to make the flicker
		# sequence last approximately 2-3 seconds total.
		var delay: float = randf_range(0.1, 0.35)

		# Alternate: odd iterations = ON, even iterations = OFF
		# Start with OFF on the first flicker (i=0) for a "sputter" feel
		var is_on: bool = (i % 2 == 1)

		_flicker_tween.tween_callback(_set_light_visible.bind(is_on))
		_flicker_tween.tween_interval(delay)

	# After the flicker sequence, settle to the correct final state
	_flicker_tween.tween_callback(_set_light_visible.bind(true))
	_flicker_tween.tween_callback(_on_flicker_complete)


## Called when the power-on flicker sequence finishes.
## Cleans up the tween reference and logs the event.
func _on_flicker_complete() -> void:
	_flicker_tween = null
	print("[%s] Power-on flicker complete. Light stabilized." % light_name)


func is_generator_running() -> bool:
	var nm = get_node_or_null("/root/NightManager")
	if nm and "is_generator_on" in nm:
		return nm.is_generator_on
	return true  # Fallback so lights function normally during testing


## Called when NightManager emits generator_state_changed.
## - Generator turning ON: triggers the startup flicker sequence.
## - Generator turning OFF: snaps the light off instantly (no flicker).
func _on_generator_state_changed(is_running: bool) -> void:
	if is_running:
		# Power restored — play the dramatic startup flicker
		_play_power_on_flicker()
	else:
		# Power lost — snap off instantly, no flicker
		_cancel_flicker()
		_set_light_visible(false)


## ─────────────────────────────────────────────────────────────────────────────
## OVERLOAD TRAP — Endgame climax execution
## ─────────────────────────────────────────────────────────────────────────────

## Triggers the Overload state on this light.
##
## Called by the computer terminal when the player executes the
## "EXECUTE OVERLOAD_PORCH_GRID" command after unlocking LOG_02_CRITICAL.
##
## Effects:
##   1. Sets is_overloaded = true
##   2. Saves the original drain rate and spikes it to 50.0
##   3. Boosts the OmniLight3D to blinding intensity (energy 30.0, range 20.0)
##   4. Forces the light ON (is_switched_on = true)
##   5. Calls NightManager.recalculate_fuel_drain() so the generator
##      immediately starts burning fuel at the catastrophic rate
##
## The overload persists until the generator runs out of fuel (blackout)
## or the overload is manually reset via reset_overload().
func trigger_overload() -> void:
	if is_overloaded:
		print("[%s] Overload already active! Ignoring duplicate call." % light_name)
		return
	
	if not is_overload_target:
		print("[%s] ERROR: This light is not an overload target! Ignoring trigger." % light_name)
		return
	
	print("[%s] ⚡ OVERLOAD INITIATED! ⚡" % light_name)
	
	# 1. Set the overload flag
	is_overloaded = true
	
	# 2. Save original drain rate and spike it to catastrophic levels
	_original_drain_rate = energy_drain_rate
	energy_drain_rate = 50.0  # Drains generator fuel in ~seconds
	
	# 3. Force the light ON (bypasses the faulty guard since we're internal)
	is_switched_on = true
	
	# 4. Boost the OmniLight3D to blinding intensity
	if light_node:
		light_node.light_energy = 30.0
		light_node.omni_range = 20.0
		light_node.visible = true
	
	# 5. Swap meshes to show the ON state
	if mesh_on and mesh_off:
		mesh_on.visible = true
		mesh_off.visible = false
	
	# 6. Recalculate fuel drain so the generator immediately feels the load
	var nm = get_node_or_null("/root/NightManager")
	if nm and nm.has_method("recalculate_fuel_drain"):
		nm.recalculate_fuel_drain()
	
	print("[%s] Overload active! Drain rate: %.1f | Light energy: %.1f" % [light_name, energy_drain_rate, light_node.light_energy if light_node else 0.0])


## Resets the Overload state, restoring the original drain rate and light
## intensity. Called when the generator dies (blackout) or if the trap
## is manually disarmed.
func reset_overload() -> void:
	if not is_overloaded:
		return
	
	print("[%s] Overload reset. Restoring normal light parameters." % light_name)
	
	is_overloaded = false
	
	# Restore original drain rate
	energy_drain_rate = _original_drain_rate
	_original_drain_rate = 0.0
	
	# Restore light intensity to default
	if light_node:
		light_node.light_energy = 2.0
		light_node.omni_range = 5.0
	
	# Update visibility based on normal switch/generator state
	_update_light_state()
	
	# Recalculate fuel drain
	var nm = get_node_or_null("/root/NightManager")
	if nm and nm.has_method("recalculate_fuel_drain"):
		nm.recalculate_fuel_drain()
	
	print("[%s] Overload reset complete. Drain rate restored to %.1f." % [light_name, energy_drain_rate])
