extends CharacterBody3D

## "The Entity" — the main antagonist.
## Slasher teleportation paradigm: the Entity never pathfinds from 200m away.
## Instead, it constantly relocates to blind spots 20m behind the player,
## then stalks them locally using the NavigationAgent3D.

enum State {
	DORMANT,
	STALK,
	RELOCATE,
	APPROACH_WINDOW,
	WINDOW_PEEK,
}

@export var speed: float = 4.0
@export var catch_distance: float = 1.5
@export var relocate_radius: float = 20.0
@export var path_update_interval: float = 0.3
@export var stuck_timeout: float = 1.5
@export var shadow_material: Material = null

@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _monster_model: Node3D = $MonsterModel if has_node("MonsterModel") else null
@onready var _anim_tree: AnimationTree = $AnimationTree if has_node("AnimationTree") else null
@onready var _growl_audio: AudioStreamPlayer3D = $GrowlAudio if has_node("GrowlAudio") else null
@onready var _footstep_audio: AudioStreamPlayer3D = $FootstepAudio if has_node("FootstepAudio") else null

var _anim_state_machine: AnimationNodeStateMachinePlayback = null
var _entity_step_timer: float = 0.0
var _entity_step_interval: float = 0.5

var _player: Node3D = null
var _state: State = State.DORMANT
var _is_active: bool = false
var _path_timer: float = 0.0
var _stuck_timer: float = 0.0
var _game_time: float = 0.0

# Grace period to prevent instant teleport-chaining
var _relocate_cooldown: float = 0.0 

# When the Entity is seen by the player, it enters a "flee" state
var _is_fleeing: bool = false
var _flee_angle: float = 0.0
var _flee_direction: int = 1

# --- Night escalation & window peek variables ---
var current_night: int = 1
var window_peek_chance: float = 0.60
var current_stalk_speed: float = 4.0
var current_relocate_cooldown: float = 2.5

# Window peek state tracking
var _window_peek_timer: float = 0.0
var _window_peek_duration: float = 12.0
var _window_peek_marker: Node3D = null
var _window_peek_spotted: bool = false
var _window_peek_vanish_timer: float = 0.0
var _window_peek_vanish_delay: float = 1.0

# Staging position used for woodline approach and physical retreat
var _window_peek_staging_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("entity")
	_find_player()
	
	_nav_agent.path_desired_distance = 2.0
	_nav_agent.target_desired_distance = 2.0
	
	print("\n================== GLOBAL ANIMATION SYSTEM AUDIT ==================")
	
	# 1. Inspect the Monster Model Node
	if _monster_model:
		print("[AUDIT] MonsterModel Node Name: '%s'" % _monster_model.name)
		print("[AUDIT] MonsterModel Path Relative to Entity: %s" % get_path_to(_monster_model))
		
		# Find the actual Skeleton3D node where the physical bones live
		var skeleton: Skeleton3D = null
		for child in _monster_model.get_children():
			if child is Skeleton3D:
				skeleton = child
			elif child.has_node("Skeleton3D"):
				skeleton = child.get_node("Skeleton3D")
		
		if skeleton:
			print("[AUDIT] SUCCESS: Found active Skeleton3D node: '%s'" % skeleton.name)
			print("[AUDIT] Skeleton Node Path relative to MonsterModel: %s" % _monster_model.get_path_to(skeleton))
			print("[AUDIT] First 5 Available Bone Names in Skeleton: ", [skeleton.get_bone_name(0), skeleton.get_bone_name(1), skeleton.get_bone_name(2), skeleton.get_bone_name(3), skeleton.get_bone_name(4)])
		else:
			print("[AUDIT] CRITICAL WARNING: No Skeleton3D node detected anywhere under MonsterModel hierarchy!")
	else:
		print("[AUDIT] CRITICAL ERROR: _monster_model reference is completely NULL!")

	# 2. Dynamic AnimationPlayer Snapping & Library Track Validation
	var active_player: AnimationPlayer = null
	if _monster_model:
		if _monster_model.has_node("AnimationPlayer"):
			active_player = _monster_model.get_node("AnimationPlayer") as AnimationPlayer
		elif _monster_model.has_node("AnimationPlayer2"):
			active_player = _monster_model.get_node("AnimationPlayer2") as AnimationPlayer

	if active_player:
		print("[AUDIT] SUCCESS: Found active player engine node: '%s'" % active_player.name)
		var libs = active_player.get_animation_library_list()
		print("[AUDIT] Registered Animation Libraries present: ", libs)
		
		for lib_name in libs:
			var lib = active_player.get_animation_library(lib_name)
			if lib:
				var anims = lib.get_animation_list()
				print("[AUDIT]   -> Library '%s' contains tracks: %s" % [lib_name, anims])
				
				# Deep track key property analysis on the 'walk' or 'walk.anim' track if it exists
				for anim_name in anims:
					if "walk" in anim_name.to_lower():
						var anim = lib.get_animation(anim_name)
						print("[AUDIT]   Diving into track properties for key: '%s/%s'" % [lib_name, anim_name])
						print("[AUDIT]   Total property modification lines in this clip: %d" % anim.get_track_count())
						if anim.get_track_count() > 0:
							print("[AUDIT]   Sample Target Path of Track 0: '%s'" % anim.track_get_path(0))
							print("[AUDIT]   Sample Target Path of Track 1: '%s'" % anim.track_get_path(1))
	else:
		print("[AUDIT] CRITICAL ERROR: Could not locate AnimationPlayer or AnimationPlayer2 under the model container!")

	# 3. AnimationTree Parameter Validation
	if _anim_tree:
		print("[AUDIT] AnimationTree Node is present.")
		print("[AUDIT] AnimationTree is pointing to Player Path: %s" % _anim_tree.anim_player)
		if active_player:
			_anim_tree.anim_player = _anim_tree.get_path_to(active_player)
			_anim_state_machine = _anim_tree.get("parameters/playback")
			if _anim_state_machine:
				print("[AUDIT] SUCCESS: State machine parameter playback extracted completely!")
			else:
				print("[AUDIT] WARNING: 'parameters/playback' is returning null. Check your AnimationTree root node setup!")
	else:
		print("[AUDIT] WARNING: AnimationTree node link is completely missing from the scene tree structure!")
		
	print("===================================================================\n")

	# Retain your default physics settings
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	floor_constant_speed = true
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(60.0)
	
	visible = false
	_set_visuals_visible(false)
	call_deferred("_initialize_entity")

func _set_visuals_visible(v: bool) -> void:
	if _monster_model:
		_monster_model.visible = v

func _apply_shadow_material() -> void:
	if not _monster_model or not shadow_material:
		return
	var meshes: Array[MeshInstance3D] = []
	_find_mesh_instances(_monster_model, meshes)
	for m in meshes:
		m.material_override = shadow_material

func _find_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_find_mesh_instances(child, result)

func _initialize_entity() -> void:
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		nm.night_started.connect(_on_night_started)
		nm.night_ended.connect(_on_night_ended)
		if nm.is_night_active:
			activate()
			_relocate_behind_player()
	else:
		call_deferred("_initialize_entity")

func _on_night_started(night: int) -> void:
	setup_night_difficulty(night)
	activate()
	_relocate_behind_player()

func setup_night_difficulty(night: int) -> void:
	current_night = night
	current_stalk_speed = 3.5 + (night - 1) * 0.6
	current_relocate_cooldown = maxf(0.7, 3.0 - (night - 1) * 0.5)
	window_peek_chance = maxf(0.05, 0.70 - (night - 1) * 0.15)
	print("[Entity] Night %d difficulty set: speed=%.1f, cooldown=%.1fs, peek_chance=%.2f" % [night, current_stalk_speed, current_relocate_cooldown, window_peek_chance])

func _on_night_ended(_night: int) -> void:
	deactivate()

func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node3D
	else:
		_player = _find_node_by_type(get_tree().root, "CharacterBody3D")

func _find_node_by_type(node: Node, type_name: String) -> Node3D:
	if node.is_class(type_name):
		return node as Node3D
	for child in node.get_children():
		var result = _find_node_by_type(child, type_name)
		if result:
			return result
	return null

func activate() -> void:
	_is_active = true
	visible = true
	_state = State.RELOCATE
	_set_visuals_visible(true)
	print("[Entity] Activated — RELOCATE to blind spot")

func deactivate() -> void:
	_is_active = false
	velocity = Vector3.ZERO
	visible = false
	_state = State.DORMANT
	_set_visuals_visible(false)
	print("[Entity] Deactivated — DORMANT")

func _physics_process(delta: float) -> void:
	_game_time += delta
	
	if _relocate_cooldown > 0.0:
		_relocate_cooldown -= delta
	
	if global_position.y < -10.0:
		print("[Entity] Fell into the void at Y=%.1f — RELOCATE" % global_position.y)
		velocity = Vector3.ZERO
		_state = State.RELOCATE
		_relocate_behind_player()
		return
	
	if not _is_active or not _player:
		return
	
	if not is_on_floor() and _state != State.WINDOW_PEEK:
		velocity += get_gravity() * delta
	
	match _state:
		State.DORMANT:
			velocity = Vector3.ZERO
		State.STALK:
			_stalk_state(delta)
		State.RELOCATE:
			velocity = Vector3.ZERO
		State.APPROACH_WINDOW:
			_approach_window_state(delta)
		State.WINDOW_PEEK:
			_window_peek_state(delta)
	
	move_and_slide()
	
	# --- Dynamic Movement Facing ---
	var flat_vel = Vector2(velocity.x, velocity.z)
	if flat_vel.length_squared() > 0.05 and _monster_model:
		var target_angle = atan2(flat_vel.x, flat_vel.y)
		_monster_model.rotation.y = lerp_angle(_monster_model.rotation.y, target_angle, delta * 10.0)
	
	_update_animations(delta)

func _is_player_spotting_entity() -> bool:
	if not _player or not is_instance_valid(_player):
		return false
	
	var cam = get_viewport().get_camera_3d()
	if not cam:
		return false
	
	var flashlight_on := false
	if _player.has_method("_toggle_flashlight"):
		var fl = _player.get("_flashlight")
		if fl and is_instance_valid(fl):
			flashlight_on = fl.is_on if "is_on" in fl else fl.visible
		else:
			flashlight_on = _player.get("_flashlight_on")
	else:
		var fl = cam.get_node_or_null("Flashlight")
		if fl:
			flashlight_on = fl.is_on if "is_on" in fl else fl.visible
	
	if not flashlight_on:
		return false
	
	var cam_forward = -cam.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	
	var to_entity = (global_position - cam.global_position)
	to_entity.y = 0.0
	to_entity = to_entity.normalized()
	
	if cam_forward.dot(to_entity) <= 0.55:
		return false
	
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(cam.global_position, global_position + Vector3(0, 1, 0))
	query.exclude = [self, _player]
	var hit = space.intersect_ray(query)
	if not hit.is_empty() and hit.collider != self:
		return false
	
	return true

func _stalk_state(delta: float) -> void:
	var is_seen: bool = _is_player_spotting_entity()
	
	if is_seen:
		if not _is_fleeing:
			_is_fleeing = true
			_flee_direction = 1 if randf() > 0.5 else -1
			_flee_angle = atan2(global_position.z - _player.global_position.z, global_position.x - _player.global_position.x)
			print("[Entity] Spotted! Fleeing at 2x speed in circular arc around player")
		
		_flee_angle += _flee_direction * delta * 1.5
		var flee_speed = current_stalk_speed * 2.0
		
		var circle_target = Vector3(
			_player.global_position.x + cos(_flee_angle) * relocate_radius,
			0.0,
			_player.global_position.z + sin(_flee_angle) * relocate_radius
		)
		
		var move_dir = global_position.direction_to(circle_target)
		move_dir.y = 0.0
		move_dir = move_dir.normalized()
		velocity.x = move_dir.x * flee_speed
		velocity.z = move_dir.z * flee_speed
		
		if not _is_player_spotting_entity():
			_is_fleeing = false
		return
	
	_is_fleeing = false
	
	if _relocate_cooldown <= 0.0:
		var real_speed = get_real_velocity().length()
		if real_speed < 0.2:
			_stuck_timer += delta
			if _stuck_timer >= stuck_timeout:
				print("[Entity] Stuck (real_vel=%.2f for %.1fs) — RELOCATE" % [real_speed, _stuck_timer])
				_relocate_behind_player()
				return
		else:
			_stuck_timer = 0.0

	if global_position.distance_to(_player.global_position) <= catch_distance:
		_on_caught_player()
		return
	
	_path_timer += delta
	if _path_timer >= path_update_interval:
		_path_timer = 0.0
		_nav_agent.target_position = _player.global_position
	
	# --- Flat 2D Plane Math ---
	if _nav_agent.is_navigation_finished():
		var dir_2d := Vector2(_player.global_position.x - global_position.x, _player.global_position.z - global_position.z)
		if dir_2d.length() > 0.01:
			var move_dir_2d = dir_2d.normalized()
			velocity.x = move_dir_2d.x * current_stalk_speed
			velocity.z = move_dir_2d.y * current_stalk_speed
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		var next_pos = _nav_agent.get_next_path_position()
		var dir_2d := Vector2(next_pos.x - global_position.x, next_pos.z - global_position.z)
		
		if dir_2d.length() <= 0.01:
			dir_2d = Vector2(_player.global_position.x - global_position.x, _player.global_position.z - global_position.z)
			
		if dir_2d.length() > 0.01:
			var move_dir_2d = dir_2d.normalized()
			velocity.x = move_dir_2d.x * current_stalk_speed
			velocity.z = move_dir_2d.y * current_stalk_speed
		else:
			velocity.x = 0.0
			velocity.z = 0.0

func _relocate_behind_player() -> void:
	if not _player:
		return
		
	velocity = Vector3.ZERO
	_state = State.RELOCATE
	
	var camera = _player.get_viewport().get_camera_3d()
	var cam_basis: Basis = camera.global_transform.basis if camera else Basis()
	
	var cam_forward = -cam_basis.z
	cam_forward.y = 0.0
	var behind_dir = -cam_forward.normalized()
	
	var space_state = get_world_3d().direct_space_state
	var cylinder_shape: CylinderShape3D
	
	if _collision_shape and _collision_shape.shape is SphereShape3D:
		var sphere = _collision_shape.shape as SphereShape3D
		cylinder_shape = CylinderShape3D.new()
		cylinder_shape.radius = sphere.radius * 1.1
		cylinder_shape.height = 2.0
	
	for attempt in range(50):
		var angle_offset = deg_to_rad(randf_range(-80.0, 80.0)) 
		var spawn_dir = behind_dir.rotated(Vector3.UP, angle_offset).normalized()
		var candidate = _player.global_position + spawn_dir * relocate_radius
		
		var ray_query = PhysicsRayQueryParameters3D.create(
			Vector3(candidate.x, 30.0, candidate.z), 
			Vector3(candidate.x, -20.0, candidate.z)
		)
		ray_query.collide_with_areas = false
		ray_query.collide_with_bodies = true
		ray_query.exclude = [self]
		
		var ground_result = space_state.intersect_ray(ray_query) if space_state else {}
		if ground_result.is_empty() or ground_result.position.y > 3.0:
			continue
			
		var raw_pos = ground_result.position
		var map = get_world_3d().navigation_map
		var nav_pos = NavigationServer3D.map_get_closest_point(map, raw_pos)
		
		var spawn_pos = raw_pos
		if nav_pos.distance_to(raw_pos) < 5.0:
			spawn_pos = nav_pos
			
		spawn_pos.y += 0.05
		
		if cylinder_shape and space_state:
			var shape_query = PhysicsShapeQueryParameters3D.new()
			shape_query.shape = cylinder_shape
			shape_query.transform = Transform3D.IDENTITY.translated(spawn_pos + Vector3(0, 0.5, 0))
			shape_query.collision_mask = 1
			shape_query.exclude = [self]
			shape_query.collide_with_areas = false
			shape_query.collide_with_bodies = true
			
			if not space_state.intersect_shape(shape_query).is_empty():
				continue
		
		_finalize_relocation(spawn_pos, "Cleanly")
		return
	
	var fallback_raw = _player.global_position + behind_dir * relocate_radius
	var map = get_world_3d().navigation_map
	var safe_nav_pos = NavigationServer3D.map_get_closest_point(map, fallback_raw)
	
	var final_fallback = safe_nav_pos
	if final_fallback == Vector3.ZERO or final_fallback.distance_to(fallback_raw) > 5.0:
		final_fallback = fallback_raw
		
	final_fallback.y += 0.05
	_finalize_relocation(final_fallback, "Fallback")

func _finalize_relocation(spawn_pos: Vector3, method: String) -> void:
	global_position = spawn_pos
	velocity = Vector3.ZERO
	_stuck_timer = 0.0
	
	var cabin_pos = Vector3(9.0, 0.0, 0.4) 
	var dist_to_cabin = _player.global_position.distance_to(cabin_pos)
	var is_inside_cabin = dist_to_cabin < 15.0
	
	if is_inside_cabin and randf() < window_peek_chance:
		_start_window_peek()
		return
	
	_state = State.STALK
	_nav_agent.target_position = _player.global_position
	_relocate_cooldown = current_relocate_cooldown
	print("[Entity] Relocated %s to (%.1f, %.1f, %.1f)" % [method, spawn_pos.x, spawn_pos.y, spawn_pos.z])

func _start_window_peek() -> void:
	var window_groups = get_tree().get_nodes_in_group("WindowMarkers")
	if window_groups.is_empty():
		_state = State.STALK
		_nav_agent.target_position = _player.global_position
		_relocate_cooldown = current_relocate_cooldown
		return
	
	var window_parent = window_groups[0] as Node3D
	var markers: Array[Node3D] = []
	for child in window_parent.get_children():
		if child is Marker3D:
			markers.append(child as Marker3D)
	
	if markers.is_empty():
		_state = State.STALK
		_nav_agent.target_position = _player.global_position
		_relocate_cooldown = current_relocate_cooldown
		return
	
	var nearest_dist: float = INF
	var nearest_marker: Node3D = null
	for marker in markers:
		var d = marker.global_position.distance_squared_to(_player.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest_marker = marker
	
	if not nearest_marker:
		nearest_marker = markers[0]
	
	_window_peek_marker = nearest_marker
	
	var cabin_pos = Vector3(9.0, 0.0, 0.4)
	var dir_from_cabin = (nearest_marker.global_position - cabin_pos).normalized()
	
	var staging_spawn_pos = nearest_marker.global_position + (dir_from_cabin * 20.0)
	var map = get_world_3d().navigation_map
	var nav_pos = NavigationServer3D.map_get_closest_point(map, staging_spawn_pos)
	
	if nav_pos.distance_to(staging_spawn_pos) < 5.0:
		staging_spawn_pos = nav_pos
	
	var space_state = get_world_3d().direct_space_state
	if space_state:
		var ray_query = PhysicsRayQueryParameters3D.create(
			Vector3(staging_spawn_pos.x, 30.0, staging_spawn_pos.z),
			Vector3(staging_spawn_pos.x, -20.0, staging_spawn_pos.z)
		)
		ray_query.collide_with_areas = false
		ray_query.collide_with_bodies = true
		ray_query.exclude = [self]
		var ground_result = space_state.intersect_ray(ray_query)
		if not ground_result.is_empty():
			staging_spawn_pos.y = ground_result.position.y + 0.05
	
	_window_peek_staging_pos = staging_spawn_pos
	global_position = staging_spawn_pos
	velocity = Vector3.ZERO
	_nav_agent.target_position = nearest_marker.global_position
	
	_window_peek_timer = 0.0
	_window_peek_spotted = false
	_window_peek_vanish_timer = 0.0
	_state = State.APPROACH_WINDOW
	_relocate_cooldown = current_relocate_cooldown
	print("[Entity] Window hunt initialized. Spawning in woodline at (%.1f, %.1f, %.1f). Stalking toward window marker '%s'." % [staging_spawn_pos.x, staging_spawn_pos.y, staging_spawn_pos.z, nearest_marker.name])

func _approach_window_state(delta: float) -> void:
	if not _window_peek_marker:
		_relocate_behind_player()
		return
	
	_nav_agent.target_position = _window_peek_marker.global_position
	
	var next_pos = _nav_agent.get_next_path_position()
	var dir_2d := Vector2(next_pos.x - global_position.x, next_pos.z - global_position.z)
	var approach_speed = current_stalk_speed * 0.5
	
	if dir_2d.length() <= 0.01 and _window_peek_marker:
		dir_2d = Vector2(_window_peek_marker.global_position.x - global_position.x, _window_peek_marker.global_position.z - global_position.z)
		
	if dir_2d.length() > 0.01:
		var move_dir_2d = dir_2d.normalized()
		velocity.x = move_dir_2d.x * approach_speed
		velocity.z = move_dir_2d.y * approach_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	
	var dist_to_window = global_position.distance_to(_window_peek_marker.global_position)
	if dist_to_window < 1.2:
		velocity = Vector3.ZERO
		global_position = _window_peek_marker.global_position
		global_transform.basis = _window_peek_marker.global_transform.basis
		
		_window_peek_timer = 0.0
		_state = State.WINDOW_PEEK
	
	if _is_player_spotting_entity():
		_relocate_behind_player()
		return

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_F2 and event.pressed and not event.is_echo():
		if _is_active and _player:
			_start_window_peek()

func _window_peek_state(delta: float) -> void:
	_window_peek_timer += delta
	
	if _window_peek_spotted:
		_window_peek_vanish_timer += delta
		
		if _window_peek_staging_pos != Vector3.ZERO:
			_nav_agent.target_position = _window_peek_staging_pos
			var next_pos = _nav_agent.get_next_path_position()
			var dir_2d := Vector2(next_pos.x - global_position.x, next_pos.z - global_position.z)
			var sprint_speed = current_stalk_speed * 1.5
			
			if dir_2d.length() <= 0.01:
				dir_2d = Vector2(_window_peek_staging_pos.x - global_position.x, _window_peek_staging_pos.z - global_position.z)
				
			if dir_2d.length() > 0.01:
				var move_dir_2d = dir_2d.normalized()
				velocity.x = move_dir_2d.x * sprint_speed
				velocity.z = move_dir_2d.y * sprint_speed
			else:
				velocity.x = 0.0
				velocity.z = 0.0
			
			var dist_to_window = global_position.distance_to(_window_peek_marker.global_position)
			if dist_to_window > 15.0 or _window_peek_vanish_timer >= _window_peek_vanish_delay:
				_relocate_behind_player()
		else:
			if _window_peek_vanish_timer >= _window_peek_vanish_delay:
				_relocate_behind_player()
		return
	
	if _is_player_spotting_entity():
		_window_peek_spotted = true
		_window_peek_vanish_timer = 0.0
		return
	
	if _window_peek_timer >= _window_peek_duration:
		_relocate_behind_player()

func _on_caught_player() -> void:
	_is_active = false
	velocity = Vector3.ZERO
	
	if _growl_audio:
		_growl_audio.pitch_scale = randf_range(0.8, 1.1)
		_growl_audio.play()
	
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		nm.horror_event.emit("entity_caught_player")

func _update_animations(_delta: float) -> void:
	if not _anim_state_machine:
		return
		
	# FORCE GROUNDING: Clamp the model container to the physics root to prevent root motion drift
	if _monster_model:
		_monster_model.position = Vector3(0.0, -0.95, 0.0)
		
	# TRUE VELOCITY TRACKING: Prevents idle flickering during waypoint switch calculations
	var real_vel := get_real_velocity()
	var horz_speed := Vector2(real_vel.x, real_vel.z).length()
	
	match _state:
		State.STALK, State.APPROACH_WINDOW:
			if real_vel.y > 0.8:
				_anim_state_machine.travel("ClimbUp")
			elif real_vel.y < -0.8 and not is_on_floor():
				_anim_state_machine.travel("ClimbDown")
			elif horz_speed > 0.2:
				_anim_state_machine.travel("Stalk")
				if _footstep_audio and is_on_floor():
					_entity_step_timer -= _delta
					if _entity_step_timer <= 0.0:
						_footstep_audio.pitch_scale = randf_range(0.85, 1.1)
						_footstep_audio.play()
						_entity_step_timer = _entity_step_interval
			else:
				_anim_state_machine.travel("Idle")
				_entity_step_timer = 0.0
				
		State.WINDOW_PEEK:
			if _window_peek_spotted:
				_anim_state_machine.travel("Stalk")
			else:
				_anim_state_machine.travel("Idle")
				
		State.DORMANT:
			_anim_state_machine.travel("Idle")