class_name EntityStateStunned
extends EntityState

## Paralysed by the portable lamp's overload (data {"duration": seconds}).
## A generator blackout breaks the stun early and enrages it
## (Entity.on_generator_blackout).
## Afterwards: a committed, fast charge at a player who is outside
## (config.post_stun_chase_time), otherwise it goes for the fuse box.
##
## The totem defence (teleporting to the willow to catch a player there) is
## off from the stun until the player is back inside the cabin
## (Entity._physics_process clears totem_defense_disabled then): the stun
## buys the player their run at the totem, and the chase after it is a race.

const S := Entity.State

var _left := 0.0


func enter(_from: int, data: Dictionary) -> void:
	_left = data.get("duration", 30.0)
	entity.totem_defense_disabled = true
	entity.audio.play_scream()


func update(delta: float) -> void:
	_left -= delta
	entity.stop()
	entity.play_anim(&"entity_in_light")


func next_state() -> int:
	if _left > 0.0:
		return NO_CHANGE
	if perception.player_outside:
		return go(S.CHARGE, {"committed": true, "max_time": config.post_stun_chase_time})
	var box := world.fuse_box()
	if box and box.is_powered():
		return S.SABOTAGE
	return S.HUNT if perception.entity_inside else S.OBSERVE


func reacts_to_flashlight() -> bool:
	return false


func reacts_to_lamp() -> bool:
	return false
