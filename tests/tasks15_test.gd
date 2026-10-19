extends SceneTree
## planning/tasks.txt round 7, round C (planning/tasks_plan_r7.txt):
##   6  climbing to an upstairs window it "reaches" it about a metre lower
##      (config.perch_head_height 2.65), and clinging there its climb pose
##      is frozen (it played on in place)
##   7  leaving through a window it faces it and crawls out (LowCrawl, low
##      over the sill), downstairs and up (then it turns to face the wall
##      and climbs down)
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/tasks15_test.gd

var _failures := 0
var _scene: Node
var _entity


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[TASKS15 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	await _frames(2)
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(90)
	var player: CharacterBody3D = get_first_node_in_group("player")
	player.global_position = Vector3(12.2, 3.9, 17.4)   # the bedroom
	player.set_physics_process(false)
	_entity = get_first_node_in_group("entity")
	_entity.can_kill = false

	await _test_perch()
	await _test_ground_exit()
	await _test_upper_exit()

	print("[TASKS15 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _window(window_name: String) -> Node:
	for window in get_nodes_in_group("WindowMarkers"):
		if window.name == window_name:
			return window
	return null


func _test_perch() -> void:
	var landing: Node = _window("LandingWindow")
	var link: CabinEntryLink = landing._entry_link
	_entity.get_node("DebugOverlay").debug_landing_breach()
	var perched := false
	for i in 60 * 30:
		await _frames(1)
		if _entity.is_perched_at(link):
			perched = true
			break
	await _frames(30)
	var below: float = landing.global_position.y - _entity.global_position.y
	_check("6: it reaches the upstairs window ~1 m lower than before (feet %.2f m below its centre, was 1.65)" % below,
		perched and absf(below - 2.65) < 0.25)
	var a: Transform3D = _skeleton_pose()
	await _frames(60)
	var b: Transform3D = _skeleton_pose()
	_check("6: clinging there its climb pose is frozen (not climbing on the spot)",
		_entity._anim_player.speed_scale == 0.0 and a.is_equal_approx(b), "anim speed %.2f" % _entity._anim_player.speed_scale)


## A bone's pose (the first bone with any rotation), to see if it moves.
func _skeleton_pose() -> Transform3D:
	var skeleton: Skeleton3D = _entity.find_children("*", "Skeleton3D", true, false)[0]
	return skeleton.get_bone_pose(min(5, skeleton.get_bone_count() - 1))


## Leaving through `window` (opened) from inside: [facing within 25 deg the
## whole way to the sill, the crawl played].
func _leave_through(window: Node, from_inside: float) -> Array:
	window.shatter_window()
	for i in 6:
		window.damage_barricade()
	await _frames(30)
	var link: CabinEntryLink = window._entry_link
	_entity.debug_breach = false
	var inward: Vector3 = (link.end_position - link.start_position) * Vector3(1, 0, 1)
	_entity._teleport(link.end_position + inward.normalized() * from_inside)
	_entity.request_state(_entity.State.FLEE, {"calm": true})
	var crawled := false
	var worst := 0.0
	var crossed := false
	for i in 60 * 15:
		await _frames(1)
		if _entity.is_traversing():
			crossed = true
			if _entity._traversal_anim == _entity.EXIT_CRAWL_ANIM:
				crawled = true
			var to_window: Vector3 = (window.global_position - _entity.global_position) * Vector3(1, 0, 1)
			var facing: Vector3 = _entity.global_basis.z * Vector3(1, 0, 1)
			# Until it's through (the window then behind it).
			if to_window.dot(inward) < 0.0 and to_window.length() > 0.3:
				worst = maxf(worst, rad_to_deg(facing.angle_to(to_window)))
		elif crossed:
			break
	return [crossed and worst < 25.0, crawled, worst]


func _test_ground_exit() -> void:
	var result: Array = await _leave_through(_window("LivingRoomWindow"), 2.5)
	_check("7: out of a ground-floor window: facing it all the way (worst %.0f deg), crawling out" % result[2], result[0] and result[1])


func _test_upper_exit() -> void:
	var landing: Node = _window("LandingWindow")
	var result: Array = await _leave_through(landing, 1.5)
	var link: CabinEntryLink = landing._entry_link
	var to_wall: Vector3 = (link.end_position - link.start_position) * Vector3(1, 0, 1)
	var facing: Vector3 = _entity.global_basis.z * Vector3(1, 0, 1)
	_check("7: out of the upstairs window: facing it (worst %.0f deg), crawling out; down the wall facing it" % result[2],
		result[0] and result[1] and _entity.global_position.y < 1.5)
