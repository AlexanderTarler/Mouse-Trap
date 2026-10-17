extends SceneTree
## planning/round8_plan.txt: gameplay and UX.
##   1 the opening says to play with headphones
##   2 what the Entity copies comes back slightly wrong (low; footsteps four,
##     one late)
##   3 low on fuel the generator coughs and the lit rooms brown out
##   4 the wristwatch: the game's time on a believable clock (06:00 at dawn,
##     20:00 at dusk), taught on the first night; the hall clock ticks
##   5 the notebook's "The Entity" chapter: what's been learned, kept by the
##     checkpoint
##   6 the house creaks, more each night, away from the player and the Entity
##   7 captions (when on), with a direction
##   8 the microphone: a loud moment is a noise the Entity hears, and the
##     Entity may play it back
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/round8_test.gd

var _failures := 0
var _scene: Node
var _player: CharacterBody3D
var _entity
var _nm: Node


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[ROUND8 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	# (The player's own settings put back afterwards; the microphone and
	# captions off to start, as by default.)
	var had_settings := FileAccess.file_exists("user://settings.cfg")
	var backup := FileAccess.get_file_as_bytes("user://settings.cfg") if had_settings else PackedByteArray()
	GameSettings.set_value("audio/microphone", false)
	GameSettings.set_value("accessibility/captions", false)
	await _frames(2)
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(120)
	_player = get_first_node_in_group("player")
	_entity = get_first_node_in_group("entity")
	_nm = root.get_node("NightManager")
	_entity.can_kill = false

	_test_headphones()
	_test_watch()
	await _test_journal()
	_test_captions()
	await _test_low_fuel()
	await _test_mimic_tell()
	await _test_house()
	await _test_microphone()

	print("[ROUND8 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	if had_settings:
		var file := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		file.store_buffer(backup)
		file.close()
	quit(1 if _failures > 0 else 0)


func _test_headphones() -> void:
	var opening := Opening.new()
	root.add_child(opening)
	_check("1: the opening's first card says to play with headphones",
		opening._headphones != null and "headphones" in opening._headphones.text.to_lower())
	opening.queue_free()


func _test_watch() -> void:
	var texts := [Wristwatch.clock_text(0.0), Wristwatch.clock_text(0.3), Wristwatch.clock_text(0.5), Wristwatch.clock_text(0.75), Wristwatch.clock_text(0.999)]
	_check("4: the watch reads the game's time on a real clock: dawn 06:00, Day 1's start 14:24, dusk 20:00, 01:00, nearly 06:00 (%s)" % ", ".join(texts),
		texts.slice(0, 4) == ["06:00", "14:24", "20:00", "01:00"] and texts[4].begins_with("05:5"))
	_check("4: the player has the watch, the hall clock ticks",
		_player.get_node_or_null("Wristwatch") != null and _scene.find_child("ClockTick", true, false) != null
		and (_scene.find_child("ClockTick", true, false) as AudioStreamPlayer3D).stream != null)
	var tm: Node = root.get_node("TutorialManager")
	_check("4: the watch is taught (its hint exists)", tm._find_tutorial("watch") != null)


func _test_journal() -> void:
	var notebook: Node = get_first_node_in_group("notebook_ui")
	var monologue: Node = root.get_node("Monologue")
	var empty: bool = notebook.entity_entry_count() == 0
	EntityJournal.learn(_scene, "beam")
	var after_one: int = notebook.entity_entry_count()
	EntityJournal.learn(_scene, "beam_harder")
	var rewritten: bool = notebook.entity_entry_count() == 1 and "longer" in notebook._entity_entries["beam"]
	EntityJournal.learn(_scene, "lit_room")
	_check("5: the Entity chapter starts empty, entries come as they're learned (the beam rewritten, not added)",
		empty and after_one == 1 and rewritten and notebook.entity_entry_count() == 2)
	_check("5: the index lists it", "The Entity" in notebook._index_label.text and "2 entries" in notebook._index_label.text)
	var page: String = notebook._all_pages[notebook._entity_start_page] if notebook._entity_start_page < notebook._all_pages.size() else ""
	_check("5: it's in the notebook, after the field notes", "THE ENTITY" in page and "lit room" in page)
	for i in 60 * 6:
		await _frames(1)
		if monologue.has_thought("entity_journal_first"):
			break
	_check("5: the first entry: \"I should write this down.\"", monologue.has_thought("entity_journal_first"))
	# The checkpoint keeps it.
	var checkpoint: Node = root.get_node("Checkpoint")
	checkpoint.capture("day")
	EntityJournal.learn(_scene, "ambush")
	checkpoint.restore()
	await _frames(5)
	_check("5: restoring a checkpoint puts the chapter back as it was", notebook.entity_entry_count() == 2 and not notebook.has_entity_entry("ambush"))
	# A real lesson: its ambush breath.
	_entity.audio.play_tell()
	_check("5: the ambush breath writes its entry", notebook.has_entity_entry("ambush"))


func _test_captions() -> void:
	var captions: Node = root.get_node("Captions")
	GameSettings.set_value("accessibility/captions", false)
	captions.last_text = ""
	Caption.text(_scene, "a car alarm")
	var silent: bool = captions.last_text == ""
	GameSettings.set_value("accessibility/captions", true)
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	Caption.at(_scene, "glass breaking", cam.global_position - cam.global_basis.z * 2.0)
	var ahead: String = captions.last_text
	Caption.at(_scene, "a breath", cam.global_position + cam.global_basis.z * 2.0)
	var behind: String = captions.last_text
	_check("7: captions off: nothing; on: \"%s\", \"%s\"" % [ahead, behind],
		silent and ahead == "[glass breaking, close ahead]" and behind == "[a breath, close behind]")


func _test_low_fuel() -> void:
	var generator: Node = get_first_node_in_group("generator_controller")
	generator.is_switched_on = true
	_nm.is_generator_on = true
	_nm.generator_fuel = 50.0
	generator.coughs = 0
	await _frames(60 * 10)
	var healthy: int = generator.coughs
	_nm.generator_fuel = 8.0
	generator._low_fuel_left = 0.0
	await _frames(60 * 2)
	_check("3: low on fuel the generator coughs (and the lit rooms brown out); not with a fuller tank",
		healthy == 0 and generator.coughs >= 1, "%d coughs at 50%%, %d at 8%%" % [healthy, generator.coughs])
	_nm.generator_fuel = 100.0


func _test_mimic_tell() -> void:
	_player.global_position = Vector3(12.2, 3.9, 17.4)   # upstairs, the bedroom
	await _frames(10)
	var audio: Node = _entity.audio
	audio.mimic("switch")
	var pitch: float = audio._decoy.pitch_scale
	_check("2: what it copies comes back low (%.2f, never the player's own 1.0)" % pitch, pitch < 0.95)
	_check("2: copied footsteps: four, one of them late", audio.MIMIC_STEPS == 4 and audio.MIMIC_LATE > 0.2)


func _test_house() -> void:
	var house: Node = _scene.find_child("HouseUnease", true, false)
	_player.global_position = Vector3(6.0, 1.0, 17.0)   # the living room
	await _frames(5)
	_nm.current_night = 3
	_nm.is_night_active = true
	var ok: bool = house.creak()
	var spot: Vector3 = house.last_spot
	var away: bool = spot.distance_to(_player.global_position) >= house.AWAY_FROM_PLAYER
	_check("6: at night the house creaks, in a room away from the player (%.1f m)" % spot.distance_to(_player.global_position), ok and away)
	_check("6: more often each night (Night 1 %.0f-%.0f s, Night 3 %.0f-%.0f s apart)" % [house.GAPS[0].x, house.GAPS[0].y, house.GAPS[2].x, house.GAPS[2].y],
		house.GAPS[2].x < house.GAPS[1].x and house.GAPS[1].x < house.GAPS[0].x and house.GAPS[2].y < house.GAPS[1].y and house.GAPS[1].y < house.GAPS[0].y)
	_nm.is_night_active = false
	house.played = 0
	await _frames(60)
	_check("6: not by day", house.played == 0)


func _test_microphone() -> void:
	var voice: PlayerVoice = _player.get_node("PlayerVoice")
	_check("8: off by default: not listening", GameSettings.DEFAULTS["audio/microphone"] == false and not PlayerVoice.enabled() and not voice.is_listening())
	# A loud moment (as if the microphone picked one up).
	_entity.activate()
	_entity._teleport(_player.global_position + Vector3(4.0, 0.0, 0.0))
	await _frames(5)
	voice.voice(PlayerVoice.threshold_db() + 20.0)
	var noise: Dictionary = _entity.perception.last_noise
	_check("8: a loud moment is a noise the Entity hears (a shout carries further)", noise.get("kind") == &"voice_loud" and noise.get("heard", false), str(noise.get("kind")))
	# Kept, and played back.
	var clip := AudioStreamWAV.new()
	voice.loud_clip = clip
	# (From the bedroom: from the middle of the living room every room is too
	# close to put a copied sound in.)
	_player.global_position = Vector3(12.2, 3.9, 17.4)
	await _frames(5)
	_nm.current_night = 3
	var played: bool = _entity.audio.mimic("voice")
	_check("8: it can play the player's own loud moment back, slightly off", played and _entity.audio._decoy.stream == clip and _entity.audio._decoy.pitch_scale < 0.95)
