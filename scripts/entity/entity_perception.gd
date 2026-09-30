class_name EntityPerception
extends Node

## What the Entity knows. update() runs once per physics frame (from the
## brain) and refreshes a snapshot every state reads, so sight is never
## throttled differently depending on who asks.
##
## Sight and hearing feed MEMORY (last seen / last heard). States pursue
## memory, not the player's live position, so the player can lose it.
## The one exception is `player_inside` / `player_room`: which building the
## player is in is treated as common knowledge (it hears the door, sees the
## lights), but not where they are inside it.

var entity: Entity
var config: EntityConfig

# ─── Snapshot (refreshed every update) ───────────────────────────────────────
var can_see_player := false
var player_room := "Outside"
var player_inside := false
var player_outside: bool:
	get:
		return not player_inside
var entity_room := "Outside"
var entity_inside := false
var entity_in_lit_room := false
var distance_to_player := INF
## The Entity is on screen for the player (in the camera frustum, unoccluded).
var in_player_view := false
## The player is looking more or less straight at the Entity.
var player_watching := false
## Seconds the player has been outside without being seen or heard.
var unseen_outside_time := 0.0

# ─── Memory ──────────────────────────────────────────────────────────────────
var last_seen_position := Vector3.ZERO
var last_heard_position := Vector3.ZERO
var last_heard_room := ""
var _last_seen_clock := -INF
var _last_heard_clock := -INF

# ─── Flashlight ──────────────────────────────────────────────────────────────
## A flashlight beam (standard or overcharged) is on the Entity right now.
var illuminated := false
## The overcharged beam is on the Entity right now.
var overcharged := false
## Seconds the beam has been continuously on it.
var stare_time := 0.0
## How strongly the beam hits it right now (0-1: closer and more centred is
## stronger). 0 when no beam is on it.
var beam_strength := 0.0
## Builds while a standard beam is on it, drains slowly otherwise; at 1 the
## standoff winds up to a charge (see EntityConfig.charge_stare_time).
var stare_pressure := 0.0
var _beam_strength := 0.0
## Seconds of overcharged beam, tolerant of drop-outs shorter than
## config.overcharge_grace.
var overcharge_time := 0.0
var _beam_hit := false
var _beam_overcharged := false
var _overcharge_lost_time := 0.0

## Time the Entity has been active; memory ages against this, so pausing the
## game doesn't age it.
var _clock := 0.0
var _camera: Camera3D = null

const WATCHING_STATES := [Entity.State.OBSERVE, Entity.State.PEEK, Entity.State.APPROACH]
const PLAYER_CHEST := Vector3(0.0, 1.0, 0.0)
const ROOM_SAMPLE_HEIGHT := 1.0   ## Room volumes start ~0.25 m above the floor.
const PLAYER_VIEW_DISTANCE := 60.0
const WATCH_CONE_DEGREES := 20.0


func setup(owner_entity: Entity) -> void:
	entity = owner_entity
	config = owner_entity.config


func update(delta: float) -> void:
	_clock += delta
	var player := entity.get_player()
	if not player:
		return

	_update_rooms(player)
	distance_to_player = entity.global_position.distance_to(player.global_position)
	_update_flashlight(delta)
	_update_sight(player)

	var chest := entity.global_position + Vector3.UP * config.eye_height * 0.6
	in_player_view = is_in_player_view(chest)
	player_watching = in_player_view and is_player_looking_at(chest, WATCH_CONE_DEGREES)

	if player_inside or can_see_player or has_fresh_noise(2.0):
		unseen_outside_time = 0.0
	else:
		unseen_outside_time += delta

	if illuminated:
		entity.confidence.modify(-config.stare_drain * delta)


func reset_memory() -> void:
	_last_seen_clock = -INF
	_last_heard_clock = -INF
	unseen_outside_time = 0.0


# ─── Memory queries ──────────────────────────────────────────────────────────

func time_since_seen() -> float:
	return _clock - _last_seen_clock


func time_since_heard() -> float:
	return _clock - _last_heard_clock


func has_fresh_sighting(max_age: float = -1.0) -> bool:
	return time_since_seen() < (config.memory_time if max_age < 0.0 else max_age)


func has_fresh_noise(max_age: float = -1.0) -> bool:
	return time_since_heard() < (config.memory_time if max_age < 0.0 else max_age)


# ─── Hearing ─────────────────────────────────────────────────────────────────

## A noise of `radius` meters at `noise_position`. Walls halve the radius.
func hear_noise(noise_position: Vector3, radius: float) -> void:
	var eye := entity.global_position + Vector3.UP * config.eye_height
	if _is_blocked(eye, noise_position + Vector3.UP * 0.5):
		radius *= config.hearing_wall_multiplier
	if entity.global_position.distance_to(noise_position) > radius:
		return
	last_heard_position = noise_position
	last_heard_room = RoomLightDetector.get_room_name_at(noise_position + Vector3.UP * ROOM_SAMPLE_HEIGHT)
	_last_heard_clock = _clock


# ─── Flashlight ──────────────────────────────────────────────────────────────

## Called by the player every frame with the result of its own (occluded)
## beam check. This is the only source of flashlight information.
## `strength` (0-1) is how strongly the beam hits: closer and more centred is
## stronger.
func on_flashlight(is_hit: bool, is_overcharged: bool, strength: float = 1.0) -> void:
	_beam_hit = is_hit
	_beam_overcharged = is_hit and is_overcharged
	_beam_strength = clampf(strength, 0.0, 1.0) if is_hit else 0.0


func _update_flashlight(delta: float) -> void:
	illuminated = _beam_hit
	overcharged = _beam_overcharged
	beam_strength = _beam_strength
	stare_time = stare_time + delta if _beam_hit else 0.0
	if _beam_hit and not _beam_overcharged:
		stare_pressure += delta * lerpf(0.4, 1.0, beam_strength) / config.charge_stare_time
	elif not _beam_hit:
		stare_pressure -= delta * config.stare_pressure_decay
	stare_pressure = clampf(stare_pressure, 0.0, 1.0)
	if _beam_overcharged:
		overcharge_time += delta
		_overcharge_lost_time = 0.0
	else:
		_overcharge_lost_time += delta
		if _overcharge_lost_time > config.overcharge_grace:
			overcharge_time = 0.0


# ─── Sight ───────────────────────────────────────────────────────────────────

func vision_range() -> float:
	var player := entity.get_player()
	if player.has_method("is_flashlight_on") and player.is_flashlight_on():
		return config.vision_range_flashlight
	if entity.get_state() in WATCHING_STATES:
		return config.vision_range_watching
	if RoomLightDetector.is_position_in_lit_room(player.global_position + Vector3.UP * ROOM_SAMPLE_HEIGHT):
		return config.vision_range_lit
	var dark_range := config.vision_range_dark
	if player.has_method("is_crouching") and player.is_crouching():
		dark_range *= config.crouch_vision_multiplier
	return dark_range


func _update_sight(player: Node3D) -> void:
	can_see_player = false
	if distance_to_player > vision_range():
		return
	var eye := entity.global_position + Vector3.UP * config.eye_height
	var target := player.global_position + PLAYER_CHEST
	var to_player := target - entity.global_position
	to_player.y = 0.0
	var forward := entity.global_transform.basis.z
	forward.y = 0.0
	if forward.normalized().dot(to_player.normalized()) < cos(deg_to_rad(config.vision_half_angle)):
		return
	if _is_blocked(eye, target):
		return
	can_see_player = true
	last_seen_position = player.global_position
	_last_seen_clock = _clock


# ─── The player's point of view ──────────────────────────────────────────────

## True if `world_position` is on the player's screen and not hidden behind
## world geometry.
func is_in_player_view(world_position: Vector3) -> bool:
	var cam := _get_camera()
	if not cam:
		return false
	if cam.global_position.distance_to(world_position) > PLAYER_VIEW_DISTANCE:
		return false
	if not cam.is_position_in_frustum(world_position):
		return false
	return not _is_blocked(cam.global_position, world_position)


## True if the player's camera points within `degrees` of `world_position`.
func is_player_looking_at(world_position: Vector3, degrees: float) -> bool:
	var cam := _get_camera()
	if not cam:
		return false
	var to_target := (world_position - cam.global_position).normalized()
	return (-cam.global_transform.basis.z).dot(to_target) >= cos(deg_to_rad(degrees))


func _get_camera() -> Camera3D:
	if is_instance_valid(_camera) and _camera.is_inside_tree():
		return _camera
	var player := entity.get_player()
	if player:
		_camera = player.get_node_or_null("CameraHolder/Camera3D") as Camera3D
	if not _camera:
		_camera = entity.get_viewport().get_camera_3d()
	return _camera


# ─── Rooms ───────────────────────────────────────────────────────────────────

## Inside/outside comes from the cabin footprint (EntityWorld), which has no
## gaps; the room trigger volumes leave gaps in doorways. Room names are only
## used for display and for lit-room checks.
func _update_rooms(player: Node3D) -> void:
	if player.has_method("get_player_room"):
		player_room = player.get_player_room()
	else:
		player_room = RoomLightDetector.get_room_name_at(player.global_position + Vector3.UP * ROOM_SAMPLE_HEIGHT)
	player_inside = entity.world.is_inside_cabin(player.global_position)
	var sample := entity.global_position + Vector3.UP * ROOM_SAMPLE_HEIGHT
	entity_room = RoomLightDetector.get_room_name_at(sample)
	entity_inside = entity.world.is_inside_cabin(entity.global_position)
	entity_in_lit_room = entity_inside and RoomLightDetector.is_position_in_lit_room(sample)


## True if world geometry (layer 1) blocks the straight line from `from` to
## `to`. The player's body is on layer 1 too, so it is excluded.
func _is_blocked(from: Vector3, to: Vector3) -> bool:
	var exclude: Array[RID] = [entity.get_rid()]
	var player := entity.get_player()
	if player is CollisionObject3D:
		exclude.append((player as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, Entity.LAYER_WORLD, exclude)
	return not entity.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
