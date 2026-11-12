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
## It never follows them onto the porch: under the porch light (or inside)
## the player is out of its reach, and it waits at the edge of the light.

const S := Entity.State
const REPOSITION_COOLDOWN := 4.0
## The player must be inside this long to end the van chase (so brushing the
## porch or a one-frame room change doesn't end it).
const VAN_SAFE_TIME := 0.5
## How far from the porch light the van chase stops (m, flat).
const PORCH_GUARD_RADIUS := 6.0

var _lost_time := 0.0
var _reposition_cooldown := 0.0
var _player_inside_time := 0.0
var _watched_time := 0.0


func enter(_from: int, _data: Dictionary) -> void:
	_lost_time = 0.0
	_player_inside_time = 0.0
	_watched_time = 0.0
	_reposition_cooldown = REPOSITION_COOLDOWN
	# (The hunting music: EntityAudio.update_hunt_music.)


func exit(_to: int) -> void:
	pass


func update(delta: float) -> void:
	var player := entity.get_player()
	if entity.van_chase_active:
		_player_inside_time = _player_inside_time + delta if perception.player_inside else 0.0
		var hold := _porch_hold_point(player)
		if hold != Vector3.INF:
			if entity.move_to(hold, _van_chase_speed(player)) < 0.6:
				entity.stop()
				entity.face(player.global_position)
			return
		entity.move_to(player.global_position, _van_chase_speed(player))
		return

	_lost_time = 0.0 if perception.can_see_player else _lost_time + delta
	_reposition_cooldown -= delta

	var speed := config.stalk_speed
	_watched_time = _watched_time + delta if perception.player_watching else 0.0
	if config.stalk_freeze_when_watched and perception.player_watching \
			and perception.distance_to_player > config.stalk_freeze_min_distance:
		# Caught being watched: down low, staring back, then crawling closer.
		entity.crawl()
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
			return go(S.FLEE, {VANISH: true})
		return NO_CHANGE
	if perception.player_inside:
		return S.OBSERVE
	if perception.can_see_player and perception.distance_to_player < config.stalk_lunge_distance \
			and not perception.player_watching:
		return S.CHARGE
	if _lost_time > config.stalk_lose_time:
		return go(S.SEARCH, {TARGET: perception.last_seen_position})
	return NO_CHANGE


func can_catch() -> bool:
	return true


func reacts_to_lamp() -> bool:
	return not entity.van_chase_active


## Where to wait when the player is under the porch light or inside: at the
## edge of the light, on the Entity's side. INF when the chase goes on.
func _porch_hold_point(player: Node3D) -> Vector3:
	var pool := _porch_pool()
	if pool == Vector3.INF:
		return Vector3.INF
	var centre := Vector3(pool.x, entity.global_position.y, pool.z)
	var player_flat := Vector3(player.global_position.x, centre.y, player.global_position.z)
	if not perception.player_inside and player_flat.distance_to(centre) > PORCH_GUARD_RADIUS:
		return Vector3.INF
	var away := entity.global_position - centre
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.FORWARD
	return centre + away.normalized() * (PORCH_GUARD_RADIUS + 0.5)


var _porch_centre := Vector3.INF


## The middle of the pool of light the porch light throws (it hangs on the
## wall by the door and shines out): halfway between the lamp and where its
## beam meets the ground. The porch light is the cabin light that's stuck
## on (is_faulty).
func _porch_pool() -> Vector3:
	if _porch_centre != Vector3.INF:
		return _porch_centre
	for light in entity.get_tree().get_nodes_in_group("CabinLights"):
		if light.get("is_faulty") != true or not light is Node3D:
			continue
		var lamp := (light as Node3D).global_position
		_porch_centre = lamp
		var spots := (light as Node).find_children("*", "SpotLight3D", true, false)
		if not spots.is_empty():
			var spot := spots[0] as SpotLight3D
			var dir := -spot.global_transform.basis.z
			var ground := entity.global_position.y
			if dir.y < -0.05:
				var hit := spot.global_position + dir * ((ground - spot.global_position.y) / dir.y)
				_porch_centre = (lamp + hit) * 0.5
		return _porch_centre
	return Vector3.INF


func _van_chase_speed(player: Node3D) -> float:
	var sprint: float = player.get("run_speed") if player.get("run_speed") != null else 6.5
	var t := clampf((time - config.van_ramp_delay) / config.van_ramp_time, 0.0, 1.0)
	return sprint * lerpf(config.van_speed_ratio_start, config.van_speed_ratio_max, t)
