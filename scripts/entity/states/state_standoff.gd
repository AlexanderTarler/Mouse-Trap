class_name EntityStateStandoff
extends EntityState

## Held by the flashlight.
##   Overcharged beam: it writhes in the light; after
##   config.overcharge_repel_time it flees.
##   Standard beam (both outside): it freezes and stares back while stare
##   pressure builds (perception.stare_pressure). When it is full it winds up:
##   crouches, growls, its eyes flare, for config.charge_windup_time. Look
##   away in time and it backs off; overcharge it and it flees; hold the beam
##   and it charges.
## When the beam is gone it backs out of the light, facing the player, then
## resumes what it was doing. Afterwards the brain won't let a standard beam
## freeze it again for config.standoff_cooldown.

const S := Entity.State
const RESUMABLE := [S.OBSERVE, S.STALK, S.SEARCH, S.APPROACH, S.HUNT]
const WINDUP_GLOW := 6.0

enum Phase { HELD, WINDUP, BACK_OFF }

var _resume_state := S.OBSERVE
var _phase := Phase.HELD
var _phase_time := 0.0
var _lost_time := 0.0
var _screamed := false
var _retreat_target := Vector3.ZERO


func enter(from: int, _data: Dictionary) -> void:
	_resume_state = from
	_lost_time = 0.0
	_screamed = false
	_set_phase(Phase.HELD)


func exit(_to: int) -> void:
	entity.set_eye_glow(1.0)
	brain.standoff_cooldown = config.standoff_cooldown


func update(delta: float) -> void:
	_phase_time += delta
	_lost_time = 0.0 if perception.illuminated else _lost_time + delta
	entity.face(entity.get_player().global_position)
	match _phase:
		Phase.HELD:
			entity.stop()
			var writhing := perception.overcharged or perception.overcharge_time > 0.0
			entity.play_anim(&"entity_in_light" if writhing else &"Idle")
			if writhing and not _screamed:
				_screamed = true
				entity.audio.play_scream()
		Phase.WINDUP:
			entity.stop()
			entity.play_anim(&"AttackWindow")
			# Eyes flare up over the wind-up.
			entity.set_eye_glow(lerpf(1.0, WINDUP_GLOW, clampf(_phase_time / config.charge_windup_time, 0.0, 1.0)))
		Phase.BACK_OFF:
			entity.move_to(_retreat_target, config.flee_speed * 0.5)


func next_state() -> int:
	# The overcharged beam always wins, in any phase.
	if perception.overcharge_time >= config.overcharge_repel_time:
		return S.FLEE
	if perception.overcharged and perception.entity_inside != perception.player_inside:
		return S.FLEE
	if _phase == Phase.WINDUP and perception.overcharged:
		return S.FLEE

	var both_outside := not perception.entity_inside and not perception.player_inside
	match _phase:
		Phase.HELD:
			if both_outside and perception.illuminated and not perception.overcharged \
					and perception.stare_pressure >= 1.0:
				_set_phase(Phase.WINDUP)
				entity.audio.play_voice("angry", true)
				entity.audio.play_growl()
			elif _lost_time > config.standoff_release_time:
				_start_back_off()
		Phase.WINDUP:
			if _lost_time > config.windup_release_time:
				# The player looked away in time.
				entity.audio.play_grunt(0.8)
				_start_back_off()
			elif _phase_time >= config.charge_windup_time:
				perception.stare_pressure = 0.0
				return S.CHARGE
		Phase.BACK_OFF:
			var arrived := Entity._flat_distance(entity.global_position, _retreat_target) < 0.8
			if arrived or _phase_time >= config.standoff_retreat_time:
				if _resume_state in RESUMABLE:
					return _resume_state
				return S.HUNT if perception.entity_inside else S.OBSERVE
	return NO_CHANGE


func _set_phase(phase: Phase) -> void:
	_phase = phase
	_phase_time = 0.0
	if phase != Phase.WINDUP:
		entity.set_eye_glow(1.0)


## Out of the light: straight away from the player, onto the navmesh.
func _start_back_off() -> void:
	var away := entity.global_position - entity.get_player().global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = -entity.global_transform.basis.z
	var target := entity.global_position + away.normalized() * config.standoff_retreat_distance
	_retreat_target = world.snap_to_navmesh(target)
	_set_phase(Phase.BACK_OFF)


## True while it is crouched, about to charge (the player can still stop it).
func is_winding_up() -> bool:
	return _phase == Phase.WINDUP


func reacts_to_flashlight() -> bool:
	return false


func reacts_to_lamp() -> bool:
	return false
