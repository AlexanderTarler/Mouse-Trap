class_name EntityStateFlee
extends EntityState

## Running from the light, or leaving the cabin.
##   Inside:  heads out through the nearest open entry (the route crosses its
##            link, so it climbs back out of the window it came in through,
##            or leaves by the door). If every entry is shut it waits for a
##            moment the player isn't looking and slips out.
##   Outside: sprints for a dark spot away from the player.
## It is done once it has arrived somewhere the player can't see it.
##
## data:
##   {"calm": true}   leaving on its own: no confidence penalty, walks.
##   {"vanish": true} end of the van chase: deactivates when done.

const S := Entity.State
const ARRIVE_DISTANCE := 1.5
const REPEL_SOURCES := [S.APPROACH, S.PEEK, S.BREACH, S.ENTER, S.STANDOFF]

var _calm := false
var _vanish := false
var _sealed_in := false
var _destination := Vector3.ZERO
var _arrived := false
## Sealed in: the next look for a way to slip out (not every frame).
var _slip_retry := 0.0
const SLIP_RETRY := 0.5


func enter(from: int, data: Dictionary) -> void:
	_calm = data.get("calm", false)
	entity.cancel_oneshot()   # driven off mid-roar
	_vanish = data.get("vanish", false)
	_arrived = false
	if not _calm and not _vanish:
		entity.confidence.repelled()
		if from in REPEL_SOURCES:
			world.mark_repelled(brain.target_entry)
	brain.target_entry = null
	_choose_destination()


func update(delta: float) -> void:
	if _sealed_in:
		entity.stop()
		_slip_retry -= delta
		if _slip_retry > 0.0:
			return
		_slip_retry = SLIP_RETRY
		var spot := world.find_hidden_point(world.cabin_center(), 12.0, 20.0, Vector3.INF)
		if spot != Vector3.INF and entity.try_teleport(spot):
			_sealed_in = false
			_destination = spot
		return
	var speed := config.hunt_speed if _calm else config.flee_speed
	var remaining := entity.move_to(_destination, speed)
	_arrived = remaining < ARRIVE_DISTANCE or (entity.nav_agent.is_navigation_finished() and remaining < 4.0)


func next_state() -> int:
	if entity.is_traversing():
		return NO_CHANGE
	var out_of_sight := not perception.in_player_view
	var timed_out := time > config.flee_max_time * (2.0 if _calm else 1.0)
	if not ((_arrived and out_of_sight) or timed_out):
		return NO_CHANGE
	if perception.entity_inside:
		# Still inside after running out of time: try again from here.
		_choose_destination()
		time = 0.0
		return NO_CHANGE
	if _vanish:
		entity.end_van_chase()
		return NO_CHANGE
	return S.OBSERVE


func reacts_to_flashlight() -> bool:
	return false


func reacts_to_lamp() -> bool:
	return false


func _choose_destination() -> void:
	_sealed_in = false
	_slip_retry = 0.0
	if perception.entity_inside:
		var exit := world.nearest_exit()
		if exit:
			_destination = world.outside_of(exit, 6.0)
		else:
			_sealed_in = true
		return
	var threat := entity.get_player().global_position
	_destination = world.find_flee_point(entity.global_position, threat, config.flee_distance)
