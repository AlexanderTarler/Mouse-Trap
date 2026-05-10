extends Node

## Manages the night progression and horror events.
## Tracks which night the player is on and triggers escalating events.

signal night_started(night: int)
signal night_ended(night: int)
signal horror_event(event_name: String)

## Named constants for horror events to avoid magic strings.
enum EventName {
	DISTANT_SOUND = 0,
	SHADOW_OUTSIDE,
	ENTITY_GLIMPSE,
	DOOR_CREAK,
	ENTITY_INSIDE,
	OBJECT_MOVED,
	FOOTSTEPS,
	ENTITY_APPEARS,
	LIGHTS_FLICKER,
	ENTITY_CHARGE,
	ENTITY_CONSTANT,
	POLTERGEIST,
	FINAL_CONFRONTATION,
}

## Maps EventName enum values to their string representations.
const EVENT_STRINGS: Dictionary = {
	EventName.DISTANT_SOUND: "distant_sound",
	EventName.SHADOW_OUTSIDE: "shadow_outside",
	EventName.ENTITY_GLIMPSE: "entity_glimpse",
	EventName.DOOR_CREAK: "door_creak",
	EventName.ENTITY_INSIDE: "entity_inside",
	EventName.OBJECT_MOVED: "object_moved",
	EventName.FOOTSTEPS: "footsteps",
	EventName.ENTITY_APPEARS: "entity_appears",
	EventName.LIGHTS_FLICKER: "lights_flicker",
	EventName.ENTITY_CHARGE: "entity_charge",
	EventName.ENTITY_CONSTANT: "entity_constant",
	EventName.POLTERGEIST: "poltergeist",
	EventName.FINAL_CONFRONTATION: "final_confrontation",
}

## Current night (1-5)
var current_night: int = 1

## Total nights to survive
var total_nights: int = 5

## Time of night in hours (0.0 = start, 24.0 = end)
var night_progress: float = 0.0

## Night duration in real seconds
var night_duration: float = 120.0  # 2 minutes per night for testing

## Whether the current night is active
var is_night_active: bool = false

## Events that have been triggered this night
var _triggered_events: Array[String] = []

## Timer for night progression
var _night_timer: float = 0.0

func _ready() -> void:
	# Delay start to ensure all autoloads are initialized
	await get_tree().process_frame
	start_night(1)

func _process(delta: float) -> void:
	if not is_night_active:
		return
	
	_night_timer += delta
	night_progress = (_night_timer / night_duration) * 24.0
	
	# Check for time-based events
	_check_time_events()
	
	# Check if night is over
	if _night_timer >= night_duration:
		end_current_night()

## Starts a specific night.
func start_night(night: int) -> void:
	current_night = night
	_night_timer = 0.0
	night_progress = 0.0
	_triggered_events.clear()
	is_night_active = true
	night_started.emit(night)
	
	print("Night %d has begun..." % night)

## Ends the current night and starts the next one.
func end_current_night() -> void:
	is_night_active = false
	night_ended.emit(current_night)
	
	print("Night %d has ended!" % current_night)
	
	if current_night < total_nights:
		# Start next night after a brief pause
		await get_tree().create_timer(2.0).timeout
		start_night(current_night + 1)
	else:
		print("All nights survived! Game over.")

## Checks for time-based horror events.
func _check_time_events() -> void:
	var hour = night_progress
	
	match current_night:
		1:
			# Night 1: Subtle events
			if hour > 2.0 and not "distant_sound" in _triggered_events:
				_trigger_event("distant_sound")
			if hour > 6.0 and not "shadow_outside" in _triggered_events:
				_trigger_event("shadow_outside")
		
		2:
			# Night 2: Entity appears briefly
			if hour > 3.0 and not "entity_glimpse" in _triggered_events:
				_trigger_event("entity_glimpse")
			if hour > 7.0 and not "door_creak" in _triggered_events:
				_trigger_event("door_creak")
		
		3:
			# Night 3: Entity inside
			if hour > 2.0 and not "entity_inside" in _triggered_events:
				_trigger_event("entity_inside")
			if hour > 5.0 and not "object_moved" in _triggered_events:
				_trigger_event("object_moved")
			if hour > 8.0 and not "footsteps" in _triggered_events:
				_trigger_event("footsteps")
		
		4:
			# Night 4: Aggressive
			if hour > 1.0 and not "entity_appears" in _triggered_events:
				_trigger_event("entity_appears")
			if hour > 4.0 and not "lights_flicker" in _triggered_events:
				_trigger_event("lights_flicker")
			if hour > 7.0 and not "entity_charge" in _triggered_events:
				_trigger_event("entity_charge")
		
		5:
			# Night 5: Final night - constant activity
			if hour > 1.0 and not "entity_constant" in _triggered_events:
				_trigger_event("entity_constant")
			if hour > 4.0 and not "poltergeist" in _triggered_events:
				_trigger_event("poltergeist")
			if hour > 8.0 and not "final_confrontation" in _triggered_events:
				_trigger_event("final_confrontation")

## Triggers a horror event.
func _trigger_event(event_name: String) -> void:
	_triggered_events.append(event_name)
	horror_event.emit(event_name)
	print("Horror event: %s" % event_name)

## Returns the current night's intensity (0.0 to 1.0).
func get_intensity() -> float:
	var night_factor = float(current_night) / float(total_nights)
	var time_factor = night_progress / 24.0
	return min(1.0, night_factor * 0.6 + time_factor * 0.4)
