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
	
	# ─── DOOR MARKER VERIFICATION ──────────────────────────────────────
	# Verify that the door's IndoorBreachWaypoint marker is in the WindowMarkers
	# group. If not, log a warning so the developer knows to add it in the scene.
	var door_marker_found = false
	for w in _window_markers:
		if w.name == "IndoorBreachWaypoint" and w.get_parent() and w.get_parent().is_in_group("Door"):
			door_marker_found = true
			break
	if not door_marker_found:
		# Try to find the door marker directly
		var door = entity.get_tree().get_first_node_in_group("Door")
		if door:
			var marker = door.get_node_or_null("IndoorBreachWaypoint")
			if marker:
				print("[Navigation] WARNING: Door's IndoorBreachWaypoint found but NOT in WindowMarkers group! Add it to the WindowMarkers group in the scene editor.")
			else:
				print("[Navigation] WARNING: Door node found but missing IndoorBreachWaypoint child Marker3D! Add a Marker3D named 'IndoorBreachWaypoint' as a child of the Door node.")
		else:
			print("[Navigation] No Door node found in 'Door' group. Door approach will be unavailable.")



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
	
	# ─── PERIODIC DEBUG LOG (every 2 seconds) ──────────────────────────
	# Logs whether the player is considered inside or outside by both the
	# player's own room detection AND the Entity's navigation module.
	# This helps debug false "player is outside" detections that cause the
	# Entity to incorrectly enter STALK instead of INDOOR_SEARCH.
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
func _get_light_detector() -> Node:
	if not _light_detector or not is_instance_valid(_light_detector):
		_light_detector = entity.get_node_or_null("/root/RoomLightDetector")
	return _light_detector



## Returns true if ALL ground-floor windows are secured by light sanctuary.
## This means every window's room light is switched on AND the generator is
## running, making every window "secure" via light. The Entity cannot approach
## any window and must wait in OBSERVE_FROM_TREELINE until a light turns off.
##
## Used by the ALL_WINDOWS_LIT loop guard in entity_ai.gd to prevent the
## Entity from continuously cycling frames when there are no valid windows.
func are_all_windows_lit() -> bool:
	if _window_markers.is_empty():
		return false
	
	for w in _window_markers:
		# Only check ground-floor windows (same filter as pick_tactical_window)
		if not w.get_parent().is_in_group("BottomFloorWindows"):
			continue
		
		# Check if this window is NOT secure due to light
		# A window is "secure by light" when room_light.is_room_lit() returns true
		var is_secure_by_light: bool = false
		if "room_light" in w and w.room_light:
			if w.room_light.has_method("is_room_lit") and w.room_light.is_room_lit():
				is_secure_by_light = true
		
		if not is_secure_by_light:
			# Found a window that is NOT lit — not all windows are lit
			return false
	
	# All ground-floor windows are lit
	return true


## Returns true if the player is on the second floor of the cabin.
## Uses a Y-axis threshold (3.0 meters above ground level).
## Ground floor Y ≈ 0.0, second floor Y ≈ 3.0+
func is_player_on_second_floor() -> bool:
	var player = entity.get_player()
	if not player:
		return false
	return player.global_position.y > 3.0



## Finds the nearest exterior wall base position below a second-story window.
## Uses the cached _window_markers array to avoid tree traversal.
## Scans WindowMarkers, finds ones with Y > 3.0 (second story), projects their
## position down to ground level (Y = 0.0), and returns the closest one to the Entity.
## Used by CLIMB_WALL state to determine where to begin the vertical ascent.
func find_nearest_second_story_window_base() -> Vector3:
	var best_pos = Vector3.ZERO
	var shortest = INF
	for w in _window_markers:
		if w.global_position.y < 3.0:
			continue  # Skip ground-floor windows
		# Project the window position down to ground level
		var base_pos = Vector3(w.global_position.x, 0.0, w.global_position.z)
		var d = entity.global_position.distance_to(base_pos)
		if d < shortest:
			shortest = d
			best_pos = base_pos
	return best_pos


## Picks a tactical window using smart room-based deduction.
## The Entity selects the window the player is LEAST likely to be watching,
## based on acoustic intelligence and room lighting.
##
## SELECTION LOGIC:
##   1. Identify the `last_heard_room` (from entity_sensory) — the room the
##      Entity last heard the player in.
##   2. Get all available ground-floor windows (with standard filters applied).
##   3. Filter OUT any windows that belong to the `last_heard_room` — the Entity
##      avoids approaching the room it last heard the player in, because the
##      player is likely watching that window.
##   4. Prefer windows that belong to UNLIT rooms (using RoomLightDetector).
##      Dark rooms are safer approach points — the player can't see the Entity
##      approaching through the darkness.
##   5. If multiple candidates remain, pick the one furthest from the
##      `last_heard_exact_position` — the Entity flanks to the opposite side
##      of the cabin from where the player was last heard.
##
## LIGHT SANCTUARY FILTER:
##   Windows whose room light is switched on are EXCLUDED from selection.
##   The Entity will never approach a window that has an active CabinLight,
##   because the light makes the window "secure" — the Entity avoids lit areas.
##
## NIGHT 2 BOARDED WINDOW FILTER:
##   On Night 2, boarded windows are also excluded. The Entity can only
##   approach and peek through unboarded (glass-only) windows on Night 2.
##   On Night 3+, boarded windows are fair game.
##
## Parameters:
##   player: The player Node3D to measure distance from.
##
## Returns: A Node3D window marker, or null if no windows are available.
func pick_tactical_window(player: Node3D) -> Node3D:
	if not player or _window_markers.is_empty():
		return null
	
	# ─── GET ACOUSTIC INTELLIGENCE ──────────────────────────────────────
	# Read the last_heard_room from the sensory module. This tells us which
	# room the Entity last heard the player in. If empty, the Entity has no
	# acoustic intelligence and falls back to standard selection.
	var sensory = entity.get_sensory_module()
	var last_heard_room: String = ""
	if sensory and "last_heard_room" in sensory:
		last_heard_room = sensory.last_heard_room
	
	# Read the last_heard_exact_position from the controller for distance
	# calculations. This is the exact 3D position of the last noise the
	# Entity heard.
	var last_heard_pos: Vector3 = entity.get_last_heard_exact_position()
	
	# Determine the current night for boarded window filtering.
	var current_night: int = 3
	var night_manager = entity.get_node_or_null("/root/NightManager")
	if night_manager and "current_night" in night_manager:
		current_night = night_manager.current_night
	
	# ─── BUILD CANDIDATE LIST ───────────────────────────────────────────
	# Gather all ground-floor windows that pass standard filters.
	# Each candidate is stored as a dictionary with metadata for scoring.
	var candidates: Array[Dictionary] = []
	for w in _window_markers:
		# ─── BOTTOM FLOOR FILTER ──────────────────────────────────────
		if not w.get_parent().is_in_group("BottomFloorWindows"):
			continue
		
		# ─── LIGHT SANCTUARY FILTER ──────────────────────────────────
		if "room_light" in w and w.room_light and w.room_light.is_switched_on:
			continue
		
		# ─── NIGHT 2 BOARDED WINDOW FILTER ──────────────────────────
		if current_night == 2 and w.has_method("is_barricaded") and w.is_barricaded():
			continue
		
		# ─── BREACH COOLDOWN FILTER ──────────────────────────────────
		var cabin_window = w.get_parent() as CabinWindow
		if cabin_window and cabin_window.has_method("get_window_id"):
			var window_id = cabin_window.get_window_id()
			if _breach_cooldowns.has(window_id) and _breach_cooldowns[window_id] > 0.0:
				continue
		
		# ─── DETERMINE WHICH ROOM THIS WINDOW BELONGS TO ─────────────
		# Use RoomLightDetector to resolve the window's position to a room name.
		# This tells us which room the window is in, so we can apply the
		# "avoid last_heard_room" rule.
		var window_room: String = RoomLightDetector.get_room_name_at(w.global_position)
		
		# ─── CHECK IF THE WINDOW'S ROOM IS LIT ──────────────────────
		# Use RoomLightDetector to check if the room this window belongs to
		# is currently lit. Unlit rooms are preferred — the Entity can approach
		# through darkness without being seen.
		var is_room_lit: bool = RoomLightDetector.is_position_in_lit_room(w.global_position)
		
		# ─── CALCULATE DISTANCE FROM LAST HEARD POSITION ────────────
		# If we have a last_heard_exact_position, calculate the 2D distance
		# from that position to this window. The Entity prefers windows that
		# are FAR from where the player was last heard (flanking behavior).
		var dist_from_last_heard: float = INF
		if last_heard_pos != Vector3.ZERO:
			dist_from_last_heard = Vector2(
				w.global_position.x - last_heard_pos.x,
				w.global_position.z - last_heard_pos.z
			).length()
		
		# ─── STORE CANDIDATE ─────────────────────────────────────────
		candidates.append({
			"marker": w,
			"window_room": window_room,
			"is_room_lit": is_room_lit,
			"dist_from_last_heard": dist_from_last_heard,
			"is_last_heard_room": (window_room == last_heard_room and last_heard_room != "")
		})
	
	# ─── ADD THE FRONT DOOR AS A CANDIDATE ──────────────────────────────
	# The front door is treated as an entry point alongside windows.
	# It gets a bonus score (preferred over windows) because it's the most
	# direct entry point. The door is excluded if:
	#   1. It's locked (door.is_locked == true) — the Entity can't enter
	#   2. The door approach cooldown is active (entity._door_approach_cooldown > 0.0)
	#      — the Entity recently tried the door and found it locked
	#
	# The door is added as a candidate with special metadata:
	#   - "is_door": true (distinguishes it from window candidates)
	#   - "dist_from_last_heard": INF (the door has no room association,
	#     so it's always treated as "furthest from last heard position")
	#   - "is_last_heard_room": false (the door is not a room)
	#   - "is_room_lit": false (the door is not a room, so it's never "lit")
	var door = get_tree().get_first_node_in_group("Door")
	if door and door.has_method("is_in_group"):
		var door_locked: bool = door.is_locked if "is_locked" in door else false
		var door_cooldown: float = entity._door_approach_cooldown if "_door_approach_cooldown" in entity else 0.0
		
		if not door_locked and door_cooldown <= 0.0:
			# Find the EntityDoorWaypoint marker for pathfinding
			var door_wp: Node3D = null
			var waypoints = get_tree().get_nodes_in_group("EntityWaypoints")
			for wp in waypoints:
				if wp.name == "EntityDoorWaypoint":
					door_wp = wp
					break
			
			if door_wp:
				candidates.append({
					"marker": door_wp,
					"is_door": true,
					"window_room": "Outside",
					"is_room_lit": false,
					"dist_from_last_heard": INF,
					"is_last_heard_room": false
				})
				print("[Navigation] Door added as approach candidate (unlocked, cooldown=%.1f)." % door_cooldown)
	
	if candidates.is_empty():
		return null
	
	# ─── STEP 1: FILTER OUT LAST_HEARD_ROOM WINDOWS ────────────────────

	# Remove any windows that belong to the room the Entity last heard the
	# player in. The Entity avoids approaching the same room — the player
	# is likely watching that window. If ALL windows are in the last_heard_room
	# (or last_heard_room is empty), keep all candidates.
	var filtered: Array[Dictionary] = []
	for c in candidates:
		if not c["is_last_heard_room"]:
			filtered.append(c)
	
	# If filtering removed everything, fall back to all candidates
	if filtered.is_empty():
		filtered = candidates
	
	# ─── STEP 2: PREFER UNLIT ROOMS ────────────────────────────────────
	# Separate candidates into unlit (preferred) and lit (fallback).
	var unlit_candidates: Array[Dictionary] = []
	var lit_candidates: Array[Dictionary] = []
	for c in filtered:
		if not c["is_room_lit"]:
			unlit_candidates.append(c)
		else:
			lit_candidates.append(c)
	
	# ─── STEP 3: PICK THE FURTHEST FROM LAST HEARD POSITION ────────────
	# From the preferred group (unlit rooms), pick the window furthest from
	# the last_heard_exact_position. This creates a flanking behavior where
	# the Entity approaches from the opposite side of the cabin.
	# If no unlit candidates exist, fall back to lit candidates.
	var best_candidate: Dictionary = {}
	var best_dist: float = -INF
	
	var pool = unlit_candidates if not unlit_candidates.is_empty() else lit_candidates
	
	for c in pool:
		var d = c["dist_from_last_heard"]
		if d > best_dist:
			best_dist = d
			best_candidate = c
	
	if best_candidate.is_empty():
		# Absolute fallback: pick the first candidate
		best_candidate = filtered[0]
	
	# CRITICAL: Return the PARENT node (CabinWindow), not the Marker3D itself.
	var selected_marker: Node3D = best_candidate["marker"] as Node3D
	if selected_marker:
		return selected_marker.get_parent() as Node3D
	
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
	if _window_markers.is_empty():
		return null
	
	var closest: Node3D = null
	var closest_dist: float = INF
	var entity_pos_2d = Vector2(entity.global_position.x, entity.global_position.z)
	
	for w in _window_markers:
		# Only ground-floor windows
		if not w.get_parent().is_in_group("BottomFloorWindows"):
			continue
		
		var cabin_window = w.get_parent() as CabinWindow
		if not cabin_window:
			continue
		
		# Must have shattered glass AND not be boarded
		if not cabin_window.is_glass_shattered:
			continue
		if cabin_window.is_boarded:
			continue
		
		var w_pos_2d = Vector2(w.global_position.x, w.global_position.z)
		var d: float = entity_pos_2d.distance_to(w_pos_2d)
		if d < closest_dist:
			closest_dist = d
			closest = cabin_window
	
	return closest


func pick_next_vantage_point() -> void:
	var candidates = _treeline_markers.filter(func(m): return m != entity.get_last_vantage_point())
	if candidates.is_empty():
		candidates = _treeline_markers
	
	var best_marker = candidates.pick_random()
	entity.set_last_vantage_point(best_marker)
	entity.get_nav_agent().target_position = best_marker.global_position
	entity.set_at_vantage_point(false)
