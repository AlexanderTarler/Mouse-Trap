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

## The exact part names required for a complete repair.
const REQUIRED_PARTS: Array[String] = ["Car Battery", "Radiator", "Ignition Wiring"]

## How many components the player has installed so far.
var components_collected: int = 0

## Tracks which part names have already been installed.
## Keys are item_name strings (e.g., "Car Battery"), values are bool.
var _installed_parts: Dictionary = {}

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
		
		# ─── FORCE TIME TO DEEP NIGHT (cycle_progress = 0.9) ──────
		# Night 2.2 van sequence: 0.9 = 4 minutes into the 5-min night
		# phase (1 min until dawn). Time is paused so the world stays
		# in this dark state until the player investigates the van.
		var gt = get_node_or_null("/root/GameTime")
		if gt:
			gt.cycle_progress = 0.9
			gt._elapsed = gt.cycle_progress * gt.cycle_duration
			gt.is_day = false
			gt.is_time_paused = true
			gt.time_changed.emit(0.9)
			print("[EscapeVan] GameTime forced to cycle_progress=0.9 (4 min into night) and paused during van sequence.")
		
		# ─── DARKEN ENVIRONMENT ───────────────────────────────────
		_darken_environment_for_van_sequence()
		
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
## Scans the inventory for items of type CAR_PART. For each one found,
## checks if that specific part type has already been installed.
## Rejects duplicates and installs only unique parts.
func _try_install_component() -> void:
	var inventory = get_node_or_null("/root/Inventory")
	if not inventory:
		print("[EscapeVan] ERROR: Inventory autoload not found!")
		return
	
	# Scan inventory for any car part (ItemType.CAR_PART = 7)
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
	
	# ─── UNIQUE PART VALIDATION ──────────────────────────────────
	# Reject duplicate installs — each part type can only be installed once.
	if _installed_parts.has(car_part_name):
		_show_hud_message("I already installed a %s. I need different parts." % car_part_name)
		print("[EscapeVan] DUPLICATE REJECTED: %s is already installed." % car_part_name)
		return
	
	# Validate that this is actually one of the 3 required parts.
	if car_part_name not in REQUIRED_PARTS:
		_show_hud_message("This doesn't look like it belongs in the van...")
		print("[EscapeVan] UNKNOWN PART REJECTED: '%s' is not a required van component." % car_part_name)
		return
	
	# Remove the car part from inventory and mark it as installed
	inventory.remove_at(car_part_index)
	_installed_parts[car_part_name] = true
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
	
	# Check if the TotemAnchor was destroyed by looking for nodes in the
	# dedicated "totem_anchor" group. The TotemAnchor adds itself to this
	# group in _ready(), ensuring a reliable lookup.
	var totem_destroyed = false
	var totems = get_tree().get_nodes_in_group("totem_anchor")
	for totem in totems:
		if "is_purged" in totem and totem.is_purged:
			totem_destroyed = true
			break
	
	endgame.start_ending_sequence(totem_destroyed)


## Triggers the first chase sequence (Night 1 narrative).
## Stops the alarm, shows the "ignition torn out" message, unlocks sprint,
## teleports the Entity to the van area in STALK state, and calls
## NightManager.trigger_first_chase().
func _trigger_first_chase() -> void:
	# Stop the alarm
	alarm_active = false
	if _alarm_audio:
		_alarm_audio.stop()
	if _alarm_light:
		_alarm_light.visible = false
	
	# Mark the van as investigated so the alarm can never be re-activated
	van_investigated = true
	
	# ─── VAN SEQUENCE FLAG ────────────────────────────────────────
	# Do NOT clear is_van_sequence_active here! The Entity needs this
	# flag to remain true so the Director's Tier 2 forces STALK state
	# throughout the entire outdoor chase. The flag is cleared when the
	# Entity enters INDOOR_SEARCH (entity_ai.gd), meaning the player
	# successfully escaped back inside the cabin.
	
	# ─── FORCE NIGHT 2.2 TIME & LIGHTING ──────────────────────
	# The van sequence is over but we must stay in deep night at
	# cycle_progress=0.9 (4 min into the 5-min night phase).
	# Do NOT reset the night or push time back to midnight.
	# 1. Force GameTime to deep night
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		gt.cycle_progress = 0.9
		gt._elapsed = gt.cycle_progress * gt.cycle_duration
		gt.is_day = false
		gt.time_changed.emit(0.9)
		print("[EscapeVan] Time re-forced to cycle_progress=0.9 (4 min into night) for Night 2.2.")
	
	# 2. RESTORE ENVIRONMENT — but do it BEFORE unpausing time to prevent
	#    the "bright flash" caused by a stale skybox evaluation.
	_restore_environment_lighting()
	
	# 3. NOW unpause time so the clock ticks from 04:00
	if gt:
		gt.is_time_paused = false
		gt.is_running = true
		print("[EscapeVan] GameTime unpaused. Night 2.2 clock starts from 04:00.")
	
	# ─── UNLOCK SPRINT ─────────────────────────────────────────────
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
	
	# ─── TELEPORT ENTITY TO VAN + FORCE STALK ──────────────────────
	_teleport_entity_to_van()
	
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


## ─── ENVIRONMENT & ENTITY HELPERS ──────────────────────────

## Forces the EnvironmentController to unnaturally dark levels during the
## van alarm sequence so the player is fully disoriented when they step
## outside. Delegates to EnvironmentController.force_true_night() for
## consistent, centralized darkness control.
func _darken_environment_for_van_sequence() -> void:
	var ec = get_node_or_null("/root/CottageHorror/EnvironmentController")
	if not ec:
		ec = get_node_or_null("/root/Main/EnvironmentController")
	if not ec:
		print("[EscapeVan] EnvironmentController not found — skipping darkness override.")
		return
	
	# Delegate to EnvironmentController's force_true_night() for proper
	# centralized darkness control (solid black background, zero ambient, etc.)
	if ec.has_method("force_true_night"):
		ec.force_true_night()
		print("[EscapeVan] Environment darkened for van sequence via force_true_night().")
	else:
		# Fallback: manual override for older EnvironmentController versions
		if ec.world_environment and ec.world_environment.environment:
			ec.world_environment.environment.ambient_light_energy = 0.02
			ec.world_environment.environment.ambient_light_color = Color(0.01, 0.01, 0.03)
		if ec.sun:
			ec.sun.light_energy = 0.0
		if ec.moon:
			ec.moon.light_energy = 0.03
		print("[EscapeVan] Environment darkened via fallback manual override.")


## Restores the EnvironmentController to normal day/night cycle behavior.
## Called when the player investigates the van (end of van sequence).
func _restore_environment_lighting() -> void:
	var ec = get_node_or_null("/root/CottageHorror/EnvironmentController")
	if not ec:
		ec = get_node_or_null("/root/Main/EnvironmentController")
	if not ec:
		return
	
	# Use EnvironmentController's restore_cycle() to properly restore
	# background_mode to BG_SKY and recalculate all lighting values.
	if ec.has_method("restore_cycle"):
		ec.restore_cycle()
	elif ec.has_method("_apply_cycle"):
		ec._apply_cycle()
	
	print("[EscapeVan] Environment lighting restored to normal cycle.")


## Finds the Entity in the scene tree, teleports it to the EntityVanSpawn
## marker, and forces it into the STALK state so it immediately begins
## pursuing the player through the forest.
func _teleport_entity_to_van() -> void:
	# 1. Find the Entity
	var entity = get_tree().get_first_node_in_group("entity")
	if not entity:
		print("[EscapeVan] ERROR: Entity not found in scene! Cannot teleport.")
		return
	
	# 2. Find the EntityVanSpawn marker
	var spawn_marker: Marker3D = null
	var scene_root = get_tree().current_scene
	if scene_root:
		spawn_marker = scene_root.get_node_or_null("EntityVanSpawn") as Marker3D
		if not spawn_marker:
			# Recursive fallback
			spawn_marker = _find_marker_recursive(scene_root, "EntityVanSpawn")
	
	if not spawn_marker:
		print("[EscapeVan] WARNING: EntityVanSpawn marker not found! Teleporting Entity to van position.")
		entity.global_transform.origin = global_transform.origin + Vector3(5, 0, -10)
	else:
		entity.global_position = spawn_marker.global_position
		print("[EscapeVan] Entity teleported to EntityVanSpawn: %s" % spawn_marker.global_position)
	
	# 3. Force STALK state
	if entity.has_method("request_state"):
		entity.request_state(EntityAI.State.STALK)
		print("[EscapeVan] Entity forced into STALK state.")
	elif entity.has_method("change_state"):
		entity.change_state("STALK")
		print("[EscapeVan] Entity.change_state('STALK') called.")
	else:
		# Fallback: set state enum directly
		if "_state" in entity:
			entity._state = 2  # STALK = 2
		print("[EscapeVan] Entity state forced to STALK via direct property.")
	
	# 4. Ensure outdoors flag — prevents AI from pathfinding into cabin
	if "thinks_player_is_inside" in entity:
		entity.thinks_player_is_inside = false
		print("[EscapeVan] Entity.thinks_player_is_inside = false.")
	
	# 5. ─── PERSISTENCE LOCK: Force STALK-only for 5 seconds ─────────
	# The Entity must stay in STALK state and cannot flee or observe for
	# the first 5 seconds after spawning at the van. This ensures the
	# Entity immediately pursues the player rather than retreating to
	# the treeline. The lock timestamp is checked by the Director.
	entity.set_meta("stalk_lock_until_ms", Time.get_ticks_msec() + 5000)
	print("[EscapeVan] Entity STALK lock armed for 5 seconds (until ms=%d)." % (Time.get_ticks_msec() + 5000))
	
	# 6. ─── TASK 6: SUPPRESS STUCK DETECTOR GRACE PERIOD (3 seconds) ─
	# Set _stuck_timer to a negative value (-3.0) so the stuck failsafe
	# in entity_controller.gd doesn't fire during the first 3 seconds
	# while the NavigationAgent3D generates a valid path around the van's
	# collision mesh. The stuck detector will add delta each frame until
	# the timer reaches 0.0, then begin normal checks.
	if "_stuck_timer" in entity:
		entity._stuck_timer = -3.0
		print("[EscapeVan] Entity _stuck_timer set to -3.0 (3-second stuck detection grace period).")


## Recursively searches for a Marker3D with the given name.
func _find_marker_recursive(root: Node, marker_name: String) -> Marker3D:
	for child in root.get_children():
		if child is Marker3D and child.name == marker_name:
			return child as Marker3D
		var found = _find_marker_recursive(child, marker_name)
		if found:
			return found
	return null


## Pushes a text message to the HUD overlay.
func _show_hud_message(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(msg)
	else:
		print("[EscapeVan HUD]: ", msg)
