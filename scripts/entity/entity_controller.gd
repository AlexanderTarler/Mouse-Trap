extends CharacterBody3D
class_name EntityController

## "The Entity" - the main antagonist of the game.
## Uses NavigationAgent3D to navigate the map and chase the player.
## Spawned at the edge of the map and relentlessly pursues the player.

## Movement speed of the entity
@export var speed: float = 4.0

## How close the entity needs to get to the player to "catch" them
@export var catch_distance: float = 1.5

## Distance at which the entity starts chasing the player
@export var chase_range: float = 50.0

## How often to recalculate the path (seconds)
@export var path_update_interval: float = 0.5

## Maximum step height the entity can climb (for stairs)
@export var max_step_height: float = 0.7

## How far ahead to check for steps
@export var step_check_distance: float = 0.5

## The orb/mesh visual
@onready var _orb: MeshInstance3D = $OrbMesh

## Navigation agent for pathfinding
@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D

## Collision shape (sphere)
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

## Timer for path recalculation
var _path_timer: float = 0.0

## Reference to the player node
var _player: Node3D = null

## Whether the entity is active and chasing
var _is_active: bool = true

## Whether the entity has been spawned and is ready
var _ready_to_chase: bool = false

## Whether we were on the floor last frame (for stair climbing)
var _was_on_floor: bool = false


func _ready() -> void:
	# Find the player
	_find_player()
	
	# Add to entity group
	add_to_group("entity")
	
	# Start hidden by default — the entity should only be visible at night
	visible = false
	
	# Wait a few frames for the navigation mesh to be ready
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Listen for day/night cycle
	if Engine.has_singleton("GameTime"):
		var gt = Engine.get_singleton("GameTime")
		gt.night_started.connect(_on_night_started)
		gt.day_started.connect(_on_day_started)
		# Start inactive during day — only spawn when night falls
		if gt.is_day:
			deactivate()
			# Hide the entity during the day by moving it far away
			global_position = Vector3(0, -100, 0)
		else:
			activate()
			spawn_at_map_edge()
	
	_ready_to_chase = true
	print("The Entity has awakened at %s" % global_position)


func _on_night_started() -> void:
	activate()
	# Spawn at a new map edge when night falls
	spawn_at_map_edge()


func _on_day_started() -> void:
	deactivate()
	# Hide the entity during the day by moving it far away
	global_position = Vector3(0, -100, 0)
	velocity = Vector3.ZERO


func _find_player() -> void:
	# Try to find the player by group
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node3D
		print("Entity found player: ", _player.name)
	else:
		# Fallback: search the scene tree
		_player = _find_node_by_type(get_tree().root, "CharacterBody3D")
		if _player:
			print("Entity found player via fallback: ", _player.name)


func _find_node_by_type(node: Node, type_name: String) -> Node3D:
	if node.is_class(type_name):
		return node as Node3D
	for child in node.get_children():
		var result = _find_node_by_type(child, type_name)
		if result:
			return result
	return null


func _physics_process(delta: float) -> void:
	if not _ready_to_chase or not _is_active:
		return
	
	if not _player:
		# Keep trying to find the player
		_find_player()
		return
	
	# Apply gravity
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	# Update path to player
	_path_timer += delta
	if _path_timer >= path_update_interval:
		_path_timer = 0.0
		_update_path_to_player()
	
	# Check if we've caught the player
	var dist_to_player = global_position.distance_to(_player.global_position)
	if dist_to_player <= catch_distance:
		_on_caught_player()
		return
	
	# Get movement direction
	var move_dir: Vector3
	
	# Move along the navigation path
	if _nav_agent.is_navigation_finished():
		# Path finished or no path - try to move directly toward player
		move_dir = _get_direction_to_player()
	else:
		# Follow the navigation path
		var next_pos = _nav_agent.get_next_path_position()
		move_dir = (next_pos - global_position).normalized()
		move_dir.y = 0.0
	
	# Set horizontal velocity
	if move_dir.length() > 0.01:
		velocity.x = move_dir.x * speed
		velocity.z = move_dir.z * speed
		
		# Stair climbing: step-up check before move_and_slide()
		if _was_on_floor and is_on_floor():
			_try_step_up(move_dir)
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	
	move_and_slide()
	
	# Store floor state for next frame
	_was_on_floor = is_on_floor()
	
	# Rotate the orb for visual effect
	if _orb:
		_orb.rotation.x += delta * 1.5
		_orb.rotation.z += delta * 1.0


## Gets the horizontal direction toward the player.
func _get_direction_to_player() -> Vector3:
	if not _player:
		return Vector3.ZERO
	
	var direction = (_player.global_position - global_position).normalized()
	direction.y = 0.0
	return direction


func _update_path_to_player() -> void:
	if not _player:
		return
	
	var dist = global_position.distance_to(_player.global_position)
	
	# Only chase if within range
	if dist <= chase_range:
		_nav_agent.target_position = _player.global_position
	else:
		# Player is out of range - stop moving
		velocity = Vector3.ZERO


## Attempts to step up onto stairs or small obstacles.
## Adapted from the player's stair climbing system for a sphere-shaped body.
func _try_step_up(direction: Vector3) -> void:
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return
	
	# Get the sphere shape info
	if not _collision_shape or not _collision_shape.shape:
		return
	var sphere: SphereShape3D = _collision_shape.shape as SphereShape3D
	if not sphere:
		return
	
	# Calculate the bottom of the sphere (where the entity's "feet" are)
	var sphere_bottom_y = global_position.y - sphere.radius
	
	# --- RAY 1: Cast down at current position to get the floor height ---
	var down_here_start = Vector3(global_position.x, sphere_bottom_y + 0.1, global_position.z)
	var down_here_end = Vector3(global_position.x, sphere_bottom_y - max_step_height - 0.5, global_position.z)
	
	var here_query = PhysicsRayQueryParameters3D.create(down_here_start, down_here_end)
	here_query.collide_with_areas = false
	here_query.collide_with_bodies = true
	here_query.exclude = [self]
	
	var here_result = space_state.intersect_ray(here_query)
	if here_result.is_empty():
		return
	
	var floor_y = here_result.position.y
	
	# --- RAY 2: Cast down ahead of the entity to check floor height on the step ---
	var ahead_pos = global_position + direction * (step_check_distance + sphere.radius * 0.5)
	var down_ahead_start = Vector3(ahead_pos.x, sphere_bottom_y + max_step_height + 0.5, ahead_pos.z)
	var down_ahead_end = Vector3(ahead_pos.x, sphere_bottom_y - 0.5, ahead_pos.z)
	
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
	var check_height = sphere_bottom_y + max_step_height + 0.1
	var check_start = Vector3(global_position.x, check_height, global_position.z)
	var check_end = check_start + direction * (step_check_distance + sphere.radius)
	
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


func _on_caught_player() -> void:
	print("The Entity has caught the player!")
	_is_active = false
	velocity = Vector3.ZERO
	
	# Emit a signal or trigger game over logic
	if Engine.has_singleton("NightManager"):
		var nm = Engine.get_singleton("NightManager")
		nm.horror_event.emit("entity_caught_player")


## Activates the entity to start chasing.
func activate() -> void:
	_is_active = true
	visible = true
	print("The Entity is now active!")


## Deactivates the entity (stops chasing and hides it).
func deactivate() -> void:
	_is_active = false
	velocity = Vector3.ZERO
	visible = false
	print("The Entity has been deactivated.")


## Sets the entity's position to a random edge of the map.
func spawn_at_map_edge() -> void:
	# The map is roughly 80x80 units (from -40 to 40 in x and z)
	# Pick a random edge position
	var edge = randi() % 4
	var spawn_pos: Vector3
	
	match edge:
		0:  # Top edge (positive Z)
			spawn_pos = Vector3(randf_range(-35, 35), 0, 38)
		1:  # Bottom edge (negative Z)
			spawn_pos = Vector3(randf_range(-35, 35), 0, -38)
		2:  # Left edge (negative X)
			spawn_pos = Vector3(-38, 0, randf_range(-35, 35))
		3:  # Right edge (positive X)
			spawn_pos = Vector3(38, 0, randf_range(-35, 35))
	
	global_position = spawn_pos
	print("Entity spawned at map edge: ", spawn_pos)
