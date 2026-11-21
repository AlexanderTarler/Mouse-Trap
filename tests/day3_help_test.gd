extends SceneTree
## Day 3+ help:
##   - finding the van's parts: two minutes after "Find parts" comes up, and
##     again after each part found, a wreck that still has a part is
##     highlighted, until all three are found;
##   - a death never restarts into a hopeless night: the flashlight and the
##     generator come back with at least a fair minimum.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/day3_help_test.gd

var _failures := 0
var _scene: Node
var _rm: Node


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[DAY3 HELP TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _hinted() -> Array:
	return get_nodes_in_group(_rm.WRECK_HINT_GROUP)


func _lit(wreck: Node) -> bool:
	for mesh in wreck.find_children("*", "MeshInstance3D", true, false):
		if (mesh as MeshInstance3D).has_meta("_xray_saved"):
			return true
	return false


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	# (The level's own start-up sets the story to Day 1 first.)
	await _frames(150)
	_rm = root.get_node("RoutineManager")
	var highlights_were: bool = _rm.enable_object_highlights
	_rm.enable_object_highlights = true

	# Day 3, the van not looked at yet: no hints.
	_rm.is_day3_sandbox = true
	_rm.van_inspected = false
	await _frames(5)
	_check("no wreck hint before the van has been looked at", _hinted().is_empty() and _rm._wreck_hint_left < 0.0)

	# "Find parts to repair the van." comes up: the countdown starts.
	_rm.on_van_inspected()
	await _frames(5)
	var counting: float = _rm._wreck_hint_left
	_check("looking at the van starts a %d s countdown to the first hint" % int(_rm.WRECK_HINT_AFTER),
		counting > _rm.WRECK_HINT_AFTER - 1.0 and counting <= _rm.WRECK_HINT_AFTER, "%.1f s left" % counting)
	_rm._wreck_hint_left = 0.05
	await _frames(5)
	var hinted := _hinted()
	var first: Node = hinted[0] if hinted.size() == 1 else null
	_check("then one wreck that has a part is highlighted",
		first != null and first.get("item_resource") != null and not first.get("is_looted") and _lit(first),
		"%d hinted" % hinted.size())

	# Its part found: the highlight goes, the next hint is two minutes off.
	if first:
		first.is_looted = true
		_rm.on_car_part_collected(String(first.item_resource.item_name))
	await _frames(5)
	_check("its part found: the highlight goes and the next hint is two minutes off",
		first != null and not _lit(first) and _hinted().is_empty() and _rm._wreck_hint_left > _rm.WRECK_HINT_AFTER - 1.0,
		"%.1f s left" % _rm._wreck_hint_left)
	_rm._wreck_hint_left = 0.05
	await _frames(5)
	var second: Array = _hinted()
	_check("the next hint is another wreck that still has a part",
		second.size() == 1 and second[0] != first and not second[0].get("is_looted"))

	# All three found: no more hints.
	_rm._clear_wreck_hint()
	_rm.van_battery_collected = true
	_rm.van_radiator_collected = true
	_rm.van_wiring_collected = true
	await _frames(5)
	_check("all parts found: no more hints", _hinted().is_empty() and _rm._wreck_hint_left < 0.0)

	# A fair restart.
	var nm: Node = root.get_node("NightManager")
	var player := get_first_node_in_group("player")
	var flashlight: Node = player.get_node("CameraHolder/Camera3D/Flashlight")
	flashlight.set_battery_level(4.0)
	nm.generator_fuel = 3.0
	nm._restore_fair_minimum()
	_check("after a death the flashlight is at least half charged and the generator a third full",
		flashlight.battery_level >= flashlight.max_battery * 0.5 - 0.01 and nm.generator_fuel >= nm.max_fuel * 0.35 - 0.01,
		"battery %.0f, fuel %.0f" % [flashlight.battery_level, nm.generator_fuel])
	flashlight.set_battery_level(90.0)
	nm.generator_fuel = 80.0
	nm._restore_fair_minimum()
	_check("more than the minimum is left as it was", is_equal_approx(flashlight.battery_level, 90.0) and is_equal_approx(nm.generator_fuel, 80.0))

	_rm.enable_object_highlights = highlights_were
	print("[DAY3 HELP TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)
