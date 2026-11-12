class_name EntityStateObserve
extends EntityState

## The baseline: watching the cabin from the treeline, moving between vantage
## points. Long relocations happen by teleporting, but only out of sight, so
## it seems to be wherever the player isn't looking.
##
## From here it decides what to do next:
##   player outside and seen            -> STALK
##   player outside and heard           -> SEARCH the noise
##   player outside, unseen for a while -> SEARCH roughly where they are
##   player inside and it feels bold    -> APPROACH a window or the door
##   every entry blocked for too long   -> SABOTAGE the fuse box

const S := Entity.State
const ARRIVE_DISTANCE := 1.2

var _spot := Vector3.ZERO
var _watching := false
var _watch_left := 0.0
var _saw_player := false
var _blocked_time := 0.0


func enter(_from: int, _data: Dictionary) -> void:
	brain.target_entry = null
	_blocked_time = 0.0
	_next_spot()


func update(delta: float) -> void:
	if perception.can_see_player:
		_saw_player = true

	if not _watching:
		var remaining := entity.move_to(_spot, config.observe_speed)
		if remaining < ARRIVE_DISTANCE or (entity.nav_agent.is_navigation_finished() and remaining < 3.0):
			_start_watching()
	else:
		entity.stop()
		# Watching from the treeline crouched low.
		entity.crawl()
		var look := perception.last_seen_position if perception.has_fresh_sighting() else world.cabin_center()
		entity.face(look)
		_watch_left -= delta
		if _watch_left <= 0.0:
			if not _saw_player and perception.player_inside:
				entity.confidence.modify(config.impatience_boost)
			_next_spot()

	_update_frustration(delta)


func next_state() -> int:
	if perception.entity_inside:
		return S.HUNT
	if perception.player_outside:
		if perception.can_see_player:
			return S.STALK
		if perception.has_fresh_noise(3.0):
			return go(S.SEARCH, {"target": perception.last_heard_position})
		if perception.unseen_outside_time > config.outside_sense_time:
			var guess := entity.get_player().global_position + _random_offset(config.outside_sense_error)
			return go(S.SEARCH, {"target": guess})
		return NO_CHANGE

	if not entity.can_approach_cabin():
		return NO_CHANGE
	if _blocked_time > config.frustration_time and entity.can_break_planks():
		var box := world.fuse_box()
		if box and box.is_powered():
			return S.SABOTAGE
	if entity.confidence.wants_to_approach():
		# The way in it would rather not be seen at, or, if that's the
		# player's own room, a lure first (EntityWorld.plan_entry).
		var plan := world.plan_entry()
		if plan.has("decoy"):
			return go(S.LURE, plan)
		if plan.has("entry"):
			return go(S.APPROACH, plan)
	return NO_CHANGE


func _next_spot() -> void:
	_watching = false
	_saw_player = false
	# Never wander off from a player it can see; next_state() reacts to them.
	if perception.can_see_player:
		_spot = entity.global_position
		_start_watching()
		return
	var point := world.pick_vantage_point(true)
	if not point:
		_spot = entity.global_position
		_start_watching()
		return
	_spot = world.snap_to_navmesh(point.global_position)
	if Entity._flat_distance(entity.global_position, _spot) > config.hidden_relocate_distance:
		entity.try_teleport(_spot)


func _start_watching() -> void:
	_watching = true
	var bold := entity.confidence.get_confidence() >= config.approach_threshold
	if bold:
		_watch_left = randf_range(config.watch_time_bold_min, config.watch_time_bold_max)
	else:
		_watch_left = randf_range(config.watch_time_min, config.watch_time_max)
	if randf() < 0.3:
		entity.audio.play_voice("murmur")


## Counts time spent wanting to come in with every entry blocked.
func _update_frustration(delta: float) -> void:
	var wants_in := perception.player_inside and entity.can_approach_cabin() \
		and entity.confidence.get_confidence() >= config.approach_threshold
	if wants_in and not world.has_viable_entry():
		_blocked_time += delta
	else:
		_blocked_time = maxf(_blocked_time - delta, 0.0)


static func _random_offset(radius: float) -> Vector3:
	var angle := randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle)) * randf_range(0.0, radius)
