extends SceneTree
## Continue (SaveGame), from the main menu after quitting:
##   - Day 1 (the game's start, the cabin not yet entered): outside it,
##     facing it
##   - Day 2 reached by going to bed on Day 1: that morning is saved (it
##     wasn't: Continue went back to the start of the game), and restored:
##     the night, the objective, inside, no leftover hint
##   - Day 2 reached by surviving Night 1 to dawn: the same
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/continue_test.gd

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
	print("[CONTINUE TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	SaveGame.path = "user://continue_test_save.dat"
	SaveGame.delete()
	await _frames(2)
	var nm: Node = root.get_node("NightManager")
	var rm: Node = root.get_node("RoutineManager")
	var tm: Node = root.get_node("TutorialManager")

	# Day 1: the start of the game.
	await _new_level()
	_save_now()
	var at := await _continue()
	var player := get_first_node_in_group("player") as Node3D
	var facing := -player.global_basis.z
	var to_cabin: Vector3 = Vector3(9.0, 0.0, 10.0) - player.global_position
	_check("Day 1: Continue picks up outside the cabin, facing it (%s)" % at,
		at.distance_to(nm.OUTSIDE_CABIN) < 1.5 and at.y < 2.0 and facing.dot(Vector3(to_cabin.x, 0, to_cabin.z).normalized()) > 0.7)

	# Day 2, by going to bed on Day 1 (advance_night from Day 1).
	await _new_level()
	_into_the_cabin()
	nm.advance_night()
	await _frames(30)
	var said := SaveGame.describe()
	var objective_then: String = rm.get_current_objective()
	at = await _continue()
	var inside: Vector3 = current_scene.get_node("PlayerSpawnpoints/PlayerSpawnDev").global_position
	_check("Day 2 (to bed on Day 1): saved that morning ('%s') and Continue restores it: night %d, '%s', inside, no leftover hint ('%s')" % [said, nm.current_night, rm.get_current_objective(), tm.visible_hint()],
		said == "Day 2" and rm.get_current_day_string() == "Day 2" and nm.current_night == 1 and nm.is_day_active and rm.get_current_objective() == objective_then and not rm.get_current_objective().begins_with("Go to the cabin")
		and at.distance_to(inside) < 1.5 and tm.visible_hint() != "movement")

	# Day 2, by surviving Night 1 to dawn.
	await _new_level()
	_into_the_cabin()
	nm.current_night = 1
	nm.is_night_active = true
	nm.is_day_active = false
	nm.end_current_night()
	await _frames(30)
	said = SaveGame.describe()
	at = await _continue()
	_check("Day 2 (through Night 1): saved ('%s') and Continue restores it: night %d, inside, no leftover hint ('%s')" % [said, nm.current_night, tm.visible_hint()],
		said == "Day 2" and nm.current_night == 2 and nm.is_day_active and at.distance_to(inside) < 1.5 and tm.visible_hint() != "movement")

	print("[CONTINUE TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	SaveGame.delete()
	current_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


## A new game (as from the main menu), saving on.
func _new_level() -> void:
	root.get_node("GameReset").new_game()
	root.get_node("Checkpoint").save_to_disk = true
	change_scene_to_file(LEVEL)
	await _frames(120)


## As the story has it by Day 2: the cabin entered, the moving taught.
func _into_the_cabin() -> void:
	var rm: Node = root.get_node("RoutineManager")
	rm.phase1_entered_cabin = true
	root.get_node("TutorialManager").mark_learned("movement")


func _save_now() -> void:
	root.get_node("Checkpoint").capture("day")


## Back to the main menu, Continue: where the player stands after.
func _continue() -> Vector3:
	var nm: Node = root.get_node("NightManager")
	var checkpoint: Node = root.get_node("Checkpoint")
	root.get_node("GameReset").new_game()
	SaveGame.read_into(checkpoint)
	checkpoint.save_to_disk = true
	change_scene_to_file(LEVEL)
	for i in 400:
		await _frames(1)
		if nm._spawn_setup_done and not checkpoint.restore_on_load and i > 30:
			break
	await _frames(60)
	return (get_first_node_in_group("player") as Node3D).global_position
