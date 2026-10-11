class_name EntityStateBreach
extends EntityState

## Breaking in through a window (data {"entry": CabinEntryLink}): the glass
## first, then one plank at a time. Once the window is passable its link
## switches on and the Entity climbs in (ENTER).
##
## The blows don't keep time: a steady blow, a long silence, then two or
## three in a rush. Sometimes (config.breach_pause_chance, once) it stops
## halfway, steps aside out of view of the glass, and goes quiet for a
## while, so the player can't tell whether it gave up.
##
## Gives up if the room lights up, if it reaches planks it isn't allowed to
## break tonight, or after config.breach_max_time (not counting the pause).

const S := Entity.State
const SIDESTEP := 1.8
const PAUSE_MIN := 8.0
const PAUSE_MAX := 16.0

var _entry: CabinEntryLink = null
var _swing: EntitySwing
var _hits := 0
var _burst_left := 0
var _pause_left := 0.0
var _paused := false
var _paused_time := 0.0
var _aside := Vector3.ZERO


func enter(_from: int, data: Dictionary) -> void:
	_entry = data.get("entry")
	brain.target_entry = _entry
	_swing = EntitySwing.new(config.hit_interval, config.hit_impact_delay)
	_hits = 0
	_burst_left = 0
	_pause_left = 0.0
	_paused = false
	_paused_time = 0.0


func update(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left -= delta
		_paused_time += delta
		_wait_aside()
		return
	if _entry.climb:
		entity.set_perch_duck(false)
	if not hold_at_entry(_entry, config.approach_speed):
		return   # still getting there (or climbing up to it)
	entity.face(_entry.end_position)
	if _swing.update(delta, entity):
		_entry.entry.damage_barricade()
		entity.traces.scratch_window(_entry)
		entity.audio.play_grunt(randf_range(0.8, 1.0))
		_hits += 1
		_swing.interval = _next_interval()
		if not _paused and _hits >= 2 and randf() < config.breach_pause_chance:
			_start_pause()


## The wait before the next blow: mostly steady, sometimes a long silence,
## sometimes a rush of two or three.
func _next_interval() -> float:
	if _burst_left > 0:
		_burst_left -= 1
		return 0.5
	var roll := randf()
	if roll < 0.25:
		_burst_left = randi_range(1, 2)
		return 0.5
	if roll < 0.5:
		return randf_range(3.5, 6.0)
	return config.hit_interval * randf_range(0.8, 1.3)


func _start_pause() -> void:
	_paused = true
	_burst_left = 0
	_pause_left = randf_range(PAUSE_MIN, PAUSE_MAX)
	var across := _entry.end_position - _entry.start_position
	var side := Vector3(-across.z, 0.0, across.x).normalized() * (SIDESTEP if randf() < 0.5 else -SIDESTEP)
	_aside = world.snap_to_navmesh(_entry.start_position + side)


## Quiet, beside the window (or below the sill), out of view of the glass.
func _wait_aside() -> void:
	if _entry.climb:
		if entity.is_perched_at(_entry):
			entity.set_perch_duck(true)
			entity.stop()
		return
	if entity.move_to(_aside, config.approach_speed) < 0.6:
		entity.stop()
		entity.face(_entry.end_position)


func is_pausing() -> bool:
	return _pause_left > 0.0


func next_state() -> int:
	var window = _entry.entry
	if window.is_passable():
		return go(S.ENTER, {"entry": _entry})
	if perception.player_outside:
		return S.STALK if perception.can_see_player else S.OBSERVE
	if world.is_entry_lit(_entry):
		entity.audio.play_grunt(1.3)
		return S.OBSERVE
	var stuck_on_planks: bool = window.is_glass_shattered and window.is_boarded and not entity.can_break_planks()
	if stuck_on_planks or time - _paused_time > config.breach_max_time:
		world.mark_repelled(_entry)
		return S.OBSERVE
	return NO_CHANGE
