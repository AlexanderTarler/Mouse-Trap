extends SceneTree
## planning/tasks.txt round 7, round D (planning/tasks_plan_r7.txt):
##   17 the cabin's and the trails' details are in the level (CabinDetails,
##      ForestDetails: written by tools/bake_details.gd), so they can be
##      moved in the editor; nothing is added at runtime any more
##   18 the small loose things in and around the cabin are KnockableProps:
##      picked up with a hold of E (like the bucket)
##   16 more crows: the cabin's roof ridge on Day 1 (up when the player is
##      ~20 m off, and not back that day), the barn roof, the wreck yard,
##      the clear-cut
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/tasks16_test.gd

var _failures := 0
var _scene: Node
var _player: CharacterBody3D


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[TASKS16 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	await _frames(2)
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(120)
	_player = get_first_node_in_group("player")

	_test_baked()
	# (The crows first: standing in the cabin for the loose things would
	# send the Day 1 roof flock off for good.)
	await _test_crows()
	await _test_loose()

	print("[TASKS16 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _test_baked() -> void:
	var cabin: Node = _scene.get_node_or_null("CabinDetails")
	var forest: Node = _scene.get_node_or_null("ForestDetails")
	_check("17: the details are in the level (CabinDetails %d, ForestDetails %d), nothing added at runtime" %
		[cabin.get_child_count() if cabin else -1, forest.get_child_count() if forest else -1],
		cabin and forest and cabin.get_child_count() >= 30 and forest.get_child_count() >= 30
		and _scene.find_child("SiteDresser", true, false) == null)
	# Saved with their owners: an editor would show and save them.
	var unowned := 0
	if cabin:
		for node in cabin.find_children("*", "", true, true):
			if node.owner == null:
				unowned += 1
	_check("17: they belong to the level (%d without an owner)" % unowned, unowned == 0)


func _test_loose() -> void:
	var cabin: Node = _scene.get_node("CabinDetails")
	var loose: Array = cabin.get_children().filter(func(n): return n is KnockableProp)
	var fallen := loose.filter(func(n: Node3D): return n.global_position.y < -1.0)
	_check("18: the small loose things in and around the cabin can be picked up (%d KnockableProps), none fallen through" % loose.size(),
		loose.size() >= 20 and fallen.is_empty())
	var own := ["coin_mp_12", "glass_bottle_12", "PsxLowPolyHomeInteriorPropsPackFootBallLod0"]
	_check("18: the level's own loose things are too (the coin, a bottle, the football)",
		own.all(func(n): return _scene.get_node(n) is KnockableProp))
	# Pick one up the way the grab does.
	var grab: Node = get_first_node_in_group("physical_grab")
	var book: KnockableProp = null
	for prop in loose:
		if String(prop.name).begins_with("book"):
			book = prop
	var was := book.global_position
	_check("18: on the grab's layer", (grab.INTERACTABLE_LAYER_MASK & book.collision_layer) != 0)
	# Standing by it (the grab carries what it holds in front of the player).
	_player.global_position = was + Vector3(1.0, 0.2, 0.0)
	await _frames(10)
	grab._grab_object(book)
	book.global_position += Vector3(0.0, 0.3, 0.0)
	await _frames(2)
	grab._drop_object()
	await _frames(60)
	_check("18: a book picked up and set down again elsewhere (moved %.2f m)" % book.global_position.distance_to(was),
		book.global_position.distance_to(was) > 0.05 and book.global_position.distance_to(was) < 6.0 and book.global_position.y > 0.5)


func _test_crows() -> void:
	var roof: Node = _scene.find_child("CrowsCabinRoof", true, false)
	var others := ["CrowsBarnRoof", "CrowsWreckYard", "CrowsClearcut", "Crows"].map(func(n): return _scene.find_child(n, true, false))
	var perched := func(flock: Node) -> bool:
		return flock != null and not flock._crows.is_empty() and flock._crows.all(func(c): return c.state == flock.State.PERCHED)
	_player.set_physics_process(false)
	_player.global_position = Vector3(9.0, 1.0, -9.0)   # 26 m from the roof
	await _frames(60)
	var still: bool = perched.call(roof)
	var ridge: float = roof._crows[0].node.global_position.y if roof else 0.0
	_check("16: Day 1, crows on the cabin's roof ridge (y %.1f), sitting tight with the player 26 m off" % ridge, still and ridge > 8.0)
	_check("16: and at the barn, the wreck yard, the clear-cut (and the willow)", others.all(func(f): return perched.call(f)),
		str(others.map(func(f): return f.name if f else "missing")))
	_player.global_position = Vector3(9.0, 1.0, -1.0)   # 18 m
	await _frames(60)
	var up: bool = roof._crows.all(func(c): return c.state != roof.State.PERCHED)
	_player.global_position = Vector3(9.0, 1.0, -80.0)   # far off
	await _frames(60 * 8)
	var back: bool = roof._crows.any(func(c): return c.state == roof.State.PERCHED)
	_check("16: within ~20 m they fly off, and don't come back that day", up and not back, "up %s, back %s" % [up, back])
