class_name EntityStateSabotage
extends EntityState

## Goes to the fuse box and smashes it, killing the generator and every light
## it powers. Triggered when every entry has been blocked for too long.
## If it can't reach the box in config.sabotage_max_time it closes the
## distance by teleporting, but only out of the player's sight.

const S := Entity.State
const ARRIVE_DISTANCE := 1.2

var _box: Node = null
var _stand_at := Vector3.ZERO
var _hits := 0
var _swing: EntitySwing


func enter(_from: int, _data: Dictionary) -> void:
	_box = world.fuse_box()
	_stand_at = world.fuse_position()
	_hits = 0
	_swing = EntitySwing.new(config.fuse_hit_interval, config.hit_impact_delay)


func update(delta: float) -> void:
	if not _box or _stand_at == Vector3.INF:
		return
	var remaining := entity.move_to(_stand_at, config.approach_speed * 1.4)
	if remaining > ARRIVE_DISTANCE:
		if time > config.sabotage_max_time:
			entity.try_teleport(_stand_at)
		return
	entity.stop()
	entity.face(_box.global_position)
	if _swing.update(delta, entity):
		_hits += 1
		entity.audio.play_grunt(0.85)
		if _hits >= config.fuse_hits:
			_box.break_fuse()


func next_state() -> int:
	if not _box or _stand_at == Vector3.INF or not _box.is_powered():
		return S.OBSERVE
	if perception.can_see_player and perception.player_outside and perception.distance_to_player < 8.0:
		return S.STALK
	return NO_CHANGE
