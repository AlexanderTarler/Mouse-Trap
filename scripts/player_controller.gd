extends CharacterBody3D

## Stair climbing settings
@export var max_step_height: float = 0.7
@export var step_check_distance: float = 0.5

## Jump settings
@export var jump_velocity: float = 4.5

@export var walk_speed: float = 3.5
@export var run_speed: float = 6.5
@export var crouch_speed: float = 1.8
@export var mouse_sensitivity: float = 0.002
@export var head_bob_enabled: bool = true
@export var head_bob_frequency: float = 2.0
@export var head_bob_amplitude: float = 0.06

# Crouch settings
@export var standing_height: float = 1.8
@export var crouching_height: float = 0.8
@export var crouch_transition_speed: float = 10.0

# Flashlight settings (used as fallback if no flashlight script attached)
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
@onready var _photo_camera: Node = $CameraHolder/Camera3D/PhotoCamera
@onready var _interaction_manager: Node = $CameraHolder/InteractionManager
@onready var _physical_grab: Node = $CameraHolder/PhysicalGrab
@onready var footstep_audio: AudioStreamPlayer3D = $FootstepAudio if has_node("FootstepAudio") else null
@onready var floor_raycast: RayCast3D = $FloorRayCast if has_node("FloorRayCast") else null

@export var wood_footsteps: Array[AudioStream] = []
@export var grass_footsteps: Array[AudioStream] = []

var _current_speed: float
var _step_timer: float = 0.0
var _step_interval: float = 0.6
var _head_bob_time: float = 0.0
var _head_bob_active: bool = false
var _is_crouching: bool = false

# Flashlight
var _flashlight_on: bool = false
var _has_flashlight: bool = false

# Crosshair
var _crosshair: Control

# Footstep sound tracking
var _footstep_timer: float = 0.0
var _footstep_interval: float = 0.5

# (Removed unused debug raycast timer)

# Stair climbing state
var _was_on_floor: bool = false

# Sprint unlock — locked on Night 1 until the first chase begins
var sprint_unlocked: bool = false

# --- STANDOFF / CHARGE MECHANIC ---
## How long the player has been staring at the Entity with the flashlight on.
## 0.0 = not looking, 1.5+ = Entity charges.
var look_timer: float = 0.0

## Reference to the StandoffEffect node on the HUD
var _standoff_effect: Node = null

## Reference to the Entity node (found at runtime)
var _entity_node: Node = null

# Stamina system
var _stamina: float = 100.0
var _max_stamina: float = 100.0
var _is_running: bool = false
var _stamina_drain_rate: float = 5.625   # Points per second while running (62.5% slower than original 15.0)
var _stamina_regen_rate: float = 8.0    # Points per second while not running
var _stamina_exhausted: bool = false
var _stamina_exhausted_timer: float = 0.0
var _stamina_exhausted_delay: float = 1.5  # Seconds before regen starts after exhaustion
signal stamina_changed(stamina_percent: float)

# Noise system
var _noise_timer: float = 0.0

## Starting items to add to the player's inventory on game start.
## Drag ItemData resources (e.g. key_resource.tres, battery_resource.tres) here
## in the editor to give the player items at the beginning of the game.
@export var starting_items: Array[ItemData] = []

func _ready() -> void:
	# Add starting items to the Inventory autoload
	for item in starting_items:
		if item:
			Inventory.add_item(item)
			print("[Player] Added starting item to inventory: ", item.item_name)
	_current_speed = walk_speed
	floor_max_angle = deg_to_rad(60.0)
	floor_snap_length = 1.2
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	
	if _camera:
		_camera.far = camera_far
		_camera.near = camera_near
	if _flashlight:
		_flashlight.light_energy = flashlight_energy
		_flashlight.spot_range = flashlight_range
		# Flashlight starts disabled until the player picks up flashlight.tscn
		_flashlight.visible = false
		if _flashlight.has_method("toggle") and _flashlight.is_on:
			_flashlight.is_on = false
	
	if _interaction_manager and _interaction_manager.has_method("set_camera"):
		_interaction_manager.set_camera(_camera)
	elif _interaction_manager:
		_interaction_manager.set("_camera", _camera)
	
	if _physical_grab and _physical_grab.has_method("set_camera"):
		_physical_grab.set_camera(_camera)
	elif _physical_grab:
		_physical_grab.set("_camera", _camera)
	
	_create_crosshair()
	get_viewport().size_changed.connect(_rebuild_crosshair)
	_footstep_interval = 1.0 / walk_speed

func _create_crosshair() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	var container = Control.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(container)
	var center_x = 0.5
	var center_y = 0.5
	var line_length = 0.012
	var line_width = 0.002
	var gap = 0.004
	var color = Color(1, 1, 1, 0.6)
	
	var top = ColorRect.new()
	top.color = color
	top.size = Vector2(get_viewport().size.x * line_width, get_viewport().size.y * line_length)
	top.position = Vector2(get_viewport().size.x * center_x - top.size.x / 2, get_viewport().size.y * center_y - top.size.y - get_viewport().size.y * gap)
	container.add_child(top)
	
	var bottom = ColorRect.new()
	bottom.color = color
	bottom.size = Vector2(get_viewport().size.x * line_width, get_viewport().size.y * line_length)
	bottom.position = Vector2(get_viewport().size.x * center_x - bottom.size.x / 2, get_viewport().size.y * center_y + get_viewport().size.y * gap)
	container.add_child(bottom)
	
	var left = ColorRect.new()
	left.color = color
	left.size = Vector2(get_viewport().size.x * line_length, get_viewport().size.y * line_width)
	left.position = Vector2(get_viewport().size.x * center_x - left.size.x - get_viewport().size.x * gap, get_viewport().size.y * center_y - left.size.y / 2)
	container.add_child(left)
	
	var right = ColorRect.new()
	right.color = color
	right.size = Vector2(get_viewport().size.x * line_length, get_viewport().size.y * line_width)
	right.position = Vector2(get_viewport().size.x * center_x + get_viewport().size.x * gap, get_viewport().size.y * center_y - right.size.y / 2)
	container.add_child(right)
	_crosshair = container

func _rebuild_crosshair() -> void:
	if not _crosshair: return
	for child in _crosshair.get_children():
		_crosshair.remove_child(child)
		child.queue_free()
	
	var center_x = 0.5
	var center_y = 0.5
	var line_length = 0.012
	var line_width = 0.002
	var gap = 0.004
	var color = Color(1, 1, 1, 0.6)
	
	var top = ColorRect.new()
	top.color = color
	top.size = Vector2(get_viewport().size.x * line_width, get_viewport().size.y * line_length)
	top.position = Vector2(get_viewport().size.x * center_x - top.size.x / 2, get_viewport().size.y * center_y - top.size.y - get_viewport().size.y * gap)
	_crosshair.add_child(top)
	
	var bottom = ColorRect.new()
	bottom.color = color
	bottom.size = Vector2(get_viewport().size.x * line_width, get_viewport().size.y * line_length)
	bottom.position = Vector2(get_viewport().size.x * center_x - bottom.size.x / 2, get_viewport().size.y * center_y + get_viewport().size.y * gap)
	_crosshair.add_child(bottom)
	
	var left = ColorRect.new()
	left.color = color
	left.size = Vector2(get_viewport().size.x * line_length, get_viewport().size.y * line_width)
	left.position = Vector2(get_viewport().size.x * center_x - left.size.x - get_viewport().size.x * gap, get_viewport().size.y * center_y - left.size.y / 2)
	_crosshair.add_child(left)
	
	var right = ColorRect.new()
	right.color = color
	right.size = Vector2(get_viewport().size.x * line_length, get_viewport().size.y * line_width)
	right.position = Vector2(get_viewport().size.x * center_x + get_viewport().size.x * gap, get_viewport().size.y * center_y - right.size.y / 2)
	_crosshair.add_child(right)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_camera_holder.rotate_x(-event.relative.y * mouse_sensitivity)
		var rot = _camera_holder.rotation
		rot.x = clamp(rot.x, -1.4, 1.4)
		_camera_holder.rotation = rot
	
	if event.is_action_pressed("ui_cancel"):
		var inv_ui = get_node_or_null("/root/CottageHorror/InventoryUI")
		if not inv_ui: inv_ui = get_node_or_null("/root/Main/InventoryUI")
		if inv_ui and inv_ui.get("_is_open"): return
		
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	if event is InputEventKey and event.keycode == KEY_F and event.pressed:
		_toggle_flashlight()
	
	# ─── PHOTO CAMERA TOGGLE (R key) ──────────────────────────────────────
	# Pressing R toggles the PhotoCamera viewfinder on/off (only if equipped).
	# The CameraHUD is instantiated lazily inside photo_camera.gd's equip()
	# when the player first presses R, ensuring the scene tree is fully loaded.
	if event is InputEventKey and event.keycode == KEY_R and event.pressed:
		if _photo_camera and _photo_camera.is_equipped:
			_photo_camera.unequip()
		elif _photo_camera:
			_photo_camera.equip()
	
	# ─── CAMERA ZOOM (RMB) ────────────────────────────────────────────────
	# Hold RMB to zoom in when the PhotoCamera is equipped.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if _photo_camera and _photo_camera.is_equipped:
			_photo_camera.toggle_zoom(event.pressed)
	
	# ─── TAKE PHOTO (LMB) ─────────────────────────────────────────────────
	# Press LMB to take a photo when zoomed in with the PhotoCamera.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _photo_camera and _photo_camera.is_equipped and _photo_camera.is_zoomed:
			_photo_camera.take_photo()
	
	# ─── CAMERA HUD DEBUG TOGGLE (Y key) ──────────────────────────────────
	# Pressing Y loads and shows the CameraHUD overlay directly for debugging.
	if event is InputEventKey and event.keycode == KEY_Y and event.pressed:
		_toggle_camera_hud_debug()

## Called by flashlight_pickup.gd when the player picks up the flashlight item.
## Enables the player's built-in flashlight so they can toggle it with F.
func enable_flashlight() -> void:
	_has_flashlight = true
	_flashlight_on = false
	if _flashlight:
		_flashlight.visible = false
		if _flashlight.has_method("toggle") and _flashlight.is_on:
			_flashlight.is_on = false
	print("[Player] Flashlight acquired! Press F to toggle.")

## Called by camera_pickup.gd when the player picks up the Floppy Disk Camera.
## Marks the camera as available but does NOT equip it — the player must
## press R to toggle the viewfinder on/off.
func enable_camera() -> void:
	if _photo_camera:
		print("[Player] PhotoCamera acquired! Press R to toggle viewfinder.")
	else:
		print("[Player] WARNING: PhotoCamera node not found!")


## Toggles the CameraHUD overlay directly for debugging (Y key).
## Loads and shows the camera viewfinder HUD without needing the camera item.
var _camera_hud_debug = null
var _camera_hud_debug_active: bool = false

func _toggle_camera_hud_debug() -> void:
	if not _camera_hud_debug:
		var hud_scene = load("res://scenes/camera_hud.tscn")
		if hud_scene:
			_camera_hud_debug = hud_scene.instantiate()
			if is_inside_tree():
				get_tree().current_scene.add_child(_camera_hud_debug)
			else:
				get_window().add_child(_camera_hud_debug)
			print("[Player] CameraHUD debug instance created.")
		else:
			print("[Player] WARNING: Could not load camera_hud.tscn for debug!")
			return
	
	_camera_hud_debug_active = not _camera_hud_debug_active
	
	if _camera_hud_debug_active:
		if _camera_hud_debug.has_method("show_hud"):
			_camera_hud_debug.show_hud()
		print("[Player] CameraHUD debug shown (Y key).")
	else:
		if _camera_hud_debug.has_method("hide_hud"):
			_camera_hud_debug.hide_hud()
		print("[Player] CameraHUD debug hidden (Y key).")


func _toggle_flashlight() -> void:
	if not _has_flashlight:
		# Show a hint that the player needs to find the flashlight first
		print("[Player] You don't have a flashlight yet! Find one in the cabin.")
		return
	if not _flashlight: return
	if _flashlight.has_method("toggle"):
		_flashlight.toggle()
	else:
		_flashlight_on = not _flashlight_on
		_flashlight.visible = _flashlight_on

func _toggle_inventory() -> void:
	var inv_ui = get_node_or_null("/root/CottageHorror/InventoryUI")
	if not inv_ui: inv_ui = get_node_or_null("/root/Main/InventoryUI")
	if inv_ui and inv_ui.has_method("_open_inventory") and inv_ui.has_method("_close_inventory"):
		if inv_ui.get("_is_open"): inv_ui._close_inventory()
		else: inv_ui._open_inventory()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = jump_velocity
		make_noise(15.0, 1.0) # Jumping is loud!

	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C):
		if not _is_crouching: _is_crouching = true
	else:
		if _is_crouching: _is_crouching = false

	_is_running = Input.is_key_pressed(KEY_SHIFT) and sprint_unlocked and not _is_crouching and _stamina > 0.0 and not _stamina_exhausted
	
	if _is_crouching: _current_speed = crouch_speed
	elif _is_running: _current_speed = run_speed
	else: _current_speed = walk_speed
	
	# --- STAMINA DRAIN / REGEN ---
	if _is_running:
		# Drain stamina while running
		_stamina -= _stamina_drain_rate * delta
		if _stamina <= 0.0:
			_stamina = 0.0
			_stamina_exhausted = true
			_stamina_exhausted_timer = 0.0
	elif _stamina_exhausted:
		# Wait for exhaustion delay before regen starts
		_stamina_exhausted_timer += delta
		if _stamina_exhausted_timer >= _stamina_exhausted_delay:
			_stamina_exhausted = false
	else:
		# Regen stamina when not running
		_stamina += _stamina_regen_rate * delta
		if _stamina > _max_stamina:
			_stamina = _max_stamina
	
	stamina_changed.emit(_stamina / _max_stamina * 100.0)

	var input_dir := Vector2(
		-1.0 if Input.is_key_pressed(KEY_A) else (1.0 if Input.is_key_pressed(KEY_D) else 0.0),
		-1.0 if Input.is_key_pressed(KEY_W) else (1.0 if Input.is_key_pressed(KEY_S) else 0.0)
	)
	
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * _current_speed
		velocity.z = direction.z * _current_speed
		_head_bob_active = true
		
		# Emit noise while running
		if _is_running and is_on_floor():
			_noise_timer += delta
			if _noise_timer >= 0.5:
				make_noise(12.0, 0.5)
				_noise_timer = 0.0
	else:
		velocity.x = move_toward(velocity.x, 0, _current_speed)
		velocity.z = move_toward(velocity.z, 0, _current_speed)
		_head_bob_active = false
		_noise_timer = 0.0

	if _was_on_floor and direction.length() > 0 and is_on_floor():
		_try_step_up(direction)

	var landed = not _was_on_floor and is_on_floor()
	if landed: make_noise(15.0, 1.0) # Thud on landing

	move_and_slide()
	_was_on_floor = is_on_floor()
	_update_crouch(delta)
	
	if velocity.length() > 0.5 and is_on_floor():
		_step_timer -= delta
		if _step_timer <= 0.0:
			_play_surface_footstep()
			# Dynamic footstep speed: when sprinting, footsteps play twice as fast
			# (interval cut in half) to match the increased movement speed.
			if _is_running and sprint_unlocked:
				_step_timer = _step_interval * 0.5
			else:
				_step_timer = _step_interval
	else:
		_step_timer = 0.0
	
	if head_bob_enabled and _head_bob_active and is_on_floor() and not _is_crouching:
		_head_bob_time += delta * _current_speed * head_bob_frequency
		var bob_offset = Vector3(head_bob_amplitude * cos(_head_bob_time * 0.5) * 0.3, head_bob_amplitude * sin(_head_bob_time), 0)
		_camera.position = bob_offset
	else:
		_head_bob_time = 0.0
		_camera.position = _camera.position.lerp(Vector3.ZERO, delta * 10.0)

func _try_step_up(direction: Vector3) -> void:
	var space_state = get_world_3d().direct_space_state
	if not space_state or not _collision_shape or not _collision_shape.shape: return
	
	var capsule: CapsuleShape3D = _collision_shape.shape as CapsuleShape3D
	var capsule_center_y = global_position.y + _collision_shape.position.y
	var capsule_bottom_y = capsule_center_y - capsule.height / 2.0
	
	var down_here_start = Vector3(global_position.x, capsule_bottom_y + 0.1, global_position.z)
	var down_here_end = Vector3(global_position.x, capsule_bottom_y - max_step_height - 0.5, global_position.z)
	var here_query = PhysicsRayQueryParameters3D.create(down_here_start, down_here_end)
	here_query.exclude = [self]
	
	var here_result = space_state.intersect_ray(here_query)
	if here_result.is_empty(): return
	var floor_y = here_result.position.y
	
	var ahead_pos = global_position + direction * (step_check_distance + capsule.radius * 0.5)
	var down_ahead_start = Vector3(ahead_pos.x, capsule_bottom_y + max_step_height + 0.5, ahead_pos.z)
	var down_ahead_end = Vector3(ahead_pos.x, capsule_bottom_y - 0.5, ahead_pos.z)
	var ahead_query = PhysicsRayQueryParameters3D.create(down_ahead_start, down_ahead_end)
	ahead_query.exclude = [self]
	
	var ahead_result = space_state.intersect_ray(ahead_query)
	if ahead_result.is_empty(): return
	var ahead_floor_y = ahead_result.position.y
	var step_height = ahead_floor_y - floor_y
	
	if step_height <= 0.01 or step_height > max_step_height: return
	
	var check_height = capsule_bottom_y + max_step_height + 0.1
	var check_start = Vector3(global_position.x, check_height, global_position.z)
	var check_end = check_start + direction * (step_check_distance + capsule.radius)
	var check_query = PhysicsRayQueryParameters3D.create(check_start, check_end)
	check_query.exclude = [self]
	
	if not space_state.intersect_ray(check_query).is_empty(): return
	
	velocity.y = sqrt(2.0 * get_gravity().length() * step_height) * 1.2
	global_position += direction * 0.02

func _play_surface_footstep() -> void:
	if not footstep_audio: return
	var chosen_stream: AudioStream = null
	
	if floor_raycast and floor_raycast.is_colliding():
		var surface_node: Node = floor_raycast.get_collider()
		var found_group := false
		while surface_node and not found_group:
			if surface_node.is_in_group("wood") and wood_footsteps.size() > 0:
				chosen_stream = wood_footsteps.pick_random()
				found_group = true
			elif surface_node.is_in_group("grass") and grass_footsteps.size() > 0:
				chosen_stream = grass_footsteps.pick_random()
				found_group = true
			else:
				surface_node = surface_node.get_parent()
	
	if not chosen_stream and grass_footsteps.size() > 0:
		chosen_stream = grass_footsteps.pick_random()
	
	if chosen_stream:
		footstep_audio.stream = chosen_stream
		footstep_audio.pitch_scale = randf_range(0.85, 1.15)
		footstep_audio.play()

func _update_crouch(delta: float) -> void:
	var target_height = crouching_height if _is_crouching else standing_height
	if not _collision_shape or not _collision_shape.shape: return
	var shape: CapsuleShape3D = _collision_shape.shape as CapsuleShape3D
	shape.height = lerp(shape.height, target_height, delta * crouch_transition_speed)
	
	var col_pos = _collision_shape.position
	col_pos.y = shape.height / 2.0 + shape.radius
	_collision_shape.position = col_pos
	
	var target_cam_height = target_height - 0.1
	var cam_pos = _camera_holder.position
	cam_pos.y = lerp(cam_pos.y, target_cam_height, delta * crouch_transition_speed)
	_camera_holder.position = cam_pos

# --- STANDOFF / CHARGE: LOOK TIMER & CAMERA SHAKE ---
func _process(delta: float) -> void:
	# Find the StandoffEffect node on the HUD (lazy init)
	if not _standoff_effect:
		var hud = get_node_or_null("/root/CottageHorror/HorrorHUD")
		if not hud:
			hud = get_node_or_null("/root/Main/HorrorHUD")
		if hud:
			_standoff_effect = hud.get_node_or_null("StandoffText")
	
	# Find the Entity node (lazy init)
	if not _entity_node:
		_entity_node = get_tree().get_first_node_in_group("entity")
	
	# Check if the flashlight is ON and we're looking at the Entity
	var is_looking_at_entity = _is_flashlight_on_entity()
	
	if is_looking_at_entity:
		# Increase look_timer while staring at the Entity with flashlight
		look_timer += delta
		
		# Clamp to max meaningful value (1.5s triggers charge)
		if look_timer > 2.0:
			look_timer = 2.0
		
		# Dynamic camera shake — intensity scales with look_timer
		var shake_intensity = look_timer / 1.5  # 0.0 to 1.0 at 1.5s
		if shake_intensity > 0.1:
			var shake = shake_intensity * 0.02  # Max 0.02 radians (~1 degree)
			_camera.h_offset = randf_range(-shake, shake)
			_camera.v_offset = randf_range(-shake, shake)
		else:
			_camera.h_offset = 0.0
			_camera.v_offset = 0.0
		
		# Notify the Entity that it's being stared at (triggers STANDOFF state)
		if _entity_node and _entity_node.has_method("on_player_stare"):
			_entity_node.on_player_stare(look_timer)
	else:
		# Not looking at the Entity — decay look_timer
		if look_timer > 0.0:
			look_timer -= delta * 2.0  # Decay twice as fast as it builds
			if look_timer < 0.0:
				look_timer = 0.0
				_camera.h_offset = 0.0
				_camera.v_offset = 0.0
			
			# Notify the Entity that stare is ending
			if _entity_node and _entity_node.has_method("on_player_stare"):
				_entity_node.on_player_stare(look_timer)
		else:
			_camera.h_offset = 0.0
			_camera.v_offset = 0.0
	
	# Update the StandoffEffect with the current look_timer
	if _standoff_effect and _standoff_effect.has_method("update_look_timer"):
		_standoff_effect.update_look_timer(look_timer)


## Checks if the player's flashlight is currently shining on the Entity.
## Uses a RayCast3D from the center of the camera to detect the Entity.
func _is_flashlight_on_entity() -> bool:
	# Flashlight must be on
	if not _flashlight or not _has_flashlight:
		return false
	if not _flashlight.is_on:
		return false
	
	if not _entity_node or not is_instance_valid(_entity_node):
		return false
	
	# Raycast from camera center to check if we're looking at the Entity
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return false
	
	var viewport_size = _camera.get_viewport().size
	var center = viewport_size / 2.0
	var from = _camera.project_ray_origin(center)
	var to = from + _camera.project_ray_normal(center) * 30.0  # Max range
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [self]
	
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return false
	
	var collider = result.collider
	
	# Walk up the parent chain to check if we hit the Entity
	var current = collider
	while current:
		if current == _entity_node:
			return true
		if current.is_in_group("entity"):
			return true
		current = current.get_parent()
	
	return false


# --- NEW NOISE SYSTEM EMITTER ---
func make_noise(radius: float, intensity: float = 1.0) -> void:
	var entity = get_tree().get_first_node_in_group("entity")
	if entity and entity.has_method("hear_noise"):
		entity.hear_noise(global_position, radius, intensity)
