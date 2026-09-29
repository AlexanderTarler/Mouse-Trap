class_name EntityStateBreach
extends EntityState

## Breaking in through a window (data {"entry": CabinEntryLink}): the glass
## first, then one plank at a time. Once the window is passable its link
## switches on and the Entity climbs in (ENTER).
##
## Gives up if the room lights up, if it reaches planks it isn't allowed to
## break tonight, or after config.breach_max_time.

const S := Entity.State

var _entry: CabinEntryLink = null
var _swing: EntitySwing


func enter(_from: int, data: Dictionary) -> void:
	_entry = data.get("entry")
	brain.target_entry = _entry
	_swing = EntitySwing.new(config.hit_interval, config.hit_impact_delay)


func update(delta: float) -> void:
	if entity.move_to(_entry.start_position, config.approach_speed) < 0.6:
		entity.stop()
	entity.face(_entry.end_position)
	if _swing.update(delta, entity):
		_entry.entry.damage_barricade()
		entity.audio.play_grunt(randf_range(0.8, 1.0))


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
	if stuck_on_planks or time > config.breach_max_time:
		world.mark_repelled(_entry)
		return S.OBSERVE
	return NO_CHANGE
