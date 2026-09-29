class_name EntityStateStandoff
extends EntityState

## Held by the flashlight.
##   Overcharged beam: it writhes in the light; after
##   config.overcharge_repel_time it flees.
##   Standard beam (both outside): it freezes and stares back; hold the beam
##   on it for config.charge_stare_time and it charges.
## When the beam is gone it goes back to what it was doing.

const S := Entity.State
const RESUMABLE := [S.OBSERVE, S.STALK, S.SEARCH, S.APPROACH, S.HUNT]

var _resume_state := S.OBSERVE
var _lost_time := 0.0
var _screamed := false


func enter(from: int, _data: Dictionary) -> void:
	_resume_state = from
	_lost_time = 0.0
	_screamed = false


func update(delta: float) -> void:
	entity.stop()
	entity.face(entity.get_player().global_position)
	var writhing := perception.overcharged or perception.overcharge_time > 0.0
	entity.play_anim(&"entity_in_light" if writhing else &"Idle")
	if writhing and not _screamed:
		_screamed = true
		entity.audio.play_scream()
	_lost_time = 0.0 if perception.illuminated else _lost_time + delta


func next_state() -> int:
	if perception.overcharge_time >= config.overcharge_repel_time:
		return S.FLEE
	if perception.overcharged and perception.entity_inside != perception.player_inside:
		return S.FLEE
	var both_outside := not perception.entity_inside and not perception.player_inside
	if both_outside and perception.illuminated and not perception.overcharged \
			and perception.stare_time >= config.charge_stare_time:
		return S.CHARGE
	if _lost_time > config.standoff_release_time:
		if _resume_state in RESUMABLE:
			return _resume_state
		return S.HUNT if perception.entity_inside else S.OBSERVE
	return NO_CHANGE


func reacts_to_flashlight() -> bool:
	return false


func reacts_to_lamp() -> bool:
	return false
