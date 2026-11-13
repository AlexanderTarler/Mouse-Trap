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
##   EntityTraversal   - its scripted moves: through windows and the door,
##                       up and down the wall, clinging outside a window.
##   EntityAnimator    - which animation plays, its feet on the ground, its
##                       head under the ceiling, cutscene poses.
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
## TEMPORARY (F4, EntityDebugOverlay.debug_landing_breach): it may climb and
## break in tonight whatever the night, through a lit or repelled window,
## until this break-in is over.
var debug_breach := false
## Set by the overload stun and kept until the player is back in the cabin
## (no totem teleport meanwhile); read by totem_anchor.gd.
var totem_defense_disabled: bool = false
## True during the Night 2 van chase (a scripted, fully aware pursuit).
var van_chase_active: bool = false
# ─── Tonight (reset when a night starts: _reset_tonight) ────────────────────
## Driven off by the overcharged beam tonight (it hardens each time).
var times_driven_off := 0
## Its once-a-night tricks, done: the fake departure, a prop knocked over.
var faked_departure_tonight := false
var prop_knocked_tonight := false
## Sounds of the player's it has copied tonight, and how many were the
## player's own voice (EntityAudio).
var mimics_tonight := 0
var voices_tonight := 0
var is_enraged: bool = false

var config: EntityConfig = CONFIG
var brain: EntityBrain
var perception: EntityPerception
var world: EntityWorld
var confidence: EntityConfidence
var audio: EntityAudio
var traces: EntityTraces
var traversal: EntityTraversal
var animator: EntityAnimator

var _player: Node3D = null
var _night_manager: Node = null
var _is_active: bool = false

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var model: Node3D = get_node_or_null("MonsterModel")
var _catch_area: Area3D = null

# ─── Movement state (reset every physics frame by the active state) ─────────
var _desired_velocity := Vector3.ZERO
## Face this instead of the movement direction (INF: none).
var _look_target := Vector3.INF
## The good ending: dying (die()).
var _dying := false
var _last_nav_target := Vector3.INF
var _nav_retarget_timer := 0.0
const NAV_RETARGET_INTERVAL := 0.3
const NAV_RETARGET_DISTANCE := 0.5
const TURN_SPEED := 8.0

# ─── Stuck detection ─────────────────────────────────────────────────────────
var _stuck_timer := 0.0
var _stuck_anchor := Vector3.ZERO

## The roar (the part of Mutant Roaring that matters, sped up) before a
## charge and when a blackout breaks its stun.
const ROAR_TIME := 1.1
const ROAR_SPEED := 1.6
## Zombie Dying's length (s), then it is gone.
const DYING_TIME := 3.6


func _ready() -> void:
	add_to_group("entity")
	collision_layer = LAYER_ENTITY
	collision_mask = MOVE_MASK
	nav_agent.avoidance_enabled = false
	nav_agent.path_desired_distance = PATH_DESIRED_DISTANCE
	nav_agent.target_desired_distance = 0.4

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
	traversal = _add_module(EntityTraversal.new(), "Traversal")
	animator = _add_module(EntityAnimator.new(), "Animator")
	nav_agent.link_reached.connect(traversal.on_link_reached)
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
	# Moving again after a frozen cinematic pose.
	animator.resume()


func deactivate() -> void:
	_is_active = false
	van_chase_active = false
	animator.cancel_oneshot()
	traversal.abort()
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
		traversal.abort()
		audio.stop_all()
	velocity = Vector3.ZERO
	visible = true
	if collision_shape:
		collision_shape.disabled = true
	if _catch_area:
		_catch_area.monitoring = false
	# Keep its own scale; `xform` only places and turns it.
	global_transform = Transform3D(xform.basis.orthonormalized() * Basis.from_scale(scale), xform.origin)
	# Speed 0: the pose holds (EntityAnimator.cinematic).
	animator.cinematic(anim, anim_speed)


## How long the overcharged beam must be held on it to drive it off now.
func repel_time() -> float:
	return config.overcharge_repel_time + times_driven_off * config.overcharge_repel_growth


## Driven off by the overcharged beam: it hardens (repel_time), and the
## journal learns of it.
func note_driven_off() -> void:
	times_driven_off += 1
	EntityJournal.learn(self, "beam" if times_driven_off <= 1 else "beam_harder")


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
	brain.force(State.STUNNED, {EntityState.DURATION: duration})


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
	brain.force(State.CHARGE, {EntityState.COMMITTED: true, EntityState.NO_ROAR: true})


## Debug console: jump to a treeline vantage point (even if in view) and watch.
func debug_relocate() -> void:
	if not _is_active:
		activate()
	var spot := world.pick_vantage_point(true)
	if spot:
		teleport(world.snap_to_navmesh(spot.global_position))
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


# What it does from which night: EntityConfig's "Nights" group. (It is only
# out there on its own from config.active_night; the earlier gates matter
# when the debug console or a test puts it in the world before that.)

## It may come to the windows and the door.
func can_approach_cabin() -> bool:
	return is_dev_mode() or current_night() >= config.approach_night


## It can break planks (before that, only glass).
func can_break_planks() -> bool:
	return is_dev_mode() or debug_breach or current_night() >= config.break_planks_night


## It plays its tricks (see EntityConfig.tricks_night for the list).
func can_use_tricks() -> bool:
	return is_dev_mode() or debug_breach or current_night() >= config.tricks_night


## It climbs the walls to the upstairs windows.
func can_climb() -> bool:
	return is_dev_mode() or debug_breach or current_night() >= config.climb_night


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


func stop() -> void:
	_desired_velocity = Vector3.ZERO


func face(target: Vector3) -> void:
	_look_target = target


## This frame's animation, whatever it is doing (states call it every frame).
func play_anim(anim: StringName, speed: float = 1.0) -> void:
	animator.override_anim = anim
	animator.override_speed = speed


## Moves low this frame (LowCrawl when it moves, Crouch when it doesn't).
func crawl() -> void:
	animator.gait = &"crawl"


## Stops where it is, faces the player and plays `anim` for `seconds`,
## whatever its state wants meanwhile (the state goes on underneath).
func play_oneshot(anim: StringName, seconds: float, speed: float = 1.0) -> void:
	animator.play_oneshot(anim, seconds, speed)


func is_playing_oneshot() -> bool:
	return animator.is_playing_oneshot()


func cancel_oneshot() -> void:
	animator.cancel_oneshot()


## The totem burned (the good ending): it dies where it stands, then is gone.
func die() -> void:
	if _dying:
		return
	_dying = true
	var seen: bool = visible and not is_traversing() and not is_clinging() and animator.has_tree()
	_is_active = false
	traversal.abort()
	velocity = Vector3.ZERO
	audio.stop_all()
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if _catch_area:
		_catch_area.set_deferred("monitoring", false)
	if seen:
		if _player:
			_turn_towards(_player.global_position)
		animator.start(&"Dying")
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
	animator.set_eye_glow(multiplier)


## Teleports only if neither the current position nor `target` is in the
## player's view, and it isn't in the middle of a move (climbing down a wall,
## vaulting a window) or holding on to a wall. Returns whether it happened.
func try_teleport(target: Vector3) -> bool:
	if is_traversing() or is_clinging():
		return false
	if perception.is_in_player_view(global_position) or perception.is_in_player_view(target):
		return false
	teleport(target)
	return true


## Puts it at `target` at once, seen or not (scripted moments, the debug
## console, tests). Behaviour uses try_teleport(), which refuses in view.
func teleport(target: Vector3) -> void:
	traversal.abort()
	global_position = target
	velocity = Vector3.ZERO
	nav_agent.target_position = target
	_last_nav_target = target
	_stuck_timer = 0.0
	_stuck_anchor = target


# ─── Its scripted moves (EntityTraversal) ───────────────────────────────────

## In the middle of a move: through a window or the door, on the wall.
func is_traversing() -> bool:
	return traversal.is_active()


## Holding on to the wall outside an upstairs window (including while ducking).
func is_clinging() -> bool:
	return traversal.is_clinging()


## Clinging outside `link`'s window, not in the middle of a move.
func is_perched_at(link: CabinEntryLink) -> bool:
	return traversal.is_perched_at(link)


## Crosses `link` now: outside -> inside if `inward`, otherwise back out.
func traverse_link(link: CabinEntryLink, inward: bool) -> void:
	traversal.traverse_link(link, inward)


## Climbs from the ground below `link`'s window to cling outside it.
func climb_to_perch(link: CabinEntryLink) -> void:
	traversal.climb_to_perch(link)


## Lets go of the wall: climbs back down, or (`scared`) drops off.
func leave_perch(scared: bool) -> void:
	traversal.leave_perch(scared)


## From the wall, in through the (open) window.
func enter_from_perch(link: CabinEntryLink) -> void:
	traversal.enter_from_perch(link)


## Ducks below the sill (`down`) or comes back up while clinging.
func set_perch_duck(down: bool) -> void:
	traversal.set_perch_duck(down)


## The next move_to() asks for a fresh path, and the stuck check starts over
## (after a move that put it somewhere else).
func reset_navigation() -> void:
	_last_nav_target = Vector3.INF
	_nav_retarget_timer = 0.0
	_stuck_timer = 0.0
	_stuck_anchor = global_position


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
	_look_target = Vector3.INF
	animator.begin_frame()

	# The totem defence, off since the lamp's stun, comes back once the
	# player is inside the cabin again.
	if totem_defense_disabled and perception.player_inside and brain.state_id != State.STUNNED:
		totem_defense_disabled = false

	if not is_traversing():
		brain.tick(delta)
		if not is_clinging():
			traversal.check_link_crossing(_desired_velocity.length_squared() >= 0.01)
	else:
		# Busy with a move (climbing, through a window): no state decides
		# anything, but it still sees, hears and feels the beam.
		brain.sense(delta)
		traversal.check_driven_off()
	# A one-shot (the roar): it stands and faces the player meanwhile.
	if animator.update_oneshot(delta, not is_traversing() and not is_clinging()):
		_desired_velocity = Vector3.ZERO
		_look_target = _player.global_position

	if is_traversing():
		traversal.update_moving(delta)
		audio.update_hunt_music(delta)
		animator.update(delta)
		return
	if is_clinging():
		traversal.update_clinging(delta)
		animator.update(delta)
		return

	velocity.x = _desired_velocity.x
	velocity.z = _desired_velocity.z
	if is_on_floor():
		velocity.y = 0.0
		# On a slope (the stair ramp) move along the floor: pushing
		# horizontally into it stalls the capsule partway up.
		# (A floor normal can be zero the frame after a teleport.)
		var floor_normal := get_floor_normal()
		if floor_normal.length_squared() > 0.01 and floor_normal.y < 0.99:
			velocity = velocity.slide(floor_normal.normalized()).normalized() * velocity.length()
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
	audio.update_hunt_music(delta)
	animator.update(delta)


func _update_facing(delta: float) -> void:
	var dir: Vector3
	if _look_target != Vector3.INF:
		dir = _look_target - global_position
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
	if not is_traversing() and not is_clinging():
		animator.start(&"NeckBite")
	audio.play_roar()
	audio.stop_chase_music()
	caught_player.emit()
	if _night_manager:
		_night_manager.horror_event.emit("entity_caught_player")


# ═════════════════════════════════════════════════════════════════════════════
# VISIBILITY
# ═════════════════════════════════════════════════════════════════════════════

func _set_hidden(hidden: bool) -> void:
	visible = not hidden
	if collision_shape:
		collision_shape.disabled = hidden
	if _catch_area:
		_catch_area.monitoring = not hidden


# ═════════════════════════════════════════════════════════════════════════════
# NIGHT EVENTS
# ═════════════════════════════════════════════════════════════════════════════

func _reset_tonight() -> void:
	times_driven_off = 0
	faked_departure_tonight = false
	prop_knocked_tonight = false
	mimics_tonight = 0
	voices_tonight = 0


func _on_night_started(night: int) -> void:
	_reset_tonight()
	audio.night_started()
	# The first nights belong to the story: the Entity only appears for the
	# Night 2 van chase (start_van_chase).
	if night < config.active_night and not is_dev_mode():
		deactivate()
		return
	# Last night's traces were there to be found during the day.
	traces.clear_all()
	if get_meta("debug_disabled", false):
		return
	activate()
	var spot := world.pick_vantage_point(true)
	if spot:
		teleport(spot.global_position)
	brain.force(State.OBSERVE)


func _on_first_chase_started() -> void:
	var marker := world.level_root().find_child("EntityVanSpawn", true, false) as Node3D
	var spawn := marker.global_position if marker else _player.global_position - _player.global_transform.basis.z * 15.0
	start_van_chase(spawn)


## Van chase over (the player reached the cabin): gone until next night.
func end_van_chase() -> void:
	van_chase_active = false
	if _night_manager:
		_night_manager.is_van_sequence_active = false
	deactivate()
