class_name EntityStateEnter
extends EntityState

## Getting inside through an open entry (data {ENTRY: CabinEntryLink}).
## It paths to the entry's inside point: the route crosses the entry link,
## and Entity._traverse() plays the climb (window) or opens the door and
## walks through it. Once standing at the link's outside end it crosses
## directly, so a spot the navmesh can't route from doesn't strand it.

const S := Entity.State
const INSIDE_DISTANCE := 2.5
const GIVE_UP_TIME := 12.0
const AT_LINK_DISTANCE := 1.2

var _entry: CabinEntryLink = null


func enter(_from: int, data: Dictionary) -> void:
	_entry = data.get(ENTRY)
	brain.target_entry = _entry


func update(_delta: float) -> void:
	# Clinging outside an upstairs window: in through it.
	if entity.is_perched_at(_entry):
		entity.enter_from_perch(_entry)
		return
	if not perception.entity_inside 			and Entity.reach_distance(entity.global_position, _entry.start_position) < AT_LINK_DISTANCE:
		entity.traverse_link(_entry, true)
		return
	entity.move_to(_entry.end_position, config.approach_speed)


func next_state() -> int:
	if entity.is_traversing():
		return NO_CHANGE
	var inside := perception.entity_inside
	if inside and Entity.reach_distance(entity.global_position, _entry.end_position) < INSIDE_DISTANCE:
		return S.HUNT
	if not inside and not _entry.enabled:
		# Shut before it got through (door locked again, window re-boarded).
		entity.audio.play_grunt(1.2)
		return S.OBSERVE
	if time > GIVE_UP_TIME:
		return S.HUNT if inside else S.OBSERVE
	return NO_CHANGE
