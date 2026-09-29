class_name EntityStateEnter
extends EntityState

## Getting inside through an open entry (data {"entry": CabinEntryLink}).
## It simply paths to the entry's inside point: the route crosses the entry
## link, and Entity._traverse() plays the climb (window) or opens the door
## and walks through it.

const S := Entity.State
const INSIDE_DISTANCE := 2.5
const GIVE_UP_TIME := 12.0

var _entry: CabinEntryLink = null


func enter(_from: int, data: Dictionary) -> void:
	_entry = data.get("entry")
	brain.target_entry = _entry


func update(_delta: float) -> void:
	entity.move_to(_entry.end_position, config.approach_speed)


func next_state() -> int:
	if entity.is_traversing():
		return NO_CHANGE
	var inside := perception.entity_inside
	if inside and Entity._flat_distance(entity.global_position, _entry.end_position) < INSIDE_DISTANCE:
		return S.HUNT
	if not inside and not _entry.enabled:
		# Shut before it got through (door locked again, window re-boarded).
		entity.audio.play_grunt(1.2)
		return S.OBSERVE
	if time > GIVE_UP_TIME:
		return S.HUNT if inside else S.OBSERVE
	return NO_CHANGE
