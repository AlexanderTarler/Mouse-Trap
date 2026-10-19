class_name DevStart
extends CanvasLayer
## Dev mode: the game started at a chosen point of the story (the Player's
## `dev_start`). The story up to it is played through quickly behind a black
## screen, by the game's own interactions (as tests/playthrough_test.gd
## does): picking things up, the fuse box, the generator, the computer, the
## bed, the nests, the van. Objectives, inventory, evidence, the notebook,
## the clock and the night are then exactly as if it had been played, and
## the checkpoints were taken on the way (a death restarts at that day or
## night, as in a real game).
##
## If a step doesn't give the objective it should (the story changed), it
## stops there and says so on screen; tests/dev_start_test.gd plays every
## start.
##
##   NightManager starts it (dev_start > 0) once the scene is set up.

signal finished(ok: bool)

enum Start {
	FREE_ROAM,       ## dev mode as before: everything unlocked, no story
	DAY_1,           ## the beginning, without the opening
	DAY_1_POWER,     ## the power on, logged into the computer: the planks
	DAY_2,           ## woken on Day 2: the nest reports
	DAY_2_NESTS,     ## the three nests documented: log the data
	NIGHT_2,         ## the data uploaded, night: lock up and go to bed
	NIGHT_2_2,       ## woken by the car alarm
	DAY_3,           ## dawn after the chase, worn out
	DAY_3_RESTED,    ## slept it off, the van looked at: find its parts
	NIGHT_3,         ## the last night falls (the van not repaired)
	NIGHT_3_REPAIRED,  ## the van repaired: escape
}

## For the Player's inspector (the same order as Start).
const NAMES := ["Free roam", "Day 1", "Day 1: power on", "Day 2", "Day 2: nests documented",
	"Night 2", "Night 2.2: car alarm", "Day 3", "Day 3: rested - find the van parts",
	"Night 3", "Night 3: van repaired"]
## How much faster than real time it plays through.
const SPEED := 10.0

var target := Start.DAY_1
## The step it stopped at, if one didn't work ("" when it got there).
var failed_step := ""
var _scene: Node
var _player: Node3D
var _rm: Node
var _nm: Node
var _gt: Node
var _label: Label
var _time_scale := 1.0
var _max_steps := 8


func _ready() -> void:
	layer = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(black)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.85, 0.83, 0.78))
	add_child(_label)


## Plays the story through to `target`, then lifts the black screen.
func run() -> void:
	_scene = get_tree().current_scene
	_player = get_tree().get_first_node_in_group("player")
	_rm = get_node("/root/RoutineManager")
	_nm = get_node("/root/NightManager")
	_gt = get_node("/root/GameTime")
	_label.text = "Dev start: %s\n\nplaying the story up to it..." % NAMES[target]
	print("[DevStart] Playing the story through to: %s" % NAMES[target])
	var entity := get_tree().get_first_node_in_group("entity")
	var could_kill: bool = entity.can_kill if entity else true
	if entity:
		entity.can_kill = false
	_player.set_process_input(false)
	_time_scale = Engine.time_scale
	_max_steps = Engine.max_physics_steps_per_frame
	Engine.time_scale = SPEED
	Engine.max_physics_steps_per_frame = int(SPEED) + 4

	await _play()

	Engine.time_scale = _time_scale
	Engine.max_physics_steps_per_frame = _max_steps
	if entity and is_instance_valid(entity):
		entity.can_kill = could_kill
	_player.set_process_input(true)
	var monologue := get_node_or_null("/root/Monologue")
	if monologue and monologue.has_method("_clear"):
		monologue._clear()
	if failed_step != "":
		_label.text = "Dev start stopped at \"%s\"\nobjective: \"%s\"\n\n(see the output; the game goes on from here)" % [failed_step, _rm.get_current_objective()]
		push_warning("[DevStart] Stopped at \"%s\" (objective \"%s\")." % [failed_step, _rm.get_current_objective()])
		await get_tree().create_timer(4.0, true, false, true).timeout
	else:
		print("[DevStart] At %s: \"%s\"" % [NAMES[target], _rm.get_current_objective()])
	finished.emit(failed_step == "")
	var fade := create_tween().set_parallel()
	for child in get_children():
		fade.tween_property(child, "modulate:a", 0.0, 0.5)
	fade.chain().tween_callback(queue_free)


func _play() -> void:
	await _frames(2)
	if target <= Start.DAY_1:
		return
	if not await _day1():
		return
	if target <= Start.DAY_2 or not await _day2():
		return
	if target <= Start.NIGHT_2_2 or not await _night22():
		return
	await _day3()


# ─── Steps ──────────────────────────────────────────────────────────────────

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## A step: `action` done, then the objective must begin with `expected`.
## False (and it stops) if it doesn't.
func _step(label: String, action: Callable, expected: String, settle: float = 0.5) -> bool:
	if failed_step != "":
		return false
	_label.text = "Dev start: %s\n\n%s..." % [NAMES[target], label]
	await action.call()
	await _wait(settle)
	if not _rm.get_current_objective().begins_with(expected):
		failed_step = label
		return false
	return true


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


func _near(node: Node3D) -> void:
	await _go(node.global_position + Vector3(1.5, 0.5, 0.0))


## Holding E on something with a hold interaction for `seconds`.
func _hold(node: Node, seconds: float) -> void:
	node.start_hold_interact()
	var step := 1.0 / 60.0
	for i in int(seconds / step):
		if node.has_method("_process_hold_interact"):
			node._process_hold_interact(step)
		if i % 30 == 0:
			await _frames(1)
	if node.has_method("stop_hold_interact"):
		node.stop_hold_interact()


func _door() -> Node:
	return get_tree().get_first_node_in_group("Door")


func _bed() -> Node:
	return _first("bed_interactable.gd")


func _van() -> Node:
	return _scene.find_child("EscapeVan", true, false)


func _nest(label: String) -> Node:
	for nest in _find("hasselmus_nest.gd"):
		if nest.nest_label == label:
			return nest
	return null


func _computer() -> Node:
	return get_tree().get_first_node_in_group("computer_ui")


func _outside_door() -> Vector3:
	for link in get_tree().get_first_node_in_group("entity").world.entries():
		if link.kind == CabinEntryLink.Kind.DOOR:
			return link.start_position + Vector3.UP * 0.2
	return Vector3.ZERO


func _shut_and_lock_door() -> void:
	if _door().is_open:
		_door().interact()
		await _wait(1.0)
	if not _door().is_locked:
		_door().toggle_lock()


# ─── Day 1 ──────────────────────────────────────────────────────────────────

func _day1() -> bool:
	var approach: Area3D = _first("cabin_approach_trigger.gd")
	var approach_at: Vector3 = approach.global_position
	for shape in approach.find_children("*", "CollisionShape3D", false, false):
		approach_at = shape.global_position
	await _step("walk up to the cabin", func(): await _go(approach_at + Vector3.UP * 0.2), "Go inside the cabin")
	await _go(_outside_door())
	await _step("try the door", func(): _door().interact(), "Find the key to the cabin")
	await _step("pick up the key", func(): _first("key_pickup.gd").interact(), "Unlock the front door")
	await _step("unlock the door and go in", func():
		_door().toggle_lock()
		await _wait(0.5)
		_door().interact()
		await _wait(1.0)
		await _go(Vector3(10.0, 1.0, 13.0)), "Log into the computer")
	var pc: Node = _first("pc_interactable.gd")
	var fuse_box: Node = _first("fuse_box.gd")
	await _step("try the computer", func(): pc.interact(), "Check the fuse box")
	await _step("pick up the flashlight", func(): _first("flashlight_pickup.gd").interact(), "Check the fuse box")
	await _step("look at the fuse box", func(): fuse_box.interact(), "Find a fuse")
	await _step("pick up the fuse", func(): _first("fuse_pickup.gd").interact(), "Replace the broken fuse")
	await _step("put the fuse in", func(): fuse_box.interact(), "Find a fuel can")
	await _step("pick up the fuel can", func(): _first("fuel_can_pickup.gd").interact(), "Refill the generator")
	var generator: Node = _first("generator_interaction.gd")
	await _step("refill the generator", func():
		generator.start_refuel()
		await _wait(10.0)
		generator.stop_refuel(), "Turn on the generator")
	await _step("switch the generator on", func(): _first("generator.gd").toggle_switch(), "Log into the computer")
	await _step("log into the computer", func():
		pc.interact()
		await _wait(1.0)
		var ui: Node = _computer()
		ui._username_input.text = "LUND"
		ui._password_input.text = "PASSKEY1"
		ui._on_login_submit()
		await _wait(1.0)
		ui.close_computer()
		await _wait(1.0), "Find 3 planks")
	if failed_step != "" or target <= Start.DAY_1_POWER:
		return false
	var planks := _find("plank_pickup.gd").slice(0, 3)
	for i in 3:
		await _step("pick up a plank", func(): planks[i].interact(), "Find 3 planks" if i < 2 else "Patch the window")
	var window: Node = null
	for w in get_tree().get_nodes_in_group("WindowMarkers"):
		if w.get("start_broken"):
			window = w
	await _step("patch the window", func(): await _hold(window, 14.0), "Lock the front door")
	await _step("lock the front door", func(): await _shut_and_lock_door(), "Turn off the lights")
	var hall_light: Node = _scene.get_node("Cabin Lights/CabinLightHall")
	await _step("turn off the hall light", func():
		if not hall_light.is_switched_on:
			hall_light.toggle_light()
		hall_light.toggle_light(), "Go to bed")
	await _step("go to bed", func(): await _bed().interact(_player), "Read the previous nest reports")
	return failed_step == ""


# ─── Day 2 ──────────────────────────────────────────────────────────────────

func _day2() -> bool:
	var pc: Node = _first("pc_interactable.gd")
	var ui: Node = _computer()
	await _step("read the previous nest reports", func():
		await _go(Vector3(11.0, 1.0, 15.0))
		pc.interact()
		await _wait(1.0)
		ui._on_previous_reports_open()
		await _wait(0.5)
		ui.close_computer(), "Locate and document Nest Alpha")
	var flashlight: Node = _player.get_node("CameraHolder/Camera3D/Flashlight")
	await _step("document Nest Alpha", func():
		await _near(_nest("Nest Alpha"))
		flashlight.is_overcharged = true
		_nest("Nest Alpha").interact()
		flashlight.is_overcharged = false, "Locate and document Nest Beta")
	await _step("document Nest Beta", func():
		_player.set_physics_process(false)
		_player._is_crouching = true
		await _near(_nest("Nest Beta"))
		await _wait(1.0)
		_nest("Nest Beta").interact()
		_player._is_crouching = false
		_player.set_physics_process(true), "Locate and document Nest Gamma")
	await _step("document Nest Gamma", func():
		var gamma: Node = _nest("Nest Gamma")
		await _near(gamma)
		for i in gamma.mimic_echoes_needed:
			flashlight.toggle()
			await _wait(2.0)
		gamma.interact(), "Log the collected nest data")
	if failed_step != "":
		return false
	await _go(Vector3(11.0, 1.0, 15.0))
	if target <= Start.DAY_2_NESTS:
		return false
	await _step("log the nest data", func():
		pc.interact()
		await _wait(1.0)
		ui._on_field_log_open()
		await _wait(0.5)
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
		await _wait(12.0)
		ui.close_computer()
		await _wait(1.0), "")
	var objective: String = _rm.get_current_objective()
	if not (objective.begins_with("Lock the door") or objective.begins_with("Go to bed")):
		failed_step = "log the nest data"
		return false
	if target <= Start.NIGHT_2:
		return false
	await _step("lock the door", func(): await _shut_and_lock_door(), "Go to bed")
	await _step("go to bed", func():
		await _go(Vector3(11.5, 4.0, 17.3))
		await _bed().interact(_player), "Investigate the car alarm")
	return failed_step == ""


# ─── Night 2.2 and Day 3 ────────────────────────────────────────────────────

func _night22() -> bool:
	await _step("go out to the van", func():
		if _door().is_locked:
			_door().toggle_lock()
		if not _door().is_open:
			_door().interact()
		await _go(_van().get_restart_transform().origin)
		_van().interact()
		await _wait(3.0), "Investigate the car alarm")
	await _step("run back into the cabin", func():
		await _go(Vector3(10.0, 1.0, 13.0))
		await _wait(12.0), "Lock the door and go to bed")
	await _step("wait for dawn", func():
		_gt.is_time_paused = false
		_gt.cycle_progress = 0.995
		_gt._elapsed = _gt.cycle_progress * _gt.cycle_duration
		for i in 60 * 30:
			await _frames(1)
			if _gt.is_day:
				break
		await _wait(2.0), "Lock the door and go to bed")
	if failed_step != "" or not _gt.is_day:
		failed_step = failed_step if failed_step != "" else "wait for dawn"
		return false
	return target > Start.DAY_3


func _day3() -> void:
	await _step("sleep it off", func():
		await _go(Vector3(11.5, 4.0, 17.3))
		await _bed().interact(_player), "Investigate the car again")
	await _step("look at the van again", func():
		if _door().is_locked:
			_door().toggle_lock()
		await _go(_van().get_restart_transform().origin)
		_van().interact(), "Find parts to repair the van")
	if failed_step != "" or target <= Start.DAY_3_RESTED:
		return
	await _step("wait for night", func():
		_gt.is_time_paused = false
		_gt.cycle_progress = 0.495
		_gt._elapsed = _gt.cycle_progress * _gt.cycle_duration
		for i in 60 * 30:
			await _frames(1)
			if _nm.is_night_active:
				break
		await _go(Vector3(10.0, 1.0, 13.0)), "")
	if not _nm.is_night_active:
		failed_step = "wait for night"
		return
	if target <= Start.NIGHT_3:
		return
	var parts := {}
	for wreck in _find("wreck_salvage.gd"):
		var item = wreck.get("item_resource")
		if item and item.item_name in _van().REQUIRED_PARTS and not parts.has(item.item_name):
			parts[item.item_name] = wreck
	for part in parts:
		await _step("salvage the %s" % part, func():
			await _near(parts[part])
			parts[part].interact()
			await _wait(1.0), "Repair the van")
	for part in parts:
		await _step("fit the %s" % part, func():
			await _go(_van().get_restart_transform().origin)
			await _hold(_van(), _van().INSTALL_TIME + 0.5), "")
	if not _van().is_repaired:
		failed_step = failed_step if failed_step != "" else "repair the van"
