extends Node

## RoutineManager — Night 1 Bedtime Routine tracker.
## A global singleton that tracks the player's progress through the
## mandatory Night 1 bedtime routine:
##
##   Step 0: "Document all 3 nests in the forest."
##   Step 1: "Upload nest data on the computer."
##   Step 2: "Refill Generator" (Outside)
##   Step 3: "Lock Door & Turn Off Lights" (Cabin)
##   Step 4: "Go to Bed" (Ready for the scare)
##
## When Step 4 is reached, the CarAlarmTrigger near the bed will
## fire the car alarm event when the player enters its area.

signal routine_step_changed(step: int, objective_text: String)

## Current routine step (0-4)
var current_step: int = 0

## How many nests the player has documented
var nests_documented: int = 0

## The HUD objective text for each step
const STEP_OBJECTIVES: Dictionary = {
	0: "Document all 3 nests in the forest.",
	1: "Upload nest data on the computer.",
	2: "Grab the jerry can and refill the generator outside.",
	3: "Lock the front door and turn off the cabin lights.",
	4: "Head to the bedroom.",
}

## Whether the routine has been completed (Step 4 reached and car alarm triggered)
var routine_completed: bool = false


func _ready() -> void:
	# Register as an autoload — accessible as /root/RoutineManager
	print("[RoutineManager] Initialized. Current step: ", current_step)


## Called by HasselmusNest when a nest is documented.
## Increments the counter and advances to Step 1 when all 3 nests are done.
func document_nest(nest_id = null) -> void:
	nests_documented += 1
	print("[RoutineManager] Nest ", str(nest_id), " documented! (", nests_documented, "/3)")

	
	if nests_documented >= 3 and current_step == 0:
		advance_step()


## Advances the routine to the next step and updates the HUD objective text.
func advance_step() -> void:
	if current_step >= 4:
		print("[RoutineManager] Routine already at max step (4). Ignoring advance.")
		return
	
	current_step += 1
	var text = STEP_OBJECTIVES.get(current_step, "")
	print("[RoutineManager] Advanced to step ", current_step, ": ", text)
	routine_step_changed.emit(current_step, text)


## Returns the current step's objective text.
func get_current_objective() -> String:
	return STEP_OBJECTIVES.get(current_step, "")


## Called by CarAlarmTrigger when the player enters the bedroom area on Step 4.
## Marks the routine as complete and triggers the car alarm event.
func trigger_car_alarm() -> void:
	if routine_completed:
		print("[RoutineManager] Car alarm already triggered. Ignoring duplicate.")
		return
	
	if current_step != 4:
		print("[RoutineManager] Cannot trigger car alarm — current step is ", current_step, " (expected 4)")
		return
	
	routine_completed = true
	print("[RoutineManager] CRITICAL: Bedtime routine complete! Triggering car alarm event.")
	
	# Update HUD text to tell the player to investigate
	routine_step_changed.emit(current_step, "Investigate the car alarm outside!")
	
	# Trigger the car alarm via NightManager
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		nm.horror_event.emit("car_alarm")
	else:
		print("[RoutineManager] ERROR: NightManager not found!")
