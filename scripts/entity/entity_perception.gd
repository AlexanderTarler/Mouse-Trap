class_name EntityPerception
extends Node

## What the Entity knows. update() runs once per physics frame (from the
## brain) and refreshes a snapshot every state reads, so sight is never
## throttled differently depending on who asks.
##
## Sight and hearing feed MEMORY (last seen / last heard). States pursue
## memory, not the player's live position, so the player can lose it.
## The one exception is `player_inside`: whether the player is in the cabin is
## treated as common knowledge (it hears the door, sees the lights). Which
## room they are in is not: see suspected_player_room().

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
## The last noise it was told about, heard or not (for the debug overlay):
## kind, distance, range (after muffling), via ("direct" or the opening it
## came through), walls, obstacles, heard, clock.
var last_noise: Dictionary = {}
var _last_seen_clock := -INF
## The room it last knew the player to be in, and when (believed_player_room).
var _known_room := ""
var _known_room_clock := -INF
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

const WATCHING_STATES := [Entity.State.OBSERVE, Entity.State.PEEK, Entity.State.APPROACH, Entity.State.LURE]
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

	var room := suspected_player_room()
	if room != "":
		_known_room = room
		_known_room_clock = _clock

	if player_inside or can_see_player or has_fresh_noise(2.0):
		unseen_outside_time = 0.0
	else:
		unseen_outside_time += delta

	if illuminated:
		entity.confidence.modify(-config.stare_drain * delta)


func reset_memory() -> void:
	_last_seen_clock = -INF
	_last_heard_clock = -INF
	_known_room = ""
	_known_room_clock = -INF
	unseen_outside_time = 0.0


## The room it believes the player is in: what it sees or hears now, else
## what it last knew (for config.room_memory_time). "" if it has no idea.
func believed_player_room() -> String:
	var now := suspected_player_room()
	if now != "":
		return now
	if _clock - _known_room_clock < config.room_memory_time:
		return _known_room
	return ""


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

const FOOTSTEPS: Array[StringName] = [&"walk", &"sprint", &"crouch"]
## Noises are heard from about knee-to-hip height, not from the floor.
const NOISE_HEIGHT := 0.8
## How far past an opening the leak path starts/ends (so the opening's own
## frame doesn't count as a wall).
const OPENING_CLEARANCE := 0.5

## A noise of `kind` (see NoiseEvent.emit) at `noise_position`. Its range comes
## from config.noise_radius (footsteps carry farther on the cabin's wooden
## floors). Cabin walls cut it hard, trees and props barely; an open door or
## a broken, unboarded window lets it out. Near the edge of hearing its
## position is only roughly known. A noise heard from inside the cabin draws
## the Entity in (confidence) and tells it which room the player is in.
## Noises the player makes (for the journal: "It hears me").
const PLAYER_NOISES: Array[StringName] = [&"walk", &"sprint", &"land", &"door", &"drop", &"click", &"hammer"]


func hear_noise(noise_position: Vector3, kind: StringName) -> void:
	var radius: float = config.noise_radius.get(String(kind), 10.0)
	var noise_room := RoomLightDetector.get_room_name_at(noise_position + Vector3.UP * ROOM_SAMPLE_HEIGHT)
	var noise_inside := noise_room != "Outside"
	if noise_inside and kind in FOOTSTEPS:
		radius *= config.indoor_footstep_multiplier

	var ear := entity.global_position + Vector3.UP * config.eye_height
	var source := noise_position + Vector3.UP * NOISE_HEIGHT
	# Farther off than it carries in the open: no wall or opening brings it
	# closer (every factor is at most 1, every way round is longer), so the
	# rays aren't cast at all.
	var straight := source.distance_to(ear)
	if straight > radius:
		last_noise = {"kind": kind, "distance": straight, "range": radius, "via": "too far",
			"walls": 0, "obstacles": 0, "heard": false, "clock": _clock}
		return
	var path := _muffling(source, ear)
	path["distance"] = source.distance_to(ear)
	path["via"] = "direct"
	if path.walls > 0:
		for opening in _sound_openings():
			var leak := _leak_through(source, ear, opening)
			if not leak.is_empty() and leak.factor / leak.distance > path.factor / path.distance:
				path = leak

	var effective: float = radius * path.factor
	var heard: bool = path.distance <= effective
	last_noise = {"kind": kind, "distance": path.distance, "range": effective, "via": path.via,
		"walls": path.walls, "obstacles": path.obstacles, "heard": heard, "clock": _clock}
	if not heard:
		return

	# Near the edge of hearing it only knows roughly where the noise was.
	var clarity: float = 1.0 - path.distance / effective
	var error := config.hearing_max_error * clampf((0.5 - clarity) / 0.5, 0.0, 1.0)
	var offset := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * error
	last_heard_position = noise_position + Vector3(offset.x, 0.0, offset.y)
	last_noise["error"] = offset.length()
	last_heard_room = noise_room
	_last_heard_clock = _clock
	# Heard the player, and the player saw it turn to the sound.
	if kind in PLAYER_NOISES and in_player_view and entity.is_active():
		EntityJournal.learn(entity, "sound")
	if noise_inside and not entity_inside:
		entity.confidence.modify(config.noise_confidence_boost * lerpf(0.5, 1.0, clarity))


## The room it believes the player is in: where it can see them indoors, or
## the room of a noise it heard recently. "" when it has no idea.
func suspected_player_room() -> String:
	if can_see_player and player_inside:
		return player_room
	if has_fresh_noise() and last_heard_room != "Outside":
		return last_heard_room
	return ""


## How much of a noise's range survives the straight line from `from` to
## `to`: {factor, walls, obstacles}. Cabin structure (walls, closed doors,
## intact or boarded windows) costs config.hearing_wall_multiplier per wall;
## trees, rocks and props cost a little each, down to a floor.
func _muffling(from: Vector3, to: Vector3) -> Dictionary:
	var space := entity.get_world_3d().direct_space_state
	var exclude: Array[RID] = [entity.get_rid()]
	var player := entity.get_player()
	if player is CollisionObject3D:
		exclude.append((player as CollisionObject3D).get_rid())
	var dir := (to - from).normalized()
	var start := from
	var wall_faces := 0
	var obstacles := 0
	for i in 16:
		var query := PhysicsRayQueryParameters3D.create(start, to, Entity.LAYER_WORLD, exclude)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		if _window_of(hit.collider):
			# Windows are handled by their openings below.
			exclude.append(hit.rid)
		elif _is_cabin_structure(hit.collider):
			# A log wall is entered and left: two faces per wall.
			wall_faces += 1
			start = hit.position + dir * 0.02
		else:
			obstacles += 1
			exclude.append(hit.rid)
	# A shut window (intact glass or boarded) is a wall; an open one isn't.
	# Their glass isn't on the world layer, so this is done geometrically.
	var walls := ceili(wall_faces / 2.0) + _closed_windows_crossed(from, to)
	var factor := pow(config.hearing_wall_multiplier, walls) \
		* maxf(pow(config.hearing_obstacle_multiplier, obstacles), config.hearing_obstacle_floor)
	return {"factor": factor, "walls": walls, "obstacles": obstacles}


func _is_cabin_structure(collider: Object) -> bool:
	return collider is Node and ((collider as Node).is_in_group("cabin_walls") or (collider as Node).is_in_group("Door"))


## The CabinWindow a collider belongs to, or null.
func _window_of(collider: Object) -> CabinWindow:
	var node := collider as Node
	while node:
		if node is CabinWindow:
			return node
		node = node.get_parent()
	return null


## Half the size of a window opening (m): width, height.
const WINDOW_HALF_SIZE := Vector2(0.65, 0.85)

## How many shut windows (intact or boarded) the segment passes through.
func _closed_windows_crossed(from: Vector3, to: Vector3) -> int:
	var count := 0
	var segment := to - from
	for window in get_tree().get_nodes_in_group("WindowMarkers"):
		if not window is CabinWindow or (window.is_glass_shattered and not window.is_boarded):
			continue
		var center: Vector3 = window.global_position
		var normal: Vector3 = window.global_transform.basis.z
		var denominator := segment.dot(normal)
		if absf(denominator) < 0.0001:
			continue
		var t := (center - from).dot(normal) / denominator
		if t <= 0.0 or t >= 1.0:
			continue
		var offset := from + segment * t - center
		if absf(offset.dot(window.global_transform.basis.x)) <= WINDOW_HALF_SIZE.x \
				and absf(offset.y) <= WINDOW_HALF_SIZE.y:
			count += 1
	return count


## Where sound can get out of (or into) the cabin: open doors, and broken
## windows that aren't boarded up. Upstairs windows count too.
func _sound_openings() -> Array[Dictionary]:
	var openings: Array[Dictionary] = []
	for door in get_tree().get_nodes_in_group("Door"):
		if door is Node3D and door.get("is_open") == true:
			var outside := door.get_node_or_null("EntityDoorWaypoint") as Node3D
			var inside := door.get_node_or_null("IndoorBreachWaypoint") as Node3D
			var center: Vector3 = (outside.global_position + inside.global_position) * 0.5 if outside and inside else door.global_position
			openings.append({"position": center + Vector3.UP * 0.6, "name": str(door.name)})
	for window in get_tree().get_nodes_in_group("WindowMarkers"):
		if window is CabinWindow and window.is_glass_shattered and not window.is_boarded:
			openings.append({"position": window.global_position, "name": str(window.name)})
	return openings


## The path from `source` through `opening` to `ear`, if neither leg crosses
## a wall. {factor, walls, obstacles, distance, via} or {} when blocked.
func _leak_through(source: Vector3, ear: Vector3, opening: Dictionary) -> Dictionary:
	var point: Vector3 = opening.position
	var near_side := point + (source - point).normalized() * OPENING_CLEARANCE
	var far_side := point + (ear - point).normalized() * OPENING_CLEARANCE
	var inner := _muffling(source, near_side)
	var outer := _muffling(far_side, ear)
	if inner.walls > 0 or outer.walls > 0:
		return {}
	return {
		"factor": inner.factor * outer.factor * config.hearing_opening_multiplier,
		"walls": 0,
		"obstacles": inner.obstacles + outer.obstacles,
		"distance": source.distance_to(point) + point.distance_to(ear),
		"via": opening.name,
	}


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
	var sight := _base_vision_range()
	# Crouched in a bush, it has to come close to see the player, even when
	# it's looking out for them (a lit flashlight gives them away).
	return minf(sight, config.bush_cover_range) if player_in_cover() else sight


func _base_vision_range() -> float:
	var player := entity.get_player()
	# No player yet (the Entity isn't active; the F3 overlay still asks).
	if not player:
		return config.vision_range_dark
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


## Crouched in a bush, flashlight off (FoliageRustle).
func player_in_cover() -> bool:
	var player := entity.get_player()
	if not player or not (player.has_method("is_crouching") and player.is_crouching()):
		return false
	if player.has_method("is_flashlight_on") and player.is_flashlight_on():
		return false
	var rustle := entity.get_tree().get_first_node_in_group("foliage_rustle")
	return rustle != null and rustle.in_cover(player.global_position)


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
