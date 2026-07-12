extends Node3D

## Physical grab system.
## Hold E (0.5s) to grab a RigidBody3D in front of the camera and move it around physically.
## Quick tap E to interact with objects (delegates to InteractionManager).
## Hold E (1s) on a locked/unlocked door to toggle its lock state (via toggle_lock()).
##
## SPECIAL CASE — PortableLamp (portable_trap group):
## The Portable High-Voltage Lamp uses a dedicated carry system instead of the
## generic grab. When the player interacts with a node in the "portable_trap"
## group, PhysicalGrab calls lamp.pick_up() / lamp.drop_trap() which manages
## its own freeze state, collision exclusion, and lerp loop. This gives the
## lamp a more natural "carry in front of you" feel (like Amnesia/Half-Life).

@export var grab_distance: float = 3.0
@export var hold_distance: float = 1.5
@export var max_grab_mass: float = 20.0

# How long E must be held before entering grab mode (seconds)
@export var hold_threshold: float = 0.5

# How long E must be held on a door to toggle its lock (seconds)
@export var door_lock_threshold: float = 1.0

var _camera: Camera3D = null
var _grabbed_body: RigidBody3D = null
var _e_held_time: float = 0.0
var _e_is_held: bool = false
var _is_grabbing: bool = false
var _has_passed_threshold: bool = false
var _prompt_label: Label = null

# Door lock hold tracking
var _door_lock_target: Node = null
var _has_passed_door_threshold: bool = false

# Saved gravity scale to restore on release
var _saved_gravity_scale: float = 1.0

## Reference to the PortableLamp being carried (if any).
## When non-null, the lamp manages its own physics via pick_up()/drop_trap().
var _carried_lamp: Node = null

## Reference to the CarryMarker (Marker3D) child of the Camera3D.
## The lamp lerps its position/rotation to match this marker while carried.
## NOTE: This is NOT set in @onready because _camera is set externally via
## set_camera() in player_controller._ready(), which runs AFTER this node's
## _ready(). Instead, we lazily create it on first use in _get_or_create_carry_marker().
var _carry_marker: Marker3D = null




func _ready() -> void:
	add_to_group("physical_grab")
	_create_prompt()



## Finds or creates a Marker3D named "CarryMarker" as a child of the camera.
## This marker defines where the PortableLamp sits in front of the player
## while being carried. Positioned ~0.5m in front and ~0.3m below the camera
## center to look like the player is holding it at waist/chest level.
func _find_or_create_carry_marker() -> Marker3D:
	if not _camera:
		return null
	
	# Check if a CarryMarker already exists as a child of the camera
	var existing: Marker3D = _camera.get_node_or_null("CarryMarker")
	if existing:
		return existing
	
	# Create a new Marker3D as a child of the camera
	var marker := Marker3D.new()
	marker.name = "CarryMarker"
	marker.position = Vector3(0.0, 0.0, -1.5)  # Centered on crosshair, 1.5m in front (matches hold_distance)
	_camera.add_child(marker)
	return marker






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
	
	# ─── CARRYING LAMP: tap E to drop ────────────────────────────────────
	# If we're carrying the lamp, a NEW press of E drops it (quick tap).
	# We check _e_is_held to distinguish a new press from the hold cycle
	# that was used to pick up the lamp.
	if _carried_lamp and event.pressed and not _e_is_held:
		_drop_carried_lamp()
		return
	
	# ─── GRABBING OBJECT: tap E to drop ──────────────────────────────────
	# Same behavior as the lamp — once an object is grabbed via hold,
	# releasing E does NOT drop it. Instead, the player must press E again
	# to release. This makes the grab system consistent with the lamp carry.
	if _is_grabbing and event.pressed and not _e_is_held:
		_drop_object()
		return
	
	if event.pressed and not _e_is_held:
		# E just pressed - start tracking hold time
		_e_is_held = true
		_e_held_time = 0.0
		_has_passed_threshold = false
		_has_passed_door_threshold = false
		_door_lock_target = null
		
	elif not event.pressed and _e_is_held:
		# E released
		_e_is_held = false
		
		if _has_passed_door_threshold:
			# Door lock hold completed — do nothing on release (already handled)
			pass
		elif not _has_passed_threshold:
			# Quick tap! Fire interact() on the current target
			_fire_interact()






func _process(delta: float) -> void:
	if not _camera:
		return
	
	# Track how long E has been held
	if _e_is_held and not _is_grabbing:
		_e_held_time += delta
		
		# Check for door lock hold (1s threshold)
		if not _has_passed_door_threshold and _e_held_time >= door_lock_threshold:
			# Check if we're looking at a door with toggle_lock
			var door_target = _find_door_target()
			if door_target:
				_has_passed_door_threshold = true
				door_target.toggle_lock()
				return  # Don't try to grab
		
		# Check for grab hold (0.5s threshold) — only if not doing door lock
		if not _has_passed_door_threshold and _e_held_time >= hold_threshold and not _has_passed_threshold:
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
		print("[PhysicalGrab] ERROR: InteractionManager not found at ../InteractionManager")
		return
	
	# Get the current target from InteractionManager using the public getter
	var target = interaction_manager.get_current_target()
	if target and target.has_method("interact"):
		target.interact()
		
		# ─── TUTORIAL: Mark interact as learned ──────────────────────────
		var tm := get_node_or_null("/root/TutorialManager")
		if tm and tm.has_method("mark_learned"):
			tm.mark_learned("interact")


func _try_grab() -> void:
	if not _camera:
		print("[PhysicalGrab] _try_grab: no camera!")
		return
	
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		print("[PhysicalGrab] _try_grab: no space state!")
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
		print("[PhysicalGrab] _try_grab: raycast hit nothing!")
		return
	
	var body = result.collider
	print("[PhysicalGrab] _try_grab: hit ", body, " (", body.name, ") type=", typeof(body), " is_rigid=", body is RigidBody3D)
	
	# Only grab RigidBody3D
	if not (body is RigidBody3D):
		print("[PhysicalGrab] _try_grab: not a RigidBody3D, skipping")
		return
	
	# Check mass
	if body.mass > max_grab_mass:
		print("[PhysicalGrab] _try_grab: mass too high: ", body.mass)
		return
	
	# Don't grab the player itself
	if body == player:
		print("[PhysicalGrab] _try_grab: is player, skipping")
		return
	
	# ─── PORTABLE LAMP CARRY CHECK ────────────────────────────────────────
	# If the body is in the "portable_trap" group, use the dedicated carry
	# system instead of the generic grab. This gives the lamp a natural
	# "hold in front of you" feel (like Amnesia/Half-Life).
	# Also check for the "interact" method as a fallback — any RigidBody3D
	# that has interact() is a special object that should use the carry system.
	if (body.is_in_group("portable_trap") or body.has_method("interact")) and body.has_method("pick_up"):
		print("[PhysicalGrab] _try_grab: found portable lamp, picking up!")
		_pick_up_lamp(body)
		return
	
	print("[PhysicalGrab] _try_grab: grabbing as regular object")
	
	# Success - grab the object
	_grab_object(body)




## Lazily gets or creates the CarryMarker.
## Unlike the old @onready approach, this is safe to call after set_camera()
## has been invoked (which happens in player_controller._ready()).
func _get_or_create_carry_marker() -> Marker3D:
	if _carry_marker:
		return _carry_marker
	_carry_marker = _find_or_create_carry_marker()
	return _carry_marker


## Picks up a PortableLamp using the dedicated carry system.
## Calls lamp.pick_up() with the CarryMarker reference so the lamp lerps
## its position/rotation to match the marker while carried.
func _pick_up_lamp(lamp: Node) -> void:
	var marker = _get_or_create_carry_marker()
	if not marker:
		print("[PhysicalGrab] ERROR: No CarryMarker available to pick up lamp!")
		return
	
	_carried_lamp = lamp
	lamp.pick_up(marker)
	print("[PhysicalGrab] PortableLamp picked up.")



## Drops the carried PortableLamp by calling lamp.drop_trap().
## The lamp handles its own deployment (enables light, sets drain rate,
## re-adds to portable_trap group, restores collision mask).
func _drop_carried_lamp() -> void:
	if not _carried_lamp:
		return
	
	if _carried_lamp.has_method("drop_trap"):
		_carried_lamp.drop_trap()
		print("[PhysicalGrab] PortableLamp dropped.")
	
	_carried_lamp = null



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


## Finds a door target in front of the camera that has toggle_lock() method.
func _find_door_target() -> Node:
	if not _camera:
		return null
	
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return null
	
	var viewport_size = _camera.get_viewport().size
	var center = viewport_size / 2.0
	var from = _camera.project_ray_origin(center)
	var to = from + _camera.project_ray_normal(center) * grab_distance
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var player = _find_player()
	if player:
		query.exclude = [player]
	
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return null
	
	var collider = result.collider
	if not collider:
		return null
	
	# Walk up the parent chain to find a node with toggle_lock
	var current = collider
	while current:
		if current.has_method("toggle_lock"):
			return current
		current = current.get_parent()
	
	return null

func _update_prompt() -> void:
	if not _prompt_label:
		return
	
	if _carried_lamp:
		_prompt_label.text = "[E] Deploy Lamp"
	elif _is_grabbing:
		_prompt_label.text = "[E] Release"
	elif _e_is_held and not _has_passed_threshold and not _has_passed_door_threshold:

		# Show what we're looking at while holding E
		var target = _find_grabbable_target()
		if target:
			_prompt_label.text = "Grabbing " + target.name + "..."
		else:
			# Check if we're looking at a door for lock toggle
			var door_target = _find_door_target()
			if door_target:
				var progress = min(1.0, _e_held_time / door_lock_threshold)
				var pct = int(progress * 100)
				if door_target.is_locked:
					_prompt_label.text = "Unlocking... %d%%" % pct
				else:
					_prompt_label.text = "Locking... %d%%" % pct
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
