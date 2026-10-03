extends SceneTree
## The third bugs.txt round:
##   1. The flashlight hint goes once F is pressed (even before the later
##      overcharge tutorial is learned).
##   2. Every tutorial hint goes once its action is done.
##   3. The Peeker stays 1 s longer once seen.
##   4. The notebook: page numbers, index progress, no stray day label.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/bugs3_test.gd

var _failures := 0
var _scene: Node
var _tm: Node
var _rm: Node


func _initialize() -> void:
	_run()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[BUGS3 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(90)
	_tm = root.get_node("TutorialManager")
	_rm = root.get_node("RoutineManager")
	# Hints go at once here (bugs4_test covers their minimum time up).
	root.get_node("TutorialManager").min_hint_time = 0.0

	await _test_flashlight_hint()
	await _test_hints()
	_test_peeker()
	await _test_notebook()

	print("[BUGS3 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	paused = false
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


## Shows a mechanic's hint afresh (not learned, not shown, nothing up).
func _show(id: String) -> void:
	var hud: Node = get_first_node_in_group("hud")
	hud.hide_hint()
	_tm._visible_id = ""
	_rm._learned_mechanics.erase(id)
	_tm._shown.erase(id)
	_tm.trigger(id, true)
	await _frames(45)


func _up() -> String:
	return get_first_node_in_group("hud").current_hint()


func _test_flashlight_hint() -> void:
	var nm: Node = root.get_node("NightManager")
	var player: Node = get_first_node_in_group("player")
	_rm._learned_mechanics.erase("overcharge")
	nm.is_night_active = true
	player._has_flashlight = true
	await _show("flashlight")
	var before := _up()
	player._toggle_flashlight()
	await _frames(2)
	_check("#1 the flashlight hint goes when F is pressed (overcharge not yet learned)",
		"[F]" in before and _up() == "" and _tm.is_learned("flashlight"), "'%s' -> '%s'" % [before, _up()])
	player._toggle_flashlight()
	nm.is_night_active = false


func _test_hints() -> void:
	# Movement: moving and crouching (not every key).
	var player: Node = get_first_node_in_group("player")
	await _show("movement")
	player._movement_tutorial_ready = true
	player._enable_movement_tutorial()
	for key in [KEY_W, KEY_CTRL]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = true
		player._input(event)
	await _frames(2)
	_check("#2 movement: gone after moving and crouching", _tm.is_learned("movement") and not "[W]" in _up(), _up())

	# PC login hint: opening the notebook is what it asks.
	await _show("pc_login_hint")
	var before := _up()
	var notebook: Node = _scene.find_child("NotebookUI", true, false)
	notebook._toggle()
	await _frames(2)
	notebook._toggle()
	_check("#2 PC login hint: gone when the notebook opens", "notebook" in before and _up() == "", "'%s' -> '%s'" % [before, _up()])

	# Low battery: swapping in a battery.
	await _show("low_battery")
	before = _up()
	var inventory_ui: Node = _scene.find_child("InventoryUI", true, false)
	var battery: Resource = null
	for item in root.get_node("Inventory").items:
		if item and item.item_name == "Battery":
			battery = item
	if not battery:
		battery = load("res://scripts/items/item_data.gd").new()
		battery.item_name = "Battery"
		root.get_node("Inventory").add_item(battery)
	inventory_ui._use_battery(battery)
	await _frames(2)
	_check("#2 low battery: gone when a battery is swapped in", "battery" in before and not "battery" in _up() and _tm.is_learned("low_battery"), "'%s' -> '%s'" % [before, _up()])

	# Pick up / drop: dropping what was picked up.
	await _show("pickup_drop")
	before = _up()
	var grab: Node = player.find_child("PhysicalGrab", true, false)
	var crate := RigidBody3D.new()
	_scene.add_child(crate)
	grab._grab_object(crate)
	grab._drop_object()
	await _frames(2)
	crate.queue_free()
	_check("#2 pick up / drop: gone once something is dropped", "pick up" in before and _up() == "", "'%s' -> '%s'" % [before, _up()])

	# Another hint stays when an unrelated mechanic is learned.
	await _show("sprint")
	_tm.mark_learned("flashlight")
	await _frames(2)
	_check("#2 an unrelated action leaves the hint up", "[SHIFT]" in _up(), _up())
	_tm.mark_learned("sprint")


func _test_peeker() -> void:
	var script: Script = load("res://scripts/window_peeker.gd")
	var delay: float = script.get_script_constant_map().get("SPOTTED_VANISH_DELAY", 0.0)
	_check("#3 the Peeker stays 1 s longer once seen (%.3f s)" % delay, is_equal_approx(delay, 1.325))


func _test_notebook() -> void:
	var notebook: Node = _scene.find_child("NotebookUI", true, false)
	notebook.add_documentation("Nest Alpha")
	notebook._toggle()
	notebook.current_spread = 1
	notebook._current_page = 0
	notebook._update_spread()
	await _frames(2)
	var numbers: Array = notebook._page_numbers
	_check("#4 notebook: page numbers on the content pages",
		numbers.size() == 2 and numbers[0].text == "— 1 —" and numbers[1].text == "— 2 —",
		"%s / %s" % [numbers[0].text if numbers.size() > 0 else "", numbers[1].text if numbers.size() > 1 else ""])
	_check("#4 notebook: the index shows progress, the nest page its stamp, no stray day label",
		"1 of 3 documented" in notebook._index_label.text and "DOCUMENTED" in notebook._notes_label.text
		and not notebook._day_label.visible)
	notebook._toggle()
