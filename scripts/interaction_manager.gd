extends Node3D

## Simple interaction manager for the horror game.
## Shows a prompt when looking at interactable objects.

@export var interaction_distance: float = 3.0
@export var prompt_text: String = "[E] Interact"

# Camera reference is set by the player controller when this node is created
var _camera: Camera3D = null
var _current_target: Node = null
var _prompt_label: Label = null

func _ready() -> void:
	_create_prompt()

func _create_prompt() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)
	
	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.position = Vector2(0, 0)
	_prompt_label.size = Vector2(0, 0)
	_prompt_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt_label.offset_top = -60
	_prompt_label.offset_bottom = -20
	_prompt_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.text = ""
	canvas.add_child(_prompt_label)

func _process(_delta: float) -> void:
	if not _camera:
		return
	
	var space_state = get_world_3d().direct_space_state
	var center = _camera.get_viewport().size / 2.0
	var from = _camera.project_ray_origin(center)
	var to = from + _camera.project_ray_normal(center) * interaction_distance
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_parent()]  # Exclude the player
	
	var result = space_state.intersect_ray(query)
	
	if result and result.collider.has_method("interact"):
		_current_target = result.collider
		# Use custom prompt text if the object provides it
		if result.collider.has_method("get_interact_text"):
			_prompt_label.text = result.collider.get_interact_text()
		else:
			_prompt_label.text = prompt_text
	else:
		_current_target = null
		_prompt_label.text = ""

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_interact") or (event is InputEventKey and event.keycode == KEY_E and event.pressed):
		if _current_target and _current_target.has_method("interact"):
			_current_target.interact()
