extends CharacterBody3D

## Stair climbing settings
@export var max_step_height: float = 0.7
@export var step_check_distance: float = 0.5

## Jump settings
@export var jump_velocity: float = 4.5

@export var walk_speed: float = 3.5
@export var crouch_speed: float = 1.8
@export var mouse_sensitivity: float = 0.002
@export var head_bob_enabled: bool = true
@export var head_bob_frequency: float = 2.0
@export var head_bob_amplitude: float = 0.06

# Crouch settings
@export var standing_height: float = 1.8
@export var crouching_height: float = 0.8
@export var crouch_transition_speed: float = 10.0

# Flashlight settings
@export var flashlight_energy: float = 5.0
@export var flashlight_range: float = 10.0

# Camera settings
@export var camera_far: float = 500.0
@export var camera_near: float = 0.1

# References to scene nodes
@onready var _camera: Camera3D = $CameraHolder/Camera3D
@onready var _camera_holder: Node3D = $CameraHolder
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _flashlight: SpotLight3D = $CameraHolder/Camera3D/Flashlight
@onready var _interaction_manager: Node = $CameraHolder/InteractionManager

var _mouse_captured: bool = false
var _current_speed: float
var _head_bob_time: float = 0.0
var _head_bob_active: bool = false
var _is_crouching: bool = false

# Flashlight
var _flashlight_on: bool = true

# Crosshair
var _crosshair: Control

# Footstep sound tracking
var _footstep_timer: float = 0.0
var _footstep_interval: float = 0.5

# Stair climbing state
var _was_on_floor: bool = false


func _ready() -> void:
	_current_speed = walk_speed
	
	# Configure CharacterBody3D for stair climbing
	floor_max_angle = deg_to_rad(60.0)
	floor_snap_length = 1.2
	
	# Capture mouse immediately
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_mouse_captured = true
	
	# Add to player group for entity tracking
	add_to_group("player")
	
	# Apply camera settings from exports
	if _camera:
		_camera.far = camera_far
		_camera.near = camera_near
	
	# Apply flashlight settings from exports
	if _flashlight:
		_flashlight.light_energy = flashlight_energy
		_flashlight.spot_range = flashlight_range
	
	# Pass camera reference to interaction manager
	if _interaction_manager and _interaction_manager.has_method("set_camera"):
		_interaction_manager.set_camera(_camera)
	elif _interaction_manager:
		_interaction_manager.set("_camera", _camera)
	
	# Create crosshair overlay
	_create_crosshair()
	
	# Rebuild crosshair on window resize
	get_viewport().size_changed.connect(_rebuild_crosshair)
	
	# Initialize footstep interval based on speed
	_footstep_interval = 1.0 / walk_speed


func _create_crosshair() -> void:
	# Create a CanvasLayer for the crosshair
	var canvas = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	
	# Create a container control
	var container = Control.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(container)
	
	# Crosshair settings
	var center_x = 0.5
	var center_y = 0.5
	var line_length = 0.012
	var line_width = 0.002
	var gap = 0.004
	var color = Color(1, 1, 1, 0.6)
	
	# Top line
	var top = ColorRect.new()
	top.color = color
	top.size = Vector2(
		get_viewport().size.x * line_width,
		get_viewport().size.y * line_length
	)
	top.position = Vector2(
		get_viewport().size.x * center_x - top.size.x / 2,
		get_viewport().size.y * center_y - top.size.y - get_viewport().size.y * gap
	)
	container.add_child(top)
	
	# Bottom line
	var bottom = ColorRect.new()
	bottom.color = color
	bottom.size = Vector2(
		get_viewport().size.x * line_width,
		get_viewport().size.y * line_length
	)
	bottom.position = Vector2(
		get_viewport().size.x * center_x - bottom.size.x / 2,
		get_viewport().size.y * center_y + get_viewport().size.y * gap
	)
	container.add_child(bottom)
	
	# Left line
	var left = ColorRect.new()
	left.color = color
	left.size = Vector2(
		get_viewport().size.x * line_length,
		get_viewport().size.y * line_width
	)
	left.position = Vector2(
		get_viewport().size.x * center_x - left.size.x - get_viewport().size.x * gap,
		get_viewport().size.y * center_y - left.size.y / 2
	)
	container.add_child(left)
	
	# Right line
	var right = ColorRect.new()
	right.color = color
	right.size = Vector2(
		get_viewport().size.x * line_length,
		get_viewport().size.y * line_width
	)
	right.position = Vector2(
		get_viewport().size.x * center_x + get_viewport().size.x * gap,
		get_viewport().size.y * center_y - right.size.y / 2
	)
	container.add_child(right)
	
	# Store reference to update on resize
	_crosshair = container


## Rebuilds the crosshair when the window is resized.
func _rebuild_crosshair() -> void:
	if not _crosshair:
		return
	# Remove old crosshair children and recreate
	for child in _crosshair.get_children():
		_crosshair.remove_child(child)
		child.queue_free()
	
	# Crosshair settings
	var center_x = 0.5
	var center_y = 0.5
	var line_length = 0.012
	var line_width = 0.002
	var gap = 0.004
	var color = Color(1, 1, 1, 0.6)
	
	# Top line
	var top = ColorRect.new()
	top.color = color
	top.size = Vector2(
		get_viewport().size.x * line_width,
		get_viewport().size.y * line_length
	)
	top.position = Vector2(
		get_viewport().size.x * center_x - top.size.x / 2,
		get_viewport().size.y * center_y - top.size.y - get_viewport().size.y * gap
	)
	_crosshair.add_child(top)
	
	# Bottom line
	var bottom = ColorRect.new()
	bottom.color = color
	bottom.size = Vector2(
		get_viewport().size.x * line_width,
		get_viewport().size.y * line_length
	)
	bottom.position = Vector2(
		get_viewport().size.x * center_x - bottom.size.x / 2,
		get_viewport().size.y * center_y + get_viewport().size.y * gap
	)
	_crosshair.add_child(bottom)
	
	# Left line
	var left = ColorRect.new()
	left.color = color
	left.size = Vector2(
		get_viewport().size.x * line_length,
		get_viewport().size.y * line_width
	)
	left.position = Vector2(
		get_viewport().size.x * center_x - left.size.x - get_viewport().size.x * gap,
		get_viewport().size.y * center_y - left.size.y / 2
	)
	_crosshair.add_child(left)
	
	# Right line
	var right = ColorRect.new()
	right.color = color
	right.size = Vector2(
		get_viewport().size.x * line_length,
		get_viewport().size.y * line_width
	)
	right.position = Vector2(
		get_viewport().size.x * center_x + get_viewport().size.x * gap,
		get_viewport().size.y * center_y - right.size.y / 2
	)
	_crosshair.add_child(right)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		# Horizontal mouse movement rotates the player
		rotate_y(-event.relative.x * mouse_sensitivity)
		# Vertical mouse movement rotates the camera holder
		_camera_holder.rotate_x(-event.relative.y * mouse_sensitivity)
		var rot = _camera_holder.rotation
		rot.x = clamp(rot.x, -1.4, 1.4)
		_camera_holder.rotation = rot
	
	if event.is_action_pressed("ui_cancel"):
		if _mouse_captured:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_mouse_captured = false
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_mouse_captured = true
	
	# Toggle flashlight with F key
	if event is InputEventKey and event.keycode == KEY_F and event.pressed:
		_toggle_flashlight()
	
	# DEBUG: Press Q to raycast and print info about the collider you're facing
	if event is InputEventKey and event.keycode == KEY_Q and event.pressed:
		_debug_raycast_collider()


func _toggle_flashlight() -> void:
	if not _flashlight:
		return
	_flashlight_on = not _flashlight_on
	_flashlight.visible = _flashlight_on


func _physics_process(delta: float) -> void:
	# Add the gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump (press Space to jump)
	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = jump_velocity

	# Handle crouch toggle (press Ctrl or C to toggle)
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C):
		if not _is_crouching:
			_is_crouching = true
	else:
		if _is_crouching:
			_is_crouching = false

	# No sprint in horror mode - just walk or crouch
	if _is_crouching:
		_current_speed = crouch_speed
	else:
		_current_speed = walk_speed

	# Get the input direction using WASD
	var input_dir := Vector2(
		-1.0 if Input.is_key_pressed(KEY_A) else (1.0 if Input.is_key_pressed(KEY_D) else 0.0),
		-1.0 if Input.is_key_pressed(KEY_W) else (1.0 if Input.is_key_pressed(KEY_S) else 0.0)
	)
	
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * _current_speed
		velocity.z = direction.z * _current_speed
		_head_bob_active = true
	else:
		velocity.x = move_toward(velocity.x, 0, _current_speed)
		velocity.z = move_toward(velocity.z, 0, _current_speed)
		_head_bob_active = false

	# --- Stair climbing: Step-up check ---
	# Perform step-up BEFORE move_and_slide() to lift the player over steps
	if _was_on_floor and direction.length() > 0 and is_on_floor():
		_try_step_up(direction)

	move_and_slide()

	# Store floor state for next frame (after move_and_slide)
	_was_on_floor = is_on_floor()

	
	# Handle crouch collision shape and camera height
	_update_crouch(delta)
	
	# Footstep sounds
	if _head_bob_active and is_on_floor():
		_footstep_timer -= delta
		if _footstep_timer <= 0.0:
			_footstep_timer = _footstep_interval * (crouch_speed / _current_speed if _is_crouching else 1.0)
			_play_footstep()
	else:
		_footstep_timer = 0.0
	
	# Head bob effect
	if head_bob_enabled and _head_bob_active and is_on_floor() and not _is_crouching:
		_head_bob_time += delta * _current_speed * head_bob_frequency
		var bob_offset = Vector3(
			head_bob_amplitude * cos(_head_bob_time * 0.5) * 0.3,
			head_bob_amplitude * sin(_head_bob_time),
			0
		)
		_camera.position = bob_offset
	else:
		_head_bob_time = 0.0
		# Smoothly return camera to center
		_camera.position = _camera.position.lerp(Vector3.ZERO, delta * 10.0)


## Attempts to step up onto stairs or small obstacles in the movement direction.
## Uses a floor-height comparison approach:
##   1. Casts down at the player's current position to get the floor height.
##   2. Casts down ahead of the player to get the floor height on the step.
##   3. If the floor ahead is higher (within max_step_height), applies a smooth
##      vertical velocity boost so move_and_slide() carries the player up.
##
## This works with merged collision meshes (like the cabin FBX imports) where
## the stairs are part of a single StaticBody and have horizontal normals on top.
func _try_step_up(direction: Vector3) -> void:
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return
	
	# Get the capsule shape info for positioning the raycasts
	if not _collision_shape or not _collision_shape.shape:
		return
	var capsule: CapsuleShape3D = _collision_shape.shape as CapsuleShape3D
	if not capsule:
		return
	
	# Calculate the bottom of the capsule (where the player's "feet" are)
	# The capsule's position is at its center, so bottom = pos.y - height/2
	var capsule_center_y = global_position.y + _collision_shape.position.y
	var capsule_bottom_y = capsule_center_y - capsule.height / 2.0
	
	# --- RAY 1: Cast down at current position to get the floor height ---
	var down_here_start = Vector3(global_position.x, capsule_bottom_y + 0.1, global_position.z)
	var down_here_end = Vector3(global_position.x, capsule_bottom_y - max_step_height - 0.5, global_position.z)
	
	var here_query = PhysicsRayQueryParameters3D.create(down_here_start, down_here_end)
	here_query.collide_with_areas = false
	here_query.collide_with_bodies = true
	here_query.exclude = [self]
	
	var here_result = space_state.intersect_ray(here_query)
	if here_result.is_empty():
		return
	
	var floor_y = here_result.position.y
	
	# --- RAY 2: Cast down ahead of the player to check floor height on the step ---
	var ahead_pos = global_position + direction * (step_check_distance + capsule.radius * 0.5)
	var down_ahead_start = Vector3(ahead_pos.x, capsule_bottom_y + max_step_height + 0.5, ahead_pos.z)
	var down_ahead_end = Vector3(ahead_pos.x, capsule_bottom_y - 0.5, ahead_pos.z)
	
	var ahead_query = PhysicsRayQueryParameters3D.create(down_ahead_start, down_ahead_end)
	ahead_query.collide_with_areas = false
	ahead_query.collide_with_bodies = true
	ahead_query.exclude = [self]
	
	var ahead_result = space_state.intersect_ray(ahead_query)
	if ahead_result.is_empty():
		return
	
	var ahead_floor_y = ahead_result.position.y
	
	# Calculate the height difference
	var step_height = ahead_floor_y - floor_y
	
	# Only step up if the floor ahead is higher (a step) and within max_step_height
	if step_height <= 0.01 or step_height > max_step_height:
		return
	
	# --- RAY 3: Check for headroom above the step ---
	# Cast forward from above the step height to make sure there's space
	var check_height = capsule_bottom_y + max_step_height + 0.1
	var check_start = Vector3(global_position.x, check_height, global_position.z)
	var check_end = check_start + direction * (step_check_distance + capsule.radius)
	
	var check_query = PhysicsRayQueryParameters3D.create(check_start, check_end)
	check_query.collide_with_areas = false
	check_query.collide_with_bodies = true
	check_query.exclude = [self]
	
	var check_result = space_state.intersect_ray(check_query)
	if not check_result.is_empty():
		# Something is blocking the headroom - can't step up
		return
	
	# --- Apply a smooth vertical velocity boost ---
	# Calculate the velocity needed to reach the step height using physics
	velocity.y = sqrt(2.0 * get_gravity().length() * step_height) * 1.2
	# Nudge forward slightly to help clear the step edge
	global_position += direction * 0.02


func _play_footstep() -> void:
	if Engine.has_singleton("HorrorSoundManager"):
		var sm = Engine.get_singleton("HorrorSoundManager")
		sm.play_footstep_at("wooden", global_position)


## DEBUG: Raycasts from the camera center and prints info about the hit collider.
func _debug_raycast_collider() -> void:
	if not _camera:
		return
	
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return
	
	var camera_center = _camera.global_position
	var camera_forward = -_camera.global_transform.basis.z
	
	var query = PhysicsRayQueryParameters3D.create(camera_center, camera_center + camera_forward * 10.0)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	
	if result.is_empty():
		print("DEBUG: No collider hit within 10 meters")
		return
	
	var collider = result.get("collider", null)
	var position = result.get("position", Vector3.ZERO)
	var normal = result.get("normal", Vector3.ZERO)
	
	print("=== DEBUG RAYCAST HIT ===")
	print("  Position: ", position)
	print("  Normal: ", normal)
	
	if collider:
		print("  Collider Type: ", collider.get_class())
		print("  Collider Name: ", collider.name)
		print("  Collider Path: ", collider.get_path())
		
		# Walk up the parent chain to find the StaticBody or root
		var parent = collider.get_parent()
		var depth = 0
		while parent and depth < 10:
			print("    Parent[", depth, "]: ", parent.name, " (", parent.get_class(), ")")
			parent = parent.get_parent()
			depth += 1
		
		# If it's a CollisionShape3D, print its shape info
		if collider is CollisionShape3D:
			var shape = collider.shape
			if shape:
				print("  Shape Type: ", shape.get_class())
				if shape is BoxShape3D:
					print("  Box Size: ", shape.size)
				elif shape is ConcavePolygonShape3D:
					print("  ConcavePolygon (trimesh) - face count: ", shape.get_faces().size() if shape.get_faces() else 0)
	else:
		print("  Collider: null")
	
	print("==========================")


func _update_crouch(delta: float) -> void:
	var target_height = crouching_height if _is_crouching else standing_height
	
	# Smoothly interpolate the collision shape height
	if not _collision_shape or not _collision_shape.shape:
		return
	var shape: CapsuleShape3D = _collision_shape.shape as CapsuleShape3D
	shape.height = lerp(shape.height, target_height, delta * crouch_transition_speed)
	
	# Adjust the collision shape position so the bottom stays on the ground
	# Capsule total height = height + 2 * radius, center is at half of that
	var col_pos = _collision_shape.position
	col_pos.y = shape.height / 2.0 + shape.radius
	_collision_shape.position = col_pos
	
	# Smoothly move the camera holder to the correct eye height
	var target_cam_height = target_height - 0.1
	var cam_pos = _camera_holder.position
	cam_pos.y = lerp(cam_pos.y, target_cam_height, delta * crouch_transition_speed)
	_camera_holder.position = cam_pos
