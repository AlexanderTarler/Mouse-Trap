class_name EntityStateSearch
extends EntityState

## Investigating a position (where the player was seen or heard): walks
## there, stops to listen, then checks a few spots nearby. A new noise
## redirects the search. Outdoors it speeds up exponentially the longer it
## searches (config.search_speed_doubling_time, up to search_speed_max).

const S := Entity.State
const ARRIVE_DISTANCE := 1.0
const NEW_NOISE_DISTANCE := 3.0

var _points: Array[Vector3] = []
var _index := 0
var _listen_left := 0.0
var _heard_at := Vector3.INF


func enter(_from: int, data: Dictionary) -> void:
	var target: Vector3 = data.get("target", perception.last_seen_position)
	_plan(target)
	entity.audio.play_voice("search")


func update(delta: float) -> void:
	# A fresh noise somewhere else: go there instead.
	if perception.has_fresh_noise(0.3) and perception.last_heard_position.distance_to(_heard_at) > NEW_NOISE_DISTANCE:
		_plan(perception.last_heard_position)

	if _index >= _points.size():
		entity.stop()
		return
	if _listen_left > 0.0:
		_listen_left -= delta
		entity.stop()
		# Turn slowly while listening.
		var sweep := Vector3(sin(time * 0.9), 0.0, cos(time * 0.9))
		entity.face(entity.global_position + sweep)
		if _listen_left <= 0.0:
			_index += 1
		return
	var remaining := entity.move_to(_points[_index], current_speed())
	if remaining < ARRIVE_DISTANCE or entity.nav_agent.is_navigation_finished():
		_listen_left = randf_range(config.search_listen_min, config.search_listen_max) / _urgency()


func next_state() -> int:
	if perception.can_see_player:
		return S.STALK if perception.player_outside else S.OBSERVE
	if perception.entity_inside and perception.player_inside:
		return S.HUNT
	if perception.player_inside:
		return S.OBSERVE
	if _index >= _points.size():
		return S.OBSERVE
	return NO_CHANGE


func can_catch() -> bool:
	return true


## How much faster than config.search_speed it is searching right now: 1 at
## first, doubling every search_speed_doubling_time seconds while both are
## outside.
func _urgency() -> float:
	if perception.entity_inside or perception.player_inside or config.search_speed_doubling_time <= 0.0:
		return 1.0
	var cap := maxf(config.search_speed_max / config.search_speed, 1.0)
	return minf(pow(2.0, time / config.search_speed_doubling_time), cap)


func current_speed() -> float:
	return config.search_speed * _urgency()


func _plan(target: Vector3) -> void:
	_heard_at = perception.last_heard_position if perception.has_fresh_noise(0.3) else Vector3.INF
	_points.clear()
	_points.append(world.snap_to_navmesh(target))
	for i in maxi(config.search_points - 1, 0):
		var angle := randf() * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * randf_range(config.search_radius * 0.4, config.search_radius)
		_points.append(world.snap_to_navmesh(target + offset))
	_index = 0
	_listen_left = 0.0
