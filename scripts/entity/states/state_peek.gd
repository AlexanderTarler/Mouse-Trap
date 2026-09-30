class_name EntityStatePeek
extends EntityState

## Standing at a window, staring in (data {"entry": CabinEntryLink}).
##
##   - While the player isn't looking, it taps on the glass now and then.
##   - When the player looks at the window it may duck out of sight, then
##     come back.
##   - If the room's light comes on it either kills the light from outside
##     (flicker, then dark) or grunts and leaves.
##   - After a while it starts breaking in (BREACH), or leaves if the window
##     is boarded and it can't break planks tonight.
##
## At a locked door (data "rattle") it tries the handle and leaves.

const S := Entity.State
const LOOK_CONE_DEGREES := 12.0
const DUCK_SIDESTEP := 1.8
const MAX_DUCKS := 2
const LIGHT_KILL_TIME := 2.5

var _entry: CabinEntryLink = null
var _rattle := false
var _stare_left := 0.0
var _tap_left := 0.0
var _duck_left := 0.0
var _duck_position := Vector3.ZERO
var _ducks := 0
var _was_looked_at := false
var _light_kill_left := 0.0   ## Waiting for a sabotaged light to finish flickering.


func enter(_from: int, data: Dictionary) -> void:
	_entry = data.get("entry")
	brain.target_entry = _entry
	_rattle = data.get("rattle", false)
	_ducks = 0
	_duck_left = 0.0
	_was_looked_at = false
	_light_kill_left = 0.0
	_tap_left = randf_range(config.tap_interval_min, config.tap_interval_max)
	if _rattle:
		_stare_left = 2.5
		_entry.entry.interact()   # Locked: plays the rattle.
	else:
		_stare_left = randf_range(config.peek_time_min, config.peek_time_max)
		entity.traces.scratch_window(_entry)


func update(delta: float) -> void:
	_light_kill_left -= delta
	if _duck_left > 0.0:
		_duck_left -= delta
		if _entry.climb:
			entity.set_perch_duck(true)   # below the sill
		else:
			entity.move_to(_duck_position, config.approach_speed)
		return
	if _entry.climb:
		entity.set_perch_duck(false)

	if not hold_at_entry(_entry, config.approach_speed):
		return   # still walking up to it, or climbing
	entity.face(_entry.end_position)
	_stare_left -= delta
	if _rattle:
		return

	var window_position := _entry.entry.global_position
	var looked_at := perception.is_player_looking_at(window_position, LOOK_CONE_DEGREES)
	if looked_at and not _was_looked_at and _ducks < MAX_DUCKS and randf() < config.peek_duck_chance:
		_duck()
	elif not looked_at:
		_tap_left -= delta
		if _tap_left <= 0.0:
			_tap_left = randf_range(config.tap_interval_min, config.tap_interval_max)
			entity.audio.play_tap_at(window_position)
	_was_looked_at = looked_at


func next_state() -> int:
	if perception.player_outside:
		return S.STALK if perception.can_see_player else S.OBSERVE
	if _rattle:
		if _stare_left > 0.0:
			return NO_CHANGE
		world.mark_repelled(_entry)
		return S.OBSERVE
	if world.is_entry_lit(_entry):
		if _light_kill_left > 0.0 or _try_kill_light():
			return NO_CHANGE
		entity.audio.play_grunt(1.3)
		return S.OBSERVE
	if _stare_left > 0.0 or _duck_left > 0.0:
		return NO_CHANGE
	var window = _entry.entry
	if window.is_passable():
		return go(S.ENTER, {"entry": _entry})
	if not (window.is_glass_shattered and window.is_boarded) or entity.can_break_planks():
		return go(S.BREACH, {"entry": _entry})
	world.mark_repelled(_entry)
	return S.OBSERVE


func _duck() -> void:
	_ducks += 1
	_duck_left = config.peek_duck_time
	var across := _entry.end_position - _entry.start_position
	var side := Vector3(-across.z, 0.0, across.x).normalized() * (DUCK_SIDESTEP if randf() < 0.5 else -DUCK_SIDESTEP)
	_duck_position = world.snap_to_navmesh(_entry.start_position + side)
	_stare_left += config.peek_duck_time


## From Night 3 it can reach the room light from outside: flicker, then dark.
func _try_kill_light() -> bool:
	if not entity.can_break_planks() or not world.can_sabotage_light():
		return false
	var light = _entry.entry.get("room_light")
	if light == null or not light.has_method("entity_sabotage"):
		return false
	light.entity_sabotage()
	world.note_light_sabotaged()
	_light_kill_left = LIGHT_KILL_TIME
	_stare_left = maxf(_stare_left, LIGHT_KILL_TIME)
	return true
