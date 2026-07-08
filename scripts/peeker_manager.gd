extends Node

## PeekerManager — Manages the "Night 1 Peeker" visual prop events.
##
## This autoload handles spawning WindowPeeker instances at cabin windows
## during Night 1. It is completely disconnected from the Entity AI system
## — the peeker is a standalone visual prop, NOT an Entity.
##
## USAGE:
##   PeekerManager.spawn_night_1_peeker()
##
## The peeker is instantiated as a child of the current scene root (not the
## target window) to avoid inheriting any local rotation or scale from the
## window node, which would warp the peeker's model.
##
## HEARTBEAT BEHAVIOR:
##   Every 20 seconds, if no peeker is currently active, a new peeker will
##   always spawn at a random window the player isn't looking at (excluding
##   the window it was last seen at). This creates persistent "is something
##   watching me?" tension throughout Night 1.

## Preload the WindowPeeker scene.
const PEEKER_SCENE: PackedScene = preload("res://scenes/window_peeker.tscn")

## Dot-product threshold for checking if the player is looking at a window.
## cos(20°) ≈ 0.94 — matches the threshold used in entity_sensory.gd.
const GAZE_DOT_THRESHOLD: float = 0.94

## Interval in seconds between heartbeat checks.
## Every heartbeat, if no peeker is active, a new one will spawn.
const HEARTBEAT_INTERVAL: float = 20.0

## Debug flag: When true, the peeker will vanish when the player looks at it.
## When false, the peeker stays regardless of the player's gaze.
## Toggled via the Debug Console UI for testing purposes.
var peeker_vanish_on_sight: bool = true

## Reference to the currently active peeker instance, if any.
var _active_peeker: WindowPeeker = null

## The window_id of the last window a peeker spawned at.
## Used to prevent the peeker from respawning at the same window twice in a row.
var _last_peeker_window_id: String = ""

## Timer counting up to the next heartbeat check.
var _heartbeat_timer: float = 0.0


func _process(delta: float) -> void:
	_heartbeat_timer += delta
	if _heartbeat_timer >= HEARTBEAT_INTERVAL:
		_heartbeat_timer = 0.0
		_heartbeat()


## Returns true if Night 1 is currently active.
func _is_night_1_active() -> bool:
	var nm = get_node_or_null("/root/NightManager")
	if not nm:
		return false
	return nm.current_night == 1 and nm.is_night_active


## Called every HEARTBEAT_INTERVAL seconds.
## If no peeker is currently active, spawns a new one.
func _heartbeat() -> void:
	if not _is_night_1_active():
		return
	
	if _active_peeker and is_instance_valid(_active_peeker):
		return
	
	print("[PeekerManager] Heartbeat: Attempting spawn...")
	_spawn_peeker()


## Spawns a WindowPeeker at a random cabin window that the player is NOT
## currently looking at.
func spawn_night_1_peeker() -> void:
	if _active_peeker and is_instance_valid(_active_peeker):
		print("[PeekerManager] Peeker already active. Skipping spawn.")
		return
	
	if not _is_player_inside_cabin():
		print("[PeekerManager] Player is outside the cabin. Skipping peeker spawn.")
		return
	
	_spawn_peeker()


## Internal spawn logic.
func _spawn_peeker() -> void:
	var target_window = _pick_valid_window()
	if not target_window:
		return
	
	var peeker: WindowPeeker = _instantiate_peeker(target_window)
	if not peeker:
		return
	
	_active_peeker = peeker
	peeker.peeker_vanish_finished.connect(_on_peeker_vanish_finished)
	
	var window_id = target_window.get("window_id") if "window_id" in target_window else target_window.name
	_last_peeker_window_id = window_id
	
	print("[PeekerManager] Night 1 Peeker spawned at window: ", target_window.name)


## Picks a random valid window that:
##   - The player is not currently looking at
##   - Is not the window where the peeker was last seen
## Returns null if no valid windows are available.
func _pick_valid_window() -> Node3D:
	var windows: Array[Node] = get_tree().get_nodes_in_group("WindowMarkers")
	if windows.is_empty():
		print("[PeekerManager] No windows found in 'WindowMarkers' group.")
		return null
	
	var valid_windows: Array[Node3D] = []
	for w in windows:
		var window_node = w as Node3D
		if not window_node or not (window_node is CabinWindow):
			continue
		if _is_player_looking_at_window(window_node):
			continue
		var wid = window_node.get("window_id") if "window_id" in window_node else window_node.name
		if wid == _last_peeker_window_id:
			continue
		valid_windows.append(window_node)
	
	if valid_windows.is_empty():
		print("[PeekerManager] No valid windows available.")
		return null
	
	return valid_windows.pick_random()


## Instantiates a WindowPeeker and positions it below ground at the window.
## The peeker will tween up into view (handled by WindowPeeker._ready).
func _instantiate_peeker(target_window: Node3D) -> WindowPeeker:
	var peeker: WindowPeeker = PEEKER_SCENE.instantiate()
	get_tree().current_scene.add_child(peeker)
	
	# Position at the window's XZ but below ground (Y offset handled by peeker)
	peeker.global_position = target_window.global_position
	
	# Face toward the cabin interior
	peeker.look_at(peeker.global_position - target_window.global_transform.basis.z)
	
	return peeker


func _on_peeker_vanish_finished() -> void:
	_active_peeker = null
	print("[PeekerManager] Peeker vanished. Next heartbeat may spawn a new one.")


func _is_player_looking_at_window(window: Node3D) -> bool:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return false
	
	var cam: Camera3D = player.get_node_or_null("CameraHolder/Camera3D")
	if not cam:
		return false
	
	var cam_forward: Vector3 = -cam.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	
	var to_window: Vector3 = window.global_position - cam.global_position
	to_window.y = 0.0
	to_window = to_window.normalized()
	
	return cam_forward.dot(to_window) >= GAZE_DOT_THRESHOLD


func _is_player_inside_cabin() -> bool:
	var player = get_tree().get_first_node_in_group("player")
	if not player or not player.has_method("get_player_room"):
		return false
	return player.get_player_room() != "Outside"
