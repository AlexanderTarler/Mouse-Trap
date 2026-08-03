extends CanvasLayer
class_name StandoffEffect

## StandoffEffect — Visual and auditory hallucinations when staring at the Entity.
##
## Displays faint, blurred Swedish text labels that fade in as the player's
## look_timer increases. Also manages the auditory hallucination audio loop.
##
## The look_timer value (0.0 to 1.5+) is set externally by the player controller.

## How fast the text labels fade in/out (seconds to reach full opacity)
@export var fade_speed: float = 2.0

## The auditory hallucination audio stream (metallic ringing/whispers)
@export var hallucination_audio: AudioStream = null

## Reference to the AudioStreamPlayer for the hallucination loop
var _audio_player: AudioStreamPlayer = null

## All hallucination text labels
var _text_labels: Array[Label] = []

## Current target opacity (0.0 to 1.0) based on look_timer
var _target_alpha: float = 0.0

## Random offset jitter for each label (adds unease)
var _label_offsets: Array[Vector2] = []

## ─── OVERCHARGE ESCALATION ─────────────────────────────────────────────
## When true, the player is holding the overcharge beam on the Entity.
## This amplifies the standoff effects: faster fade-in, stronger label jitter,
## louder auditory hallucination. Set by the player controller each frame.
var _is_overcharging: bool = false

## Overcharge intensity scalar — multiplies the standardized look_timer alpha
## curve so the effects ramp up harder and faster during an overcharge standoff.
@export var overcharge_intensity_multiplier: float = 1.6


func _ready() -> void:
	# Find all Label children — these are the hallucination text nodes
	for child in get_children():
		if child is Label:
			_text_labels.append(child)
			_label_offsets.append(Vector2.ZERO)
			child.set_meta("base_position", child.position)  # Store original position
			child.modulate = Color(1, 1, 1, 0)  # Start invisible
	
	# Set up the auditory hallucination audio player
	_audio_player = AudioStreamPlayer.new()
	_audio_player.bus = "Master"
	_audio_player.volume_db = -80.0  # Start silent
	if hallucination_audio:
		_audio_player.stream = hallucination_audio
		_audio_player.play()  # Start playing silently — will fade in
	add_child(_audio_player)


## Called every frame by the player controller with the current look_timer value.
## look_timer ranges from 0.0 (not looking) to 1.5+ (staring at the Entity).
func update_look_timer(look_timer: float) -> void:
	# ─── NIGHT GATE ─────────────────────────────────────────────────────
	# Hallucination effects are only active from Night 2 Phase 2 onward.
	# Before this point, the Entity is dormant/inactive and the player
	# should not experience standoff effects even if they look toward
	# the Entity's position.
	var nm = get_node_or_null("/root/NightManager")
	if nm and "current_night" in nm and nm.current_night < 2:
		reset()
		return
	
	# ─── OVERCHARGE-AMPLIFIED ALPHA ──────────────────────────────────
	# Standard: 0.0 at 0s, 1.0 at 1.5s (look_timer / 1.5).
	# Overcharge: multiplied by overcharge_intensity_multiplier so the
	# effects visibly spike the moment the beam surges. The alpha still
	# scales 0→1 with the stare timer, but ramps harder during the surge.
	var base_alpha := clampf(look_timer / 1.5, 0.0, 1.0)
	_target_alpha = clampf(base_alpha * (overcharge_intensity_multiplier if _is_overcharging else 1.0), 0.0, 1.0)
	
	# ─── FASTER FADE SPEED WHILE OVERCHARGING ────────────────────────
	# The effects snap on/off faster during an overcharge standoff to
	# match the high-stakes precision feel.
	var effective_fade_speed := fade_speed * (1.8 if _is_overcharging else 1.0)
	
	# Smoothly interpolate each label's opacity
	for i in range(_text_labels.size()):
		var label = _text_labels[i]
		if not label:
			continue
		
		var current_alpha = label.modulate.a
		var new_alpha = move_toward(current_alpha, _target_alpha, effective_fade_speed * get_process_delta_time())
		label.modulate = Color(1, 1, 1, new_alpha)
		
		# Randomly jitter label positions slightly for unease.
		# Overcharging multiplies the jitter amplitude for a violent, anxious feel.
		var jitter_scale := 1.0
		if _is_overcharging:
			jitter_scale = 2.5
		if _target_alpha > 0.1:
			_label_offsets[i] = Vector2(
				randf_range(-2.0, 2.0) * _target_alpha * jitter_scale,
				randf_range(-1.0, 1.0) * _target_alpha * jitter_scale
			)
			label.position = label.get_meta("base_position", label.position) + _label_offsets[i]
	
	# Fade the auditory hallucination audio in/out
	if _audio_player:
		var target_vol = -80.0
		if _target_alpha > 0.1:
			# Map alpha 0.1→1.0 to volume -40dB→-10dB.
			# Overcharging raises the floor to -30dB so the whispers are
			# already audible at the start of the standoff.
			var base_min_vol := -40.0 if not _is_overcharging else -30.0
			target_vol = base_min_vol + (_target_alpha - 0.1) * (30.0 / 0.9)
		_audio_player.volume_db = move_toward(_audio_player.volume_db, target_vol, 10.0 * get_process_delta_time())


## Public API: Called by the player controller each frame to communicate
## whether the overcharge beam is currently active. Amplifies the standoff
## hallucination effects while held.
func update_overcharge(is_overcharging: bool) -> void:
	_is_overcharging = is_overcharging


## Resets all visual effects to zero (called when look_timer decays to 0).
func reset() -> void:
	_target_alpha = 0.0
	for label in _text_labels:
		if label:
			label.modulate = Color(1, 1, 1, 0)
	if _audio_player:
		_audio_player.volume_db = -80.0
