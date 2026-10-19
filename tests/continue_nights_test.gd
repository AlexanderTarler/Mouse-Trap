extends SceneTree
## Continue (SaveGame) from a night: the night's snapshot on disk, the game
## quit to the main menu, Continue. Each night is reached by playing the
## story through to it (DevStart), saving on, as a game from the menu.
##   - Night 2: back at the start of Night 2: a night, the story as the
##     snapshot had it (a night restarts from its start, as a death does), no
##     Day 1 hint (the watch's may come: it's taught at nightfall until used)
##   - Night 2.2: back at the car alarm going off (not the start of the
##     night), by the van
##   - Night 3: back at the start of the last night, as Night 3
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/continue_nights_test.gd

const LEVEL := "res://scenes/cottage_horror.tscn"

var _failures := 0


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[CONTINUE NIGHTS TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	SaveGame.path = "user://continue_nights_test_save.dat"
	SaveGame.delete()
	await _frames(2)
	var nm: Node = root.get_node("NightManager")
	var rm: Node = root.get_node("RoutineManager")
	var tm: Node = root.get_node("TutorialManager")

	# Night 2.
	var before := await _play_to(DevStart.Start.NIGHT_2)
	var after := await _continue()
	_check("Night 2: saved ('%s'); Continue: %s, '%s' (was '%s'), hint '%s'" % [before.said, after.day, after.objective, before.objective, tm.visible_hint()],
		before.said == "Night 2" and after.day == "Night 2" and after.night_active and after.main == before.saved_main
		and tm.visible_hint() != "movement")

	# Night 2.2: the car alarm.
	before = await _play_to(DevStart.Start.NIGHT_2_2)
	after = await _continue()
	var van := current_scene.find_child("EscapeVan", true, false) as Node3D
	var player := get_first_node_in_group("player") as Node3D
	var by_van: float = player.global_position.distance_to(van.get_restart_transform().origin) if van and van.has_method("get_restart_transform") else 999.0
	_check("Night 2.2: saved at the car alarm ('%s', tag '%s'); Continue: back at it (%s, van sequence %s, %.1f m from the van's spot), '%s' (was '%s')" % [before.said, before.tag, after.day, nm.is_van_sequence_active, by_van, after.objective, before.objective],
		before.tag == "van_alarm" and nm.is_van_sequence_active and by_van < 3.5 and after.main == before.saved_main)

	# Night 3.
	before = await _play_to(DevStart.Start.NIGHT_3)
	after = await _continue()
	_check("Night 3: saved ('%s'); Continue: %s, '%s' (was '%s'), hint '%s'" % [before.said, after.day, after.objective, before.objective, tm.visible_hint()],
		before.said == "Night 3" and after.day == "Night 3" and after.night_active and nm.current_night == 3
		and after.main == before.saved_main and tm.visible_hint() != "movement")

	print("[CONTINUE NIGHTS TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	SaveGame.delete()
	current_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


## A new game from the menu, the story played to `start`, saving on: what
## the save says and the game's state then.
func _play_to(start: int) -> Dictionary:
	if current_scene:
		current_scene.queue_free()
		await _frames(3)
	root.get_node("GameReset").new_game()
	SaveGame.delete()
	var checkpoint: Node = root.get_node("Checkpoint")
	checkpoint.save_to_disk = true
	var scene: Node = load(LEVEL).instantiate()
	scene.get_node("Player").dev_start = start
	root.add_child(scene)
	current_scene = scene
	var nm: Node = root.get_node("NightManager")
	var began := Time.get_ticks_msec()
	await _frames(60)
	while nm.dev_start_runner != null and Time.get_ticks_msec() - began < 240000:
		await _frames(10)
	await _frames(60)
	var state := _state()
	state["said"] = SaveGame.describe()
	state["tag"] = checkpoint.tag
	# The story as the snapshot has it (a night restarts from its start: what
	# was done since, like Night 2's upload in the dev start, is undone).
	state["saved_main"] = int(SaveGame._read().get("states", {}).get("/root/RoutineManager", {}).get("main_objective", -1))
	return state


## Back to the main menu, Continue: the game's state after.
func _continue() -> Dictionary:
	var nm: Node = root.get_node("NightManager")
	var checkpoint: Node = root.get_node("Checkpoint")
	current_scene.queue_free()
	await _frames(3)
	root.get_node("GameReset").new_game()
	SaveGame.read_into(checkpoint)
	checkpoint.save_to_disk = true
	change_scene_to_file(LEVEL)
	for i in 400:
		await _frames(1)
		if nm._spawn_setup_done and not checkpoint.restore_on_load and i > 30:
			break
	await _frames(90)
	return _state()


func _state() -> Dictionary:
	var nm: Node = root.get_node("NightManager")
	var rm: Node = root.get_node("RoutineManager")
	return {
		"day": rm.get_current_day_string(),
		"night_active": nm.is_night_active,
		"objective": rm.get_current_objective(),
		"main": int(rm.main_objective),
	}
