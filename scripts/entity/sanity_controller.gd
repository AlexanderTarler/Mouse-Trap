extends Node3D
## The Entity's distortion field, felt through the player's own eyes. It is
## hard to look at: when it is close, the player is looking at it AND it can
## see the player, vision swims and won't focus on it, the eyes can't
## converge (double vision), colour drains away, the view narrows into a
## tunnel throbbing with the heartbeat, and whispers rise
## (shaders/distortion_field.gdshader). The closer it is and the longer the
## stare, the stronger; held at full strength, vision nearly blacks out for a
## moment.
##
##   - Only within field_radius (full strength inside full_strength_distance).
##   - Only while the player looks at it (a cone, with a clear line of sight)
##     and it sees the player (EntityPerception.can_see_player).
##   - Not before Night 2, not while the overcharged beam holds it, not
##     during cutscenes (the player's camera must be the current one).
##
## get_gaze_normalized() is the field's strength; the player's camera shake
## follows it.

const DISTORTION_SHADER := preload("res://shaders/distortion_field.gdshader")
const WHISPER_PATH := "res://assets/audio/Entity/Entity_Seen.ogg"
## A second, deeper layer that joins as the field grows strong.
const DEEP_WHISPER_PATH := "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Cinematic/sfx cinematic 53.ogg"
## Below the HUD (200), so the HUD stays readable.
const OVERLAY_LAYER := 190

## The field reaches this far from it (m)...
@export var field_radius: float = 16.0
## ...and is at full strength this close.
@export var full_strength_distance: float = 4.0
## How far off-centre the player can look and still be "looking at it" (degrees).
@export var look_cone_degrees: float = 30.0
## How fast the field grows while all conditions hold (strength per second)...
@export var rise_speed: float = 0.7
## ...and fades when they don't.
@export var fall_speed: float = 0.5
## Seconds at (nearly) full strength before vision nearly blacks out.
@export var burst_after: float = 3.0
## Whisper volume at full strength (linear) and pitch.
@export var whisper_volume: float = 0.56
@export var whisper_pitch: float = 1.3
## The deeper whisper layer joins above this strength.
@export var deep_whisper_threshold: float = 0.55

## Current field strength (0-1).
var level: float = 0.0
var burst: float = 0.0

var _full_time := 0.0
var _burst_tween: Tween = null
var _deep: AudioStreamPlayer = null
var _material: ShaderMaterial = null

@onready var _audio: AudioStreamPlayer = $SanityAudio
@onready var _overlay_layer: CanvasLayer = $OverlayLayer
@onready var _overlay: ColorRect = $OverlayLayer/SanityOverlay


func _ready() -> void:
	# The old ray node is not needed (the line of sight is a direct query).
	if has_node("SanityRayCast"):
		$SanityRayCast.enabled = false

	_audio.stream = _looping(WHISPER_PATH)
	_audio.bus = &"SFX"
	_audio.stop()
	_deep = AudioStreamPlayer.new()
	_deep.stream = _looping(DEEP_WHISPER_PATH)
	_deep.bus = &"SFX"
	add_child(_deep)

	_material = ShaderMaterial.new()
	_material.shader = DISTORTION_SHADER
	_overlay.material = _material
	_overlay.color = Color.WHITE
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	_overlay_layer.layer = OVERLAY_LAYER


func _looping(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var stream := (load(path) as AudioStream).duplicate()
	if "loop" in stream:
		stream.loop = true
	return stream


## The field's strength, 0-1 (the player's camera shake follows it).
func get_gaze_normalized() -> float:
	return clampf(level + burst * 0.5, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	var entity := get_tree().get_first_node_in_group("entity") as Node3D
	var target := _field_strength(entity)
	level = move_toward(level, target, (rise_speed if target > level else fall_speed) * delta)

	# Held at full strength: a moment of near-blackout, then it builds again.
	_full_time = _full_time + delta if level > 0.9 else 0.0
	if _full_time >= burst_after:
		_full_time = 0.0
		_start_burst()

	_update_overlay(entity)
	_update_whispers()


## How strong the field should be right now (0 when any condition fails).
func _field_strength(entity: Node3D) -> float:
	var nm := get_node_or_null("/root/NightManager")
	if nm and "current_night" in nm and nm.current_night < 2:
		return 0.0
	if not entity or not entity.has_method("is_active") or not entity.is_active():
		return 0.0
	if entity.get("is_overcharged") == true:
		return 0.0
	var cam := get_parent() as Camera3D
	if not cam or not cam.current:
		return 0.0

	var chest := entity.global_position + Vector3.UP * 1.2
	var to_it := chest - cam.global_position
	var distance := to_it.length()
	if distance > field_radius or distance < 0.01:
		return 0.0
	if (-cam.global_basis.z).dot(to_it / distance) < cos(deg_to_rad(look_cone_degrees)):
		return 0.0
	if not _clear_line(cam.global_position, chest, entity):
		return 0.0
	var perception = entity.get("perception")
	if not perception or not perception.can_see_player:
		return 0.0

	var closeness := 1.0 - clampf((distance - full_strength_distance) / maxf(field_radius - full_strength_distance, 0.01), 0.0, 1.0)
	return lerpf(0.25, 1.0, closeness)


func _clear_line(from: Vector3, to: Vector3, entity: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, (1 << 0) | (1 << 4))
	var player := get_tree().get_first_node_in_group("player") as CollisionObject3D
	if player:
		query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == entity or (hit.collider as Node).is_in_group("entity")


func _start_burst() -> void:
	if _burst_tween and _burst_tween.is_valid():
		_burst_tween.kill()
	_burst_tween = create_tween()
	_burst_tween.tween_property(self, "burst", 1.0, 0.08)
	_burst_tween.tween_property(self, "burst", 0.0, 0.7).set_ease(Tween.EASE_OUT)


func _update_overlay(entity: Node3D) -> void:
	var strength := maxf(level, burst)
	_overlay.visible = strength > 0.01
	if not _overlay.visible:
		return
	_material.set_shader_parameter("intensity", level)
	_material.set_shader_parameter("burst", burst)
	var size := get_viewport().get_visible_rect().size
	_material.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	var cam := get_parent() as Camera3D
	if cam and entity:
		var chest := entity.global_position + Vector3.UP * 1.2
		if not cam.is_position_behind(chest):
			var on_screen := cam.unproject_position(chest) / size
			_material.set_shader_parameter("center", on_screen)


func _update_whispers() -> void:
	var strength := maxf(level, burst)
	if strength > 0.02:
		if _audio.stream and not _audio.playing:
			_audio.play()
		_audio.volume_db = linear_to_db(maxf(whisper_volume * strength, 0.001))
		# The pitch drifts, more the stronger it is.
		_audio.pitch_scale = whisper_pitch + sin(Time.get_ticks_msec() * 0.0013) * 0.1 * strength
	elif _audio.playing:
		_audio.stop()

	var deep := clampf((strength - deep_whisper_threshold) / (1.0 - deep_whisper_threshold), 0.0, 1.0)
	if deep > 0.0:
		if _deep.stream and not _deep.playing:
			_deep.play()
		_deep.volume_db = linear_to_db(maxf(0.5 * deep, 0.001))
	elif _deep.playing:
		_deep.stop()
