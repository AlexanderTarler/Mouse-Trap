extends Area3D
class_name CarAlarmTrigger

## CarAlarmTrigger — Bedroom area trigger for Night 1.
## Place this Area3D near the bed in the cabin's bedroom.
## When the player enters this area AND RoutineManager.current_step == 4,
## it triggers the car alarm event and disables itself.
##
## This ensures the player must complete the full bedtime routine
## (nests → computer → generator → lock door + lights off → go to bed)
## before the car alarm narrative event fires.

## Reference to the RoutineManager autoload
var _routine_manager: Node = null

## Local flag to prevent duplicate fires even before set_deferred takes effect
var _has_fired: bool = false


func _ready() -> void:
	# Ensure this Area3D can detect the player
	collision_layer = 0  # Doesn't need to be in a collision layer for detection
	collision_mask = 1   # Detects bodies on layer 1 (player is on layer 1)
	
	# Connect the body_entered signal
	body_entered.connect(_on_body_entered)
	
	# Find RoutineManager
	_routine_manager = get_node_or_null("/root/RoutineManager")
	if not _routine_manager:
		print("[CarAlarmTrigger] ERROR: RoutineManager not found at /root/RoutineManager!")
	else:
		print("[CarAlarmTrigger] Ready. Monitoring for player entry.")


func _on_body_entered(body: Node3D) -> void:
	# Prevent duplicate fires — this flag is checked synchronously before
	# set_deferred("monitoring", false) takes effect next frame.
	if _has_fired:
		return
	
	print("[DEBUG] Body entered CarAlarmTrigger: ", body.name)
	
	# Check if the body is the Player
	if not body.is_in_group("player"):
		print("[DEBUG] Body is not the player. Ignoring.")
		return
	
	if not _routine_manager:
		print("[DEBUG] RoutineManager not available. Ignoring.")
		return
	
	# Check if the van has already been investigated — if so, the car alarm
	# sequence has already played and should never trigger again.
	var escape_van = get_node_or_null("/root/CottageHorror/EscapeVan")
	if not escape_van:
		escape_van = get_node_or_null("/root/Main/EscapeVan")
	if escape_van and escape_van.has_method("get_interact_text") and escape_van.van_investigated:
		print("[CarAlarmTrigger] Van already investigated. Ignoring trigger.")
		return
	
	var step = _routine_manager.current_step
	print("[DEBUG] Current routine step is: ", step, " (Expected 4)")
	
	if step != 4:
		print("[DEBUG] Trigger ignored. Current routine step is: ", step, " (Expected 4)")
		return
	
	_has_fired = true
	print("[DEBUG] CRITICAL: Bedtime routine complete! Triggering car alarm event.")
	
	# Trigger the car alarm via RoutineManager
	_routine_manager.trigger_car_alarm()
	
	# Safely disable this trigger so it cannot fire a second time
	set_deferred("monitoring", false)
	print("[CarAlarmTrigger] Trigger disabled to prevent duplicate fires.")
