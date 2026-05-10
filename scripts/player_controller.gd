extends CharacterBody3D

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

var _camera: Camera3D
var _camera_holder: Node3D
var _mouse_captured: bool = false
var _current_speed: float
var _head_bob_time: float = 0.0
var _head_bob_active: bool = false
var _is_crouching: bool = false

# Flashlight
var _flashlight: SpotLight3D = null
var _flashlight_on: bool = true

# Crosshair
var _crosshair: Control

# Footstep sound tracking
var _footstep_timer: float = 0.0
var _footstep_interval: float = 0.5

func _ready() -> void:
	_camera_holder = $CameraHolder as Node3D
	_camera = $CameraHolder/Camera3D as Camera3D
	_current_speed = walk_speed
	# Capture mouse immediately
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_mouse_captured = true
	
	# Add to player group for entity tracking
	add_to_group("player")
	
	# Create flashlight
	_create_flashlight()
	
	# Create crosshair overlay
	_create_crosshair()
	
	# Rebuild crosshair on window resize
	get_viewport().size_changed.connect(_rebuild_crosshair)
	
	# Initialize footstep interval based on speed
	_footstep_interval = 1.0 / walk_speed

func _create_flashlight() -> void:
	_flashlight = SpotLight3D.new()
	_flashlight.light_color = Color(1, 0.95, 0.8, 1)
	_flashlight.light_energy = flashlight_energy
	_flashlight.spot_range = flashlight_range
	_flashlight.spot_angle = 45.0
	_flashlight.spot_attenuation = 1.0
	_flashlight.shadow_enabled = true
	_flashlight.shadow_bias = 0.1
	_camera.add_child(_flashlight)
	# Set transform after adding as child
	_flashlight.transform = Transform3D(
		Basis().rotated(Vector3.RIGHT, deg_to_rad(5)),
		Vector3(0.2, -0.1, -0.3)
	)

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

	move_and_slide()
	
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
	var shape: BoxShape3D = $CollisionShape3D.shape as BoxShape3D
	var shape_size = shape.size
	shape_size.y = lerp(shape_size.y, target_height, delta * crouch_transition_speed)
	shape.size = shape_size
	
	# Adjust the collision shape position so the bottom stays on the ground
	var col_pos = $CollisionShape3D.position
	col_pos.y = shape.size.y / 2.0
	$CollisionShape3D.position = col_pos
	
	# Smoothly move the camera holder to the correct eye height
	var target_cam_height = target_height - 0.1
	var cam_pos = _camera_holder.position
	cam_pos.y = lerp(cam_pos.y, target_cam_height, delta * crouch_transition_speed)
	_camera_holder.position = cam_pos
