extends AnimatableBody3D

## How many degrees the door swings open (90 or -90 depending on hinge side)
@export var open_angle: float = 90.0
## How fast the door opens or closes in seconds
@export var swing_speed: float = 0.4
@export var open_sound: AudioStream
@export var close_sound: AudioStream

@onready var door_audio: AudioStreamPlayer3D = $DoorAudio if has_node("DoorAudio") else null

var is_open: bool = false
var is_animating: bool = false
var default_rotation_y: float

func _ready() -> void:
	# Save the baseline rotation so we always return to a clean closed state
	default_rotation_y = rotation_degrees.y

## Call this function from your Player's interaction script!
func interact() -> void:
	if is_animating:
		return # Prevent input spam while the door is mid-swing
		
	is_open = not is_open
	is_animating = true
	
	# Play door audio with pitch randomization
	if door_audio:
		# Use export-assigned sounds if available, otherwise fall back to the node's existing stream
		var target_stream = open_sound if is_open else close_sound
		if target_stream:
			door_audio.stream = target_stream
		# If no stream is set at all (neither export nor node default), skip playing
		if door_audio.stream:
			door_audio.pitch_scale = randf_range(0.9, 1.1)
			door_audio.play()
	
	# Determine target rotation destination
	var target_angle = default_rotation_y + (open_angle if is_open else 0.0)
	
	# Create a clean, smooth physics tween interpolation
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "rotation_degrees:y", target_angle, swing_speed)
	
	# Unlock input once the animation finishes moving
	tween.tween_callback(func(): is_animating = false)
	
