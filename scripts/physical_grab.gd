extends Node3D

## Physical grab system.
## Hold E (0.5s) to grab a RigidBody3D in front of the camera and move it around physically.
## Quick tap E to interact with objects (delegates to InteractionManager).

@export var grab_distance: float = 3.0
@export var hold_distance: float = 1.5
@export var max_grab_mass: float = 20.0

# How long E must be held before entering grab mode (seconds)
@export var hold_threshold: float = 0.5

var _camera: Camera3D = null
var _grabbed_body: RigidBody3D = null
var _e_held_time: float = 0.0
var _e_is_held: bool = false
var _is_grabbing: bool = false
var _has_passed_threshold: bool = false
var _prompt_label: Label = null

# Saved gravity scale to restore on release
var _saved_gravity_scale: float = 1.0


func _ready() -> void:
	_create_prompt()


func _create_prompt() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 6
	add_child(canvas)
	
	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.position = Vector2(0, 0)
	_prompt_label.size = Vector2(0, 0)
	_prompt_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt_label.offset_top = -90
	_prompt_label.offset_bottom = -50
	_prompt_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.9))
	_prompt_label.add_theme_font_size_override("font_size", 14)
	_prompt_label.text = ""
	canvas.add_child(_prompt_label)


func set_camera(cam: Camera3D) -> void:
	_camera = cam


func _input(event: InputEvent) -> void:
	# Only handle E key
	if not (event is InputEventKey and event.keycode == KEY_E):
		return
	
	if event.pressed and not _e_is_held:
		# E just pressed - start tracking hold time
		_e_is_held = true
		_e_held_time = 0.0
		_has_passed_threshold = false
		
	elif not event.pressed and _e_is_held:
		# E released
		_e_is_held = false
		
		if _is_grabbing:
			# Release the grabbed object
			_drop_object()
		elif not _has_passed_threshold:
			# Quick tap! Fire interact() on the current target
			_fire_interact()


func _process(delta: float) -> void:
	if not _camera:
		return
	
	# Track how long E has been held
	if _e_is_held and not _is_grabbing:
		_e_held_time += delta
		
		if _e_held_time >= hold_threshold and not _has_passed_threshold:
			_has_passed_threshold = true
			# Try to grab an object
			_try_grab()
	
	# Update prompt text
	_update_prompt()


func _physics_process(delta: float) -> void:
	# If we're holding an object, move it toward the target position
	if _is_grabbing and _grabbed_body:
		_update_grab(delta)


## Computes the target position in front of the camera.
func _get_target_position() -> Vector3:
	if not _camera:
		return global_position
	var camera_forward = -_camera.global_transform.basis.z
	return _camera.global_position + camera_forward * hold_distance


## Moves the grabbed object toward the target position using smooth interpolation.
## Uses global_transform.origin directly (teleport) with collision checks disabled
## to avoid physics fighting. The object is kinematic while held.
func _update_grab(delta: float) -> void:
	if not _grabbed_body:
		return
	
	var target_pos = _get_target_position()
	var current_pos = _grabbed_body.global_position
	
	# Smoothly interpolate toward the target
	var new_pos = current_pos.lerp(target_pos, min(1.0, delta * 15.0))
	
	# Use move_and_collide style: set position directly but freeze physics
	_grabbed_body.global_position = new_pos
	
	# Dampen any residual velocity
	_grabbed_body.linear_velocity = Vector3.ZERO
	_grabbed_body.angular_velocity = Vector3.ZERO


## Fires interact() on the current target via the InteractionManager.
func _fire_interact() -> void:
	var interaction_manager = get_node_or_null("../InteractionManager")
	if not interaction_manager:
		return
	
	# Get the current target from InteractionManager using the public getter
	var target = interaction_manager.get_current_target()
	if target and target.has_method("interact"):
		target.interact()


func _try_grab() -> void:
	if not _camera:
		return
	
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return
	
	var viewport_size = _camera.get_viewport().size
	var center = viewport_size / 2.0
	var from = _camera.project_ray_origin(center)
	var to = from + _camera.project_ray_normal(center) * grab_distance
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	# Exclude the player
	var player = _find_player()
	if player:
		query.exclude = [player]
	
	var result = space_state.intersect_ray(query)
	
	if result.is_empty():
		return
	
	var body = result.collider
	
	# Only grab RigidBody3D
	if not (body is RigidBody3D):
		return
	
	# Check mass
	if body.mass > max_grab_mass:
		return
	
	# Don't grab the player itself
	if body == player:
		return
	
	# Success - grab the object
	_grab_object(body)


func _grab_object(body: RigidBody3D) -> void:
	_grabbed_body = body
	_is_grabbing = true
	
	# Save the original gravity scale
	_saved_gravity_scale = body.gravity_scale
	
	# Freeze the body so it doesn't fall or collide while held
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	
	# Stop any existing motion
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO


func _drop_object() -> void:
	if not _is_grabbing or not _grabbed_body:
		return
	
	# Unfreeze the body and restore gravity
	_grabbed_body.freeze = false
	_grabbed_body.gravity_scale = _saved_gravity_scale
	
	# Give it a tiny nudge forward so it doesn't just drop straight down
	var camera_forward = -_camera.global_transform.basis.z if _camera else Vector3.FORWARD
	_grabbed_body.linear_velocity = camera_forward * 0.5
	
	_grabbed_body = null
	_is_grabbing = false


func _update_prompt() -> void:
	if not _prompt_label:
		return
	
	if _is_grabbing:
		_prompt_label.text = "[E] Release"
	elif _e_is_held and not _has_passed_threshold:
		# Show what we're looking at while holding E
		var target = _find_grabbable_target()
		if target:
			_prompt_label.text = "Grabbing " + target.name + "..."
		else:
			_prompt_label.text = ""
	else:
		_prompt_label.text = ""


func _find_grabbable_target() -> Node:
	if not _camera:
		return null
	
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return null
	
	var center = _camera.get_viewport().size / 2.0
	var from = _camera.project_ray_origin(center)
	var to = from + _camera.project_ray_normal(center) * grab_distance
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var player = _find_player()
	if player:
		query.exclude = [player]
	
	var result = space_state.intersect_ray(query)
	
	if result.is_empty():
		return null
	
	var body = result.collider
	if body is RigidBody3D and body.mass <= max_grab_mass:
		return body
	
	return null


func _find_player() -> Node:
	var parent = get_parent()
	while parent:
		if parent is CharacterBody3D:
			return parent
		parent = parent.get_parent()
	return null
