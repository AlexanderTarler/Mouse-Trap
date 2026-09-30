extends SpotLight3D

## Flashlight with battery drain system + Hold-to-Overcharge.
## Attached to the SpotLight3D child of Camera3D.
##
## OVERCHARGE SYSTEM:
##   - Tap F: Toggle on/off (standard beam, 1x drain).
##   - Hold F (>0.25s while ON): Overcharge beam (6x drain, narrower cone, higher energy).
##   - The overcharge state is communicated to the Entity via the `is_overcharged`
##     property (read by player_controller.gd and forwarded to on_player_stare()).

signal battery_changed(level: float)
signal flashlight_turned_off
signal flashlight_turned_on
signal overcharge_activated
signal overcharge_deactivated

@export var max_battery: float = 100.0
@export var drain_rate: float = 0.5  # per second when on (halved from 1.0)
@export var low_battery_threshold: float = 15.0

## ─── OVERCHARGE TUNING ─────────────────────────────────────────────────────
## Multiplier applied to drain_rate while the overcharge beam is active.
## Reduced from 6.0 → 3.0 (exactly 50% less overcharge drain), so the
## battery lasts twice as long in overcharge mode.
@export var overcharge_drain_multiplier: float = 3.0

## Standard beam energy (SpotLight3D light_energy) when not overcharged.
@export var standard_energy: float = 2.0

## Overcharge beam energy — dramatically brighter to convey the surge.
@export var overcharge_energy: float = 8.0

## Standard beam cone half-angle in degrees (SpotLight3D spot_angle).
@export var standard_spot_angle: float = 45.0

## Overcharge beam cone half-angle in degrees — narrower, rewarding precision.
@export var overcharge_spot_angle: float = 25.0

## How fast light_energy / spot_angle lerp between standard and overcharge (0-1 per second).
@export var beam_lerp_speed: float = 8.0

## ─── OVERCHARGE HUM AUDIO (placeholder) ────────────────────────────────────
## Assign the .ogg/.wav hum loop here in the Inspector when ready.
## Until then the AudioStreamPlayer node still exists but stays silent.
@export var overcharge_hum: AudioStream = null
@export var overcharge_hum_volume_db: float = -12.0

var battery_level: float = 100.0
var is_on: bool = false

## Whether the overcharge beam is currently active. Reset to false on ANY of:
## flashlight toggle off, battery death, or explicit deactivate_overcharge().
var is_overcharged: bool = false

# Flicker state
var _base_energy: float = 1.0
var _flicker_timer: float = 0.0
var _is_flickering: bool = false

## Looping AudioStreamPlayer for the overcharge hum. Created in _ready() so the
## node always exists in the tree; it only plays when a stream is assigned AND
## overcharge is active.
var _hum_player: AudioStreamPlayer = null

## ─── OVERCHARGE TUTORIAL HOLD TRACKING ────────────────────────────────────
## Accumulated time (seconds) the player has continuously held the F key in
## overcharge mode. The "Hold F to overcharge" tutorial hint only dismisses
## once this reaches OVERCHARGE_TUTORIAL_HOLD_REQUIRED (3.0s). Resets if the
## player releases F or overcharge deactivates early.
var _overcharge_tutorial_hold_time: float = 0.0

## Total continuous hold time (seconds) required before the overcharge
## tutorial ("Hold [F] to OVERCHARGE...") is dismissed via mark_learned().
const OVERCHARGE_TUTORIAL_HOLD_REQUIRED: float = 3.0

## ─── LOW BATTERY TUTORIAL ──────────────────────────────────────────────
## The percentage threshold (0-100) at which the "flashlight is low on
## energy" tutorial hint fires. Set to 30% per design. This is a SEPARATE
## threshold from low_battery_threshold (15%) which controls visual flicker.
const LOW_BATTERY_HINT_PERCENT: float = 30.0

## One-shot guard so the low-battery hint only shows once. Set to true the
## first time battery drops below LOW_BATTERY_HINT_PERCENT. Persists for
## the lifetime of the flashlight (per-session, not cross-save).
var _low_battery_hint_shown: bool = false


func _ready() -> void:
	battery_level = max_battery
	visible = is_on
	# Capture the designer's chosen standard energy from the node, but fall back
	# to the exported standard_energy if the node was left at Godot's default (1.0).
	_base_energy = light_energy if light_energy > 0.0 else standard_energy
	if light_energy <= 0.0 or is_equal_approx(light_energy, 1.0):
		_base_energy = standard_energy
	
	# ─── OVERCHARGE HUM PLAYER (placeholder) ────────────────────────────
	# Always create the node so the designer can see it in the tree. The stream
	# is assigned via the exported `overcharge_hum` property.
	_hum_player = AudioStreamPlayer.new()
	_hum_player.bus = "SFX"
	_hum_player.volume_db = overcharge_hum_volume_db
	if overcharge_hum:
		_hum_player.stream = overcharge_hum
	add_child(_hum_player)


func _process(delta: float) -> void:
	if is_on and battery_level > 0.0:
		# ─── BATTERY DRAIN (with overcharge multiplier) ─────────────────
		var active_drain: float = drain_rate
		if is_overcharged:
			active_drain *= overcharge_drain_multiplier
		battery_level -= active_drain * delta
		battery_level = maxf(battery_level, 0.0)
		battery_changed.emit(battery_level)
		
		if battery_level <= 0.0:
			# Battery died mid-standoff — cleanly reset overcharge state.
			_turn_off()
			return
		
		# ─── OVERCHARGE TUTORIAL HOLD TRACKING ────────────────────────
		# Only accumulate while the overcharge beam is active AND the
		# mechanic has not yet been learned. The hint stays on screen
		# until the player has continuously held F for at least the
		# required duration (3.0s). Once satisfied, dismiss it.
		if is_overcharged and not _is_overcharge_tutorial_learned():
			_overcharge_tutorial_hold_time += delta
			if _overcharge_tutorial_hold_time >= OVERCHARGE_TUTORIAL_HOLD_REQUIRED:
				_overcharge_tutorial_hold_time = 0.0
				_mark_overcharge_tutorial_learned()
		elif not is_overcharged:
			# Overcharge not active — reset the cumulative hold timer so
			# the player must hold continuously for the full 3 seconds.
			_overcharge_tutorial_hold_time = 0.0
		
		# ─── BEAM LERP (energy + cone) ────────────────────────────────
		_update_beam_lerp(delta)
		
		# ─── LOW BATTERY FLICKER ───────────────────────────────────────
		# The flicker applies on top of the lerped energy, making the beam
		# visually struggle without changing the is_overcharged gameplay flag.
		# ─── LOW BATTERY TUTORIAL HINT (below 30%) ───────────────
		# Shows once the first time battery drops below 30%. The tutorial
		# system handles the one-shot persistence via mark_learned(), but
		# we guard here too so the call is not spammed every frame.
		if not _low_battery_hint_shown and get_battery_percent() <= LOW_BATTERY_HINT_PERCENT:
			_low_battery_hint_shown = true
			var tm := get_node_or_null("/root/TutorialManager")
			if tm and tm.has_method("trigger"):
				tm.trigger("low_battery")
				print("[Flashlight] Battery low — triggered 'low_battery' tutorial hint.")
		
		if battery_level <= low_battery_threshold:
			_update_flicker(delta)
		elif _is_flickering:
			# Stop flickering if battery recovered above threshold
			_is_flickering = false
			light_energy = _get_target_energy()


## Smoothly lerps light_energy and spot_angle toward the current mode's targets.
## Standard beam: standard_energy / standard_spot_angle.
## Overcharge beam: overcharge_energy / overcharge_spot_angle.
func _update_beam_lerp(delta: float) -> void:
	var target_energy := _get_target_energy()
	var target_angle := overcharge_spot_angle if is_overcharged else standard_spot_angle
	light_energy = lerpf(light_energy, target_energy, beam_lerp_speed * delta)
	spot_angle = lerpf(spot_angle, target_angle, beam_lerp_speed * delta)


## Returns the visual target energy for the current mode.
func _get_target_energy() -> float:
	return overcharge_energy if is_overcharged else _base_energy


func _update_flicker(delta: float) -> void:
	_is_flickering = true
	_flicker_timer -= delta
	
	if _flicker_timer <= 0.0:
		# Random flicker interval (0.05 to 0.3 seconds)
		_flicker_timer = randf_range(0.05, 0.3)
		
		# Random energy between 0.1 and target energy.
		# Lower battery = more severe flicker (lower minimum).
		var battery_ratio = battery_level / low_battery_threshold
		var min_energy = 0.1 * (1.0 - battery_ratio * 0.7)  # 0.1 to ~0.03
		light_energy = randf_range(min_energy, _get_target_energy())


## Public API: Activate the overcharge beam. No-op if the flashlight is off,
## the battery is dead, or overcharge is already active.
func activate_overcharge() -> void:
	if not is_on or battery_level <= 0.0:
		return
	if is_overcharged:
		return
	is_overcharged = true
	_start_hum()
	overcharge_activated.emit()


## Public API: Deactivate the overcharge beam, returning to the standard beam.
## The flashlight stays ON (overcharge is a mode, not a toggle).
func deactivate_overcharge() -> void:
	if not is_overcharged:
		return
	is_overcharged = false
	# Reset the tutorial hold accumulator — the player must hold
	# continuously to satisfy the 3-second requirement.
	_overcharge_tutorial_hold_time = 0.0
	_stop_hum()
	overcharge_deactivated.emit()


## The switch: a click every time it's toggled.
const CLICK_PATHS: Array[String] = [
	"res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Buttons & Levers/button_flashlight_1.ogg",
	"res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Buttons & Levers/button_flashlight_2.ogg",
	"res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Buttons & Levers/button_flashlight_3.ogg",
]
var _click_player: AudioStreamPlayer = null


func toggle() -> void:
	if battery_level <= 0.0:
		return  # Can't turn on if battery is dead
	if is_on:
		_turn_off()
	else:
		_turn_on()
	_play_click()


func _play_click() -> void:
	if not _click_player:
		_click_player = AudioStreamPlayer.new()
		_click_player.bus = &"SFX"
		_click_player.volume_db = -8.0
		add_child(_click_player)
	var path: String = CLICK_PATHS.pick_random()
	if ResourceLoader.exists(path):
		_click_player.stream = load(path)
		_click_player.pitch_scale = randf_range(0.95, 1.05)
		_click_player.play()
	NoiseEvent.emit(self, global_position, &"click")


func _turn_on() -> void:
	is_on = true
	visible = true
	# Always start in standard mode — a fresh toggle never begins overcharged.
	is_overcharged = false
	light_energy = _base_energy
	spot_angle = standard_spot_angle
	_is_flickering = false
	flashlight_turned_on.emit()


func _turn_off() -> void:
	is_on = false
	visible = false
	# ─── CRITICAL: Reset overcharge on any power-off ─────────────────────
	# This covers: manual toggle off, battery death mid-standoff, and any
	# external force-off. Guarantees is_overcharged can never stay true while
	# the light is off.
	if is_overcharged:
		is_overcharged = false
		overcharge_deactivated.emit()
	_is_flickering = false
	_stop_hum()
	flashlight_turned_off.emit()


func refill(amount: float) -> void:
	battery_level = minf(battery_level + amount, max_battery)
	battery_changed.emit(battery_level)
	# If battery was dead and now has charge, the player can toggle it back on
	if battery_level > 0.0 and not is_on:
		pass  # Don't auto-turn on, let player decide


## Alias for refill, called by inventory when using a battery item.
func refill_battery(amount: float) -> void:
	refill(amount)


func set_battery_level(level: float) -> void:
	battery_level = clampf(level, 0.0, max_battery)
	battery_changed.emit(battery_level)


func get_battery_percent() -> float:
	return (battery_level / max_battery) * 100.0


func is_low_battery() -> bool:
	return battery_level <= low_battery_threshold


## Returns true if the "overcharge" tutorial mechanic has already been learned
## (i.e. the hint was previously dismissed via mark_learned).
func _is_overcharge_tutorial_learned() -> bool:
	var tm := get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("is_learned"):
		return tm.is_learned("overcharge")
	return true  # If TutorialManager unavailable, assume learned to avoid stuck hints


## Dismisses the "Hold F to overcharge" tutorial hint via TutorialManager.
## Called once the player has continuously held overcharge for 3.0 seconds.
func _mark_overcharge_tutorial_learned() -> void:
	var tm := get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("mark_learned"):
		tm.mark_learned("overcharge")
		print("[Flashlight] Overcharge tutorial complete — player held overcharge for %.1fs." % OVERCHARGE_TUTORIAL_HOLD_REQUIRED)


## ─── OVERCHARGE HUM AUDIO ──────────────────────────────────────────────────
func _start_hum() -> void:
	if _hum_player and _hum_player.stream and not _hum_player.playing:
		_hum_player.play()


func _stop_hum() -> void:
	if _hum_player and _hum_player.playing:
		_hum_player.stop()