extends Node

## Global game time autoload singleton.
## Manages a day/night cycle where each day and each night lasts 5 minutes.
## A full cycle (day + night) = 10 minutes.

signal time_changed(progress: float, is_day: bool)
signal day_started()
signal night_started()

## Current cycle progress (0.0 to 1.0 for the current phase)
var cycle_progress: float = 0.0

## Whether it's currently daytime
var is_day: bool = true

## Duration of each phase in seconds (5 minutes = 300 seconds)
@export var phase_duration: float = 300.0

## Total elapsed time
var elapsed_time: float = 0.0

## How many full cycles have completed
var cycles_completed: int = 0


func _process(delta: float) -> void:
	elapsed_time += delta
	cycle_progress += delta / phase_duration
	
	if cycle_progress >= 1.0:
		cycle_progress = 0.0
		if is_day:
			is_day = false
			night_started.emit()
			print("Night has fallen...")
		else:
			is_day = true
			cycles_completed += 1
			day_started.emit()
			print("Day has broken! Cycle %d completed." % cycles_completed)
	
	time_changed.emit(cycle_progress, is_day)
	
	# Debug: print progress every ~30 seconds of game time
	if int(elapsed_time) % 30 == 0 and int(elapsed_time - delta) % 30 != 0:
		print("GameTime: %s, progress=%.2f, elapsed=%.0fs" % [get_phase_string(), cycle_progress, elapsed_time])


## Returns a string like "Day" or "Night" with progress percentage.
func get_phase_string() -> String:
	var phase_name = "Day" if is_day else "Night"
	var percent = int(cycle_progress * 100)
	return "%s %d%%" % [phase_name, percent]


## Returns the time of day as a formatted string (for display).
func get_time_string() -> String:
	var total_seconds = int(elapsed_time)
	var minutes = int(total_seconds / 60)
	var seconds = total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]
