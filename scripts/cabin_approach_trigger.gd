extends Area3D

## CabinApproachTrigger — Detects when the player walks near the cabin.
## When the player enters this trigger zone, it notifies RoutineManager
## that the player has approached the cabin, which updates the HUD
## objective from "Go to the cabin." to "Go inside the cabin."
##
## This trigger is placed just outside the cabin's front door area.
## It fires once and disables itself to prevent repeated triggers.

## Whether this trigger has already fired.
var _triggered: bool = false


func _ready() -> void:
	# Connect the body_entered signal
	body_entered.connect(_on_body_entered)
	
	# Set a descriptive name for debugging
	name = "CabinApproachTrigger"


## Called when a body enters the trigger zone.
## Checks if the body is the player and if so, notifies RoutineManager.
func _on_body_entered(body: Node) -> void:
	if _triggered:
		return
	
	# Check if the entering body is the player
	if body.is_in_group("player"):
		_triggered = true
		
		# Notify RoutineManager
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_cabin_approached"):
			rm.on_cabin_approached()
			print("[CabinApproachTrigger] Player approached the cabin! Objective updated.")
		else:
			print("[CabinApproachTrigger] RoutineManager not found or missing on_cabin_approached().")
		
		# Disable the trigger to prevent re-triggering
		monitoring = false
		monitorable = false
