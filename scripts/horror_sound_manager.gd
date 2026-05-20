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
var _entity_breathing: AudioStreamPlayer = null
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

func _ready() -> void:
	_setup_audio_buses()
	_preload_audio_files()
	_setup_ambient_sounds()
	_setup_event_sounds()
	_setup_entity_sounds()
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
		var idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_volume_db(idx, linear_to_db(0.8))
	
	if not entity_exists:
		var idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Entity")
		AudioServer.set_bus_volume_db(idx, linear_to_db(0.6))

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
func _load_audio_files(dir_path: String, filename_prefix: String, count: int) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for i in range(1, count + 1):
		var path = dir_path + filename_prefix + " (%d).mp3" % i
		var stream = load(path) as AudioStream
		if stream:
			streams.append(stream)
		else:
			print("Warning: Could not load audio file: " + path)
	return streams

## Loads audio files with a custom naming pattern: "{filename_prefix} {n}{extension}"
func _load_audio_files_custom(dir_path: String, filename_prefix: String, count: int, extension: String) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for i in range(1, count + 1):
		var path = dir_path + filename_prefix + " %d%s" % [i, extension]
		var stream = load(path) as AudioStream
		if stream:
			streams.append(stream)
		else:
			print("Warning: Could not load audio file: " + path)
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
	_entity_breathing = AudioStreamPlayer.new()
	_entity_breathing.bus = "Entity"
	_entity_breathing.volume_db = -20.0
	add_child(_entity_breathing)
	
	_entity_whisper = AudioStreamPlayer.new()
	_entity_whisper.bus = "Entity"
	_entity_whisper.volume_db = -15.0
	add_child(_entity_whisper)

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

func _on_night_ended(_night: int) -> void:
	_stop_ambient()
	_stop_entity_sounds()

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
			_play_breathing(0.5)
		"object_moved":
			_play_event_sound_3d(_get_random_stream(_creaking_door_streams), Vector3(1, 0.5, -1))
		"footsteps":
			_play_event_sound_3d(_get_random_stream(_wooden_footstep_streams), Vector3(0, 1, 3))
		"entity_appears":
			_play_event_sound_3d(_get_random_stream(_monster_growl_streams), Vector3(0, 1, -4))
			_play_breathing(0.8)
		"lights_flicker":
			_play_event_sound_3d(_get_random_stream(_creaking_door_streams), Vector3(0, 1, -3))
		"entity_charge":
			_play_event_sound_3d(_get_random_stream(_monster_growl_streams), Vector3(0, 1, -2))
			_play_breathing(1.0)
		"entity_constant":
			_play_breathing(0.7)
			_play_whisper()
		"poltergeist":
			_play_event_sound_3d(_get_random_stream(_creaking_door_streams), Vector3(0, 1, 0))
		"final_confrontation":
			_play_event_sound_3d(_get_random_stream(_monster_growl_streams), Vector3(0, 1, -3))
			_play_breathing(1.0)

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

func _play_breathing(intensity: float = 0.5) -> void:
	if not _entity_breathing:
		return
	if _monster_growl_streams.is_empty():
		return
	_entity_breathing.volume_db = linear_to_db(intensity * 0.3)
	if not _entity_breathing.playing:
		_entity_breathing.stream = _get_random_stream(_monster_growl_streams)
		_entity_breathing.play()

func _play_whisper() -> void:
	if not _entity_whisper:
		return
	if not _entity_whisper.playing:
		if _ambient_wind_streams.is_empty():
			return
		_entity_whisper.stream = _get_random_stream(_ambient_wind_streams)
		_entity_whisper.volume_db = -10.0
		_entity_whisper.play()

func _stop_entity_sounds() -> void:
	if _entity_breathing:
		_entity_breathing.stop()
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

## Called by player controller for footstep sounds
func play_footstep(surface_type: String = "wooden") -> void:
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
			player.global_position = Vector3.ZERO
			player.play()
			sound_played.emit("footstep_" + surface_type)

func _get_available_event_player() -> AudioStreamPlayer3D:
	for player in _event_players:
		if not player.playing:
			return player
	return null

func set_entity_proximity(level: float) -> void:
	if level > 0.3:
		_play_breathing(level)
	else:
		_stop_entity_sounds()


## Scales monster growl volume and pitch based on watched_intensity.
## Called by PerceptionManager when the player is looking at the entity.
func set_watched_intensity(level: float) -> void:
	if level <= 0.0:
		_stop_entity_sounds()
		return
	
	# Scale breathing volume with watched intensity
	if _entity_breathing:
		_entity_breathing.volume_db = linear_to_db(level * 0.5)
		_entity_breathing.pitch_scale = 1.0 + level * 0.3
		if not _entity_breathing.playing and _monster_growl_streams.size() > 0:
			_entity_breathing.stream = _get_random_stream(_monster_growl_streams)
			_entity_breathing.play()
	
	# Scale whisper volume with watched intensity
	if _entity_whisper:
		_entity_whisper.volume_db = linear_to_db(level * 0.3)
		_entity_whisper.pitch_scale = 1.0 + level * 0.2
		if not _entity_whisper.playing and _ambient_wind_streams.size() > 0:
			_entity_whisper.stream = _get_random_stream(_ambient_wind_streams)
			_entity_whisper.play()
	
	# At high intensity, play a monster growl as a one-shot event
	if level > 0.7 and _monster_growl_streams.size() > 0:
		_play_event_sound_3d(_get_random_stream(_monster_growl_streams), Vector3(0, 1, -4))

func toggle_mute() -> void:
	_muted = not _muted
	for player in _ambient_sounds:
		player.volume_db = -80.0 if _muted else -10.0
