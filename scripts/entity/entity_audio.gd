class_name EntityAudio
extends Node3D

## The Entity's sounds. Design rule: sparse and positional. No looping voice
## lines that give its position away; short cues with cooldowns, and silence
## in between. Chase music only plays while it is actually charging (or in the
## scripted van chase). Night ambience is HorrorSoundManager's job.

const VOICE_STREAMS := {
	"murmur": [
		preload("res://assets/audio/Entity/Entity Talking.ogg"),
		preload("res://assets/audio/Entity/Entity Talking 2.ogg"),
	],
	"search": [preload("res://assets/audio/Entity/Entity Searching.ogg")],
	"angry": [preload("res://assets/audio/Entity/Entity Angry.ogg")],
}
const GRUNT_STREAM := preload("res://assets/audio/Entity/Entity_grunt_long.ogg")

const ECHOES := "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/"
const HORROR_SFX := "res://assets/audio/horror_sfx_vol_1/"
## Growls: winding up to charge, turned away by a lit window.
const GROWL_PATTERN := HORROR_SFX + "Monster Growl/Monster Growl (%d).mp3"
const GROWL_COUNT := 12
const OBJECTS := "res://assets/audio/objects/"
## Claws dragging on the logs while it climbs.
const SCRAPE_PATHS: Array[String] = [OBJECTS + "Climb Scrape.ogg"]
## Hitting the ground when it drops off a wall.
const THUD_PATHS: Array[String] = [OBJECTS + "Drop Thud.ogg"]
## Old boards under its weight.
const CREAK_PATHS: Array[String] = [OBJECTS + "Floor Creak.ogg"]
## Knocking on the glass while it peeks in at a window.
const WINDOW_KNOCK := preload("res://assets/audio/objects/Window Knock.ogg")
## Knuckles on the door.
const KNOCK_PATHS: Array[String] = [ECHOES + "SFX/Misc/hit_1.ogg", ECHOES + "SFX/Misc/hit_2.ogg", ECHOES + "SFX/Misc/hit_4.ogg"]
## Extra low murmurs for the "murmur" voice.
## Its charge shriek: monster roars pitched up.
const SHRIEK_PATHS: Array[String] = [
	ECHOES + "SFX/Creatures/Monster/monster_roar_1.ogg", ECHOES + "SFX/Creatures/Monster/monster_roar_2.ogg",
	ECHOES + "SFX/Creatures/Monster/monster_roar_3.ogg", ECHOES + "SFX/Creatures/Monster/monster_roar_4.ogg",
	ECHOES + "SFX/Creatures/Monster/monster_roar_5.ogg", ECHOES + "SFX/Creatures/Monster/monster_roar_6.ogg",
	ECHOES + "SFX/Creatures/Monster/monster_roar_7.ogg",
]
const MURMUR_PATHS: Array[String] = [
	ECHOES + "SFX/Creatures/Monster/monster_talking_1.ogg",
	ECHOES + "SFX/Creatures/Monster/monster_talking_2.ogg",
	ECHOES + "SFX/Creatures/Monster/monster_talking_3.ogg",
]

## Floor creaks: only heard from the other floor, within this distance (m),
## every CREAK_INTERVAL seconds or so while it walks.
const CREAK_DISTANCE := 9.0
const CREAK_INTERVAL_MIN := 1.4
const CREAK_INTERVAL_MAX := 3.0
## Murmurs when it is this close but out of sight, at most this often (s).
const MURMUR_DISTANCE := 12.0
const MURMUR_INTERVAL_MIN := 25.0
const MURMUR_INTERVAL_MAX := 45.0
const MURMUR_STATES := [Entity.State.HUNT, Entity.State.SEARCH, Entity.State.STALK, Entity.State.PEEK]

const VOICE_COOLDOWN := 10.0
const FOOTSTEP_PITCH_MIN := 0.7
const FOOTSTEP_PITCH_MAX := 0.95

var entity: Entity
var _voice: AudioStreamPlayer3D
var _sfx: AudioStreamPlayer3D
var _tap: AudioStreamPlayer3D
var _growl: AudioStreamPlayer3D
var _footstep: AudioStreamPlayer3D
var _voice_cooldown := 0.0
var _step_timer := 0.0
var _chase_music_on := false
var _scrape: AudioStreamPlayer3D
var _creak: AudioStreamPlayer3D
var _knock: AudioStreamPlayer3D
var _shriek: AudioStreamPlayer3D
var _shriek_streams: Array[AudioStream] = []
var _growl_streams: Array[AudioStream] = []
var _scrape_streams: Array[AudioStream] = []
var _thud_streams: Array[AudioStream] = []
var _creak_streams: Array[AudioStream] = []
var _knock_streams: Array[AudioStream] = []
var _murmur_streams: Array[AudioStream] = []
var _creak_left := 0.0
var _murmur_left := 30.0


func setup(owner_entity: Entity) -> void:
	entity = owner_entity
	position.y = entity.config.eye_height
	_voice = _make_player("Voice", 6.0, 40.0, 2.0)
	_sfx = _make_player("Sfx", 5.0, 35.0, 0.0)
	_tap = _make_player("Tap", 3.0, 18.0, 0.0)
	_tap.top_level = true
	_growl = entity.get_node_or_null("GrowlAudio")
	_footstep = entity.get_node_or_null("FootstepAudio")
	_scrape = _make_player("Scrape", 4.0, 30.0, -2.0)
	_scrape.top_level = true
	_creak = _make_player("Creak", 4.0, 20.0, 0.0)
	_creak.top_level = true
	_knock = _make_player("Knock", 5.0, 35.0, 2.0)
	_knock.top_level = true
	# A child of this node (at its eye height), so it moves with it.
	_shriek = _make_player("Shriek", 8.0, 60.0, 4.0)
	_shriek_streams = _load_paths(SHRIEK_PATHS)
	_growl_streams = _load_pattern(GROWL_PATTERN, GROWL_COUNT)
	_creak_streams = _load_paths(CREAK_PATHS)
	_scrape_streams = _load_paths(SCRAPE_PATHS)
	_thud_streams = _load_paths(THUD_PATHS)
	_knock_streams = _load_paths(KNOCK_PATHS)
	_murmur_streams = _load_paths(MURMUR_PATHS)
	_murmur_streams.append_array(VOICE_STREAMS["murmur"])


func _load_paths(paths: Array[String]) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for path in paths:
		if ResourceLoader.exists(path):
			streams.append(load(path) as AudioStream)
	return streams


func _load_pattern(pattern: String, count: int) -> Array[AudioStream]:
	var paths: Array[String] = []
	for i in range(1, count + 1):
		paths.append(pattern % i)
	return _load_paths(paths)


func _make_player(player_name: String, unit_size: float, max_distance: float, volume_db: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = player_name
	player.bus = &"Entity"
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	player.unit_size = unit_size
	player.max_distance = max_distance
	player.volume_db = volume_db
	add_child(player)
	return player


func _process(delta: float) -> void:
	_voice_cooldown = maxf(_voice_cooldown - delta, 0.0)


## A short voice cue ("murmur", "search", "angry"). Skipped while on cooldown
## unless `force` is set.
func play_voice(kind: String, force: bool = false) -> void:
	if (_voice_cooldown > 0.0 and not force) or not VOICE_STREAMS.has(kind):
		return
	var streams: Array = _murmur_streams if kind == "murmur" and not _murmur_streams.is_empty() else VOICE_STREAMS[kind]
	_voice.stream = streams.pick_random()
	_voice.pitch_scale = randf_range(0.75, 0.9)
	_voice.play()
	_voice_cooldown = VOICE_COOLDOWN


func play_roar() -> void:
	if _growl:
		_growl.pitch_scale = randf_range(0.85, 1.0)
		_growl.play()


## The shriek as it charges, from its head, wherever it is (indoors too).
func play_shriek() -> void:
	if not _shriek or _shriek_streams.is_empty():
		return
	_shriek.stream = _shriek_streams.pick_random()
	_shriek.pitch_scale = randf_range(1.15, 1.3)
	_shriek.play()


## Pained reaction (overcharge beam, stun).
func play_scream() -> void:
	if _growl:
		_growl.pitch_scale = 1.8
		_growl.play()


## Frustrated, low grunt (blocked by light, giving up).
func play_grunt(pitch: float = 1.0) -> void:
	_sfx.stream = GRUNT_STREAM
	_sfx.pitch_scale = pitch
	_sfx.play()


func play_vault() -> void:
	play_grunt(0.7)


## A deep growl (winding up to charge, turned away by a lit window).
func play_growl() -> void:
	if _growl_streams.is_empty():
		play_grunt(0.7)
		return
	_sfx.stream = _growl_streams.pick_random()
	_sfx.pitch_scale = randf_range(0.85, 1.0)
	_sfx.play()


## Claws dragging on the logs as it climbs.
func play_climb_scrape(world_position: Vector3) -> void:
	if _scrape_streams.is_empty():
		play_tap_at(world_position)
		return
	_scrape.global_position = world_position
	_scrape.stream = _scrape_streams.pick_random()
	_scrape.pitch_scale = randf_range(0.9, 1.1)
	_scrape.play()


## Hitting the ground after dropping off a wall.
func play_drop_thud() -> void:
	if not _thud_streams.is_empty():
		_scrape.global_position = entity.global_position
		_scrape.stream = _thud_streams.pick_random()
		_scrape.pitch_scale = randf_range(0.9, 1.05)
		_scrape.play()
	play_grunt(0.55)


## Three slow knocks on the door at `world_position`.
func play_knocks(world_position: Vector3) -> void:
	if _knock_streams.is_empty():
		return
	_knock.global_position = world_position
	var tween := create_tween()
	for i in 3:
		tween.tween_callback(_knock_once)
		tween.tween_interval(randf_range(0.55, 0.8))


func _knock_once() -> void:
	_knock.stream = _knock_streams.pick_random()
	_knock.pitch_scale = randf_range(0.65, 0.75)
	_knock.play()


## Boards creaking under it, heard from the other floor of the cabin: only
## when the player is inside on the floor below (or above) and close.
func update_floor_creaks(delta: float, horizontal_speed: float) -> void:
	if horizontal_speed < 0.5 or _creak_streams.is_empty() or not entity.perception.entity_inside \
			or not entity.perception.player_inside:
		return
	var player := entity.get_player()
	var rise := absf(player.global_position.y - entity.global_position.y)
	if rise < Entity.FLOOR_GAP or Entity._flat_distance(player.global_position, entity.global_position) > CREAK_DISTANCE:
		return
	_creak_left -= delta
	if _creak_left > 0.0:
		return
	_creak_left = randf_range(CREAK_INTERVAL_MIN, CREAK_INTERVAL_MAX)
	_creak.global_position = entity.global_position + Vector3.UP * 0.2
	_creak.stream = _creak_streams.pick_random()
	_creak.pitch_scale = randf_range(0.85, 1.05)
	_creak.play()


## Now and then, when it is close but the player can't see it, a murmur.
func update_murmurs(delta: float) -> void:
	_murmur_left -= delta
	if _murmur_left > 0.0:
		return
	_murmur_left = randf_range(MURMUR_INTERVAL_MIN, MURMUR_INTERVAL_MAX)
	if entity.get_state() in MURMUR_STATES and not entity.perception.in_player_view \
			and entity.perception.distance_to_player < MURMUR_DISTANCE:
		play_voice("murmur", true)


## Knocking on the glass at a world position (a window).
func play_tap_at(world_position: Vector3) -> void:
	_tap.global_position = world_position
	_tap.stream = WINDOW_KNOCK
	_tap.pitch_scale = randf_range(0.9, 1.1)
	_tap.play()


func update_footsteps(delta: float, horizontal_speed: float) -> void:
	if horizontal_speed < 0.5 or not _footstep:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	_step_timer = clampf(1.1 - horizontal_speed * 0.12, 0.22, 0.8)
	var inside := entity.perception.entity_inside
	var streams: Array[AudioStream] = entity.wood_footsteps if inside else entity.grass_footsteps
	if streams.is_empty():
		return
	_footstep.stream = streams.pick_random()
	_footstep.pitch_scale = randf_range(FOOTSTEP_PITCH_MIN, FOOTSTEP_PITCH_MAX)
	_footstep.play()


func start_chase_music() -> void:
	if entity.van_chase_active and not entity.config.van_chase_music:
		return
	var hsm := get_node_or_null("/root/HorrorSoundManager")
	if hsm and not _chase_music_on:
		hsm.play_stalk_chase()
		_chase_music_on = true


func stop_chase_music() -> void:
	var hsm := get_node_or_null("/root/HorrorSoundManager")
	if hsm and _chase_music_on:
		hsm.stop_stalk_chase()
	_chase_music_on = false


func stop_all() -> void:
	for player in [_voice, _sfx, _tap, _growl, _footstep, _scrape, _creak, _knock, _shriek]:
		if player:
			player.stop()
	stop_chase_music()
