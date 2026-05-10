extends Node

## Global game time autoload singleton.
## Tracks in-game time where 1 real second = 1 game minute.
## A full day cycle (24 hours) = 24 real minutes.

signal time_changed(hour: float)
signal day_phase_changed(phase: DayPhase)

enum DayPhase { MORNING, AFTERNOON, EVENING, NIGHT }

## Current in-game hour (0.0 to 24.0)
var current_hour: float = 8.0  # Start at 8 AM

## How many real seconds equal one game minute
@export var real_seconds_per_game_minute: float = 1.0

var _last_phase: DayPhase = DayPhase.MORNING

func _process(delta: float) -> void:
	var time_delta = (delta / real_seconds_per_game_minute) / 60.0  # Convert to hours
	current_hour = fmod(current_hour + time_delta, 24.0)
	
	# Emit signals
	time_changed.emit(current_hour)
	
	var phase = get_day_phase()
	if phase != _last_phase:
		_last_phase = phase
		day_phase_changed.emit(phase)

## Returns the current day phase based on the hour.
func get_day_phase() -> DayPhase:
	if current_hour >= 6.0 and current_hour < 12.0:
		return DayPhase.MORNING
	elif current_hour >= 12.0 and current_hour < 18.0:
		return DayPhase.AFTERNOON
	elif current_hour >= 18.0 and current_hour < 22.0:
		return DayPhase.EVENING
	else:
		return DayPhase.NIGHT

## Returns a formatted time string like "08:00 AM"
func get_time_string() -> String:
	var total_minutes = int(current_hour * 60)
	var hours = int(total_minutes / 60.0)
	var minutes = total_minutes % 60
	var am_pm = "AM" if hours < 12 else "PM"
	var display_hour = hours if hours <= 12 else hours - 12
	if display_hour == 0:
		display_hour = 12
	return "%02d:%02d %s" % [display_hour, minutes, am_pm]
