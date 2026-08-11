extends Node

## Manages all horror sound effects and ambient audio.
## Plays sounds based on NightManager events and entity proximity.
## Uses actual audio files from the horror_sfx_vol_1 asset pack.

signal sound_played(sound_name: String)

# Audio file paths
const AMBIENT_WIND_DIR: String = "res://assets/horror_sfx_vol_1/Ambient Wind/"
const CARPET_FOOTSTEP_DIR: String = "res://assets/horror_sfx_vol_1/Carpet Footstep/"
const CONCRETE_FOOTSTEP_DIR: String = "res://assets/horror_sfx_vol_1/Concrete Footsteps/"
const GRAVEL_FOOTSTEP_DIR: String = "res://assets/horror_sfx_vol_1/Gravel Footsteps/"
const LEAVES_FOOTSTEP_DIR: String = "res://assets/horror_sfx_vol_1/Leaves Footsteps/"
const METAL_FOOTSTEP_DIR: String = "res://assets/horror_sfx_vol_1/Metal Footsteps/"
const MUD_FOOTSTEP_DIR: String = "res://assets/horror_sfx_vol_1/Mud foosteps/"
const STAIRS_FOOTSTEP_DIR: String = "res://assets/horror_sfx_vol_1/Stairs Footsteps/"
const WIND_FOOTSTEP_DIR: String = "res://assets/horror_sfx_vol_1/Wind Footsteps/"
const WOODEN_FOOTSTEP_DIR: String = "res://assets/horror_sfx_vol_1/Wooden Foosteps/"
const GRASS_FOOTSTEP_DIR: String = "res://assets/audio/40 Free PSX Footsteps/Grass/"
const CREAKING_DOOR_DIR: String = "res://assets/horror_sfx_vol_1/Creaking Door/"
const MONSTER_GROWL_DIR: String = "res://assets/horror_sfx_vol_1/Monster Growl/"

# Ambient sound pool
var _ambient_sounds: Array[AudioStreamPlayer3D] = []

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
const STALK_CHASE_PATH: String = "res://assets/audio/Entity/monster_stalk_mx.ogg"
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
	
	print("HorrorSoundManager: Loaded %d ambient wind, %d wooden footsteps, %d grass footsteps, %d door creaks, %d monster growls" % [
		_ambient_wind_streams.size(),
		_wooden_footstep_streams.size(),
		_grass_footstep_streams.size(),
		_creaking_door_streams.size(),
		_monster_growl_streams.size()
	])

## Loads audio files using the exact naming pattern: "{filename_prefix} ({n}).mp3"
## Uses FileAccess.file_exists() to silently skip missing files without
## triggering the engine's broken path loader warnings in the debugger console.
func _load_audio_files(dir_path: String, filename_prefix: String, count: int) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for i in range(1, count + 1):
		var path = dir_path + filename_prefix + " (%d).mp3" % i
		if not FileAccess.file_exists(path):
			continue  # Silently skip — no warning printed to debugger
		var stream = load(path) as AudioStream
		if stream:
			streams.append(stream)
	return streams

## Loads audio files with a custom naming pattern: "{filename_prefix} {n}{extension}"
## Uses FileAccess.file_exists() to silently skip missing files without
## triggering the engine's broken path loader warnings in the debugger console.
func _load_audio_files_custom(dir_path: String, filename_prefix: String, count: int, extension: String) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for i in range(1, count + 1):
		var path = dir_path + filename_prefix + " %d%s" % [i, extension]
		if not FileAccess.file_exists(path):
			continue  # Silently skip — no warning printed to debugger
		var stream = load(path) as AudioStream
		if stream:
			streams.append(stream)
	return streams

## Gets a random stream from an array.
func _get_random_stream(streams: Array[AudioStream]) -> AudioStream:
	if streams.is_empty():
		return null
	return streams[randi() % streams.size()]

func _setup_ambient_sounds() -> void:
	for i in 3:
		var player = AudioStreamPlayer3D.new()
		player.bus = "Ambient"
		player.max_distance = 20.0
		player.volume_db = -10.0
		add_child(player)
		_ambient_sounds.append(player)

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
## Uses FileAccess.file_exists() to silently skip missing files without
## triggering the engine's broken path loader warnings in the debugger console.
func _setup_forest_ambience() -> void:
	# Day ambience player
	_day_ambience_player = AudioStreamPlayer.new()
	_day_ambience_player.bus = "Ambient"
	_day_ambience_player.volume_db = -12.0
	if FileAccess.file_exists(DAY_AMBIENCE_PATH):
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
	if FileAccess.file_exists(NIGHT_AMBIENCE_PATH):
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
	var ambient_vol = -15.0 + (night * 2.0)
	for player in _ambient_sounds:
		player.volume_db = ambient_vol
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
	
	for i in range(_ambient_sounds.size()):
		var player = _ambient_sounds[i]
		var stream = _get_random_stream(_ambient_wind_streams)
		if stream:
			player.stream = stream
			player.play()

func _stop_ambient() -> void:
	for player in _ambient_sounds:
		player.stop()

func _play_event_sound_3d(stream: AudioStream, position: Vector3) -> void:
	if not stream:
		return
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
		if _ambient_wind_streams.is_empty():
			return
		var stream = _get_random_stream(_ambient_wind_streams)
		if stream:
			# Explicitly disable looping — the audio file may have loop=true
			# in its import settings, which would cause this one-shot sound
			# to loop forever when the player enters a lit room sanctuary.
			if stream is AudioStreamOggVorbis:
				stream.loop = false
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
			return player
	return null

func set_entity_proximity(level: float) -> void:
	# Entity proximity breathing sounds have been removed.
	# This function is kept as a stub for any external callers.
	pass


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
		if not _entity_whisper.playing and _ambient_wind_streams.size() > 0:
			var stream = _get_random_stream(_ambient_wind_streams)
			if stream:
				if stream is AudioStreamOggVorbis:
					stream.loop = false
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
	if FileAccess.file_exists(STALK_CHASE_PATH):
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
## Uses FileAccess.file_exists() to silently skip missing files without
## triggering the engine's broken path loader warnings in the debugger console.
func _setup_distant_monster_sounds() -> void:
	# Preload distant monster audio files from assets/audio/Entity/
	var entity_audio_dir = "res://assets/audio/Entity/"
	var file_names = ["monster_distant_mx_1.ogg", "monster_distant_mx_4.ogg"]
	for fname in file_names:
		var path = entity_audio_dir + fname
		if not FileAccess.file_exists(path):
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
	
	# Try to load a car alarm audio file if it exists.
	# Uses FileAccess.file_exists() to silently skip missing files without
	# triggering the engine's broken path loader warnings in the debugger console.
	var car_alarm_path = "res://assets/audio/Entity/car_alarm.ogg"
	if FileAccess.file_exists(car_alarm_path):
		var stream = load(car_alarm_path) as AudioStream
		if stream:
			if stream is AudioStreamOggVorbis:
				stream.loop = true
			_distant_monster_player.stream = stream
			_distant_monster_player.volume_db = -4.0
			_distant_monster_player.play()
			print("HorrorSoundManager: Playing car alarm telegraph!")
			sound_played.emit("car_alarm_telegraph")


func toggle_mute() -> void:
	_muted = not _muted
	for player in _ambient_sounds:
		player.volume_db = -80.0 if _muted else -10.0
