extends SceneTree
## Continue (SaveGame): a Day 1 save picks up outside the cabin, facing it
## (the cabin isn't open yet at Day 1's checkpoint); a later day's inside.
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
	# Day 1.
	var at := await _continue_from(0)
	var player := get_first_node_in_group("player") as Node3D
	var nm: Node = root.get_node("NightManager")
	var facing := -player.global_basis.z
	var to_cabin: Vector3 = Vector3(9.0, 0.0, 10.0) - player.global_position
	_check("Day 1: Continue picks up outside the cabin, facing it (%s)" % at,
		at.distance_to(nm.OUTSIDE_CABIN) < 1.5 and at.y < 2.0 and facing.dot(Vector3(to_cabin.x, 0, to_cabin.z).normalized()) > 0.7)
	# A later day: inside, as before.
	at = await _continue_from(2)
	var inside: Vector3 = current_scene.get_node("PlayerSpawnpoints/PlayerSpawnDev").global_position
	_check("a later day: inside the cabin, as before (%s)" % at, at.distance_to(inside) < 1.5)

	print("[CONTINUE TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	SaveGame.delete()
	current_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


## A game saved at the start of a day (`night`: NightManager's current_night),
## then continued as from the main menu. Where the player stands after.
func _continue_from(night: int) -> Vector3:
	change_scene_to_file(LEVEL)
	await _frames(90)
	var nm: Node = root.get_node("NightManager")
	var checkpoint: Node = root.get_node("Checkpoint")
	nm.current_night = night
	nm.is_night_active = false
	nm.is_day_active = true
	checkpoint.save_to_disk = true
	checkpoint.capture("day")
	checkpoint.save_to_disk = false
	# Continue: as the main menu does it.
	root.get_node("GameReset").new_game()
	SaveGame.read_into(checkpoint)
	change_scene_to_file(LEVEL)
	for i in 300:
		await _frames(1)
		if nm._spawn_setup_done and not checkpoint.restore_on_load and i > 30:
			break
	await _frames(10)
	return (get_first_node_in_group("player") as Node3D).global_position
