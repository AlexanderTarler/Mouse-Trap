class_name EntityConfidence
extends Node

## How bold the Entity is (0-100). It only comes to the cabin at or above
## config.approach_threshold.
##
## Confidence drifts toward a RESTING value in both directions. The resting
## value rises each night and over the course of a night, so pressure builds.
## Events push it away from rest (impatience up, being repelled down) and it
## drifts back.
##
## After being driven off it RELAXES for config.relax_time: it won't
## approach, which gives the player a breather before the next build-up.
## That build -> peak -> relief rhythm is what makes the peaks land.
##
## Updated by the brain, so it never changes while the game is paused or the
## Entity is dormant.

signal confidence_changed(value: float)

var entity: Entity
var config: EntityConfig

var confidence := 0.0:
	set(value):
		value = clampf(value, 0.0, 100.0)
		if value != confidence:
			confidence = value
			confidence_changed.emit(confidence)

var resting := 0.0
var _relax_timer := 0.0


func setup(owner_entity: Entity) -> void:
	entity = owner_entity
	config = owner_entity.config
	confidence = config.confidence_base


func update(delta: float) -> void:
	resting = _resting_value()
	if _relax_timer > 0.0:
		_relax_timer -= delta
	confidence = move_toward(confidence, resting, config.confidence_drift * delta)


func _resting_value() -> float:
	var nm := entity.get_night_manager()
	var night := entity.current_night()
	var progress: float = nm.get("night_progress") if nm and nm.get("night_progress") != null else 0.0
	return config.confidence_base \
		+ maxi(night - 1, 0) * config.confidence_per_night \
		+ progress * config.confidence_night_progress


func get_confidence() -> float:
	return confidence


func set_confidence(value: float) -> void:
	confidence = value


func modify(amount: float, _source: String = "") -> void:
	confidence += amount


## Bold enough to come to the cabin, and not recovering from being repelled.
func wants_to_approach() -> bool:
	return confidence >= config.approach_threshold and not is_relaxing()


func is_relaxing() -> bool:
	return _relax_timer > 0.0


## Driven off: lose confidence and hold back for config.relax_time.
func repelled() -> void:
	confidence -= config.repel_penalty
	_relax_timer = config.relax_time


## Called by NightManager on restart/new day.
func reset() -> void:
	confidence = config.confidence_base
	_relax_timer = 0.0
