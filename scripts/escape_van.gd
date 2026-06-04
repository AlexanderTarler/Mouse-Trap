extends Node3D
class_name EscapeVan

## EscapeVan — Night 1 narrative interaction.
## Attach this script to the InteractionArea of the EscapeVan scene.
##
## On Night 1, a car alarm triggers ~30-45 seconds into the night.
## The player must go outside and interact with the van to investigate.
## When they do, they discover the ignition is torn out, and the Entity
## makes its first cinematic appearance — triggering the first chase.
##
## Flow:
##   1. NightManager emits horror_event("car_alarm")
##   2. This script hears it, sets alarm_active = true, plays alarm audio
##   3. Player interacts with the van while alarm_active is true
##   4. Script stops the alarm, shows "ignition torn out" message
##   5. Script waits 2 seconds, then calls NightManager.trigger_first_chase()
##   6. Entity spawns at the EntityVanSpawn marker and begins chasing

## Whether the car alarm is currently active (blaring)
var alarm_active: bool = false

## Whether the player has already investigated the van and triggered the first chase.
## Once true, the car alarm can never be re-activated, even on scene reload or
## night restart. This prevents the alarm sequence from playing twice.
var van_investigated: bool = false

## Reference to the AlarmAudio AudioStreamPlayer3D child node
@onready var _alarm_audio: AudioStreamPlayer3D = $AlarmAudio if has_node("AlarmAudio") else null

## Reference to the pulsing red alarm light (OmniLight3D child node)
@onready var _alarm_light: OmniLight3D = $AlarmLight if has_node("AlarmLight") else null

## Reference to the NightManager autoload
var _night_manager: Node = null


func _ready() -> void:
	_connect_night_manager()


## Connects to NightManager's horror_event signal.
## Uses a dedicated method (not _ready) to avoid re-running _ready() on retry.
func _connect_night_manager() -> void:
	_night_manager = get_node_or_null("/root/NightManager")
	if _night_manager:
		_night_manager.horror_event.connect(_on_horror_event)
	else:
		# Retry next frame — NightManager autoload may not be ready yet
		call_deferred("_connect_night_manager")


## Listens for horror events from NightManager.
## When "car_alarm" fires, activates the alarm audio and pulsing light.
## If the player has already investigated the van, the alarm is ignored
## to prevent the sequence from playing twice.
func _on_horror_event(event_name: String) -> void:
	if event_name == "car_alarm":
		if van_investigated:
			print("[EscapeVan] Van already investigated. Ignoring car alarm event.")
			return
		alarm_active = true
		if _alarm_audio:
			_alarm_audio.play()
		if _alarm_light:
			_alarm_light.visible = true
		print("[EscapeVan] Car alarm is blaring!")


## Called by the InteractionManager when the player interacts with the van.
## If the alarm is active, this triggers the first chase sequence.
func interact() -> void:
	if not alarm_active:
		print("[EscapeVan] The van is silent. Nothing to do here.")
		return
	
	# Stop the alarm
	alarm_active = false
	if _alarm_audio:
		_alarm_audio.stop()
	if _alarm_light:
		_alarm_light.visible = false
	
	# Mark the van as investigated so the alarm can never be re-activated
	van_investigated = true
	
	# Show "JOIN HIM" on the objective label for 0.5 seconds, then "FLEE"
	var objective_label = _find_objective_label()
	if objective_label:
		objective_label.text = "JOIN HIM"
		objective_label.modulate = Color(1, 0.2, 0.2, 1)  # Red
		await get_tree().create_timer(0.5).timeout
		objective_label.text = "FLEE"
		objective_label.modulate = Color(1, 0.5, 0, 1)  # Orange
	
	# Show the ignition torn out message via the HUD
	var hud = get_node_or_null("/root/CottageHorror/HUD")
	if not hud:
		hud = get_node_or_null("/root/Main/HUD")
	if hud and hud.has_method("_show_event"):
		hud._show_event("The ignition... it's been completely torn out.")
	else:
		print("[EscapeVan] The ignition... it's been completely torn out.")
	
	# Wait 2 seconds before triggering the first chase.
	# This gives the player a moment to read the HUD message and process
	# the situation before the Entity makes its terrifying arrival.
	await get_tree().create_timer(2.0).timeout
	
	# Trigger the first chase — Entity spawns and begins pursuit
	if _night_manager:
		_night_manager.trigger_first_chase()
	
	print("[EscapeVan] Player investigated the van. First chase initiated!")


## Pulsing red alarm light effect.
## Uses a sine wave based on Time.get_ticks_msec() to smoothly pulse
## the light's energy property up and down like a hazard light.
## The light is visible from very far away (omni_range = 50) so the player
## can see it from the cabin and use it as a beacon to find the van.
func _process(delta: float) -> void:
	if alarm_active and _alarm_light:
		# Set a large range so the light is visible from the cabin
		_alarm_light.omni_range = 50.0
		# Sine wave pulse: oscillates between 1.0 and 5.0 energy for a bright,
		# highly visible flashing effect that can be seen from a distance
		var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		_alarm_light.light_energy = 1.0 + pulse * 4.0


## Finds the objective label on the HUD so we can update it directly.
## The HUD is instanced as "HUD" in cottage_horror.tscn (not "HorrorHUD").
func _find_objective_label() -> Label:
	var hud = get_node_or_null("/root/CottageHorror/HUD")
	if not hud:
		hud = get_node_or_null("/root/Main/HUD")
	if hud and hud.has_node("ObjectiveLabel"):
		return hud.get_node("ObjectiveLabel") as Label
	return null


## Returns the interaction prompt text shown in the HUD.
func get_interact_text() -> String:
	if alarm_active:
		return "[E] Investigate the car"
	return "[E] Examine the van"
