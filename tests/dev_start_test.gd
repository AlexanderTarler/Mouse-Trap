extends SceneTree
## Dev starts (planning/tasks.txt 3): the Player's `dev_start` starts the game
## at a point of the story, the story up to it played through (DevStart).
## Each start: the objective, the day or night, and what the player has are
## as if it had been played. The opening doesn't play; the black screen
## lifts once it's there.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/dev_start_test.gd
##   (-- <start number> ... plays only those)

var _failures := 0
var _scene: Node
var _nm: Node
var _rm: Node


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[DEV START TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	await _frames(2)
	_nm = root.get_node("NightManager")
	_rm = root.get_node("RoutineManager")
	var only: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.is_valid_int():
			only.append(int(arg))
	for start in range(1, DevStart.NAMES.size()):
		if only.is_empty() or start in only:
			await _play(start)
	print("[DEV START TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	Engine.time_scale = 1.0
	paused = false
	if _scene:
		_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _play(start: int) -> void:
	if _scene:
		_scene.queue_free()
		await _frames(3)
	root.get_node("GameReset").new_game()
	paused = false
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	var player := _scene.get_node("Player")
	player.start_in_dev_mode = false
	player.dev_start = start
	root.add_child(_scene)
	current_scene = _scene
	var began := Time.get_ticks_msec()
	var runner: Node = null
	for i in 60:
		await _frames(1)
		runner = _nm.dev_start_runner
		if runner:
			break
	var covered: bool = runner != null and runner.get_child(0) is ColorRect
	while _nm.dev_start_runner != null and Time.get_ticks_msec() - began < 240000:
		await _frames(10)
	await _frames(40)
	var name: String = DevStart.NAMES[start]
	var seconds := (Time.get_ticks_msec() - began) / 1000.0
	var failed: String = runner.failed_step if is_instance_valid(runner) else ""
	_check("%s: played through behind a black screen (%.0f s)" % [name, seconds],
		covered and _nm.dev_start_runner == null and failed == "" and Engine.time_scale == 1.0,
		"stopped at \"%s\", objective \"%s\"" % [failed, _rm.get_current_objective()] if failed != "" else "")
	_check("%s: the black screen is gone, no opening" % name,
		_scene.find_child("DevStart", false, false) == null and _scene.find_child("Opening", false, false) == null)
	var objective: String = _rm.get_current_objective()
	var gt: Node = root.get_node("GameTime")
	var inventory: Node = root.get_node("Inventory")
	var has := func(item_name: String) -> bool:
		return inventory.items.any(func(i): return i != null and i.item_name == item_name)
	var van: Node = _scene.find_child("EscapeVan", true, false)
	var entity: Node = get_first_node_in_group("entity")
	var ok := false
	var detail := "objective \"%s\", night %d, %s" % [objective, _nm.current_night, "night" if _nm.is_night_active else "day"]
	match start:
		DevStart.Start.DAY_1:
			ok = objective.begins_with("Go to the cabin") and _nm.current_night == 0 and not has.call("Cabin Key")
		DevStart.Start.DAY_1_POWER:
			ok = objective.begins_with("Find 3 planks") and _nm.is_generator_on and has.call("Cabin Key") \
				and _rm.phase2_gen_turned_on and _nm.current_night == 0
		DevStart.Start.DAY_2:
			ok = objective.begins_with("Read the previous nest reports") and _nm.current_night == 1 and gt.is_day
		DevStart.Start.DAY_2_NESTS:
			ok = objective.begins_with("Log the collected nest data") and _nm.current_night == 1
		DevStart.Start.NIGHT_2:
			ok = (objective.begins_with("Lock the door") or objective.begins_with("Go to bed")) and _nm.is_night_active
		DevStart.Start.NIGHT_2_2:
			ok = objective.begins_with("Investigate the car alarm") and van.alarm_active and _nm.current_night == 2
		DevStart.Start.DAY_3:
			ok = _nm.current_night == 3 and gt.is_day and player.get("is_exhausted")
		DevStart.Start.DAY_3_RESTED:
			ok = objective.begins_with("Find parts to repair the van") and _nm.current_night == 3 and not player.get("is_exhausted")
		DevStart.Start.NIGHT_3:
			ok = _nm.current_night == 3 and _nm.is_night_active and not van.is_repaired
		DevStart.Start.NIGHT_3_REPAIRED:
			ok = van.is_repaired and objective.begins_with("Start the van") and _nm.is_night_active
	_check("%s: the story is there" % name, ok, detail)
	_check("%s: the Entity can kill again, the player can move" % name,
		entity.can_kill and player.is_processing_input() and player.is_physics_processing())
