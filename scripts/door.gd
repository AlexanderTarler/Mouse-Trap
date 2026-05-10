extends StaticBody3D
class_name Door

## Interactive door that can be opened/closed.
## Used for the cabin entrance and basement access.

signal door_opened()
signal door_closed()

## If true, the door starts in the open position.
@export var start_open: bool = false

## If true, this is the basement door (opens to reveal stairs).
@export var is_basement_door: bool = false

## Door swing angle in degrees (positive = inward, negative = outward).
@export var swing_angle: float = 90.0

## How fast the door opens/closes.
@export var swing_speed: float = 3.0

## Door label shown in the interaction prompt.
@export var door_label: String = "Door"

var _is_open: bool = false
var _target_rotation: float = 0.0
var _current_rotation: float = 0.0
var _is_animating: bool = false

func _ready() -> void:
	if start_open:
		_is_open = true
		_target_rotation = deg_to_rad(swing_angle)
		_current_rotation = _target_rotation
		rotation.y = _current_rotation

func _process(delta: float) -> void:
	if not _is_animating:
		return
	
	_current_rotation = lerp(_current_rotation, _target_rotation, delta * swing_speed)
	rotation.y = _current_rotation
	
	if abs(_current_rotation - _target_rotation) < 0.01:
		_current_rotation = _target_rotation
		rotation.y = _current_rotation
		_is_animating = false

## Called by InteractionManager when the player looks at this door and presses E.
func interact() -> void:
	_toggle()

func _toggle() -> void:
	_is_open = not _is_open
	_target_rotation = deg_to_rad(swing_angle) if _is_open else 0.0
	_is_animating = true
	
	if _is_open:
		door_opened.emit()
	else:
		door_closed.emit()

## Returns the interaction prompt text.
func get_interact_text() -> String:
	var action = "Close" if _is_open else "Open"
	return "[E] %s %s" % [action, door_label]
