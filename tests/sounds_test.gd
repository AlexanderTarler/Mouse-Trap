extends SceneTree
## The recorded sounds brought in from the asset library:
##   - rain: two looping recordings (medium, heavy) crossfaded by the
##     storm's strength, instead of the synthesized hiss;
##   - the ambush tell is a breath (Monster_breath);
##   - the van: the hood goes up when fitting a part, down when it's
##     repaired; the door opens when climbing in to leave; in the escape the
##     door shuts, the engine starts up, then its loop runs;
##   - the opening uses the car's engine, its turning off and its door;
##   - the Night 2.2 panic: a gasp, then fast breathing that calms down after;
##   - caught: a gasp with the sting.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/sounds_test.gd

var _failures := 0
var _scene: Node


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[SOUNDS TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(70)

	await _test_rain()
	_test_tell()
	_test_opening()
	await _test_panic()
	_test_caught()
	await _test_van()

	print("[SOUNDS TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	paused = false
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _test_rain() -> void:
	var weather: Node = root.get_node("Weather")
	weather.start_storm(0.0, true)
	await _frames(3)
	var medium: AudioStreamPlayer = weather._rain_player
	var heavy: AudioStreamPlayer = weather._heavy_player
	var looping := func(p: AudioStreamPlayer) -> bool:
		return p != null and p.stream is AudioStreamWAV and p.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and p.playing
	_check("rain: two looping recordings play (no generated noise)", looping.call(medium) and looping.call(heavy),
		"%s / %s" % [medium.stream if medium else null, heavy.stream if heavy else null])
	weather.level = 0.3
	await _frames(1)
	var light: bool = medium.volume_db > heavy.volume_db + 20.0
	weather.level = 1.0
	await _frames(1)
	var full: bool = heavy.volume_db > medium.volume_db + 20.0 and heavy.volume_db > -10.0
	_check("rain: the medium rain while it builds, the heavy rain at its height", light and full,
		"full: medium %.0f dB, heavy %.0f dB" % [medium.volume_db, heavy.volume_db])
	weather.clear_now()
	await _frames(2)
	_check("rain: cleared, both gone", weather._rain_player == null and weather._heavy_player == null and not is_instance_valid(heavy))


func _test_tell() -> void:
	var entity: Node = get_first_node_in_group("entity")
	entity.audio.play_tell()
	var sfx: AudioStreamPlayer3D = entity.audio._sfx
	_check("ambush tell: a breath", sfx.stream and sfx.stream.resource_path.ends_with("Monster_breath.wav") and sfx.playing)
	sfx.stop()


func _test_opening() -> void:
	var paths := [Opening.ENGINE_SOUND, Opening.ENGINE_OFF_SOUND, Opening.DOOR_OPEN_SOUND, Opening.DOOR_CLOSE_SOUND]
	_check("opening: the car's engine, its turning off and its door are there",
		paths.all(func(p): return ResourceLoader.exists(p)) and "objects/van/" in Opening.ENGINE_SOUND)


func _test_panic() -> void:
	var panic := PanicThoughts.new()
	root.add_child(panic)
	await _frames(2)
	panic.active = true
	await _frames(2)
	var gasped: bool = panic.gasp.playing
	await _frames(50)
	_check("panic: a gasp, then fast breathing (looping)",
		gasped and panic.breath.playing and panic.breath_level > 0.99 and panic.breath.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"gasp %s, breath %s at %.2f" % [gasped, panic.breath.playing, panic.breath_level])
	panic.clear()
	await _frames(60)
	var easing: bool = panic.breath.playing and panic.breath_level > 0.2 and panic.breath_level < 0.9
	await _frames(120)
	_check("panic: over, the breathing calms down (not cut off) and stops",
		easing and not panic.breath.playing and panic.breath_level == 0.0, "easing=%s level %.2f" % [easing, panic.breath_level])
	panic.queue_free()


func _test_caught() -> void:
	var jm: Node = root.get_node("JumpscareManager")
	_check("caught: a gasp goes with the sting",
		jm._gasp_player and jm._gasp_player.stream.resource_path.ends_with("Gasp.wav"))


func _test_van() -> void:
	var van: Node = _scene.get_node("EscapeVan")
	var inventory: Node = root.get_node("Inventory")
	var parts := {}
	for node in _scene.find_children("*", "", true, false):
		var item = node.get("item_resource")
		if item and item.item_name in van.REQUIRED_PARTS and not parts.has(item.item_name):
			parts[item.item_name] = item
	for item in parts.values():
		inventory.add_item(item)
	van.van_investigated = true
	var car: AudioStreamPlayer3D = van._car_audio
	van.start_hold_interact()
	_check("van: holding E with a part, the hood goes up",
		van.hood_open and car.playing and car.stream == van.HOOD_OPEN_STREAM)
	for i in int(van.INSTALL_TIME * 60.0) + 10:
		van._process_hold_interact(1.0 / 60.0)
	_check("van: still fitting parts, the hood stays up (no new sound)", van.hood_open and van.components_collected == 1 and car.stream == van.HOOD_OPEN_STREAM)
	for i in int(van.INSTALL_TIME * 60.0 * 2.0) + 20:
		van._process_hold_interact(1.0 / 60.0)
	_check("van: repaired, the hood comes down (%d parts)" % van.components_collected,
		van.is_repaired and not van.hood_open and car.stream == van.HOOD_CLOSE_STREAM)

	var cinematics: Node = get_first_node_in_group("cinematics")
	van._trigger_ending()
	await _frames(2)
	_check("van: climbing in, the door opens", car.stream == van.DOOR_OPEN_STREAM and car.playing)
	await _frames(30)
	var engine: AudioStreamPlayer3D = cinematics._v_engine
	var starting: bool = engine != null and engine.stream.resource_path.ends_with("Car_Engine_Start_Up.ogg") and engine.playing and not cinematics._v_engine_running
	# (Sound plays in real time, the test's frames faster than that: the
	# cutscene would be over first. The start-up is done, as it were.)
	if starting:
		engine.finished.emit()
	await _frames(2)
	_check("escape: the engine starts up, then its loop runs",
		starting and cinematics._v_engine_running and engine.playing and engine.stream.loop,
		"starting=%s running=%s" % [starting, cinematics._v_engine_running])
