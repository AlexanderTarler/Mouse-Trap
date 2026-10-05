class_name EntityStateHunt
extends EntityState

## Inside the cabin. It goes where it last saw or heard the player, and
## otherwise prowls from room to room, stopping in each to look around. It
## does not know which room the player is hiding in, but it remembers where
## it found them before (across nights) and checks those spots first.
##
## A player sheltering in a lit room is safe from it, but not from being
## watched: it waits in the dark nearby, staring. Seeing the player up close
## in the dark means a charge. If nothing turns up for
## config.hunt_give_up_time it leaves (FLEE, calm).

const S := Entity.State
const ARRIVE_DISTANCE := 1.0
const CHARGE_DISTANCE := 9.0
const REMEMBER_INTERVAL := 3.0

var _patrol: Array[Vector3] = []
var _patrol_index := 0
var _scan_left := 0.0
var _since_contact := 0.0
var _lead = null   ## Vector3 or null: the position being investigated.
var _remember_cooldown := 0.0


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
	entity.audio.play_voice("search")


func update(delta: float) -> void:
	var player := entity.get_player()
	if perception.can_see_player or perception.has_fresh_noise(1.0):
		_since_contact = 0.0
		_lead = _indoor_lead()
	else:
		_since_contact += delta
	_remember_cooldown -= delta
	if perception.can_see_player and perception.player_inside and _remember_cooldown <= 0.0:
		_remember_cooldown = REMEMBER_INTERVAL
		world.remember_hiding_spot(player.global_position)

	if _player_in_lit_room(player) and perception.has_fresh_sighting(4.0):
		entity.stop()
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
		return

	if _patrol.is_empty():
		entity.stop()
		return
	var remaining := entity.move_to(_patrol[_patrol_index], config.hunt_speed)
	if remaining < ARRIVE_DISTANCE:
		_patrol_index = (_patrol_index + 1) % _patrol.size()
		_scan_left = config.room_scan_time


func next_state() -> int:
	if entity.is_traversing():
		return NO_CHANGE
	if not perception.entity_inside:
		return S.STALK if perception.can_see_player else S.OBSERVE
	var player := entity.get_player()
	if perception.can_see_player and perception.distance_to_player < CHARGE_DISTANCE and not _player_in_lit_room(player):
		return S.CHARGE
	# The player got out: leave and pick up the trail outside.
	if perception.player_outside and _since_contact > 2.0:
		return go(S.FLEE, {"calm": true})
	if _since_contact > config.hunt_give_up_time:
		entity.audio.play_grunt(0.9)
		return go(S.FLEE, {"calm": true})
	return NO_CHANGE


func can_catch() -> bool:
	return true


## The freshest lead, ignoring leads outside the cabin while the player is
## known to be inside (a stale sighting from the yard shouldn't walk it out).
func _indoor_lead():
	var lead = freshest_lead()
	if lead != null and perception.player_inside and not world.is_inside_cabin(lead):
		return null
	return lead


static func _player_in_lit_room(player: Node3D) -> bool:
	return RoomLightDetector.is_position_in_lit_room(player.global_position + Vector3.UP)
