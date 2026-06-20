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
## Every heartbeat, if no peeker is active, there's a 50% chance to spawn one.
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
	# Count up the heartbeat timer
	_heartbeat_timer += delta
	if _heartbeat_timer >= HEARTBEAT_INTERVAL:
		_heartbeat_timer = 0.0
		_heartbeat()


## Returns true if Night 1 is currently active (the peeker should be allowed).
## The peeker should ONLY appear during Night 1 — not during Day 1 onboarding
## or any other time.
func _is_night_1_active() -> bool:
	var nm = get_node_or_null("/root/NightManager")
	if not nm:
		return false
	return nm.current_night == 1 and nm.is_night_active


## Called every HEARTBEAT_INTERVAL seconds.
## If no peeker is currently active, always spawns a new one at a random
## window the player isn't looking at (excluding the last window).
func _heartbeat() -> void:
	# ─── NIGHT 1 GUARD ──────────────────────────────────────────────
	# The peeker should ONLY appear during Night 1. Skip the heartbeat
	# entirely if Night 1 hasn't started yet or has already ended.
	if not _is_night_1_active():
		return
	
	# Skip if a peeker is already active
	if _active_peeker and is_instance_valid(_active_peeker):
		return
	
	# Always spawn — no 50/50 roll. The peeker reappears every 20 seconds
	# as long as it's not currently active.
	print("[PeekerManager] Heartbeat: Attempting spawn...")
	_spawn_peeker()


## Spawns a WindowPeeker at a random cabin window that the player is NOT
## currently looking at. The peeker is added as a child of the current scene
## root to avoid inheriting any local transforms from the window node.
func spawn_night_1_peeker() -> void:
	# Don't spawn if there's already an active peeker
	if _active_peeker and is_instance_valid(_active_peeker):
		print("[PeekerManager] Peeker already active. Skipping spawn.")
		return
	
	# ─── INSIDE CABIN CHECK ──────────────────────────────────────────
	# Only spawn the peeker if the player is currently inside the cabin.
	# If the player is outside (e.g., at the generator or car), the peeker
	# would spawn at a window they can't see, wasting the scare.
	if not _is_player_inside_cabin():
		print("[PeekerManager] Player is outside the cabin. Skipping peeker spawn.")
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
	
	# ─── REMEMBER LAST WINDOW ────────────────────────────────────────
	# Store the window_id so the next spawn can exclude this window.
	var window_id = target_window.get("window_id") if "window_id" in target_window else target_window.name
	_last_peeker_window_id = window_id
	
	# Show HUD message
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message("⚠️ Peeker spawned at: %s" % window_id)
	
	print("[PeekerManager] Night 1 Peeker spawned at window: ", target_window.name)


## Room names that belong to the bottom floor.
const BOTTOM_FLOOR_ROOMS: Array[String] = ["HallRoom", "LivingRoom", "ComputerRoom"]

## Room names that belong to the second floor.
const UPPER_FLOOR_ROOMS: Array[String] = ["Stairs", "UpperHallRoom", "OfficeRoom", "BedRoom"]

## Returns the floor the player is currently on based on their room.
## Uses get_player_room() to determine which room the player is in,
## then checks against the known room-to-floor mappings.
## Returns "bottom" or "upper".
func _get_player_floor() -> String:
	var player = get_tree().get_first_node_in_group("player")
	if not player or not player.has_method("get_player_room"):
		return "bottom"
	
	var room: String = player.get_player_room()
	
	if room in UPPER_FLOOR_ROOMS:
		return "upper"
	
	# Default to bottom floor (includes "Outside", unknown rooms, etc.)
	return "bottom"


## Returns true if the given window is on the specified floor.
## Uses the window's window_id or name to determine which floor it belongs to.
## Bottom floor windows have IDs like "LivingRoomWindow", "HallRoomWindow", etc.
## Upper floor windows have IDs like "UpperHallWindow", "BedRoomWindowRight", etc.
func _is_window_on_floor(window: Node3D, floor: String) -> bool:
	var window_id = window.get("window_id") if "window_id" in window else window.name
	
	# Check if the window name contains any upper-floor room name
	for upper_room in UPPER_FLOOR_ROOMS:
		if upper_room.to_lower() in window_id.to_lower():
			return floor == "upper"
	
	# Check if the window name contains any bottom-floor room name
	for bottom_room in BOTTOM_FLOOR_ROOMS:
		if bottom_room.to_lower() in window_id.to_lower():
			return floor == "bottom"
	
	# Fallback: if we can't determine the floor from the name, assume
	# the window is on the same floor as the player.
	return true


## Picks a random valid window that:
##   - Is on the same floor as the player
##   - The player is not currently looking at
##   - Is not the window where the peeker was last seen
## Returns null if no valid windows are available.
func _pick_valid_window() -> Node3D:
	var windows: Array[Node] = get_tree().get_nodes_in_group("WindowMarkers")
	if windows.is_empty():
		print("[PeekerManager] No windows found in 'WindowMarkers' group. Cannot spawn peeker.")
		return null
	
	var player_floor = _get_player_floor()
	
	# Filter windows by floor, gaze, and last-seen exclusion
	var valid_windows: Array[Node3D] = []
	for w in windows:
		var window_node = w as Node3D
		if not window_node or not (window_node is CabinWindow):
			continue
		# Only target windows on the same floor as the player
		if not _is_window_on_floor(window_node, player_floor):
			continue
		if _is_player_looking_at_window(window_node):
			continue
		# Skip the last window the peeker was seen at
		var wid = window_node.get("window_id") if "window_id" in window_node else window_node.name
		if wid == _last_peeker_window_id:
			continue
		valid_windows.append(window_node)
	
	if valid_windows.is_empty():
		print("[PeekerManager] No valid windows on the %s floor. Player may be between floors." % player_floor)
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


## Returns true if the player is currently inside the cabin.
## Uses the player's get_player_room() method — if the result is anything
## other than "Outside", the player is inside a cabin room and the peeker
## can spawn.
##
## This prevents the peeker from spawning when the player is outside
## (e.g., at the generator, car, or treeline) where they wouldn't see it.
func _is_player_inside_cabin() -> bool:
	var player = get_tree().get_first_node_in_group("player")
	if not player or not player.has_method("get_player_room"):
		return false
	
	var room: String = player.get_player_room()
	return room != "Outside"
