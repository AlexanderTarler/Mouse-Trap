extends SceneTree
## The Entity's hearing:
##   - footsteps carry far in the open (walk 18 m, sprint 35 m)
##   - a tree in between barely muffles; a cabin wall muffles hard
##   - an open window lets sound out of its room
##   - near the edge of hearing the position is only roughly known
##   - a noise heard from inside tells it which room the player is in, and it
##     favours that room's windows (and grows bolder)
##   - boarding, doors, switches and footsteps all reach it through NoiseEvent.emit
##   - the debug overlay reports the last noise
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/hearing_test.gd

const YARD := Vector3(20.0, 0.3, 4.0)
const HALL_NOISE := Vector3(6.5, 0.75, 11.0)
const LIVING_NOISE := Vector3(7.2, 0.75, 18.4)
const COMPUTER_NOISE := Vector3(14.0, 0.75, 17.4)

var _failures := 0
var _scene: Node
var _entity
var _player: CharacterBody3D
var _nm: Node


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[HEARING TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	# Normal game rules, whatever the level's dev-mode toggle says.
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(10)
	_entity = get_first_node_in_group("entity")
	_player = get_first_node_in_group("player") as CharacterBody3D
	_nm = root.get_node("NightManager")
	_player.set_process(false)
	_player.set_physics_process(false)
	_nm.current_night = 3
	_nm.is_time_paused = true
	var game_time := root.get_node_or_null("GameTime")
	if game_time:
		game_time.is_time_paused = true
	_entity.can_kill = false
	_entity.activate()
	_entity.request_state(_entity.State.OBSERVE)
	_close_cabin()
	await _frames(5)

	var line := _open_line(28.0)
	if line.is_empty():
		_check("setup: found an unobstructed 28 m line outdoors", false)
	else:
		_test_open_ground(line)
		_test_imprecision(line)
	_test_tree()
	_test_cabin_wall()
	_test_open_window()
	_test_heard_room()
	_test_noise_sources()
	_test_overlay()

	print("[HEARING TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


# ─── Helpers ─────────────────────────────────────────────────────────────────

## Door shut and locked, every window intact and unboarded.
func _close_cabin() -> void:
	for link in get_nodes_in_group("cabin_entry_links"):
		if link.kind == 0:
			link.entry.is_locked = true
			link.entry.is_open = false
	for window in get_nodes_in_group("WindowMarkers"):
		if window.has_method("is_passable"):   # the group also holds plain markers
			window.is_glass_shattered = false
			window.is_boarded = false


func _ground(p: Vector3) -> Vector3:
	return _entity.world.snap_to_navmesh(p)


## The Entity at `entity_pos` is told about a noise; returns what it made of it.
func _hear(entity_pos: Vector3, noise_pos: Vector3, kind: StringName) -> Dictionary:
	_entity.global_position = entity_pos
	_entity.perception._last_heard_clock = -INF
	_entity.hear_noise(noise_pos, kind)
	return _entity.perception.last_noise


func _desc(n: Dictionary) -> String:
	return "%.1f m away, carries %.1f m, %d wall(s), %d obstacle(s), via %s" % [n.distance, n.range, n.walls, n.obstacles, n.via]


## Two outdoor ground points `length` apart with nothing at all in between.
func _open_line(length: float) -> Array:
	for i in 80:
		var a := _ground(YARD + Vector3(randf_range(-15.0, 15.0), 0.0, randf_range(-15.0, 15.0)))
		var dir := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		var b := _ground(a + dir * length)
		if a.distance_to(b) < length - 0.5 or _entity.world.is_inside_cabin(a) or _entity.world.is_inside_cabin(b):
			continue
		var n := _hear(a, b, &"click")
		if n.walls == 0 and n.obstacles == 0:
			return [a, b]
	return []


# ─── Scenarios ───────────────────────────────────────────────────────────────

func _test_open_ground(line: Array) -> void:
	var a: Vector3 = line[0]
	var b: Vector3 = line[1]
	var dir := (b - a).normalized()
	var walk_15 := _hear(a, _ground(a + dir * 15.0), &"walk")
	var walk_25 := _hear(a, _ground(a + dir * 25.0), &"walk")
	var sprint_25 := _hear(a, _ground(a + dir * 25.0), &"sprint")
	_check("open ground: walking heard at 15 m", walk_15.heard, _desc(walk_15))
	_check("open ground: walking not heard at 25 m", not walk_25.heard, _desc(walk_25))
	_check("open ground: sprinting heard at 25 m (from a vantage point)", sprint_25.heard, _desc(sprint_25))


## C: near the edge of hearing the position is fuzzy; close by it is exact.
func _test_imprecision(line: Array) -> void:
	var a: Vector3 = line[0]
	var dir: Vector3 = (line[1] - a).normalized()
	var far := _ground(a + dir * 17.0)
	var near := _ground(a + dir * 5.0)
	var far_errors: Array[float] = []
	var near_errors: Array[float] = []
	for i in 12:
		_hear(a, far, &"walk")
		far_errors.append(Vector2(_entity.perception.last_heard_position.x - far.x, _entity.perception.last_heard_position.z - far.z).length())
		_hear(a, near, &"walk")
		near_errors.append(Vector2(_entity.perception.last_heard_position.x - near.x, _entity.perception.last_heard_position.z - near.z).length())
	var max_far: float = far_errors.max()
	var max_near: float = near_errors.max()
	_check("imprecision: a noise at the edge of hearing is placed roughly (1-5 m off)",
		max_far > 1.0 and max_far <= _entity.config.hearing_max_error + 0.01, "up to %.1f m off" % max_far)
	_check("imprecision: a close noise is placed exactly", max_near < 0.01, "up to %.2f m off" % max_near)


## B: a tree in between barely muffles.
func _test_tree() -> void:
	var trees := _scene.get_node("Details/Outside Cabin").get_children().filter(
		func(n): return "pine" in str(n.name).to_lower() and n is Node3D)
	for tree in trees:
		var trunk := _ground((tree as Node3D).global_position)
		if trunk.distance_to((tree as Node3D).global_position) > 1.5 or _entity.world.is_inside_cabin(trunk):
			continue
		for angle in [0.0, 1.6, 3.1, 4.7]:
			var dir := Vector3.FORWARD.rotated(Vector3.UP, angle)
			var ear := _ground(trunk + dir * 4.0)
			var source := _ground(trunk - dir * 8.0)
			var n := _hear(ear, source, &"walk")
			if n.walls == 0 and n.obstacles >= 1:
				_check("tree: a trunk in between barely muffles (walk still heard at %.0f m)" % n.distance,
					n.heard and n.range >= 18.0 * _entity.config.hearing_obstacle_floor, _desc(n))
				return
	_check("tree: found a trunk to test with", false)


## B: cabin walls cut sound hard.
func _test_cabin_wall() -> void:
	_close_cabin()
	var near := _hear(_ground(Vector3(6.5, 0.3, 4.0)), HALL_NOISE, &"walk")
	var far := _hear(_ground(Vector3(6.5, 0.3, 0.5)), HALL_NOISE, &"walk")
	_check("cabin wall: footsteps in the hall heard just outside the front wall", near.heard and near.walls >= 1, _desc(near))
	_check("cabin wall: ...but not 10 m out (it would be in the open)", not far.heard and far.walls >= 1 and far.distance < 18.0, _desc(far))


## B: a broken, unboarded window lets sound out of its room.
func _test_open_window() -> void:
	_close_cabin()
	var outside := _ground(Vector3(7.8, 0.3, 28.0))
	var shut := _hear(outside, LIVING_NOISE, &"walk")
	var window: Node = _scene.get_node("Windows/BottomFloorWindows/LivingRoomWindow")
	window.is_glass_shattered = true
	var open := _hear(outside, LIVING_NOISE, &"walk")
	window.is_boarded = true
	var boarded := _hear(outside, LIVING_NOISE, &"walk")
	_close_cabin()
	_check("window: living room footsteps not heard 10 m out while the window is intact", not shut.heard, _desc(shut))
	_check("window: heard through the broken window", open.heard and open.walls == 0, _desc(open))
	_check("window: not heard once it is boarded up again", not boarded.heard, _desc(boarded))


## D: a noise heard inside tells it where the player is; it keeps away from
## that room's windows (it would rather not be seen) and grows bolder.
func _test_heard_room() -> void:
	_close_cabin()
	var had_power: bool = _nm.is_generator_on
	_nm.is_generator_on = false   # all rooms dark: lights don't sway the choice
	var outside := _ground(Vector3(19.5, 0.3, 17.4))
	_entity.global_position = outside
	_entity.perception.reset_memory()
	var before := _count_computer_picks(30)
	var confidence_before: float = _entity.confidence.confidence
	var n := _hear(outside, COMPUTER_NOISE, &"walk")
	var boost: float = _entity.confidence.confidence - confidence_before
	var suspected: String = _entity.perception.suspected_player_room()
	var after := _count_computer_picks(30)
	_nm.is_generator_on = had_power
	_check("heard room: footsteps in the computer room heard through its wall", n.heard, _desc(n))
	_check("heard room: it now thinks the player is in the ComputerRoom", suspected == "ComputerRoom", "'%s'" % suspected)
	_check("heard room: it keeps away from that room's windows", after <= 3, "%d/30 picks (before the noise: %d/30)" % [after, before])
	_check("heard room: a noise from inside makes it bolder", boost > 0.0, "confidence +%.2f" % boost)


func _count_computer_picks(tries: int) -> int:
	var hits := 0
	for i in tries:
		var link = _entity.world.pick_entry()
		if link and "ComputerRoom" in str(link.entry.name):
			hits += 1
	return hits


## E: game actions reach the Entity through NoiseEvent.emit.
func _test_noise_sources() -> void:
	_close_cabin()
	var window: Node = _scene.get_node("Windows/BottomFloorWindows/HallWindowRight")
	var in_front := _ground(window.global_position + Vector3(0.0, 0.0, -14.0))
	_entity.global_position = in_front
	window._is_boarding = true
	window._hammer_noise_timer = 0.0
	window._process_hold_interact(1.05)
	window._is_boarding = false
	window._boarding_progress = 0.0
	var hammer: Dictionary = _entity.perception.last_noise
	_check("sources: boarding a window hammers loud enough to hear 14 m away",
		hammer.get("kind") == &"hammer" and hammer.get("heard", false), _desc(hammer) if not hammer.is_empty() else "no noise")

	var door: Node = _scene.get_node("NavigationRegion3D/Cabin/Door")
	door.is_locked = false
	_entity.perception.last_noise = {}
	door.interact()
	var door_noise: Dictionary = _entity.perception.last_noise
	door.interact()
	door.is_locked = true
	_check("sources: opening the door makes a noise", door_noise.get("kind") == &"door", str(door_noise.get("kind")))

	_entity.perception.last_noise = {}
	_scene.get_node("Lightswitches/LightSwitchHall/InteractionArea").interact()
	var click: Dictionary = _entity.perception.last_noise
	_scene.get_node("Lightswitches/LightSwitchHall/InteractionArea").interact()
	_check("sources: flipping a light switch makes a (quiet) noise", click.get("kind") == &"click", str(click.get("kind")))

	_entity.perception.last_noise = {}
	_player.global_position = _ground(YARD)
	_player.make_noise(&"walk")
	_check("sources: the player's footsteps reach the Entity", _entity.perception.last_noise.get("kind") == &"walk",
		str(_entity.perception.last_noise.get("kind")))


## F: the debug overlay reports the last noise.
func _test_overlay() -> void:
	var overlay = _entity.get_node_or_null("DebugOverlay")
	if not overlay:
		_check("overlay: present (debug build)", false)
		return
	var text: String = overlay._build_text()
	_check("overlay: shows the last noise and where it thinks the player is",
		"last noise:" in text and "thinks the player is in" in text)
