extends SceneTree
## planning/tasks.txt, from the second playtest (Day 1 / Night 1):
##   1 the "Hold SHIFT to sprint" hint goes after 3 s of sprinting
##   2 the van isn't "broken" before Night 2.2 (no "busted", no checklist)
##   3 the flashlight drains half as fast
##   4 the battery hint says [TAB] opens the inventory, and comes up when
##     the battery runs out (if it hasn't yet)
##   5 at the computer, Escape closes the notebook first (real key events)
##   6 the notebook's page hints sit 10% further in; one notebook only
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/tasks10_test.gd

var _failures := 0
var _scene: Node
var _player: Node3D


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[TASKS10 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap(code: Key) -> void:
	_key(code, true)
	await _frames(3)
	_key(code, false)
	await _frames(3)


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(60)
	_player = get_first_node_in_group("player")

	_test_notebook_layout()
	await _test_escape_at_computer()
	await _test_van_before_alarm()
	await _test_flashlight()
	await _test_sprint_hint()

	print("[TASKS10 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _test_notebook_layout() -> void:
	var notebooks := get_nodes_in_group("notebook_ui")
	_check("6: one notebook (the player used to make a second one)", notebooks.size() == 1, str(notebooks.map(func(n): return n.name)))
	var notebook: Node = notebooks[0]
	var prev := notebook.get_node("%PrevHint") as Label
	var next := notebook.get_node("%NextHint") as Label
	_check("6: \"Prev Page\" and \"Next Page\" sit 10% further towards the middle",
		is_equal_approx(prev.anchor_left, 0.1) and is_equal_approx(next.anchor_right, 0.9))


func _test_escape_at_computer() -> void:
	var notebook: Node = get_first_node_in_group("notebook_ui")
	var computer: Node = get_first_node_in_group("computer_ui")
	computer.open_computer()
	await _frames(10)
	await _tap(KEY_J)
	var opened: bool = notebook.is_open()
	await _tap(KEY_ESCAPE)
	var first: bool = not notebook.is_open() and computer.is_open
	await _tap(KEY_ESCAPE)
	_check("5: at the computer, J opens the notebook, Escape closes it (the computer stays), Escape again leaves the computer",
		opened and first and not computer.is_open, "opened=%s notebook-only=%s computer=%s" % [opened, first, computer.is_open])
	paused = false


func _test_van_before_alarm() -> void:
	var van: Node = _scene.find_child("EscapeVan", true, false)
	var rm: Node = root.get_node("RoutineManager")
	var hud: Node = get_first_node_in_group("hud")
	van.interact()
	await _frames(3)
	_check("2: examining the van before Night 2.2: not broken (no repair, no checklist), just the ride home",
		not rm.van_inspected and not van.van_investigated and "busted" not in van.get_interact_text() and van.get_interact_text().begins_with("[E] Examine"))


func _test_flashlight() -> void:
	var flashlight: Node = _player.get_node("CameraHolder/Camera3D/Flashlight")
	_check("3: the flashlight drains half as fast (%.2f a second)" % flashlight.drain_rate, is_equal_approx(flashlight.drain_rate, 0.25))
	var hint: TutorialData = load("res://resources/tutorial/tutorial_low_battery.tres")
	_check("4: the battery hint says [TAB] opens the inventory", "[TAB]" in hint.prompt_text and "inventory" in hint.prompt_text, hint.prompt_text)
	var tm: Node = root.get_node("TutorialManager")
	_player.enable_flashlight()
	if not flashlight.is_on:
		flashlight.toggle()
	flashlight._low_battery_hint_shown = true   # as if its 30% moment was lost
	tm._shown.erase("low_battery")
	# (No other hint on screen: one up blocks it.)
	for i in 300:
		if tm.visible_hint() == "":
			break
		tm.mark_learned(tm.visible_hint())
		await _frames(1)
	flashlight.battery_level = 0.01
	await _frames(5)
	_check("4: out of battery: the battery hint comes up (if it hadn't yet)", tm._shown.has("low_battery"), tm.visible_hint())
	flashlight.battery_level = 100.0


func _test_sprint_hint() -> void:
	var tm: Node = root.get_node("TutorialManager")
	_player.sprint_unlocked = true
	_player._sprint_hold_time = 0.0
	_player._sprint_tutorial_marked = false
	tm.trigger("sprint", true)
	_player.global_position = Vector3(30.0, 1.0, 30.0)   # the open yard
	await _frames(5)
	_key(KEY_SHIFT, true)
	_key(KEY_W, true)
	await _frames(120)
	var at_two: bool = tm.is_learned("sprint")
	await _frames(80)
	var after: bool = tm.is_learned("sprint")
	_key(KEY_W, false)
	_key(KEY_SHIFT, false)
	_check("1: the sprint hint stays for the first seconds, gone after 3 s of sprinting (%.1f s)" % _player._sprint_hold_time,
		not at_two and after)
