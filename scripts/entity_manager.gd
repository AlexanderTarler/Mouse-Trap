extends Node

## Entity Manager - The Stalking Entity
##
## The Entity is a mysterious stalker that:
## - Moves through the cabin using physics (CharacterBody3D), same as the player
## - Tries to maintain line-of-sight on the player without being seen
## - Builds up a "gaze" kill timer the longer it watches the player unseen
## - Gets faster the more it has watched the player
## - Gets slower when the player spots it
## - If gaze reaches 100%, the player dies
## - Can move between all 3 floors (ground, upper, basement)

signal entity_appeared(location: String)
signal entity_disappeared()
signal player_watched(intensity: float)
signal gaze_progress_updated(progress: float)
signal player_killed()

# Entity states
enum EntityState {
	HIDDEN,       # Not active, lurking in shadows
	STALKING,     # Moving through cabin, seeking LOS on player
	EXPOSED,      # Player can see the Entity -> retreating
	HUNTING,      # High gaze progress -> more aggressive movement
	KILLING       # Gaze reached 100% -> player death
}

# Player's walk speed (reference for Entity speed scaling)
const PLAYER_BASE_SPEED: float = 3.5

# Gaze timer: 30 seconds cumulative LOS = death
const GAZE_MAX_TIME: float = 30.0

# How fast gaze decreases when player sees the Entity (faster than increase)
const GAZE_DECREASE_RATE: float = 1.0 / 15.0

# How fast gaze increases when Entity sees player unseen
const GAZE_INCREASE_RATE: float = 1.0 / 30.0

# Speed scaling
const SPEED_MIN: float = 0.8   # When fully exposed
const SPEED_MAX: float = 2.0   # When about to kill

# Stalking positions on all 3 floors (x,z only - y is handled by physics/gravity)
# Ground floor positions
static var STALK_GROUND = [
	Vector3(-5.5, 0, -4.5),  # Back-left corner
	Vector3(5.5, 0, -4.5),   # Back-right corner
	Vector3(-5.5, 0, 4.5),   # Front-left corner
	Vector3(5.5, 0, 4.5),    # Front-right corner
	Vector3(-3.0, 0, -4.0),  # Behind sofa (left side)
	Vector3(3.0, 0, -4.0),   # Behind bed (right side)
	Vector3(-4.5, 0, 0.0),   # Left wall middle
	Vector3(4.5, 0, 0.0),    # Right wall middle
	Vector3(-2.0, 0, -2.0),  # Near table
	Vector3(2.0, 0, -2.0),   # Near table right
	Vector3(-1.0, 0, 3.0),   # Left of stairs
	Vector3(1.0, 0, 3.0),    # Right of stairs
]

# Upper floor positions
static var STALK_UPPER = [
	Vector3(-4.0, 0, -3.0),  # Upper back-left
	Vector3(4.0, 0, -3.0),   # Upper back-right
	Vector3(-4.0, 0, 3.0),   # Upper front-left
	Vector3(4.0, 0, 3.0),    # Upper front-right
	Vector3(-2.0, 0, 0.0),   # Upper center-left
	Vector3(2.0, 0, 0.0),    # Upper center-right
	Vector3(0.0, 0, -3.0),   # Upper back-center
	Vector3(0.0, 0, 3.0),    # Upper front-center
]

# Basement positions
static var STALK_BASEMENT = [
	Vector3(-4.0, 0, -3.0),  # Basement back-left
	Vector3(4.0, 0, -3.0),   # Basement back-right
	Vector3(-4.0, 0, 3.0),   # Basement front-left
	Vector3(4.0, 0, 3.0),    # Basement front-right
	Vector3(-2.0, 0, 0.0),   # Basement center-left
	Vector3(2.0, 0, 0.0),    # Basement center-right
]

# All stalking positions combined
var _all_stalk_positions = []

# Stair positions for floor transitions (x,z only)
static var STAIR_BOTTOM = Vector3(0, 0, -2.0)   # Bottom of stairs (ground floor)
static var STAIR_TOP = Vector3(0, 0, 2.0)       # Top of stairs (upper floor)
static var BASEMENT_STAIRS_TOP = Vector3(-4, 0, 4.0)    # Top of basement stairs
static var BASEMENT_STAIRS_BOTTOM = Vector3(-4, 0, 4.0) # Bottom of basement stairs

var _current_state: EntityState = EntityState.HIDDEN
var _player: Node3D = null
var _entity_body: CharacterBody3D = null
var _camera: Camera3D = null

# Gaze system
var _gaze_progress: float = 0.0
var _entity_speed: float = PLAYER_BASE_SPEED

# Movement
var _current_target_pos: Vector3 = Vector3.ZERO
var _current_floor: int = 0  # 0=ground, 1=upper, -1=basement
var _move_timer: float = 0.0
var _move_interval: float = 4.0  # How often to pick a new position
var _arrival_distance: float = 1.5

# Stalking
var _stalk_cooldown: float = 0.0
var _exposed_timer: float = 0.0
var _hunt_threshold: float = 0.5  # Gaze progress above this = HUNTING state

# Visual effects
var _glow: OmniLight3D = null

# Visibility control - use a timer instead of random flickering
var _visibility_timer: float = 0.0
var _is_visible_glimpse: bool = false

func _ready() -> void:
	# Combine all stalking positions
	_all_stalk_positions = STALK_GROUND + STALK_UPPER + STALK_BASEMENT
	
	_setup_entity_physics_body()
	_connect_signals()
	print("EntityManager ready - The Entity is watching...")

func _setup_entity_physics_body() -> void:
	# Create the entity as a CharacterBody3D so it uses physics/gravity
	_entity_body = CharacterBody3D.new()
	_entity_body.name = "Entity"
	_entity_body.visible = false
	_entity_body.floor_stop_on_slope = true
	_entity_body.floor_block_on_wall = true
	add_child(_entity_body)
	
	# Add collision shape (same size as player)
	var col_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(0.6, 1.8, 0.6)
	col_shape.shape = box_shape
	col_shape.position = Vector3(0, 0.9, 0)  # Center the collision shape
	_entity_body.add_child(col_shape)
	
	# Create a humanoid silhouette using multiple meshes
	# Body (torso)
	var body = MeshInstance3D.new()
	var body_box = BoxMesh.new()
	body_box.size = Vector3(0.6, 0.7, 0.3)
	body.mesh = body_box
	body.position = Vector3(0, 0.9, 0)
	_entity_body.add_child(body)
	
	# Head
	var head = MeshInstance3D.new()
	var head_sphere = SphereMesh.new()
	head_sphere.radius = 0.15
	head_sphere.height = 0.3
	head.mesh = head_sphere
	head.position = Vector3(0, 1.5, 0)
	_entity_body.add_child(head)
	
	# Left arm
	var left_arm = MeshInstance3D.new()
	var arm_box = BoxMesh.new()
	arm_box.size = Vector3(0.12, 0.6, 0.12)
	left_arm.mesh = arm_box
	left_arm.position = Vector3(-0.4, 0.9, 0)
	_entity_body.add_child(left_arm)
	
	# Right arm
	var right_arm = MeshInstance3D.new()
	right_arm.mesh = arm_box
	right_arm.position = Vector3(0.4, 0.9, 0)
	_entity_body.add_child(right_arm)
	
	# Legs
	var leg_box = BoxMesh.new()
	leg_box.size = Vector3(0.15, 0.6, 0.15)
	
	var left_leg = MeshInstance3D.new()
	left_leg.mesh = leg_box
	left_leg.position = Vector3(-0.15, 0.3, 0)
	_entity_body.add_child(left_leg)
	
	var right_leg = MeshInstance3D.new()
	right_leg.mesh = leg_box
	right_leg.position = Vector3(0.15, 0.3, 0)
	_entity_body.add_child(right_leg)
	
	# Dark, slightly transparent material for all parts
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.08, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.3, 0.4, 1)
	mat.emission_energy_multiplier = 1.5
	
	# Apply material to all parts
	for child in _entity_body.get_children():
		if child is MeshInstance3D:
			child.material_override = mat
	
	# Add a dim glow light
	_glow = OmniLight3D.new()
	_glow.light_color = Color(0.3, 0.3, 0.5, 1)
	_glow.light_energy = 1.0
	_glow.omni_range = 4.0
	_entity_body.add_child(_glow)
	
	# Add a second glow light at the head for eerie effect
	var head_glow = OmniLight3D.new()
	head_glow.light_color = Color(0.4, 0.4, 0.6, 1)
	head_glow.light_energy = 0.5
	head_glow.omni_range = 2.0
	head_glow.position = Vector3(0, 1.5, 0)
	_entity_body.add_child(head_glow)

func _connect_signals() -> void:
	# Find NightManager via scene tree
	var nm = get_tree().root.find_child("NightManager", true, false)
	if not nm:
		nm = get_tree().root.get_node_or_null("/root/NightManager")
	
	if nm:
		nm.night_started.connect(_on_night_started)
		nm.night_ended.connect(_on_night_ended)
		nm.horror_event.connect(_on_horror_event)
	else:
		print("EntityManager ERROR: NightManager not found!")

func _on_night_started(night: int) -> void:
	_current_state = EntityState.STALKING
	_gaze_progress = 0.0
	_entity_speed = PLAYER_BASE_SPEED
	_stalk_cooldown = 5.0  # Brief grace period
	_exposed_timer = 0.0
	_move_timer = 0.0
	_visibility_timer = 0.0
	_is_visible_glimpse = false
	
	# Start at a random ground floor position
	_current_floor = 0
	var start_pos = STALK_GROUND[randi() % STALK_GROUND.size()]
	_current_target_pos = start_pos
	
	# Place entity at a valid position above the ground floor
	# Physics will handle dropping it to the floor
	_entity_body.global_position = Vector3(start_pos.x, 2.0, start_pos.z)
	_entity_body.velocity = Vector3.ZERO
	_entity_body.visible = false
	
	print("Entity begins stalking... Night %d" % night)

func _on_night_ended(_night: int) -> void:
	_current_state = EntityState.HIDDEN
	_hide_entity()
	_gaze_progress = 0.0
	print("Entity retreats as dawn breaks...")

func _on_horror_event(event_name: String) -> void:
	match event_name:
		"shadow_outside":
			_move_to_floor(0)
			_current_target_pos = Vector3(0, 0, -4.5)
		"entity_glimpse":
			# Use a non-await approach: set a timer flag
			_is_visible_glimpse = true
			_visibility_timer = 0.5
			_entity_body.visible = true
		"entity_inside":
			_current_target_pos = Vector3(0, 0, 0)
		"entity_appears":
			_current_target_pos = _get_nearby_position(3.0)
		"entity_charge":
			_entity_speed = PLAYER_BASE_SPEED * 1.5
			if _player:
				_current_target_pos = _player.global_position
		"entity_constant":
			_move_interval = 2.0
		"final_confrontation":
			_entity_speed = PLAYER_BASE_SPEED * 2.0
			_move_interval = 1.5

func _physics_process(delta: float) -> void:
	if _current_state == EntityState.HIDDEN:
		return
	
	# Find player if not set
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
		if not _player:
			return
		_camera = _player.get_node_or_null("CameraHolder/Camera3D") as Camera3D
	
	if not _camera:
		return
	
	# Handle glimpse visibility timer (non-await approach)
	if _is_visible_glimpse:
		_visibility_timer -= delta
		if _visibility_timer <= 0.0:
			_is_visible_glimpse = false
			if _current_state != EntityState.HIDDEN:
				_entity_body.visible = false
				entity_disappeared.emit()
	
	# --- Core LOS checks ---
	var entity_pos = _entity_body.global_position
	var player_pos = _player.global_position
	var player_eye_pos = player_pos + Vector3(0, 1.7, 0)  # Player eye height
	var entity_eye_pos = entity_pos + Vector3(0, 1.5, 0)  # Entity eye height
	
	# Check: Can Entity see the player?
	var entity_sees_player = _has_line_of_sight(entity_eye_pos, player_eye_pos)
	
	# Check: Can Player see the Entity?
	var player_sees_entity = false
	if _entity_body.visible:
		player_sees_entity = _has_line_of_sight(player_eye_pos, entity_eye_pos)
	
	# --- Update gaze progress ---
	if entity_sees_player and not player_sees_entity:
		# Entity sees player unseen -> gaze increases
		_gaze_progress += delta * GAZE_INCREASE_RATE
		_entity_speed = lerp(PLAYER_BASE_SPEED, PLAYER_BASE_SPEED * SPEED_MAX, _gaze_progress)
		
		if _current_state != EntityState.HUNTING and _gaze_progress >= _hunt_threshold:
			_current_state = EntityState.HUNTING
			print("Entity is now HUNTING (gaze: %0.1f%%)" % (_gaze_progress * 100))
		
	elif player_sees_entity:
		# Player sees Entity -> gaze decreases (reward)
		_gaze_progress -= delta * GAZE_DECREASE_RATE
		_entity_speed = lerp(PLAYER_BASE_SPEED * SPEED_MIN, PLAYER_BASE_SPEED, 1.0 - _gaze_progress)
		
		if _current_state != EntityState.EXPOSED:
			_current_state = EntityState.EXPOSED
			_exposed_timer = 0.0
			print("Entity is EXPOSED! (gaze: %0.1f%%)" % (_gaze_progress * 100))
	
	# Clamp gaze
	_gaze_progress = clamp(_gaze_progress, 0.0, 1.0)
	
	# Emit signals
	player_watched.emit(_gaze_progress)
	gaze_progress_updated.emit(_gaze_progress)
	
	# Check for death
	if _gaze_progress >= 1.0:
		_kill_player()
		return
	
	# --- State machine ---
	match _current_state:
		EntityState.STALKING, EntityState.HUNTING:
			_update_stalking(delta)
		EntityState.EXPOSED:
			_update_exposed(delta)
		EntityState.KILLING:
			pass  # Handled above
	
	# --- Physics-based movement (same as player) ---
	_move_toward_target_physics(delta)
	
	# --- Visual updates ---
	_update_entity_visual(delta)

## Gets the 3D space state for raycasting.
func _get_space_state():
	var world = get_tree().root.get_world_3d()
	if not world:
		return null
	return world.direct_space_state

## Checks if there's a clear line of sight between two points.
func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var space_state = _get_space_state()
	if not space_state:
		return false
	var query = PhysicsRayQueryParameters3D.create(from, to)
	# Exclude the entity itself and the player from the raycast
	query.exclude = [_entity_body, _player]
	var result = space_state.intersect_ray(query)
	
	# If nothing was hit, or the hit is very close to the target, LOS is clear
	if result.is_empty():
		return true
	
	var hit_dist = from.distance_to(result.position)
	var target_dist = from.distance_to(to)
	
	# Allow small margin for error
	return hit_dist >= target_dist - 0.5

## Updates stalking behavior - moving to positions that give LOS on player.
func _update_stalking(delta: float) -> void:
	_stalk_cooldown -= delta
	_move_timer += delta
	
	if _move_timer >= _move_interval:
		# Pick a new stalking position
		var best_pos = _find_best_stalk_position()
		if best_pos != Vector3.ZERO:
			_current_target_pos = best_pos
		
		_move_timer = 0.0
		
		# Occasionally become visible (glimpse) - use timer instead of await
		if randf() < 0.2 and not _entity_body.visible and not _is_visible_glimpse:
			_is_visible_glimpse = true
			_visibility_timer = 0.3
			_entity_body.visible = true
			entity_appeared.emit("glimpse")

## Updates exposed behavior - retreating from player's sight.
func _update_exposed(delta: float) -> void:
	_exposed_timer += delta
	
	# Move to a position that's NOT in player's LOS
	var retreat_pos = _find_retreat_position()
	if retreat_pos != Vector3.ZERO:
		_current_target_pos = retreat_pos
	
	# Hide the entity when retreating
	_entity_body.visible = false
	_is_visible_glimpse = false
	
	# After a few seconds of being unseen, return to stalking
	if _exposed_timer > 3.0 and _gaze_progress < _hunt_threshold:
		_current_state = EntityState.STALKING
		print("Entity returns to stalking...")
	elif _exposed_timer > 5.0:
		_current_state = EntityState.STALKING
		print("Entity returns to stalking (timeout)...")

## Finds the best stalking position that gives LOS on player without being seen.
func _find_best_stalk_position() -> Vector3:
	if not _player or not _camera:
		return _get_random_position_on_floor(_current_floor)
	
	var player_eye = _player.global_position + Vector3(0, 1.7, 0)
	var best_pos = Vector3.ZERO
	var best_score = -999.0
	
	# Consider positions on all floors
	var candidates = _all_stalk_positions
	
	for pos in candidates:
		# Use the entity's actual position for LOS check (y is handled by physics)
		var entity_eye = Vector3(pos.x, _entity_body.global_position.y + 1.5, pos.z)
		
		# Check if Entity can see player from this position
		var can_see_player = _has_line_of_sight(entity_eye, player_eye)
		if not can_see_player:
			continue
		
		# Check if player can see Entity from this position
		var player_can_see = _has_line_of_sight(player_eye, entity_eye)
		
		# Score: prefer positions where Entity sees player but player doesn't see Entity
		var score = 0.0
		if not player_can_see:
			score = 10.0  # High score for hidden positions with LOS
		else:
			score = -5.0  # Penalty for positions where player can see Entity
		
		# Bonus for being closer to the player (more intense)
		var dist = _player.global_position.distance_to(pos)
		score += max(0, 8.0 - dist) * 0.5
		
		# Bonus for being on the same floor (avoids unnecessary stair climbing)
		var pos_floor = _get_floor_of_position(pos)
		if pos_floor == _current_floor:
			score += 2.0
		
		# Add randomness
		score += randf_range(-1.0, 1.0)
		
		if score > best_score:
			best_score = score
			best_pos = pos
	
	if best_pos == Vector3.ZERO:
		# Fallback: move to a random position
		best_pos = _get_random_position_on_floor(_current_floor)
	
	return best_pos

## Finds a position to retreat to where the player can't see the Entity.
func _find_retreat_position() -> Vector3:
	if not _player or not _camera:
		return _get_random_position_on_floor(_current_floor)
	
	var player_eye = _player.global_position + Vector3(0, 1.7, 0)
	var best_pos = Vector3.ZERO
	var best_score = -999.0
	
	for pos in _all_stalk_positions:
		var entity_eye = Vector3(pos.x, _entity_body.global_position.y + 1.5, pos.z)
		
		# Check if player can see Entity from this position
		var player_can_see = _has_line_of_sight(player_eye, entity_eye)
		
		if player_can_see:
			continue  # Skip positions where player can see Entity
		
		# Score: prefer positions far from player and on different floors
		var dist = _player.global_position.distance_to(pos)
		var score = dist
		
		var pos_floor = _get_floor_of_position(pos)
		if pos_floor != _current_floor:
			score += 5.0  # Bonus for changing floors
		
		score += randf_range(-1.0, 1.0)
		
		if score > best_score:
			best_score = score
			best_pos = pos
	
	if best_pos == Vector3.ZERO:
		best_pos = _get_random_position_on_floor(_current_floor)
	
	return best_pos

## Moves the entity toward its target using physics (CharacterBody3D).
## Works exactly like the player controller - uses get_gravity(), is_on_floor(), move_and_slide().
## Uses move_toward for smooth deceleration like the player.
func _move_toward_target_physics(delta: float) -> void:
	var current_pos = _entity_body.global_position
	var target_flat = Vector3(_current_target_pos.x, 0, _current_target_pos.z)
	var current_flat = Vector3(current_pos.x, 0, current_pos.z)
	var dist = current_flat.distance_to(target_flat)
	
	# Apply gravity (same as player)
	if not _entity_body.is_on_floor():
		_entity_body.velocity += _entity_body.get_gravity() * delta
	
	if dist < _arrival_distance:
		# At target - slow down horizontally using move_toward (same as player)
		_entity_body.velocity.x = move_toward(_entity_body.velocity.x, 0, _entity_speed * delta * 10.0)
		_entity_body.velocity.z = move_toward(_entity_body.velocity.z, 0, _entity_speed * delta * 10.0)
		_entity_body.move_and_slide()
		return
	
	# Calculate horizontal direction toward target
	var dir = (target_flat - current_flat).normalized()
	
	# Set horizontal velocity toward target (same pattern as player)
	_entity_body.velocity.x = dir.x * _entity_speed
	_entity_body.velocity.z = dir.z * _entity_speed
	
	# Move using physics (handles collisions, slopes, stairs)
	_entity_body.move_and_slide()
	
	# If we hit a wall, pick a new random target to avoid getting stuck
	if _entity_body.is_on_wall():
		# Get a random position on the current floor as a new target
		_current_target_pos = _get_random_position_on_floor(_current_floor)
		_move_timer = 0.0
	
	# Update current floor based on position
	_current_floor = _get_floor_of_position(_entity_body.global_position)

## Gets which floor a position is on.
func _get_floor_of_position(pos: Vector3) -> int:
	if pos.y < -0.5:
		return -1  # Basement
	elif pos.y > 2.5:
		return 1   # Upper floor
	else:
		return 0   # Ground floor

## Gets a random position on the specified floor.
func _get_random_position_on_floor(target_floor: int) -> Vector3:
	match target_floor:
		-1:
			return STALK_BASEMENT[randi() % STALK_BASEMENT.size()]
		1:
			return STALK_UPPER[randi() % STALK_UPPER.size()]
		_:
			return STALK_GROUND[randi() % STALK_GROUND.size()]

## Moves the entity to a specific floor (uses stairs).
func _move_to_floor(target_floor: int) -> void:
	if target_floor == _current_floor:
		return
	
	# Set target to stair position for the target floor
	match target_floor:
		-1:
			_current_target_pos = BASEMENT_STAIRS_BOTTOM
		1:
			_current_target_pos = STAIR_TOP
		_:
			_current_target_pos = STAIR_BOTTOM

## Gets a position near the player.
func _get_nearby_position(distance: float) -> Vector3:
	if not _player:
		return _get_random_position_on_floor(_current_floor)
	
	var angle = randf_range(0, TAU)
	var offset = Vector3(cos(angle), 0, sin(angle)) * distance
	return _player.global_position + offset

## Kills the player.
func _kill_player() -> void:
	_current_state = EntityState.KILLING
	_entity_body.visible = true
	_is_visible_glimpse = false
	
	# Don't teleport - walk toward the player instead
	if _player:
		_current_target_pos = _player.global_position + Vector3(0, 0, 2)
	
	player_killed.emit()
	print("ENTITY KILLED THE PLAYER!")
	
	# Flash the glow
	if _glow:
		_glow.light_energy = 5.0

func _hide_entity() -> void:
	_entity_body.visible = false
	_is_visible_glimpse = false
	entity_disappeared.emit()

func _update_entity_visual(delta: float) -> void:
	if not _entity_body.visible:
		return
	
	# ALWAYS face the player - the Entity never shows its back
	if _player:
		var look_target = _player.global_position
		look_target.y = _entity_body.global_position.y
		_entity_body.look_at(look_target, Vector3.UP)
	
	# Pulse the glow based on gaze progress
	if _glow:
		var base_glow = 0.3 + _gaze_progress * 2.0
		_glow.light_energy = base_glow + sin(Time.get_ticks_msec() * 0.003) * 0.2

## Get the current gaze progress (0.0 to 1.0).
func get_gaze_progress() -> float:
	return _gaze_progress

## Get the current entity state.
func get_entity_state() -> EntityState:
	return _current_state

## Get the current watch intensity (for HUD effects).
func get_watch_intensity() -> float:
	return _gaze_progress
