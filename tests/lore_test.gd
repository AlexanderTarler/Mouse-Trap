extends SceneTree
## Crows at the willow, the opening, and Arvid's notes:
##   - crows perch by day, take off when the player (or the Entity) comes
##     near, stay away at night;
##   - the opening freezes the player, shows the phone failing to send, and
##     [Space] skips it and gives the player back;
##   - the notes and the terminal logs tell one story (the Institute, the
##     bait, the willow), and the notebook names the player, not Arvid.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/lore_test.gd

var _failures := 0
var _scene: Node


func _initialize() -> void:
	_run()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[LORE TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(30)
	await _test_crows()
	await _test_opening()
	_test_story()
	print("[LORE TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _states(crows: Node) -> Array:
	var out := []
	for c in crows._crows:
		out.append(c.state)
	return out


func _test_crows() -> void:
	var crows: Node = _scene.find_child("Crows", true, false)
	var player := get_first_node_in_group("player") as Node3D
	var gt: Node = root.get_node("GameTime")
	gt.is_day = true
	player.global_position = Vector3(60, 1, 40)
	crows._settle_all()
	await _frames(20)
	var perched: bool = _states(crows).all(func(s): return s == crows.State.PERCHED)
	_check("crows perch at the willow by day (%d)" % crows._crows.size(), crows._crows.size() >= 5 and perched)
	player.global_position = crows.CENTRE + Vector3(4, 0.6, 0)
	await _frames(40)
	var flying: bool = _states(crows).all(func(s): return s != crows.State.PERCHED)
	_check("they take off when the player comes close", flying, str(_states(crows)))
	player.global_position = Vector3(60, 1, 40)
	await _frames(int(60 * 10))
	await _frames(30)
	var back: bool = _states(crows).all(func(s): return s == crows.State.PERCHED)
	_check("and settle again once the player is far away", back, str(_states(crows)))
	# GameTime held still, or its next tick sets is_day back from the clock.
	gt.set_process(false)
	gt.is_day = false
	await _frames(30)
	var gone: bool = _states(crows).all(func(s): return s != crows.State.PERCHED)
	_check("none stay at night", gone, str(_states(crows)))
	gt.is_day = true
	gt.set_process(true)


func _test_opening() -> void:
	var player: Node = get_first_node_in_group("player")
	var opening := Opening.new()
	_scene.add_child(opening)
	opening.play()
	await _frames(30)
	var frozen: bool = not player.is_physics_processing()
	# Until the message has failed (the opening's timers run on real time).
	for i in 60 * 40:
		await process_frame
		var failed := false
		for label in opening._thread.find_children("*", "Label", true, false):
			if "Not delivered" in (label as Label).text:
				failed = true
		if failed:
			break
	var thread_text := ""
	for row in opening._thread.get_children():
		for label in row.find_children("*", "Label", true, false):
			thread_text += (label as Label).text + " | "
	_check("the opening freezes the player; the phone has no service and the message fails",
		frozen and "No service" in opening._service.text and "Not delivered" in thread_text and "terminal" in thread_text, thread_text)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	opening._unhandled_input(key)
	await _frames(5)
	_check("[Space] skips it and gives the player back", player.is_physics_processing() and (not is_instance_valid(opening) or not opening.playing))


func _test_story() -> void:
	var note_1: String = (load("res://resources/arvid_note.tres") as Resource).note_text
	var note_2: String = (load("res://resources/arvid_note_2.tres") as Resource).note_text
	var ui := load("res://scripts/computer_ui.gd") as Script
	var consts := ui.get_script_constant_map()
	var logs: String = consts.ARVID_LOG_01_SURVEY + consts.ARVID_LOG_02_CRITICAL
	_check("Arvid's notes: no signal, the tunnel; the bait, the willow, his login",
		"signal" in note_1 and "tunnel" in note_1 and "bait" in note_2 and "willow" in note_2 and "STENBERG" in note_2 and "1996" in note_2)
	_check("the terminal logs: the Institute, and the trap as it works (floodlight, overload, the willow)",
		"Institute" in logs and "floodlight" in logs and "OVERLOAD" in logs and "willow" in logs)
	var notebook := load("res://scripts/ui/notebook_ui.gd") as Script
	var credentials: String = notebook.get_script_constant_map().CREDENTIALS_PAGE
	_check("the notebook's credentials are the player's (Lund), replacing Stenberg",
		"Researcher:[/b] Lund" in credentials and "Stenberg" in credentials and not "Lindqvist" in credentials)
