class_name EntityStateAttackLamp
extends EntityState

## The portable lamp is deployed, powered and shining: it goes and smashes it.
## When the lamp goes dark it returns to hunting (inside) or watching.

const S := Entity.State

var _swing: EntitySwing


func enter(_from: int, _data: Dictionary) -> void:
	_swing = EntitySwing.new(config.lamp_hit_interval, config.hit_impact_delay)
	entity.audio.play_grunt(1.1)


func update(delta: float) -> void:
	var lamp := world.active_lamp()
	if not lamp:
		return
	var remaining := entity.move_to(lamp.global_position, config.stalk_speed)
	if remaining > config.lamp_attack_range:
		return
	entity.stop()
	entity.face(lamp.global_position)
	if _swing.update(delta, entity) and lamp.has_method("take_physical_hit"):
		lamp.take_physical_hit((lamp.global_position - entity.global_position).normalized())


func next_state() -> int:
	if world.active_lamp():
		return NO_CHANGE
	return S.HUNT if perception.entity_inside else S.OBSERVE


func reacts_to_lamp() -> bool:
	return false


func can_catch() -> bool:
	return true
