class_name EntityAnimator
extends Node

## How the Entity looks while it does what it does:
##   - which animation plays (from how it moves, what its state asked for this
##     frame, the move it is in the middle of), and how fast;
##   - one-shots that hold it still for a moment (the roar);
##   - its feet on the ground whatever plays (each animation holds the body at
##     a different height), and its head under the ceiling indoors;
##   - the glint around its eyes;
##   - being puppeted by a cutscene (cinematic).
## The AnimationTree is advanced by hand, at the speed asked (the tree ignores
## the AnimationPlayer's speed): 0 holds a pose.
##
## States use it through the Entity (play_anim, crawl, play_oneshot,
## set_eye_glow).

## Reference speeds the cycles were authored for (m/s).
const ANIM_WALK_SPEED := 2.5
const ANIM_RUN_SPEED := 6.0
## How fast LowCrawl moves it played at normal speed (m/s).
const ANIM_CRAWL_SPEED := 1.3
## The top of its head at full size, walking upright (m).
const TALLEST := 2.9
## Space kept between its head and a ceiling (m).
const HEADROOM := 0.2
const MIN_SIZE := 0.7
const HEADROOM_CHECK_INTERVAL := 0.15
## On the wall (climbing up, clinging, down, in through an upstairs window)
## the model is lowered this much more (m): it hung too high on the wall
## for the look of it, and whatever it plays while holding on (breaking the
## upstairs glass) as much. (Climbing in has its own lift taken out:
## tools/process_entity_anims.gd; it's carried up over the sill instead.
## CLIMB_IN_EXTRA_DROP eases it down more as it goes, if ever needed.)
const CLIMB_DROP := {&"ClimbUp": 1.0, &"ClimbDown": 1.0, &"ClimbIn": 1.0}
const CLINGING_DROP := 1.0
const CLIMB_IN_EXTRA_DROP := 0.0
const CLIMB_IN_EASE := 1.2
## Most of its animations hold the body higher than the walk cycle does, so
## it floated above the ground in them. The model is lowered by this much
## (measured: each animation's lowest hand/foot against the walk's).
const ANIM_GROUND_OFFSET := {
	&"Idle": -0.37,
	&"running_crawl": -0.43,
	&"entity_in_light": -0.31,
	&"AttackWindow": -0.38,
	&"entity_running": -0.17,
	# The Mixamo set processed by tools/process_entity_anims.gd. Positive:
	# it crouches, crawls or lies lower than the walk, so the model is raised.
	&"Crouch": 0.21,
	&"LookAround": -0.24,
	&"LowCrawl": 0.34,
	&"Roar": -0.22,
	&"Dying": 0.33,
	&"NeckBite": -0.25,
	&"Punch": -0.27,
	&"HitReact": -0.32,
	&"DropLand": -0.10,
	&"ClimbIn": 0.0,
	&"DiveIn": 0.0,
}

var entity: Entity

var tree: AnimationTree = null
var playback: AnimationNodeStateMachinePlayback = null
var player: AnimationPlayer = null
## Indoors it shrinks a little to fit under the ceiling (1 = full size).
var size := 1.0

# ─── This frame's wishes (reset every physics frame: begin_frame) ───────────
## The animation its state asked for, whatever it is doing ("" for none).
var override_anim: StringName = &""
var override_speed := 1.0
## This frame's way of moving: &"crawl" (low, on its belly) or the usual.
var gait: StringName = &""

## How its AnimationTree normally advances (cinematic can stop it).
var _tree_mode := AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
var _model: Node3D = null
var _model_base_y := 0.0
var _model_base_scale := Vector3.ONE
var _eye_glow: OmniLight3D = null
var _eye_glow_energy := 0.0
## The glow is only a glint around its eyes (0.7 m): in the dark it's a shape
## the flashlight finds, not a lamp. Flaring (the charge wind-up) it grows.
var _eye_glow_range := 0.0
var _glow_base_y := 0.0
var _target_size := 1.0
var _headroom_check := 0.0
var _climb_in_time := 0.0
## A one-shot that holds it still for a moment (play_oneshot): the roar.
var _oneshot_anim: StringName = &""
var _oneshot_left := 0.0
var _oneshot_speed := 1.0
## The physics tick the animation tree was last advanced on (_process covers
## the ones it wasn't).
var _advanced_frame := -1
## In a cinematic: the speed its animation plays at; -1 otherwise.
var _cinematic_speed := -1.0


func setup(owner_entity: Entity) -> void:
	entity = owner_entity
	_model = entity.model
	tree = entity.get_node_or_null("AnimationTree") as AnimationTree
	_eye_glow = entity.get_node_or_null("ProfileGlow") as OmniLight3D
	if _model:
		_model_base_y = _model.position.y
		_model_base_scale = _model.scale
	if _eye_glow:
		_eye_glow_energy = _eye_glow.light_energy
		_eye_glow_range = _eye_glow.omni_range
		_glow_base_y = _eye_glow.position.y
	if tree:
		_tree_mode = tree.callback_mode_process
		playback = tree.get("parameters/playback")
		player = tree.get_node_or_null(tree.anim_player) as AnimationPlayer


## Whether it has an animation tree to play anything on.
func has_tree() -> bool:
	return playback != null


func current() -> StringName:
	return playback.get_current_node() if playback else &""


# ═════════════════════════════════════════════════════════════════════════════
# WHAT STATES ASK FOR
# ═════════════════════════════════════════════════════════════════════════════

## A new physics frame: this frame's wishes start empty.
func begin_frame() -> void:
	override_anim = &""
	override_speed = 1.0
	gait = &""


## Stops it where it is and plays `anim` for `seconds`, whatever its state
## wants meanwhile (the state goes on underneath).
func play_oneshot(anim: StringName, seconds: float, speed: float = 1.0) -> void:
	_oneshot_anim = anim
	_oneshot_left = seconds
	_oneshot_speed = speed
	if playback:
		playback.start(anim)


func is_playing_oneshot() -> bool:
	return _oneshot_left > 0.0


func cancel_oneshot() -> void:
	_oneshot_left = 0.0


## Counts a one-shot down. While one plays and the body is `free` (not in
## the middle of a move or on the wall) it takes this frame's animation:
## true then (the Entity stands still and faces the player).
func update_oneshot(delta: float, free: bool) -> bool:
	if _oneshot_left <= 0.0:
		return false
	_oneshot_left -= delta
	if not free:
		return false
	override_anim = _oneshot_anim
	override_speed = _oneshot_speed
	return true


## Starts `anim` at once, at normal speed (dying, the bite).
func start(anim: StringName) -> void:
	if playback:
		playback.start(anim)
	if player:
		player.speed_scale = 1.0


## Scales the glow around its head: 1 is normal, higher flares it (the charge
## wind-up).
func set_eye_glow(multiplier: float) -> void:
	if _eye_glow:
		_eye_glow.light_energy = _eye_glow_energy * multiplier
		_eye_glow.omni_range = _eye_glow_range * (1.0 + (multiplier - 1.0) * 0.6)


# ═════════════════════════════════════════════════════════════════════════════
# CUTSCENES
# ═════════════════════════════════════════════════════════════════════════════

## Puppeted by a cutscene: plays `anim` at `speed` (0 holds the pose). The
## tree stops advancing on its own; _process plays it on at that speed.
func cinematic(anim: StringName, speed: float) -> void:
	if playback and playback.get_current_node() != anim:
		playback.start(anim)
	if player:
		player.speed_scale = speed
	_cinematic_speed = speed
	if tree and tree.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
		tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


## Its own again after a cutscene's frozen pose.
func resume() -> void:
	_cinematic_speed = -1.0
	if tree:
		tree.callback_mode_process = _tree_mode
	if player:
		player.speed_scale = 1.0


# ═════════════════════════════════════════════════════════════════════════════
# EVERY FRAME
# ═════════════════════════════════════════════════════════════════════════════

## Picks this physics frame's animation and advances the tree (from
## Entity._physics_process).
func update(delta: float) -> void:
	if not playback:
		return
	var moves := entity.traversal
	var real := entity.get_real_velocity()
	var horizontal_speed := Vector2(real.x, real.z).length()
	var anim: StringName
	var speed_scale := 1.0
	if moves.is_active():
		if moves.anim != &"":
			anim = moves.anim
		else:
			anim = &"EnterWindow" if moves.kind == CabinEntryLink.Kind.WINDOW else &"Stalk"
	elif moves.is_clinging() and override_anim == &"":
		# Holding on to the wall: the climb pose, frozen (playing on in place
		# looked like climbing on the spot); it moves only while it shifts
		# (ducking below the sill, coming back up).
		anim = &"ClimbUp"
		speed_scale = 0.6 if entity.global_position.distance_to(moves.perch_hold()) > 0.05 else 0.0
	elif override_anim != &"":
		anim = override_anim
		speed_scale = override_speed
	elif gait == &"crawl" or (entity.perception and entity.perception.entity_inside):
		# Low, crawling, in the house (and wherever it creeps): the crawl
		# played as fast as it actually moves.
		if horizontal_speed > 0.2:
			anim = &"LowCrawl"
			speed_scale = clampf(horizontal_speed / ANIM_CRAWL_SPEED, 0.6, 2.0)
		else:
			anim = &"Crouch"
	elif horizontal_speed > 4.5:
		anim = &"running_crawl"
		speed_scale = clampf(horizontal_speed / ANIM_RUN_SPEED, 0.8, 2.0)
	elif horizontal_speed > 0.2:
		anim = &"Stalk"
		speed_scale = clampf(horizontal_speed / ANIM_WALK_SPEED, 0.6, 2.0)
	else:
		anim = &"Idle"
	if playback.get_current_node() != anim:
		playback.travel(anim)
	if player:
		player.speed_scale = speed_scale
	# The AnimationTree ignores the player's speed: it's advanced here by
	# hand, at the speed asked (0 holds the pose: clinging still).
	if tree:
		if tree.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
			tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		tree.advance(delta * speed_scale)
		_advanced_frame = Engine.get_physics_frames()


## Keeps its feet on the ground whatever animation plays (ANIM_GROUND_OFFSET),
## easing between them as the animations cross-fade; and indoors keeps its
## head under the ceiling (walking upright it is taller than the ground
## floor's 2.85 m, and its head poked up through the floor above).
func _process(delta: float) -> void:
	# The animation tree is advanced by hand (update, at the speed asked); a
	# tick that didn't (caught, dying, set aside) plays it on as is.
	if tree and tree.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL \
			and _advanced_frame != Engine.get_physics_frames():
		tree.advance(delta * (_cinematic_speed if _cinematic_speed >= 0.0 else 1.0))
	if not _model or not playback or not entity.visible:
		return
	_headroom_check -= delta
	if _headroom_check <= 0.0:
		_headroom_check = HEADROOM_CHECK_INTERVAL
		_target_size = _fit_under_ceiling()
	size = lerpf(size, _target_size, clampf(delta * 4.0, 0.0, 1.0))
	_model.scale = _model_base_scale * size
	var now := playback.get_current_node()
	var drop: float = CLIMB_DROP.get(now, 0.0)
	if entity.traversal.is_clinging() and not CLIMB_DROP.has(now):
		drop = CLINGING_DROP
	if now == EntityTraversal.CLIMB_IN_ANIM:
		_climb_in_time += delta
		drop += CLIMB_IN_EXTRA_DROP * smoothstep(0.0, CLIMB_IN_EASE, _climb_in_time)
	else:
		_climb_in_time = 0.0
	if _eye_glow:
		_eye_glow.position.y = _glow_base_y * size - drop
	var target: float = _model_base_y + ANIM_GROUND_OFFSET.get(now, 0.0) * size - drop
	_model.position.y = lerpf(_model.position.y, target, clampf(delta * 8.0, 0.0, 1.0))


## Its size under whatever is above it indoors: full size if its head fits
## (TALLEST plus HEADROOM), smaller if not, never below MIN_SIZE.
func _fit_under_ceiling() -> float:
	if not entity.perception or not entity.perception.entity_inside or not entity.is_inside_tree():
		return 1.0
	var feet := entity.global_position
	var query := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.5, feet + Vector3.UP * (TALLEST + HEADROOM), Entity.LAYER_WORLD)
	query.exclude = [entity.get_rid()]
	var hit := entity.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 1.0
	return clampf((hit.position.y - feet.y - HEADROOM) / TALLEST, MIN_SIZE, 1.0)
