extends Node3D

## TrailSpawner - Creates winding forest trails from the cabin to multiple destinations.
## Places dense trees along the trail edges to create narrow, winding paths.
## Also generates visible trail meshes with a distinct dirt texture.

@export var spawner_enabled: bool = true

@export var tree_scenes: Array[PackedScene]

## Array of foliage PackedScenes (bushes, ferns, mushrooms, weeds) — purely aesthetic, NO colliders
@export var foliage_scenes: Array[PackedScene]

## Probability (0.0–1.0) that a given placement spawns foliage alongside trees.
@export var foliage_spawn_chance: float = 0.4

## How many foliage pieces to spawn per tree (1 = sparse, 3-5 = lush forest floor)
@export var foliage_per_tree: int = 3

## Probability (0.0–1.0) that a grid cell spawns standalone foliage even without a tree.
@export var standalone_foliage_chance: float = 0.5

## Maximum number of standalone foliage pieces to spawn (safety cap).
@export var max_foliage_count: int = 1500

@export var trail_width: float = 1.5     # Width of the clear path
@export var tree_density: int = 300      # Number of trees along trail
@export var cabin_position: Vector3 = Vector3(9.009, 0, 0.409)  # Cabin front door position

## Array of destination positions to create trails to (e.g. nest locations)
@export var trail_destinations: Array[Vector3] = []

## The winding trail waypoints for each trail (indexed by destination)
var trails: Array[Array] = []  # Array of Array[Vector3]


func _ready() -> void:
	if not spawner_enabled:
		return
	# Auto-populate PizzaDoggy PSX assets if arrays are empty
	_load_pizzadoggy_assets()
	
	# Always generate the main spawn-to-cabin trail
	_generate_main_trail()
	
	# Dynamically discover nest positions from the scene tree
	var nest_nodes = get_tree().get_nodes_in_group("hasselmus_nests")
	trail_destinations.clear()
	for nest in nest_nodes:
		trail_destinations.append(nest.global_position)
	
	# Generate trails to each destination
	for dest in trail_destinations:
		_generate_destination_trail(dest)
	
	# Generate meshes for all trails
	for i in range(trails.size()):
		_generate_trail_mesh(i)
	
	_debug_log_trail_info()
	
	# Defer tree spawning to ensure the world and physics are fully initialized
	call_deferred("_spawn_trail_trees")
	
	# Defer standalone foliage to fill the forest floor
	call_deferred("_spawn_standalone_foliage")


func _generate_main_trail() -> void:
	## Generate the main winding path from far away to the cabin
	var trail: Array[Vector3] = []
	var segments = 20
	
	for i in range(segments + 1):
		var t = float(i) / float(segments)
		var progress = 1.0 - t
		
		var wind_angle = t * 4.0 * PI
		var wind_amplitude = lerpf(15.0, 3.0, t)
		var wind_offset = sin(wind_angle) * wind_amplitude
		
		var pos = Vector3(
			cabin_position.x + wind_offset,
			cabin_position.y,
			cabin_position.z - (200.0 * progress)
		)
		trail.append(pos)
	
	# Ensure the last point is right at the cabin door
	trail.append(Vector3(cabin_position.x, cabin_position.y, cabin_position.z))
	trails.append(trail)


func _generate_destination_trail(dest: Vector3) -> void:
	## Generate a winding path from the cabin to a destination
	var trail: Array[Vector3] = []
	var distance = cabin_position.distance_to(dest)
	if distance < 1.0:
		return  # Skip if destination is too close
	
	var segments = max(6, int(distance / 10.0))  # One waypoint per ~10 meters
	
	for i in range(segments + 1):
		var t = float(i) / float(segments)
		
		# Winding offset perpendicular to the direction
		var wind_angle = t * 3.0 * PI
		var wind_amplitude = lerpf(5.0, 1.0, t)  # Moderate winding
		var wind_offset = sin(wind_angle) * wind_amplitude
		
		# Direction from cabin to destination
		var dir_to_dest = (dest - cabin_position).normalized()
		var perp = Vector3(-dir_to_dest.z, 0, dir_to_dest.x).normalized()
		
		var pos = cabin_position.lerp(dest, t)
		pos += perp * wind_offset
		pos.y = cabin_position.y  # Keep at ground level
		
		trail.append(pos)
	
	# Ensure the last point is right at the destination
	trail.append(Vector3(dest.x, cabin_position.y, dest.z))
	trails.append(trail)


func _generate_trail_mesh(trail_index: int) -> void:
	## Creates a visible trail surface along the winding path.
	## Snaps each vertex to the physical terrain so the trail sits on top of the ground.
	if trail_index >= trails.size():
		return
	var trail_points = trails[trail_index]
	if trail_points.size() < 2:
		return
	
	# Get physics space for ground snapping
	var space_state = null
	if get_world_3d():
		space_state = get_world_3d().direct_space_state
	
	# Create a natural dirt trail material with vertex alpha blending
	var trail_material = StandardMaterial3D.new()
	trail_material.albedo_color = Color(0.25, 0.18, 0.12, 1)  # Dark dirt brown
	trail_material.roughness = 1.0  # Matte, unreflective earth
	trail_material.metallic = 0.0
	trail_material.emission_enabled = false
	trail_material.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	trail_material.uv1_scale = Vector3(1, 1, 1)
	trail_material.uv1_triplanar = true
	trail_material.uv1_triplanar_sharpness = 0.5
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.vertex_color_use_as_albedo = true
	trail_material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
	trail_material.no_depth_test = false
	
	var half_width = trail_width * 0.5
	var fade_width = half_width * 0.4  # Outer 40% on each side fades to transparent
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for i in range(trail_points.size() - 1):
		var p0 = trail_points[i]
		var p1 = trail_points[i + 1]
		
		if i == 0 or i == trail_points.size() - 2:
			print("[DEBUG TRAIL MESH] Trail ", trail_index, " Segment ", i, " positions: p0=", p0, " p1=", p1)
		
		# Snap both waypoints to the physical ground via raycast
		if space_state:
			p0 = _snap_to_ground(space_state, p0)
			p1 = _snap_to_ground(space_state, p1)
		
		var dir = (p1 - p0).normalized()
		if dir.length() < 0.001:
			dir = Vector3.FORWARD
		
		var perp = Vector3(-dir.z, 0, dir.x).normalized()
		
		# Outer edge vertices (full transparency)
		var a = p0 + perp * half_width       # right edge at p0
		var b = p0 - perp * half_width       # left edge at p0
		var c = p1 - perp * half_width       # left edge at p1
		var d = p1 + perp * half_width       # right edge at p1
		
		# Inner center vertices (full opacity)
		var inner_a = p0 + perp * (half_width - fade_width)  # right inner at p0
		var inner_b = p0 - perp * (half_width - fade_width)  # left inner at p0
		var inner_c = p1 - perp * (half_width - fade_width)  # left inner at p1
		var inner_d = p1 + perp * (half_width - fade_width)  # right inner at p1
		
		# Place trail virtually flat on the terrain (1mm above to avoid Z-fighting)
		var y_offset = 0.001
		a.y += y_offset
		b.y += y_offset
		c.y += y_offset
		d.y += y_offset
		inner_a.y += y_offset
		inner_b.y += y_offset
		inner_c.y += y_offset
		inner_d.y += y_offset
		
		# --- LEFT FADE QUAD (b -> inner_b -> inner_c -> c) ---
		# Outer edge (b, c) = transparent, Inner edge (inner_b, inner_c) = opaque
		st.set_color(Color(1, 1, 1, 0))
		st.set_uv(Vector2(0, 0))
		st.add_vertex(b)
		st.set_color(Color(1, 1, 1, 1))
		st.set_uv(Vector2(1, 0))
		st.add_vertex(inner_b)
		st.set_color(Color(1, 1, 1, 1))
		st.set_uv(Vector2(1, 1))
		st.add_vertex(inner_c)
		
		st.set_color(Color(1, 1, 1, 0))
		st.set_uv(Vector2(0, 0))
		st.add_vertex(b)
		st.set_color(Color(1, 1, 1, 1))
		st.set_uv(Vector2(1, 1))
		st.add_vertex(inner_c)
		st.set_color(Color(1, 1, 1, 0))
		st.set_uv(Vector2(0, 1))
		st.add_vertex(c)
		
		# --- CENTER OPAQUE QUAD (inner_b -> inner_a -> inner_d -> inner_c) ---
		st.set_color(Color(1, 1, 1, 1))
		st.set_uv(Vector2(0, 0))
		st.add_vertex(inner_b)
		st.set_color(Color(1, 1, 1, 1))
		st.set_uv(Vector2(1, 0))
		st.add_vertex(inner_a)
		st.set_color(Color(1, 1, 1, 1))
		st.set_uv(Vector2(1, 1))
		st.add_vertex(inner_d)
		
		st.set_color(Color(1, 1, 1, 1))
		st.set_uv(Vector2(0, 0))
		st.add_vertex(inner_b)
		st.set_color(Color(1, 1, 1, 1))
		st.set_uv(Vector2(1, 1))
		st.add_vertex(inner_d)
		st.set_color(Color(1, 1, 1, 1))
		st.set_uv(Vector2(0, 1))
		st.add_vertex(inner_c)
		
		# --- RIGHT FADE QUAD (inner_a -> a -> d -> inner_d) ---
		st.set_color(Color(1, 1, 1, 1))
		st.set_uv(Vector2(0, 0))
		st.add_vertex(inner_a)
		st.set_color(Color(1, 1, 1, 0))
		st.set_uv(Vector2(1, 0))
		st.add_vertex(a)
		st.set_color(Color(1, 1, 1, 0))
		st.set_uv(Vector2(1, 1))
		st.add_vertex(d)
		
		st.set_color(Color(1, 1, 1, 1))
		st.set_uv(Vector2(0, 0))
		st.add_vertex(inner_a)
		st.set_color(Color(1, 1, 1, 0))
		st.set_uv(Vector2(1, 1))
		st.add_vertex(d)
		st.set_color(Color(1, 1, 1, 1))
		st.set_uv(Vector2(0, 1))
		st.add_vertex(inner_d)
	
	st.generate_normals()
	var mesh = st.commit()
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = trail_material
	mesh_instance.name = "TrailMesh_%d" % trail_index
	# Make invisible to the player while keeping the mesh in the physics world
	# so tree_spawner.gd can still detect "TrailMesh" via raycasts for avoidance.
	mesh_instance.visible = false
	add_child(mesh_instance)


func _debug_log_trail_info() -> void:
	print("[TrailSpawner] === TRAIL DEBUG INFO ===")
	print("[TrailSpawner] Total trails: %d" % trails.size())
	for ti in range(trails.size()):
		var trail_points = trails[ti]
		if trail_points.size() < 2:
			continue
		var trail_start = trail_points[0]
		var trail_end = trail_points[trail_points.size() - 1]
		var straight_line_dist = trail_start.distance_to(trail_end)
		
		var path_length = 0.0
		for i in range(trail_points.size() - 1):
			path_length += trail_points[i].distance_to(trail_points[i + 1])
		
		var straightness_ratio = path_length / straight_line_dist if straight_line_dist > 0 else 1.0
		
		print("[TrailSpawner] Trail %d: start=(%.1f, %.1f, %.1f) end=(%.1f, %.1f, %.1f) dist=%.1f path=%.1f ratio=%.2f waypoints=%d" % [
			ti,
			trail_start.x, trail_start.y, trail_start.z,
			trail_end.x, trail_end.y, trail_end.z,
			straight_line_dist, path_length, straightness_ratio, trail_points.size()
		])
		
		# Place debug markers (disabled - no longer needed)
		#var color_start = Color.RED if ti == 0 else Color(0.5 + ti * 0.2, 0, 1.0 - ti * 0.2, 1)
		#_place_debug_marker(trail_start, color_start, "Trail%d_Start" % ti)
		#_place_debug_marker(trail_end, Color.GREEN, "Trail%d_End" % ti)
		#for i in range(trail_points.size()):
		#	var wp = trail_points[i]
		#	var color = Color.YELLOW if i % 2 == 0 else Color.ORANGE
		#	_place_debug_marker(wp, color, "Trail%d_WP_%d" % [ti, i])
	
	print("[TrailSpawner] =========================")


func _place_debug_marker(pos: Vector3, color: Color, name_str: String) -> void:
	var marker = MeshInstance3D.new()
	marker.name = name_str
	var box = BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	box.material = mat
	marker.mesh = box
	marker.position = pos
	marker.position.y += 0.5
	add_child(marker)


func _spawn_trail_trees() -> void:
	if tree_scenes.is_empty():
		print("TrailSpawner: No tree scenes assigned!")
		return
	
	var space_state = null
	if get_world_3d():
		space_state = get_world_3d().direct_space_state
	
	# Collect all trail points from all trails for distance checking
	var all_trail_points: Array[Vector3] = []
	for trail in trails:
		all_trail_points.append_array(trail)
	
	# Calculate the spawn point (start of main trail) for the clear area.
	# The Entity spawns at trails[0][0] (the trailhead), so we need a wide
	# 15-meter clearing to ensure the Entity's safe-spawn collision checks
	# (GATE 2: CylinderShape overlap test) don't clip into tree trunks.
	var trailhead = trails[0][0] if trails.size() > 0 and trails[0].size() >= 2 else Vector3.ZERO
	var spawn_point = trailhead
	var clear_radius = 15.0
	
	# Dense forest: trees placed close together just outside the trail corridor
	# Creates a labyrinth-like feel with narrow, winding paths
	var min_distance_from_trail = trail_width * 0.5 + 0.5  # Just 0.5m outside trail edge
	var max_distance_from_trail = trail_width * 0.5 + 6.0  # Up to 6m from trail edge
	var placed_positions: Array[Vector3] = []
	
	# Use a grid-based approach for dense, even coverage
	var grid_step = 1.2  # Place trees every 1.2 meters in a grid pattern
	
	# Collect all trail segments for grid coverage
	for trail_idx in range(trails.size()):
		var trail_points = trails[trail_idx]
		if trail_points.size() < 2:
			continue
		
		# Walk along the trail and place trees on both sides
		for seg_i in range(trail_points.size() - 1):
			var p0 = trail_points[seg_i]
			var p1 = trail_points[seg_i + 1]
			var seg_dir = (p1 - p0).normalized()
			if seg_dir.length() < 0.001:
				seg_dir = Vector3.FORWARD
			var perp = Vector3(-seg_dir.z, 0, seg_dir.x).normalized()
			var seg_length = p0.distance_to(p1)
			
			# Place trees along this segment at grid intervals
			var steps = max(1, int(seg_length / grid_step))
			for s in range(steps + 1):
				var t = float(s) / float(steps)
				var trail_pos = p0.lerp(p1, t)
				
				# Place trees on both sides at varying distances
				for side in [-1.0, 1.0]:
					var dist_from_trail = min_distance_from_trail + randf_range(0.0, max_distance_from_trail - min_distance_from_trail)
					var tree_pos = trail_pos + perp * side * dist_from_trail
					
					# Small jitter for natural look
					tree_pos.x += randf_range(-0.3, 0.3)
					tree_pos.z += randf_range(-0.3, 0.3)
					
					# Check against ALL trails (strict)
					var too_close_to_any_trail = false
					for other_trail in trails:
						var closest_dist = _distance_to_trail(other_trail, tree_pos)
						if closest_dist < trail_width * 0.5 + 0.3:
							too_close_to_any_trail = true
							break
					if too_close_to_any_trail:
						continue
					
					# Skip if too close to the cabin (circular exclusion zone)
					var dist_to_cabin = Vector2(tree_pos.x - cabin_position.x, tree_pos.z - cabin_position.z).length()
					if dist_to_cabin < 12.0:
						continue
						
					# Skip if too close to spawn
					if tree_pos.distance_to(spawn_point) < clear_radius:
						continue
					
					# Skip if too close to another placed tree (tight spacing for dense forest)
					var too_close_to_other = false
					for placed in placed_positions:
						if tree_pos.distance_to(placed) < 1.5:
							too_close_to_other = true
							break
					if too_close_to_other:
						continue
					
					var ground_pos = tree_pos
					if space_state:
						ground_pos = _snap_to_ground(space_state, tree_pos)
					
					# CABIN COLLIDER FAILSAFE — skip if raycast hit the cabin/house itself
					if space_state:
						var ray_from = Vector3(tree_pos.x, 30.0, tree_pos.z)
						var ray_to = Vector3(tree_pos.x, -20.0, tree_pos.z)
						var q = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
						q.collide_with_areas = false
						q.collide_with_bodies = true
						var r = space_state.intersect_ray(q)
						if not r.is_empty() and (r.collider.name.containsn("cabin") or r.collider.name.containsn("house")):
							continue
					
					var tree_resource = tree_scenes.pick_random()
					if not tree_resource:
						continue
					
					var tree = tree_resource.instantiate()
					add_child(tree)
					_center_node_hierarchy(tree)
					tree.global_position = ground_pos
					tree.rotation.y = randf_range(0, TAU)
					
					_ensure_collider(tree)
					placed_positions.append(ground_pos)
					
					# --- FOLIAGE PLACEMENT (non-colliding undergrowth) ---
					_spawn_foliage_near(ground_pos, space_state)
	
	# Fill in gaps with random trees for extra density
	var remaining = tree_density - placed_positions.size()
	if remaining > 0:
		for i in range(remaining):
			# Pick a random trail
			var trail_idx = randi() % trails.size()
			var trail_points = trails[trail_idx]
			
			var trail_t = randf_range(0.0, 1.0)
			var trail_pos = _get_point_on_trail(trail_points, trail_t)
			var trail_dir = _get_trail_direction(trail_points, trail_t)
			var perp_dir = Vector3(-trail_dir.z, 0, trail_dir.x).normalized()
			
			var side = 1.0 if randf() > 0.5 else -1.0
			var distance_from_trail = min_distance_from_trail + randf_range(0.0, max_distance_from_trail - min_distance_from_trail)
			
			var tree_pos = trail_pos + perp_dir * side * distance_from_trail
			tree_pos.x += randf_range(-0.5, 0.5)
			tree_pos.z += randf_range(-0.5, 0.5)
			
			# Check against ALL trails
			var too_close_to_any_trail = false
			for other_trail in trails:
				var closest_dist = _distance_to_trail(other_trail, tree_pos)
				if closest_dist < trail_width * 0.5 + 0.3:
					too_close_to_any_trail = true
					break
			if too_close_to_any_trail:
				continue
			
			# Skip if too close to the cabin (circular exclusion zone)
			var dist_to_cabin = Vector2(tree_pos.x - cabin_position.x, tree_pos.z - cabin_position.z).length()
			if dist_to_cabin < 12.0:
				continue
			
			if tree_pos.distance_to(spawn_point) < clear_radius:
				continue
			
			var too_close_to_other = false
			for placed in placed_positions:
				if tree_pos.distance_to(placed) < 1.5:
					too_close_to_other = true
					break
			if too_close_to_other:
				continue
			
			var ground_pos = tree_pos
			if space_state:
				ground_pos = _snap_to_ground(space_state, tree_pos)
			
			# CABIN COLLIDER FAILSAFE — skip if raycast hit the cabin/house itself
			if space_state:
				var ray_from = Vector3(tree_pos.x, 30.0, tree_pos.z)
				var ray_to = Vector3(tree_pos.x, -20.0, tree_pos.z)
				var q = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
				q.collide_with_areas = false
				q.collide_with_bodies = true
				var r = space_state.intersect_ray(q)
				if not r.is_empty() and (r.collider.name.containsn("cabin") or r.collider.name.containsn("house")):
					continue
			
			var tree_resource = tree_scenes.pick_random()
			if not tree_resource:
				continue
			
			var tree = tree_resource.instantiate()
			add_child(tree)
			_center_node_hierarchy(tree)
			tree.global_position = ground_pos
			tree.rotation.y = randf_range(0, TAU)
			
			_ensure_collider(tree)
			placed_positions.append(ground_pos)
	
	print("[TrailSpawner] Placed %d trees in dense forest layout" % placed_positions.size())


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
	if dist_to_cabin < 12.0:
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
	## Second pass: fills the forest floor with standalone foliage
	## (ferns, grass, mushrooms, stones) on a finer grid between trees.
	## This creates a dense, natural-looking undergrowth layer.
	if foliage_scenes.is_empty():
		return
	
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return
	
	var foliage_spawned: int = 0
	var foliage_grid_step = 2.0  # Finer grid than trees
	
	# Use the trail corridor bounds to define the foliage area
	var min_z = INF
	var max_z = -INF
	var min_x = INF
	var max_x = -INF
	for trail in trails:
		for pt in trail:
			if pt.x < min_x: min_x = pt.x
			if pt.x > max_x: max_x = pt.x
			if pt.z < min_z: min_z = pt.z
			if pt.z > max_z: max_z = pt.z
	
	# Expand bounds to cover the forest around trails
	var margin = 15.0
	min_x -= margin
	max_x += margin
	min_z -= margin
	max_z += margin
	
	for x_pos in range(int(min_x), int(max_x), int(foliage_grid_step)):
		for z_pos in range(int(min_z), int(max_z), int(foliage_grid_step)):
			if foliage_spawned >= max_foliage_count:
				print("TrailSpawner: Reached max_foliage_count (%d). Stopping standalone foliage." % max_foliage_count)
				return
			
			# Density control
			if randf() > standalone_foliage_chance:
				continue
			
			var target_x = x_pos + randf_range(-0.5, 0.5)
			var target_z = z_pos + randf_range(-0.5, 0.5)
			
			# --- CABIN EXCLUSION ---
			var dist_to_cabin = Vector2(target_x - cabin_position.x, target_z - cabin_position.z).length()
			if dist_to_cabin < 12.0:
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
	
	print("TrailSpawner: Spawned %d standalone foliage pieces." % foliage_spawned)


func _distance_to_trail(trail_points: Array, point: Vector3) -> float:
	if trail_points.size() < 2:
		return INF
	
	var min_dist = INF
	for i in range(trail_points.size() - 1):
		var dist = _distance_to_segment(point, trail_points[i], trail_points[i + 1])
		if dist < min_dist:
			min_dist = dist
	
	return min_dist


func _distance_to_segment(point: Vector3, seg_start: Vector3, seg_end: Vector3) -> float:
	var seg = seg_end - seg_start
	var seg_len_sq = seg.length_squared()
	if seg_len_sq < 0.0001:
		return point.distance_to(seg_start)
	
	var t = (point - seg_start).dot(seg) / seg_len_sq
	t = clampf(t, 0.0, 1.0)
	
	var closest = seg_start + seg * t
	return point.distance_to(closest)


func _get_point_on_trail(trail_points: Array, t: float) -> Vector3:
	if trail_points.is_empty():
		return Vector3.ZERO
	
	t = clampf(t, 0.0, 1.0)
	var index_f = t * (trail_points.size() - 1)
	var index = int(index_f)
	var frac = index_f - index
	
	if index >= trail_points.size() - 1:
		return trail_points[-1]
	
	return trail_points[index].lerp(trail_points[index + 1], frac)


func _get_trail_direction(trail_points: Array, t: float) -> Vector3:
	if trail_points.size() < 2:
		return Vector3.FORWARD
	
	t = clampf(t, 0.0, 1.0)
	var index_f = t * (trail_points.size() - 1)
	var index = int(index_f)
	
	if index >= trail_points.size() - 1:
		index = trail_points.size() - 2
	
	var dir = (trail_points[index + 1] - trail_points[index]).normalized()
	if dir.length() < 0.001:
		return Vector3.FORWARD
	return dir


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
		print("TrailSpawner: Auto-loaded %d PizzaDoggy tree scenes." % tree_scenes.size())
	
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
		print("TrailSpawner: Auto-loaded %d PizzaDoggy foliage scenes." % foliage_scenes.size())


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


func _snap_to_ground(space_state: PhysicsDirectSpaceState3D, pos: Vector3) -> Vector3:
	if not space_state:
		return pos
	
	var from = Vector3(pos.x, pos.y + 20.0, pos.z)
	var to = Vector3(pos.x, pos.y - 20.0, pos.z)
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	
	var result = space_state.intersect_ray(query)
	if result:
		return result.position + Vector3(0, 0.05, 0)
	return pos


func _ensure_collider(tree_node: Node3D) -> void:
	var existing = null
	for child in tree_node.get_children():
		if child is StaticBody3D:
			existing = child
			break
	
	if existing:
		return
	
	var static_body = StaticBody3D.new()
	var collision_shape = CollisionShape3D.new()
	var cylinder = CylinderShape3D.new()
	
	cylinder.height = 10.0
	cylinder.radius = 0.5
	
	collision_shape.shape = cylinder
	static_body.add_child(collision_shape)
	tree_node.add_child(static_body)
	collision_shape.position.y = 5.0
	
	var nav_obstacle = NavigationObstacle3D.new()
	nav_obstacle.radius = 1.5
	nav_obstacle.height = 8.0
	nav_obstacle.avoidance_enabled = true
	tree_node.add_child(nav_obstacle)
	nav_obstacle.position.y = 4.0
