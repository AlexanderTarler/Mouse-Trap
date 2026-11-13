extends SceneTree
## planning/tasks.txt round 2, Night 2.2 (planning/tasks_plan.txt):
##   8  waking to the alarm: "Why is the car alarm blaring?"; the noise
##      ("entity_glimpse") a few seconds later: "What the fuck was that?!",
##      then the alarm and the battery; never over the wake thought
##   9  the wildlife falls silent all Night 2.2 (rain, thunder, wind stay)
##   11 the chase: "Oh fuck!" panic all over the screen, clear of the
##      middle, until they're inside
##   13 inside with the front door shut: it stays shut until Day 3
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/regression/tasks7_test.gd

var _failures := 0
var _scene: Node
var _player: Node3D
var _nm: Node
var _story: Node
var _mono: Node
var _events: Array[String] = []


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _seconds(s: float) -> void:
	await _frames(int(s * 60.0))


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[TASKS7 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(60)
	_player = get_first_node_in_group("player")
	_nm = root.get_node("NightManager")
	_story = root.get_node("NightTwoStory")
	_mono = root.get_node("Monologue")
	_nm.horror_event.connect(func(e: String) -> void: _events.append(e))

	await _test_night_starts()
	_test_wildlife()
	await _test_panic()
	await _test_door()

	print("[TASKS7 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


## As the bed does after Day 2: the alarm, Night 2 at 04:00, waking up.
func _test_night_starts() -> void:
	var gt: Node = root.get_node("GameTime")
	_nm.is_van_sequence_active = true
	_nm.van_sequence_started = true
	_nm.current_night = 2
	_nm.start_night(2)
	gt.cycle_progress = 0.9
	gt._elapsed = gt.cycle_progress * gt.cycle_duration
	gt.is_day = false
	gt.is_time_paused = true
	_nm.is_time_paused = false
	_nm.horror_event.emit("car_alarm")
	_story.on_woke_to_alarm()
	await _seconds(2.0)
	var wake: bool = _mono.has_thought("n22_wake")
	await _seconds(3.0)   # 5 s in: the noise has come by now
	var waited: bool = not _mono.has_thought("n22_noise") or _story._wake_until <= _story._clock
	await _seconds(1.5)
	var noise_thought: bool = _mono.has_thought("n22_noise")
	await _seconds(3.5)
	var alarm_thought: bool = _mono.has_thought("n22_alarm_power")
	var noise_came: bool = "entity_glimpse" in _events
	_check("8: waking: \"Why is the car alarm blaring?\"", wake)
	_check("8: the noise (footstep, murmur, creak) comes a few seconds after waking", noise_came, str(_events))
	_check("8: then \"What the fuck was that?!\" (after the wake thought), and 3 s later the alarm and the battery",
		waited and noise_thought and alarm_thought, "waited=%s noise=%s alarm=%s" % [waited, noise_thought, alarm_thought])


func _test_wildlife() -> void:
	var hsm: Node = root.get_node("HorrorSoundManager")
	hsm._update_silence(_player)
	var hushed: bool = hsm.wildlife_hushed() and hsm._night_ambience_player.volume_db <= -79.0
	hsm._distant_left = 0.0
	hsm._distant_player.stop()
	hsm._update_distant(0.2, _player)
	var no_calls: bool = not hsm._distant_player.playing
	# The chase over (it vanished): still quiet till morning.
	_nm.is_van_sequence_active = false
	var still: bool = hsm.wildlife_hushed()
	_nm.is_van_sequence_active = true
	_nm.current_night = 3
	_nm.van_sequence_started = false
	_nm.is_van_sequence_active = false
	var night3: bool = not hsm.wildlife_hushed()
	_nm.current_night = 2
	_nm.van_sequence_started = true
	_nm.is_van_sequence_active = true
	_check("9: Night 2.2: the forest falls silent (no night bed, no distant calls), till morning; Night 3 normal",
		hushed and no_calls and still and night3, "hushed=%s calls=%s still=%s n3=%s" % [hushed, no_calls, still, night3])


func _test_panic() -> void:
	var entity = get_first_node_in_group("entity")
	_player.global_position = Vector3(20.0, 1.0, 40.0)   # outside, in the yard
	entity.global_position = _player.global_position + Vector3(8.0, 0.0, 0.0)
	entity.van_chase_active = true
	_nm.first_chase_started.emit()
	await _seconds(3.0)
	var panic = _story._panic
	var popping: bool = panic != null and panic.active and panic.count() > 0
	var clear_middle := true
	var screen: Vector2 = panic.get_viewport().get_visible_rect().size if panic else Vector2.ONE
	if panic:
		for label in panic._shown:
			if is_instance_valid(label):
				var off: Vector2 = (label.position + label.size * 0.5) / screen - Vector2(0.5, 0.5)
				clear_middle = clear_middle and (absf(off.x) > panic.CLEAR_X or absf(off.y) > panic.CLEAR_Y)
	_check("11: chased: \"Oh fuck!\" pops up around the screen (%d now), never over the middle" % (panic.count() if panic else 0),
		popping and clear_middle)
	# Closer = more often.
	var near_rate := _rate(panic, 3.0)
	var far_rate := _rate(panic, 40.0)
	_check("11: more panic the closer it is (interval %.2f s near, %.2f s far)" % [near_rate, far_rate], near_rate < far_rate)
	_player.global_position = Vector3(10.0, 1.0, 13.0)   # the hall
	await _seconds(1.5)
	_check("11/12: inside: the panic stops; \"What the FUCK was that?!\"",
		not panic.active and panic.count() == 0 and _mono.has_thought("n22_inside"))


func _rate(panic, distance: float) -> float:
	var far := clampf(inverse_lerp(panic.NEAR, panic.FAR, distance), 0.0, 1.0)
	return lerpf(panic.INTERVAL_NEAR, panic.INTERVAL_FAR, far)


func _test_door() -> void:
	var door: Node = get_first_node_in_group("Door")
	door.set_state_quietly(false, false)
	# The thoughts gone first (say() never cuts a thought short).
	for i in 600:
		if not is_instance_valid(_mono._thought):
			break
		await physics_frame
	var locked: bool = door.story_locked
	door.interact()
	await _frames(2)
	var shut: bool = not door.is_open
	var stays: bool = shut and _mono._said == "There is no way I'm going outside now."
	_story._on_night_ended(2)
	var morning: bool = not door.story_locked
	door.interact()
	await _seconds(1.0)
	var opens: bool = door.is_open
	_check("13: inside after the chase with the door shut: it won't open (\"There is no way...\")", locked and stays,
		"locked=%s shut=%s said=%s" % [locked, shut, _mono._said])
	_check("13: Day 3: the door opens again", morning and opens)
	# A Night 2.2 restart (the alarm again): no lock before the chase.
	door.set_state_quietly(false, false)
	_nm.horror_event.emit("car_alarm")
	await _seconds(0.3)
	_check("13: after a restart at the van, the door isn't locked until the chase again", not door.story_locked)
