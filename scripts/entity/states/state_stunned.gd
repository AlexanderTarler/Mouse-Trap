class_name EntityStateStunned
extends EntityState

## Paralysed by the portable lamp's overload (data {"duration": seconds}).
## The totem defence is off while it lasts. A generator blackout breaks the
## stun early and enrages it (Entity.on_generator_blackout).
## Afterwards: charges a player who is outside, otherwise goes for the fuse box.

const S := Entity.State

var _left := 0.0


func enter(_from: int, data: Dictionary) -> void:
	_left = data.get("duration", 30.0)
	entity.totem_defense_disabled = true
	entity.audio.play_scream()


func exit(_to: int) -> void:
	entity.totem_defense_disabled = false


func update(delta: float) -> void:
	_left -= delta
	entity.stop()
	entity.play_anim(&"entity_in_light")


func next_state() -> int:
	if _left > 0.0:
		return NO_CHANGE
	if perception.player_outside:
		return S.CHARGE
	var box := world.fuse_box()
	if box and box.is_powered():
		return S.SABOTAGE
	return S.HUNT if perception.entity_inside else S.OBSERVE


func reacts_to_flashlight() -> bool:
	return false


func reacts_to_lamp() -> bool:
	return false
