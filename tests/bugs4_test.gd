extends SceneTree
## The fourth bugs.txt round:
##   1. The plank thought comes with the "Find 3 planks" objective (after the
##      computer is closed), not with the first plank.
##   2. The Day 1 door-lock Peeker is at the landing window, also when the
##      door was locked before the objective came up.
##   3. Waking up is a little after dawn, and the sky shows it at once.
##   4. The clock, time to day/night, room and generator show only with F3;
##      the battery only while the flashlight is on.
##   5. The nests' crouch / stand still hints go once done.
##   6. Rain brings clouds.
##   7. The Night 2.2 chase stops at the edge of the porch light.
##   8. A thought when the car is first inspected on Day 3.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/bugs4_test.gd

var _failures := 0
var _scene: Node
var _tm: Node
var _rm: Node


func _initialize() -> void:
	_run()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[BUGS4 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(90)
	_tm = root.get_node("TutorialManager")
	_rm = root.get_node("RoutineManager")

	await _test_plank_thought()
	await _test_peeker()
	await _test_wake()
	await _test_hud()
	await _test_nest_hints()
	_test_clouds()
	_test_van_thought()
	await _test_porch()

	print("[BUGS4 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	paused = false
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _test_plank_thought() -> void:
	var monologue: Node = root.get_node("Monologue")
	var pc: Node = get_first_node_in_group("computer_ui")
	_rm.on_plank_picked_up()
	var after_plank: bool = monologue.has_thought("broken_window")
	pc.is_open = true
	_rm.phase2_computer_used = false
	_rm.on_computer_used()
	var while_open: bool = monologue.has_thought("broken_window")
	pc.computer_closed.emit()
	pc.is_open = false
	await _frames(2)
	_check("#1 the plank thought comes as 'Find 3 planks' starts, once the computer is closed",
		not after_plank and not while_open and monologue.has_thought("broken_window"))
	monologue._clear()


func _test_peeker() -> void:
	var pm: Node = root.get_node("PeekerManager")
	var player := get_first_node_in_group("player") as Node3D
	player.global_position = (_scene.get_node("PlayerSpawnpoints/PlayerSpawnDev") as Node3D).global_position
	# Locked early (while still on the planks), ticked off when it comes up.
	_rm.main_objective = 7
	_rm.on_door_locked()
	_rm.main_objective = 8
	_rm.get_current_objective()
	await _frames(3)
	_check("#2 the Day 1 Peeker is at the landing window (door locked before the objective)",
		pm._last_peeker_window_id == "Landing_Window", pm._last_peeker_window_id)
	pm.remove_active_peeker()
	_rm.main_objective = 99
	_rm.day2_step = 6
	_rm.on_door_locked()
	await _frames(2)
	_check("#2 the Day 2 door-lock Peeker is at the hall window", pm._last_peeker_window_id == "Hall_Window_Right",
		pm._last_peeker_window_id)
	pm.remove_active_peeker()


func _test_wake() -> void:
	var nm: Node = root.get_node("NightManager")
	var ec: Node = get_first_node_in_group("environment_controller")
	# GameTime held still, or its next tick sends the real clock in between.
	var gt: Node = root.get_node("GameTime")
	gt.set_process(false)
	ec._on_game_time_changed(0.8, true)
	ec._on_game_time_changed(nm.WAKE_PROGRESS)
	await _frames(1)
	_check("#3 waking: a little after dawn (%.2f), shown at once (sky at %.2f)" % [nm.WAKE_PROGRESS, ec.cycle_progress],
		nm.WAKE_PROGRESS > 0.0 and nm.WAKE_PROGRESS < 0.08 and is_equal_approx(ec.cycle_progress, nm.WAKE_PROGRESS))
	gt.set_process(true)
	ec._on_game_time_changed(gt.cycle_progress, true)


func _f3(hud: Node) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F3
	event.pressed = true
	hud._unhandled_input(event)


func _test_hud() -> void:
	var hud: Node = get_first_node_in_group("hud")
	var debug: Array = [hud.time_label, hud.clock_label, hud.phase_bar, hud.fuel_bar]
	var hidden: bool = debug.all(func(c): return not c.visible)
	_f3(hud)
	await _frames(1)
	var shown: bool = debug.all(func(c): return c.visible) and hud._room_label != null and hud._room_label.visible
	_f3(hud)
	_check("#4 clock, time left, phase bar, room and generator: only with F3", hidden and shown)
	var player: Node = get_first_node_in_group("player")
	var flashlight: Node = hud._flashlight
	flashlight.is_on = false
	await _frames(2)
	var off_hidden: bool = not hud.battery_bar.visible
	flashlight.is_on = true
	await _frames(2)
	var on_shown: bool = hud.battery_bar.visible
	flashlight.is_on = false
	await _frames(1)
	hud._on_stamina_changed(100.0)
	var stamina_hidden: bool = hud.stamina_bar.modulate.a == 0.0
	hud._on_stamina_changed(60.0)
	var stamina_shown: bool = hud.stamina_bar.modulate.a > 0.0
	hud._on_stamina_changed(100.0)
	_check("#4 the battery shows only with the flashlight on; stamina only while used",
		off_hidden and on_shown and stamina_hidden and stamina_shown)


func _show(id: String) -> void:
	get_first_node_in_group("hud").hide_hint()
	_tm._visible_id = ""
	_rm._learned_mechanics.erase(id)
	_tm._shown.erase(id)
	_tm.trigger(id, true)
	await _frames(40)


func _test_nest_hints() -> void:
	var hud: Node = get_first_node_in_group("hud")
	var player := get_first_node_in_group("player") as CharacterBody3D
	await _show("stealth")
	var before: String = hud.current_hint()
	var ctrl := InputEventKey.new()
	ctrl.keycode = KEY_CTRL
	ctrl.physical_keycode = KEY_CTRL
	ctrl.pressed = true
	Input.parse_input_event(ctrl)
	await _frames(3)
	ctrl.pressed = false
	Input.parse_input_event(ctrl)
	await _frames(100)
	_check("#5 'Hold [CTRL] to crouch' goes once the player crouches", "crouch" in before and hud.current_hint() == "",
		"'%s' -> '%s'" % [before, hud.current_hint()])
	player.velocity = Vector3.ZERO
	await _show("stillness")
	before = hud.current_hint()
	await _frames(120)
	_check("#5 'Stand completely still' goes after standing still a moment (and is up long enough to read)",
		"still" in before and hud.current_hint() == "", "'%s' -> '%s'" % [before, hud.current_hint()])


func _test_clouds() -> void:
	var ec: Node = get_first_node_in_group("environment_controller")
	ec.weather = 1.0
	ec._apply_cycle()
	var cover: float = (ec._sky_material as ShaderMaterial).get_shader_parameter("cloud_cover")
	ec.weather = 0.0
	ec._apply_cycle()
	var clear: float = (ec._sky_material as ShaderMaterial).get_shader_parameter("cloud_cover")
	_check("#6 rain brings clouds (cover %.1f in the storm, %.1f clear)" % [cover, clear], cover > 0.9 and clear < 0.05)


func _test_van_thought() -> void:
	var monologue: Node = root.get_node("Monologue")
	_rm.van_inspected = false
	_rm.on_van_inspected()
	_check("#8 inspecting the car on Day 3: 'The car's wrecked...'", monologue.has_thought("van_wrecked"))
	monologue._clear()


func _test_porch() -> void:
	var entity: Node = get_first_node_in_group("entity")
	var player := get_first_node_in_group("player") as Node3D
	var porch: Node3D = null
	for light in get_nodes_in_group("CabinLights"):
		if light.get("is_faulty") == true:
			porch = light
	# Stand in the porch light's pool, just outside the door.
	var spot := porch.find_children("*", "SpotLight3D", true, false)[0] as SpotLight3D
	var outward := -spot.global_transform.basis.z
	outward.y = 0.0
	outward = outward.normalized()
	var porch_ground := Vector3(porch.global_position.x, player.global_position.y, porch.global_position.z) + outward * 2.2
	player.global_position = porch_ground
	player.velocity = Vector3.ZERO
	var nm: Node = root.get_node("NightManager")
	nm.current_night = 2
	nm.is_night_active = true
	nm.is_van_sequence_active = true
	entity.start_van_chase(porch_ground + outward * 20.0)
	var closest := INF
	for i in 600:
		await physics_frame
		player.global_position = porch_ground
		var flat: Vector3 = entity.global_position - porch_ground
		flat.y = 0.0
		closest = minf(closest, flat.length())
	_check("#7 Night 2.2: the chase stops at the edge of the porch light (closest %.1f m from it)" % closest,
		closest > 5.5 and entity.van_chase_active, entity.get_state_name())
	entity.end_van_chase()
