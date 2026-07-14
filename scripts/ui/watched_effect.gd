extends ColorRect
class_name WatchedEffect

## "Feeling watched" visual effect overlay.
## Uses a shader-based distortion effect (chromatic aberration, pixelation, noise, vignette)
## that scales with watched_intensity from the PerceptionManager.
##
## Also manages the blindness overlay (full-screen black fade).
##
## Plays "sfx cinematic 53" as a one-shot audio cue when the player is looking at the Entity.

## Reference to the PerceptionManager (set automatically)
@export var perception_manager: Node = null

## Reference to the BlindnessRect (a ColorRect child for the blindness effect)
@onready var _blindness_rect: ColorRect = $BlindnessRect

## Shader material instance
var _shader_material: ShaderMaterial

## Time accumulator for shader animation
var _effect_time: float = 0.0

## Whether blindness is currently active
var _is_blind: bool = false

## Watched audio — plays "sfx cinematic 53" when the player is looking at the Entity
var _watched_audio_player: AudioStreamPlayer = null
var _watched_audio_was_playing: bool = false
const WATCHED_AUDIO_PATH: String = "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Cinematic/sfx cinematic 53.ogg"
const WATCHED_AUDIO_VOLUME_DB: float = -6.0


func _ready() -> void:
	# Set up the shader material
	material = ShaderMaterial.new()
	_shader_material = material as ShaderMaterial
	_shader_material.shader = preload("res://shaders/distortion.gdshader")
	
	# Make this cover the full screen
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Initialize shader parameters
	_shader_material.set_shader_parameter("watched_intensity", 0.0)
	_shader_material.set_shader_parameter("effect_time", 0.0)
	
	# Set up blindness rect
	if _blindness_rect:
		_blindness_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_blindness_rect.color = Color(0, 0, 0, 0)
	
	# Set up watched audio player (2D, non-positional)
	_watched_audio_player = AudioStreamPlayer.new()
	_watched_audio_player.bus = "SFX"
	_watched_audio_player.volume_db = WATCHED_AUDIO_VOLUME_DB
	var watched_stream = load(WATCHED_AUDIO_PATH) as AudioStream
	if watched_stream:
		# Enable looping so the whispers play continuously while the player
		# is looking at the Entity, rather than cutting out after one play.
		if watched_stream is AudioStreamOggVorbis:
			watched_stream.loop = true
		_watched_audio_player.stream = watched_stream
	add_child(_watched_audio_player)
	
	# Find PerceptionManager
	if not perception_manager:
		perception_manager = get_node_or_null("/root/CottageHorror/Player/PerceptionManager")
		if not perception_manager:
			perception_manager = get_node_or_null("/root/Main/Player/PerceptionManager")
	
	# Connect to PerceptionManager signals
	if perception_manager:
		perception_manager.watched_intensity_changed.connect(_on_watched_intensity_changed)
		perception_manager.blindness_started.connect(_on_blindness_started)
		perception_manager.blindness_ended.connect(_on_blindness_ended)
		print("WatchedEffect: Connected to PerceptionManager")
	else:
		print("WatchedEffect: PerceptionManager not found")


func _process(delta: float) -> void:
	_effect_time += delta
	if _shader_material:
		_shader_material.set_shader_parameter("effect_time", _effect_time)


func _on_watched_intensity_changed(intensity: float) -> void:
	if _shader_material:
		_shader_material.set_shader_parameter("watched_intensity", intensity)
	
	# Play "sfx cinematic 53" when the player starts looking at the Entity.
	# Once playing, the audio loops continuously until the player looks away
	# (intensity drops to 0.0). At peak intensity (1.0), the volume reaches
	# its maximum audible level and stays there.
	if intensity > 0.0 and not _watched_audio_was_playing:
		if _watched_audio_player and _watched_audio_player.stream:
			_watched_audio_player.play()
		_watched_audio_was_playing = true
	elif intensity <= 0.0 and _watched_audio_was_playing:
		if _watched_audio_player and _watched_audio_player.playing:
			_watched_audio_player.stop()
		_watched_audio_was_playing = false


func _on_blindness_started() -> void:
	_is_blind = true
	if _blindness_rect:
		# Fade to black over 0.3 seconds
		var tween = create_tween()
		tween.tween_property(_blindness_rect, "color", Color(0, 0, 0, 1), 0.3)


func _on_blindness_ended() -> void:
	_is_blind = false
	if _blindness_rect:
		# Fade back from black over 0.5 seconds
		var tween = create_tween()
		tween.tween_property(_blindness_rect, "color", Color(0, 0, 0, 0), 0.5)
