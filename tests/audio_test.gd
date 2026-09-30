extends SceneTree
## Audio: every referenced sound exists, the manager's sound sets load, the
## buses and room reverb are set up, and the night soundscape behaves:
## indoor muffling, wind, the forest going quiet near the Entity, distant
## sounds, whistling broken windows, events placed around the player, stair
## footsteps and the chase music. Plus the Entity's and the house's own
## sounds: growls, climbing, floor creaks, knocks, plank blows, the flashlight
## click, stingers, the house settling and the tension drone.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/audio_test.gd

const HALL := Vector3(6.7, 0.75, 11.5)
const LANDING := Vector3(6.0, 3.73, 17.4)
const STAIRS := Vector3(3.575, 2.3, 11.9)
const YARD := Vector3(20.0, 0.3, 4.0)

var _failures := 0
var _scene: Node
var _player: CharacterBody3D
var _hsm: Node


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[AUDIO TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	_test_references()

	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(10)
	_player = get_first_node_in_group("player") as CharacterBody3D
	_player.set_physics_process(false)
	_hsm = root.get_node("HorrorSoundManager")
	var nm := root.get_node("NightManager")
	nm.is_time_paused = true
	var game_time := root.get_node_or_null("GameTime")
	if game_time:
		game_time.is_time_paused = true
	# Let the NightManager's delayed spawn setup place the player first.
	await _frames(60)

	_test_sound_sets()
	_test_buses_and_rooms()
	await _test_muffling()
	await _test_night_soundscape()
	_test_event_positions()
	await _test_footsteps()
	_test_chase_music()
	_test_entity_sound_sets()
	await _test_floor_creaks()
	_test_house_sounds()
	await _test_stingers_and_settling()
	await _test_tension()

	print("[AUDIO TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


# ─── References ──────────────────────────────────────────────────────────────

## Every literal audio path in a script or scene must exist.
func _test_references() -> void:
	var regex := RegEx.new()
	regex.compile("res://assets/audio/[^\"]+?\\.(ogg|wav|mp3)")
	var missing: Array[String] = []
	var checked := 0
	for file in _files("res://scripts", ".gd") + _files("res://scenes", ".tscn"):
		var text := FileAccess.get_file_as_string(file)
		for m in regex.search_all(text):
			var path := m.get_string()
			if "%" in path:
				continue   # a pattern, checked through the loaded sets below
			checked += 1
			if not ResourceLoader.exists(path):
				missing.append("%s -> %s" % [file.get_file(), path])
	_check("references: every audio file named in scripts and scenes exists (%d checked)" % checked,
		missing.is_empty(), ", ".join(missing))


func _files(dir: String, extension: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if not d:
		return out
	for f in d.get_files():
		if f.ends_with(extension):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_files(dir.path_join(sub), extension))
	return out


## The manager's sound sets load in full (these were silently empty).
func _test_sound_sets() -> void:
	var expected := {
		"_ambient_wind_streams": 9, "_wooden_footstep_streams": 8, "_stairs_footstep_streams": 8,
		"_creaking_door_streams": 12, "_monster_growl_streams": 12, "_grass_footstep_streams": 6,
		"_whisper_streams": 3, "_distant_forest_streams": 8, "_distant_roar_streams": 4,
	}
	var short: Array[String] = []
	for set_name in expected:
		var got: int = _hsm.get(set_name).size()
		if got != expected[set_name]:
			short.append("%s %d/%d" % [set_name, got, expected[set_name]])
	_check("sound sets: wind, footsteps, door creaks, growls, whispers and distant sounds all load", short.is_empty(), ", ".join(short))


func _test_buses_and_rooms() -> void:
	var interior := AudioServer.get_bus_index("Interior")
	var ambient := AudioServer.get_bus_index("Ambient")
	_check("buses: an Interior reverb bus and a muffling filter on the Ambient bus",
		interior >= 0 and _hsm._bus_effect(interior, "AudioEffectReverb") != null
		and _hsm._bus_effect(ambient, "AudioEffectLowPassFilter") != null)
	var rooms := get_nodes_in_group("Cabin_Interior").filter(func(n): return n is Area3D and n.has_method("is_lit"))
	var ringing := rooms.filter(func(r): return r.reverb_bus_enabled and r.reverb_bus_name == &"Interior")
	_check("rooms: every room sends its sounds to the Interior reverb", rooms.size() >= 7 and ringing.size() == rooms.size(),
		"%d of %d rooms" % [ringing.size(), rooms.size()])


func _cutoff() -> float:
	var low_pass: AudioEffectLowPassFilter = _hsm._bus_effect(AudioServer.get_bus_index("Ambient"), "AudioEffectLowPassFilter")
	return low_pass.cutoff_hz


func _stand(floor_pos: Vector3) -> void:
	_player.global_position = floor_pos + Vector3.DOWN * 0.25


func _test_muffling() -> void:
	_stand(HALL)
	await _frames(120)
	var hall := _cutoff()
	_stand(LANDING)
	await _frames(120)
	var landing := _cutoff()
	_stand(YARD)
	await _frames(120)
	var yard := _cutoff()
	_check("muffling: outside sounds are muffled indoors, less upstairs, open outdoors",
		hall < 1000.0 and landing > hall and landing < 2500.0 and yard > 10000.0,
		"hall %.0f Hz, landing %.0f Hz, yard %.0f Hz" % [hall, landing, yard])


func _test_night_soundscape() -> void:
	_stand(YARD)
	_hsm._on_night_started(3)
	await _frames(90)
	var winds: Array = _hsm._ambient_sounds
	_check("wind: two looping wind layers play at night and fade in",
		winds.size() == 2 and winds.all(func(w): return w.stream != null and w.playing and w.volume_db > -40.0),
		str(winds.map(func(w): return "%s %.0f dB" % [w.playing, w.volume_db])))

	# The Entity close by: the forest goes quiet.
	var entity = get_first_node_in_group("entity")
	entity.can_kill = false
	entity.activate()
	entity.request_state(entity.State.STUNNED)
	entity._teleport(_player.global_position + Vector3(6.0, 0.0, 0.0))
	await _frames(120)
	var quiet: float = _hsm._night_ambience_player.volume_db
	entity.deactivate()
	await _frames(60)
	var back: float = _hsm._night_ambience_player.volume_db
	_check("silence: the forest falls silent when the Entity is near, then slowly returns",
		quiet < -24.0 and back > quiet, "near %.0f dB, after it left %.0f dB" % [quiet, back])

	# A distant sound, somewhere around the player.
	_hsm._distant_left = 0.0
	await _frames(20)
	var distant: AudioStreamPlayer3D = _hsm._distant_player
	var d: float = Vector2(distant.global_position.x - _player.global_position.x,
		distant.global_position.z - _player.global_position.z).length()
	_check("distant: a far-off sound plays 30-45 m from the player", distant.stream != null and d >= 29.0 and d <= 46.0,
		"%s at %.1f m" % [distant.stream.resource_path.get_file() if distant.stream else "nothing", d])

	# A broken window whistles until it is boarded up.
	var window: Node = _scene.get_node("Windows/BottomFloorWindows/LivingRoomWindow")
	window.is_glass_shattered = true
	await _frames(20)
	var whistling: bool = window.has_node("WindWhistle")
	window.is_boarded = true
	await _frames(20)
	var stopped: bool = not window.has_node("WindWhistle")
	window.is_boarded = false
	window.is_glass_shattered = false
	_check("windows: wind whistles through a broken window, and stops once it is boarded",
		whistling and stopped, "whistling=%s, stopped after boarding=%s" % [whistling, stopped])
	_hsm._on_night_ended(3)


func _test_event_positions() -> void:
	_stand(YARD)
	for p in _hsm._event_players:
		p.stop()
	_hsm._on_horror_event("footsteps")
	var playing: Array = _hsm._event_players.filter(func(p): return p.playing)
	var near: bool = not playing.is_empty() and playing[0].global_position.distance_to(_player.global_position) < 6.0
	_check("events: scripted horror sounds play around the player (not at the map origin)", near,
		"at %s, player at %s" % [playing[0].global_position.snapped(Vector3.ONE * 0.1) if not playing.is_empty() else "none",
			_player.global_position.snapped(Vector3.ONE * 0.1)])


func _test_footsteps() -> void:
	_stand(STAIRS)
	await _frames(3)   # room overlaps update on the physics step
	_player._is_crouching = false
	_player._is_running = false
	_player._play_surface_footstep()
	var on_stairs: bool = _player.stairs_footsteps.has(_player.footstep_audio.stream)
	var walk_db: float = _player.footstep_audio.volume_db
	_player._is_crouching = true
	_player._play_surface_footstep()
	var crouch_db: float = _player.footstep_audio.volume_db
	_player._is_crouching = false
	_check("footsteps: stair steps on the stairs; crouching is quieter than walking",
		on_stairs and _player.stairs_footsteps.size() == 8 and crouch_db < walk_db - 5.0,
		"stairs=%s, walk %.1f dB, crouch %.1f dB" % [on_stairs, walk_db, crouch_db])


func _test_chase_music() -> void:
	_hsm.play_stalk_chase()
	var player: AudioStreamPlayer = _hsm._stalk_chase_player
	_check("chase music: the chase loop exists and starts", player != null and player.stream != null,
		player.stream.resource_path.get_file() if player and player.stream else "no player/stream")
	_hsm._stop_stalk_chase()


# ─── Entity, house and tension ──────────────────────────────────────────────

func _test_entity_sound_sets() -> void:
	var audio = get_first_node_in_group("entity").audio
	var expected := {
		"_growl_streams": 12, "_scrape_streams": 3, "_thud_streams": 3,
		"_creak_streams": 12, "_knock_streams": 3,
	}
	var short: Array[String] = []
	for set_name in expected:
		var got: int = audio.get(set_name).size()
		if got != expected[set_name]:
			short.append("%s %d/%d" % [set_name, got, expected[set_name]])
	if audio._murmur_streams.size() < 3:
		short.append("_murmur_streams %d" % audio._murmur_streams.size())
	_check("entity sounds: growls, climb scrapes, drop thuds, floor creaks, knocks and murmurs load",
		short.is_empty(), ", ".join(short))


## The Entity walking on the floor above the player makes the boards creak.
func _test_floor_creaks() -> void:
	var entity = get_first_node_in_group("entity")
	_stand(HALL)
	entity.activate()
	entity.request_state(entity.State.STUNNED)
	entity._teleport(LANDING)
	await _frames(10)
	var audio = entity.audio
	audio._creak_left = 0.0
	audio.update_floor_creaks(0.1, 2.0)
	var above: bool = audio._creak.playing
	audio._creak.stop()
	# On the same floor: no creaks.
	entity._teleport(HALL + Vector3(3.0, 0.0, 0.0))
	await _frames(10)
	audio._creak_left = 0.0
	audio.update_floor_creaks(0.1, 2.0)
	var same: bool = audio._creak.playing
	entity.deactivate()
	await _frames(5)
	_check("floor creaks: boards creak under the Entity on the other floor, not on the same one",
		above and not same, "above=%s, same floor=%s" % [above, same])


func _test_house_sounds() -> void:
	var window: Node = _scene.get_node("Windows/BottomFloorWindows/LivingRoomWindow")
	window.is_boarded = true
	window.is_glass_shattered = true
	window.planks_remaining = 3
	window.hits_on_current_plank = 0
	window.damage_barricade()
	var plank: AudioStreamPlayer3D = window.get_node_or_null("PlankHitSound")
	var hit_ok := plank != null and plank.stream != null and plank.playing
	_check("planks: a blow on a boarded window thuds", hit_ok,
		plank.stream.resource_path.get_file() if plank and plank.stream else "no sound")

	var flashlight: Node = null
	for node in _player.find_children("*", "", true, false):
		if node.has_method("toggle") and "battery_level" in node:
			flashlight = node
			break
	var clicked := false
	if flashlight:
		flashlight.toggle()
		clicked = flashlight._click_player != null and flashlight._click_player.playing
		flashlight.toggle()
	_check("flashlight: the switch clicks", clicked, "flashlight found=%s" % (flashlight != null))


func _test_stingers_and_settling() -> void:
	_hsm._stinger_cooldown = 0.0
	var first: bool = _hsm.play_stinger()
	var second: bool = _hsm.play_stinger()
	_check("stingers: one plays, and a second right after is held back by the cooldown",
		first and not second and _hsm._stinger_player.playing)

	_stand(HALL)
	_hsm._on_night_started(2)
	await _frames(30)
	for p in _hsm._event_players:
		p.stop()
	_hsm._settle_left = 0.0
	await _frames(20)
	var creaks: Array = _hsm._event_players.filter(func(p): return p.playing)
	var ok := false
	var detail := "nothing played"
	if not creaks.is_empty():
		var c: AudioStreamPlayer3D = creaks[0]
		var d := Vector2(c.global_position.x - _player.global_position.x, c.global_position.z - _player.global_position.z).length()
		ok = c.pitch_scale < 0.7 and d >= 2.9 and d <= 7.1
		detail = "pitch %.2f at %.1f m" % [c.pitch_scale, d]
	_check("house settling: a low board creak somewhere near the player indoors at night", ok, detail)
	_hsm._on_night_ended(2)


## The drone swells as the Entity closes in, and is gone by day.
func _test_tension() -> void:
	var entity = get_first_node_in_group("entity")
	_stand(YARD)
	_hsm._on_night_started(3)
	entity.activate()
	entity.request_state(entity.State.STUNNED)
	entity._teleport(_player.global_position + Vector3(40.0, 0.0, 0.0))
	await _frames(60)
	var far_db: float = _hsm._tension_player.volume_db
	entity._teleport(_player.global_position + Vector3(5.0, 0.0, 0.0))
	await _frames(240)
	var near_db: float = _hsm._tension_player.volume_db
	var near_playing: bool = _hsm._tension_player.playing
	entity.deactivate()
	_hsm._on_night_ended(3)
	await _frames(5)
	_check("tension: the drone swells as the Entity comes close, and stops by day",
		near_playing and near_db > far_db + 10.0 and near_db > -20.0 and not _hsm._tension_player.playing,
		"far %.0f dB, near %.0f dB" % [far_db, near_db])
