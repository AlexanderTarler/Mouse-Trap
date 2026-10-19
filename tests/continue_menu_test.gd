extends SceneTree
## Continue the way a player does it: a game from the main menu played into
## Day 2, the pause menu's Main Menu, the main menu's Continue button. What
## comes back: Day 2's story (not Day 1's "Go to the cabin."), and the HUD
## saying so (its day card and objective, not the ones from before the load).
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/continue_menu_test.gd

const LEVEL := "res://scenes/cottage_horror.tscn"
const MENU := "res://scenes/ui/main_menu.tscn"

var _failures := 0


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("[CONTINUE MENU TEST] %s  %s" % ["PASS" if ok else "FAIL", label])


func _run() -> void:
	SaveGame.path = "user://continue_menu_test_save.dat"
	SaveGame.delete()
	await _frames(2)
	var nm: Node = root.get_node("NightManager")
	var rm: Node = root.get_node("RoutineManager")
	var checkpoint: Node = root.get_node("Checkpoint")

	for route in ["dawn", "bed"]:
		# A new game, from the menu.
		root.get_node("GameReset").new_game()
		SaveGame.delete()
		checkpoint.save_to_disk = true
		change_scene_to_file(LEVEL)
		await _frames(150)
		rm.phase1_entered_cabin = true
		root.get_node("TutorialManager").mark_learned("movement")
		if route == "dawn":
			nm.current_night = 1
			nm.is_night_active = true
			nm.is_day_active = false
			nm.end_current_night()
			rm.on_day2_started()   # (as dawn does after it)
		else:
			nm.advance_night()
		await _frames(60)
		var objective_then: String = rm.get_current_objective()
		var day_then: String = rm.get_current_day_string()

		# The pause menu's Main Menu.
		paused = false
		change_scene_to_file(MENU)
		await _frames(30)
		var menu := current_scene as MainMenu
		# Continue.
		menu._on_continue_pressed()
		var began := Time.get_ticks_msec()
		while (current_scene == menu or not nm._spawn_setup_done or checkpoint.restore_on_load) and Time.get_ticks_msec() - began < 60000:
			await _frames(5)
		await _frames(120)
		var hud := current_scene.get_node_or_null("HUD")
		var hud_objective: String = hud.objective_label.text if hud else "?"
		var hud_day: String = hud.night_label.text if hud else "?"
		print("[CONTINUE MENU TEST] %s: before '%s' / '%s'; after '%s' / '%s', HUD '%s' / '%s'" % [route, day_then, objective_then, rm.get_current_day_string(), rm.get_current_objective(), hud_day, hud_objective])
		_check("%s: the story is Day 2's again" % route, rm.get_current_objective() == objective_then and not objective_then.begins_with("Go to the cabin") and rm.get_current_day_string() == day_then)
		_check("%s: the HUD says so" % route, hud_objective == objective_then and hud_day == day_then)

	# Left mid-day (the pause menu's Main Menu): Continue picks up right there:
	# the spot, the way the player faced, the time, the day's progress.
	var player := get_first_node_in_group("player") as CharacterBody3D
	var gt: Node = root.get_node("GameTime")
	var spot := Vector3(14.0, 0.0, 22.0)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 20.0, spot + Vector3.DOWN * 20.0, 1, [player.get_rid()]))
	if not hit.is_empty():
		spot.y = (hit.position as Vector3).y + 0.9
	player.reset_camera()
	player.global_transform = Transform3D(Basis(Vector3.UP, 1.2), spot)
	await _frames(60)
	var stood := player.global_position
	var yaw_then := player.global_rotation.y
	gt.cycle_progress = 0.21
	gt._elapsed = gt.cycle_progress * gt.cycle_duration
	rm.day2_step = 2
	var objective_left: String = rm.get_current_objective()
	var heaps_then := _heap_contents()
	await _frames(2)
	current_scene.get_node("PauseMenu")._on_main_menu_pressed()
	await _frames(30)
	var said := SaveGame.describe()
	var menu2 := current_scene as MainMenu
	menu2._on_continue_pressed()
	var began2 := Time.get_ticks_msec()
	while (current_scene == menu2 or not nm._spawn_setup_done or checkpoint.restore_on_load) and Time.get_ticks_msec() - began2 < 60000:
		await _frames(5)
	await _frames(60)
	player = get_first_node_in_group("player") as CharacterBody3D
	var hud2 := current_scene.get_node_or_null("HUD")
	print("[CONTINUE MENU TEST] left at %s (yaw %.2f, time %.2f, '%s'); back at %s (yaw %.2f, time %.2f, '%s', HUD '%s'), menu said '%s'" % [stood, yaw_then, 0.21, objective_left, player.global_position, player.global_rotation.y, gt.cycle_progress, rm.get_current_objective(), hud2.objective_label.text if hud2 else "?", said])
	_check("left mid-day: Continue picks up where the player stood, facing the same way", player.global_position.distance_to(stood) < 1.0 and absf(angle_difference(player.global_rotation.y, yaw_then)) < 0.1)
	_check("left mid-day: the time and the day's progress kept", absf(gt.cycle_progress - 0.21) < 0.02 and rm.day2_step == 2 and rm.get_current_objective() == objective_left and hud2 and hud2.objective_label.text == objective_left and said == "Day 2")

	var heaps_now := _heap_contents()
	print("[CONTINUE MENU TEST] scrap heaps: %s -> %s" % [heaps_then, heaps_now])
	_check("the scrap heaps hold the same items (not nulls)", heaps_then == heaps_now and not "<null>" in heaps_now and heaps_now.length() > 10)

	print("[CONTINUE MENU TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	SaveGame.delete()
	current_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


## Every scrap heap's contents, as names and counts.
func _heap_contents() -> String:
	var out: PackedStringArray = []
	for node in current_scene.find_children("ScrapHeap*", "", true, false):
		if not "contents" in node:
			continue
		for entry in node.contents:
			var item = entry.get("item_data")
			out.append("%s x%d" % [item.item_name if item else "<null>", entry.get("quantity", 0)])
	return ", ".join(out)
