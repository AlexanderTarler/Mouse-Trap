class_name EntityStateStalk
extends EntityState

## Following the player outside, toward where it last SAW them (so breaking
## line of sight and moving away actually works).
##
## When the player looks straight at it from a distance it stops dead and
## stares back for a moment, then keeps creeping closer, slowly while
## watched and at full speed when they look away; watching never holds it
## off for good. Close, visible and unwatched, it lunges (CHARGE); watched
## all the way, it simply walks up to them. If the player gets far away and it's out of
## view, it quietly repositions somewhere near them.
##
## During the Night 2 van chase this is a scripted, fully aware pursuit paced
## against the player's sprint; reaching the cabin ends it (FLEE, vanish).

const S := Entity.State
const REPOSITION_COOLDOWN := 4.0
## The player must be inside this long to end the van chase (so brushing the
## porch or a one-frame room change doesn't end it).
const VAN_SAFE_TIME := 0.5

var _lost_time := 0.0
var _reposition_cooldown := 0.0
var _player_inside_time := 0.0
var _watched_time := 0.0


func enter(_from: int, _data: Dictionary) -> void:
	_lost_time = 0.0
	_player_inside_time = 0.0
	_watched_time = 0.0
	_reposition_cooldown = REPOSITION_COOLDOWN
	if entity.van_chase_active:
		entity.audio.start_chase_music()


func exit(_to: int) -> void:
	if entity.van_chase_active:
		entity.audio.stop_chase_music()


func update(delta: float) -> void:
	var player := entity.get_player()
	if entity.van_chase_active:
		_player_inside_time = _player_inside_time + delta if perception.player_inside else 0.0
		entity.move_to(player.global_position, _van_chase_speed(player))
		return

	_lost_time = 0.0 if perception.can_see_player else _lost_time + delta
	_reposition_cooldown -= delta

	var speed := config.stalk_speed
	_watched_time = _watched_time + delta if perception.player_watching else 0.0
	if config.stalk_freeze_when_watched and perception.player_watching \
			and perception.distance_to_player > config.stalk_freeze_min_distance:
		if _watched_time < config.stalk_stare_time:
			entity.stop()
			entity.face(player.global_position)
			return
		speed *= config.stalk_watched_speed

	if perception.distance_to_player > config.rubberband_distance and _reposition_cooldown <= 0.0:
		_reposition_cooldown = REPOSITION_COOLDOWN
		var spot := world.find_hidden_point(player.global_position, 18.0, 28.0, Vector3.INF)
		if spot != Vector3.INF:
			entity.try_teleport(spot)

	var target := perception.last_seen_position
	var remaining := entity.move_to(target, speed)
	if remaining < 1.0:
		entity.face(target)


func next_state() -> int:
	if entity.van_chase_active:
		if _player_inside_time > VAN_SAFE_TIME:
			return go(S.FLEE, {"vanish": true})
		return NO_CHANGE
	if perception.player_inside:
		return S.OBSERVE
	if perception.can_see_player and perception.distance_to_player < config.stalk_lunge_distance \
			and not perception.player_watching:
		return S.CHARGE
	if _lost_time > config.stalk_lose_time:
		return go(S.SEARCH, {"target": perception.last_seen_position})
	return NO_CHANGE


func can_catch() -> bool:
	return true


func reacts_to_lamp() -> bool:
	return not entity.van_chase_active


func _van_chase_speed(player: Node3D) -> float:
	var sprint: float = player.get("run_speed") if player.get("run_speed") != null else 6.5
	var t := clampf((time - config.van_ramp_delay) / config.van_ramp_time, 0.0, 1.0)
	return sprint * lerpf(config.van_speed_ratio_start, config.van_speed_ratio_max, t)
