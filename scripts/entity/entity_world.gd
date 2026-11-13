class_name EntityWorld
extends Node

## Where things are, and which places are good for the Entity:
##   - treeline vantage points to watch the cabin from
##   - cabin entry points (the CabinEntryLink on each window and the door)
##   - a light map of the yard, so it keeps to the dark
##   - hidden spots near a position (out of the player's view)
##   - the fuse box and the portable lamp
##   - what it has learned: which windows the player guards, and where the
##     player tends to hide inside (kept across nights; it learns)

var entity: Entity
var config: EntityConfig

const LIGHT_CELL := 2.0
const LIGHT_HALF_CELLS := 20            ## 80 m x 80 m around the cabin.
const LIGHT_REBUILD_INTERVAL := 1.5
const DARK_THRESHOLD := 0.1
const REPEL_MEMORY := 90.0              ## Seconds a repelled entry is avoided.
## Long-term "this window is guarded" memory: each repel adds 1, fading with
## this time constant (seconds). pick_entry() subtracts GUARD_PENALTY per point.
const GUARD_MEMORY := 600.0
const GUARD_PENALTY := 1.5
## Rooms that are passages, not places to search.
const NOT_PATROLLED_ROOMS := ["Stairs"]
const MAX_HIDING_SPOTS := 5
const HIDING_SPOT_MERGE := 2.5
## Lit-room lights stutter when it passes this close outside their window.
const PRESENCE_RADIUS := 3.5
const PRESENCE_COOLDOWN := 20.0
const PRESENCE_CHECK_INTERVAL := 0.25
## Fewer, bigger moments: after one of its tricks (a copied sound, a light
## killed from inside, a prop knocked over, an ambush sprung, the fake
## departure) the others wait this long.
const TRICK_GAP := 60.0

var _vantage_points: Array[Node3D] = []
var _last_vantage: Node3D = null
var _entries: Array = []                ## Array[CabinEntryLink]
var _repelled_until: Dictionary = {}    ## CabinEntryLink -> clock time
var _guard_score: Dictionary = {}       ## CabinEntryLink -> float
var _spotted_until: Dictionary = {}     ## CabinEntryLink -> clock time (mark_spotted)
var _hiding_spots: Array[Dictionary] = []   ## {"position": Vector3, "weight": float}
var _presence_timer := 0.0
var _presence_cooldown: Dictionary = {} ## CabinEntryLink -> clock time
var _light_grid := PackedFloat32Array()
var _light_center := Vector3.ZERO
var _light_timer := 0.0
var _clock := 0.0
var _fuse_box: Node = null
var _fuse_box_searched := false
var _cabin_center := Vector3.ZERO
var _last_light_sabotage := -INF
var _last_trick := -INF
var _footprint := PackedVector2Array()
var _footprint_searched := false


func setup(owner_entity: Entity) -> void:
	entity = owner_entity
	config = owner_entity.config
	_light_grid.resize((LIGHT_HALF_CELLS * 2 + 1) * (LIGHT_HALF_CELLS * 2 + 1))


func update(delta: float) -> void:
	_clock += delta
	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = LIGHT_REBUILD_INTERVAL
		_rebuild_light_grid()
	var fade := exp(-delta / GUARD_MEMORY)
	for link in _guard_score:
		_guard_score[link] *= fade
	_presence_timer -= delta
	if _presence_timer <= 0.0:
		_presence_timer = PRESENCE_CHECK_INTERVAL
		_update_presence_flicker()


# ═════════════════════════════════════════════════════════════════════════════
# CABIN ENTRY POINTS
# ═════════════════════════════════════════════════════════════════════════════

func entries() -> Array:
	if _entries.is_empty():
		_entries = get_tree().get_nodes_in_group(CabinEntryLink.GROUP)
	return _entries


func cabin_center() -> Vector3:
	if _cabin_center == Vector3.ZERO and not entries().is_empty():
		for link in entries():
			_cabin_center += link.end_position
		_cabin_center /= entries().size()
	return _cabin_center


## True if this entry's room is lit (lit rooms are off limits).
func is_entry_lit(link: CabinEntryLink) -> bool:
	if link.kind == CabinEntryLink.Kind.WINDOW:
		var light = link.entry.get("room_light")
		return light != null and light.is_room_lit()
	# The door is guarded by its hall light and by the porch light, which
	# burns whenever the generator runs.
	var nm := entity.get_night_manager()
	if nm and nm.get("is_generator_on") == true:
		return true
	return RoomLightDetector.is_position_in_lit_room(link.end_position + Vector3.UP)


func is_repelled(link: CabinEntryLink) -> bool:
	return _repelled_until.get(link, -1.0) > _clock


func mark_repelled(link: CabinEntryLink) -> void:
	if link:
		_repelled_until[link] = _clock + REPEL_MEMORY
		_guard_score[link] = _guard_score.get(link, 0.0) + 1.0


## How strongly it remembers being driven off at this entry.
func guard_score(link: CabinEntryLink) -> float:
	return _guard_score.get(link, 0.0)


## Whether the Entity would currently consider approaching this entry.
func is_entry_viable(link: CabinEntryLink) -> bool:
	if entity.debug_breach:
		return true
	if is_repelled(link) or is_entry_lit(link):
		return false
	# Upstairs windows mean climbing the wall: not before Night 4.
	if link.climb and not entity.can_climb():
		return false
	if link.kind == CabinEntryLink.Kind.WINDOW:
		var window = link.entry
		# Boarded windows are worth approaching only if it can break planks
		# tonight (or the glass is still intact, to peek and smash).
		if window.is_boarded and window.is_glass_shattered and not entity.can_break_planks():
			return false
	return true


## The room an entry opens into (lower case, "" for none).
func entry_room(link: CabinEntryLink) -> String:
	return RoomLightDetector.get_room_name_at(link.end_position + Vector3.UP).to_lower()


## Spotted at an entry (the player saw it there): avoided for a while.
func mark_spotted(link: CabinEntryLink) -> void:
	if link:
		_spotted_until[link] = _clock + entity.config.spotted_memory


func is_spotted(link: CabinEntryLink) -> bool:
	return _spotted_until.get(link, -1.0) > _clock


## Whether the player could see it standing outside this entry right now.
func player_sees_entry(link: CabinEntryLink) -> bool:
	var spot := (perch_position(link) if link.climb else link.start_position) + Vector3.UP * 1.2
	return entity.perception.is_in_player_view(spot)


## How attractive an entry is as a way in (no randomness): open beats shut,
## unboarded beats boarded, the door only when unlocked; dark beats lit;
## less if it was driven off there. `shy` adds its wish not to be seen: away
## from the room it believes the player is in, from entries the player can
## see, from where it was spotted, and towards the far side of the cabin.
func entry_score(link: CabinEntryLink, shy: bool = true) -> float:
	var config := entity.config
	var score := 0.0
	if link.kind == CabinEntryLink.Kind.DOOR:
		score += 3.0 if not link.entry.is_locked else -1.5
	else:
		var window = link.entry
		if window.is_passable():
			score += 3.0
		elif not window.is_boarded:
			score += 1.5
		else:
			score -= window.planks_remaining * 0.5
		if link.climb:
			score -= config.climb_entry_penalty
	score -= get_light_at(link.start_position) * 3.0
	score -= guard_score(link) * GUARD_PENALTY
	if shy:
		var room := entity.perception.believed_player_room().to_lower()
		if room != "" and entry_room(link) == room:
			score -= config.shy_room_penalty
		if player_sees_entry(link):
			score -= config.shy_view_penalty
		if is_spotted(link):
			score -= config.shy_spotted_penalty
		# Far from where it last saw or heard the player (it doesn't know
		# where they are otherwise).
		var lead := entity.perception.freshest_lead()
		if lead != Vector3.INF:
			score += minf(Entity._flat_distance(lead, link.end_position) / 8.0, config.shy_distance_bonus)
	return score


## Chooses an entry to approach, or null if none is viable: the best
## entry_score() (shy), with a little randomness.
func pick_entry() -> CabinEntryLink:
	var best: CabinEntryLink = null
	var best_score := -INF
	for link in entries():
		if not is_entry_viable(link):
			continue
		var score := entry_score(link) + randf() * 2.0
		if score > best_score:
			best_score = score
			best = link
	return best


## Whether there is any way in it would consider (no scoring, no dice).
func has_viable_entry() -> bool:
	for link in entries():
		if is_entry_viable(link):
			return true
	return false


## How it means to get in: {EntityState.ENTRY: link} to go straight for one, or
## {EntityState.ENTRY: link, EntityState.DECOY: other} to lure the player away from `entry`
## first. It lures when the best way in, judged without shyness, opens into
## the room it believes the player is in, and another room has a usable
## window it can make noise at (config.lure_chance). {} if no way in.
func plan_entry() -> Dictionary:
	var room := entity.perception.believed_player_room().to_lower()
	if room != "" and randf() < entity.config.lure_chance:
		var target: CabinEntryLink = null
		var target_score := -INF
		for link in entries():
			if is_entry_viable(link) and not link.climb:
				var score := entry_score(link, false) + randf() * 0.5
				if score > target_score:
					target_score = score
					target = link
		if target and entry_room(target) == room:
			var decoy := _pick_decoy(target, room)
			if decoy:
				return {EntityState.ENTRY: target, EntityState.DECOY: decoy}
	var entry := pick_entry()
	return {EntityState.ENTRY: entry} if entry else {}


## A window of another room to make noise at: on the ground, not one the
## player can see, as far from `target` as possible.
func _pick_decoy(target: CabinEntryLink, player_room: String) -> CabinEntryLink:
	var best: CabinEntryLink = null
	var best_distance := 0.0
	for link in entries():
		if link == target or link.kind != CabinEntryLink.Kind.WINDOW or link.climb:
			continue
		var room := entry_room(link)
		if room == "" or room == player_room or is_entry_lit(link) or player_sees_entry(link):
			continue
		var distance := Entity._flat_distance(link.end_position, target.end_position)
		if distance > best_distance:
			best_distance = distance
			best = link
	return best


## Where it clings outside an upstairs window: feet config.perch_head_height
## below the window's centre and config.perch_wall_offset out from it, so its
## head is at the glass (standing on the ledge where there is one).
func perch_position(link: CabinEntryLink) -> Vector3:
	var outward := link.start_position - link.end_position
	outward.y = 0.0
	outward = outward.normalized()
	return link.entry.global_position + outward * entity.config.perch_wall_offset \
		+ Vector3.DOWN * entity.config.perch_head_height


## The passable entry closest (by path) to the Entity, for leaving the cabin.
func nearest_exit() -> CabinEntryLink:
	var map := entity.get_world_3d().navigation_map
	var best: CabinEntryLink = null
	var best_length := INF
	for link in entries():
		if not link.enabled:
			continue
		var path := NavigationServer3D.map_get_path(map, entity.global_position, link.end_position, true)
		if path.is_empty():
			continue
		var length := _path_length(path)
		if length < best_length:
			best_length = length
			best = link
	return best


## Whether enough quiet has passed since its last trick (TRICK_GAP).
func trick_ready() -> bool:
	return _clock - _last_trick > TRICK_GAP


func note_trick() -> void:
	_last_trick = _clock


## A loose physics prop (a RigidBody3D light enough to tip over: a
## KnockableProp or a pickup lying about, not the portable lamp) within
## `radius` of `pos`, inside the cabin, or null.
func loose_prop_near(pos: Vector3, radius: float) -> RigidBody3D:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP * 0.6)
	query.exclude = [entity.get_rid()]
	for hit in entity.get_world_3d().direct_space_state.intersect_shape(query, 16):
		var body = hit.get("collider")
		if body is RigidBody3D and not body.freeze and body.mass <= 15.0 \
				and not body.is_in_group("player") and not body.has_method("pick_up") and is_inside_cabin(body.global_position):
			return body
	return null


## Room lights can be killed from outside at most once per cooldown.
func can_sabotage_light() -> bool:
	return _clock - _last_light_sabotage > config.light_sabotage_cooldown


func note_light_sabotaged() -> void:
	_last_light_sabotage = _clock


# ─── Hiding spots ─────────────────────────────────────────────────────────────

## Remembers a place inside where it found the player. Nearby sightings merge
## into one spot that grows in weight.
func remember_hiding_spot(pos: Vector3) -> void:
	for spot in _hiding_spots:
		if spot.position.distance_to(pos) < HIDING_SPOT_MERGE:
			spot.position = spot.position.lerp(pos, 0.3)
			spot.weight += 1.0
			return
	_hiding_spots.append({"position": pos, "weight": 1.0})
	_hiding_spots.sort_custom(func(a, b): return a.weight > b.weight)
	if _hiding_spots.size() > MAX_HIDING_SPOTS:
		_hiding_spots.pop_back()


## Remembered hiding spots, most used first.
func hiding_spots() -> Array[Vector3]:
	_hiding_spots.sort_custom(func(a, b): return a.weight > b.weight)
	var result: Array[Vector3] = []
	for spot in _hiding_spots:
		result.append(spot.position)
	return result


# ─── Presence ────────────────────────────────────────────────────────────────

## Passing close outside a lit window makes that room's light stutter.
func _update_presence_flicker() -> void:
	if not entity.is_active() or entity.perception.entity_inside:
		return
	for link in entries():
		if link.kind != CabinEntryLink.Kind.WINDOW:
			continue
		if _presence_cooldown.get(link, -INF) > _clock:
			continue
		if Entity._flat_distance(entity.global_position, link.start_position) > PRESENCE_RADIUS:
			continue
		var light = link.entry.get("room_light")
		if light and light.has_method("presence_flicker") and light.is_room_lit():
			light.presence_flicker()
			_presence_cooldown[link] = _clock + PRESENCE_COOLDOWN


## A point just outside `link`, `distance` meters out from the wall.
func outside_of(link: CabinEntryLink, distance: float = 5.0) -> Vector3:
	var out := link.start_position - link.end_position
	out.y = 0.0
	return snap_to_navmesh(link.start_position + out.normalized() * distance)


# ═════════════════════════════════════════════════════════════════════════════
# VANTAGE POINTS & HIDDEN SPOTS
# ═════════════════════════════════════════════════════════════════════════════

func vantage_points() -> Array[Node3D]:
	if _vantage_points.is_empty():
		for node in get_tree().get_nodes_in_group("Treeline_Vantage_Points"):
			if node is Node3D:
				_vantage_points.append(node)
	return _vantage_points


## Picks a treeline spot to watch from: dark, at a menacing distance from the
## player, different from the last one, and (if `prefer_hidden`) not currently
## on the player's screen.
func pick_vantage_point(prefer_hidden: bool) -> Node3D:
	var player := entity.get_player()
	var best: Node3D = null
	var best_score := -INF
	for point in vantage_points():
		var score := randf()
		var pos := point.global_position
		if point == _last_vantage:
			score -= 3.0
		if is_dark(pos):
			score += 2.0
		if player:
			var dist := pos.distance_to(player.global_position)
			if dist >= 18.0 and dist <= 45.0:
				score += 1.0
		if prefer_hidden and entity.perception.is_in_player_view(pos + Vector3.UP):
			score -= 3.0
		if score > best_score:
			best_score = score
			best = point
	if best:
		_last_vantage = best
	return best


## A walkable point outside the cabin between `min_radius` and `max_radius`
## from `center`, out of the player's view if possible, dark if possible.
## Returns `fallback` when nothing suitable is found.
func find_hidden_point(center: Vector3, min_radius: float, max_radius: float, fallback: Vector3) -> Vector3:
	var best := fallback
	var best_score := -INF
	for i in 12:
		var angle := randf() * TAU
		var radius := randf_range(min_radius, max_radius)
		var candidate := snap_to_navmesh(center + Vector3(cos(angle), 0.0, sin(angle)) * radius)
		if is_inside_cabin(candidate):
			continue
		var score := 0.0
		if not entity.perception.is_in_player_view(candidate + Vector3.UP):
			score += 3.0
		score -= get_light_at(candidate) * 2.0
		if score > best_score:
			best_score = score
			best = candidate
	return best


## Cover indoors: a walkable spot inside the cabin, on the Entity's floor,
## between `min_radius` and `max_radius` from `center`, that the player can't
## see. Darker and nearer the Entity is better. INF if there is none.
func find_cover(center: Vector3, min_radius: float, max_radius: float) -> Vector3:
	var best := Vector3.INF
	var best_score := -INF
	var floor_y := entity.global_position.y
	for i in 20:
		var angle := randf() * TAU
		var radius := randf_range(min_radius, max_radius)
		var candidate := snap_to_navmesh(center + Vector3(cos(angle), 0.0, sin(angle)) * radius)
		if absf(candidate.y - floor_y) > Entity.FLOOR_GAP or not is_inside_cabin(candidate):
			continue
		var p := entity.perception
		if p.is_in_player_view(candidate + Vector3.UP * 1.2) or p.is_in_player_view(candidate + Vector3.UP * 0.4):
			continue
		var score := -get_light_at(candidate) * 3.0 - Entity._flat_distance(candidate, entity.global_position) * 0.3
		if score > best_score:
			best_score = score
			best = candidate
	return best


## A dark spot roughly `distance` meters away from `threat`, for fleeing.
func find_flee_point(from: Vector3, threat: Vector3, distance: float) -> Vector3:
	var away := from - threat
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = from - cabin_center()
		away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD
	var best := snap_to_navmesh(from + away * distance)
	var best_score := -INF
	for offset in [0.0, 35.0, -35.0, 70.0, -70.0]:
		var dir := away.rotated(Vector3.UP, deg_to_rad(offset))
		var candidate := snap_to_navmesh(from + dir * distance)
		if is_inside_cabin(candidate):
			continue
		var score := -absf(offset) / 70.0 - get_light_at(candidate) * 2.0
		if not entity.perception.is_in_player_view(candidate + Vector3.UP):
			score += 1.0
		if score > best_score:
			best_score = score
			best = candidate
	return best


## Floor-level centers of the cabin rooms on both floors, for indoor patrols.
## A room whose nearest navmesh point lies outside the cabin (e.g. a volume
## with no floor of its own) is skipped, or the patrol would lead outdoors.
func room_centers() -> Array[Vector3]:
	var centers: Array[Vector3] = []
	for area in get_tree().get_nodes_in_group("Cabin_Interior"):
		if not area is Area3D or str(area.name) in NOT_PATROLLED_ROOMS:
			continue
		# The room's main box, not the area's origin (they can differ).
		var box := area.get_node_or_null("CollisionShape3D") as Node3D
		var center := snap_to_navmesh(box.global_position if box else area.global_position)
		if is_inside_cabin(center):
			centers.append(center)
	return centers


## True if `pos` is inside the cabin walls, judged by the cabin footprint
## (the outline of the Cabin's ExteriorNavCarve). Falls back to the room
## volumes if the footprint can't be found.
func is_inside_cabin(pos: Vector3) -> bool:
	if _footprint.is_empty() and not _footprint_searched:
		_load_footprint()
	if _footprint.is_empty():
		return RoomLightDetector.get_room_name_at(pos + Vector3.UP) != "Outside"
	return Geometry2D.is_point_in_polygon(Vector2(pos.x, pos.z), _footprint)


func _load_footprint() -> void:
	_footprint_searched = true
	var carve := level_root().find_child("ExteriorNavCarve", true, false) as NavigationObstacle3D
	if not carve:
		push_warning("EntityWorld: ExteriorNavCarve not found; using room volumes for inside/outside.")
		return
	for vertex in carve.vertices:
		var world_vertex := carve.global_transform * vertex
		_footprint.append(Vector2(world_vertex.x, world_vertex.z))


func snap_to_navmesh(pos: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(entity.get_world_3d().navigation_map, pos)


# ═════════════════════════════════════════════════════════════════════════════
# LIGHT MAP
# ═════════════════════════════════════════════════════════════════════════════

## 0.0 = pitch black, 1.0 = fully lit.
func get_light_at(pos: Vector3) -> float:
	var cx := int(round((pos.x - _light_center.x) / LIGHT_CELL))
	var cz := int(round((pos.z - _light_center.z) / LIGHT_CELL))
	if absi(cx) > LIGHT_HALF_CELLS or absi(cz) > LIGHT_HALF_CELLS:
		return 0.0
	return _light_grid[_cell_index(cx, cz)]


func is_dark(pos: Vector3) -> bool:
	return get_light_at(pos) < DARK_THRESHOLD


func _cell_index(cx: int, cz: int) -> int:
	return (cz + LIGHT_HALF_CELLS) * (LIGHT_HALF_CELLS * 2 + 1) + (cx + LIGHT_HALF_CELLS)


func _rebuild_light_grid() -> void:
	_light_center = cabin_center()
	var sources := _light_sources()
	var width := LIGHT_HALF_CELLS * 2 + 1
	for cz in range(-LIGHT_HALF_CELLS, LIGHT_HALF_CELLS + 1):
		for cx in range(-LIGHT_HALF_CELLS, LIGHT_HALF_CELLS + 1):
			var cell := Vector3(_light_center.x + cx * LIGHT_CELL, 0.0, _light_center.z + cz * LIGHT_CELL)
			var total := 0.0
			for source in sources:
				var d := Vector2(cell.x - source.x, cell.z - source.z).length()
				if d < source.w:
					total += 1.0 - d / source.w
			_light_grid[(cz + LIGHT_HALF_CELLS) * width + (cx + LIGHT_HALF_CELLS)] = minf(total, 1.0)


## Active lights as Vector4(x, y, z, radius).
func _light_sources() -> Array[Vector4]:
	var sources: Array[Vector4] = []
	for light in get_tree().get_nodes_in_group("CabinLights"):
		if light.has_method("is_room_lit") and light.is_room_lit():
			sources.append(_source(light, light.get("light_radius"), 8.0))
	var nm := entity.get_night_manager()
	var generator_on: bool = nm != null and nm.get("is_generator_on") == true
	for light in get_tree().get_nodes_in_group("PorchLights"):
		if generator_on and light.get("is_switched_on") != false:
			sources.append(_source(light, light.get("light_radius"), 12.0))
	var lamp := active_lamp()
	if lamp:
		sources.append(_source(lamp, lamp.get("light_radius"), 10.0))
	var player := entity.get_player()
	if player and player.has_method("is_flashlight_on") and player.is_flashlight_on():
		var cam := player.get_node_or_null("CameraHolder/Camera3D") as Node3D
		if cam:
			var beam_end := cam.global_position - cam.global_transform.basis.z * 8.0
			sources.append(Vector4(beam_end.x, beam_end.y, beam_end.z, 4.0))
	return sources


## The level scene (current_scene in game; the Entity's owner when the level
## is instanced some other way, e.g. by tests).
func level_root() -> Node:
	var scene := get_tree().current_scene
	if scene:
		return scene
	return entity.owner if entity.owner else get_tree().root


static func _source(node: Node3D, radius, default_radius: float) -> Vector4:
	var r: float = radius if radius != null else default_radius
	var p := node.global_position
	return Vector4(p.x, p.y, p.z, r)


static func _path_length(path: PackedVector3Array) -> float:
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length


# ═════════════════════════════════════════════════════════════════════════════
# FUSE BOX & PORTABLE LAMP
# ═════════════════════════════════════════════════════════════════════════════

func fuse_box() -> Node:
	if is_instance_valid(entity.fuse_box_node):
		return entity.fuse_box_node
	if not is_instance_valid(_fuse_box) and not _fuse_box_searched:
		_fuse_box_searched = true
		for node in level_root().find_children("*", "", true, false):
			if node is FuseBox:
				_fuse_box = node
				break
	return _fuse_box


## Where to stand to hit the fuse box.
func fuse_position() -> Vector3:
	if is_instance_valid(entity.fuse_waypoint):
		return entity.fuse_waypoint.global_position
	var box := fuse_box()
	if not box:
		return Vector3.INF
	for child in box.get_children():
		if child is Marker3D:
			return child.global_position
	return snap_to_navmesh(box.global_position)


## The portable lamp if it is deployed, powered and shining; otherwise null.
func active_lamp() -> Node3D:
	var lamp := get_tree().get_first_node_in_group("portable_trap") as Node3D
	if lamp and lamp.get("is_deployed") and lamp.get("is_powered") and lamp.get("is_on"):
		return lamp
	return null
