extends Node
class_name EntityAudioController

## Entity Audio Controller — dedicated node for Entity footstep, voice, and
## ambience audio management. Extracted from entity_controller.gd to satisfy
## the Single Responsibility Principle.
##
## ARCHITECTURE:
##   The entity_controller.gd (Motor Hub) creates this as a child node named
##   "EntityAudioController". It accesses audio players through the Blackboard's
##   cached node references, reads Blackboard state for context, and calls
##   update_audio(delta) each physics frame to manage all audio concerns.
##
##   Footstep sounds, chase music, night ambience, voice lines (angry, talking,
##   searching), and the light sanctuary grunt are all managed here.
##   entity_controller.gd no longer holds any audio arrays or music players.

# ─── REFERENCE: The Blackboard (set by entity_controller.gd)
var blackboard: EntityBlackboard = null

# ─── FOOTSTEP AUDIO ─────────────────────────────────────────────────────
@export var wood_footsteps: Array[AudioStream] = []
@export var grass_footsteps: Array[AudioStream] = []
@export var footstep_interval_normal: float = 0.5
@export var footstep_interval_charge: float = 0.25
@export var footstep_pitch_min: float = 0.7
@export var footstep_pitch_max: float = 0.95
var _entity_step_timer: float = 0.0
var _entity_step_interval: float = 0.5

# ─── CHASE MUSIC ───────────────────────────────────────────────────────
const CHASE_MUSIC_PATH: String = "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/Ambiences/ambience_d6_loop.ogg"
const CHASE_MUSIC_FADE_SPEED: float = 2.0
const CHASE_MUSIC_VOLUME_DB: float = -8.0

# ─── CHASE EXIT GRUNT ──────────────────────────────────────────────────
const CHASE_EXIT_GRUNT_PATH: String = "res://assets/audio/Entity/Entity_grunt_long.ogg"
const CHASE_EXIT_GRUNT_COOLDOWN_DURATION: float = 5.0

# ─── NIGHT AMBIENCE ────────────────────────────────────────────────────
const NIGHT_AMBIENCE_PATH: String = "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/Ambiences/ambience_d1_loop.ogg"
const NIGHT_AMBIENCE_FADE_SPEED: float = 3.0
const NIGHT_AMBIENCE_VOLUME_DB: float = -18.0

# ─── VOICE / SPATIAL ───────────────────────────────────────────────────
var _was_chasing_prev: bool = false


## Initialize with the Blackboard reference.
## Called by entity_controller.gd after adding this node as a child.
func setup(bb: EntityBlackboard) -> void:
	blackboard = bb


## Called every physics frame from entity_controller.gd's _physics_process().
## Delegates to the appropriate audio sub-handler.
func update_audio(delta: float) -> void:
	if not blackboard:
		return
	
	_update_chase_music(delta)
	_update_night_ambience(delta)
	_update_chase_exit_grunt(delta)
	_update_footsteps(delta)
	_update_flinch_sound(delta)
	_update_light_sanctuary_sound(delta)


# ─── CHASE MUSIC ──────────────────────────────────────────────────────
func _update_chase_music(delta: float) -> void:
	var player = blackboard.chase_music_player
	if not player:
		return
	
	var is_chasing = (blackboard.state == EntityAI.State.CHARGE or 
					  blackboard.state == EntityAI.State.INDOOR_SEARCH or
					  blackboard.is_hunting)
	
	if is_chasing and not blackboard.chase_music_was_playing:
		# Start playing chase music
		_load_and_fade_in(player, CHASE_MUSIC_PATH, CHASE_MUSIC_VOLUME_DB, CHASE_MUSIC_FADE_SPEED)
		blackboard.chase_music_was_playing = true
	elif not is_chasing and blackboard.chase_music_was_playing:
		# Stop chase music with fade
		_fade_and_stop(player, CHASE_MUSIC_FADE_SPEED)
		blackboard.chase_music_was_playing = false


# ─── NIGHT AMBIENCE ────────────────────────────────────────────────────
func _update_night_ambience(delta: float) -> void:
	var player = blackboard.night_ambience_player
	if not player:
		return
	
	var is_active = (blackboard.state != EntityAI.State.DORMANT and 
					not blackboard.is_fading)
	
	if is_active and not blackboard.night_ambience_was_playing:
		_load_and_fade_in(player, NIGHT_AMBIENCE_PATH, NIGHT_AMBIENCE_VOLUME_DB, NIGHT_AMBIENCE_FADE_SPEED)
		blackboard.night_ambience_was_playing = true
	elif not is_active and blackboard.night_ambience_was_playing:
		_fade_and_stop(player, NIGHT_AMBIENCE_FADE_SPEED)
		blackboard.night_ambience_was_playing = false


# ─── CHASE EXIT GRUNT ──────────────────────────────────────────────────
func _update_chase_exit_grunt(delta: float) -> void:
	var player = blackboard.chase_exit_grunt_player
	if not player:
		return
	
	# Detect transition from chase to non-chase
	var is_chasing = (blackboard.state == EntityAI.State.CHARGE)
	var transitioned_out = _was_chasing_prev and not is_chasing
	_was_chasing_prev = is_chasing
	
	if transitioned_out and blackboard.chase_exit_grunt_cooldown <= 0.0:
		# Play the grunt sound
		var stream = load(CHASE_EXIT_GRUNT_PATH) as AudioStream
		if stream:
			player.stream = stream
			player.play()
			blackboard.chase_exit_grunt_cooldown = CHASE_EXIT_GRUNT_COOLDOWN_DURATION
	
	# Decrement cooldown
	if blackboard.chase_exit_grunt_cooldown > 0.0:
		blackboard.chase_exit_grunt_cooldown -= delta


# ─── FOOTSTEPS ─────────────────────────────────────────────────────────
func _update_footsteps(delta: float) -> void:
	var player = blackboard.footstep_audio
	if not player:
		return
	
	var is_moving = blackboard.entity and blackboard.entity.velocity.length_squared() > 0.1
	var is_charging = (blackboard.state == EntityAI.State.CHARGE)
	
	if is_moving:
		_entity_step_timer -= delta
		var interval = footstep_interval_charge if is_charging else footstep_interval_normal
		if _entity_step_timer <= 0.0:
			_entity_step_timer = interval
			_play_footstep(player)
	else:
		_entity_step_timer = 0.0
	
	_entity_step_interval = footstep_interval_charge if is_charging else footstep_interval_normal


func _play_footstep(player: AudioStreamPlayer3D) -> void:
	# Pick a random footstep sound based on terrain
	var pool: Array[AudioStream] = []
	if not wood_footsteps.is_empty() and randf() < 0.3:
		pool = wood_footsteps
	elif not grass_footsteps.is_empty():
		pool = grass_footsteps
	
	if pool.is_empty():
		return
	
	var stream = pool[randi() % pool.size()]
	if not stream:
		return
	
	player.stream = stream
	player.pitch_scale = randf_range(footstep_pitch_min, footstep_pitch_max)
	player.play()


# ─── LIGHT SANCTUARY GRUNT ─────────────────────────────────────────────
func _update_light_sanctuary_sound(delta: float) -> void:
	var player = blackboard.light_sanctuary_grunt_player
	if not player:
		return
	
	if blackboard.has_played_light_sound:
		return
	
	# Play when Entity is repelled by light sanctuary (in lit room)
	if blackboard.is_indoor_retreat and not blackboard.has_played_light_sound:
		var stream = load(CHASE_EXIT_GRUNT_PATH) as AudioStream
		if stream:
			player.stream = stream
			player.play()
			blackboard.has_played_light_sound = true


# ─── FLINCH SOUND ──────────────────────────────────────────────────────
func _update_flinch_sound(delta: float) -> void:
	# Flinch sounds are managed via the spatial voice system in entity_ai.gd
	# This is a placeholder for future extraction
	pass


# ─── AUDIO HELPERS ─────────────────────────────────────────────────────
func _load_and_fade_in(player: AudioStreamPlayer, path: String, volume: float, fade_speed: float) -> void:
	var stream = load(path) as AudioStream
	if not stream:
		return
	player.stream = stream
	player.volume_db = -80.0
	player.play()
	# Fade in via tween
	var tween = create_tween()
	tween.tween_property(player, "volume_db", volume, fade_speed)


func _fade_and_stop(player: AudioStreamPlayer, fade_speed: float) -> void:
	var tween = create_tween()
	tween.tween_property(player, "volume_db", -80.0, fade_speed)
	tween.tween_callback(player.stop)