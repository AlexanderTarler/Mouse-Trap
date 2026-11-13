extends SceneTree
## UI review, round 1 (planning/ui_review.txt):
##   1.1 the UI scales with the window (canvas_items stretch), the inventory
##       panel is anchored to the centre;
##   1.2 prompts never show formatting tags; statuses are dimmed;
##   1.3 the stash title is a place, not an internal id;
##   1.4 the inventory: 5 x 2 slots, the selected item in the info box, "Use"
##       named for what it does and greyed out where it does nothing;
##   1.5 prompts: "[E] ..." taps, "[Hold E] ..." holds, statuses keyless;
##   1.6 a click doesn't throw a note away;
##   1.8 no "Night x / 5";
##   2.2 a new objective is announced;
##   2.9 the death scene says it can be skipped.
## Round 2:
##   2.1 [R] swaps in a spare battery;
##   2.3 one ring around the crosshair for every hold;
##   2.4 the crosshair reacts to what is aimed at;
##   2.6 a Controls page; 2.7 brightness, FOV, head bob, sensitivity,
##       invert Y; 2.8 a tip on the death screen.
## Round 3:
##   3.1 a quiet HUD (gauges, the day as a card); 3.2 the bundled fonts;
##   3.3 the endings by name, with the phone epilogue; 3.4 the death screen
##   as a field report; 3.5 the opening's phone, readable; 3.6 quiet pickup
##   lines; 2.5 item pictures from their models.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/ui_test.gd

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
	print("[UI TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(60)
	root.get_node("NightManager").is_time_paused = true

	_test_scaling()
	await _test_inventory()
	_test_prompts()
	_test_stash_title()
	await _test_note_click()
	await _test_objective_notice()
	_test_skip_hint()
	await _test_crosshair()
	await _test_hold_ring()
	await _test_battery_key()
	await _test_settings()
	_test_death_tip()
	_test_fonts()
	await _test_quiet_hud()
	_test_death_report()
	await _test_endings()
	_test_phone_and_icons()

	print("[UI TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _test_scaling() -> void:
	var mode: String = ProjectSettings.get_setting("display/window/stretch/mode", "disabled")
	var aspect: String = ProjectSettings.get_setting("display/window/stretch/aspect", "")
	var panel: Control = get_first_node_in_group("inventory_ui").get_node("Panel")
	_check("scaling: the UI scales with the window, the inventory is anchored to the centre",
		mode == "canvas_items" and aspect == "expand" and panel.anchor_left == 0.5 and panel.anchor_top == 0.5,
		"%s / %s" % [mode, aspect])


func _test_inventory() -> void:
	var ui: Node = get_first_node_in_group("inventory_ui")
	var inv: Node = root.get_node("Inventory")
	var saved: Array = inv.items.duplicate()
	inv.items.clear()
	inv.items.append(load("res://resources/battery_resource.tres"))
	inv.items.append(load("res://resources/plank_resource.tres"))
	ui._open_inventory()
	await _frames(2)
	var grid: GridContainer = ui.grid_container
	ui._on_item_selected(0)
	var battery_use: String = ui.use_button.text
	var battery_ok: bool = not ui.use_button.disabled and ui.info_item_name_label.text != ""
	ui._on_item_selected(1)
	var plank_disabled: bool = ui.use_button.disabled
	var desc: String = ui.info_item_desc_label.text
	ui._close_inventory()
	inv.items = saved
	_check("inventory: 5 x 2 slots, the item in the info box, \"Use\" says what it does or is greyed out",
		grid.columns == 5 and grid.get_child_count() == 10 and battery_use == "Swap Battery" and battery_ok and plank_disabled and desc != "",
		"use '%s' for a battery; plank greyed=%s" % [battery_use, plank_disabled])


func _test_prompts() -> void:
	var player: Node = get_first_node_in_group("player")
	var im: Node = player.find_child("InteractionManager", true, false)
	im._show_prompt("[color=gray]Too tired to do this[/color]")
	var stripped: String = im._prompt_label.text
	var dim: Color = im._prompt_label.get_theme_color("font_color")
	im._show_prompt("[E] Open Gate")
	var bright: Color = im._prompt_label.get_theme_color("font_color")
	im._show_prompt("")
	_check("prompts: no formatting tags shown; statuses dimmed, actions bright",
		stripped == "Too tired to do this" and dim.a < bright.a, "'%s'" % stripped)

	# Every interactable in the level: a key it can act on, or a plain status.
	var bad: Array[String] = []
	for node in _scene.find_children("*", "", true, false):
		if not node.has_method("get_interact_text"):
			continue
		var text = node.get_interact_text()
		if not (text is String) or text == "":
			continue
		if "[color" in text or "[Hold " in text and not text.begins_with("[Hold E]") or "Hold to" in text or "[Hold %" in text:
			bad.append("%s: %s" % [node.name, text])
		if text.begins_with("[E]") and ("(Full)" in text or "(Active)" in text or "(Secured)" in text or "Need " in text):
			bad.append("%s: %s" % [node.name, text])
	_check("prompts: \"[E]\" only where E does something, holds read \"[Hold E] ...\"", bad.is_empty(), str(bad))


func _test_stash_title() -> void:
	var heap: Node = null
	for n in _scene.find_children("*", "", true, false):
		if n.get_script() and str(n.get_script().resource_path).ends_with("scrap_heap.gd") and n.get("place_name") == "Barn":
			heap = n
	var ui: Node = load("res://scenes/stash_ui.tscn").instantiate()
	_scene.add_child(ui)
	ui.open_container_stash(heap, [])
	var title: String = ui._title_label.text
	ui._close_stash()
	ui.queue_free()
	_check("stash: titled by its place", title == "Scrap Heap — Barn" and not "scrap_heap_" in title, title)


func _test_note_click() -> void:
	var note_ui: Node = get_first_node_in_group("note_ui")
	note_ui.display_note("A short note.", "Note")
	await _frames(2)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	note_ui._input(click)
	var still_open: bool = note_ui._is_open
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	note_ui._input(esc)
	_check("notes: a stray click doesn't close one; Esc does", still_open and not note_ui._is_open)


func _test_objective_notice() -> void:
	var hud: Node = get_first_node_in_group("hud")
	hud._on_routine_step_changed(1, "Something new to do.")
	await _frames(20)
	var note: Label = hud.get("_objective_note")
	var night_label: Label = hud.get_node("NightLabel")
	_check("objective: a new one is announced (\"Notebook updated\"); no \"/ 5\" nights",
		note != null and note.modulate.a > 0.2 and not "/ 5" in night_label.text, night_label.text)


func _test_skip_hint() -> void:
	var cinematics = _scene.find_child("Cinematics", true, false)
	cinematics._ensure_overlay()
	var hint: Label = cinematics.get("_skip_hint")
	_check("death scene: it says it can be skipped", hint != null and "skip" in hint.text.to_lower())


func _test_crosshair() -> void:
	var ring: Node = get_first_node_in_group("crosshair")
	var im: Node = get_first_node_in_group("player").find_child("InteractionManager", true, false)
	im._show_prompt("[E] Open Gate")
	var action: int = im.target_kind
	im._show_prompt("Generator (full)")
	var status: int = im.target_kind
	im._show_prompt("")
	_check("crosshair: a dot that knows an action from a status from nothing",
		ring is Crosshair and action == 1 and status == 2 and im.target_kind == 0)


func _test_hold_ring() -> void:
	var ring: Node = get_first_node_in_group("crosshair")
	var window: Node = _scene.get_node("Windows/BottomFloorWindows/LivingRoomWindow")
	window._is_boarding = true
	window._boarding_progress = window.BOARD_PER_PLANK_TIME * 0.5
	var progress: float = window.get_hold_progress()
	window._is_boarding = false
	window._boarding_progress = 0.0
	ring.set_hold(progress)
	await _frames(2)
	var shown: bool = ring._hold >= 0.4
	await _frames(20)
	_check("hold ring: boarding reports its progress, the ring shows it, then goes",
		absf(progress - 0.5) < 0.01 and shown and ring._hold < 0.0, "progress %.2f" % progress)


func _press_r() -> void:
	var ev := InputEventAction.new()
	ev.action = "swap_battery"
	ev.pressed = true
	get_first_node_in_group("inventory_ui")._unhandled_input(ev)


func _test_battery_key() -> void:
	var player: Node = get_first_node_in_group("player")
	var inv: Node = root.get_node("Inventory")
	var saved: Array = inv.items.duplicate()
	var had: bool = player._has_flashlight
	player._has_flashlight = true
	var light: Node = player._flashlight
	light.battery_level = 20.0
	inv.items.clear()
	inv.items.append(load("res://resources/battery_resource.tres"))
	_press_r()
	var swapped: bool = light.battery_level > 60.0 and inv.items.is_empty()
	var monologue: Node = root.get_node("Monologue")
	monologue._clear()
	_press_r()
	await _frames(2)
	var told: bool = monologue._said == "No spare batteries."
	inv.items = saved
	player._has_flashlight = had
	_check("battery key: [R] swaps in a spare; with none, a thought says so", swapped and told,
		"battery %.0f, said '%s'" % [light.battery_level, monologue._said])


func _test_settings() -> void:
	var menu: Node = load("res://scenes/ui/options_menu.tscn").instantiate()
	_scene.add_child(menu)
	await _frames(2)
	var player: Node = get_first_node_in_group("player")
	var camera: Camera3D = player.get_node("CameraHolder/Camera3D")
	var saved := {}
	for key in GameSettings.DEFAULTS:
		saved[key] = GameSettings.get_value(key)
	menu.find_child("BrightnessSlider", true, false).value = 1.4
	menu.find_child("FovSlider", true, false).value = 90.0
	menu.find_child("SensitivitySlider", true, false).value = 2.0
	menu.find_child("InvertYCheck", true, false).button_pressed = true
	menu.find_child("HeadBobCheck", true, false).button_pressed = false
	await _frames(2)
	var layer: CanvasLayer = root.get_node_or_null(GameSettings.BRIGHTNESS_LAYER)
	var applied: bool = layer != null and layer.visible and is_equal_approx(camera.fov, 90.0) 		and is_equal_approx(player.look_scale, 2.0) and player.invert_y and not player.head_bob_enabled
	menu._show_controls()
	var keys: Node = menu.find_child("Keys", true, false)
	var listed: int = keys.get_child_count() / 2 if keys else 0
	for key in saved:
		GameSettings.set_value(key, saved[key])
	menu.queue_free()
	await _frames(2)
	_check("settings: brightness, FOV, sensitivity, invert Y and head bob take effect; a Controls page lists the keys",
		applied and listed >= 10 and root.get_node(GameSettings.BRIGHTNESS_LAYER).visible == (absf(float(saved["video/brightness"]) - 1.0) > 0.01),
		"applied=%s, %d keys" % [applied, listed])


func _test_death_tip() -> void:
	var jumpscare: Node = root.get_node("JumpscareManager")
	var canvas := CanvasLayer.new()
	_scene.add_child(canvas)
	jumpscare._add_death_tip(canvas)
	var tip: Label = canvas.get_node_or_null("TipLabel")
	_check("death: a survival tip under the buttons", tip != null and tip.text.length() > 10, tip.text if tip else "none")
	canvas.queue_free()


func _test_fonts() -> void:
	var font: String = ProjectSettings.get_setting("gui/theme/custom_font", "")
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	_scene.add_child(menu)
	var title_font: Font = menu.get_node("TitleLabel").get_theme_font("font")
	menu.queue_free()
	var thought_font: Font = root.get_node("Monologue")._get_font()
	_check("fonts: Courier Prime for the UI, its italic for thoughts, Special Elite for titles",
		font.ends_with("CourierPrime-Regular.ttf") and ResourceLoader.exists(font)
			and title_font and title_font.resource_path.ends_with("SpecialElite-Regular.ttf")
			and thought_font and thought_font.resource_path.ends_with("CourierPrime-Italic.ttf"),
		"%s / %s" % [font, title_font.resource_path if title_font else "none"])


func _test_quiet_hud() -> void:
	var hud: Node = get_first_node_in_group("hud")
	var gauges: Node = hud.get("_gauges")
	hud._on_battery_changed(40.0)
	hud._on_stamina_changed(30.0)
	var fed: bool = gauges != null and is_equal_approx(gauges.battery, 40.0) and is_equal_approx(gauges.stamina, 30.0)
	var old_hidden: bool = not hud.battery_bar.visible and not hud.stamina_bar.visible
	hud._on_stamina_changed(100.0)
	hud.night_label.text = ""
	hud._update_night_label(2)
	await _frames(30)
	var shown: float = hud.night_label.modulate.a
	hud.show_pickup_message("+ Fuel Can")
	_check("HUD: quiet gauges instead of coloured bars; the day as a card that fades in; quiet pickups",
		fed and old_hidden and shown > 0.2 and hud._pickup_label.text == "+ Fuel Can" and not "🔋" in hud.battery_label.text,
		"fed=%s hidden=%s card %.2f" % [fed, old_hidden, shown])


func _test_death_report() -> void:
	var text := FileAccess.get_file_as_string("res://scenes/death_screen.tscn")
	_check("death screen: a field report, not \"You Died\"", "Field survey suspended" in text and not "You Died" in text)


func _test_endings() -> void:
	var screen: Node = load("res://scenes/ui/ending_screen.tscn").instantiate()
	_scene.add_child(screen)
	screen.setup_ending(1)
	await _frames(30)
	var phone := screen.find_children("*", "Panel", true, false).filter(func(n): return n is Phone)
	var box: Control = screen.get_node("VBoxContainer")
	var hidden_first: bool = box.modulate.a < 0.1 and not phone.is_empty()
	# Any key skips the epilogue.
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	screen._input(key)
	await _frames(150)
	var caption: Label = screen.find_child("EndingCountLabel", true, false)
	_check("endings: \"It Follows\", the phone epilogue first (skippable), then the words and \"Ending 1 of 2\"",
		hidden_first and box.modulate.a > 0.5 and screen.title_label.text == "It Follows"
			and caption and caption.text == "Ending 1 of 2" and not "player" in screen.subtitle_label.text.to_lower(),
		"title '%s', box %.2f" % [screen.title_label.text, box.modulate.a])
	screen.queue_free()


func _test_phone_and_icons() -> void:
	var opening_src := FileAccess.get_file_as_string("res://scripts/cinematics/opening.gd")
	var phone := Phone.new()
	_scene.add_child(phone)
	phone.build("Test", "12:00")
	var bubble: Dictionary = phone.bubble("Hello", false, "now")
	var label: Label = bubble.row.find_children("*", "Label", true, false)[0]
	var big: bool = label.get_theme_font_size("font_size") >= 18
	phone.queue_free()
	var battery = load("res://resources/battery_resource.tres")
	_check("phone: one Phone for the opening and the endings, text big enough to read; item pictures from models",
		"Phone.new()" in opening_src and big and ItemIcons._model_path(battery) != "" and ItemIcons.icon_for(battery) == null,
		"(no pictures in a headless run: the labels stay)")
