extends Node
class_name EntityNavigation

## Entity Navigation System — Vantage point selection, outside detection,
## pathfinding helpers, and the Spatial Light Mapping grid.
##
## The light cost grid is a 2D heatmap of light intensity across the yard.
## The Entity uses it to path around lit areas, choosing longer routes
## through dense trees just to stay in pitch-black shadows.
##
## Grid resolution: 2-meter cells covering a 60m × 60m bounding box
## centered on the cabin. Total: ~900 cells. Rebuild cost: ~2ms every 2s.

var entity: CharacterBody3D = null

# ─── LIGHT COST GRID ─────────────────────────────────────────────────────────
## Dictionary mapping cell_key (Vector3i) to light cost (0.0 = dark, 1.0 = fully lit).
var _light_cost_grid: Dictionary = {}

## Grid cell size in meters.
const GRID_CELL_SIZE: float = 2.0

## Half-extent of the grid in cells (30m / 2m = 15 cells in each direction).
const GRID_HALF_EXTENT: int = 15

## Cache of light source data for the current frame.
## Each entry: { position: Vector3, radius: float, intensity: float }
var _light_sources: Array[Dictionary] = []

## Whether the grid needs rebuilding this frame.
var _grid_dirty: bool = true

## Timer for periodic grid rebuilds.
var _rebuild_timer: float = 0.0

## Rebuild interval in seconds.
const REBUILD_INTERVAL: float = 2.0

## The bounding box center (the cabin center, updated from entity.cabin_center).
var _grid_center: Vector3 = Vector3(0.0, 0.0, 14.88)

# ─── DEBUG VISUALIZATION ─────────────────────────────────────────────────────
## Whether to draw the light cost grid as debug spheres in the editor.
var _debug_draw_grid: bool = false

## Timer for debug draw updates.
var _debug_draw_timer: float = 0.0

const DEBUG_DRAW_INTERVAL: float = 1.0


func setup(parent: CharacterBody3D) -> void:
	entity = parent
	_grid_center = entity.cabin_center if "cabin_center" in entity else Vector3(0.0, 0.0, 14.88)


func _process(delta: float) -> void:
	if not entity or not is_instance_valid(entity):
		return
	
	# Periodic grid rebuild
	_rebuild_timer += delta
	if _rebuild_timer >= REBUILD_INTERVAL or _grid_dirty:
		_rebuild_timer = 0.0
		_scan_light_sources()
		_rebuild_light_cost_grid()
		_grid_dirty = false
		
		if OS.is_debug_build():
			print("[Light Grid] Rebuilt. Sources: %d | Cells: %d" % [_light_sources.size(), _light_cost_grid.size()])


# ─── LIGHT SOURCE SCANNING ───────────────────────────────────────────────────

## Scans the scene tree for all active light sources and caches their data.
## Called every REBUILD_INTERVAL seconds or when _grid_dirty is set to true.
func _scan_light_sources() -> void:
	_light_sources.clear()
	
	# 1. Cabin Lights (interior room lights that leak through windows)
	var cabin_lights: Array[Node] = entity.get_tree().get_nodes_in_group("CabinLights")
	for cl in cabin_lights:
		if "is_switched_on" in cl and cl.is_switched_on:
			var light_pos: Vector3 = cl.global_position if "global_position" in cl else Vector3.ZERO
			var radius: float = cl.light_radius if "light_radius" in cl else 8.0
			var intensity: float = cl.light_intensity if "light_intensity" in cl else 1.0
			_light_sources.append({
				"position": light_pos,
				"radius": radius,
				"intensity": intensity,
				"type": "cabin_light"
			})
	
	# 2. Porch Lights (exterior floodlights)
	var porch_lights: Array[Node] = entity.get_tree().get_nodes_in_group("PorchLights")
	for pl in porch_lights:
		if "is_switched_on" in pl and pl.is_switched_on:
			var light_pos: Vector3 = pl.global_position if "global_position" in pl else Vector3.ZERO
			var radius: float = pl.light_radius if "light_radius" in pl else 12.0
			var intensity: float = pl.light_intensity if "light_intensity" in pl else 1.5
			_light_sources.append({
				"position": light_pos,
				"radius": radius,
				"intensity": intensity,
				"type": "porch_light"
			})
	
	# 3. Portable Lamps (player-deployed high-voltage lamps)
	var portable_lamps: Array[Node] = entity.get_tree().get_nodes_in_group("PortableLamps")
	for lamp in portable_lamps:
		if "is_on" in lamp and lamp.is_on:
			var light_pos: Vector3 = lamp.global_position if "global_position" in lamp else Vector3.ZERO
			var radius: float = lamp.light_radius if "light_radius" in lamp else 10.0
			var intensity: float = lamp.light_intensity if "light_intensity" in lamp else 1.2
			_light_sources.append({
				"position": light_pos,
				"radius": radius,
				"intensity": intensity,
				"type": "portable_lamp"
			})
	
	# 4. Flashlight Beam (if player is outside, the flashlight projects light)
	if entity._player:
		var flashlight_on: bool = false
		if entity._player.has_method("is_flashlight_on"):
			flashlight_on = entity._player.is_flashlight_on()
		
		if flashlight_on:
			var player_pos: Vector3 = entity._player.global_position
			var cam = entity.get_viewport().get_camera_3d()
			if cam:
				var cam_forward: Vector3 = -cam.global_transform.basis.z
				# Project the flashlight beam 8 meters forward from the player
				var beam_end: Vector3 = player_pos + cam_forward * 8.0
				_light_sources.append({
					"position": beam_end,
					"radius": 4.0,
					"intensity": 0.8,
					"type": "flashlight"
				})
	
	# 5. Generator Exhaust Flame (small light near the generator when running)
	var nm: Node = entity.get_node_or_null("/root/NightManager")
	if nm and "is_generator_on" in nm and nm.is_generator_on:
		var gen: Node = entity.get_tree().get_first_node_in_group("Generator")
		if gen:
			var gen_pos: Vector3 = gen.global_position if "global_position" in gen else Vector3.ZERO
			_light_sources.append({
				"position": gen_pos + Vector3(0.0, 0.5, 0.0),
				"radius": 3.0,
				"intensity": 0.3,
				"type": "generator_exhaust"
			})


# ─── GRID REBUILDING ─────────────────────────────────────────────────────────

## Rebuilds the entire light cost grid by sampling each cell against all
## active light sources. Runs every REBUILD_INTERVAL seconds.
func _rebuild_light_cost_grid() -> void:
	_light_cost_grid.clear()
	
	var center_x: float = _grid_center.x
	var center_z: float = _grid_center.z
	
	# Iterate over all cells in the bounding box
	for cell_x in range(-GRID_HALF_EXTENT, GRID_HALF_EXTENT + 1):
		for cell_z in range(-GRID_HALF_EXTENT, GRID_HALF_EXTENT + 1):
			var world_x: float = center_x + cell_x * GRID_CELL_SIZE
			var world_z: float = center_z + cell_z * GRID_CELL_SIZE
			var cell_pos: Vector3 = Vector3(world_x, 0.0, world_z)
			
			# Calculate total light cost at this cell
			var total_cost: float = 0.0
			for source in _light_sources:
				var src_pos: Vector3 = source["position"] as Vector3
				var radius: float = source["radius"] as float
				var intensity: float = source["intensity"] as float
				
				var dist: float = cell_pos.distance_to(src_pos)
				if dist < radius:
					# Linear falloff: cost = intensity * (1 - dist/radius)
					var contribution: float = intensity * (1.0 - dist / radius)
					total_cost += contribution
			
			# Clamp to 0.0–1.0
			total_cost = clampf(total_cost, 0.0, 1.0)
			
			# Store in grid
			var cell_key: Vector3i = Vector3i(cell_x, 0, cell_z)
			_light_cost_grid[cell_key] = total_cost


# ─── PUBLIC QUERY API ────────────────────────────────────────────────────────

## Returns the light cost at a given world position.
## Samples the nearest grid cell. Returns 0.0 if the position is outside
## the grid bounding box (assumed to be in deep forest = pitch black).
func get_light_cost_at(position: Vector3) -> float:
	var local_x: float = position.x - _grid_center.x
	var local_z: float = position.z - _grid_center.z
	var cell_x: int = int(round(local_x / GRID_CELL_SIZE))
	var cell_z: int = int(round(local_z / GRID_CELL_SIZE))
	
	# Clamp to grid bounds
	cell_x = clampi(cell_x, -GRID_HALF_EXTENT, GRID_HALF_EXTENT)
	cell_z = clampi(cell_z, -GRID_HALF_EXTENT, GRID_HALF_EXTENT)
	
	var cell_key: Vector3i = Vector3i(cell_x, 0, cell_z)
	return _light_cost_grid.get(cell_key, 0.0)


## Returns the average light cost along a path from `from` to `to`.
## Samples 5 evenly-spaced points along the path and averages their costs.
## Used by entity_ai.gd's window shopping utility scorer to penalize
## windows that require crossing lit areas.
func get_path_cost(from: Vector3, to: Vector3) -> float:
	var total_cost: float = 0.0
	var samples: int = 5
	
	for i in range(samples):
		var t: float = float(i) / float(samples - 1)
		var sample_pos: Vector3 = from.lerp(to, t)
		total_cost += get_light_cost_at(sample_pos)
	
	return total_cost / float(samples)


## Returns true if the given position is in darkness (light cost < 0.1).
## Used by the Phantom Evasion system to find safe retreat positions.
func is_position_in_dark(pos: Vector3) -> bool:
	return get_light_cost_at(pos) < 0.1


## Finds the nearest grid cell with light cost < 0.1 (pitch black).
## Searches outward in a spiral pattern from the given position.
## Returns the world position of the nearest dark cell.
## If no dark cell is found within the search radius, returns the
## farthest cell from all light sources (least-lit position).
func get_nearest_dark_position(from: Vector3) -> Vector3:
	var local_x: float = from.x - _grid_center.x
	var local_z: float = from.z - _grid_center.z
	var start_cell_x: int = int(round(local_x / GRID_CELL_SIZE))
	var start_cell_z: int = int(round(local_z / GRID_CELL_SIZE))
	
	# Spiral search outward up to 10 cells (20 meters)
	var max_search_radius: int = 10
	var best_cell: Vector3i = Vector3i(start_cell_x, 0, start_cell_z)
	var best_cost: float = 1.0  # Start with max cost, look for lower
	
	for radius in range(1, max_search_radius + 1):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				# Only check cells on the perimeter of the current radius
				if abs(dx) != radius and abs(dz) != radius:
					continue
				
				var cell_key: Vector3i = Vector3i(start_cell_x + dx, 0, start_cell_z + dz)
				var cost: float = _light_cost_grid.get(cell_key, 0.0)
				
				if cost < best_cost:
					best_cost = cost
					best_cell = cell_key
					
					# Early exit: found a dark cell
					if cost < 0.1:
						var world_x: float = _grid_center.x + best_cell.x * GRID_CELL_SIZE
						var world_z: float = _grid_center.z + best_cell.z * GRID_CELL_SIZE
						return Vector3(world_x, from.y, world_z)
	
	# No dark cell found — return the least-lit position found
	var world_x_fallback: float = _grid_center.x + best_cell.x * GRID_CELL_SIZE
	var world_z_fallback: float = _grid_center.z + best_cell.z * GRID_CELL_SIZE
	return Vector3(world_x_fallback, from.y, world_z_fallback)


## Marks the grid as dirty, forcing a rebuild on the next _process() tick.
## Called by external systems (e.g., CabinLight when toggled on/off).
func mark_grid_dirty() -> void:
	_grid_dirty = true


# ─── LEGACY METHODS (Preserved from original entity_navigation.gd) ──────────

## Returns true if the player is outside the cabin.
## Uses the player's floor raycast to check if they're standing on wood (inside)
## or grass/dirt (outside). Falls back to distance check if raycast is unavailable.
func is_player_outside() -> bool:
	if not entity._player:
		return false
	
	# Try to use the player's floor raycast to detect surface type
	var floor_raycast = entity._player.get_node_or_null("FloorRayCast")
	if floor_raycast and floor_raycast is RayCast3D and floor_raycast.is_colliding():
		var surface_node: Node = floor_raycast.get_collider()
		while surface_node:
			if surface_node.is_in_group("wood"):
				return false  # Standing on wood = inside the cabin
			if surface_node.is_in_group("grass"):
				return true   # Standing on grass = outside
			surface_node = surface_node.get_parent()
	
	# Fallback: distance check from cabin center
	return entity._player.global_position.distance_to(entity.cabin_center) > 10.0


## Returns true if the player is on the second floor of the cabin.
## Uses a Y-axis threshold (3.0 meters above ground level).
## Ground floor Y ≈ 0.0, second floor Y ≈ 3.0+
func is_player_on_second_floor() -> bool:
	if not entity._player:
		return false
	return entity._player.global_position.y > 3.0


## Finds the nearest exterior wall base position below a second-story window.
## Scans WindowMarkers, finds ones with Y > 3.0 (second story), projects their
## position down to ground level (Y = 0.0), and returns the closest one to the Entity.
## Used by CLIMB_WALL state to determine where to begin the vertical ascent.
func find_nearest_second_story_window_base() -> Vector3:
	var windows = entity.get_tree().get_nodes_in_group("WindowMarkers")
	var best_pos = Vector3.ZERO
	var shortest = INF
	for w in windows:
		if w.global_position.y < 3.0:
			continue  # Skip ground-floor windows
		# Project the window position down to ground level
		var base_pos = Vector3(w.global_position.x, 0.0, w.global_position.z)
		var d = entity.global_position.distance_to(base_pos)
		if d < shortest:
			shortest = d
			best_pos = base_pos
	return best_pos


## Picks a new vantage point from the Treeline_Vantage_Points group,
## blacklisting the last visited one to avoid getting stuck.
func pick_next_vantage_point() -> void:
	var treeline_markers = entity.get_tree().get_nodes_in_group("Treeline_Vantage_Points")
	var candidates = treeline_markers.filter(func(m): return m != entity._last_vantage_point)
	if candidates.is_empty():
		candidates = treeline_markers
	
	var best_marker = candidates.pick_random()
	entity._last_vantage_point = best_marker
	entity._nav_agent.target_position = best_marker.global_position
	entity._is_at_vantage_point = false
	print("[Entity AI] Moving to new vantage point: ", best_marker.name)
