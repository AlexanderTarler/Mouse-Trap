class_name EntityBrain
extends Node

## The Entity's state machine.
##
## Each physics frame:
##   1. Perception and confidence update (once, so every state sees the same
##      snapshot).
##   2. Interrupts: reactions that apply to most states (the flashlight, a lit
##      room indoors, the portable lamp). A state opts out through
##      reacts_to_flashlight() / reacts_to_lamp().
##   3. The current state updates, then decides whether to switch.
##
## External systems use force() (via Entity.request_state and friends).

signal state_changed(from: int, to: int)

const S := Entity.State
const HISTORY_SIZE := 12

var entity: Entity
var state_id: int = S.DORMANT
var previous_state_id: int = S.DORMANT
var current: EntityState
## Recent transitions ("OBSERVE -> STALK") for the debug overlay.
var history: Array[String] = []
## The window/door the Entity is currently going for (set by APPROACH, PEEK,
## BREACH, ENTER). FLEE marks it as repelled.
var target_entry: CabinEntryLink = null

var _states: Dictionary = {}


func setup(owner_entity: Entity) -> void:
	entity = owner_entity
	_register(S.DORMANT, EntityStateDormant.new())
	_register(S.OBSERVE, EntityStateObserve.new())
	_register(S.STALK, EntityStateStalk.new())
	_register(S.SEARCH, EntityStateSearch.new())
	_register(S.CHARGE, EntityStateCharge.new())
	_register(S.APPROACH, EntityStateApproach.new())
	_register(S.PEEK, EntityStatePeek.new())
	_register(S.BREACH, EntityStateBreach.new())
	_register(S.ENTER, EntityStateEnter.new())
	_register(S.HUNT, EntityStateHunt.new())
	_register(S.STANDOFF, EntityStateStandoff.new())
	_register(S.FLEE, EntityStateFlee.new())
	_register(S.STUNNED, EntityStateStunned.new())
	_register(S.SABOTAGE, EntityStateSabotage.new())
	_register(S.ATTACK_LAMP, EntityStateAttackLamp.new())
	current = _states[S.DORMANT]


## The brain is created after every other module, so states can grab them.
func _register(id: int, state: EntityState) -> void:
	state.setup(entity, self)
	_states[id] = state


func tick(delta: float) -> void:
	entity.perception.update(delta)
	entity.confidence.update(delta)
	entity.world.update(delta)

	current.time += delta
	var interrupt := _check_interrupts()
	if interrupt != EntityState.NO_CHANGE and interrupt != state_id:
		_transition(interrupt, {})

	current.update(delta)
	var next := current.next_state()
	if next != EntityState.NO_CHANGE and next != state_id:
		_transition(next, {})


## Switches state immediately, from outside the normal flow.
func force(to: int, data: Dictionary = {}) -> void:
	_transition(to, data)


## Switches state from inside a state's update(), passing data along.
func go(to: int, data: Dictionary = {}) -> void:
	_transition(to, data)


func get_state(id: int) -> EntityState:
	return _states[id]


func _transition(to: int, data: Dictionary) -> void:
	var from := state_id
	current.exit(to)
	previous_state_id = from
	state_id = to
	current = _states[to]
	current.time = 0.0
	current.enter(from, data)
	history.push_front("%s -> %s" % [S.keys()[from], S.keys()[to]])
	if history.size() > HISTORY_SIZE:
		history.pop_back()
	state_changed.emit(from, to)


func _check_interrupts() -> int:
	if state_id == S.DORMANT or entity.van_chase_active:
		return EntityState.NO_CHANGE
	var p := entity.perception

	# The flashlight. Only the overcharged beam repels; the standard beam
	# freezes it outdoors when both are outside (and leads to a charge).
	if current.reacts_to_flashlight() and state_id != S.STANDOFF:
		if p.overcharged:
			var entity_inside := p.entity_inside
			var player_inside := p.player_inside
			if entity_inside != player_inside:
				return S.FLEE
			return S.STANDOFF
		if p.illuminated and not p.entity_inside and not p.player_inside:
			return S.STANDOFF

	# It will not stay in a lit room.
	if p.entity_inside and p.entity_in_lit_room and state_id != S.FLEE and state_id != S.STUNNED:
		return S.FLEE

	# A lit portable lamp must be destroyed.
	if current.reacts_to_lamp() and entity.can_approach_cabin() and entity.world.active_lamp() != null:
		return S.ATTACK_LAMP

	return EntityState.NO_CHANGE
