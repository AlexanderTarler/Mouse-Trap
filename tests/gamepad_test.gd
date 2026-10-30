extends SceneTree
## The gamepad, the "keep these settings?" countdown, and the crouch hint
## moving to the second nest:
##   - every action has its pad button or stick, the look actions exist;
##   - hints and prompts name the pad's buttons while a pad is in use;
##   - the movement hint no longer mentions crouching, the nest's hint does;
##   - a display change is reverted unless kept in time.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/gamepad_test.gd

var _failures := 0


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[GAMEPAD TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" and not ok else ""])


func _has_pad_event(action: String, button: int = -1, axis: int = -1) -> bool:
	for event in InputMap.action_get_events(action):
		if button >= 0 and event is InputEventJoypadButton and event.button_index == button:
			return true
		if axis >= 0 and event is InputEventJoypadMotion and event.axis == axis:
			return true
	return false


func _run() -> void:
	await _frames(2)
	GameKeys.apply()

	# ─── The actions ────────────────────────────────────────────────
	_check("walking: the left stick drives the four move actions",
		_has_pad_event("move_left", -1, JOY_AXIS_LEFT_X) and _has_pad_event("move_right", -1, JOY_AXIS_LEFT_X)
		and _has_pad_event("move_forward", -1, JOY_AXIS_LEFT_Y) and _has_pad_event("move_back", -1, JOY_AXIS_LEFT_Y))
	_check("looking: the right stick has its own four actions",
		_has_pad_event("look_left", -1, JOY_AXIS_RIGHT_X) and _has_pad_event("look_up", -1, JOY_AXIS_RIGHT_Y))
	_check("buttons: jump A, crouch B, use X, flashlight Y, pause Start, cancel B",
		_has_pad_event("jump", JOY_BUTTON_A) and _has_pad_event("ui_crouch", JOY_BUTTON_B)
		and _has_pad_event("ui_interact", JOY_BUTTON_X) and _has_pad_event("flashlight", JOY_BUTTON_Y)
		and _has_pad_event("pause_menu", JOY_BUTTON_START) and _has_pad_event("ui_cancel", JOY_BUTTON_B))
	GameKeys.apply()
	var before := InputMap.action_get_events("jump").size()
	GameKeys.apply()
	_check("applying twice doesn't pile events up", InputMap.action_get_events("jump").size() == before)
	_check("the keyboard keys are still there next to the pad's",
		InputMap.action_get_events("ui_interact").any(func(e): return e is InputEventKey))

	# ─── Hints name the pad's buttons ───────────────────────────────
	GameKeys.gamepad_active = false
	var on_keys := GameKeys.keys_in("[E] Open · [Hold F] Overcharge · Use [W][A][S][D] to move.")
	GameKeys.gamepad_active = true
	var on_pad := GameKeys.keys_in("[E] Open · [Hold F] Overcharge · Use [W][A][S][D] to move.")
	GameKeys.gamepad_active = false
	_check("on the keyboard the hints are left as written", on_keys == "[E] Open · [Hold F] Overcharge · Use [W][A][S][D] to move.", on_keys)
	_check("on a pad: [X] Open, [Hold Y] Overcharge, the left stick walks",
		on_pad == "[X] Open · [Hold Y] Overcharge · Use [Left stick] to move.", on_pad)

	# ─── The crouch hint is the nest's ──────────────────────────────
	var tutorials: Array = root.get_node("TutorialManager").tutorials
	var movement := ""
	var stealth := ""
	for t in tutorials:
		if t.mechanic_id == "movement":
			movement = t.prompt_text
		elif t.mechanic_id == "stealth":
			stealth = t.prompt_text
	_check("the movement hint is only about moving", movement != "" and not "CTRL" in movement and not "silent" in movement, movement)
	_check("the second nest's hint teaches crouching, and that it makes you silent",
		"[CTRL]" in stealth and "silent" in stealth, stealth)

	# ─── Keep these settings? ───────────────────────────────────────
	var menu: Node = load("res://scenes/ui/options_menu.tscn").instantiate()
	root.add_child(menu)
	await _frames(2)
	menu.show_menu()
	var original := int(GameSettings.get_value("video/quality"))
	var other := 0 if original != 0 else 2
	var quality: OptionButton = menu.find_child("QualityOption", true, false)
	quality.select(other)
	quality.item_selected.emit(other)
	await _frames(2)
	var asked: bool = menu._confirm != null and menu._confirm.visible
	var applied_at_once: bool = int(GameSettings.get_value("video/quality")) == other
	menu._revert_change()
	await _frames(2)
	_check("a graphics change applies at once and asks to keep it",
		asked and applied_at_once)
	_check("Revert puts the old setting (and the drop-down) back",
		int(GameSettings.get_value("video/quality")) == original and quality.get_selected_id() == original and not menu._confirm.visible)
	quality.select(other)
	quality.item_selected.emit(other)
	await _frames(2)
	menu._keep_change()
	_check("Keep makes it stay", int(GameSettings.get_value("video/quality")) == other and not menu._confirm.visible)
	# Not answered in time: back.
	quality.select(original)
	quality.item_selected.emit(original)
	await _frames(2)
	menu._confirm_left = 0.05
	await _frames(10)
	_check("not answered in time, it goes back by itself",
		int(GameSettings.get_value("video/quality")) == other and not menu._confirm.visible)
	# Leaving the menu with it unanswered also puts it back.
	quality.select(original)
	quality.item_selected.emit(original)
	await _frames(2)
	menu.hide_menu()
	_check("leaving the menu unanswered puts it back",
		int(GameSettings.get_value("video/quality")) == other and not menu._confirm.visible)
	GameSettings.set_value("video/quality", original)
	menu.queue_free()
	await _frames(2)

	print("[GAMEPAD TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)
