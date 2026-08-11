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
	
	# ─── NIGHT 2.2+ CLEANUP CHECK ────────────────────────────────────
	# The peeker must NEVER remain visible from Night 2.2 (car alarm
	# sequence) onwards. If a peeker was spawned during Night 2.1 and is
	# still active when the player goes to bed (which sets
	# is_van_sequence_active = true), it must be force-deleted here.
	# Also covers Night 3+ nights where current_night >= 3 — the peeker
	# should never appear again.
	var nm_cleanup = get_node_or_null("/root/NightManager")
	if _active_peeker and is_instance_valid(_active_peeker):
		if nm_cleanup:
			if nm_cleanup.get("is_van_sequence_active") == true:
				print("[PeekerManager] Van sequence active with lingering peeker. Removing peeker.")
				remove_active_peeker()
			elif nm_cleanup.get("current_night") != null and int(nm_cleanup.current_night) >= 3:
				print("[PeekerManager] Night %s — peeker disabled. Removing lingering peeker." % str(nm_cleanup.current_night))
				remove_active_peeker()
	
	# ─── CABIN-EXIT CHECK ────────────────────────────────────────────
	# If the peeker is active but the player has left the cabin,
	# immediately remove it. This prevents the peeker from being visible
	# while the player is outside (where it shouldn't appear).
	if _active_peeker and is_instance_valid(_active_peeker):
		if not _is_player_inside_cabin():
			print("[PeekerManager] Player left cabin with active peeker. Removing peeker.")
			remove_active_peeker()


## Returns true if the peeker is allowed to appear this night.
##
## BUG 9 FIX: The peeker is allowed on Night 1 AND Night 2.1 (Day 2 before
## the van sequence), but NOT Night 2.2 (car alarm sequence) or onwards.
## Night 2.2 is detected via the NightManager's is_van_sequence_active flag,
## which the bed sets to true when the Nest Data upload sleep triggers the
## car alarm. Nights 3+ are excluded by the current_night <= 2 gate.
func _is_night_1_active() -> bool:
	var nm = get_node_or_null("/root/NightManager")
	if not nm:
		return false
	
	# Night 1: normal peeker behavior (active night, current_night == 1)
	if nm.current_night == 1 and nm.is_night_active:
		return true
	
	# Night 2.1: ONLY active when a NIGHT is actually in progress.
	# Previously this returned true for all of Day 2 daytime because
	# is_night_active was NOT checked → the peeker spawned during Day 2
	# daytime (playtest bug). The peeker is a NIGHT-ONLY visual event.
	# Excluded when is_van_sequence_active (Night 2.2) — the peeker must
	# never appear during the car-alarm chase narrative.
	if nm.current_night == 2 and nm.is_night_active and not nm.is_van_sequence_active:
		return true
	
	# Night 2.2+ and everything onwards: peeker disabled.
	return false


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


## Forces immediate removal of the currently active peeker, if any.
## Used when transitioning out of Night 1 or when the player leaves the cabin.
## The peeker is freed without playing the duck-down animation, since these
## are hard transitions that should be instant.
func remove_active_peeker() -> void:
	if not _active_peeker or not is_instance_valid(_active_peeker):
		return
	
	print("[PeekerManager] Force-removing active peeker.")
	_active_peeker.peeker_vanish_finished.disconnect(_on_peeker_vanish_finished)
	_active_peeker.queue_free()
	_active_peeker = null
	_heartbeat_timer = 0.0


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
##   - Is NOT in a room with the cabin light ON (Bug 8: lika lit rooms)
##   - Is NOT fully boarded up (the peeker cannot peek through a sealed wall)
##
## BUG 8 FIX: Prioritises unboarded windows in unlit rooms. Boarded windows
## are only used as a fallback if no unboarded+unlit options exist. Windows
## in lit rooms are never selected since the peeker cannot appear where the
## player can clearly see the window.
## Returns null if no valid windows are available.
func _pick_valid_window() -> Node3D:
	var windows: Array[Node] = get_tree().get_nodes_in_group("WindowMarkers")
	if windows.is_empty():
		print("[PeekerManager] No windows found in 'WindowMarkers' group.")
		return null
	
	var unlit_unboarded: Array[Node3D] = []
	var unlit_boarded: Array[Node3D] = []
	
	for w in windows:
		var window_node = w as Node3D
		if not window_node or not (window_node is CabinWindow):
			continue
		if _is_player_looking_at_window(window_node):
			continue
		var wid = window_node.get("window_id") if "window_id" in window_node else window_node.name
		if wid == _last_peeker_window_id:
			continue
		
		# ─── BUG 8: SKIP LIT ROOMS ────────────────────────────────
		# If the window belongs to a room whose cabin light is actually
		# emitting (room_light is set AND is_room_lit()), the peeker must
		# NOT appear there — the player could see it clearly.
		var room_lit: bool = false
		if "room_light" in window_node and window_node.room_light:
			if window_node.room_light.has_method("is_room_lit"):
				room_lit = window_node.room_light.is_room_lit()
			elif "is_switched_on" in window_node.room_light:
				room_lit = window_node.room_light.is_switched_on
		if room_lit:
			continue
		
		# ─── BUG 8: SKIP FULLY BOARDED WINDOWS ───────────────────
		# A fully boarded/sealed window (3 planks) cannot be peeked through.
		var fully_boarded: bool = false
		if "is_boarded" in window_node and window_node.is_boarded:
			if "planks_remaining" in window_node and window_node.planks_remaining >= 3:
				fully_boarded = true
		if fully_boarded:
			continue
		
		# ─── PRIORITY SORTING: Unboarded first, then partially boarded ──
		# All surviving windows are unlit. Split into unboarded (priority)
		# and partially-or-fully boarded (fallback).
		var is_boarded_state: bool = "is_boarded" in window_node and window_node.is_boarded
		if is_boarded_state:
			unlit_boarded.append(window_node)
		else:
			unlit_unboarded.append(window_node)
	
	# ─── SELECTION: Prioritise unboarded windows in unlit rooms ──
	if not unlit_unboarded.is_empty():
		return unlit_unboarded.pick_random()
	if not unlit_boarded.is_empty():
		print("[PeekerManager] No unboarded unlit windows. Falling back to partially-boarded unlit windows.")
		return unlit_boarded.pick_random()
	
	print("[PeekerManager] No valid windows available (all lit or fully boarded).")
	return null


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
