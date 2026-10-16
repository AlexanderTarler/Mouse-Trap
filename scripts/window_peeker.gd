extends Node3D
class_name WindowPeeker

## WindowPeeker: the scripted Peeker at a window (PeekerManager places it,
## facing in). A visual actor only: no AI, no navigation, not in the
## "entity" group.
##
## It's alive, the way the Entity is:
##   - the Entity's own animations: a slow, breathing idle;
##   - its head follows the player (a LookAtModifier3D on the Head bone,
##     limited, with a little lag), so it watches you back;
##   - the Entity's eye glint, so at night you see the eyes before the shape;
##   - now and then its head twitches aside and back, so a second look is
##     never quite the same.
## It doesn't rise out of the ground: it leans in from beside the window
## frame (quick, from Day 2: it slips up from below the sill). Looked at for
## SPOTTED_VANISH_DELAY, it has held your gaze long enough: it pulls back
## sideways and down into a crouch, and is gone (peeker_vanish_finished).

signal peeker_vanish_finished

@onready var _monster_model: Node3D = $MonsterModel

## Where the model sits (local to the peeker, which is scaled up) while it
## looks in.
@export var model_offset: Vector3 = Vector3(0, -0.57, 0)
## Played when it's seen and goes.
@export var piano_stinger_sfx: AudioStream = null
## From Day 2: everything faster (it's been seen before).
var quick: bool = false

## The player's gaze: within ~20 degrees, closer than GAZE_MAX_DISTANCE.
const GAZE_DOT_THRESHOLD: float = 0.94
const GAZE_MAX_DISTANCE: float = 25.0
## Seen this long, it goes (long enough to be sure of what you saw).
const SPOTTED_VANISH_DELAY: float = 1.325
const QUICK_VANISH_DELAY: float = 0.35

## The Entity's animations (the same resources its AnimationTree plays).
const ANIMATIONS := {
	&"idle": "res://assets/animations/idle.anim",
	&"crouch": "res://assets/animations/entity/crouching_idle.anim",
}
const LIBRARY := &"peek"
## The breathing idle, slowed.
const IDLE_SPEED := 0.7

## Leaning in from beside the frame: this far to the side (local units),
## over this long.
const LEAN_DISTANCE: float = 0.45
const LEAN_DURATION: float = 2.2
## Quick: up from below the sill.
const QUICK_RISE_DISTANCE: float = -0.6
const QUICK_RISE_DURATION: float = 0.35
## Going: back to the side and down.
const PULL_BACK_DOWN: float = -0.5
const PULL_BACK_DURATION: float = 0.45
const QUICK_DUCK_DURATION: float = 0.15

## The head turning to the player: at most this far (degrees), easing
## over HEAD_LAG seconds.
const HEAD_LIMIT_SIDEWAYS := 70.0
const HEAD_LIMIT_UPDOWN := 40.0
const HEAD_LAG := 0.6
## Now and then a twitch: the head snaps aside, then back.
const TWITCH_INTERVAL := Vector2(4.0, 9.0)
const TWITCH_TIME := 0.35
const TWITCH_SNAP := 0.08

## The eye glint (as the Entity's ProfileGlow).
const GLINT_COLOR := Color(0.126, 0.34, 0.233)
const GLINT_ENERGY := 0.7
const GLINT_RANGE := 0.7
## Just in front of the eyes (m).
const GLINT_FORWARD := 0.12

var _cached_camera: Camera3D = null
var _anim: AnimationPlayer = null
var _skeleton: Skeleton3D = null
var _head_bone := -1
var _eye_bones: Array[int] = []
var _look: LookAtModifier3D = null
var _look_target: Node3D = null
var _glint: OmniLight3D = null
var _side := 1.0
var _spotted_timer: float = 0.0
## Arriving (leaning in / rising): not yet watching for the player's gaze.
var _is_rising: bool = true
var _is_vanishing: bool = false
var _twitch_left := 0.0
var _twitch_offset := Vector3.ZERO
var _twitch_time := 0.0


func _ready() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player:
		_cached_camera = player.get_node_or_null("CameraHolder/Camera3D")
	if not _cached_camera:
		_cached_camera = get_viewport().get_camera_3d()
	_side = 1.0 if randf() < 0.5 else -1.0
	_twitch_left = randf_range(TWITCH_INTERVAL.x, TWITCH_INTERVAL.y)
	if not _monster_model:
		_is_rising = false
		return
	_skeleton = _monster_model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	_head_bone = _skeleton.find_bone("Head") if _skeleton else -1
	if _skeleton:
		for eye in ["LeftEye", "RightEye"]:
			if _skeleton.find_bone(eye) >= 0:
				_eye_bones.append(_skeleton.find_bone(eye))
	_setup_animations()
	_setup_head()
	_setup_glint()
	_arrive()


## The Entity's idle and crouch, on the model's own AnimationPlayer.
func _setup_animations() -> void:
	_anim = _monster_model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if not _anim:
		return
	var library := AnimationLibrary.new()
	for anim_name in ANIMATIONS:
		var path: String = ANIMATIONS[anim_name]
		if ResourceLoader.exists(path):
			library.add_animation(anim_name, load(path))
	if _anim.has_animation_library(LIBRARY):
		_anim.remove_animation_library(LIBRARY)
	_anim.add_animation_library(LIBRARY, library)
	# The resources are shared with the Entity: loop by replaying, not by
	# changing their loop mode.
	_anim.animation_finished.connect(_on_animation_finished)
	_play(&"idle", IDLE_SPEED)


func _play(anim_name: StringName, speed: float = 1.0, blend: float = 0.25) -> void:
	var full := StringName("%s/%s" % [LIBRARY, anim_name])
	if _anim and _anim.has_animation(full):
		_anim.play(full, blend, speed)


func _on_animation_finished(anim_name: StringName) -> void:
	if not _is_vanishing and anim_name == StringName("%s/idle" % LIBRARY):
		_play(&"idle", IDLE_SPEED, 0.0)


## Its head follows a marker that stays on the player's camera.
func _setup_head() -> void:
	if not _skeleton or _head_bone < 0:
		return
	_look_target = Node3D.new()
	_look_target.name = "LookTarget"
	_look_target.top_level = true
	add_child(_look_target)
	if _cached_camera:
		_look_target.global_position = _cached_camera.global_position
	_look = LookAtModifier3D.new()
	_look.name = "HeadLook"
	_skeleton.add_child(_look)
	_look.bone_name = "Head"
	_look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	_look.use_angle_limitation = true
	_look.symmetry_limitation = true
	_look.primary_limit_angle = deg_to_rad(HEAD_LIMIT_SIDEWAYS)
	_look.secondary_limit_angle = deg_to_rad(HEAD_LIMIT_UPDOWN)
	_look.duration = HEAD_LAG
	_look.transition_type = Tween.TRANS_SINE
	_look.ease_type = Tween.EASE_OUT
	_look.target_node = _look.get_path_to(_look_target)


func _setup_glint() -> void:
	_glint = OmniLight3D.new()
	_glint.name = "EyeGlint"
	_glint.top_level = true
	_glint.light_color = GLINT_COLOR
	_glint.light_energy = GLINT_ENERGY
	_glint.omni_range = GLINT_RANGE
	_glint.shadow_enabled = false
	add_child(_glint)
	_place_glint()


## Leaning in from beside the frame (quick: up from below the sill).
func _arrive() -> void:
	var start := model_offset
	if quick:
		start.y += QUICK_RISE_DISTANCE
	else:
		start.x += LEAN_DISTANCE * _side
	_monster_model.position = start
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE if not quick else Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT if not quick else Tween.EASE_OUT)
	tween.tween_property(_monster_model, "position", model_offset, QUICK_RISE_DURATION if quick else LEAN_DURATION)
	tween.finished.connect(_on_rise_finished)


func _on_rise_finished() -> void:
	_is_rising = false


func _process(delta: float) -> void:
	_update_head(delta)
	_place_glint()
	if _is_rising or _is_vanishing:
		return
	if _monster_model and _monster_model.position != model_offset:
		_monster_model.position = model_offset
	if is_player_looking_at_me():
		var pm = get_node_or_null("/root/PeekerManager")
		if (pm and pm.peeker_vanish_on_sight) or not pm:
			_spotted_timer += delta
			if _spotted_timer >= (QUICK_VANISH_DELAY if quick else SPOTTED_VANISH_DELAY):
				_vanish()
	else:
		_spotted_timer = 0.0


## The head's target: the player's camera, now and then snapped aside.
func _update_head(delta: float) -> void:
	if not _look or not _cached_camera:
		return
	_twitch_left -= delta
	if _twitch_left <= 0.0 and not _is_vanishing:
		_twitch_left = randf_range(TWITCH_INTERVAL.x, TWITCH_INTERVAL.y)
		_twitch_time = TWITCH_TIME
		_twitch_offset = global_basis.x.normalized() * randf_range(-1.2, 1.2) + Vector3.UP * randf_range(-0.6, 0.4)
		_look.duration = TWITCH_SNAP
	if _twitch_time > 0.0:
		_twitch_time -= delta
		if _twitch_time <= 0.0:
			_twitch_offset = Vector3.ZERO
			_look.duration = TWITCH_SNAP * 2.0
	elif _look.duration < HEAD_LAG and _twitch_offset == Vector3.ZERO:
		_look.duration = minf(_look.duration + delta, HEAD_LAG)
	_look_target.global_position = _cached_camera.global_position + _twitch_offset


## The glint just in front of its eyes (or its head, if it has none).
func _place_glint() -> void:
	if not _glint or not _skeleton or _head_bone < 0:
		return
	var bones: Array[int] = _eye_bones if not _eye_bones.is_empty() else [_head_bone]
	var at := Vector3.ZERO
	for bone in bones:
		at += (_skeleton.global_transform * _skeleton.get_bone_global_pose(bone)).origin
	at /= bones.size()
	var head := _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone)
	_glint.global_position = at + head.basis.z.normalized() * GLINT_FORWARD


## Whether the player is looking straight at this peeker (camera cone).
func is_player_looking_at_me() -> bool:
	if not _cached_camera:
		return false
	var dist_sq = _cached_camera.global_position.distance_squared_to(global_position)
	if dist_sq > GAZE_MAX_DISTANCE * GAZE_MAX_DISTANCE:
		return false
	var cam_forward: Vector3 = -_cached_camera.global_transform.basis.z.normalized()
	var to_peeker: Vector3 = (global_position - _cached_camera.global_position).normalized()
	return cam_forward.dot(to_peeker) >= GAZE_DOT_THRESHOLD


## Seen: back to the side and down, crouching, then gone.
func _vanish() -> void:
	if _is_vanishing:
		return
	_is_vanishing = true
	_play_sfx(piano_stinger_sfx)
	_think_seen()
	if not _monster_model:
		peeker_vanish_finished.emit()
		queue_free()
		return
	_play(&"crouch", 1.4, 0.12)
	var target := model_offset + Vector3(LEAN_DISTANCE * 1.2 * _side, PULL_BACK_DOWN, 0.0)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_monster_model, "position", target, QUICK_DUCK_DURATION if quick else PULL_BACK_DURATION)
	tween.finished.connect(_on_duck_finished)


## What the player makes of it: the first time, the second time.
func _think_seen() -> void:
	var monologue := get_node_or_null("/root/Monologue")
	if not monologue:
		return
	if not monologue.has_thought("peeker_seen_1"):
		monologue.think_when_free("...what was that?", 4.0, "peeker_seen_1", 0.6)
	else:
		monologue.think_when_free("Twice now. Not imagining it.", 4.0, "peeker_seen_2", 0.6)


func _on_duck_finished() -> void:
	peeker_vanish_finished.emit()
	queue_free()


func _play_sfx(stream: AudioStream) -> void:
	if not stream:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = -9.0
	get_tree().current_scene.add_child(player)
	player.global_position = global_position
	player.play()
	player.finished.connect(player.queue_free)
