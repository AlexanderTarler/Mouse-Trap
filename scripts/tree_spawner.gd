extends Node3D

## Grid Blanket Spawner — replaces the old ring-based tree spawning with a
## physics-aware nested grid system. Uses downward raycasts to find the actual
## ground height, avoids roads, trails, and the cabin footprint.
@export var spawner_enabled: bool = true
## Array of tree PackedScenes to randomly choose from
@export var tree_scenes: Array[PackedScene]

## Array of foliage PackedScenes (bushes, ferns, mushrooms, weeds) — purely aesthetic, NO colliders
@export var foliage_scenes: Array[PackedScene]

## Direction of the road (0 is East)
@export var road_angle: float = 0.0

## Width of the "no tree" zone along the road
@export var road_gap_width: float = 0.8

## Half-size of the square map area. Loops from -map_bounds_size to +map_bounds_size on X and Z
@export var map_bounds_size: float = 80.0

## Distance between placement attempts in the grid
@export var grid_step: float = 4.0

## Random displacement added to each grid position to break up grid lines
@export var position_jitter: float = 2.0

## Probability (0.0–1.0) that a given grid cell actually spawns a tree.
## Set lower to thin out the forest and reduce lag.
@export var spawn_chance: float = 0.55

## Probability (0.0–1.0) that a given grid cell spawns foliage alongside trees.
@export var foliage_spawn_chance: float = 0.35

## How many foliage pieces to spawn per tree (1 = sparse, 3-5 = lush forest floor)
@export var foliage_per_tree: int = 4

## Probability (0.0–1.0) that a grid cell spawns standalone foliage even without a tree.
@export var standalone_foliage_chance: float = 0.6

## Maximum number of standalone foliage pieces to spawn (safety cap).
@export var max_foliage_count: int = 2000

## Maximum number of trees to spawn (safety cap to prevent lag).
@export var max_tree_count: int = 800

## Center of the cabin — trees within cabin_exclusion_radius will be skipped
@export var cabin_position: Vector3 = Vector3(9.009, 0, 0.409)

## Radius around the cabin where no trees are placed (12m to prevent clipping)
@export var cabin_exclusion_radius: float = 12.0


func _ready() -> void:
	if not spawner_enabled:
		print("TreeSpawner is disabled via Inspector. Skipping generation.")
		return
	else:	
		# Auto-populate PizzaDoggy PSX assets if arrays are empty
		_load_pizzadoggy_assets()
		_spawn_trees()
		# Second pass: fill the forest floor with standalone foliage
		_spawn_standalone_foliage()


func _spawn_trees() -> void:
	var trees_spawned: int = 0
	
	# Nested grid loop — covers the entire map area evenly
	for x_pos in range(-int(map_bounds_size), int(map_bounds_size), int(grid_step)):
		for z_pos in range(-int(map_bounds_size), int(map_bounds_size), int(grid_step)):
			# Safety cap: stop spawning once we hit the limit
			if trees_spawned >= max_tree_count:
				print("TreeSpawner: Reached max_tree_count (%d). Stopping." % max_tree_count)
				return
			
			# Density control: only a fraction of grid cells actually spawn a tree
			if randf() > spawn_chance:
				continue
			
			# Add jitter to break up grid lines
			var target_x = x_pos + randf_range(-position_jitter, position_jitter)
			var target_z = z_pos + randf_range(-position_jitter, position_jitter)
			
			# --- ROAD ANGLE CHECK ---
			# Calculate the angle of this position relative to the origin
			var angle = atan2(target_z, target_x)
			var angle_diff = abs(wrapf(angle - road_angle, -PI, PI))
			if angle_diff < road_gap_width:
				continue
			
			# --- PHYSICS RAYCAST — find the actual ground height ---
			var space_state = get_world_3d().direct_space_state
			if not space_state:
				continue
			
			var ray_from = Vector3(target_x, 30.0, target_z)
			var ray_to = Vector3(target_x, -20.0, target_z)
			var query = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			
			var result = space_state.intersect_ray(query)
			if result.is_empty():
				continue  # No ground found — skip
			
			# --- CABIN COLLIDER FAILSAFE ---
			# If the raycast hit the cabin/house itself, skip (defeats badly-offset 3D meshes)
			if result.collider.name.containsn("cabin") or result.collider.name.containsn("house"):
				continue
			
			# --- TRAIL MESH AVOIDANCE ---
			# Check if the collider is a trail mesh (narrow walking paths)
			if result.collider.name.contains("TrailMesh"):
				continue
			
			# --- CABIN FOOTPRINT CHECK (moderate exclusion zone) ---
			# Keep a reasonable clearing around the cabin structure itself.
			# The cabin is roughly at (9, 0, 0.4) — we exclude a ~12m radius circle.
			var ground_point = result.position
			var cabin_cx = cabin_position.x
			var cabin_cz = cabin_position.z
			var dist_to_cabin = Vector2(ground_point.x - cabin_cx, ground_point.z - cabin_cz).length()
			if dist_to_cabin < cabin_exclusion_radius:
				continue
			
			# --- ASSET PLACEMENT ---
			# Pick a random tree scene
			var tree_resource = tree_scenes.pick_random()
			if not tree_resource:
				continue
			var tree = tree_resource.instantiate()
			add_child(tree)
			trees_spawned += 1
			
			# Position at the exact ground intersection point
			tree.global_position = ground_point
			
			# Random Y rotation
			tree.rotation.y = randf_range(0, TAU)
			
			# --- ORIGIN OFFSET NORMALIZATION (PizzaDoggy PSX models) ---
			# PizzaDoggy GLB imports often nest MeshInstance3D nodes inside Node3D wrappers
			# with non-zero local transforms. We recursively traverse ALL descendants to
			# neutralize offsets so the model sits correctly at the parent origin.
			_center_node_hierarchy(tree)
			
			# Ensure the tree has a collider
			_ensure_collider(tree)
			
			# --- FOLIAGE PLACEMENT (non-colliding undergrowth) ---
			_spawn_foliage_near(ground_point, space_state)
	
	print("TreeSpawner: Finished. Spawned %d trees." % trees_spawned)


func _spawn_foliage_near(ground_pos: Vector3, space_state: PhysicsDirectSpaceState3D) -> void:
	## Places decorative foliage (ferns, grass, mushrooms, stones) around a tree position.
	## Spawns multiple pieces per tree for a lush forest floor.
	## Foliage NEVER gets colliders — purely aesthetic.
	if foliage_scenes.is_empty():
		return
	
	# Roll the dice for foliage at this location
	if randf() > foliage_spawn_chance:
		return
	
	# Spawn multiple foliage pieces around the tree for a lush undergrowth
	var count = randi_range(1, foliage_per_tree)
	for i in range(count):
		_place_single_foliage(ground_pos, space_state)


func _place_single_foliage(ground_pos: Vector3, space_state: PhysicsDirectSpaceState3D) -> void:
	## Places one piece of foliage at a random offset from the given position.
	var foliage_resource = foliage_scenes.pick_random()
	if not foliage_resource:
		return
	
	# Random offset around the tree (0.3 to 3.0 meters away)
	var offset_dist = randf_range(0.3, 3.0)
	var offset_angle = randf_range(0, TAU)
	var foliage_x = ground_pos.x + cos(offset_angle) * offset_dist
	var foliage_z = ground_pos.z + sin(offset_angle) * offset_dist
	
	# --- CABIN EXCLUSION CHECK ---
	var dist_to_cabin = Vector2(foliage_x - cabin_position.x, foliage_z - cabin_position.z).length()
	if dist_to_cabin < cabin_exclusion_radius:
		return
	
	# Raycast to find ground height at foliage position
	var ray_from = Vector3(foliage_x, 30.0, foliage_z)
	var ray_to = Vector3(foliage_x, -20.0, foliage_z)
	var query = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return
	
	# Skip if raycast hit the cabin/house or trail mesh
	if result.collider.name.containsn("cabin") or result.collider.name.containsn("house"):
		return
	if result.collider.name.contains("TrailMesh"):
		return
	
	var foliage_ground = result.position
	
	var foliage = foliage_resource.instantiate()
	add_child(foliage)
	foliage.global_position = foliage_ground
	foliage.rotation.y = randf_range(0, TAU)
	
	# Random scale variation for natural look
	var scale_var = randf_range(0.7, 1.3)
	foliage.scale = Vector3(scale_var, scale_var, scale_var)
	
	# CRITICAL: Foliage NEVER gets colliders — skip _ensure_collider entirely.
	# The player and Entity must be able to walk straight through bushes.
	
	# --- ORIGIN OFFSET NORMALIZATION (PizzaDoggy PSX foliage) ---
	_center_node_hierarchy(foliage)


func _spawn_standalone_foliage() -> void:
	## Second pass: fills the entire forest floor with standalone foliage
	## (ferns, grass, mushrooms, stones) on a finer grid between trees.
	## This creates a dense, natural-looking undergrowth layer.
	if foliage_scenes.is_empty():
		return
	
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return
	
	var foliage_spawned: int = 0
	var foliage_grid_step = 2.0  # Finer grid than trees (4.0)
	
	for x_pos in range(-int(map_bounds_size), int(map_bounds_size), int(foliage_grid_step)):
		for z_pos in range(-int(map_bounds_size), int(map_bounds_size), int(foliage_grid_step)):
			if foliage_spawned >= max_foliage_count:
				print("TreeSpawner: Reached max_foliage_count (%d). Stopping standalone foliage." % max_foliage_count)
				return
			
			# Density control
			if randf() > standalone_foliage_chance:
				continue
			
			var target_x = x_pos + randf_range(-0.5, 0.5)
			var target_z = z_pos + randf_range(-0.5, 0.5)
			
			# --- CABIN EXCLUSION ---
			var dist_to_cabin = Vector2(target_x - cabin_position.x, target_z - cabin_position.z).length()
			if dist_to_cabin < cabin_exclusion_radius:
				continue
			
			# Raycast to find ground
			var ray_from = Vector3(target_x, 30.0, target_z)
			var ray_to = Vector3(target_x, -20.0, target_z)
			var query = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			
			var result = space_state.intersect_ray(query)
			if result.is_empty():
				continue
			
			# Skip cabin, house, trail meshes
			if result.collider.name.containsn("cabin") or result.collider.name.containsn("house"):
				continue
			if result.collider.name.contains("TrailMesh"):
				continue
			
			var ground_pos = result.position
			
			var foliage_resource = foliage_scenes.pick_random()
			if not foliage_resource:
				continue
			
			var foliage = foliage_resource.instantiate()
			add_child(foliage)
			foliage_spawned += 1
			foliage.global_position = ground_pos
			foliage.rotation.y = randf_range(0, TAU)
			
			# Random scale variation
			var scale_var = randf_range(0.7, 1.3)
			foliage.scale = Vector3(scale_var, scale_var, scale_var)
			
			_center_node_hierarchy(foliage)
	
	print("TreeSpawner: Spawned %d standalone foliage pieces." % foliage_spawned)


func _load_pizzadoggy_assets() -> void:
	## Auto-populates tree_scenes and foliage_scenes from PizzaDoggy PSX GLB files
	## if the arrays are empty. This allows the spawner to work without manual
	## inspector assignment.
	var base_path = "res://assets/PSX Nature/Models/GLB/"
	
	# --- TREES (pine + deciduous) ---
	if tree_scenes.is_empty():
		var tree_paths := [
			base_path + "pine_tree_n_1.glb",
			base_path + "pine_tree_n_1_1.glb",
			base_path + "pine_tree_n_1_2.glb",
			base_path + "pine_tree_n_1_3.glb",
			base_path + "pine_tree_n_1_4.glb",
			base_path + "pine_tree_n_2.glb",
			base_path + "pine_tree_n_2_1.glb",
			base_path + "pine_tree_n_2_2.glb",
			base_path + "pine_tree_n_2_3.glb",
			base_path + "pine_tree_n_2_4.glb",
			base_path + "pine_tree_n_3.glb",
			base_path + "pine_tree_n_3_1.glb",
			base_path + "pine_tree_n_3_2.glb",
			base_path + "pine_tree_n_3_3.glb",
			base_path + "pine_tree_n_3_4.glb",
			base_path + "tree_1.glb",
			base_path + "tree_5.glb",
			base_path + "tree_6.glb",
		]
		for path in tree_paths:
			var scene = load(path) as PackedScene
			if scene:
				tree_scenes.append(scene)
		print("TreeSpawner: Auto-loaded %d PizzaDoggy tree scenes." % tree_scenes.size())
	
	# --- FOLIAGE (ferns, grass, mushrooms, stones) ---
	if foliage_scenes.is_empty():
		var foliage_paths := [
			base_path + "fern_1.glb",
			base_path + "fern_2.glb",
			base_path + "fern_3.glb",
			base_path + "grass_1.glb",
			base_path + "grass_2.glb",
			base_path + "grass_3.glb",
			base_path + "grass_4.glb",
			base_path + "mushroom_n_1.glb",
			base_path + "mushroom_n_1_0.glb",
			base_path + "mushroom_n_1_1.glb",
			base_path + "mushroom_n_1_2.glb",
			base_path + "mushroom_n_2.glb",
			base_path + "mushroom_n_2_0.glb",
			base_path + "mushroom_n_2_1.glb",
			base_path + "mushroom_n_2_2.glb",
			base_path + "mushroom_n_3.glb",
			base_path + "mushroom_n_3_1.glb",
			base_path + "mushroom_n_4.glb",
			base_path + "mushroom_n_4_1.glb",
			base_path + "stone_1.glb",
			base_path + "stone_2.glb",
			base_path + "stone_3.glb",
			base_path + "stone_4.glb",
			base_path + "stone_5.glb",
		]
		for path in foliage_paths:
			var scene = load(path) as PackedScene
			if scene:
				foliage_scenes.append(scene)
		print("TreeSpawner: Auto-loaded %d PizzaDoggy foliage scenes." % foliage_scenes.size())


func _center_node_hierarchy(node: Node3D) -> void:
	## Recursively traverses all descendants and resets local positions to zero.
	## Handles PizzaDoggy GLB imports that nest MeshInstance3D nodes inside
	## Node3D wrappers with non-zero local transforms.
	for child in node.get_children():
		if child is MeshInstance3D or child is Node3D:
			child.position = Vector3.ZERO
			# Recurse into Node3D wrappers to catch deeper nesting
			if child is Node3D and child.get_child_count() > 0:
				_center_node_hierarchy(child)


func _ensure_collider(tree_node: Node3D) -> void:
	# This checks if the tree already has a StaticBody3D.
	# If not, it adds a simple Cylinder collider.
	if not tree_node.find_child("*StaticBody3D*", true):
		var static_body = StaticBody3D.new()
		var collision_shape = CollisionShape3D.new()
		var cylinder = CylinderShape3D.new()
		
		cylinder.height = 10.0  # Adjust to your tree height
		cylinder.radius = 0.5   # Adjust to your trunk width
		
		collision_shape.shape = cylinder
		static_body.add_child(collision_shape)
		tree_node.add_child(static_body)
		# Move the collider slightly up so it's not halfway in the ground
		collision_shape.position.y = 5.0
