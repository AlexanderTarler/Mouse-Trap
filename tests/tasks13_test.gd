extends SceneTree
## planning/tasks.txt round 7, round A (planning/tasks_plan_r7.txt):
##   1  the bed is highlighted for "go to bed" only on Day 1 / Night 1
##   2  the cabin lights drain half as much
##   3  the Cabin Key is a key (its scene, its picture, dropping it), not the
##      fuel can its resource pointed at
##   4  the player's breathing 30% quieter
##   8  Arvid's second note: "it despises light"; 11: the recovery key is
##      Linnea_and_Maja (and the note says so)
##   10 the generator drains by day too
##   13 burning the willow: "I fucking did it. I fucking did it!"
##   15 back past the cabin afterwards: "It's actually gone. Thank you, Arvid."
##   19 the ending screens wrap on words
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/tasks13_test.gd

var _failures := 0
var _scene: Node
var _player: Node3D
var _nm: Node
var _rm: Node


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[TASKS13 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	await _frames(2)
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(90)
	_player = get_first_node_in_group("player")
	_nm = root.get_node("NightManager")
	_rm = root.get_node("RoutineManager")

	_test_bed_highlight()
	_test_static()
	await _test_day_drain()
	await _test_willow_thoughts()

	print("[TASKS13 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _test_bed_highlight() -> void:
	_nm.current_night = 0
	_rm._bed_highlighted = false
	_rm._update_bed_highlight("Go to bed.")
	var day1: bool = _rm._bed_highlighted
	_rm._update_bed_highlight("Turn off the lights")
	_nm.current_night = 2
	_rm._update_bed_highlight("Go to bed.")
	var night2: bool = _rm._bed_highlighted
	_nm.current_night = 3
	_rm._update_bed_highlight("Lock the door and go to bed.")
	var day3: bool = _rm._bed_highlighted
	_nm.current_night = 0
	_check("1: the bed is highlighted for going to bed on Day 1, not on Night 2 or Day 3",
		day1 and not night2 and not day3, "day 1 %s, night 2 %s, day 3 %s" % [day1, night2, day3])


func _test_static() -> void:
	var generator: Node = get_first_node_in_group("generator_controller")
	_check("2: the cabin lights drain half as much (%.3f, porch %.3f)" % [generator.cabin_light_drain_rate, generator.porch_light_drain_rate],
		is_equal_approx(generator.cabin_light_drain_rate, 0.125) and is_equal_approx(generator.porch_light_drain_rate, 0.075))

	var key: ItemData = load("res://resources/key_resource.tres")
	var pickup: Node = _scene.get_node("Key")
	_check("3: the Cabin Key's picture and what's dropped are the key, not the fuel can",
		key != null and ItemIcons._model_path(key) == "res://scenes/key.tscn"
		and pickup.item_data.scene_to_spawn != null and pickup.item_data.scene_to_spawn.resource_path == "res://scenes/key.tscn",
		pickup.item_data.scene_to_spawn.resource_path if pickup.item_data.scene_to_spawn else "none")

	var breathing: AudioStreamPlayer3D = _player._breathing_audio
	_check("4: the player's breathing is 30%% quieter (%.1f dB, was -16)" % _player.BREATHING_DB,
		is_equal_approx(_player.BREATHING_DB, -19.1) and breathing != null)

	var note: ItemData = load("res://resources/arvid_note_2.tres")
	_check("8: Arvid's note, by the girls: it despises light, use that", "despises light" in note.note_text and "Use that to your advantage" in note.note_text)
	var ui: Node = get_first_node_in_group("computer_ui")
	_check("11: the recovery key is Linnea_and_Maja (any case), and the note gives it",
		ui.ARVID_DECRYPTION_KEY == "Linnea_and_Maja" and "Linnea_and_Maja" in note.note_text and not "STENBERG_1996" in note.note_text)
	ui._key_input.text = "linnea_and_maja"
	ui._on_submit_decryption_key()
	_check("11: typing it in restores Arvid's logs", ui.is_arvid_log_1_unlocked)

	var screen: Control = load("res://scenes/ui/ending_screen.tscn").instantiate()
	var subtitle: Label = screen.get_node("VBoxContainer/SubtitleLabel")
	_check("19: the ending screens wrap on whole words", subtitle.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART)
	screen.free()


func _test_day_drain() -> void:
	var gt: Node = root.get_node("GameTime")
	_check("10: precondition: it's day", gt.is_day and not _nm.is_night_active)
	_nm.is_time_paused = false
	_nm.is_day_active = true
	_nm.generator_fuel = 50.0
	_nm.is_generator_on = true
	_nm.recalculate_fuel_drain()
	await _frames(120)
	_check("10: the generator burns fuel by day (%.2f left of 50)" % _nm.generator_fuel, _nm.generator_fuel < 49.9)


func _test_willow_thoughts() -> void:
	var monologue: Node = root.get_node("Monologue")
	_player.global_position = Vector3(100.0, 1.0, 80.0)   # at the willow
	await _frames(5)
	_rm.on_anchor_destroyed()
	# (A thought waits its turn behind one already on screen.)
	for i in 60 * 20:
		await _frames(1)
		if monologue.has_thought("willow_burned"):
			break
	_check("13: burning the willow: \"I fucking did it. I fucking did it!\"", monologue.has_thought("willow_burned"))
	await _frames(60 * 6)
	var not_yet: bool = not monologue.has_thought("willow_gone")
	_player.global_position = Vector3(20.0, 1.0, 20.0)   # back by the cabin
	for i in 60 * 20:
		await _frames(1)
		if monologue.has_thought("willow_gone"):
			break
	_check("15: back past the cabin afterwards: \"It's actually gone. Thank you, Arvid.\" (not before)",
		not_yet and monologue.has_thought("willow_gone"))
