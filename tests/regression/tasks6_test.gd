extends SceneTree
## planning/tasks.txt round 1 (planning/tasks_plan.txt):
##   1  the Day 1 Peeker at the bedroom window (bugs2/bugs4 check the spawn)
##   3  darker rain clouds
##   4  "Glad I'm not hydrophobic" 10 s into the Day 2 rain
##   5  Escape closes the notebook before the computer
##   6  the thought once the data is logged
##   10 a Night 2.2 restart leaves the front door unlocked and open
##   12 "What the FUCK was that?!" on reaching the cabin in the chase
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/regression/tasks6_test.gd

var _failures := 0
var _scene: Node
var _player: Node3D


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[TASKS6 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(60)
	_player = get_first_node_in_group("player")
	var game_time := root.get_node_or_null("GameTime")
	if game_time:
		game_time.is_time_paused = true
	root.get_node("NightManager").is_time_paused = true

	_test_peeker_window()
	_test_clouds()
	await _test_hydrophobic()
	await _test_notebook_escape()
	await _test_logging_thought()
	await _test_inside_thought()
	await _test_van_restart_door()

	print("[TASKS6 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _test_peeker_window() -> void:
	var pm: Node = root.get_node("PeekerManager")
	var window = pm._find_window_by_id("Bedroom_Right")
	_check("1: the bedroom window the Day 1 Peeker uses exists (upstairs)",
		window != null and window.global_position.y > 4.0, str(window))


func _test_clouds() -> void:
	var shader: Shader = load("res://shaders/day_night_sky.gdshader")
	var ec: Node = get_first_node_in_group("environment_controller")
	_check("3: rain clouds are pulled towards a dark slate grey with the storm",
		shader != null and shader.code.contains("lit = mix(lit, rain, storm)") and ec != null)


func _test_hydrophobic() -> void:
	var gamma: Node = null
	for nest in _scene.find_children("*", "", true, false):
		if nest.get("nest_label") == "Nest Gamma":
			gamma = nest
	gamma.lock_type = "stillness"
	gamma.lock_timer = gamma.lock_duration
	_player.velocity = Vector3.ZERO
	gamma.interact()
	var weather: Node = root.get_node("Weather")
	var storm: bool = weather._target > 0.0
	await _frames(9 * 60)
	var early: bool = root.get_node("Monologue").has_thought("hydrophobic")
	await _frames(int(1.5 * 60))
	_check("4: documenting Nest Gamma breaks the storm; 10 s later \"Glad I'm not hydrophobic\"",
		storm and not early and root.get_node("Monologue").has_thought("hydrophobic"), "storm=%s early=%s" % [storm, early])
	weather.clear_now()


func _test_notebook_escape() -> void:
	var computer: Node = get_first_node_in_group("computer_ui")
	var notebook: Node = get_first_node_in_group("notebook_ui")
	computer.open_computer()
	await _frames(5)
	notebook._input(_action("ui_notebook"))
	await _frames(3)
	var opened: bool = notebook.is_open()
	var pause: Node = _scene.find_child("PauseMenu", true, false)
	pause._unhandled_input(_action("pause_menu"))
	await _frames(3)
	var first: bool = not notebook.is_open() and computer.is_open
	pause._unhandled_input(_action("pause_menu"))
	await _frames(10)
	_check("5: Escape at the computer closes the notebook first, then the computer",
		opened and first and not computer.is_open, "opened=%s first=%s computer open=%s" % [opened, first, computer.is_open])
	if pause and pause.visible and pause.has_method("_on_resume_pressed"):
		pause._on_resume_pressed()
	paused = false


func _action(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _test_logging_thought() -> void:
	var computer: Node = get_first_node_in_group("computer_ui")
	computer._on_logging_done()
	await _frames(2 * 60)
	_check("6: the data logged and night fallen: \"One more night in this luxurious cottage...\"",
		root.get_node("Monologue").has_thought("one_more_night"))


func _test_inside_thought() -> void:
	var entity = get_first_node_in_group("entity")
	entity.van_chase_active = true
	_player.global_position = Vector3(10.0, 1.0, 13.0)   # the hall
	await _frames(int(1.6 * 60))
	var inside: bool = root.get_node("Monologue").has_thought("n22_inside")
	entity.van_chase_active = false
	_check("12: reaching the cabin in the Night 2.2 chase: \"What the FUCK was that?!\"", inside,
		"room %s" % _player.get_player_room())


func _test_van_restart_door() -> void:
	var nm: Node = root.get_node("NightManager")
	var van: Node = _scene.find_child("EscapeVan", true, false)
	var door: Node = get_first_node_in_group("Door")
	# In bed, the door locked behind the player; the alarm goes off.
	door.set_state_quietly(false, true)
	nm.current_night = 2
	nm.is_night_active = false
	nm._checkpoint_saved = false
	nm.is_van_sequence_active = true
	nm.horror_event.emit("car_alarm")
	await _frames(5)
	van.interact()
	await _frames(10)
	nm.restart_from_checkpoint()
	await _frames(10)
	_check("10: dying in Night 2.2 and restarting: the front door is unlocked and open",
		not door.is_locked and door.is_open, "locked=%s open=%s" % [door.is_locked, door.is_open])
