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

# ─── BREACH COOLDOWN SYSTEM ────────────────────────────────────────────────────
## Dictionary mapping WindowID (String) to a cooldown timer (float) in seconds.
## When a window is breached, its cooldown is set to 60.0 seconds. During this
## time, the Entity will NOT select this window for approach/breach.
## Decremented by delta each frame in process_navigation().
var _breach_cooldowns: Dictionary = {}

## Duration (in seconds) a window remains on cooldown after being breached.
const BREACH_COOLDOWN_DURATION: float = 60.0

## ─── ALREADY BREACHED PENALTY ────────────────────────────────────────────────
## Utility score penalty applied to windows whose glass is already shattered.
## This makes the Entity prefer to breach *other* windows first, creating more
## varied and unpredictable approach patterns instead of re-breaching the same
## window repeatedly.
const ALREADY_BREACHED_PENALTY: float = 500.0

# ─── CACHED SCENE TREE GROUPS ───────────────────────────────────────────────
## Cached references to scene tree groups populated once in _ready().
## Avoids expensive get_tree().get_nodes_in_group() calls in the AI/physics loop.
var _window_markers: Array[Node3D] = []
var _treeline_markers: Array[Node3D] = []

## Pre-cached array of actual CabinWindow nodes on the ground floor.
## Populated once in _cache_scene_groups() by iterating _window_markers.
## Eliminates repeated get_parent() and is_in_group() calls inside hot loops.
var _cabin_windows: Array[CabinWindow] = []


func setup(parent: CharacterBody3D) -> void:
	entity = parent
	_grid_center = entity.cabin_center if "cabin_center" in entity else Vector3(0.0, 0.0, 14.88)
	
	# Cache scene tree groups once to avoid tree traversal during runtime
	_cache_scene_groups()


## Populates cached group arrays. Called once from setup().
func _cache_scene_groups() -> void:
	var windows = entity.get_tree().get_nodes_in_group("WindowMarkers")
	for w in windows:
		if w is Node3D:
			_window_markers.append(w as Node3D)
	
	var treeline = entity.get_tree().get_nodes_in_group("Treeline_Vantage_Points")
	for t in treeline:
		if t is Node3D:
			_treeline_markers.append(t as Node3D)
	
	# ─── AUTO-POPULATE FALLBACK: VantagePoints Container ──────────────
	# If no treeline markers were found via the group, try to find a
	# "VantagePoints" node in the scene root and use its children as markers.
	# This prevents the Entity from freezing due to an empty _treeline_markers
	# array when the scene tree hasn't been properly tagged with groups.
	if _treeline_markers.is_empty():
		var root = entity.get_tree().current_scene
		if root:
			var container = root.get_node_or_null("VantagePoints")
			if container:
				for child in container.get_children():
					if child is Node3D:
						_treeline_markers.append(child as Node3D)
				print("[Navigation] Auto-populated %d markers from VantagePoints container." % _treeline_markers.size())
			else:
				push_warning("VantagePoints container not found in scene root! Entity may freeze without navigation markers.")
	
	print("[Entity Navigation] Cached %d window markers and %d treeline markers." % [_window_markers.size(), _treeline_markers.size()])
	
	# ─── PRE-CACHE CABIN WINDOWS ────────────────────────────────────────
	# Populate _cabin_windows by iterating _window_markers once.
	# This eliminates repeated get_parent() and is_in_group() calls inside
	# hot loops like find_nearest_broken_window() and are_all_windows_lit().
	for w in _window_markers:
		var parent = w.get_parent()
		if parent is CabinWindow and parent.is_in_group("BottomFloorWindows"):
			# ─── TASK 8: Exclude porch windows from bottom-floor lit check ──
			# The porch light is always on and never turns off. If a porch
			# window is counted in the "all windows lit" calculation, it
			# creates a false positive — the frustration system sees all
			# windows as lit and triggers FUSE_SABOTAGE prematurely.
			# Filter out any window whose name or parent name contains "porch".
			var window_name = parent.name.to_lower()
			if window_name.contains("porch"):
				print("[Navigation] Skipping porch window: %s" % parent.name)
				continue
			_cabin_windows.append(parent as CabinWindow)
	
	print("[Navigation] Pre-cached %d CabinWindow nodes (excluding porch)." % _cabin_windows.size())
	
	# ─── DOOR MARKER VERIFICATION ──────────────────────────────────────
	# Verify that the door has a Marker3D in the "DoorBreachWaypoint" group.
	# If not, log a warning so the developer knows to add it in the scene.
	var door_marker_found = false
	var door_breach_wps = entity.get_tree().get_nodes_in_group("DoorBreachWaypoint")
	for wp in door_breach_wps:
		if wp.get_parent() and wp.get_parent().is_in_group("Door"):
			door_marker_found = true
			break
	if not door_marker_found:
		# Try to find the door marker directly
		var door = entity.get_tree().get_first_node_in_group("Door")
		if door:
			var markers = entity.get_tree().get_nodes_in_group("DoorBreachWaypoint")
			var found = false
			for m in markers:
				if m.get_parent() == door:
					found = true
					break
			if found:
				print("[Navigation] WARNING: Door's DoorBreachWaypoint found but NOT in WindowMarkers group! Add it to the WindowMarkers group in the scene editor.")
			else:
				print("[Navigation] WARNING: Door node found but missing DoorBreachWaypoint child Marker3D! Add a Marker3D in the 'DoorBreachWaypoint' group as a child of the Door node.")
		else:
			print("[Navigation] No Door node found in 'Door' group. Door approach will be unavailable.")


## Returns the cached array of window markers (Marker3D nodes in the
## "WindowMarkers" group). Used by entity_controller.gd's proximity grace
## period to check if the Entity is near a door or window without performing
## expensive get_tree().get_nodes_in_group() calls in the physics loop.
func get_window_markers() -> Array[Node3D]:
	return _window_markers


func _process(delta: float) -> void:
	if not entity or not is_instance_valid(entity):
		return
	
	# ─── BREACH COOLDOWN DECAY ──────────────────────────────────────────
	# Decrement all breach cooldown timers by delta each frame.
	# When a cooldown reaches 0.0 or below, the window is removed from the
	# dictionary so it becomes available for selection again.
	_process_breach_cooldowns(delta)
	
	# Periodic grid rebuild
	_rebuild_timer += delta
	if _rebuild_timer >= REBUILD_INTERVAL or _grid_dirty:
		_rebuild_timer = 0.0
		_scan_light_sources()
		_rebuild_light_cost_grid()
		_grid_dirty = false


## Decrements all breach cooldown timers by delta. Removes entries whose
## cooldown has expired (<= 0.0) so the window becomes available again.
func _process_breach_cooldowns(delta: float) -> void:
	if _breach_cooldowns.is_empty():
		return
	
	var expired: Array[String] = []
	for window_id in _breach_cooldowns.keys():
		var remaining: float = _breach_cooldowns[window_id] - delta
		if remaining <= 0.0:
			expired.append(window_id)
		else:
			_breach_cooldowns[window_id] = remaining
	
	for window_id in expired:
		_breach_cooldowns.erase(window_id)
		print("[Navigation] Breach cooldown expired for window '%s'. Available for approach again." % window_id)


## Marks a window as breached, setting its cooldown timer to 60.0 seconds.
## During this time, the Entity will NOT select this window for approach/breach.
## Called by entity_ai.gd when the glass shatters (shatter_window() is called).
##
## Parameters:
##   window_id: The unique identifier string for the window (e.g., "Window_01").
func mark_window_breached(window_id: String) -> void:
	_breach_cooldowns[window_id] = BREACH_COOLDOWN_DURATION
	print("[Navigation] Window '%s' marked as breached. Cooldown set to %.1f seconds." % [window_id, BREACH_COOLDOWN_DURATION])


# ─── LIGHT SOURCE SCANNING ───────────────────────────────────────────────────

## Scans the scene tree for all active light sources and caches their data.
## Called every REBUILD_INTERVAL seconds or when _grid_dirty is set to true.
func _scan_light_sources() -> void:
	_light_sources.clear()
	
	# 1. Cabin Lights (interior room lights that leak through windows)
	var cabin_lights: Array[Node] = entity.get_cabin_lights()
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
	var player = entity.get_player()
	if player:
		var flashlight_on: bool = false
		if player.has_method("is_flashlight_on"):
			flashlight_on = player.is_flashlight_on()
		
		if flashlight_on:
			var player_pos: Vector3 = player.global_position
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
	var nm: Node = _get_night_manager_nav()
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
	var center_x: float = _grid_center.x
	var center_z: float = _grid_center.z
	
	# PERFORMANCE: Short-circuit — if no light sources changed, skip the rebuild.
	# The only time lights change is during power-out or switch toggles, which
	# already set _grid_dirty = true.
	if _light_sources.is_empty() and _light_cost_grid.size() > 0:
		return  # No lights = all cells stay dark. Don't waste CPU.
	
	# PERFORMANCE: Incremental rebuild — only recompute cells that are within
	# range of active light sources. Cells farther than the max light radius
	# from ALL sources stay at their default (0.0 = dark) and don't need computing.
	var max_light_radius: float = 0.0
	for source in _light_sources:
		var r: float = source["radius"] as float
		if r > max_light_radius:
			max_light_radius = r
	
	# Build a set of cell_keys that need recomputing.
	# For each light source, only mark cells within its radius.
	var dirty_cells: Array[Vector3i] = []
	var seen: Dictionary = {}  # deduplication set
	
	for source in _light_sources:
		var src_pos: Vector3 = source["position"] as Vector3
		var radius: float = source["radius"] as float
		var cell_radius: int = ceili(radius / GRID_CELL_SIZE)
		var src_cell_x: int = int(round((src_pos.x - center_x) / GRID_CELL_SIZE))
		var src_cell_z: int = int(round((src_pos.z - center_z) / GRID_CELL_SIZE))
		
		for dx in range(-cell_radius, cell_radius + 1):
			for dz in range(-cell_radius, cell_radius + 1):
				var cx: int = src_cell_x + dx
				var cz: int = src_cell_z + dz
				# Clamp to grid bounds
				if cx < -GRID_HALF_EXTENT or cx > GRID_HALF_EXTENT: continue
				if cz < -GRID_HALF_EXTENT or cz > GRID_HALF_EXTENT: continue
				var key := Vector3i(cx, 0, cz)
				if not seen.has(key):
					seen[key] = true
					dirty_cells.append(key)
	
	# If the number of dirty cells is close to the full grid, fall through to the
	# full rebuild (the clear() + full iteration is faster than indirection overhead).
	var total_cells: int = (2 * GRID_HALF_EXTENT + 1) * (2 * GRID_HALF_EXTENT + 1)
	
	if dirty_cells.size() > total_cells * 0.75:
		# Full rebuild — clear everything and recompute all cells.
		_light_cost_grid.clear()
		for cell_x in range(-GRID_HALF_EXTENT, GRID_HALF_EXTENT + 1):
			for cell_z in range(-GRID_HALF_EXTENT, GRID_HALF_EXTENT + 1):
				var world_x: float = center_x + cell_x * GRID_CELL_SIZE
				var world_z: float = center_z + cell_z * GRID_CELL_SIZE
				var cell_pos: Vector3 = Vector3(world_x, 0.0, world_z)
				
				var total_cost: float = 0.0
				for source in _light_sources:
					var src_pos: Vector3 = source["position"] as Vector3
					var src_radius: float = source["radius"] as float
					var intensity: float = source["intensity"] as float
					
					var dist: float = cell_pos.distance_to(src_pos)
					if dist < src_radius:
						var contribution: float = intensity * (1.0 - dist / src_radius)
						total_cost += contribution
				
				total_cost = clampf(total_cost, 0.0, 1.0)
				var cell_key: Vector3i = Vector3i(cell_x, 0, cell_z)
				_light_cost_grid[cell_key] = total_cost
	else:
		# Incremental rebuild — only recompute the dirty cells.
		# Cells outside the dirty set keep their previous values.
		for cell_idx in dirty_cells:
			var cell_x: int = cell_idx.x
			var cell_z: int = cell_idx.z
			var world_x: float = center_x + cell_x * GRID_CELL_SIZE
			var world_z: float = center_z + cell_z * GRID_CELL_SIZE
			var cell_pos: Vector3 = Vector3(world_x, 0.0, world_z)
			
			var total_cost: float = 0.0
			for source in _light_sources:
				var src_pos: Vector3 = source["position"] as Vector3
				var src_radius: float = source["radius"] as float
				var intensity: float = source["intensity"] as float
				
				var dist: float = cell_pos.distance_to(src_pos)
				if dist < src_radius:
					var contribution: float = intensity * (1.0 - dist / src_radius)
					total_cost += contribution
			
			total_cost = clampf(total_cost, 0.0, 1.0)
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

## Timer for periodic inside/outside debug logging (every 2 seconds).
var _inside_outside_debug_timer: float = 0.0

## Returns true if the player is inside any registered cabin room.
## Uses get_player_room() which delegates to player_controller.gd's reliable
## overlaps_body() detection against Cabin_Interior Area3D volumes.
##
## If the player's room name is anything other than "Outside", they are
## considered to be inside the cabin. This is more reliable than the old
## distance-fallback + get_overlapping_bodies() approach, which could fail
## when the player was in transitional spaces, hallways, or on the second
## floor where Area3D volumes might not perfectly cover all interior spaces.
func is_player_inside() -> bool:
	var player = entity.get_player()
	if not player:
		return false
	
	# Delegate to player_controller.gd's get_player_room() which uses
	# area.overlaps_body(self) — a more reliable overlap check.
	# If the room name is anything other than "Outside", the player is inside.
	var result = get_player_room() != "Outside"
	
	# ─── PERIODIC DEBUG LOG (every 2 seconds, DEBUG BUILDS ONLY) ────────
	# Logs whether the player is considered inside or outside by both the
	# player's own room detection AND the Entity's navigation module.
	# Debug-only to eliminate console spam in release builds.
	if OS.is_debug_build():
		_inside_outside_debug_timer += 0.016  # Approximate delta for _process
		if _inside_outside_debug_timer >= 2.0:
			_inside_outside_debug_timer = 0.0
			var player_room = get_player_room()
			var entity_inside = result
			print("[INSIDE/OUTSIDE DEBUG] Player room='%s' | Entity thinks player is inside=%s" % [player_room, entity_inside])
	
	return result


## Returns true if the player is outside the cabin.
## Simply inverts is_player_inside() for API compatibility.
func is_player_outside() -> bool:
	return not is_player_inside()


## Returns the name of the room the player is currently in, or "Outside" if
## the player is not inside any registered cabin interior area.
## Delegates to player_controller.gd's get_player_room() method.
func get_player_room() -> String:
	var player = entity.get_player()
	if not player:
		return "Outside"
	if player.has_method("get_player_room"):
		return player.get_player_room()
	return "Outside"


## ─── LIGHT DETECTION CONVENIENCE METHODS ─────────────────────────────────────
## These methods delegate to the RoomLightDetector autoload singleton.
## They provide a clean API for the Entity AI to query lighting state
## without needing to reference the autoload directly.

## Returns true if the player is currently in a lit room.
## A room is "lit" when BOTH the light switch is ON AND the generator is running.
func is_player_in_lit_room() -> bool:
	var detector = _get_light_detector()
	if detector:
		return detector.is_player_in_lit_room()
	return false


## Returns true if the Entity is currently in a lit room.
## The Entity is only inside a lit room if it has breached the cabin
## (INDOOR_SEARCH state) and the room it's in has an active light.
func is_entity_in_lit_room() -> bool:
	var detector = _get_light_detector()
	if detector:
		return detector.is_entity_in_lit_room()
	return false


## Returns true if the given world position is inside a lit room.
func is_position_in_lit_room(position: Vector3) -> bool:
	var detector = _get_light_detector()
	if detector:
		return detector.is_position_in_lit_room(position)
	return false


## Returns the name of the room at the given position, or "Outside".
func get_room_name_at(position: Vector3) -> String:
	var detector = _get_light_detector()
	if detector:
		return detector.get_room_name_at(position)
	return "Outside"


## Internal helper to get the RoomLightDetector autoload.
var _light_detector: Node = null
var _night_manager_nav: Node = null

func _get_light_detector() -> Node:
	if not _light_detector or not is_instance_valid(_light_detector):
		_light_detector = entity.get_node_or_null("/root/RoomLightDetector")
	return _light_detector


## Returns cached NightManager reference.
func _get_night_manager_nav() -> Node:
	if not _night_manager_nav or not is_instance_valid(_night_manager_nav):
		_night_manager_nav = entity.get_node_or_null("/root/NightManager")
	return _night_manager_nav



## Returns true if ALL ground-floor windows are secured by light sanctuary.
## This means every window's room light is switched on AND the generator is
## running, making every window "secure" via light. The Entity cannot approach
## any window and must wait in OBSERVE_FROM_TREELINE until a light turns off.
##
## Used by the ALL_WINDOWS_LIT loop guard in entity_ai.gd to prevent the
## Entity from continuously cycling frames when there are no valid windows.
func are_all_windows_lit() -> bool:
	if _cabin_windows.is_empty():
		return false
	
	for cabin_window in _cabin_windows:
		# Check if this window is NOT secure due to light
		# A window is "secure by light" when room_light.is_room_lit() returns true
		var is_secure_by_light: bool = false
		if cabin_window.room_light:
			if cabin_window.room_light.has_method("is_room_lit") and cabin_window.room_light.is_room_lit():
				is_secure_by_light = true
		
		if not is_secure_by_light:
			# Found a window that is NOT lit — not all windows are lit
			return false
	
	# All ground-floor windows are lit
	return true


## Returns true if the player is currently lit by a cabin light or porch light.
## Checks the player's position against all cached static light sources
## (cabin_light and porch_light types only — NOT flashlight or portable lamps).
## If the player is within any static light's radius, they are considered "lit up"
## and the Entity should stop STALKING and return to default behavior.
##
## This is used by entity_director.gd's Tier 3 STALK handling to force the Entity
## to exit STALK when the player steps into a lit area (cabin interior light
## leaking through windows, or the exterior porch floodlight).
func is_player_lit_by_static_lights() -> bool:
	var player = entity.get_player()
	if not player:
		return false
	
	var player_pos: Vector3 = player.global_position
	
	for source in _light_sources:
		var src_type: String = source.get("type", "")
		# Only check static environmental lights (cabin lights and porch lights)
		if src_type != "cabin_light" and src_type != "porch_light":
			continue
		
		var src_pos: Vector3 = source["position"] as Vector3
		var radius: float = source["radius"] as float
		
		var dist: float = player_pos.distance_to(src_pos)
		if dist < radius:
			return true
	
	return false


## Picks a tactical window using room-grouped selection.
## The Entity selects windows by room, not by individual markers.
##
## SELECTION LOGIC (Room-Based):
##   1. Group all bottom-floor windows by room name. Include the front door
##      as a separate "Outside" entry.
##   2. REMOVE rooms where the cabin light is ON (lit rooms = unsafe).
##   3. If ALL rooms are lit, return null (triggers frustration → SABOTAGE_FUSE).
##   4. REMOVE the room where the player was last heard acoustically.
##   5. Flatten ALL remaining rooms into one candidate pool. Banned windows
##      are NOT erased — every window stays a potential option.
##   6. Filter to VIABLE windows: skip breach-cooldown, flinch-blacklisted
##      (string ID), and node-level flinch-banned instances. Banned windows
##      are skipped ONLY while the ban is active, so the NEXT-most-attractive
##      viable window (e.g., the boarded window in the same room) is chosen.
##   7. Among viable windows, prefer unboarded. If all boarded, pick the one
##      with the least barricade health remaining (closest to break). Random
##      among ties.
##   8. If NO window is viable (all lit / all banned / all on cooldown),
##      return null → the Director routes to SABOTAGE_FUSE.
##
## Parameters:
##   player: The player Node3D (unused in the new logic but kept for API compatibility).
##
## Returns: A Node3D (the CabinWindow parent), or null if no windows are available.
func pick_tactical_window(player: Node3D) -> Node3D:
	if not player or _window_markers.is_empty():
		return null
	
	# ─── GET ACOUSTIC INTELLIGENCE ──────────────────────────────────────
	var sensory = entity.get_sensory_module()
	var last_heard_room: String = ""
	if sensory and "last_heard_room" in sensory:
		last_heard_room = sensory.last_heard_room
	
	# ─── STEP 1: GROUP WINDOWS BY ROOM ─────────────────────────────────
	# Iterate all bottom-floor window markers and build a room-name → list mapping.
	# Each entry stores the CabinWindow reference for accessing is_boarded, planks_remaining, etc.
	var rooms: Dictionary = {}  # room_name → Array[{cabin_window, marker, window_id}]
	
	for w in _window_markers:
		# Only ground-floor windows
		if not w.get_parent().is_in_group("BottomFloorWindows"):
			continue
		
		var cabin_window = w.get_parent() as CabinWindow
		if not cabin_window:
			continue
		
		# Resolve the room name via RoomLightDetector using the CabinWindow's
		# position (the window frame), NOT the WindowMarker's exterior position.
		# The marker is placed outside the cabin wall and does NOT overlap the
		# Cabin_Interior Area3D — get_room_name_at() returns "Outside" for all
		# markers, causing EVERY window to be dropped from the room group.
		var window_room: String = RoomLightDetector.get_room_name_at(cabin_window.global_position)
		if window_room == "" or window_room == "Outside":
			# Fallback: if the room name resolved to "Outside" even for the
			# CabinWindow position, the Interior Area3D volumes may not cover
			# this area. Log a diagnostic but do NOT skip the window — let it
			# be placed in a default "Unknown" room so the Entity can still
			# approach it.
			window_room = "Unknown_%s" % cabin_window.name
		
		var window_id: String = ""
		if cabin_window.has_method("get_window_id"):
			window_id = cabin_window.get_window_id()
		# PROPERTY FALLBACK: CabinWindow.window_id is a plain @export var —
		# there is NO get_window_id() method on the script. has_method() returns
		# false, so without this fallback window_id stays "" and the flinch
		# blacklist filter (`blacklisted.has(wid)`) never matches the repelled
		# window (e.g. 'Computer_Left') — the Entity re-selected the exact same
		# window it was just repelled from. Read the property when the method
		# is absent.
		if window_id.is_empty() and "window_id" in cabin_window:
			window_id = str(cabin_window.window_id)
		
		# Determine approach marker (WindowMarker child or the marker itself)
		var approach_marker: Node3D = w
		if cabin_window.has_node("WindowMarker"):
			approach_marker = cabin_window.get_node("WindowMarker") as Node3D
		
		# Build the window entry
		var entry: Dictionary = {
			"cabin_window": cabin_window,
			"marker": approach_marker,
			"window_id": window_id,
			"is_boarded": cabin_window.is_boarded,
			"planks_remaining": cabin_window.planks_remaining,
			"hits_on_current_plank": cabin_window.hits_on_current_plank,
		}
		
		# Add to the room group
		if not rooms.has(window_room):
			rooms[window_room] = []
		rooms[window_room].append(entry)
	
	if rooms.is_empty():
		return null
	
	# ─── STEP 1.5: REMOVE LIT ROOMS ────────────────────────────────────
	# Check each room's windows: if ANY window in that room has a room_light
	# that is switched on AND the generator is running (is_room_lit()), remove
	# the entire room from consideration. The Entity will not approach lit rooms.
	var lit_rooms: Array[String] = []
	for room_name in rooms.keys():
		var windows = rooms[room_name] as Array
		if windows.is_empty():
			lit_rooms.append(room_name)
			continue
		# Check the first window's CabinWindow for room_light
		var first_window = windows[0] as Dictionary
		var cw = first_window["cabin_window"] as CabinWindow
		if cw and cw.room_light:
			if cw.room_light.has_method("is_room_lit") and cw.room_light.is_room_lit():
				lit_rooms.append(room_name)
	
	for lit_room in lit_rooms:
		rooms.erase(lit_room)
		print("[Navigation] Room '%s' excluded: cabin light is ON." % lit_room)
	
	# ─── STEP 1.75: ALL ROOMS LIT → TRIGGER SABOTAGE ──────────────────
	# If ALL rooms were removed because their lights are on, return null.
	# The caller (_approach_window_state()) will detect null → signal completion
	# → Director transitions to OBSERVE_FROM_TREELINE → frustration accumulates
	# → Tier 1 Sabotage eventually triggers SABOTAGE_FUSE to break the fuse box.
	if rooms.is_empty():
		print("[Navigation] ALL ROOMS ARE LIT! Returning null: Entity cannot approach any window. Frustration will trigger SABOTAGE_FUSE.")
		return null
	
	# ─── STEP 2: SOFT PENALTY for last-heard room (never erase!) ──────
	# Previously this ERASED the entire room where the player was last heard.
	# If that room was the only non-lit room (and contained the banned window
	# PLUS a boarded sibling), the whole room vanished → pick_tactical_window()
	# returned null → APPROACH_WINDOW → OBSERVE → APPROACH loop, with the
	# viable boarded window never considered.
	#
	# Now windows are NEVER removed from the pool: a `_in_last_heard_room` flag
	# is stamped on each window so the ranking step can prefer OTHER rooms ONLY
	# when equally-attractive unboarded candidates exist. The last-heard room's
	# windows remain fully selectable when they are the only option.
	var last_heard_room_lc: String = last_heard_room.to_lower()
	for room_name in rooms.keys():
		var room_match: bool = room_name.to_lower() == last_heard_room_lc
		for entry in rooms[room_name] as Array:
			entry["_in_last_heard_room"] = room_match
	
	# ─── STEP 3: FLATTEN ALL REMAINING ROOMS INTO ONE CANDIDATE POOL ──
	# Collect EVERY window from every remaining (non-lit) room. The old
	# code picked a single room (fewest boarded windows) and only rolled
	# to rooms TIED at that same boarded count — so when the most
	# attractive unboarded window in a room was flinch-banned, the boardED
	# second window in that same room was never offered (the room lost the
	# "fewest boarded" comparison and was dropped entirely). The Entity
	# deadlocked: banned window → null → OBSERVE → APPROACH forever.
	#
	# New behavior (matches design):
	#   - Flinch-banned / breach-cooldown windows are SKIPPED (not erased).
	#   - Every remaining window across all rooms is a candidate.
	#   - If the most-attractive window is banned, the SECOND-most
	#     attractive viable window is chosen (e.g., the boarded window in
	#     the same room).
	#   - Only when NO window is viable (all lit / all banned / all on
	#     cooldown) is null returned → the Director routes to SABOTAGE_FUSE.
	var all_windows: Array[Dictionary] = []
	for room_name in rooms.keys():
		for entry in rooms[room_name] as Array:
			all_windows.append(entry)
	
	# ─── STEP 4: FILTER TO VIABLE WINDOWS, THEN RANK ───────────────────
	# Viability filters:
	#   1. Breach cooldown — hard skip (recently breached, truly unavailable).
	#   2. Flinch blacklist (string ID) — skip while banned (time-bounded,
	#      self-pruning on every read; the SINGLE source of truth for the
	#      interrupted-window ban).
	#
	# The old node-level flinch ban (_flinch_banned_window) is intentionally
	# NOT filtered here. Its "lift on a different selection" logic in
	# entity_ai.gd was what made the banned window re-selectable after a
	# single OBSERVE→APPROACH cycle. The time-limited string blacklist is
	# authoritative and cannot be accidentally cleared.
	var filtered_windows: Array[Dictionary] = []
	for entry in all_windows:
		var wid = entry["window_id"] as String
		
		# Breach cooldown filter
		if _breach_cooldowns.has(wid) and _breach_cooldowns[wid] > 0.0:
			continue
		
		# Flinch blacklist (string ID) filter
		if entity and entity.has_method("get_flinch_blacklisted_windows"):
			var blacklisted = entity.get_flinch_blacklisted_windows()
			if not blacklisted.is_empty() and blacklisted.has(wid):
				continue
		
		filtered_windows.append(entry)
	
	if filtered_windows.is_empty():
		print("[Navigation] No viable windows remain (all lit, on breach cooldown, or flinch-banned). Returning null → SABOTAGE_FUSE.")
		return null
	
	# Prefer unboarded windows
	var unboarded: Array[Dictionary] = []
	var boarded: Array[Dictionary] = []
	for entry in filtered_windows:
		if entry["is_boarded"]:
			boarded.append(entry)
		else:
			unboarded.append(entry)
	
	# ─── FLANKING PREFERENCE (soft): Among UNBOARDED windows, prefer those
	# NOT in the last-heard room (the Entity flanks away from the player's
	# known room). If ALL unboarded windows are in the last-heard room (or
	# there are none), fall back to ALL unboarded — so a banned unboarded
	# window + boarded sibling in the player's own room still yields a
	# selectable window instead of null.
	var unboarded_other: Array[Dictionary] = []
	var unboarded_heard: Array[Dictionary] = []
	for entry in unboarded:
		if entry.get("_in_last_heard_room", false):
			unboarded_heard.append(entry)
		else:
			unboarded_other.append(entry)
	
	var chosen_entry: Dictionary = {}
	if not unboarded.is_empty():
		var unboarded_pool: Array[Dictionary] = unboarded_other if not unboarded_other.is_empty() else unboarded_heard
		# Pick randomly among the preferred unboarded windows
		chosen_entry = unboarded_pool[randi() % unboarded_pool.size()]
		print("[Navigation] Window '%s' selected (unboarded%s)." % [chosen_entry["window_id"], ", last-heard room" if chosen_entry.get("_in_last_heard_room", false) else ""])
	else:
		# All boarded — pick the one with least barricade health.
		# barricade health = (planks_remaining * HITS_PER_PLANK) - hits_on_current_plank
		# Lower = closer to breaking.
		var best_boarded: Array[Dictionary] = []
		var lowest_health: int = 999
		for entry in boarded:
			var hits_remaining: int = (entry["planks_remaining"] * 3) - entry["hits_on_current_plank"]
			if hits_remaining < lowest_health:
				lowest_health = hits_remaining
				best_boarded = [entry]
			elif hits_remaining == lowest_health:
				best_boarded.append(entry)
		
		chosen_entry = best_boarded[randi() % best_boarded.size()]
		print("[Navigation] Window '%s' selected (boarded, %d hits remaining)." % [chosen_entry["window_id"], lowest_health])
	
	# Return the CabinWindow parent (same return type as before)
	var result_cabin_window: CabinWindow = chosen_entry["cabin_window"] as CabinWindow
	if result_cabin_window:
		return result_cabin_window
	
	return null



## Finds the nearest broken (glass shattered) and unboarded window to the Entity.
## Used by the RETREAT state when the Entity is inside the cabin and needs to
## escape through a window (e.g., when the player shines a flashlight at it
## indoors, or a room light is turned on while the Entity is inside).
##
## The Entity can only exit through windows that:
##   1. Have shattered glass (is_glass_shattered == true)
##   2. Are NOT boarded up (is_boarded == false)
##   3. Are on the ground floor (BottomFloorWindows group)
##
## Returns the CabinWindow node, or null if no suitable window is found.
func find_nearest_broken_window() -> Node3D:
	if _cabin_windows.is_empty():
		return null
	
	var closest: Node3D = null
	var closest_dist_sq: float = INF
	var entity_pos = entity.global_position
	
	for cabin_window in _cabin_windows:
		# Must have shattered glass AND not be boarded
		if not cabin_window.is_glass_shattered:
			continue
		if cabin_window.is_boarded:
			continue
		
		# Flatten Y to ignore height differences (compare in 2D XZ plane)
		var w_pos = cabin_window.global_position
		w_pos.y = entity_pos.y
		var d_sq: float = entity_pos.distance_squared_to(w_pos)
		if d_sq < closest_dist_sq:
			closest_dist_sq = d_sq
			closest = cabin_window
	
	return closest


func pick_next_vantage_point() -> void:
	# ─── STATE GUARD: Never override an active approach/breach targeting ──
	# If the Entity is mid-approach (APPROACH_WINDOW), peeking (WINDOW_PEEK),
	# or hunting inside (INDOOR_SEARCH), a treeline vantage point is NOT a
	# valid destination — it would redirect the Entity 30m+ away from the
	# cabin mid-action. Only callers in passive states (OBSERVE, FLINCH,
	# RETREAT arrival, etc.) should legitimately set a new vantage point.
	var entity_state = entity.get_state()
	# ─── APPROACH_WINDOW ABANDON BYPASS (Stuck-Loop Fix) ────────────────
	# fade_and_relocate() clears the window/door target BEFORE calling
	# pick_next_vantage_point(). If we are still in APPROACH_WINDOW but
	# no target remains (set_current_window_target(null) + is_door_target
	# false), the approach has been abandoned — allow relocation to break
	# the stuck loop that previously repeated every 1.5 seconds.
	var has_live_approach_target: bool = false
	if entity_state == EntityAI.State.APPROACH_WINDOW:
		var wp = entity.get_current_window_target()
		var door_target: bool = entity.get("is_door_target") == true
		has_live_approach_target = (wp != null) or door_target
	if entity_state == EntityAI.State.WINDOW_PEEK \
			or entity_state == EntityAI.State.INDOOR_SEARCH \
			or (entity_state == EntityAI.State.APPROACH_WINDOW and has_live_approach_target):
		print("[NAV_GUARD] pick_next_vantage_point() BLOCKED — Entity is in %s. Preserving current nav target." % EntityAI.State.keys()[entity_state])
		return
	
	var candidates = _treeline_markers.filter(func(m): return m != entity.get_last_vantage_point())
	if candidates.is_empty():
		candidates = _treeline_markers
	
	# ─── UTILITY SCORING (smarter flanking) ──────────────────────────────
	# Score each candidate by:
	#   1. Darkness (preferred) — the Entity hides in shadows, using the
	#      existing light cost grid.
	#   2. Reasonable distance from the player (25-45m band) — close enough
	#      to keep pressure but far enough to stay unnoticed.
	var best_marker: Node3D = candidates[0]
	var best_score: float = -INF
	var player_ref = entity.get_player()
	
	for marker in candidates:
		var score: float = 1.0
		var mark_pos: Vector3 = marker.global_position
		
		# Darkness bonus — prefer markers in pitch-black areas
		if is_position_in_dark(mark_pos):
			score += 2.0
		
		# Distance band bonus — prefer the 25-45m band from the player
		if player_ref:
			var dist_player: float = mark_pos.distance_to(player_ref.global_position)
			if dist_player >= 25.0 and dist_player <= 45.0:
				score += 1.0
		
		if score > best_score:
			best_score = score
			best_marker = marker
	
	entity.set_last_vantage_point(best_marker)
	entity.get_nav_agent().target_position = best_marker.global_position
	entity.set_at_vantage_point(false)
	
	# ─── DEBUG TARGET INJECTION ──────────────────────────────────────────
	# If the Entity is in INDOOR_SEARCH or APPROACH_WINDOW, warn when the
	# NavTarget is being set to a point more than 10 meters from the cabin
	# center. This helps identify which script is overriding the NavTarget
	# while the Entity is trying to approach the door or breach the interior.
	#
	# A valid approach/breach target should be near the cabin (within 10m).
	# If the target is in the forest (e.g., (30.45, 0, -10.52)), something
	# is wrong — the Entity is being redirected to a treeline vantage point
	# instead of the door/window it was approaching.
	# NOTE: entity_state is already declared at the top of this function
	# by the STATE GUARD. Reuse it here for the debug warning.
	if entity_state == EntityAI.State.INDOOR_SEARCH or entity_state == EntityAI.State.APPROACH_WINDOW:
		var cabin_dist = best_marker.global_position.distance_to(entity.cabin_center)
		if cabin_dist > 10.0:
			push_warning("[NAV_OVERRIDE] pick_next_vantage_point() setting target to (%.1f, %.1f, %.1f) — %.1fm from cabin! Entity state=%s" % [best_marker.global_position.x, best_marker.global_position.y, best_marker.global_position.z, cabin_dist, EntityAI.State.keys()[entity_state]])

