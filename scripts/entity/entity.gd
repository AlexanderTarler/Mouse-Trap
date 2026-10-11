class_name Entity
extends CharacterBody3D

## The Entity: the body, movement and public API.
##
## Decisions live elsewhere:
##   EntityBrain       - the state machine (one class per state in states/).
##   EntityPerception  - what it knows this frame (sight, hearing, flashlight).
##   EntityWorld       - where things are (vantage points, entries, light).
##   EntityConfidence  - how bold it is.
##   EntityAudio       - its sounds.
##   EntityTraces      - claw prints and gouges it leaves behind.
##
## Conventions:
##   - The BODY turns to face where it looks; the model is a child with no
##     rotation of its own. Forward is +Z (the model faces +Z).
##   - All tuning values come from `config` (resources/entity_config.tres).
##   - States never teleport the Entity where the player can see it; use
##     try_teleport(), which refuses if either end is in view.

enum State {
	DORMANT,      ## Hidden and inactive (daytime, story pauses).
	OBSERVE,      ## Watching the cabin from the treeline.
	STALK,        ## Following the player outside.
	SEARCH,       ## Investigating where the player was seen or heard.
	CHARGE,       ## Committed lunge at the player.
	APPROACH,     ## Walking up to a window or the door.
	PEEK,         ## Staring in through a window.
	BREACH,       ## Smashing a window's glass and planks.
	ENTER,        ## Climbing in through a window or walking in through the door.
	HUNT,         ## Searching the cabin interior.
	STANDOFF,     ## Held in place by the flashlight beam.
	FLEE,         ## Running from the light (or leaving the cabin).
	STUNNED,      ## Paralysed by the portable lamp's overload.
	SABOTAGE,     ## Breaking the fuse box.
	ATTACK_LAMP,  ## Smashing the portable lamp.
	LURE,         ## Knocking at another room's window to draw the player away.
}

const CONFIG: EntityConfig = preload("res://resources/entity_config.tres")

## Physics layers. Note the player's body is on layer 1 (with the world), so
## every raycast against LAYER_WORLD must exclude the player.
const LAYER_WORLD := 1 << 0   ## Cabin, ground, door, props, player body.
const LAYER_PLAYER := 1 << 1
const LAYER_ENTITY := 1 << 4  ## Layer 5.
## Trees and rocks (layers 3 and 4) are deliberately not collided with: the
## Entity phases through foliage.
const MOVE_MASK := LAYER_WORLD | LAYER_PLAYER

signal caught_player

@export var wood_footsteps: Array[AudioStream] = []
@export var grass_footsteps: Array[AudioStream] = []
## Optional: assign in the level, otherwise found via class/group lookup.
@export var fuse_box_node: Node = null
@export var fuse_waypoint: Marker3D = null

## When false (debug console), reaching the player doesn't kill them.
var can_kill: bool = true
## Set by the overload stun and kept until the player is back in the cabin
## (no totem teleport meanwhile); read by totem_anchor.gd.
var totem_defense_disabled: bool = false
## True during the Night 2 van chase (a scripted, fully aware pursuit).
var van_chase_active: bool = false
var is_enraged: bool = false

var config: EntityConfig = CONFIG
var brain: EntityBrain
var perception: EntityPerception
var world: EntityWorld
var confidence: EntityConfidence
var audio: EntityAudio
var traces: EntityTraces

var _player: Node3D = null
var _night_manager: Node = null
var _is_active: bool = false

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var model: Node3D = get_node_or_null("MonsterModel")
@onready var _anim_tree: AnimationTree = get_node_or_null("AnimationTree")

var _anim_playback: AnimationNodeStateMachinePlayback = null
var _anim_player: AnimationPlayer = null
var _catch_area: Area3D = null
@onready var _eye_glow: OmniLight3D = get_node_or_null("ProfileGlow") as OmniLight3D
@onready var _eye_glow_energy: float = _eye_glow.light_energy if _eye_glow else 0.0
## The glow is only a glint around its eyes (0.7 m): in the dark it's a shape
## the flashlight finds, not a lamp. Flaring (the charge wind-up) it grows.
@onready var _eye_glow_range: float = _eye_glow.omni_range if _eye_glow else 0.0

# ─── Movement state (reset every physics frame by the active state) ─────────
var _desired_velocity := Vector3.ZERO
var _look_target = null            ## Vector3 or null: face this instead of the movement direction.
var _anim_override: StringName = &""
var _anim_override_speed := 1.0
## This frame's way of moving: &"crawl" (low, on its belly) or the usual.
var _gait: StringName = &""
## A one-shot that holds it still for a moment (play_oneshot): the roar.
var _oneshot_anim: StringName = &""
var _oneshot_left := 0.0
var _oneshot_speed := 1.0
## The good ending: dying (die()).
var _dying := false
var _model_base_y := 0.0
var _model_base_scale := Vector3.ONE
var _glow_base_y := 0.0
## Indoors it shrinks a little to fit under the ceiling (1 = full size).
var _size := 1.0
var _target_size := 1.0
var _headroom_check := 0.0
var _last_nav_target := Vector3.INF
var _nav_retarget_timer := 0.0
const NAV_RETARGET_INTERVAL := 0.3
const NAV_RETARGET_DISTANCE := 0.5
const TURN_SPEED := 8.0

# ─── Link traversal (climbing through a window / walking through the door) ──
var _traversal: Tween = null
var _traversal_kind := -1
## Animation for the current leg of a traversal (empty: pick from the kind).
var _traversal_anim: StringName = &""

# ─── Clinging to the wall outside an upstairs window ────────────────────────
var _perch_link: CabinEntryLink = null
var _perch_offset := Vector3.ZERO
var _climb_tap_left := 0.0
const CLIMB_TAP_INTERVAL := 0.95

# ─── Stuck detection ─────────────────────────────────────────────────────────
var _stuck_timer := 0.0
var _stuck_anchor := Vector3.ZERO


func _ready() -> void:
	add_to_group("entity")
	collision_layer = LAYER_ENTITY
	collision_mask = MOVE_MASK
	nav_agent.avoidance_enabled = false
	nav_agent.path_desired_distance = PATH_DESIRED_DISTANCE
	nav_agent.target_desired_distance = 0.4
	nav_agent.link_reached.connect(_on_link_reached)

	if model:
		_model_base_y = model.position.y
		_model_base_scale = model.scale
	if _eye_glow:
		_glow_base_y = _eye_glow.position.y
	if _anim_tree:
		_anim_playback = _anim_tree.get("parameters/playback")
		_anim_player = _anim_tree.get_node_or_null(_anim_tree.anim_player) as AnimationPlayer

	_catch_area = Area3D.new()
	_catch_area.name = "CatchArea"
	_catch_area.collision_layer = 0
	_catch_area.collision_mask = LAYER_WORLD | LAYER_PLAYER
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = config.catch_distance
	shape.shape = sphere
	shape.position.y = 0.8
	_catch_area.add_child(shape)
	_catch_area.body_entered.connect(_on_catch_area_body_entered)
	add_child(_catch_area)

	perception = _add_module(EntityPerception.new(), "Perception")
	world = _add_module(EntityWorld.new(), "World")
	confidence = _add_module(EntityConfidence.new(), "EntityConfidence")
	audio = _add_module(EntityAudio.new(), "Audio")
	traces = _add_module(EntityTraces.new(), "Traces")
	brain = _add_module(EntityBrain.new(), "Brain")
	if OS.is_debug_build():
		_add_module(EntityDebugOverlay.new(), "DebugOverlay")

	_set_hidden(true)
	_connect_night_manager.call_deferred()


func _add_module(module: Node, module_name: String) -> Node:
	module.name = module_name
	add_child(module)
	if module.has_method("setup"):
		module.setup(self)
	return module


func _connect_night_manager() -> void:
	_night_manager = get_node_or_null("/root/NightManager")
	if not _night_manager:
		return
	_night_manager.night_started.connect(_on_night_started)
	_night_manager.first_chase_started.connect(_on_first_chase_started)
	if _night_manager.is_night_active:
		_on_night_started(_night_manager.current_night)


# ═════════════════════════════════════════════════════════════════════════════
# PUBLIC API (used by other game systems)
# ═════════════════════════════════════════════════════════════════════════════

func activate() -> void:
	if not _player:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	_is_active = true
	is_enraged = false
	_set_hidden(false)
	velocity = Vector3.ZERO


func deactivate() -> void:
	_is_active = false
	van_chase_active = false
	_oneshot_left = 0.0
	_cancel_traversal()
	_release_perch()
	velocity = Vector3.ZERO
	_set_hidden(true)
	if brain:
		brain.force(State.DORMANT)
	if audio:
		audio.stop_all()


## True while the Entity is present in the world (visible and thinking).
## perception_manager.gd and sanity_controller.gd gate their effects on this.
func is_active() -> bool:
	return _is_active and visible and process_mode != PROCESS_MODE_DISABLED


## Asks the brain to switch state (debug console, scripted events).
func request_state(state: State, data: Dictionary = {}) -> void:
	if not _is_active:
		activate()
	brain.force(state, data)


## Puppets it for an ending cutscene: out of the game (no thinking, moving,
## catching or sounds of its own), visible at `xform`, playing `anim`. Call it
## every frame to move it; deactivate() or restore it afterwards.
func cinematic_pose(xform: Transform3D, anim: StringName, anim_speed: float = 1.0) -> void:
	if _is_active or is_traversing() or is_clinging():
		_is_active = false
		_cancel_traversal()
		_release_perch()
		audio.stop_all()
	velocity = Vector3.ZERO
	visible = true
	if collision_shape:
		collision_shape.disabled = true
	if _catch_area:
		_catch_area.monitoring = false
	# Keep its own scale; `xform` only places and turns it.
	global_transform = Transform3D(xform.basis.orthonormalized() * Basis.from_scale(scale), xform.origin)
	if _anim_playback and _anim_playback.get_current_node() != anim:
		_anim_playback.start(anim)
	if _anim_player:
		_anim_player.speed_scale = anim_speed


func get_state() -> State:
	return brain.state_id if brain else State.DORMANT


func get_state_name() -> String:
	return State.keys()[get_state()]


## Starts the Night 2 van chase: appears at `spawn_position` and pursues the
## player until they reach the cabin, then vanishes for the rest of the night.
func start_van_chase(spawn_position: Vector3) -> void:
	if van_chase_active:
		return
	activate()
	van_chase_active = true
	global_position = spawn_position
	velocity = Vector3.ZERO
	brain.force(State.STALK)


## Called by the player every frame. `strength` (0-1): how strongly the beam
## hits (closer and more centred is stronger).
func on_flashlight(is_hit: bool, overcharged: bool, strength: float = 1.0) -> void:
	if perception:
		perception.on_flashlight(is_hit, overcharged, strength)


## True while an overcharged beam is on the Entity (sanity/perception effects
## are suppressed during this moment of player power).
var is_overcharged: bool:
	get:
		return perception != null and perception.overcharged


## Called through NoiseEvent.emit(): a noise of `kind` at `noise_position`.
func hear_noise(noise_position: Vector3, kind: StringName) -> void:
	if _is_active and perception:
		perception.hear_noise(noise_position, kind)


## Portable lamp overload. Ignored when far away or already stunned.
func trigger_overload_stun(trap_position: Vector3, duration: float = 30.0) -> void:
	if not _is_active or get_state() == State.STUNNED:
		return
	if global_position.distance_to(trap_position) > 25.0:
		return
	brain.force(State.STUNNED, {"duration": duration})


## The generator died. If it was stunned, the stun breaks and it is enraged
## for the rest of the night.
func on_generator_blackout() -> void:
	if get_state() != State.STUNNED:
		return
	is_enraged = true
	audio.play_roar()
	brain.force(State.STALK if perception.player_outside else State.HUNT)
	play_oneshot(&"Roar", ROAR_TIME, ROAR_SPEED)


## Totem defence: appear at `position` and charge the player.
func defend_totem(position: Vector3) -> void:
	if not _is_active:
		return
	var nav_map := get_world_3d().navigation_map
	var snapped := NavigationServer3D.map_get_closest_point(nav_map, position)
	global_position = snapped
	velocity = Vector3.ZERO
	# No roar first: the defence is a surprise.
	brain.force(State.CHARGE, {"committed": true, "no_roar": true})


## Debug console: jump to a treeline vantage point (even if in view) and watch.
func debug_relocate() -> void:
	if not _is_active:
		activate()
	var spot := world.pick_vantage_point(true)
	if spot:
		_teleport(world.snap_to_navmesh(spot.global_position))
	brain.force(State.OBSERVE)


func get_confidence_module() -> EntityConfidence:
	return confidence


func get_player() -> Node3D:
	return _player


func get_night_manager() -> Node:
	return _night_manager


func current_night() -> int:
	return _night_manager.current_night if _night_manager else 3


func is_dev_mode() -> bool:
	return _night_manager != null and _night_manager.get("is_dev_mode") == true


## Night 1 is watch-only; from Night 2 it may come to the windows.
func can_approach_cabin() -> bool:
	return is_dev_mode() or current_night() >= 2


## Night 2 it can break glass but not planks; from Night 3, planks too.
func can_break_planks() -> bool:
	return is_dev_mode() or current_night() >= 3


func speed_multiplier() -> float:
	return config.enraged_speed_multiplier if is_enraged else 1.0


# ═════════════════════════════════════════════════════════════════════════════
# MOVEMENT (called by states every frame)
# ═════════════════════════════════════════════════════════════════════════════

## Walks along the navmesh toward `target`. Returns the remaining distance
## (see reach_distance: a target on another floor is never "close").
func move_to(target: Vector3, speed: float) -> float:
	_nav_retarget_timer -= get_physics_process_delta_time()
	if _last_nav_target.distance_to(target) > NAV_RETARGET_DISTANCE and _nav_retarget_timer <= 0.0:
		nav_agent.target_position = target
		_last_nav_target = target
		_nav_retarget_timer = NAV_RETARGET_INTERVAL
	var next := nav_agent.get_next_path_position()
	# A path point right above or below it (the navmesh riding over a step or
	# a low rock): it can't get any closer to it on the flat, and the agent
	# only counts a point as reached within PATH_DESIRED_DISTANCE in 3D, so
	# it stood there for good. The reach distance covers the gap until the
	# agent has moved on to the next point.
	var gap := absf(next.y - global_position.y)
	if _flat_distance(global_position, next) < 0.3 and gap > PATH_DESIRED_DISTANCE * 0.8:
		nav_agent.path_desired_distance = gap + 0.2
	elif nav_agent.path_desired_distance != PATH_DESIRED_DISTANCE:
		nav_agent.path_desired_distance = PATH_DESIRED_DISTANCE
	if not nav_agent.is_navigation_finished():
		_set_move_direction(next - global_position, speed * speed_multiplier())
	return reach_distance(global_position, target)


## Moves straight toward `target`, ignoring the navmesh (short hops only).
func move_direct(target: Vector3, speed: float) -> float:
	_set_move_direction(target - global_position, speed * speed_multiplier())
	return reach_distance(global_position, target)


## True when the navmesh has no route closer than `tolerance` to `target`.
func is_unreachable(target: Vector3, tolerance: float = 1.5) -> bool:
	var map := get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, global_position, target, true)
	return path.is_empty() or reach_distance(path[path.size() - 1], target) > tolerance


func stop() -> void:
	_desired_velocity = Vector3.ZERO


func face(target: Vector3) -> void:
	_look_target = target


## This frame's animation, whatever it is doing (states call it every frame).
func play_anim(anim: StringName, speed: float = 1.0) -> void:
	_anim_override = anim
	_anim_override_speed = speed


## Moves low this frame (LowCrawl when it moves, Crouch when it doesn't).
func crawl() -> void:
	_gait = &"crawl"


## Stops where it is, faces the player and plays `anim` for `seconds`,
## whatever its state wants meanwhile (the state goes on underneath).
func play_oneshot(anim: StringName, seconds: float, speed: float = 1.0) -> void:
	_oneshot_anim = anim
	_oneshot_left = seconds
	_oneshot_speed = speed
	if _anim_playback:
		_anim_playback.start(anim)


func is_playing_oneshot() -> bool:
	return _oneshot_left > 0.0


func cancel_oneshot() -> void:
	_oneshot_left = 0.0


## The totem burned (the good ending): it dies where it stands, then is gone.
func die() -> void:
	if _dying:
		return
	_dying = true
	var seen := visible and not is_traversing() and not is_clinging() and _anim_playback != null
	_is_active = false
	_cancel_traversal()
	_release_perch()
	velocity = Vector3.ZERO
	audio.stop_all()
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if _catch_area:
		_catch_area.set_deferred("monitoring", false)
	if seen:
		if _player:
			_turn_towards(_player.global_position)
		_anim_playback.start(&"Dying")
		if _anim_player:
			_anim_player.speed_scale = 1.0
		await get_tree().create_timer(DYING_TIME).timeout
	hide()
	process_mode = Node.PROCESS_MODE_DISABLED


## Turns at once to face `target` (flat).
func _turn_towards(target: Vector3) -> void:
	var to := target - global_position
	if Vector2(to.x, to.z).length() > 0.01:
		rotation.y = atan2(to.x, to.z)


## Scales the glow around its head: 1 is normal, higher flares it (the charge
## wind-up).
func set_eye_glow(multiplier: float) -> void:
	if _eye_glow:
		_eye_glow.light_energy = _eye_glow_energy * multiplier
		_eye_glow.omni_range = _eye_glow_range * (1.0 + (multiplier - 1.0) * 0.6)


## Teleports only if neither the current position nor `target` is in the
## player's view, and it isn't in the middle of a move (climbing down a wall,
## vaulting a window) or holding on to a wall. Returns whether it happened.
func try_teleport(target: Vector3) -> bool:
	if is_traversing() or is_clinging():
		return false
	if perception.is_in_player_view(global_position) or perception.is_in_player_view(target):
		return false
	_teleport(target)
	return true


func _teleport(target: Vector3) -> void:
	_cancel_traversal()
	_release_perch()
	global_position = target
	velocity = Vector3.ZERO
	nav_agent.target_position = target
	_last_nav_target = target
	_stuck_timer = 0.0
	_stuck_anchor = target


func is_traversing() -> bool:
	return _traversal != null


func _set_move_direction(direction: Vector3, speed: float) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	_desired_velocity = direction.normalized() * speed


## How close (3D) a path point must be to count as reached (see move_to).
const PATH_DESIRED_DISTANCE := 0.6


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Height difference beyond which two points are on different floors.
const FLOOR_GAP := 1.5

## Distance for "have I got there?": horizontal, so slopes and step heights
## don't matter, unless the points are on different floors: then the height
## is added, so standing below an upstairs room never counts as being in it.
static func reach_distance(a: Vector3, b: Vector3) -> float:
	var flat := _flat_distance(a, b)
	var rise := absf(a.y - b.y)
	return flat + rise if rise > FLOOR_GAP else flat


# ═════════════════════════════════════════════════════════════════════════════
# FRAME LOOP
# ═════════════════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	if not _is_active or not _player:
		return

	_desired_velocity = Vector3.ZERO
	_look_target = null
	_anim_override = &""
	_anim_override_speed = 1.0
	_gait = &""

	# The totem defence, off since the lamp's stun, comes back once the
	# player is inside the cabin again.
	if totem_defense_disabled and perception.player_inside and brain.state_id != State.STUNNED:
		totem_defense_disabled = false

	if not is_traversing():
		brain.tick(delta)
		if not is_clinging():
			_check_link_crossing()
	if _oneshot_left > 0.0:
		_oneshot_left -= delta
		if not is_traversing() and not is_clinging():
			_desired_velocity = Vector3.ZERO
			_look_target = _player.global_position
			_anim_override = _oneshot_anim
			_anim_override_speed = _oneshot_speed

	if is_traversing():
		_update_climb_sounds(delta)
		_update_animation(delta)
		return
	if is_clinging():
		# Holding on outside the window: no gravity, no walking.
		var hold := world.perch_position(_perch_link) + _perch_offset
		global_position = global_position.lerp(hold, clampf(delta * 6.0, 0.0, 1.0))
		velocity = Vector3.ZERO
		_face_window(_perch_link)
		_update_animation(delta)
		return

	velocity.x = _desired_velocity.x
	velocity.z = _desired_velocity.z
	if is_on_floor():
		velocity.y = 0.0
		# On a slope (the stair ramp) move along the floor: pushing
		# horizontally into it stalls the capsule partway up.
		if get_floor_normal().y < 0.99:
			velocity = velocity.slide(get_floor_normal()).normalized() * velocity.length()
	else:
		velocity += get_gravity() * delta
	move_and_slide()

	_update_facing(delta)
	_update_stuck(delta)
	_check_catch()
	traces.update_tracks(is_on_floor())
	var ground_speed := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	audio.update_footsteps(delta, ground_speed)
	audio.update_floor_creaks(delta, ground_speed)
	audio.update_murmurs(delta)
	audio.update_mimicry(delta)
	_update_animation(delta)


## Keeps its feet on the ground whatever animation plays (ANIM_GROUND_OFFSET),
## easing between them as the animations cross-fade; and indoors keeps its
## head under the ceiling (walking upright it is taller than the ground
## floor's 2.85 m, and its head poked up through the floor above).
func _process(delta: float) -> void:
	if not model or not _anim_playback or not visible:
		return
	_headroom_check -= delta
	if _headroom_check <= 0.0:
		_headroom_check = HEADROOM_CHECK_INTERVAL
		_target_size = _fit_under_ceiling()
	_size = lerpf(_size, _target_size, clampf(delta * 4.0, 0.0, 1.0))
	model.scale = _model_base_scale * _size
	if _eye_glow:
		_eye_glow.position.y = _glow_base_y * _size
	var target: float = _model_base_y + ANIM_GROUND_OFFSET.get(_anim_playback.get_current_node(), 0.0) * _size
	model.position.y = lerpf(model.position.y, target, clampf(delta * 8.0, 0.0, 1.0))


## Its size under whatever is above it indoors: full size if its head fits
## (TALLEST plus HEADROOM), smaller if not, never below MIN_SIZE.
func _fit_under_ceiling() -> float:
	if not perception or not perception.entity_inside or not is_inside_tree():
		return 1.0
	var from := global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, global_position + Vector3.UP * (TALLEST + HEADROOM), LAYER_WORLD)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 1.0
	return clampf((hit.position.y - global_position.y - HEADROOM) / TALLEST, MIN_SIZE, 1.0)


func _update_facing(delta: float) -> void:
	var dir: Vector3
	if _look_target != null:
		dir = (_look_target as Vector3) - global_position
	else:
		dir = _desired_velocity
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	var target_yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))


func _update_stuck(delta: float) -> void:
	if _desired_velocity.length_squared() < 0.01:
		_stuck_timer = 0.0
		_stuck_anchor = global_position
		return
	_stuck_timer += delta
	if _stuck_timer < config.stuck_time:
		return
	if _flat_distance(global_position, _stuck_anchor) < config.stuck_progress:
		brain.current.on_stuck()
	_stuck_timer = 0.0
	_stuck_anchor = global_position


## Default stuck recovery: hop to the next path point if nobody is watching,
## otherwise force a fresh path.
func unstick() -> void:
	var next := nav_agent.get_next_path_position()
	if next.distance_to(global_position) > 0.3 and try_teleport(next):
		return
	_last_nav_target = Vector3.INF
	_nav_retarget_timer = 0.0


func _check_catch() -> void:
	if not can_kill or not brain.current.can_catch():
		return
	if global_position.distance_to(_player.global_position) <= config.catch_distance:
		_catch()


func _on_catch_area_body_entered(body: Node) -> void:
	if body == _player and _is_active and can_kill and brain.current.can_catch():
		_catch()


func _catch() -> void:
	_is_active = false
	velocity = Vector3.ZERO
	# At the player's throat while the camera locks on to it.
	_turn_towards(_player.global_position)
	if _anim_playback and not is_traversing() and not is_clinging():
		_anim_playback.start(&"NeckBite")
		if _anim_player:
			_anim_player.speed_scale = 1.0
	audio.play_roar()
	audio.stop_chase_music()
	caught_player.emit()
	if _night_manager:
		_night_manager.horror_event.emit("entity_caught_player")


# ═════════════════════════════════════════════════════════════════════════════
# LINK TRAVERSAL (windows and the door)
# ═════════════════════════════════════════════════════════════════════════════

## Crosses `link` now: outside -> inside if `inward`, otherwise back out.
func traverse_link(link: CabinEntryLink, inward: bool) -> void:
	if is_traversing() or not link.enabled:
		return
	if inward:
		_traverse(link, link.start_position, link.end_position)
	else:
		_traverse(link, link.end_position, link.start_position)


## Backup for link_reached: if the path was requested while already standing
## on a link's end, the agent may skip the signal and head straight for the
## far end (into the wall). Standing at one end of an open link with the far
## end as the next waypoint means: cross it.
const LINK_CROSS_NEAR := 1.2
const LINK_CROSS_NEXT := 0.8

func _check_link_crossing() -> void:
	if nav_agent.is_navigation_finished() or _desired_velocity.length_squared() < 0.01:
		return
	var next := nav_agent.get_next_path_position()
	for link in world.entries():
		if not link.enabled:
			continue
		if reach_distance(global_position, link.start_position) < LINK_CROSS_NEAR 				and reach_distance(next, link.end_position) < LINK_CROSS_NEXT:
			_traverse(link, link.start_position, link.end_position)
			return
		if reach_distance(global_position, link.end_position) < LINK_CROSS_NEAR 				and reach_distance(next, link.start_position) < LINK_CROSS_NEXT:
			_traverse(link, link.end_position, link.start_position)
			return


func _on_link_reached(details: Dictionary) -> void:
	var link := details.get("owner") as CabinEntryLink
	if not link or is_traversing():
		return
	var start: Vector3 = details.get("link_entry_position", link.start_position)
	var end: Vector3 = details.get("link_exit_position", link.end_position)
	_traverse(link, start, end)


## Carries the Entity across an entry link. Collision is off during the move:
## windows are climbed over the sill, the door is walked through after opening.
func _traverse(link: CabinEntryLink, start: Vector3, end: Vector3) -> void:
	if link.climb:
		_traverse_climb(link, start.distance_to(link.start_position) < start.distance_to(link.end_position))
		return
	_traversal_kind = link.kind
	collision_mask = 0
	velocity = Vector3.ZERO
	var dir := end - start
	rotation.y = atan2(dir.x, dir.z)
	_traversal = create_tween()
	if link.kind == CabinEntryLink.Kind.DOOR:
		var door := link.entry
		if door and not door.is_open and not door.is_locked:
			door.interact()
			_traversal.tween_interval(0.5)
		var duration := maxf(start.distance_to(end) / config.approach_speed, 0.5)
		_traversal.tween_property(self, "global_position", start, 0.15)
		_traversal.tween_property(self, "global_position", end, duration)
	else:
		audio.play_vault()
		var apex := (start + end) * 0.5 + Vector3.UP * 1.0
		var half := config.vault_time * 0.5
		_traversal.tween_property(self, "global_position", start, 0.15)
		_traversal.tween_property(self, "global_position", apex, half).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		_traversal.tween_property(self, "global_position", end, half).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	_traversal.finished.connect(_end_traversal)


func _end_traversal() -> void:
	_traversal = null
	_traversal_kind = -1
	_traversal_anim = &""
	if not is_clinging():
		collision_mask = MOVE_MASK
	_last_nav_target = Vector3.INF
	_nav_retarget_timer = 0.0
	_stuck_timer = 0.0
	_stuck_anchor = global_position


func _cancel_traversal() -> void:
	if _traversal:
		_traversal.kill()
		_end_traversal()


# ═════════════════════════════════════════════════════════════════════════════
# CLIMBING (upstairs windows, from Night 4)
# ═════════════════════════════════════════════════════════════════════════════
# It climbs the wall below an upstairs window and clings outside it (on the
# ledge where there is one): peeking, tapping and breaking the glass happen
# from there. It vaults in from the wall, climbs back down when it gives up,
# and drops off when it is driven away. A route through an open upstairs
# window (its link) does the whole climb and vault in one go.

func can_climb() -> bool:
	return is_dev_mode() or current_night() >= config.climb_night


## Holding on to the wall outside an upstairs window (including while ducking).
func is_clinging() -> bool:
	return _perch_link != null


## Clinging outside `link`'s window, not in the middle of a move.
func is_perched_at(link: CabinEntryLink) -> bool:
	return _perch_link == link and not is_traversing()


## Climbs from the ground below `link`'s window to cling outside it.
func climb_to_perch(link: CabinEntryLink) -> void:
	if is_traversing() or is_clinging():
		return
	var perch := world.perch_position(link)
	var base := Vector3(perch.x, link.start_position.y, perch.z)
	_begin_climb(link)
	_face_window(link)
	traces.scratch_climb(link, base, perch)
	_traversal.tween_callback(_set_traversal_anim.bind(&"Stalk"))
	_traversal.tween_property(self, "global_position", base, maxf(global_position.distance_to(base) / config.approach_speed, 0.2))
	_tween_climb(base, perch, &"ClimbUp")
	_traversal.tween_callback(_set_perch.bind(link))


## Lets go of the wall: climbs back down, or (`scared`) drops off.
func leave_perch(scared: bool) -> void:
	if not is_clinging() or is_traversing():
		return
	var link := _perch_link
	var base := Vector3(global_position.x, link.start_position.y, global_position.z)
	_perch_offset = Vector3.ZERO
	_begin_climb(link)
	if scared:
		# Falling To Landing: the fall, then landing in a crouch and rising.
		_traversal.tween_callback(_set_traversal_anim.bind(&"DropLand"))
		_traversal.tween_property(self, "global_position", base, config.drop_time) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		_traversal.tween_callback(audio.play_drop_thud)
		# Off the wall once it hits the ground; then it gets up.
		_traversal.tween_callback(_set_perch.bind(null))
		_traversal.tween_interval(DROP_LAND_TIME)
	else:
		_tween_climb(global_position, base, &"ClimbDown")
	_traversal.tween_callback(_set_perch.bind(null))


## From the wall, in through the (open) window.
func enter_from_perch(link: CabinEntryLink) -> void:
	if not is_perched_at(link) or not link.enabled:
		return
	_begin_climb(link)
	_traversal.tween_callback(_set_perch.bind(null))
	_tween_vault(global_position, link.end_position)


## Ducks below the sill (`down`) or comes back up while clinging.
func set_perch_duck(down: bool) -> void:
	_perch_offset = Vector3.DOWN * config.perch_duck_drop if down else Vector3.ZERO


## A route through an open upstairs window: the whole climb in one move.
func _traverse_climb(link: CabinEntryLink, inward: bool) -> void:
	var perch := world.perch_position(link)
	var base := Vector3(perch.x, link.start_position.y, perch.z)
	_begin_climb(link)
	_face_window(link)
	if inward:
		traces.scratch_climb(link, base, perch)
		_traversal.tween_property(self, "global_position", base, maxf(global_position.distance_to(base) / config.approach_speed, 0.2))
		_tween_climb(base, perch, &"ClimbUp")
		_tween_vault(perch, link.end_position)
	else:
		_tween_vault(global_position, perch)
		_traversal.tween_callback(_face_window.bind(link))
		_tween_climb(perch, base, &"ClimbDown")
		_traversal.tween_property(self, "global_position", link.start_position, 0.3)


func _begin_climb(link: CabinEntryLink) -> void:
	_traversal_kind = link.kind
	collision_mask = 0
	velocity = Vector3.ZERO
	_climb_tap_left = 0.0
	_traversal = create_tween()
	_traversal.finished.connect(_end_traversal)


func _tween_climb(from: Vector3, to: Vector3, anim: StringName) -> void:
	_traversal.tween_callback(_set_traversal_anim.bind(anim))
	_traversal.tween_property(self, "global_position", to, maxf(from.distance_to(to) / config.climb_speed, 0.3))


func _tween_vault(from: Vector3, to: Vector3) -> void:
	var apex := (from + to) * 0.5 + Vector3.UP * 0.6
	var half := config.vault_time * 0.5
	_traversal.tween_callback(_set_traversal_anim.bind(&"EnterWindow"))
	_traversal.tween_callback(audio.play_vault)
	_traversal.tween_property(self, "global_position", apex, half).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_traversal.tween_property(self, "global_position", to, half).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)


func _set_traversal_anim(anim: StringName) -> void:
	_traversal_anim = anim


func _set_perch(link: CabinEntryLink) -> void:
	_perch_link = link


## Claws on the logs while it climbs.
func _update_climb_sounds(delta: float) -> void:
	if _traversal_anim != &"ClimbUp" and _traversal_anim != &"ClimbDown":
		return
	_climb_tap_left -= delta
	if _climb_tap_left <= 0.0:
		_climb_tap_left = CLIMB_TAP_INTERVAL
		audio.play_climb_scrape(global_position + Vector3.UP * 1.2)


func _face_window(link: CabinEntryLink) -> void:
	var inward := link.end_position - link.start_position
	rotation.y = atan2(inward.x, inward.z)


## Drops any hold on the wall at once (teleport, deactivation).
func _release_perch() -> void:
	_perch_link = null
	_perch_offset = Vector3.ZERO
	if not is_traversing():
		collision_mask = MOVE_MASK


# ═════════════════════════════════════════════════════════════════════════════
# ANIMATION & VISIBILITY
# ═════════════════════════════════════════════════════════════════════════════

## Reference walking speed the "Stalk" animation was authored for.
const ANIM_WALK_SPEED := 2.5
## The top of its head at full size, walking upright (m).
const TALLEST := 2.9
## Space kept between its head and a ceiling (m).
const HEADROOM := 0.2
const MIN_SIZE := 0.7
const HEADROOM_CHECK_INTERVAL := 0.15
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
}
const ANIM_RUN_SPEED := 6.0
## How fast LowCrawl moves it played at normal speed (m/s).
const ANIM_CRAWL_SPEED := 1.3
## The roar (the part of Mutant Roaring that matters, sped up) before a
## charge and when a blackout breaks its stun.
const ROAR_TIME := 1.1
const ROAR_SPEED := 1.6
## Zombie Dying's length (s), then it is gone.
const DYING_TIME := 3.6
## Getting up after dropping off a wall (the rest of Falling To Landing).
const DROP_LAND_TIME := 0.55

func _update_animation(_delta: float) -> void:
	if not _anim_playback:
		return
	var horizontal_speed := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	var anim: StringName
	var speed_scale := 1.0
	if is_traversing():
		if _traversal_anim != &"":
			anim = _traversal_anim
		else:
			anim = &"EnterWindow" if _traversal_kind == CabinEntryLink.Kind.WINDOW else &"Stalk"
	elif is_clinging() and _anim_override == &"":
		# Holding still on the wall: the climb cycle, barely moving.
		anim = &"ClimbUp"
		speed_scale = 0.15
	elif _anim_override != &"":
		anim = _anim_override
		speed_scale = _anim_override_speed
	elif _gait == &"crawl":
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
	if _anim_playback.get_current_node() != anim:
		_anim_playback.travel(anim)
	if _anim_player:
		_anim_player.speed_scale = speed_scale


func _set_hidden(hidden: bool) -> void:
	visible = not hidden
	if collision_shape:
		collision_shape.disabled = hidden
	if _catch_area:
		_catch_area.monitoring = not hidden


# ═════════════════════════════════════════════════════════════════════════════
# NIGHT EVENTS
# ═════════════════════════════════════════════════════════════════════════════

func _on_night_started(night: int) -> void:
	# Nights 1 and 2 belong to the story: the Entity only appears for the
	# Night 2 van chase (start_van_chase).
	if night <= 2 and not is_dev_mode():
		deactivate()
		return
	# Last night's traces were there to be found during the day.
	traces.clear_all()
	if get_meta("debug_disabled", false):
		return
	activate()
	var spot := world.pick_vantage_point(true)
	if spot:
		_teleport(spot.global_position)
	brain.force(State.OBSERVE)


func _on_first_chase_started() -> void:
	var marker := world._level_root().find_child("EntityVanSpawn", true, false) as Node3D
	var spawn := marker.global_position if marker else _player.global_position - _player.global_transform.basis.z * 15.0
	start_van_chase(spawn)


## Van chase over (the player reached the cabin): gone until next night.
func end_van_chase() -> void:
	van_chase_active = false
	if _night_manager:
		_night_manager.is_van_sequence_active = false
	deactivate()
