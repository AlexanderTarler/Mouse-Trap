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

# ─── Transition data keys (enter()'s `data`, Entity.request_state) ───────────
# Named, so a mistyped key is an error instead of a default silently used.
const ENTRY := "entry"          ## CabinEntryLink: the window or door it is for.
const DECOY := "decoy"          ## CabinEntryLink: the window to make noise at (LURE).
const RUSH := "rush"            ## APPROACH: fast, no stopping (after a lure).
const RATTLE := "rattle"        ## PEEK: a locked door, try the handle and leave.
const CALM := "calm"            ## FLEE: leaving on its own (walks, no penalty).
const VANISH := "vanish"        ## FLEE: the van chase ends, gone when done.
const COMMITTED := "committed"  ## CHARGE: tracks the player the whole way.
const NO_ROAR := "no_roar"      ## CHARGE: no roar first.
const MAX_TIME := "max_time"    ## CHARGE: lasts this long (s).
const DURATION := "duration"    ## STUNNED: for this long (s).
const TARGET := "target"        ## SEARCH: Vector3, where to look.

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


## Switches to `to` with `data` (for transitions that need to pass something,
## such as an entry point). Use as `return go(State.X, {ENTRY: link})` from
## next_state().
func go(to: int, data: Dictionary = {}) -> int:
	brain.go(to, data)
	return NO_CHANGE


## The player has left the cabin while it was busy at it (walking up, at a
## window, luring): after them if it can see them, else back to watching.
## NO_CHANGE while the player is inside.
func player_left_cabin() -> int:
	if not perception.player_outside:
		return NO_CHANGE
	return Entity.State.STALK if perception.can_see_player else Entity.State.OBSERVE


## A spot beside `link` on the outside, `distance` m along the wall (either
## way): out of view of the glass (ducking away from a look, a pause in
## breaking in).
func beside_entry(link: CabinEntryLink, distance: float) -> Vector3:
	var across := link.end_position - link.start_position
	var side := Vector3(-across.z, 0.0, across.x).normalized() * (distance if randf() < 0.5 else -distance)
	return world.snap_to_navmesh(link.start_position + side)
