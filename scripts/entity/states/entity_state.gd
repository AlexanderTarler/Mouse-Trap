class_name EntityState
extends RefCounted

## Base class for one Entity behaviour. The brain calls, in order:
##   enter(from, data)  once, when the state becomes active
##   update(delta)      every physics frame: set movement via entity.move_to()
##                      etc. Movement is reset each frame, so a frame that
##                      doesn't call a move function stands still.
##   next_state()       every frame after update(); return a State to switch,
##                      or NO_CHANGE to stay
##   exit(to)           once, when leaving
##
## `time` is the number of seconds since enter().

const NO_CHANGE := -1

var entity: Entity
var brain: EntityBrain
var perception: EntityPerception
var world: EntityWorld
var config: EntityConfig
var time := 0.0


func setup(owner_entity: Entity, owner_brain: EntityBrain) -> void:
	entity = owner_entity
	brain = owner_brain
	perception = owner_entity.perception
	world = owner_entity.world
	config = owner_entity.config


func enter(_from: int, _data: Dictionary) -> void:
	pass


func exit(_to: int) -> void:
	pass


func update(_delta: float) -> void:
	pass


func next_state() -> int:
	return NO_CHANGE


## Whether touching the player in this state kills them.
func can_catch() -> bool:
	return false


## Whether the flashlight can interrupt this state.
func reacts_to_flashlight() -> bool:
	return true


## Whether a lit portable lamp pulls the Entity out of this state.
func reacts_to_lamp() -> bool:
	return true


## Called when movement has made no progress for config.stuck_time seconds.
func on_stuck() -> void:
	entity.unstick()


## Switches to `to` with `data` (for transitions that need to pass something,
## such as an entry point). Use as `return go(State.X, {...})` from next_state().
## Keeps it at `link`'s outside spot: on the ground in front of a door or a
## ground-floor window, or clinging to the wall outside an upstairs window
## (climbing up first). True once it is there.
func hold_at_entry(link: CabinEntryLink, speed: float) -> bool:
	if link.climb:
		if entity.is_perched_at(link):
			entity.stop()
			return true
		if not entity.is_traversing() and entity.move_to(link.start_position, speed) < 0.8:
			entity.climb_to_perch(link)
		return false
	if entity.move_to(link.start_position, speed) < 0.6:
		entity.stop()
		return true
	return false


func go(to: int, data: Dictionary = {}) -> int:
	brain.go(to, data)
	return NO_CHANGE


## Where to go looking for the player, based on memory: last sighting if it's
## fresh, otherwise the last noise, otherwise null.
func freshest_lead():
	if perception.has_fresh_sighting():
		return perception.last_seen_position
	if perception.has_fresh_noise():
		return perception.last_heard_position
	return null
