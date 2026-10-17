extends SceneTree
## planning/round9_plan.txt: menus and options.
##   A the options in tabs; volumes saved and applied (the Entity's bus
##     following Sound Effects); switches; the mic meter drawn; Objective
##     Highlights, Screen Shake and Caption Size settings; Reset to Defaults
##   B rebindable keys (GameKeys): the game reads actions, bound by physical
##     key; the Controls tab rebinds; Reset Keys
##   C the brightness screen
##   D graphics quality
##   E the pause menu shows the day or night and the objective (not the time)
##   F the main menu's backdrop: the cabin, a lit window, a visitor
##   G Continue: the checkpoint written to disk and read back
## The player's own settings file is put back as it was afterwards, and the
## save goes to a test file.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/round9_test.gd

var _failures := 0
var _scene: Node
var _player: CharacterBody3D
var _settings_backup := PackedByteArray()
var _had_settings := false


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[ROUND9 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	_had_settings = FileAccess.file_exists("user://settings.cfg")
	if _had_settings:
		_settings_backup = FileAccess.get_file_as_bytes("user://settings.cfg")
	SaveGame.path = "user://round9_test_save.dat"
	SaveGame.delete()
	await _frames(2)
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(120)
	_player = get_first_node_in_group("player")
	get_first_node_in_group("entity").can_kill = false

	await _test_options()
	await _test_keys()
	await _test_calibration()
	_test_quality()
	await _test_pause()
	await _test_backdrop()
	await _test_save()

	print("[ROUND9 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	SaveGame.delete()
	_scene.queue_free()
	await _frames(2)
	# The player's own settings back.
	if _had_settings:
		var file := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		file.store_buffer(_settings_backup)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	quit(1 if _failures > 0 else 0)


func _menu() -> Node:
	var menu: Node = load("res://scenes/ui/options_menu.tscn").instantiate()
	_scene.add_child(menu)
	menu.show_menu()
	return menu


func _test_options() -> void:
	var menu := _menu()
	await _frames(2)
	var tabs: TabContainer = menu.find_child("Tabs", true, false)
	var names := []
	for i in tabs.get_tab_count():
		names.append(tabs.get_tab_title(i))
	_check("A: four tabs: %s" % ", ".join(names), names == ["Audio", "Video", "Controls", "Accessibility"])
	# Volumes: saved, applied, the Entity's bus following Sound Effects.
	var sfx: HSlider = menu.find_child("SFXSlider", true, false)
	sfx.value = 0.4
	var echo: HSlider = menu.find_child("RoomEchoSlider", true, false)
	var bus_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	var entity_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Entity"))
	var config := ConfigFile.new()
	config.load("user://settings.cfg")
	_check("A: Sound Effects saved and applied; the Entity bus follows (%.1f / %.1f dB)" % [bus_db, entity_db],
		is_equal_approx(bus_db, linear_to_db(0.4)) and is_equal_approx(entity_db, linear_to_db(0.4 * GameSettings.ENTITY_OF_SFX))
		and is_equal_approx(float(config.get_value("audio", "sfx", 0.0)), 0.4) and echo != null
		and menu.find_child("PlayerVoiceSlider", true, false) == null)
	# Switches.
	var checks: Array = menu.find_children("*", "CheckButton", true, false)
	var check_boxes: Array = menu.find_children("*", "CheckBox", true, false).filter(func(c): return not c is CheckButton)
	_check("A: every toggle is a switch (%d), drawn" % checks.size(),
		checks.size() >= 6 and check_boxes.is_empty() and (checks[0] as CheckButton).has_theme_icon_override("checked"))
	var meter: ProgressBar = menu.find_child("MicMeter", true, false)
	_check("A: the mic meter has a fill drawn", meter != null and meter.has_theme_stylebox_override("fill"))
	# Objective highlights, screen shake, caption size.
	var routine: Node = root.get_node("RoutineManager")
	(menu.find_child("HighlightsCheck", true, false) as CheckButton).button_pressed = false
	var highlights_off: bool = not routine.enable_object_highlights
	(menu.find_child("ScreenShakeCheck", true, false) as CheckButton).button_pressed = false
	var shake_off := GameSettings.shake() == 0.0
	var caption_option: OptionButton = menu.find_child("CaptionSizeOption", true, false)
	caption_option.select(2)
	caption_option.item_selected.emit(2)
	var caption: Label = root.get_node("Captions").get_node("Caption")
	var large := caption.get_theme_font_size("font_size")
	_check("A: Objective Highlights, Screen Shake and Caption Size are settings that take effect",
		highlights_off and shake_off and large == 28, "caption %d" % large)
	# The stare's shake follows it.
	_player.look_timer = 1.4
	_player._camera.h_offset = 0.0
	await _frames(3)
	_check("A: with Screen Shake off, staring doesn't shake the camera", is_zero_approx(_player._camera.h_offset) and is_zero_approx(_player._camera.v_offset))
	_player.look_timer = 0.0
	# Reset to Defaults (twice: the first press asks).
	var reset: Button = menu.find_child("ResetButton", true, false)
	reset.pressed.emit()
	var asked: bool = not bool(GameSettings.get_value("video/screen_shake"))
	reset.pressed.emit()
	await _frames(2)
	_check("A: Reset to Defaults asks once, then puts everything back",
		asked and bool(GameSettings.get_value("video/screen_shake")) and is_equal_approx(float(GameSettings.get_value("audio/sfx")), 0.8)
		and routine.enable_object_highlights and int(GameSettings.get_value("accessibility/caption_size")) == 1)
	menu.queue_free()
	await _frames(1)


func _press(physical: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical
	event.pressed = pressed
	return event


func _test_keys() -> void:
	GameKeys.reset()
	var defaults: bool = GameKeys.key_of("move_forward") == KEY_W and GameKeys.label("move_forward") == "W" and GameKeys.key_of("watch") == KEY_T
	_check("B: the keys default by position (W for forward, T the watch)", defaults)
	# The game reads actions: rebind forward to I and walk.
	GameKeys.rebind("move_forward", KEY_I)
	_player.global_position = Vector3(6.0, 1.0, 17.0)
	_player.rotation.y = 0.0
	await _frames(5)
	var start := _player.global_position
	Input.parse_input_event(_press(KEY_I, true))
	await _frames(30)
	var held := Input.is_action_pressed("move_forward")
	Input.parse_input_event(_press(KEY_I, false))
	var moved := _player.global_position.distance_to(start)
	var w_still := InputMap.action_has_event("move_forward", _press(KEY_W, true))
	_check("B: forward rebound to I walks the player (%.2f m); W no longer does" % moved, held and moved > 0.2 and not w_still)
	# The flashlight on G.
	GameKeys.rebind("flashlight", KEY_G)
	_player._has_flashlight = true
	var light: Node = _player._flashlight
	var was_on: bool = light.is_on
	_player._input(_press(KEY_G, true))
	await _frames(2)
	_player._input(_press(KEY_G, false))
	await _frames(2)
	_check("B: the flashlight rebound to G toggles it", light.is_on != was_on)
	if light.is_on != was_on:
		_player._input(_press(KEY_G, true))
		await _frames(2)
		_player._input(_press(KEY_G, false))
	# Saved, and the Controls tab rebinds by clicking and pressing.
	var config := ConfigFile.new()
	config.load("user://settings.cfg")
	var saved: bool = int(config.get_value("keys", "flashlight", 0)) == KEY_G
	var menu := _menu()
	await _frames(2)
	menu._show_controls()
	var button: Button = menu.find_child("watchKey", true, false)
	button.pressed.emit()
	var asking: bool = button.text == "Press a key..."
	menu._input(_press(KEY_Y, true))
	_check("B: saved; in the Controls tab click a key, press the new one",
		saved and asking and GameKeys.key_of("watch") == KEY_Y and button.text == GameKeys.key_label(KEY_Y), button.text)
	# A key used twice is marked.
	GameKeys.rebind("watch", KEY_G)
	menu._refresh_keys()
	var note: Label = menu.find_child("KeyNote", true, false)
	_check("B: a key used twice is pointed out", GameKeys.clashes("watch") == ["flashlight"] and note.text != "", note.text)
	# Hints and prompts name the player's keys.
	GameKeys.rebind("ui_interact", KEY_G)
	var prompt := GameKeys.keys_in("[E] Open Door\n[Hold E] Lock Door · [Esc] Close")
	var page := GameKeys.keys_in("[E] Next · [Q] Prev", {"E": "notebook_next_page"})
	var unchanged := GameKeys.keys_in("Press [J] to open your field notebook.")
	_check("B: hints and prompts show a rebound key ('%s'); the others as written" % prompt.replace("\n", " / "),
		prompt == "[G] Open Door\n[Hold G] Lock Door · [Esc] Close" and page == "[E] Next · [Q] Prev" and unchanged == "Press [J] to open your field notebook.")
	(menu.find_child("ResetKeysButton", true, false) as Button).pressed.emit()
	_check("B: Reset Keys", GameKeys.key_of("watch") == KEY_T and GameKeys.key_of("flashlight") == KEY_F and GameKeys.key_of("move_forward") == KEY_W
		and InputMap.action_has_event("move_forward", _press(KEY_W, true)) and note.text == "")
	menu.queue_free()
	await _frames(1)


func _test_calibration() -> void:
	GameSettings.set_value("video/calibrated", false)
	var screen := BrightnessCalibration.new()
	root.add_child(screen)
	await _frames(2)
	var slider: HSlider = screen.find_child("CalibrationSlider", true, false)
	slider.value = 1.3
	var faint := BrightnessCalibration.shown(BrightnessCalibration.SHADES[0], 1.0) < BrightnessCalibration.shown(BrightnessCalibration.SHADES[0], 1.3)
	var closed := [false]
	screen.closed.connect(func(): closed[0] = true)
	(screen.find_child("DoneButton", true, false) as Button).pressed.emit()
	_check("C: the brightness screen sets the brightness and is remembered as seen",
		is_equal_approx(float(GameSettings.get_value("video/brightness")), 1.3) and faint and closed[0] and bool(GameSettings.get_value("video/calibrated")))
	GameSettings.set_value("video/brightness", 1.0)


func _test_quality() -> void:
	GameSettings.set_value("video/quality", 0)
	var low := root.positional_shadow_atlas_size == GraphicsQuality.LAMP_SHADOW[0] and GraphicsQuality.plant_distance() == 40.0
	var batches := _scene.find_children("*", "MultiMeshInstance3D", true, false).filter(func(b): return b.visibility_range_end > 0.0)
	var drawn_low := not batches.is_empty() and batches.all(func(b): return is_equal_approx(b.visibility_range_end, 40.0))
	GameSettings.set_value("video/quality", 2)
	var high := root.positional_shadow_atlas_size == GraphicsQuality.LAMP_SHADOW[2] and root.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA
	GameSettings.set_value("video/quality", 1)
	_check("D: graphics quality Low / High change shadows, plant distance (%d batches), edges" % batches.size(), low and drawn_low and high
		and root.positional_shadow_atlas_size == GraphicsQuality.LAMP_SHADOW[1])


func _test_pause() -> void:
	var pause: Node = _scene.find_child("PauseMenu", true, false)
	var hud := get_first_node_in_group("hud")
	hud.objective_label.text = "Find the fuel can"
	pause._open()
	var where: Label = pause.find_child("WhereLabel", true, false)
	var objective: Label = pause.find_child("ObjectiveLabel", true, false)
	_check("E: the pause menu says where you are: '%s' / '%s'" % [where.text, objective.text],
		where.text == "Day 1" and objective.text == "Find the fuel can")
	pause._resume()
	await _frames(2)


func _test_backdrop() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var backdrop := MenuBackdrop.new()
	viewport.add_child(backdrop)
	await _frames(2)
	var cabin := backdrop.find_child("Cabin", false, false)
	var window := backdrop.find_child("LitWindow", false, false)
	var hidden: bool = not backdrop.entity.visible
	backdrop.visit(0)
	var shown: bool = backdrop.entity.visible
	backdrop._visit_left = 0.05
	await _frames(10)
	_check("F: the menu's backdrop: the cabin, a lit window, and now and then a visitor at the treeline",
		cabin != null and window != null and backdrop.window_light != null and hidden and shown and not backdrop.entity.visible
		and backdrop.find_children("*", "AudioStreamPlayer", false, false).size() == 1)
	viewport.queue_free()
	await _frames(1)


func _test_save() -> void:
	var checkpoint: Node = root.get_node("Checkpoint")
	var inventory: Node = root.get_node("Inventory")
	var tm: Node = root.get_node("TutorialManager")
	var item: Resource = load("res://resources/battery_resource.tres").duplicate()
	inventory.add_item(item)
	var items_then: int = inventory.items.filter(func(i): return i != null).size()
	tm.mark_learned("watch")
	checkpoint.save_to_disk = true
	checkpoint.capture("day")
	checkpoint.save_to_disk = false
	var written := SaveGame.exists()
	var described := SaveGame.describe()
	# Forget it all: as if the game were started again.
	inventory.clear()
	checkpoint._free_templates()
	checkpoint._states.clear()
	checkpoint._taken = false
	root.get_node("RoutineManager")._learned_mechanics.erase("watch")
	var read := SaveGame.read_into(checkpoint)
	checkpoint.restore_on_load = false
	checkpoint.restore()
	await _frames(5)
	var items_now: int = inventory.items.filter(func(i): return i != null).size()
	var battery_back: bool = inventory.items.any(func(i): return i != null and i.get("item_name") == item.get("item_name"))
	_check("G: the checkpoint is written to disk ('%s') and read back: the inventory (%d of %d items), the world, the hints" % [described, items_now, items_then],
		written and described.begins_with("Day") and read and items_now == items_then and battery_back and tm.is_learned("watch")
		and checkpoint.has_checkpoint() and checkpoint.kind == "day")
	# Continue on the main menu.
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	_scene.add_child(menu)
	await _frames(2)
	var continue_button: Button = menu.find_child("ContinueButton", true, false)
	_check("G: the main menu offers Continue (%s), and Play becomes New Game" % (continue_button.text if continue_button else "none"),
		continue_button != null and continue_button.visible and "Day" in continue_button.text and menu.play_button.text == "New Game")
	menu.queue_free()
	await _frames(1)
