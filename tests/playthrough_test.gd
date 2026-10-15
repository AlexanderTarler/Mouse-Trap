extends SceneTree
## planning/mvp_plan.txt 2: the whole story, Day 1 to an ending, through the
## game's own interactions (picking things up, the door, the fuse box, the
## generator, the computer, the window, the bed, the nests, the van...),
## checking the objective after every step. A change that breaks the
## story's chain (an objective that never advances, a step that can't be
## done) fails here instead of in a player's game.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/playthrough_test.gd

var _failures := 0
var _scene: Node
var _player: Node3D
var _rm: Node
var _nm: Node
var _stopped := false


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _seconds(s: float) -> void:
	await _frames(int(s * 60.0))


func _objective() -> String:
	return _rm.get_current_objective()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[PLAYTHROUGH] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


## A step of the story: `action` done, then the objective must read
## `expected` (a prefix is enough). Stops the run at the first broken step
## (everything after it would fail for the same reason).
func _step(label: String, action: Callable, expected: String, wait: float = 0.5) -> void:
	if _stopped:
		return
	await action.call()
	await _seconds(wait)
	var now := _objective()
	var ok := now.begins_with(expected)
	_check("%s -> \"%s\"" % [label, now], ok, "" if ok else "expected \"%s\"" % expected)
	if not ok:
		_stopped = true


func _find(script_file: String) -> Array[Node]:
	var found: Array[Node] = []
	for node in _scene.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script and script.resource_path.get_file() == script_file:
			found.append(node)
	return found


func _first(script_file: String) -> Node:
	var found := _find(script_file)
	return found[0] if not found.is_empty() else null


func _go(at: Vector3) -> void:
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	await _frames(10)


## Holding E on something with a hold interaction for `seconds`.
func _hold(node: Node, seconds: float) -> void:
	node.start_hold_interact()
	for i in int(seconds * 60.0):
		await physics_frame
		if node.has_method("_process_hold_interact"):
			node._process_hold_interact(1.0 / 60.0)
	if node.has_method("stop_hold_interact"):
		node.stop_hold_interact()


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(90)
	_player = get_first_node_in_group("player")
	_rm = root.get_node("RoutineManager")
	_nm = root.get_node("NightManager")
	_check("the game starts on Day 1: \"%s\"" % _objective(), _objective().begins_with("Go to the cabin"))

	await _day1()
	await _day2()
	await _night22()
	await _day3()

	print("[PLAYTHROUGH] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


# ─── Day 1 ──────────────────────────────────────────────────────────────────

func _door() -> Node:
	return get_first_node_in_group("Door")


func _outside_door() -> Vector3:
	for link in get_first_node_in_group("entity").world.entries():
		if link.kind == CabinEntryLink.Kind.DOOR:
			return link.start_position + Vector3.UP * 0.2
	return Vector3.ZERO


func _day1() -> void:
	var approach: Area3D = _first("cabin_approach_trigger.gd")
	var approach_at: Vector3 = approach.global_position
	for shape in approach.find_children("*", "CollisionShape3D", false, false):
		approach_at = shape.global_position
	await _step("walk up to the cabin", func(): await _go(approach_at + Vector3.UP * 0.2), "Go inside the cabin")
	await _go(_outside_door())
	await _step("try the door (locked)", func(): _door().interact(), "Find the key to the cabin")
	await _step("pick up the key", func(): _first("key_pickup.gd").interact(), "Unlock the front door")
	await _step("unlock the door and go in", func():
		_door().toggle_lock()
		await _seconds(0.5)
		_door().interact()
		await _seconds(1.0)
		await _go(Vector3(10.0, 1.0, 13.0)), "Log into the computer")
	var pc: Node = _first("pc_interactable.gd")
	var fuse_box: Node = _first("fuse_box.gd")
	await _step("try the computer (no power)", func(): pc.interact(), "Check the fuse box")
	await _step("pick up the flashlight (on the way)", func(): _first("flashlight_pickup.gd").interact(), "Check the fuse box")
	await _step("look at the fuse box", func(): fuse_box.interact(), "Find a fuse")
	await _step("pick up the fuse", func(): _first("fuse_pickup.gd").interact(), "Replace the broken fuse")
	await _step("put the fuse in", func(): fuse_box.interact(), "Find a fuel can")
	await _step("pick up the fuel can", func(): _first("fuel_can_pickup.gd").interact(), "Refill the generator")
	var generator: Node = _first("generator_interaction.gd")
	await _step("refill the generator (hold)", func():
		generator.start_refuel()
		await _seconds(8.0)
		generator.stop_refuel(), "Turn on the generator")
	await _step("switch the generator on", func(): _first("generator.gd").interact(), "Log into the computer")
	await _step("log into the computer", func():
		pc.interact()
		await _seconds(1.0)
		var ui: Node = get_first_node_in_group("computer_ui")
		ui._username_input.text = "LUND"
		ui._password_input.text = "PASSKEY1"
		ui._on_login_submit()
		await _seconds(1.0)
		ui.close_computer()
		await _seconds(1.0), "Find 3 planks")
	var planks := _find("plank_pickup.gd").slice(0, 3)
	for i in 3:
		await _step("pick up a plank (%d/3)" % (i + 1), func(): planks[i].interact(), "Find 3 planks" if i < 2 else "Patch the window")
	var window: Node = null
	for w in get_nodes_in_group("WindowMarkers"):
		if w.get("start_broken"):
			window = w
	await _step("patch the window (hold)", func(): await _hold(window, 14.0), "Lock the front door")
	await _step("lock the front door", func():
		if _door().is_open:
			_door().interact()
			await _seconds(1.0)
		_door().toggle_lock(), "Turn off the lights")
	var hall_light: Node = _scene.get_node("Cabin Lights/CabinLightHall")
	await _step("turn off the hall light", func():
		if not hall_light.is_switched_on:
			hall_light.toggle_light()
		hall_light.toggle_light(), "Go to bed")
	await _step("go to bed (Day 1 ends)", func(): await _bed().interact(_player), "Read the previous nest reports")


# ─── Day 2 ──────────────────────────────────────────────────────────────────

func _nest(label: String) -> Node:
	for nest in _find("hasselmus_nest.gd"):
		if nest.nest_label == label:
			return nest
	return null


func _near(node: Node3D) -> void:
	await _go(node.global_position + Vector3(1.5, 0.5, 0.0))


func _day2() -> void:
	var pc: Node = _first("pc_interactable.gd")
	var ui: Node = get_first_node_in_group("computer_ui")
	await _step("read the previous nest reports", func():
		await _go(Vector3(11.0, 1.0, 15.0))
		pc.interact()
		await _seconds(1.0)
		ui._on_previous_reports_open()
		await _seconds(0.5)
		ui.close_computer(), "Locate and document Nest Alpha")
	var flashlight: Node = _player.get_node("CameraHolder/Camera3D/Flashlight")
	await _step("document Nest Alpha (the flashlight overcharged at it)", func():
		await _near(_nest("Nest Alpha"))
		flashlight.is_overcharged = true
		_nest("Nest Alpha").interact()
		flashlight.is_overcharged = false, "Locate and document Nest Beta")
	await _step("document Nest Beta (crouching)", func():
		# Crouched before it's in reach (walking up standing spoils it).
		_player.set_physics_process(false)
		_player._is_crouching = true
		await _near(_nest("Nest Beta"))
		await _seconds(1.0)
		_nest("Nest Beta").interact()
		_player._is_crouching = false
		_player.set_physics_process(true), "Locate and document Nest Gamma")
	await _step("document Nest Gamma (standing still)", func():
		var gamma: Node = _nest("Nest Gamma")
		await _near(gamma)
		await _seconds(gamma.lock_duration + 1.0)
		gamma.interact(), "Log the collected nest data")
	await _step("log the nest data (the field log, from the notebook's answers)", func():
		await _go(Vector3(11.0, 1.0, 15.0))
		pc.interact()
		await _seconds(1.0)
		ui._on_field_log_open()
		await _seconds(0.5)
		var rows := [[ui._dropdown_anomaly_a, ui._pop_input_a, "Nest Alpha"],
				[ui._dropdown_anomaly_b, ui._pop_input_b, "Nest Beta"],
				[ui._dropdown_anomaly_c, ui._pop_input_c, "Nest Gamma"]]
		for row in rows:
			var answer: Dictionary = ui.NEST_ANSWER_KEY[row[2]]
			for i in row[0].item_count:
				if row[0].get_item_text(i) == answer.anomaly:
					row[0].select(i)
			row[1].text = answer.pop
		ui._on_correlate_data()
		await _seconds(12.0)
		ui.close_computer()
		await _seconds(1.0), "")
	_check("the upload done, the next step is to lock up or go to bed (\"%s\")" % _objective(),
		_objective().begins_with("Lock the door") or _objective().begins_with("Go to bed"))
	# Night fell with the upload; if the game hasn't locked the door for
	# them, they lock it (an already locked door counts).
	if _objective().begins_with("Lock the door"):
		await _step("lock the door", func():
			if _door().is_open:
				_door().interact()
				await _seconds(1.0)
			_door().toggle_lock(), "Go to bed")
	await _step("go to bed (woken by the car alarm: Night 2.2)", func():
		await _go(Vector3(11.5, 4.0, 17.3))
		await _bed().interact(_player), "Investigate the car alarm")


# ─── Night 2.2 ──────────────────────────────────────────────────────────────

func _van() -> Node:
	return _scene.find_child("EscapeVan", true, false)


func _night22() -> void:
	if _stopped:
		return
	var entity = get_first_node_in_group("entity")
	await _step("go out to the van and investigate (the chase begins)", func():
		if _door().is_locked:
			_door().toggle_lock()
		if not _door().is_open:
			_door().interact()
		await _go(_van().get_restart_transform().origin)
		_van().interact()
		await _seconds(3.0), "Investigate the car alarm")
	_check("the chase is on (the Entity after them)", entity.van_chase_active)
	await _step("run back into the cabin", func():
		await _go(Vector3(10.0, 1.0, 13.0))
		await _seconds(12.0), "Lock the door and go to bed")
	_check("inside, it gives up the chase", not entity.van_chase_active)
	var gt: Node = root.get_node("GameTime")
	await _step("wait for dawn", func():
		gt.is_time_paused = false
		gt.cycle_progress = 0.995
		gt._elapsed = gt.cycle_progress * gt.cycle_duration
		for i in 60 * 20:
			await physics_frame
			if gt.is_day:
				break
		await _seconds(2.0), "Lock the door and go to bed")
	_check("dawn: Day 3, worn out (night %d)" % _nm.current_night, _nm.current_night == 3 and gt.is_day and _player.get("is_exhausted"))
	_check("no Peeker from Night 2.2 on", not is_instance_valid(root.get_node("PeekerManager")._active_peeker))


# ─── Day 3 ──────────────────────────────────────────────────────────────────

func _day3() -> void:
	if _stopped:
		return
	await _step("sleep it off (exhausted, Day 3)", func():
		await _go(Vector3(11.5, 4.0, 17.3))
		await _bed().interact(_player), "Investigate the car again")
	await _step("look at the van again", func():
		if _door().is_locked:
			_door().toggle_lock()
		await _go(_van().get_restart_transform().origin)
		_van().interact(), "Find parts to repair the van")
	var parts := {}
	for wreck in _find("wreck_salvage.gd"):
		var item = wreck.get("item_resource")
		if item and item.item_name in _van().REQUIRED_PARTS and not parts.has(item.item_name):
			parts[item.item_name] = wreck
	_check("the three van parts are out there (%s)" % ", ".join(parts.keys()), parts.size() == 3)
	var salvaged := [0]
	for part in parts:
		salvaged[0] += 1
		await _step("salvage the %s" % part, func():
			await _near(parts[part])
			parts[part].interact()
			await _seconds(1.0), "Repair the van (%d/3 parts)" % salvaged[0])
	var fitted := [0]
	for part in parts:
		fitted[0] += 1
		await _step("fit the %s (hold)" % part, func():
			await _go(_van().get_restart_transform().origin)
			_van().interact()
			for i in int((_van().INSTALL_TIME + 0.5) * 60.0):
				await physics_frame
				_van()._process_hold_interact(1.0 / 60.0), "Repair the van (3/3" if fitted[0] < 3 else "Start the van and escape")
	var em: Node = root.get_node("EndgameManager")
	await _step("start the van and escape", func():
		_van().interact()
		await _seconds(3.0), "Start the van and escape")
	_check("an ending (%s)" % em.get("current_ending"), em.is_ending_active or em.current_ending != 0)


func _bed() -> Node:
	return _first("bed_interactable.gd")
