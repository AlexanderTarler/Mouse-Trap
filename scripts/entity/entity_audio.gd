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
const TAP_STREAM := preload("res://assets/audio/Entity/Metal_random tapping.wav")

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


func setup(owner_entity: Entity) -> void:
	entity = owner_entity
	position.y = entity.config.eye_height
	_voice = _make_player("Voice", 6.0, 40.0, 2.0)
	_sfx = _make_player("Sfx", 5.0, 35.0, 0.0)
	_tap = _make_player("Tap", 3.0, 18.0, 0.0)
	_tap.top_level = true
	_growl = entity.get_node_or_null("GrowlAudio")
	_footstep = entity.get_node_or_null("FootstepAudio")


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
	_voice.stream = VOICE_STREAMS[kind].pick_random()
	_voice.pitch_scale = randf_range(0.75, 0.9)
	_voice.play()
	_voice_cooldown = VOICE_COOLDOWN


func play_roar() -> void:
	if _growl:
		_growl.pitch_scale = randf_range(0.85, 1.0)
		_growl.play()


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


## Tapping on glass at a world position (a window).
func play_tap_at(world_position: Vector3) -> void:
	_tap.global_position = world_position
	_tap.stream = TAP_STREAM
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
	for player in [_voice, _sfx, _tap, _growl, _footstep]:
		if player:
			player.stop()
	stop_chase_music()
