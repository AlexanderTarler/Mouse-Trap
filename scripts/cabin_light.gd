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

## Whether this light casts shadows. Defaults to true so the porch light's
## OmniLight3D occludes against cabin wall meshes, preventing light bleed
## through thin wall seams (the "porch light shining inside the cabin" bug).
## Set false per-fixture in the Inspector for performance-critical lights.
@export var cast_shadows: bool = true

## If true, this light is short-circuited and cannot be toggled off by any switch.
## The light is permanently stuck ON whenever the generator has power.
@export var is_faulty: bool = false

## [DEPRECATED] — Overload trap logic has been migrated to the Portable
## High-Voltage Lamp (scripts/objects/portable_lamp.gd).
## This flag is retained as a simple export for scene compatibility only.
## It no longer gates any overload behavior in this script.
@export var is_overload_target: bool = false

## Sound played when this light switch is toggled (both ON and OFF).
@export var light_switch_sfx: AudioStream = null


## The physical light emitter child (OmniLight3D or SpotLight3D).
## Resolved by _find_light_node() — see that function for why the `or`-based
## expression is avoided.
@onready var light_node: Light3D = _find_light_node()

## Resolves the Light3D emitter child. GDScript's `or` operator ALWAYS yields a
## boolean regardless of operand types, so the previous one-liner
##   $OmniLight3D or $SpotLight3D if ... else null
## — and even the parenthesized get_node_or_null() variant — produced a BOOL,
## failing the `Light3D` type of light_node (the error that appeared when the
## porch light was converted from OmniLight3D to SpotLight3D). It also required
## `$OmniLight3D` unconditionally, throwing "Node not found" for Spot-only
## scenes. An explicit null-check chain returns the existing Light3D type-safely.
func _find_light_node() -> Light3D:
	if has_node("OmniLight3D"):
		return get_node("OmniLight3D") as Light3D
	if has_node("SpotLight3D"):
		return get_node("SpotLight3D") as Light3D
	return null
@onready var mesh_on: Node3D = $LightMeshOn if has_node("LightMeshOn") else null
@onready var mesh_off: Node3D = $LightMeshOff if has_node("LightMeshOff") else null

var is_switched_on: bool = false

## Tween used for the power-on flicker sequence.

## Stored so we can kill it if the generator state changes mid-flicker.
var _flicker_tween: Tween = null


func _ready() -> void:
	add_to_group("CabinLights")

	# ─── SHADOW ENABLE (Bug: porch light bleeding into cabin) ─────────
	# Shadows let the OmniLight3D be occluded by the cabin wall meshes.
	# Without shadows, the light illuminates through thin seam gaps.
	# Disable per-fixture via the inspector cast_shadows = false.
	if light_node and light_node is Light3D:
		light_node.shadow_enabled = cast_shadows

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
	
	# ─── DAY 1 ONBOARDING: PHASE 3 — LIGHT TOGGLED OFF ────────────────
	# Notify RoutineManager that a light was toggled off, passing this
	# light's display name so the manager can gate the "Turn off the light
	# in the hall" objective to the hall fixture specifically.
	if not is_switched_on:
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_light_toggled_off"):
			# Pass the node path so RoutineManager can reliably identify the
			# hall fixture (path contains "Hall", e.g. .../CabinLightHall).
			# The scene's hall lamp still uses the default "Room Light" name,
			# so the display name alone is NOT enough to gate the objective.
			rm.on_light_toggled_off(light_name, get_path())



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


## Returns true if this light is actually emitting light right now.
## A room is considered "lit" only when BOTH:
##   - The light switch is ON (is_switched_on == true)
##   - The generator is running (has power)
##
## This is the single source of truth for the Light Detection System.
## Used by CabinWindow, RoomLightDetector, and the Entity AI to determine
## whether a room is safe (lit) or dangerous (dark).
func is_room_lit() -> bool:
	return is_switched_on and is_generator_running()


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
## OVERLOAD TRAP — [MIGRATED]
## ─────────────────────────────────────────────────────────────────────────────
## The overload trap logic has been migrated to the Portable High-Voltage Lamp
## (scripts/objects/portable_lamp.gd). The porch light is no longer an overload
## target — it remains in the scene as a baseline environmental hazard with
## is_faulty = true (permanently stuck ON, drawing normal energy_drain_rate).


## Plays a one-shot sound effect via a temporary AudioStreamPlayer3D.
func _play_sfx(stream: AudioStream) -> void:
	if not stream:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = "SFX"
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
