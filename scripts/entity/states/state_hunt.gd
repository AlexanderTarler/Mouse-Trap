class_name EntityStateHunt
extends EntityState

## Inside the cabin. It goes where it last saw or heard the player, and
## otherwise prowls from room to room, stopping in each to look around. It
## does not know which room the player is hiding in, but it remembers where
## it found them before (across nights) and checks those spots first.
##
## It would rather not be seen. Looked at from a distance (or by a player in
## a lit room), it slips out of sight within a moment, into a dark spot the
## player can't see, and crouches there for a few seconds; in the corner of
## the player's eye it carries on. A player sheltering in a lit room is safe
## from it, but not from being waited for: it lurks in the dark nearby, out
## of view. Seeing the player up close in the dark means a charge.
##
## From Night 3 it lies in wait. After checking a room it may crouch in a
## dark corner on the player's way (where it last heard them, or the next
## room), silent and still, for config.ambush_time_min..max. If the player
## comes within config.ambush_spring_distance, or finds it with a look, it
## breathes (the tell), and a moment later lunges, without the roar.
##
## From Night 3 the light isn't a bunker any more: waiting outside a lit
## room, it taps on the wall from the dark side, and after
## config.siege_light_time it kills the light from inside (a stutter, then
## dark; the player can switch it back on). Passing a loose prop while
## unseen, it may knock it over (once a night): a thud from somewhere.
## These tricks keep apart (EntityWorld.trick_ready).
##
## If nothing turns up for config.hunt_give_up_time it leaves (FLEE, calm).
## From Night 3, at most once a night, it only sounds like it leaves: claws
## on the window frame, a thud outside, a growl in the yard, while it waits
## in ambush near the player. Only after that does it really go, quietly.

const S := Entity.State
const ARRIVE_DISTANCE := 1.0
const CHARGE_DISTANCE := 9.0
const REMEMBER_INTERVAL := 3.0
## How long it remembers seeing the player in a lit room, to keep waiting
## outside it (it can't see them from its hiding place).
const SIEGE_MEMORY := 12.0
## Hunting time (outside ambushes) before it will lie in wait again.
const AMBUSH_COOLDOWN := 15.0
## Ambushes on the way of a noise heard this recently; otherwise ahead.
const AMBUSH_NOISE_MEMORY := 30.0
## Knocks over props this close to it.
const PROP_REACH := 1.2

var _patrol: Array[Vector3] = []
var _patrol_index := 0
var _scan_left := 0.0
var _since_contact := 0.0
var _lead = null   ## Vector3 or null: the position being investigated.
var _remember_cooldown := 0.0
## Hiding: where, and for how long yet.
var _cover := Vector3.INF
var _cover_left := 0.0
## Lying in wait: where, facing which way, for how long yet.
var _ambush := Vector3.INF
var _ambush_watch := Vector3.ZERO
var _ambush_left := 0.0
var _ambush_cooldown := 0.0
## The tell before springing from an ambush (-1: not springing).
var _tell_left := -1.0
## After the fake departure's ambush: leave for real (quietly).
var _leave_after_ambush := false
var _faked_night := -1
## Waiting outside a lit room: for how long, and the next tap on the wall.
var _siege_time := 0.0
var _wall_tap_left := 0.0
var _prop_check := 0.0
var _prop_night := -1
## After finding no cover: not looked for again until this runs out (it was
## searched for every frame: 20 navmesh lookups and up to 40 rays each).
var _cover_retry := 0.0
const COVER_RETRY := 0.5


func enter(_from: int, _data: Dictionary) -> void:
	_since_contact = 0.0
	_scan_left = 0.0
	_lead = _indoor_lead()
	# Rooms on its own floor first (in random order), then the other floor,
	# so it doesn't run up and down the stairs between every room.
	var rooms := world.room_centers()
	rooms.shuffle()
	var here := entity.global_position.y
	rooms.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return absf(a.y - here) < Entity.FLOOR_GAP and absf(b.y - here) >= Entity.FLOOR_GAP)
	_patrol = world.hiding_spots()
	_patrol.append_array(rooms)
	_patrol_index = 0
	_remember_cooldown = 0.0
	_cover_left = 0.0
	_ambush = Vector3.INF
	_ambush_cooldown = AMBUSH_COOLDOWN * 0.5
	_tell_left = -1.0
	_leave_after_ambush = false
	_siege_time = 0.0
	_cover_retry = 0.0
	_wall_tap_left = randf_range(3.0, 6.0)
	entity.audio.play_voice("search")


func update(delta: float) -> void:
	var player := entity.get_player()
	if _tell_left >= 0.0:
		_tell_left = maxf(_tell_left - delta, 0.0)
		entity.stop()
		entity.face(player.global_position)
		return
	if perception.can_see_player or perception.has_fresh_noise(1.0):
		_since_contact = 0.0
		if not is_ambushing():
			_lead = _indoor_lead()
	elif not is_ambushing():
		_since_contact += delta
	_remember_cooldown -= delta
	_cover_retry -= delta
	if perception.can_see_player and perception.player_inside and _remember_cooldown <= 0.0:
		_remember_cooldown = REMEMBER_INTERVAL
		world.remember_hiding_spot(player.global_position)

	var lit := _player_in_lit_room(player)
	if lit and perception.has_fresh_sighting(SIEGE_MEMORY):
		_update_siege(delta, player)
	else:
		_siege_time = 0.0
	if is_ambushing():
		if _update_ambush(delta, player, lit):
			return
	else:
		_ambush_cooldown -= delta
	# Looked at from too far to lunge (or from the safety of a light): out
	# of sight.
	if perception.player_watching and _cover_left <= 0.0 and (perception.distance_to_player >= CHARGE_DISTANCE or lit):
		_take_cover(entity.global_position, 1.5, 6.0, randf_range(2.5, 4.5))
	# The player is sheltering in the light: it waits in the dark near the
	# room, out of their view.
	if lit and perception.has_fresh_sighting(SIEGE_MEMORY) and _cover_left <= 0.0:
		if not _take_cover(player.global_position, 3.0, 8.0, 6.0):
			entity.stop()
			entity.face(player.global_position)
			return
	if _cover_left > 0.0:
		_cover_left -= delta
		if entity.move_to(_cover, config.hunt_alert_speed) < 0.7:
			entity.crawl()
			entity.face(player.global_position)
		return

	if _lead != null:
		var remaining := entity.move_to(_lead, config.hunt_alert_speed)
		if remaining < ARRIVE_DISTANCE:
			_lead = null
			_scan_left = config.room_scan_time
		return

	if _scan_left > 0.0:
		_scan_left -= delta
		entity.stop()
		var sweep := Vector3(sin(time * 1.1), 0.0, cos(time * 1.1))
		entity.face(entity.global_position + sweep)
		# Done looking around: maybe wait here for them instead.
		if _scan_left <= 0.0:
			_maybe_ambush()
		return

	if _patrol.is_empty():
		entity.stop()
		return
	_knock_props(delta)
	var remaining := entity.move_to(_patrol[_patrol_index], config.hunt_speed)
	if remaining < ARRIVE_DISTANCE:
		_patrol_index = (_patrol_index + 1) % _patrol.size()
		_scan_left = config.room_scan_time


## Lying in wait. True while it is (this frame is handled).
func _update_ambush(delta: float, player: Node3D, lit: bool) -> bool:
	var close := perception.distance_to_player < config.ambush_spring_distance and absf(player.global_position.y - entity.global_position.y) < Entity.FLOOR_GAP
	var found := perception.player_watching and perception.distance_to_player < CHARGE_DISTANCE
	if not lit and (close or found):
		_spring()
		return true
	_ambush_left -= delta
	# Found from too far to reach: the ambush is spoiled, it slips away.
	if _ambush_left <= 0.0 or (perception.player_watching and not close):
		_ambush = Vector3.INF
		_ambush_cooldown = AMBUSH_COOLDOWN
		return false
	if entity.move_to(_ambush, config.hunt_alert_speed) < 0.7:
		entity.crawl()
		entity.face(player.global_position if perception.can_see_player else _ambush_watch)
	return true


## The tell: a breath, then (next_state) the lunge.
func _spring() -> void:
	_ambush = Vector3.INF
	_ambush_cooldown = AMBUSH_COOLDOWN
	_leave_after_ambush = false
	_tell_left = config.ambush_tell_time
	entity.audio.play_tell()
	world.note_trick()


func _maybe_ambush() -> void:
	if not entity.can_break_planks() or _ambush_cooldown > 0.0 or randf() >= config.ambush_chance:
		return
	var watch: Vector3
	if perception.has_fresh_noise(AMBUSH_NOISE_MEMORY) and world.is_inside_cabin(perception.last_heard_position):
		watch = perception.last_heard_position
	elif not _patrol.is_empty():
		watch = _patrol[_patrol_index]
	else:
		return
	_lie_in_wait(watch, 1.5, 6.0, randf_range(config.ambush_time_min, config.ambush_time_max))


## Waits, hidden, near `watch` (facing it) for `seconds`. False if there is
## no hidden spot.
func _lie_in_wait(watch: Vector3, min_radius: float, max_radius: float, seconds: float) -> bool:
	var spot := world.find_cover(watch, min_radius, max_radius)
	if spot == Vector3.INF:
		return false
	_ambush = spot
	_ambush_watch = watch
	_ambush_left = seconds
	_cover_left = 0.0
	return true


## Giving up: from Night 3, once a night, it only sounds like it leaves.
func _fake_departure() -> bool:
	var night := entity.current_night()
	if not entity.can_break_planks() or _faked_night == night or randf() >= config.fake_departure_chance:
		return false
	var exit := world.nearest_exit()
	if not exit:
		return false
	var player := entity.get_player()
	if not _lie_in_wait(player.global_position, 3.0, 8.0, randf_range(config.ambush_time_min, config.ambush_time_max) + 10.0):
		return false
	_faked_night = night
	_leave_after_ambush = true
	world.note_trick()
	entity.audio.play_departure(exit, world.outside_of(exit, 12.0))
	return true


## Outside a lit room (Night 3): taps on the wall from the dark side, then
## the light goes. Night 2 the light is a safe haven.
func _update_siege(delta: float, player: Node3D) -> void:
	if not entity.can_break_planks():
		return
	_siege_time += delta
	if is_hiding():
		_wall_tap_left -= delta
		if _wall_tap_left <= 0.0:
			_wall_tap_left = randf_range(5.0, 9.0)
			var toward := player.global_position - entity.global_position
			toward.y = 0.0
			entity.audio.play_tap_at(entity.global_position + toward.limit_length(1.0) + Vector3.UP * 1.2)
	if _siege_time >= config.siege_light_time and world.trick_ready() and world.can_sabotage_light():
		if kill_room_light(player.global_position):
			_siege_time = 0.0


## Kills the light of the room at `pos` from inside (a stutter, then dark).
func kill_room_light(pos: Vector3) -> bool:
	var room = RoomLightDetector.get_room_at(pos + Vector3.UP)
	var light = room.get("room_light") if room else null
	if light == null or not light.has_method("entity_sabotage") or light.is_faulty or not light.is_room_lit():
		return false
	light.entity_sabotage()
	world.note_light_sabotaged()
	world.note_trick()
	return true


## Passing a loose prop unseen (Night 3, once a night): knocks it over.
func _knock_props(delta: float) -> void:
	_prop_check -= delta
	if _prop_check > 0.0:
		return
	_prop_check = 0.5
	var night := entity.current_night()
	if not entity.can_break_planks() or _prop_night == night or perception.in_player_view or not world.trick_ready():
		return
	var prop := world.loose_prop_near(entity.global_position, PROP_REACH)
	if prop == null:
		return
	var away := prop.global_position - entity.global_position
	away.y = 0.0
	prop.apply_central_impulse((away.normalized() * 1.5 + Vector3.UP * 0.8) * prop.mass)
	entity.audio.play_thud_at(prop.global_position)
	_prop_night = night
	world.note_trick()


func next_state() -> int:
	if entity.is_traversing():
		return NO_CHANGE
	if _tell_left >= 0.0:
		if _tell_left > 0.0:
			return NO_CHANGE
		_tell_left = -1.0
		return go(S.CHARGE, {"no_roar": true})
	if not perception.entity_inside:
		return S.STALK if perception.can_see_player else S.OBSERVE
	if is_ambushing():
		return NO_CHANGE
	var player := entity.get_player()
	if perception.can_see_player and perception.distance_to_player < CHARGE_DISTANCE and not _player_in_lit_room(player):
		return S.CHARGE
	# The player got out: leave and pick up the trail outside.
	if perception.player_outside and _since_contact > 2.0:
		return go(S.FLEE, {"calm": true})
	if _since_contact > config.hunt_give_up_time:
		if _leave_after_ambush:
			return go(S.FLEE, {"calm": true})
		if _fake_departure():
			return NO_CHANGE
		entity.audio.play_grunt(0.9)
		return go(S.FLEE, {"calm": true})
	return NO_CHANGE


func can_catch() -> bool:
	return true


## Hides at a spot near `center` the player can't see, for `seconds`.
## False if there is none.
func _take_cover(center: Vector3, min_radius: float, max_radius: float, seconds: float) -> bool:
	if _cover_retry > 0.0:
		return false
	var spot := world.find_cover(center, min_radius, max_radius)
	if spot == Vector3.INF:
		_cover_retry = COVER_RETRY
		return false
	_cover = spot
	_cover_left = seconds
	return true


func is_hiding() -> bool:
	return _cover_left > 0.0


## Lying in wait (or on its way there): silent and still.
func is_ambushing() -> bool:
	return _ambush != Vector3.INF


## The freshest lead, ignoring leads outside the cabin while the player is
## known to be inside (a stale sighting from the yard shouldn't walk it out).
func _indoor_lead():
	var lead = freshest_lead()
	if lead != null and perception.player_inside and not world.is_inside_cabin(lead):
		return null
	return lead


static func _player_in_lit_room(player: Node3D) -> bool:
	return RoomLightDetector.is_position_in_lit_room(player.global_position + Vector3.UP)
