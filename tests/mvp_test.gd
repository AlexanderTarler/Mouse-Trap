extends SceneTree
## planning/mvp_review.txt: the fixes before upload.
##   - losing the window (focus) during play opens the pause menu; not with
##     a screen open that frees the mouse
##   - the movement hint goes after a while of moving, crouched or not
##   - Continue, Credits and Producer Mode press only themselves
##   - an ending clears the save (a game started from the menu)
##   - a save from another version of the game isn't restored
##   - the windows' kept glass is freed with the level (no nodes left over)
##   - Credits opens and closes
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/mvp_test.gd

var _failures := 0
var _scene: Node


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[MVP TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	SaveGame.path = "user://mvp_test_save.dat"
	SaveGame.delete()
	await _frames(2)
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(120)
	await _test_focus()
	await _test_movement_hint()
	await _test_menu_buttons()
	_test_save_version()
	await _test_ending_clears_save()
	# The level unloaded: nothing left over.
	var orphans_before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	_scene.queue_free()
	await _frames(5)
	var orphans_after := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	_check("the level unloaded leaves no nodes behind (the windows' kept glass freed)", orphans_after <= orphans_before, "%d -> %d" % [orphans_before, orphans_after])
	print("[MVP TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	SaveGame.delete()
	quit(1 if _failures > 0 else 0)


func _test_focus() -> void:
	var pause: Node = _scene.find_child("PauseMenu", true, false)
	var notebook := get_first_node_in_group("notebook_ui")
	notebook._toggle()
	pause._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var not_over_notebook: bool = not pause._is_open
	notebook._toggle()
	pause._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var opened: bool = pause._is_open
	pause._resume()
	await _frames(2)
	_check("leaving the window during play pauses the game (not with the notebook open)", not_over_notebook and opened)


func _test_movement_hint() -> void:
	var player := get_first_node_in_group("player")
	var tm: Node = root.get_node("TutorialManager")
	root.get_node("RoutineManager")._learned_mechanics.erase("movement")
	player._enable_movement_tutorial()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.keycode = KEY_W
	key.pressed = true
	player._input(key)
	var early: bool = not tm.is_learned("movement")
	await _frames(int(60 * (player.MOVEMENT_HINT_TIME + 1.0)))
	_check("the movement hint goes %d s after moving, without crouching" % int(player.MOVEMENT_HINT_TIME), early and tm.is_learned("movement"))


func _test_menu_buttons() -> void:
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	_scene.add_child(menu)
	await _frames(2)
	var counts := []
	for button_name in ["ContinueButton", "CreditsButton", "ProducerButton"]:
		var button: Button = menu.find_child(button_name, true, false)
		counts.append(button.pressed.get_connections().filter(func(c): return c.callable.get_method() != "_play_click").size() if button else -1)
	menu._on_credits_pressed()
	var credits: Node = menu.get_node_or_null("Credits")
	var shown: bool = credits != null and "Thank you for playing" in (credits.find_child("CreditsText", true, false) as RichTextLabel).text
	(credits.find_child("BackButton", true, false) as Button).pressed.emit()
	await _frames(2)
	_check("Continue, Credits and Producer Mode press only themselves (%s); Credits opens and closes" % str(counts),
		counts == [1, 1, 1] and shown and menu.get_node_or_null("Credits") == null)
	menu.queue_free()
	await _frames(1)


func _test_save_version() -> void:
	var checkpoint: Node = root.get_node("Checkpoint")
	checkpoint.save_to_disk = true
	checkpoint.capture("day")
	checkpoint.save_to_disk = false
	var readable := SaveGame.describe() != ""
	# Rewritten as if by another version of the game.
	var file := FileAccess.open(SaveGame.path, FileAccess.READ)
	var data: Dictionary = file.get_var()
	file.close()
	data["game_version"] = "0.0.1"
	file = FileAccess.open(SaveGame.path, FileAccess.WRITE)
	file.store_var(data)
	file.close()
	_check("a save from another version of the game isn't offered or restored (this one: v%s)" % SaveGame.game_version(),
		readable and SaveGame.describe() == "" and not SaveGame.read_into(checkpoint) and SaveGame.game_version() != "")


func _test_ending_clears_save() -> void:
	var checkpoint: Node = root.get_node("Checkpoint")
	checkpoint.save_to_disk = true
	checkpoint.capture("day")
	var saved := SaveGame.exists()
	var screen: Node = load("res://scenes/ui/ending_screen.tscn").instantiate() if ResourceLoader.exists("res://scenes/ui/ending_screen.tscn") else null
	if screen:
		_scene.add_child(screen)
		screen.setup_ending(1)
	checkpoint.save_to_disk = false
	_check("an ending clears the save (Continue no longer offers the last night)", screen != null and saved and not SaveGame.exists())
	if screen:
		screen.queue_free()
	await _frames(2)
