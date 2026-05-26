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
	# Calculate target alpha: 0.0 at 0s, 1.0 at 1.5s
	_target_alpha = clampf(look_timer / 1.5, 0.0, 1.0)
	
	# Smoothly interpolate each label's opacity
	for i in range(_text_labels.size()):
		var label = _text_labels[i]
		if not label:
			continue
		
		var current_alpha = label.modulate.a
		var new_alpha = move_toward(current_alpha, _target_alpha, fade_speed * get_process_delta_time())
		label.modulate = Color(1, 1, 1, new_alpha)
		
		# Randomly jitter label positions slightly for unease
		if _target_alpha > 0.1:
			_label_offsets[i] = Vector2(
				randf_range(-2.0, 2.0) * _target_alpha,
				randf_range(-1.0, 1.0) * _target_alpha
			)
			label.position = label.get_meta("base_position", label.position) + _label_offsets[i]
	
	# Fade the auditory hallucination audio in/out
	if _audio_player:
		var target_vol = -80.0
		if _target_alpha > 0.1:
			# Map alpha 0.1→1.0 to volume -40dB→-10dB
			target_vol = -40.0 + (_target_alpha - 0.1) * (30.0 / 0.9)
		_audio_player.volume_db = move_toward(_audio_player.volume_db, target_vol, 10.0 * get_process_delta_time())


## Resets all visual effects to zero (called when look_timer decays to 0).
func reset() -> void:
	_target_alpha = 0.0
	for label in _text_labels:
		if label:
			label.modulate = Color(1, 1, 1, 0)
	if _audio_player:
		_audio_player.volume_db = -80.0
