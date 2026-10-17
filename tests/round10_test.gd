extends SceneTree
## planning/tasks.txt (round 10):
##   1 the Day 1 roof crows go up at 50 m (tasks16_test)
##   2 no time of day in the pause menu (round9_test)
##   3 starting faster: the forest's checks quicker (and the forest exactly as
##     before), the level loading in the background from the main menu, the
##     opening playing while the level comes in under it
##   4 broken windows leave their glass on the floor inside
##   + the game's forest sounds silent behind the main menu
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/round10_test.gd

var _failures := 0
var _scene: Node


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[ROUND10 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	SaveGame.path = "user://round10_test_save.dat"
	await _frames(2)
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(120)
	get_first_node_in_group("entity").can_kill = false

	_test_fast_checks()
	await _test_shards()
	await _test_menu()
	await _test_opening()

	print("[ROUND10 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	SaveGame.delete()
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


## The quick answers are the same answers (the forest's layout hangs on them).
func _test_fast_checks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 10
	var road_wrong := 0
	var path_wrong := 0
	for i in 20000:
		var p := Vector3(rng.randf_range(-130, 130), 0, rng.randf_range(-130, 130))
		var margin := rng.randf_range(0.0, 10.0)
		if GravelRoad.covers(p, margin) != (GravelRoad.distance_to(p) < GravelRoad.width_at(p.x) * 0.5 + margin):
			road_wrong += 1
		var reach := rng.randf_range(0.0, 1.5)
		var slow := TerrainMask.path(p) > 0.1
		for offset in [Vector3(reach, 0, 0), Vector3(-reach, 0, 0), Vector3(0, 0, reach), Vector3(0, 0, -reach)]:
			slow = slow or TerrainMask.path(p + offset) > 0.1
		if TerrainMask.near_path(p, reach) != slow:
			path_wrong += 1
	_check("3: the road and path checks, made quick, answer exactly as before (20000 points)", road_wrong == 0 and path_wrong == 0,
		"%d road, %d path differ" % [road_wrong, path_wrong])


func _test_shards() -> void:
	var broken: Node3D = null
	var whole: Node3D = null
	for w in get_nodes_in_group("WindowMarkers"):
		if not "start_broken" in w:
			continue
		if w.start_broken:
			broken = w
		elif not w.is_glass_shattered and not w.is_upstairs_window and whole == null:
			whole = w
	var shards: MeshInstance3D = broken.get_node_or_null("FloorShards")
	var inward: Vector3 = broken.global_basis.z.normalized()
	var box := shards.global_transform * shards.get_aabb() if shards else AABB()
	var inside := shards != null and (box.get_center() - broken.global_position).dot(inward) > 0.1
	var on_floor := shards != null and box.position.y < broken.global_position.y - 1.0 and box.size.y < 0.05
	_check("4: the window broken from the start has its glass on the floor inside, under it (%s)" % box, shards != null and shards.visible and inside and on_floor)
	# Breaking one now leaves glass too; a restored checkpoint takes it away.
	var none_before: bool = whole.get_node_or_null("FloorShards") == null
	var checkpoint: Node = root.get_node("Checkpoint")
	checkpoint.capture("day")
	whole.shatter_window()
	await _frames(5)
	var after: MeshInstance3D = whole.get_node_or_null("FloorShards")
	var shown := after != null and after.visible
	checkpoint.restore()
	await _frames(5)
	_check("4: a window broken in play leaves glass; back to before it broke, it's gone", none_before and shown and not after.visible)


func _test_menu() -> void:
	var sounds: Node = root.get_node("HorrorSoundManager")
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	_scene.add_child(menu)
	await _frames(3)
	var quiet: bool = sounds.menu_quiet and sounds.process_mode == Node.PROCESS_MODE_DISABLED
	# (Not loading the level on a thread here: only as the game's own menu.)
	var loading := ResourceLoader.load_threaded_get_status("res://scenes/cottage_horror.tscn") != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	menu.queue_free()
	await _frames(3)
	_check("+: behind the main menu the game's forest sounds are silent, and back after it (no level loading on a thread inside a test)",
		quiet and not sounds.menu_quiet and sounds.process_mode != Node.PROCESS_MODE_DISABLED and not loading)


## The opening from the menu: on black before the level; the level brought in
## between cards once loaded; skipped early, it waits on black for it.
func _test_opening() -> void:
	var loaded := [false]
	var asked := [0]
	var opening := Opening.new()
	opening.level_ready = false
	opening.start_level = func() -> bool:
		asked[0] += 1
		return loaded[0]
	root.add_child(opening)
	opening.play()
	await _frames(60 * 5)
	var waited_on_cards: bool = asked[0] > 0 and not opening._level_started and opening.playing
	loaded[0] = true
	await _frames(60 * 4)
	var brought: bool = opening._level_started
	# Skipped before the level is up: black and "Loading...".
	opening._unhandled_input(_space())
	await _frames(2)
	var waits: bool = is_instance_valid(opening) and opening._loading.visible and opening._black.color.a > 0.99
	opening.attach_to_game()
	await _frames(60 * 2)
	_check("3: the opening plays on black before the level is in, brings it in between cards once loaded, and if skipped early waits for it",
		waited_on_cards and brought and waits and not is_instance_valid(opening), "asked %d" % asked[0])


func _space() -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	return key
