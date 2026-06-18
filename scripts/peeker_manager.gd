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
##   Every 20 seconds, if no peeker is currently active, there is a 50%
##   chance a new peeker will spawn at a random window the player isn't
##   looking at. This creates persistent "is something watching me?" tension
##   throughout Night 1.

## Preload the WindowPeeker scene.
const PEEKER_SCENE: PackedScene = preload("res://scenes/window_peeker.tscn")

## Dot-product threshold for checking if the player is looking at a window.
## cos(20°) ≈ 0.94 — matches the threshold used in entity_sensory.gd.
const GAZE_DOT_THRESHOLD: float = 0.94

## Interval in seconds between heartbeat checks.
## Every heartbeat, if no peeker is active, there's a 50% chance to spawn one.
const HEARTBEAT_INTERVAL: float = 20.0

## Debug flag: When true, the peeker will vanish when the player looks at it.
## When false, the peeker stays regardless of the player's gaze.
## Toggled via the Debug Console UI for testing purposes.
var peeker_vanish_on_sight: bool = true

## Reference to the currently active peeker instance, if any.
var _active_peeker: WindowPeeker = null

## Timer counting up to the next heartbeat check.
var _heartbeat_timer: float = 0.0


func _process(delta: float) -> void:
	# Count up the heartbeat timer
	_heartbeat_timer += delta
	if _heartbeat_timer >= HEARTBEAT_INTERVAL:
		_heartbeat_timer = 0.0
		_heartbeat()


## Called every HEARTBEAT_INTERVAL seconds.
## If no peeker is currently active, rolls a 50/50 chance to spawn one.
func _heartbeat() -> void:
	# Skip if a peeker is already active
	if _active_peeker and is_instance_valid(_active_peeker):
		return
	
	# 50/50 chance to spawn
	if randf() >= 0.5:
		print("[PeekerManager] Heartbeat: 50/50 roll passed. Attempting spawn...")
		_spawn_peeker()
	else:
		print("[PeekerManager] Heartbeat: 50/50 roll missed. No spawn this cycle.")


## Spawns a WindowPeeker at a random cabin window that the player is NOT
## currently looking at. The peeker is added as a child of the current scene
## root to avoid inheriting any local transforms from the window node.
func spawn_night_1_peeker() -> void:
	# Don't spawn if there's already an active peeker
	if _active_peeker and is_instance_valid(_active_peeker):
		print("[PeekerManager] Peeker already active. Skipping spawn.")
		return
	
	_spawn_peeker()


## Internal spawn logic shared by spawn_night_1_peeker() and _heartbeat().
func _spawn_peeker() -> void:
	var target_window = _pick_valid_window()
	if not target_window:
		return
	
	# Instantiate and position the peeker
	var peeker: WindowPeeker = _instantiate_peeker(target_window)
	if not peeker:
		return
	
	# Track the active peeker
	_active_peeker = peeker
	peeker.peeker_vanish_finished.connect(_on_peeker_vanish_finished)
	
	# Show HUD message
	var window_id = target_window.get("window_id") if "window_id" in target_window else target_window.name
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message("⚠️ Peeker spawned at: %s" % window_id)
	
	print("[PeekerManager] Night 1 Peeker spawned at window: ", target_window.name)


## Picks a random valid window that the player is not currently looking at.
## Returns null if no valid windows are available.
func _pick_valid_window() -> Node3D:
	var windows: Array[Node] = get_tree().get_nodes_in_group("WindowMarkers")
	if windows.is_empty():
		print("[PeekerManager] No windows found in 'WindowMarkers' group. Cannot spawn peeker.")
		return null
	
	# Filter out windows the player is currently looking at
	var valid_windows: Array[Node3D] = []
	for w in windows:
		var window_node = w as Node3D
		if window_node and window_node is CabinWindow and not _is_player_looking_at_window(window_node):
			valid_windows.append(window_node)
	
	if valid_windows.is_empty():
		print("[PeekerManager] All windows are being watched by the player. No valid target.")
		return null
	
	return valid_windows.pick_random()


## Instantiates a WindowPeeker and positions it at the given window.
## Returns the peeker instance, or null if something went wrong.
func _instantiate_peeker(target_window: Node3D) -> WindowPeeker:
	var peeker: WindowPeeker = PEEKER_SCENE.instantiate()
	
	# Add to the root scene so it inherits no local transforms from the window
	get_tree().current_scene.add_child(peeker)
	
	# Set global position to the window's position
	peeker.global_position = target_window.global_position
	
	# Align Peeker to face toward the cabin interior (toward the player).
	peeker.look_at(peeker.global_position - target_window.global_transform.basis.z)
	
	return peeker


## Called when the active peeker's vanish animation finishes.
## Clears the active peeker reference so the next heartbeat can spawn a new one.
func _on_peeker_vanish_finished() -> void:
	_active_peeker = null
	print("[PeekerManager] Peeker vanished. Next heartbeat may spawn a new one.")


## Returns true if the player's camera is pointed within ~20 degrees of the
## given window position. Used to filter out windows the player is already
## watching so the peeker doesn't spawn directly in their line of sight.
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
