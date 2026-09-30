extends Node

## Manages all horror sound effects and ambient audio.
## Plays sounds based on NightManager events and entity proximity.
##
## THE NIGHT SOUNDSCAPE (updated 5x a second in _process):
##   - Forest bed (night ambience) that falls silent when the Entity is near.
##   - Two looping wind layers that swell with the fog, louder upstairs.
##   - Occasional distant sounds around the player: wood cracking, things
##     falling, and (from Night 3) far-off roars.
##   - Wind whistling at broken, unboarded windows.
##   - The house settling: now and then an old board creaks near the player
##     while they are inside.
##   - A tension drone that rises as the Entity gets closer or bolder (and
##     steps aside for the chase music).
##   - Stingers: the first time each night the player sees the Entity, and
##     when it kills a light (play_stinger, with a cooldown).
##   - Indoors, everything outside (the Ambient bus) is muffled: a low-pass
##     filter and a volume dip, less so upstairs.
## Sounds made inside the cabin get a small wooden-room reverb: every
## CabinRoom sends 3D audio to the "Interior" bus set up here.
##
## Streams are checked with ResourceLoader.exists(), which also works in
## exported builds (ResourceLoader.exists() doesn't see imported audio there).

signal sound_played(sound_name: String)

# Audio file paths
const HORROR_SFX_DIR: String = "res://assets/audio/horror_sfx_vol_1/"
const ECHOES_DIR: String = "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/"
const AMBIENT_WIND_DIR: String = HORROR_SFX_DIR + "Ambient Wind/"
const CARPET_FOOTSTEP_DIR: String = HORROR_SFX_DIR + "Carpet Footstep/"
const CONCRETE_FOOTSTEP_DIR: String = HORROR_SFX_DIR + "Concrete Footsteps/"
const GRAVEL_FOOTSTEP_DIR: String = HORROR_SFX_DIR + "Gravel Footsteps/"
const LEAVES_FOOTSTEP_DIR: String = HORROR_SFX_DIR + "Leaves Footsteps/"
const METAL_FOOTSTEP_DIR: String = HORROR_SFX_DIR + "Metal Footsteps/"
const MUD_FOOTSTEP_DIR: String = HORROR_SFX_DIR + "Mud foosteps/"
const STAIRS_FOOTSTEP_DIR: String = HORROR_SFX_DIR + "Stairs Footsteps/"
const WIND_FOOTSTEP_DIR: String = HORROR_SFX_DIR + "Wind Footsteps/"
const WOODEN_FOOTSTEP_DIR: String = HORROR_SFX_DIR + "Wooden Foosteps/"
const GRASS_FOOTSTEP_DIR: String = "res://assets/audio/40 Free PSX Footsteps/Grass/"
const CREAKING_DOOR_DIR: String = HORROR_SFX_DIR + "Creaking Door/"
const MONSTER_GROWL_DIR: String = HORROR_SFX_DIR + "Monster Growl/"
## Low murmurs for the Entity's "whisper" (it used to borrow wind clips).
const WHISPER_PATHS: Array[String] = [
	ECHOES_DIR + "SFX/Creatures/Monster/monster_talking_1.ogg",
	ECHOES_DIR + "SFX/Creatures/Monster/monster_talking_2.ogg",
	ECHOES_DIR + "SFX/Creatures/Monster/monster_talking_3.ogg",
]
## Distant night sounds around the player (every night).
const DISTANT_FOREST_PATHS: Array[String] = [
	ECHOES_DIR + "SFX/Misc/crack_1_wood.ogg",
	ECHOES_DIR + "SFX/Misc/crack_2_wood.ogg",
	ECHOES_DIR + "SFX/Misc/fall_distant_1.ogg",
	ECHOES_DIR + "SFX/Impacts/impact_distant_1.ogg",
	ECHOES_DIR + "SFX/Impacts/impact_distant_2.ogg",
	ECHOES_DIR + "SFX/Impacts/impact_distant_3.ogg",
	ECHOES_DIR + "SFX/Impacts/impact_distant_4.ogg",
	ECHOES_DIR + "SFX/Impacts/impact_distant_5.ogg",
]
## Far-off roars, from Night 3 (and never while the Entity is close).
const DISTANT_ROAR_PATHS: Array[String] = [
	ECHOES_DIR + "SFX/Creatures/Monster/monster_roar_distant_1.ogg",
	ECHOES_DIR + "SFX/Creatures/Monster/monster_roar_distant_3.ogg",
	ECHOES_DIR + "SFX/Creatures/Monster/monster_roar_distant_5.ogg",
	ECHOES_DIR + "SFX/Creatures/Monster/monster_roar_distant_7.ogg",
]

## Short horror stingers.
const STINGER_PATHS: Array[String] = [
	ECHOES_DIR + "Bonus/Pure Horror/One-shots/stinger_ph_1.ogg",
	ECHOES_DIR + "Bonus/Pure Horror/One-shots/stinger_ph_2.ogg",
	ECHOES_DIR + "Bonus/Pure Horror/One-shots/stinger_ph_3.ogg",
	ECHOES_DIR + "Bonus/Pure Horror/One-shots/stinger_ph_4.ogg",
	ECHOES_DIR + "Bonus/Pure Horror/One-shots/stinger_ph_5.ogg",
	ECHOES_DIR + "Bonus/Pure Horror/One-shots/stinger_ph_6.ogg",
]
## The tension drone (a low sub-tone loop).
const TENSION_PATH: String = ECHOES_DIR + "Bonus/Pure Horror/Loops/sub_tones_loop_1.ogg"

# ─── Soundscape tuning ──────────────────────────────────────────────────────
const SOUNDSCAPE_INTERVAL := 0.2
## Ambient bus low-pass cutoff (Hz): outdoors, ground floor, upstairs.
const OPEN_CUTOFF := 20000.0
const INDOOR_CUTOFF := 700.0
const UPSTAIRS_CUTOFF := 1500.0
## Ambient bus volume dip indoors (dB).
const INDOOR_DUCK_DB := -5.0
const UPSTAIRS_DUCK_DB := -3.0
## Wind layers: base volume, per-night increase, fog swell and upstairs boost (dB).
const WIND_BASE_DB := -20.0
const WIND_PER_NIGHT_DB := 1.5
const WIND_MAX_DB := -8.0
const WIND_FOG_DB := 5.0
const WIND_UPSTAIRS_DB := 3.0
## The forest goes quiet when the Entity is this close (m).
const SILENCE_DISTANCE := 14.0
const NIGHT_AMBIENCE_DB := -12.0
const SILENCED_AMBIENCE_DB := -30.0
## Seconds between distant sounds, and how far away they are (m).
const DISTANT_INTERVAL_MIN := 25.0
const DISTANT_INTERVAL_MAX := 55.0
const DISTANT_RANGE_MIN := 30.0
const DISTANT_RANGE_MAX := 45.0
const DISTANT_ROAR_CHANCE := 0.3
## Whistling wind at a broken window.
const WHISTLE_DB := -10.0
## Stingers never closer together than this (s).
const STINGER_COOLDOWN := 40.0
const STINGER_DB := -4.0
## The house settling while the player is inside: one creak every so often,
## this far from the player (m).
const SETTLE_INTERVAL_MIN := 30.0
const SETTLE_INTERVAL_MAX := 70.0
const SETTLE_RANGE_MIN := 3.0
const SETTLE_RANGE_MAX := 7.0
## Tension: full within TENSION_NEAR m, nothing beyond TENSION_FAR m; its
## boldness (confidence) adds up to TENSION_CONFIDENCE_SHARE on its own.
const TENSION_NEAR := 6.0
const TENSION_FAR := 30.0
const TENSION_CONFIDENCE_SHARE := 0.4
const TENSION_SILENT_DB := -50.0
const TENSION_FULL_DB := -12.0

# Night wind layers (2D, on the Ambient bus)
var _ambient_sounds: Array[AudioStreamPlayer] = []

# Horror event sound pool
var _event_players: Array[AudioStreamPlayer3D] = []

# Entity proximity sounds (2D - always audible)
var _entity_whisper: AudioStreamPlayer = null

# Preloaded audio streams
var _ambient_wind_streams: Array[AudioStream] = []
var _wooden_footstep_streams: Array[AudioStream] = []
var _carpet_footstep_streams: Array[AudioStream] = []
var _concrete_footstep_streams: Array[AudioStream] = []
var _gravel_footstep_streams: Array[AudioStream] = []
var _leaves_footstep_streams: Array[AudioStream] = []
var _metal_footstep_streams: Array[AudioStream] = []
var _mud_footstep_streams: Array[AudioStream] = []
var _stairs_footstep_streams: Array[AudioStream] = []
var _wind_footstep_streams: Array[AudioStream] = []
var _grass_footstep_streams: Array[AudioStream] = []
var _creaking_door_streams: Array[AudioStream] = []
var _monster_growl_streams: Array[AudioStream] = []

# Whether sound is muted
var _muted: bool = false

var _whisper_streams: Array[AudioStream] = []
var _distant_forest_streams: Array[AudioStream] = []
var _distant_roar_streams: Array[AudioStream] = []

# Soundscape state
var _is_night := false
var _night := 0
var _soundscape_left := 0.0
var _distant_left := 30.0
var _distant_player: AudioStreamPlayer3D = null
var _whistles: Dictionary = {}   ## CabinWindow -> AudioStreamPlayer3D
var _muffle_cutoff := OPEN_CUTOFF
var _muffle_db := 0.0
var _silence_db := NIGHT_AMBIENCE_DB
var _stinger_streams: Array[AudioStream] = []
var _stinger_player: AudioStreamPlayer = null
var _stinger_cooldown := 0.0
var _seen_tonight := false
var _settle_left := 45.0
var _tension_player: AudioStreamPlayer = null
var _tension := 0.0

# Distant monster music player (plays when night starts)
var _distant_monster_player: AudioStreamPlayer = null
var _distant_monster_streams: Array[AudioStream] = []

# ─── TASK 2: STALK CHASE AUDIO ──────────────────────────────────────────
# Dedicated 2D chase track that plays while the Entity is in the STALK state
# AND the player is within 30m. Uses tween-based fade so re-entry near the
# player resumes the track cleanly instead of restarting from the beginning.
var _stalk_chase_player: AudioStreamPlayer = null
var _stalk_chase_streams: Array[AudioStream] = []
var _stalk_chase_playing: bool = false
var _stalk_chase_fade_tween: Tween = null
## The chase loop ("monster_stalk_mx.ogg" never existed; this is the kit's).
const STALK_CHASE_PATH: String = ECHOES_DIR + "Soundtracks/death close by (loop).ogg"
const STALK_CHASE_FADE_TIME: float = 0.5

# Day/Night forest ambience players
var _day_ambience_player: AudioStreamPlayer = null
var _night_ambience_player: AudioStreamPlayer = null
const DAY_AMBIENCE_PATH: String = "res://assets/audio/Ambience/Forest Ambience.ogg"
const NIGHT_AMBIENCE_PATH: String = "res://assets/audio/Ambience/Forest_night_ambience.ogg"

func _ready() -> void:
	_setup_audio_buses()
	_preload_audio_files()
	_setup_ambient_sounds()
	_setup_event_sounds()
	_setup_entity_sounds()
	_setup_distant_monster_sounds()
	_setup_stalk_chase_sounds()
	_setup_forest_ambience()
	_connect_signals()

func _setup_audio_buses() -> void:
	var ambient_exists = false
	var sfx_exists = false
	var entity_exists = false
	
	for i in AudioServer.bus_count:
		var name = AudioServer.get_bus_name(i)
		if name == "Ambient":
			ambient_exists = true
		elif name == "SFX":
			sfx_exists = true
		elif name == "Entity":
			entity_exists = true
	
	if not ambient_exists:
		var idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Ambient")
		AudioServer.set_bus_volume_db(idx, linear_to_db(0.3))
	
	if not sfx_exists:
		var sfx_idx = AudioServer.bus_count
		AudioServer.add_bus(sfx_idx)
		AudioServer.set_bus_name(sfx_idx, "SFX")
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(0.8))
	
	if not entity_exists:
		var entity_idx = AudioServer.bus_count
		AudioServer.add_bus(entity_idx)
		AudioServer.set_bus_name(entity_idx, "Entity")
		AudioServer.set_bus_volume_db(entity_idx, linear_to_db(0.6))

	# Indoors, outside sounds are muffled: a low-pass filter and a volume dip
	# on the Ambient bus (opened/closed by the soundscape tick).
	var ambient_idx := AudioServer.get_bus_index("Ambient")
	if _bus_effect(ambient_idx, "AudioEffectLowPassFilter") == null:
		var low_pass := AudioEffectLowPassFilter.new()
		low_pass.cutoff_hz = OPEN_CUTOFF
		AudioServer.add_bus_effect(ambient_idx, low_pass)
	if _bus_effect(ambient_idx, "AudioEffectAmplify") == null:
		AudioServer.add_bus_effect(ambient_idx, AudioEffectAmplify.new())

	# A small wooden room: CabinRooms send 3D audio made inside them here.
	if AudioServer.get_bus_index("Interior") < 0:
		var interior_idx := AudioServer.bus_count
		AudioServer.add_bus(interior_idx)
		AudioServer.set_bus_name(interior_idx, "Interior")
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.28
		reverb.damping = 0.75
		reverb.spread = 0.6
		reverb.hipass = 0.15
		reverb.dry = 0.0
		reverb.wet = 1.0
		AudioServer.add_bus_effect(interior_idx, reverb)


func _bus_effect(bus_idx: int, effect_class: String) -> AudioEffect:
	if bus_idx < 0:
		return null
	for i in AudioServer.get_bus_effect_count(bus_idx):
		var effect := AudioServer.get_bus_effect(bus_idx, i)
		if effect.is_class(effect_class):
			return effect
	return null

## Preloads all audio files from the horror_sfx_vol_1 asset pack.
func _preload_audio_files() -> void:
	# Ambient wind (files: "Ambient Wind (1).mp3" through "Ambient Wind (9).mp3")
	_ambient_wind_streams = _load_audio_files(AMBIENT_WIND_DIR, "Ambient Wind", 9)
	
	# Footstep types
	_wooden_footstep_streams = _load_audio_files(WOODEN_FOOTSTEP_DIR, "Wooden Foosteps", 8)
	_carpet_footstep_streams = _load_audio_files(CARPET_FOOTSTEP_DIR, "Carpet Footstep", 4)
	_concrete_footstep_streams = _load_audio_files(CONCRETE_FOOTSTEP_DIR, "Concrete Footsteps", 4)
	_gravel_footstep_streams = _load_audio_files(GRAVEL_FOOTSTEP_DIR, "Gravel Footsteps", 8)
	_leaves_footstep_streams = _load_audio_files(LEAVES_FOOTSTEP_DIR, "Leaves Footsteps", 4)
	_metal_footstep_streams = _load_audio_files(METAL_FOOTSTEP_DIR, "Metal Footsteps", 4)
	_mud_footstep_streams = _load_audio_files(MUD_FOOTSTEP_DIR, "Mud Footsteps", 8)
	_stairs_footstep_streams = _load_audio_files(STAIRS_FOOTSTEP_DIR, "Stair Footsteps", 8)
	_wind_footstep_streams = _load_audio_files(WIND_FOOTSTEP_DIR, "Wind Footsteps", 4)
	
	# Creaking doors (files: "Creaking Door (1).mp3" through "Creaking Door (12).mp3")
	_creaking_door_streams = _load_audio_files(CREAKING_DOOR_DIR, "Creaking Door", 12)
	
	# Monster growls (files: "Monster Growl (1).mp3" through "Monster Growl (12).mp3")
	_monster_growl_streams = _load_audio_files(MONSTER_GROWL_DIR, "Monster Growl", 12)
	
	# Grass footsteps (files: "Footstep Grass 1.ogg" through "Footstep Grass 6.ogg")
	_grass_footstep_streams = _load_audio_files_custom(GRASS_FOOTSTEP_DIR, "Footstep Grass", 6, ".ogg")

	_whisper_streams = _load_paths(WHISPER_PATHS)
	_distant_forest_streams = _load_paths(DISTANT_FOREST_PATHS)
	_distant_roar_streams = _load_paths(DISTANT_ROAR_PATHS)
	_stinger_streams = _load_paths(STINGER_PATHS)
	
	print("HorrorSoundManager: Loaded %d ambient wind, %d wooden footsteps, %d grass footsteps, %d door creaks, %d monster growls" % [
		_ambient_wind_streams.size(),
		_wooden_footstep_streams.size(),
		_grass_footstep_streams.size(),
		_creaking_door_streams.size(),
		_monster_growl_streams.size()
	])

## Loads audio files using the exact naming pattern: "{filename_prefix} ({n}).mp3"
## Uses ResourceLoader.exists() to silently skip missing files without
## triggering the engine's broken path loader warnings in the debugger console.
func _load_audio_files(dir_path: String, filename_prefix: String, count: int) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for i in range(1, count + 1):
		var path = dir_path + filename_prefix + " (%d).mp3" % i
		if not ResourceLoader.exists(path):
			continue  # Silently skip — no warning printed to debugger
		var stream = load(path) as AudioStream
		if stream:
			streams.append(stream)
	return streams

## Loads audio files with a custom naming pattern: "{filename_prefix} {n}{extension}"
## Uses ResourceLoader.exists() to silently skip missing files without
## triggering the engine's broken path loader warnings in the debugger console.
func _load_audio_files_custom(dir_path: String, filename_prefix: String, count: int, extension: String) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for i in range(1, count + 1):
		var path = dir_path + filename_prefix + " %d%s" % [i, extension]
		if not ResourceLoader.exists(path):
			continue  # Silently skip — no warning printed to debugger
		var stream = load(path) as AudioStream
		if stream:
			streams.append(stream)
	return streams

func _load_paths(paths: Array[String]) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for path in paths:
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream:
				streams.append(stream)
		else:
			push_warning("HorrorSoundManager: missing audio " + path)
	return streams


## Gets a random stream from an array.
func _get_random_stream(streams: Array[AudioStream]) -> AudioStream:
	if streams.is_empty():
		return null
	return streams[randi() % streams.size()]

## Two night wind layers. They were 3D players left at the world origin
## (15 m from the cabin, 20 m range), so they were barely audible; wind is
## all around, so they are plain 2D players now.
func _setup_ambient_sounds() -> void:
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = "Ambient"
		player.volume_db = -80.0
		add_child(player)
		_ambient_sounds.append(player)
	_distant_player = AudioStreamPlayer3D.new()
	_distant_player.bus = "Ambient"
	_distant_player.unit_size = 12.0
	_distant_player.max_distance = 90.0
	add_child(_distant_player)
	_stinger_player = AudioStreamPlayer.new()
	_stinger_player.bus = "SFX"
	_stinger_player.volume_db = STINGER_DB
	add_child(_stinger_player)
	_tension_player = AudioStreamPlayer.new()
	_tension_player.bus = "Entity"
	_tension_player.volume_db = TENSION_SILENT_DB
	if ResourceLoader.exists(TENSION_PATH):
		var drone := (load(TENSION_PATH) as AudioStream).duplicate()
		_set_loop(drone)
		_tension_player.stream = drone
	add_child(_tension_player)

func _setup_event_sounds() -> void:
	for i in 8:
		var player = AudioStreamPlayer3D.new()
		player.bus = "SFX"
		player.max_distance = 15.0
		add_child(player)
		_event_players.append(player)

func _setup_entity_sounds() -> void:
	_entity_whisper = AudioStreamPlayer.new()
	_entity_whisper.bus = "Entity"
	_entity_whisper.volume_db = -15.0
	add_child(_entity_whisper)

## Sets up the day/night forest ambience players.
## Day ambience plays "Forest Ambience.ogg" on loop during daytime.
## Night ambience plays "Forest_night_ambience.ogg" on loop during nighttime.
## Uses ResourceLoader.exists() to silently skip missing files without
## triggering the engine's broken path loader warnings in the debugger console.
func _setup_forest_ambience() -> void:
	# Day ambience player
	_day_ambience_player = AudioStreamPlayer.new()
	_day_ambience_player.bus = "Ambient"
	_day_ambience_player.volume_db = -12.0
	if ResourceLoader.exists(DAY_AMBIENCE_PATH):
		var day_stream = load(DAY_AMBIENCE_PATH) as AudioStream
		if day_stream:
			if day_stream is AudioStreamOggVorbis:
				day_stream.loop = true
			_day_ambience_player.stream = day_stream
	add_child(_day_ambience_player)
	
	# Night ambience player
	_night_ambience_player = AudioStreamPlayer.new()
	_night_ambience_player.bus = "Ambient"
	_night_ambience_player.volume_db = -12.0
	if ResourceLoader.exists(NIGHT_AMBIENCE_PATH):
		var night_stream = load(NIGHT_AMBIENCE_PATH) as AudioStream
		if night_stream:
			if night_stream is AudioStreamOggVorbis:
				night_stream.loop = true
			_night_ambience_player.stream = night_stream
	add_child(_night_ambience_player)
	
	# Start with day ambience (game starts in daytime)
	_play_day_ambience()
	print("HorrorSoundManager: Forest ambience set up.")


## Plays the day forest ambience on loop and stops night ambience.
func _play_day_ambience() -> void:
	if _night_ambience_player and _night_ambience_player.playing:
		_night_ambience_player.stop()
	if _day_ambience_player and _day_ambience_player.stream:
		_day_ambience_player.play()
		print("HorrorSoundManager: Playing day forest ambience.")


## Plays the night forest ambience on loop and stops day ambience.
func _play_night_ambience() -> void:
	if _day_ambience_player and _day_ambience_player.playing:
		_day_ambience_player.stop()
	if _night_ambience_player and _night_ambience_player.stream:
		_night_ambience_player.play()
		print("HorrorSoundManager: Playing night forest ambience.")


func _connect_signals() -> void:
	# NightManager is registered as an autoload, so it's a child of the root node.
	# Use get_node to access it, with a deferred call to ensure it's initialized.
	call_deferred("_deferred_connect_night_manager")


func _deferred_connect_night_manager() -> void:
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		nm.night_started.connect(_on_night_started)
		nm.night_ended.connect(_on_night_ended)
		nm.horror_event.connect(_on_horror_event)
		print("HorrorSoundManager: Connected to NightManager signals")
	else:
		print("HorrorSoundManager: NightManager not found via /root/NightManager")
		# Retry next frame in case NightManager isn't ready yet
		call_deferred("_deferred_connect_night_manager")

func _on_night_started(night: int) -> void:
	_is_night = true
	_night = night
	_seen_tonight = false
	_settle_left = randf_range(SETTLE_INTERVAL_MIN, SETTLE_INTERVAL_MAX) * 0.5
	_distant_left = randf_range(DISTANT_INTERVAL_MIN, DISTANT_INTERVAL_MAX) * 0.5
	_play_ambient()
	# Switch to night forest ambience
	_play_night_ambience()
	# Night 1 & Night 2 exceptions: The distant monster sound is suppressed
	# for Night 1 (car alarm narrative), Night 2.1 (nest-upload cinematic
	# time-skip), and Night 2.2 (van car-alarm narrative). The howl will
	# play when the corresponding chase sequence fires instead.
	if night <= 2:
		print("HorrorSoundManager: Night %d — suppressing distant monster sound." % night)
	else:
		var nm_check = get_node_or_null("/root/NightManager")
		if nm_check and nm_check.get("is_van_sequence_active") == true:
			print("HorrorSoundManager: Van sequence active — suppressing distant monster sound.")
		else:
			# Play the distant monster sound when night starts
			play_distant_monster()

func _on_night_ended(_night: int) -> void:
	_is_night = false
	_stop_whistles()
	_tension = 0.0
	if _tension_player:
		_tension_player.stop()
		_tension_player.volume_db = TENSION_SILENT_DB
	if _distant_player:
		_distant_player.stop()
	_silence_db = NIGHT_AMBIENCE_DB
	if _night_ambience_player:
		_night_ambience_player.volume_db = NIGHT_AMBIENCE_DB
	_stop_ambient()
	_stop_entity_sounds()
	_stop_distant_monster()
	_stop_stalk_chase()
	# Switch back to day forest ambience
	_play_day_ambience()

func _on_horror_event(event_name: String) -> void:
	match event_name:
		"distant_sound":
			_play_event_sound_3d(_get_random_stream(_creaking_door_streams), Vector3(0, 1, -8))
		"shadow_outside":
			_play_event_sound_3d(_get_random_stream(_ambient_wind_streams), Vector3(0, 1, -6))
		"entity_glimpse":
			_play_event_sound_3d(_get_random_stream(_wooden_footstep_streams), Vector3(3, 1, -5))
			_play_whisper()
		"door_creak":
			_play_event_sound_3d(_get_random_stream(_creaking_door_streams), Vector3(0, 1, 4))
		"entity_inside":
			_play_event_sound_3d(_get_random_stream(_wooden_footstep_streams), Vector3(-2, 1, 2))
		"object_moved":
			_play_event_sound_3d(_get_random_stream(_creaking_door_streams), Vector3(1, 0.5, -1))
		"footsteps":
			_play_event_sound_3d(_get_random_stream(_wooden_footstep_streams), Vector3(0, 1, 3))
		"entity_appears":
			_play_event_sound_3d(_get_random_stream(_monster_growl_streams), Vector3(0, 1, -4))
		"lights_flicker":
			_play_event_sound_3d(_get_random_stream(_creaking_door_streams), Vector3(0, 1, -3))
		"entity_charge":
			_play_event_sound_3d(_get_random_stream(_monster_growl_streams), Vector3(0, 1, -2))
		"entity_constant":
			_play_whisper()
		"poltergeist":
			_play_event_sound_3d(_get_random_stream(_creaking_door_streams), Vector3(0, 1, 0))
		"final_confrontation":
			_play_event_sound_3d(_get_random_stream(_monster_growl_streams), Vector3(0, 1, -3))

func _play_ambient() -> void:
	if _ambient_sounds.is_empty() or _ambient_wind_streams.is_empty():
		return
	var pool := _ambient_wind_streams.duplicate()
	pool.shuffle()
	for i in range(_ambient_sounds.size()):
		var player := _ambient_sounds[i]
		var stream: AudioStream = pool[i % pool.size()].duplicate()
		_set_loop(stream)
		player.stream = stream
		player.volume_db = -80.0   # faded in by the soundscape tick
		player.play(randf() * maxf(stream.get_length() - 1.0, 0.0))


func _set_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = true

func _stop_ambient() -> void:
	for player in _ambient_sounds:
		player.stop()

## `offset` is relative to the player (x right, y up, -z ahead); the scripted
## events used to be placed at fixed map coordinates near the world origin,
## 15 m from the cabin.
func _play_event_sound_3d(stream: AudioStream, offset: Vector3) -> void:
	if not stream:
		return
	var position := _around_player(offset)
	for player in _event_players:
		if not player.playing:
			player.stream = stream
			player.global_position = position
			player.play()
			sound_played.emit(stream.resource_path.get_file())
			return

func _play_whisper() -> void:
	if not _entity_whisper:
		return
	if not _entity_whisper.playing:
		var stream := _get_random_stream(_whisper_streams)
		if stream:
			_entity_whisper.stream = stream
			_entity_whisper.volume_db = -10.0
			_entity_whisper.play()

func _stop_entity_sounds() -> void:
	if _entity_whisper:
		_entity_whisper.stop()

## Called by player controller for footstep sounds at a specific position
func play_footstep_at(surface_type: String = "wooden", position: Vector3 = Vector3.ZERO) -> void:
	if _muted:
		return
	
	var stream: AudioStream = null
	match surface_type:
		"wooden":
			stream = _get_random_stream(_wooden_footstep_streams)
		"carpet":
			stream = _get_random_stream(_carpet_footstep_streams)
		"concrete":
			stream = _get_random_stream(_concrete_footstep_streams)
		"gravel":
			stream = _get_random_stream(_gravel_footstep_streams)
		"leaves":
			stream = _get_random_stream(_leaves_footstep_streams)
		"metal":
			stream = _get_random_stream(_metal_footstep_streams)
		"mud":
			stream = _get_random_stream(_mud_footstep_streams)
		"stairs":
			stream = _get_random_stream(_stairs_footstep_streams)
		"wind":
			stream = _get_random_stream(_wind_footstep_streams)
		"grass":
			stream = _get_random_stream(_grass_footstep_streams)
		_:
			stream = _get_random_stream(_wooden_footstep_streams)
	
	if stream:
		var player = _get_available_event_player()
		if player:
			player.stream = stream
			player.global_position = position
			player.play()
			sound_played.emit("footstep_" + surface_type)

func _get_available_event_player() -> AudioStreamPlayer3D:
	for player in _event_players:
		if not player.playing:
			player.pitch_scale = 1.0
			return player
	return null

## Scales monster growl volume and pitch based on watched_intensity.
## Called by PerceptionManager when the player is looking at the entity.
func set_watched_intensity(level: float) -> void:
	if level <= 0.0:
		_stop_entity_sounds()
		return
	
	# Scale whisper volume with watched intensity
	if _entity_whisper:
		_entity_whisper.volume_db = linear_to_db(level * 0.3)
		_entity_whisper.pitch_scale = 1.0 + level * 0.2
		if not _entity_whisper.playing and _whisper_streams.size() > 0:
			var stream := _get_random_stream(_whisper_streams)
			if stream:
				_entity_whisper.stream = stream
				_entity_whisper.play()
	
	# At high intensity, play a monster growl as a one-shot event
	if level > 0.7 and _monster_growl_streams.size() > 0:
		_play_event_sound_3d(_get_random_stream(_monster_growl_streams), Vector3(0, 1, -4))

## ─── TASK 2: STALK CHASE AUDIO SETUP ────────────────────────────────────
## Creates a dedicated 2D AudioStreamPlayer for the STALK chase track.
## Tries to load a dedicated `monster_stalk_mx.ogg`; falls back to the
## distant monster stream if the dedicated file is missing.
func _setup_stalk_chase_sounds() -> void:
	# Try to load a dedicated stalk/music track for the chase.
	if ResourceLoader.exists(STALK_CHASE_PATH):
		var stream = load(STALK_CHASE_PATH) as AudioStream
		if stream:
			if stream is AudioStreamOggVorbis:
				stream.loop = true
			_stalk_chase_streams.append(stream)
			print("HorrorSoundManager: Loaded STALK chase audio: " + STALK_CHASE_PATH)
	
	# Create a 2D audio player for the chase track (always audible).
	_stalk_chase_player = AudioStreamPlayer.new()
	_stalk_chase_player.bus = "Entity"
	_stalk_chase_player.volume_db = -20.0
	add_child(_stalk_chase_player)


## Public API: Plays (or resumes) the STALK chase audio. The call is a
## no-op if the track is already playing — the position is preserved so the
## track never restarts from the beginning when the player re-enters the
## 30m proximity boundary. If a previous fade-out was in progress, it is
## cancelled and the volume lerps back up.
func play_stalk_chase() -> void:
	if not _stalk_chase_player:
		return
	if _stalk_chase_player.stream == null:
		# Assign a stream on first play (dedicated track, then distant fallback).
		if not _stalk_chase_streams.is_empty():
			_stalk_chase_player.stream = _stalk_chase_streams[0]
		elif not _distant_monster_streams.is_empty():
			_stalk_chase_player.stream = _distant_monster_streams[0]
			if _stalk_chase_player.stream is AudioStreamOggVorbis:
				_stalk_chase_player.stream.loop = true
		else:
			return
	if _stalk_chase_playing:
		return  # Track already active — keep the current playback position.
	_stalk_chase_playing = true
	# Cancel any in-progress fade-out tween so the volume lerp isn't fought.
	if _stalk_chase_fade_tween and _stalk_chase_fade_tween.is_valid():
		_stalk_chase_fade_tween.kill()
		_stalk_chase_fade_tween = null
	_stalk_chase_player.volume_db = -20.0
	_stalk_chase_player.play()
	print("HorrorSoundManager: STALK chase audio playing.")


## Public API: Fades out and stops the STALK chase audio over 0.5s.
## This prevents an abrupt cutoff and allows clean resume on the next
## proximity entry without restarting the track.
func stop_stalk_chase() -> void:
	if not _stalk_chase_player:
		return
	if not _stalk_chase_playing:
		return
	_stalk_chase_playing = false
	if _stalk_chase_fade_tween and _stalk_chase_fade_tween.is_valid():
		_stalk_chase_fade_tween.kill()
	_stalk_chase_fade_tween = create_tween()
	_stalk_chase_fade_tween.tween_property(_stalk_chase_player, "volume_db", -80.0, STALK_CHASE_FADE_TIME)
	_stalk_chase_fade_tween.tween_callback(_stalk_chase_player.stop)
	print("HorrorSoundManager: STALK chase audio fading out.")


## Internal helper: stops the STALK chase audio immediately (no fade).
## Used on night-end cleanup where a hard stop is acceptable.
func _stop_stalk_chase() -> void:
	if _stalk_chase_fade_tween and _stalk_chase_fade_tween.is_valid():
		_stalk_chase_fade_tween.kill()
		_stalk_chase_fade_tween = null
	_stalk_chase_playing = false
	if _stalk_chase_player and _stalk_chase_player.playing:
		_stalk_chase_player.stop()


## Sets up the distant monster audio player and preloads the audio files.
## Uses ResourceLoader.exists() to silently skip missing files without
## triggering the engine's broken path loader warnings in the debugger console.
func _setup_distant_monster_sounds() -> void:
	# Preload distant monster audio files from assets/audio/Entity/
	var entity_audio_dir = "res://assets/audio/Entity/"
	var file_names = ["monster_distant_mx_1.ogg", "monster_distant_mx_4.ogg"]
	for fname in file_names:
		var path = entity_audio_dir + fname
		if not ResourceLoader.exists(path):
			continue  # Silently skip — no warning printed to debugger
		var stream = load(path) as AudioStream
		if stream:
			_distant_monster_streams.append(stream)
			print("HorrorSoundManager: Loaded distant monster audio: " + path)
	
	# Create a 2D audio player for the distant monster sound (always audible)
	_distant_monster_player = AudioStreamPlayer.new()
	_distant_monster_player.bus = "Entity"
	_distant_monster_player.volume_db = -8.0
	add_child(_distant_monster_player)


## Public API: plays a distant monster sound.
## Called by NightManager.trigger_first_chase() and internally by _on_night_started().
## Always plays monster_distant_mx_1.ogg (the first loaded stream) for a
## consistent, subtle awakening cue. monster_distant_mx_4.ogg is reserved
## for future use (e.g., final night intensity).
func play_distant_monster() -> void:
	if _distant_monster_streams.is_empty() or not _distant_monster_player:
		return
	
	# Always use the first stream (monster_distant_mx_1.ogg) for the awakening cue.
	# This provides a consistent, recognizable sound that signals the Entity is active.
	var stream = _distant_monster_streams[0]
	if stream:
		_distant_monster_player.stream = stream
		_distant_monster_player.play()
		print("HorrorSoundManager: Playing distant monster sound (mx_1)!")
		sound_played.emit("distant_monster")


## Stops the distant monster sound.
func _stop_distant_monster() -> void:
	if _distant_monster_player and _distant_monster_player.playing:
		_distant_monster_player.stop()


## Plays a distant car alarm sound as a narrative telegraph for the Night 1 intro.
## The sound is positioned outside the cabin (e.g., near the van) and loops
## until the player interacts with the escape van to investigate.
##
## IMPORTANT: This function must NEVER play the distant monster sound as a
## fallback. The car alarm narrative is the player's first audio cue after
## waking up — a monster howl would spoil the Entity's reveal. If the car
## alarm audio file is missing, we silently skip playback rather than
## substituting the monster sound.
func play_car_alarm_telegraph() -> void:
	# Use the distant monster player as a 2D audio source (always audible)
	# since the car alarm should be heard from inside the cabin.
	if not _distant_monster_player:
		return
	
	# The alarm itself is the van's own positional AlarmAudio (escape_van.gd,
	# started by the "car_alarm" horror event), audible from the cabin. The
	# "car_alarm.ogg" this used to look for never existed, and playing a 2D
	# copy on top would double it, so there is nothing to add here.
	sound_played.emit("car_alarm_telegraph")


func toggle_mute() -> void:
	_muted = not _muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Ambient"), _muted)


# ═════════════════════════════════════════════════════════════════════════════
# NIGHT SOUNDSCAPE
# ═════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	_soundscape_left -= delta
	if _soundscape_left > 0.0:
		return
	var step := SOUNDSCAPE_INTERVAL - _soundscape_left
	_soundscape_left = SOUNDSCAPE_INTERVAL
	var player := _player()
	if not player:
		return
	var inside: bool = player.has_method("get_player_room") and player.get_player_room() != "Outside"
	var upstairs: bool = inside and player.global_position.y > 2.5
	_update_muffle(inside, upstairs)
	_stinger_cooldown = maxf(_stinger_cooldown - step, 0.0)
	if _is_night:
		_update_wind(upstairs)
		_update_silence(player)
		_update_distant(step, player)
		_update_whistles()
		_update_settling(step, player, inside)
		_update_tension(player)
		_update_first_sighting()


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


## A point relative to the player (their facing), or `offset` itself if
## there is no player.
func _around_player(offset: Vector3) -> Vector3:
	var player := _player()
	if not player or not player.is_inside_tree():
		return offset
	return player.global_transform * offset


## Indoors, the outside (Ambient bus) is muffled; less so upstairs, under the
## roof, where the wind is right above.
func _update_muffle(inside: bool, upstairs: bool) -> void:
	var cutoff := OPEN_CUTOFF
	var duck := 0.0
	if upstairs:
		cutoff = UPSTAIRS_CUTOFF
		duck = UPSTAIRS_DUCK_DB
	elif inside:
		cutoff = INDOOR_CUTOFF
		duck = INDOOR_DUCK_DB
	# Ease in log space so the filter sweep sounds even.
	_muffle_cutoff = exp(lerpf(log(_muffle_cutoff), log(cutoff), 0.35))
	_muffle_db = lerpf(_muffle_db, duck, 0.35)
	var idx := AudioServer.get_bus_index("Ambient")
	var low_pass := _bus_effect(idx, "AudioEffectLowPassFilter") as AudioEffectLowPassFilter
	if low_pass:
		low_pass.cutoff_hz = _muffle_cutoff
	var amplify := _bus_effect(idx, "AudioEffectAmplify") as AudioEffectAmplify
	if amplify:
		amplify.volume_db = _muffle_db


## Wind grows through the nights, swells when the fog is thick, and is louder
## upstairs; the two layers breathe slowly out of step.
func _update_wind(upstairs: bool) -> void:
	var target := minf(WIND_BASE_DB + _night * WIND_PER_NIGHT_DB, WIND_MAX_DB)
	var controller := get_tree().get_first_node_in_group("environment_controller")
	if controller and controller.has_method("get_fog_visibility"):
		var visibility: float = controller.get_fog_visibility()
		if visibility < INF:
			target += WIND_FOG_DB * clampf((55.0 - visibility) / 25.0, 0.0, 1.0)
	if upstairs:
		target += WIND_UPSTAIRS_DB
	var t := Time.get_ticks_msec() / 1000.0
	for i in _ambient_sounds.size():
		var player := _ambient_sounds[i]
		var swell := sin(t * 0.13 + i * 2.1) * 3.0
		player.volume_db = lerpf(player.volume_db, target + swell, 0.15)


## The crickets stop when the Entity is close. The first sign it's there.
func _update_silence(player: Node3D) -> void:
	var entity := get_tree().get_first_node_in_group("entity") as Node3D
	var near := false
	if entity and entity.has_method("is_active") and entity.is_active():
		near = entity.global_position.distance_to(player.global_position) < SILENCE_DISTANCE
	var target := SILENCED_AMBIENCE_DB if near else NIGHT_AMBIENCE_DB
	# Falls silent quickly, comes back slowly.
	_silence_db = lerpf(_silence_db, target, 0.25 if near else 0.05)
	if _night_ambience_player:
		_night_ambience_player.volume_db = _silence_db


## Something far off in the forest now and then.
func _update_distant(step: float, player: Node3D) -> void:
	_distant_left -= step
	if _distant_left > 0.0 or not _distant_player:
		return
	_distant_left = randf_range(DISTANT_INTERVAL_MIN, DISTANT_INTERVAL_MAX)
	var streams := _distant_forest_streams
	var entity := get_tree().get_first_node_in_group("entity") as Node3D
	var entity_far := not entity or entity.global_position.distance_to(player.global_position) > 30.0
	if _night >= 3 and entity_far and randf() < DISTANT_ROAR_CHANCE and not _distant_roar_streams.is_empty():
		streams = _distant_roar_streams
	var stream := _get_random_stream(streams)
	if not stream:
		return
	var direction := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	_distant_player.global_position = player.global_position \
		+ direction * randf_range(DISTANT_RANGE_MIN, DISTANT_RANGE_MAX) + Vector3.UP * 2.0
	_distant_player.stream = stream
	_distant_player.pitch_scale = randf_range(0.85, 1.05)
	_distant_player.play()
	sound_played.emit("distant_" + stream.resource_path.get_file())


## Wind whistles through broken, unboarded windows.
func _update_whistles() -> void:
	for window in get_tree().get_nodes_in_group("WindowMarkers"):
		if not window is CabinWindow:
			continue
		var open: bool = window.is_glass_shattered and not window.is_boarded
		var whistle: AudioStreamPlayer3D = _whistles.get(window)
		if open and not whistle and not _ambient_wind_streams.is_empty():
			whistle = AudioStreamPlayer3D.new()
			whistle.name = "WindWhistle"
			whistle.bus = "SFX"
			whistle.unit_size = 1.5
			whistle.max_distance = 14.0
			whistle.volume_db = WHISTLE_DB
			whistle.pitch_scale = randf_range(1.2, 1.5)   # thinner, whistling
			var stream: AudioStream = _get_random_stream(_ambient_wind_streams).duplicate()
			_set_loop(stream)
			whistle.stream = stream
			window.add_child(whistle)
			whistle.play(randf() * maxf(stream.get_length() - 1.0, 0.0))
			_whistles[window] = whistle
		elif whistle and (not open or not is_instance_valid(window)):
			whistle.queue_free()
			_whistles.erase(window)


func _stop_whistles() -> void:
	for window in _whistles:
		var whistle: AudioStreamPlayer3D = _whistles[window]
		if is_instance_valid(whistle):
			whistle.queue_free()
	_whistles.clear()


## A short horror stinger, unless one played in the last STINGER_COOLDOWN s.
## Returns whether it played.
func play_stinger() -> bool:
	if _stinger_cooldown > 0.0 or _stinger_streams.is_empty() or not _stinger_player:
		return false
	_stinger_cooldown = STINGER_COOLDOWN
	_stinger_player.stream = _get_random_stream(_stinger_streams)
	_stinger_player.play()
	sound_played.emit("stinger")
	return true


## The first time each night the player actually sees the Entity.
func _update_first_sighting() -> void:
	if _seen_tonight:
		return
	var entity := get_tree().get_first_node_in_group("entity")
	if entity and entity.has_method("is_active") and entity.is_active() \
			and entity.get("perception") and entity.perception.in_player_view:
		_seen_tonight = true
		play_stinger()


## The old house settling around the player while they are inside.
func _update_settling(step: float, player: Node3D, inside: bool) -> void:
	_settle_left -= step
	if _settle_left > 0.0:
		return
	_settle_left = randf_range(SETTLE_INTERVAL_MIN, SETTLE_INTERVAL_MAX)
	if not inside or _creaking_door_streams.is_empty():
		return
	var player3d := _get_available_event_player()
	if not player3d:
		return
	var direction := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	player3d.stream = _get_random_stream(_creaking_door_streams)
	player3d.global_position = player.global_position + direction * randf_range(SETTLE_RANGE_MIN, SETTLE_RANGE_MAX) \
		+ Vector3.UP * randf_range(0.5, 2.5)
	player3d.pitch_scale = randf_range(0.45, 0.65)   # boards, not hinges
	player3d.play()
	sound_played.emit("house_settling")


## A low drone that rises as the Entity closes in (or grows bold), and gets
## out of the way of the chase music.
func _update_tension(player: Node3D) -> void:
	if not _tension_player or not _tension_player.stream:
		return
	var level := 0.0
	var entity := get_tree().get_first_node_in_group("entity")
	if entity and entity.has_method("is_active") and entity.is_active():
		var distance: float = entity.global_position.distance_to(player.global_position)
		level = clampf((TENSION_FAR - distance) / (TENSION_FAR - TENSION_NEAR), 0.0, 1.0)
		var confidence = entity.get("confidence")
		if confidence and "confidence" in confidence:
			level = maxf(level, clampf(confidence.confidence / 100.0, 0.0, 1.0) * TENSION_CONFIDENCE_SHARE)
	if _stalk_chase_playing:
		level = 0.0
	_tension = lerpf(_tension, level, 0.1)
	_tension_player.volume_db = lerpf(TENSION_SILENT_DB, TENSION_FULL_DB, _tension)
	if _tension > 0.02 and not _tension_player.playing:
		_tension_player.play()
	elif _tension <= 0.02 and _tension_player.playing:
		_tension_player.stop()
