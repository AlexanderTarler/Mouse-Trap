extends SceneTree
## Playtest fixes (planning/tasks.txt, after the save-state playtest):
##   - going to bed: only the yawn; no breathing (neither the cinematic's
##     own nor the out-of-breath loop carried in from running)
##   - Settings > Audio > Test Microphone: plays the microphone back (heard:
##     its own bus, not muted), off on a second press, another tab, leaving
##   - the first launch: after the brightness, the microphone and the
##     objective highlights, both off; highlights off by default too
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/playtest12_test.gd

const LEVEL := "res://scenes/cottage_horror.tscn"
const BREATHING := "res://assets/audio/objects/Player Breathing.ogg"

var _failures := 0


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("[PLAYTEST12 TEST] %s  %s" % ["PASS" if ok else "FAIL", label])


func _run() -> void:
	var settings_backup := {}
	for key in ["audio/microphone", "gameplay/objective_highlights", "video/calibrated"]:
		settings_backup[key] = GameSettings.get_value(key)

	# ─── The first launch ──────────────────────────────────────────────
	_check("objective highlights are off by default", GameSettings.DEFAULTS["gameplay/objective_highlights"] == false and GameSettings.DEFAULTS["audio/microphone"] == false)
	GameSettings.set_value("audio/microphone", true)
	GameSettings.set_value("gameplay/objective_highlights", true)
	GameSettings.set_value("video/calibrated", false)
	var calibration := BrightnessCalibration.new()
	calibration.first_launch = true
	var closed := [false]
	calibration.closed.connect(func(): closed[0] = true)
	root.add_child(calibration)
	await _frames(3)
	(calibration.find_child("DoneButton", true, false) as Button).pressed.emit()
	await _frames(3)
	var mic_check := calibration.find_child("SetupMicrophoneCheck", true, false) as CheckButton
	var hl_check := calibration.find_child("SetupHighlightsCheck", true, false) as CheckButton
	var texts := _texts(calibration)
	_check("after the brightness: the microphone and highlights, both off, and where to find them (%s)" % [texts.left(80)],
		not closed[0] and mic_check and hl_check and not mic_check.button_pressed and not hl_check.button_pressed
		and GameSettings.get_value("audio/microphone") == false and GameSettings.get_value("gameplay/objective_highlights") == false
		and "Settings" in texts and "Audio" in texts and "Accessibility" in texts)
	hl_check.button_pressed = true
	(calibration.find_child("SetupDoneButton", true, false) as Button).pressed.emit()
	await _frames(3)
	_check("a choice made there is kept, and Done closes it (calibrated)", closed[0] and GameSettings.get_value("gameplay/objective_highlights") == true and GameSettings.get_value("video/calibrated") == true)
	# From Options > Video > Calibrate (not the first launch): no second page.
	var again := BrightnessCalibration.new()
	var closed_again := [false]
	again.closed.connect(func(): closed_again[0] = true)
	root.add_child(again)
	await _frames(3)
	(again.find_child("DoneButton", true, false) as Button).pressed.emit()
	await _frames(3)
	_check("Calibrate from Settings: Done closes at once", closed_again[0])

	# ─── Test Microphone ───────────────────────────────────────────────
	GameSettings.set_value("audio/microphone", false)
	var menu: Node = load("res://scenes/ui/options_menu.tscn").instantiate()
	root.add_child(menu)
	menu.show_menu()
	await _frames(5)
	var test := menu.find_child("MicTestButton", true, false) as Button
	test.button_pressed = true
	await _frames(70)
	var listener: PlayerVoice = menu._mic_listener
	var heard_back: bool = is_instance_valid(listener._monitor_player) and listener._monitor_player.playing and listener._monitor_player.stream is AudioStreamGenerator
	_check("Test on: listening with the microphone setting off, played back (listening %s, playback %s, input users %d)" % [listener.is_listening(), heard_back, PlayerVoice._users],
		listener.monitor and listener.is_listening() and heard_back and PlayerVoice._users == 1)
	# The microphone's input shared: a second listener (the player's, in the
	# game) on and off again doesn't switch it off under the Test (it did:
	# the Test heard you once, then never again).
	var other := PlayerVoice.new()
	other.monitor = true   # (listens with the setting off, as the Test does)
	root.add_child(other)
	await _frames(70)
	var both := PlayerVoice._users
	other.queue_free()
	await _frames(5)
	_check("another listener comes and goes: the Test still listens, the input still on (users %d, then %d)" % [both, PlayerVoice._users],
		both == 2 and PlayerVoice._users == 1 and listener.is_listening() and listener._monitor_player.playing)
	test.button_pressed = false
	await _frames(70)
	_check("Test pressed again: off (not listening, the microphone being off; input off)", not listener.monitor and not listener.is_listening() and test.text == "Test" and PlayerVoice._users == 0 and not is_instance_valid(listener._monitor_player))
	test.button_pressed = true
	await _frames(5)
	menu._tabs.current_tab = 1
	await _frames(5)
	_check("another tab: Test off", not test.button_pressed and not listener.monitor)
	menu._tabs.current_tab = 0
	test.button_pressed = true
	await _frames(5)
	menu.hide_menu()
	await _frames(5)
	_check("leaving the menu: Test off", not test.button_pressed and not listener.monitor)
	menu.queue_free()

	# ─── Bed: only the yawn ────────────────────────────────────────────
	change_scene_to_file(LEVEL)
	await _frames(150)
	var player := get_first_node_in_group("player") as Node3D
	# Out of breath from running.
	if player._breathing_audio:
		player._breathing_audio.play()
	# (As the bed starts it.)
	var bed: Node = null
	for node in current_scene.find_children("*", "", true, false):
		if node.has_method("_sleep_cinematic"):
			bed = node
			break
	var cinematic: SleepCinematic = bed._sleep_cinematic()
	cinematic.fall_asleep(player)
	await _frames(20)
	var breathing_players := 0
	var yawns := 0
	for node in root.find_children("*", "AudioStreamPlayer", true, false):
		var sound := node as AudioStreamPlayer
		if sound.playing and sound.stream and sound.stream.resource_path == BREATHING:
			breathing_players += 1
		if sound.name == "Yawn":
			yawns += 1
	var stamina_breathing: bool = player._breathing_audio != null and player._breathing_audio.playing
	_check("lying down: the yawn (%d), no breathing (%d cinematic, out-of-breath loop %s)" % [yawns, breathing_players, stamina_breathing],
		yawns == 1 and breathing_players == 0 and not stamina_breathing)

	for key in settings_backup:
		GameSettings.set_value(key, settings_backup[key])
	print("[PLAYTEST12 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _texts(node: Node) -> String:
	var out := ""
	for label in node.find_children("*", "Label", true, false):
		out += (label as Label).text + " "
	return out
