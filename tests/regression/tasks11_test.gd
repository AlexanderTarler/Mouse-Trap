extends SceneTree
## planning/tasks.txt (round 5):
##   1 the generator: a tap of E on it switches it on or off, holding E
##     with a fuel can refills it (a tap doesn't spill any fuel); the old
##     switch on a rod is gone, the "Turn on the generator" step highlights
##     the generator itself
##   2 starting a game, black from the first frame until the opening is up
##     (the scene as saved, the player in the cabin, never shows)
##   4 Nest Gamma copies the player's sounds (what the Entity's mimicry
##     does at night): two copied and it can be documented
##   5 the death cutscene: dragged with the eye higher off the ground,
##     never under it, and hoisted to the willow's trunk without going into
##     the bark (or through the Entity)
##   (3, the dev starts: tests/dev_start_test.gd)
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/regression/tasks11_test.gd

var _failures := 0
var _scene: Node
var _player: Node3D
var _nm: Node


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[TASKS11 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	await _frames(2)
	_nm = root.get_node("NightManager")
	# 2: the main menu's Play puts the cover up, then the scene loads.
	_nm.show_start_cover()
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(2)
	var covered_early: bool = _nm.has_start_cover()
	await _frames(60)
	_player = get_first_node_in_group("player")
	_check("2: black from the first frame until the game is set up, then gone",
		covered_early and not _nm.has_start_cover() and _nm._spawn_setup_done)

	await _test_generator()
	await _test_gamma()
	await _test_death()

	print("[TASKS11 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	paused = false
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _test_generator() -> void:
	var packed: PackedScene = load("res://scenes/generator.tscn")
	var lone := packed.instantiate()
	_check("1: the switch on a rod is gone", lone.get_node_or_null("GeneratorSwitch") == null)
	lone.free()

	var generator: Node = get_first_node_in_group("generator_controller")
	var point: Node = generator.get_node("InteractionArea")
	var fuse_box: Node = get_first_node_in_group("xray_fuse_box")
	fuse_box.current_state = 2   # powered
	_nm.generator_fuel = 50.0
	generator.is_switched_on = false
	_nm.is_generator_on = false
	var inventory: Node = root.get_node("Inventory")
	inventory.clear()
	await _frames(2)
	_check("1: no fuel can: the prompt is just switching it on (with the fuel)",
		point.get_interact_text() == "[E] Turn Generator On (50% fuel)", point.get_interact_text())
	point.interact()
	var on: bool = generator.is_switched_on and _nm.is_generator_on
	point.interact()
	_check("1: a tap switches it on, another off", on and not generator.is_switched_on)

	var can = load("res://resources/fuel_can_resource.tres").duplicate()
	can.fuel_amount = 100.0
	inventory.add_item(can)
	await _frames(2)
	_check("1: with a fuel can: switch it (tap) or refill it (hold)",
		point.get_interact_text() == "[E] Turn Generator On\n[Hold E] Refill Generator (50% fuel)", point.get_interact_text().c_escape())
	# A tap: pressed (the refuel starts on the press) and let go at once.
	point.start_refuel()
	await _frames(6)
	point.stop_refuel()
	point.interact()
	_check("1: a tap with a fuel can switches it on and spills no fuel",
		generator.is_switched_on and is_equal_approx(_nm.generator_fuel, 50.0), "%.2f" % _nm.generator_fuel)
	# A hold: fuel goes in, and letting go doesn't switch it.
	point.start_refuel()
	await _frames(60)
	point.stop_refuel()
	point.interact()
	_check("1: holding refills it, and letting go doesn't switch it off",
		generator.is_switched_on and _nm.generator_fuel > 52.0, "%.2f" % _nm.generator_fuel)
	inventory.clear()

	var source := FileAccess.get_file_as_string("res://scripts/routine_manager.gd")
	_check("1: refilled, the generator itself is highlighted for switching on (no switch group left)",
		not source.contains("xray_generator_switch") and get_nodes_in_group("xray_generator_switch").is_empty())


func _test_gamma() -> void:
	var gamma: Node = null
	for nest in get_nodes_in_group("hasselmus_nests"):
		if nest.nest_label == "Nest Gamma":
			gamma = nest
	var flashlight: Node = _player.get_node("CameraHolder/Camera3D/Flashlight")
	_player.enable_flashlight()
	_player.global_position = gamma.global_position + Vector3(1.5, 0.5, 0.0)
	await _frames(20)
	_check("4: Nest Gamma copies sounds (not stand-still-and-listen); a clue at first",
		gamma.lock_type == "mimic" and not gamma.lock_satisfied and not gamma.get_interact_text().begins_with("["), gamma.get_interact_text())
	flashlight.toggle()
	await _frames(90)
	var echo: AudioStreamPlayer3D = gamma.get_node_or_null("EchoAudio")
	var copied_once: bool = gamma.mimic_echoes == 1 and echo != null and echo.stream.resource_path.ends_with("button_flashlight_1.ogg") \
		and echo.pitch_scale < 1.0 and not gamma.lock_satisfied
	var notebook: Node = get_first_node_in_group("notebook_ui")
	notebook._toggle()
	await _frames(5)
	notebook._toggle()
	await _frames(90)
	paused = false
	_check("4: a flashlight click comes back from the stump a moment later, a little off; then the notebook",
		copied_once and gamma.mimic_echoes == 2, "echoes %d" % gamma.mimic_echoes)
	await _frames(2)
	_check("4: copied twice: it can be documented", gamma.lock_satisfied and gamma.get_interact_text().begins_with("[E] Document"), gamma.get_interact_text())
	var hint: String = root.get_node("RoutineManager").DAY2_NEST_HINTS["Nest Gamma"]
	_check("4: the notebook's hint says they answer back (\"%s\")" % hint, "answer back" in hint)


func _test_death() -> void:
	var cinematics: Node = get_first_node_in_group("cinematics")
	root.get_node("EndgameManager").death_cutscenes_seen = 0
	cinematics.play_death()
	var lowest := INF
	var drag_height := 0.0
	var lair: Vector3 = cinematics._lair_position()
	var end := Vector3.ZERO
	var near_entity := INF
	var entity: Node3D = get_first_node_in_group("entity")
	while cinematics.is_playing():
		await process_frame
		var cam: Camera3D = cinematics.death_cam
		var above: float = cam.global_position.y - cinematics._ground_y(cam.global_position)
		lowest = minf(lowest, above)
		if cinematics._clock > 2.0 and cinematics._clock < 6.0:
			drag_height = above
		if cinematics._d_hoisting and cinematics._d_hoist > 0.05:
			var chest := entity.global_position + Vector3.UP * 1.6
			near_entity = minf(near_entity, cam.global_position.distance_to(chest))
		if cinematics._d_hoist >= 1.0:
			end = cam.global_position
	_check("5: dragged with the eye higher off the ground (%.2f m), never under it (lowest %.2f m)" % [drag_height, lowest],
		drag_height > 0.35 and lowest > 0.1)
	# From the end spot towards the trunk: the bark is at least 0.4 m away.
	var space: PhysicsDirectSpaceState3D = _scene.get_world_3d().direct_space_state
	var dir: Vector3 = cinematics._d_dir
	var query := PhysicsRayQueryParameters3D.create(end, end + dir * 3.0, 1)
	query.exclude = [entity.get_rid(), (_player as CollisionObject3D).get_rid()]
	query.hit_from_inside = true
	var hit: Dictionary = space.intersect_ray(query)
	var gap: float = (hit.position - end).length() if hit else INF
	_check("5: hoisted against the willow, clear of its trunk (%.2f m from the bark)" % gap,
		hit and gap > 0.4 and gap < 1.0 and Vector2(end.x - lair.x, end.z - lair.z).length() < 2.5)
	_check("5: swung up over the Entity, not through it (%.2f m from its chest at the closest)" % near_entity, near_entity > 0.9)
