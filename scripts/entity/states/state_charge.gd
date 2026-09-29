class_name EntityStateCharge
extends EntityState

## A lunge at the player. Outdoors (and when defending the totem) it is
## committed and the flashlight can't stop it. Indoors it is slower and the
## overcharged beam still drives it off; that is the player's defence.
## Ends when the player has been out of sight for a moment or after
## config.charge_max_time. Indoors it goes back to hunting the cabin (never to
## the treeline); outdoors it searches where it last saw them.
##
## data {"committed": true} (totem defence) tracks the player directly for
## the whole charge instead of only while visible.

const S := Entity.State

var _committed := false
var _lost_time := 0.0


func enter(_from: int, data: Dictionary) -> void:
	_committed = data.get("committed", false)
	_lost_time = 0.0
	entity.audio.play_voice("angry", true)
	entity.audio.play_roar()
	entity.audio.start_chase_music()


func exit(_to: int) -> void:
	entity.audio.stop_chase_music()


func update(delta: float) -> void:
	_lost_time = 0.0 if perception.can_see_player else _lost_time + delta
	var player := entity.get_player()
	var tracks_player := _committed or perception.can_see_player or _lost_time < 0.5
	var target := player.global_position if tracks_player else perception.last_seen_position
	var speed := config.indoor_charge_speed if perception.entity_inside else config.charge_speed
	entity.move_to(target, speed)


func next_state() -> int:
	var lost := _lost_time > config.charge_lose_sight_time and not _committed
	if not lost and time < config.charge_max_time:
		return NO_CHANGE
	if perception.entity_inside:
		return S.HUNT
	if perception.player_outside:
		return go(S.SEARCH, {"target": perception.last_seen_position})
	return S.OBSERVE


func can_catch() -> bool:
	return true


func reacts_to_flashlight() -> bool:
	return perception.entity_inside and not _committed


func reacts_to_lamp() -> bool:
	return false
