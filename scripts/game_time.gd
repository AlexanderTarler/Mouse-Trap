extends Node

## GameTime - The single source of truth for the day/night cycle.
## Manages a 10-minute (600 second) total cycle: 5 minutes day, 5 minutes night.
## 
## cycle_progress: 0.0 to 1.0
##   0.0 - 0.5 = Day (Sunrise to Sunset)
##   0.5 - 1.0 = Night (Moonrise to Moonset)
##
## The game starts with time frozen (is_time_paused = true) at cycle_progress = 0.25
## (mid-afternoon). Time remains frozen until the Inciting Incident (nest catalyst
## event) unfreezes it and pushes progress toward sunset.

signal time_changed(progress: float)
signal day_started
signal night_started

## Total duration of one full day/night cycle in seconds (10 minutes = 600s)
## For testing, set to a lower value like 60 (1 minute cycle = 30s day + 30s night)
@export var cycle_duration: float = 600.0

## Speed multiplier for testing (press T to toggle 10x speed)
var speed_multiplier: float = 1.0

## Current cycle progress (0.0 to 1.0)
var cycle_progress: float = 0.25

## Whether it is currently day (true) or night (false)
var is_day: bool = true

## Whether the cycle is actively running
var is_running: bool = true

## Whether time is paused (frozen). The game starts paused at mid-afternoon.
## Time is unpaused by the nest catalyst event (Inciting Incident).
var is_time_paused: bool = true

## Internal timer tracking elapsed time
var _elapsed: float = 0.0

## Cached previous phase to detect transitions
var _was_day: bool = true

## Tick accumulator for throttling _process() to 5 Hz (0.2s intervals)
var _tick_timer: float = 0.0


func _ready() -> void:
	# Initialize to mid-afternoon (progress 0.25 = ~3:00 PM)
	cycle_progress = 0.25
	_elapsed = cycle_progress * cycle_duration
	is_day = cycle_progress < 0.5
	_was_day = is_day
	
	# Time starts paused — the player explores in a frozen mid-afternoon state
	is_time_paused = true
	
	# Emit initial state
	time_changed.emit(cycle_progress)
	if is_day:
		day_started.emit()
	else:
		night_started.emit()


func _process(delta: float) -> void:
	# --- THROTTLE OPTIMIZATION ---
	# Time advances at 5 Hz (0.2s intervals). Frame-perfect precision is
	# unnecessary for a 24-hour cycle that spans 24 real minutes.
	_tick_timer += delta
	if _tick_timer < 0.2:
		return
	_tick_timer = 0.0

	if not is_running:
		return
	
	# Time accumulation is wrapped in the pause check.
	# When is_time_paused is true, the clock stays frozen.
	if not is_time_paused:
		# Advance the cycle (apply speed multiplier)
		# Use _tick_timer's accumulated value (0.2s tick interval) instead of this frame's delta
		# to keep time progressing at real-time speed despite the 5Hz throttle.
		_elapsed += 0.2 * speed_multiplier
		cycle_progress = fmod(_elapsed / cycle_duration, 1.0)
	
	# Determine current phase (always evaluated, even when paused,
	# so set_progress() updates propagate correctly)
	is_day = cycle_progress < 0.5
	
	# Check for phase transitions
	if is_day and not _was_day:
		day_started.emit()
		print("GameTime: Day started at progress ", cycle_progress)
	elif not is_day and _was_day:
		night_started.emit()
		print("GameTime: Night started at progress ", cycle_progress)
	
	_was_day = is_day
	
	# Emit time changed signal
	time_changed.emit(cycle_progress)


## Returns the progress within the current phase (0.0 to 1.0).
## During day, this maps 0.0-0.5 to 0.0-1.0.
## During night, this maps 0.5-1.0 to 0.0-1.0.
func get_phase_progress() -> float:
	if is_day:
		return cycle_progress / 0.5
	else:
		return (cycle_progress - 0.5) / 0.5


## Pauses the cycle.
func pause() -> void:
	is_running = false


## Resumes the cycle.
func resume() -> void:
	is_running = true


## Unpauses time, allowing the day/night cycle to advance.
## Called by the nest catalyst event (Inciting Incident).
func unpause_time() -> void:
	is_time_paused = false
	is_running = true
	# Emit immediately so connected HUDs force a visual refresh this frame
	time_changed.emit(cycle_progress)
	print("GameTime: Time unpaused! The cycle is now advancing.")


## Sets the cycle to a specific progress value (0.0 to 1.0).
## Works even when time is paused — used by the nest event to force sunset.
func set_progress(value: float) -> void:
	cycle_progress = clampf(value, 0.0, 1.0)
	_elapsed = cycle_progress * cycle_duration
	is_day = cycle_progress < 0.5
	
	# Emit signals for the new state
	time_changed.emit(cycle_progress)
	if is_day:
		day_started.emit()
	else:
		night_started.emit()
	
	_was_day = is_day


## Resets the cycle to the start of the night phase (progress = 0.5).
## Used by the Game Over restart flow to re-enter the night from scratch.
func reset_to_night_start() -> void:
	set_progress(0.5)