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
const PLAY_WATCHED_AUDIO := false


func _ready() -> void:
	# ─── DARKNESS/BLINDNESS OVERLAY REMOVED ─────────────────────
	# The visual darkness/blindness screen effect has been COMPLETELY removed.
	# Previously this applied a distortion.gdshader (vignette darkening,
	# chromatic aberration, pixelation) and a full-screen BlindnessRect that
	# faded to black. Both mechanisms are now disabled — the player instead
	# gets an increasingly violent camera shake (handled by player_controller.gd).
	_effect_time = 0.0
	
	# Make this cover the full screen (kept for layout, render disabled)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Set up blindness rect — fully hidden and transparent (no black fade)
	if _blindness_rect:
		_blindness_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_blindness_rect.color = Color(0, 0, 0, 0)
		_blindness_rect.visible = false
	
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
		perception_manager = get_tree().get_first_node_in_group("perception_manager")
	
	# Connect to PerceptionManager signals
	if perception_manager:
		perception_manager.watched_intensity_changed.connect(_on_watched_intensity_changed)
		perception_manager.blindness_started.connect(_on_blindness_started)
		perception_manager.blindness_ended.connect(_on_blindness_ended)
		print("WatchedEffect: Connected to PerceptionManager")
	else:
		print("WatchedEffect: PerceptionManager not found")


func _process(delta: float) -> void:
	# The shader-based darkness overlay is completely removed.
	# No shader material is created/assigned, so _shader_material is null
	# and no darkness/vignette effect can render. Kept as a no-op.
	pass


func _on_watched_intensity_changed(intensity: float) -> void:
	# Do NOT feed watched_intensity into any darkness shader.
	# The visual darkness overlay is gone — intensity is still used below
	# to drive the watched/whisper audio cue.
	
	# The whispers moved into the Entity's distortion field
	# (sanity_controller.gd), which only works close by, while the player
	# looks at it AND it sees the player. This looped on any glance within
	# 40 m, so it stays off.
	if not PLAY_WATCHED_AUDIO:
		return
	if intensity > 0.0 and not _watched_audio_was_playing:
		if _watched_audio_player and _watched_audio_player.stream:
			_watched_audio_player.play()
		_watched_audio_was_playing = true
	elif intensity <= 0.0 and _watched_audio_was_playing:
		if _watched_audio_player and _watched_audio_player.playing:
			_watched_audio_player.stop()
		_watched_audio_was_playing = false


func _on_blindness_started() -> void:
	# Blindness (full-screen black) COMPLETELY REMOVED.
	# No-op — the player should NOT see the screen fade to black.
	_is_blind = false
	return


func _on_blindness_ended() -> void:
	# Blindness (full-screen black) COMPLETELY REMOVED.
	# No-op — the player should NOT see the screen fade back from black.
	_is_blind = false
	return
