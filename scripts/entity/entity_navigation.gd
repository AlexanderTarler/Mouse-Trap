extends Node

## Entity Navigation System — Vantage point selection, outside detection, and pathfinding helpers.
## Receives a reference to the parent entity_controller to read/write shared state.

var entity: CharacterBody3D = null


func setup(parent: CharacterBody3D) -> void:
	entity = parent


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
