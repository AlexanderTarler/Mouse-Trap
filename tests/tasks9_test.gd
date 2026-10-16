extends SceneTree
## planning/tasks.txt round 4 (planning/tasks_plan.txt):
##   16 Night 3+ is darker: the ground fog glows less (the fog colour the
##      scene overrode is gone)
##   15 save states: the snapshot also keeps the notebook, the thoughts had,
##      the knockable props and the night; "Play Again" after an ending
##      reloads the scene and puts it back to the last checkpoint
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/tasks9_test.gd

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
	print("[TASKS9 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(60)
	_player = get_first_node_in_group("player")

	await _test_fog()
	await _test_snapshot()
	await _test_play_again()

	print("[TASKS9 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	current_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _test_fog() -> void:
	var ec: Node = get_first_node_in_group("environment_controller")
	var nm: Node = root.get_node("NightManager")
	var gt: Node = root.get_node("GameTime")
	var material: FogMaterial = ec.ground_fog.material
	gt.is_time_paused = true
	nm.is_time_paused = true
	gt.cycle_progress = 0.75
	gt._elapsed = 0.75 * gt.cycle_duration
	ec._on_game_time_changed(0.75, true)
	# (Setting the night puts the clock at 00:00, when the fog is only just
	# coming in: mid-night again after each.)
	var mid_night := func() -> void:
		gt.cycle_progress = 0.75
		gt._elapsed = 0.75 * gt.cycle_duration
		ec._on_game_time_changed(0.75, true)
	nm.current_night = 2
	await _frames(10)
	mid_night.call()
	await _frames(2)
	var night2: Color = material.emission
	nm.current_night = 3
	await _frames(10)
	mid_night.call()
	await _frames(2)
	var night3: Color = material.emission
	_check("16: no override of the night fog colour (the script's dark one is used)",
		ec.night_fog_color.is_equal_approx(Color(0.02, 0.02, 0.04)), str(ec.night_fog_color))
	_check("16: the ground fog glows less from Night 3 (%.2f, Nights 1-2 %.2f)" % [night3.r, night2.r],
		night3.is_equal_approx(ec.night3_ground_fog_emission) and night3.r < night2.r * 0.8)
	nm.current_night = 0
	gt.cycle_progress = 0.3
	gt._elapsed = 0.3 * gt.cycle_duration
	ec._on_game_time_changed(0.3, true)
	await _frames(5)


func _test_snapshot() -> void:
	var checkpoint: Node = root.get_node("Checkpoint")
	var monologue: Node = root.get_node("Monologue")
	var notebook: Node = get_first_node_in_group("notebook_ui")
	var prop: RigidBody3D = get_first_node_in_group("knockable")
	var prop_at := prop.global_position
	checkpoint.capture("day")
	notebook.add_documentation("Nest Alpha")
	monologue.think("A thought after the checkpoint.", null, 1.0, "t9_after")
	prop.global_position += Vector3(0.6, 0.0, 0.0)
	await _frames(2)
	checkpoint.restore()
	await _frames(2)
	_check("15: the notebook's pages go back (a nest documented after it is undocumented)",
		not notebook._unlocked_nests.has("Nest Alpha"))
	_check("15: thoughts had after the checkpoint come again", not monologue.has_thought("t9_after"))
	_check("15: knockable props are back where they stood (%.2f m off)" % prop.global_position.distance_to(prop_at),
		prop.global_position.distance_to(prop_at) < 0.05)


func _test_play_again() -> void:
	var checkpoint: Node = root.get_node("Checkpoint")
	var nm: Node = root.get_node("NightManager")
	var inventory: Node = root.get_node("Inventory")
	var rm: Node = root.get_node("RoutineManager")
	var door: Node = get_first_node_in_group("Door")
	# A day well into the game: Day 3, with things in the pack.
	nm.current_night = 2
	nm.is_night_active = false
	nm.is_day_active = true
	inventory.add_item(load("res://resources/battery_resource.tres"))
	nm.generator_fuel = 42.0
	door.set_state_quietly(false, false)
	checkpoint.capture("day")
	var items: int = inventory.get_item_count()
	var objective: int = rm.main_objective
	# Then the rest of the game, up to an ending.
	nm.current_night = 4
	inventory.add_item(load("res://resources/plank_resource.tres"))
	inventory.add_item(load("res://resources/plank_resource.tres"))
	nm.generator_fuel = 3.0
	door.set_state_quietly(false, true)
	rm.main_objective = objective + 5
	# The ending screen's Play Again.
	var screen: Node = load("res://scenes/ui/ending_screen.tscn").instantiate() if ResourceLoader.exists("res://scenes/ui/ending_screen.tscn") else null
	if screen:
		root.add_child(screen)
		await _frames(2)
		screen._on_retry_pressed()
	else:
		nm.reload_from_checkpoint()
		change_scene_to_file("res://scenes/cottage_horror.tscn")
	for i in 240:
		await physics_frame
		if current_scene and current_scene != _scene and not checkpoint.restore_on_load and nm._spawn_setup_done:
			break
	await _frames(30)
	var fresh := current_scene
	door = get_first_node_in_group("Door")
	_check("15: Play Again reloads the scene and restores it (no new game, no pending restore)",
		fresh != null and fresh != _scene and not checkpoint.restore_on_load, str(fresh))
	_check("15: back to the checkpoint's day (night %d) and story (objective %d)" % [nm.current_night, rm.main_objective],
		nm.current_night == 2 and rm.main_objective == objective and nm.is_day_active)
	_check("15: the inventory as it was then (%d items), the fuel (%.0f), the door unlocked" % [inventory.get_item_count(), nm.generator_fuel],
		inventory.get_item_count() == items and is_equal_approx(nm.generator_fuel, 42.0) and door != null and not door.is_locked)
	if is_instance_valid(screen):
		screen.queue_free()
