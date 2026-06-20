extends Node3D
class_name EscapeVan

## EscapeVan — Night 1 narrative interaction + Endgame repair objective.
##
## PHASE 1 — NIGHT 1 ALARM:
## On Night 1, a car alarm triggers ~30-45 seconds into the night.
## The player must go outside and interact with the van to investigate.
## When they do, they discover the ignition is torn out, and the Entity
## makes its first cinematic appearance — triggering the first chase.
##
## PHASE 2 — REPAIR & ESCAPE:
## After the alarm sequence, the van becomes a repair objective. The player
## must scavenge 3 car components (Battery, Radiator, Ignition Wiring) from
## scrap heaps around the map. Once all 3 are installed, the van is repaired
## and the player can trigger the ending sequence.
##
## CONSTRAINTS:
## - Van interaction is BLOCKED while the alarm is active (must investigate first).
## - Van interaction is BLOCKED if the first chase hasn't been triggered yet.
## - Once repaired, interacting triggers the ending (Good or Mediocre based on
##   whether the TotemAnchor was destroyed).

# ─── REPAIR STATE ──────────────────────────────────────────

## Total car components needed to repair the van.
const COMPONENTS_NEEDED: int = 3

## How many components the player has installed so far.
var components_collected: int = 0

## Whether the van is fully repaired and ready for escape.
var is_repaired: bool = false

# ─── ALARM STATE ───────────────────────────────────────────

## Whether the car alarm is currently active (blaring).
var alarm_active: bool = false

## Whether the player has already investigated the van and triggered the first chase.
## Once true, the car alarm can never be re-activated, even on scene reload or
## night restart. This prevents the alarm sequence from playing twice.
var van_investigated: bool = false

# ─── NODE REFERENCES ───────────────────────────────────────

## Reference to the AlarmAudio AudioStreamPlayer3D child node.
@onready var _alarm_audio: AudioStreamPlayer3D = $AlarmAudio if has_node("AlarmAudio") else null

## Reference to the pulsing red alarm light (OmniLight3D child node).
@onready var _alarm_light: OmniLight3D = $AlarmLight if has_node("AlarmLight") else null

## Reference to the repair success sound player.
@onready var _repair_audio: AudioStreamPlayer3D = $RepairAudio if has_node("RepairAudio") else null

## Reference to the NightManager autoload.
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


# ─── HORROR EVENTS ─────────────────────────────────────────

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


# ─── INTERACTION ───────────────────────────────────────────

## Called by the InteractionManager when the player interacts with the van.
##
## BEHAVIOR:
## - If alarm is active → triggers the first chase sequence (Night 1 narrative).
## - If repaired → triggers the ending sequence.
## - If not repaired and player has a car part in inventory → installs it.
## - Otherwise → shows a contextual message.
func interact() -> void:
	# ─── PRIORITY 1: Alarm is active → trigger first chase ──────────
	if alarm_active:
		_trigger_first_chase()
		return
	
	# ─── PRIORITY 2: Van is repaired → trigger ending ───────────────
	if is_repaired:
		_trigger_ending()
		return
	
	# ─── PRIORITY 3: Not repaired → try to install a component ──────
	_try_install_component()


## Tries to install a car component from the player's inventory.
## Scans the inventory for an item of type CAR_PART. If found, removes it
## and increments the component count. If all 3 are installed, marks the
## van as repaired.
func _try_install_component() -> void:
	var inventory = get_node_or_null("/root/Inventory")
	if not inventory:
		print("[EscapeVan] ERROR: Inventory autoload not found!")
		return
	
	# Scan inventory for a car part (ItemType.CAR_PART = 7)
	var car_part_index = -1
	var car_part_name = ""
	for i in range(inventory.items.size()):
		var item = inventory.items[i]
		if item and item.item_type == 7:
			car_part_index = i
			car_part_name = item.item_name
			break
	
	if car_part_index < 0:
		_show_hud_message("You need car parts to repair the van. Check the scrap heaps.")
		print("[EscapeVan] No car parts in inventory.")
		return
	
	# Remove the car part from inventory
	inventory.remove_at(car_part_index)
	components_collected += 1
	
	print("[EscapeVan] Component installed: %s (%d/%d)" % [car_part_name, components_collected, COMPONENTS_NEEDED])
	_show_hud_message("%s installed! (%d/%d parts)" % [car_part_name, components_collected, COMPONENTS_NEEDED])
	
	# Check if all components are installed
	if components_collected >= COMPONENTS_NEEDED:
		_repair_complete()
	else:
		# Play a "part installed" sound if available
		if _repair_audio:
			_repair_audio.pitch_scale = 1.0
			_repair_audio.play()


## Called when all 3 components have been installed.
## Marks the van as repaired, plays a success sound, and updates the prompt.
func _repair_complete() -> void:
	is_repaired = true
	
	print("[EscapeVan] ⚡ VAN REPAIRED! All %d components installed." % COMPONENTS_NEEDED)
	_show_hud_message("The van is repaired! Get in and escape!")
	
	# Play a triumphant repair sound
	if _repair_audio:
		_repair_audio.pitch_scale = 1.5  # Higher pitch = success tone
		_repair_audio.play()


## Triggers the ending sequence via EndgameManager.
## Checks if the TotemAnchor was destroyed to decide between Good and Mediocre.
func _trigger_ending() -> void:
	print("[EscapeVan] Player is escaping! Triggering ending sequence.")
	
	var endgame = get_node_or_null("/root/EndgameManager")
	if not endgame:
		print("[EscapeVan] ERROR: EndgameManager not found!")
		return
	
	# Check if the TotemAnchor was destroyed by looking for its is_purged property
	var totem_destroyed = false
	var totem = get_tree().get_first_node_in_group("interactable")
	if totem and "is_purged" in totem:
		totem_destroyed = totem.is_purged
	
	endgame.start_ending_sequence(totem_destroyed)


## Triggers the first chase sequence (Night 1 narrative).
## Stops the alarm, shows the "ignition torn out" message, unlocks sprint,
## and calls NightManager.trigger_first_chase().
func _trigger_first_chase() -> void:
	# Stop the alarm
	alarm_active = false
	if _alarm_audio:
		_alarm_audio.stop()
	if _alarm_light:
		_alarm_light.visible = false
	
	# Mark the van as investigated so the alarm can never be re-activated
	van_investigated = true
	
	# ─── UNLOCK SPRINT ─────────────────────────────────────────────
	# If the player started without sprint (start_with_sprint = false),
	# investigating the car alarm unlocks the ability to sprint.
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("unlock_sprint"):
		player.unlock_sprint()
	
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
	
	# Wait 2 seconds before triggering the first chase
	await get_tree().create_timer(2.0).timeout
	
	# Trigger the first chase — Entity spawns and begins pursuit
	if _night_manager:
		_night_manager.trigger_first_chase()
	
	print("[EscapeVan] Player investigated the van. First chase initiated!")


# ─── PROCESS ───────────────────────────────────────────────

## Pulsing red alarm light effect.
## Uses a sine wave based on Time.get_ticks_msec() to smoothly pulse
## the light's energy property up and down like a hazard light.
func _process(delta: float) -> void:
	if alarm_active and _alarm_light:
		_alarm_light.omni_range = 50.0
		var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		_alarm_light.light_energy = 1.0 + pulse * 4.0


# ─── UI HELPERS ────────────────────────────────────────────

## Finds the objective label on the HUD so we can update it directly.
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
	if is_repaired:
		return "[E] Escape"
	if van_investigated:
		return "[E] Repair the van (%d/3 parts)" % components_collected
	return "[E] Examine the van"


## Pushes a text message to the HUD overlay.
func _show_hud_message(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(msg)
	else:
		print("[EscapeVan HUD]: ", msg)
