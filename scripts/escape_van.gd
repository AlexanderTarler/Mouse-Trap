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

# ─── TASK 8: SPRINT TUTORIAL ONE-SHOT GUARD ─────────────────────────
## True once the "Hold SHIFT to run" hint has been fired at the STALK
## transition (during the Night 2.2 van sequence). Prevents re-triggering
## if the chase sequence is ever re-run (e.g. scene reload).
var _sprint_tutorial_fired: bool = false
## The Night 2.2 checkpoint has been taken at the alarm.
var _alarm_checkpoint_taken: bool = false

# ─── HOLD-TO-INTERACT: Car Part Installation ──────────────────────────────
## Whether the player is currently holding E to install a car part.
## Set by start_hold_interact(), cleared by stop_hold_interact().
var _is_installing: bool = false

## Accumulated hold progress (seconds) for the current car part installation.
## Counts up from 0.0 to INSTALL_TIME (5.0s), then one part is installed.
## Saved on release so the player can continue from where they left off.
var _install_progress: float = 0.0

## How long the player must hold E to install one car part.
const INSTALL_TIME: float = 5.0

## The car part currently being installed (cached name for completion).
var _pending_part_name: String = ""
var _pending_part_index: int = -1

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
func _connect_night_manager() -> void:
	_night_manager = get_node_or_null("/root/NightManager")
	if _night_manager:
		_night_manager.horror_event.connect(_on_horror_event)
	else:
		call_deferred("_connect_night_manager")


# ─── HORROR EVENTS ─────────────────────────────────────────

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
		
		var gt = get_node_or_null("/root/GameTime")
		if gt:
			gt.cycle_progress = 0.9
			gt._elapsed = gt.cycle_progress * gt.cycle_duration
			gt.is_day = false
			gt.is_time_paused = true
			gt.time_changed.emit(0.9)
			print("[EscapeVan] GameTime forced to cycle_progress=0.9 (4 min into night) and paused during van sequence.")
		
		_darken_environment_for_van_sequence()
		print("[EscapeVan] Car alarm is blaring!")
		# Night 2.2 starts here: a death in it restarts at the van with the
		# alarm going (Checkpoint "van_alarm"), not at the start of Night 2.
		if not _alarm_checkpoint_taken:
			_alarm_checkpoint_taken = true
			var checkpoint := get_node_or_null("/root/Checkpoint")
			if checkpoint and checkpoint.has_method("capture"):
				checkpoint.capture("night", "van_alarm")


# ─── INTERACTION ───────────────────────────────────────────

func interact() -> void:
	# ─── PRIORITY 1: Alarm is active → trigger first chase ──────────
	if alarm_active:
		_trigger_first_chase()
		return
	
	# ─── PRIORITY 2: Van is repaired → trigger ending ───────────────
	if is_repaired:
		_trigger_ending()
		return
	
	# ─── PRIORITY 3: First time inspecting a non-repaired van ───────
	# Notify RoutineManager to activate the van checklist in the notebook.
	_ensure_van_inspected()
	
	# ─── PRIORITY 4: Not repaired → try to install a component ──────
	_try_install_component()


## Ensures the van inspection event fires exactly once.
## Called on the first interact() when the van is not repaired.
func _ensure_van_inspected() -> void:
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("on_van_inspected"):
		rm.on_van_inspected()


## Tries to install a car component from the player's inventory.
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
		_show_hud_message("This van is busted. I need to find parts to fix it... maybe the wrecked cars nearby still have some useable components.")
		print("[EscapeVan] No car parts in inventory.")
		return
	
	# ─── UNIQUE PART VALIDATION ──────────────────────────────────
	if _installed_parts.has(car_part_name):
		_show_hud_message("I've already put a %s in. I need something else." % car_part_name.to_lower())
		print("[EscapeVan] DUPLICATE REJECTED: %s is already installed." % car_part_name)
		return
	
	if car_part_name not in REQUIRED_PARTS:
		_show_hud_message("This doesn't look like it belongs in the van...")
		print("[EscapeVan] UNKNOWN PART REJECTED: '%s' is not a required van component." % car_part_name)
		return
	
	# Remove the car part from inventory and mark it as installed
	inventory.remove_at(car_part_index)
	_installed_parts[car_part_name] = true
	components_collected += 1
	
	print("[EscapeVan] Component installed: %s (%d/%d)" % [car_part_name, components_collected, COMPONENTS_NEEDED])
	_show_hud_message(_installed_line(car_part_name))
	
	# ─── NOTIFY ROUTINEMANAGER ────────────────────────────────────
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("on_van_part_installed"):
		rm.on_van_part_installed(car_part_name)
	
	# Check if all components are installed
	if components_collected >= COMPONENTS_NEEDED:
		_repair_complete()
	else:
		if _repair_audio:
			_repair_audio.pitch_scale = 1.0
			_repair_audio.play()


## The thought after fitting a part: how many are still missing.
func _installed_line(part_name: String) -> String:
	var remaining := COMPONENTS_NEEDED - components_collected
	if remaining <= 0:
		return "That's the %s in." % part_name.to_lower()
	var left := "One more part to go." if remaining == 1 else "%s more parts to go." % ("Two" if remaining == 2 else str(remaining))
	return "That's the %s in. %s" % [part_name.to_lower(), left]


## Called when all 3 components have been installed.
func _repair_complete() -> void:
	is_repaired = true
	
	print("[EscapeVan] ⚡ VAN REPAIRED! All %d components installed." % COMPONENTS_NEEDED)
	_show_hud_message("That should do it. Time to get the hell out of here.")
	
	# ─── NOTIFY ROUTINEMANAGER ────────────────────────────────────
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("on_van_repaired"):
		rm.on_van_repaired()
	
	if _repair_audio:
		_repair_audio.pitch_scale = 1.5
		_repair_audio.play()


# ─── HOLD-TO-INTERACT: Car Part Installation ──────────────────────────────
## Called by PhysicalGrab when the player presses E while looking at the van.
## Starts accumulating hold progress for installing a car part.
func start_hold_interact() -> void:
	if is_repaired or not van_investigated or alarm_active:
		return
	# Find a valid car part to install
	_pending_part_index = -1
	_pending_part_name = ""
	var inventory = get_node_or_null("/root/Inventory")
	if not inventory:
		return
	for i in range(inventory.items.size()):
		var item = inventory.items[i]
		if item and item.item_type == 7:
			# Check it's not a duplicate
			if not _installed_parts.has(item.item_name) and item.item_name in REQUIRED_PARTS:
				_pending_part_index = i
				_pending_part_name = item.item_name
				break
	if _pending_part_index < 0:
		return
	_is_installing = true
	
	# TASK 8: Start the repair sound the MOMENT the player holds E.
	# Previously the audio only played when the part reached 100% installation.
	if _repair_audio:
		_repair_audio.pitch_scale = 1.0
		_repair_audio.play()
	print("[Van Install] Start installing %s at progress %.1f/%.1fs" % [_pending_part_name, _install_progress, INSTALL_TIME])


## Called by PhysicalGrab when the player releases E.
## Saves progress so the player can continue from where they left off.
func stop_hold_interact() -> void:
	if not _is_installing:
		return
	_is_installing = false
	
	# TASK 8: Stop the repair sound if the player releases E before finishing.
	if _repair_audio:
		_repair_audio.stop()
	print("[Van Install] Released at progress %.1f/%.1fs" % [_install_progress, INSTALL_TIME])


## Called by PhysicalGrab every frame while E is held.
## Accumulates hold progress for installing the car part.
func _process_hold_interact(delta: float) -> void:
	if not _is_installing:
		return
	
	_install_progress += delta
	
	if _install_progress >= INSTALL_TIME:
		_install_progress = 0.0
		
		# Check the car part is still in inventory
		var inventory = get_node_or_null("/root/Inventory")
		if not inventory or _pending_part_index >= inventory.items.size():
			_is_installing = false
			return
		var item = inventory.items[_pending_part_index]
		if not item or item.item_name != _pending_part_name:
			# Part was removed somehow — find a new one
			_is_installing = false
			start_hold_interact()
			return
		
		# Install it
		inventory.remove_at(_pending_part_index)
		_installed_parts[_pending_part_name] = true
		components_collected += 1
		
		print("[EscapeVan] Component installed via hold: %s (%d/%d)" % [_pending_part_name, components_collected, COMPONENTS_NEEDED])
		_show_hud_message(_installed_line(_pending_part_name))
		
		# TASK 8: The repair audio is already playing from start_hold_interact() —
		# do NOT restart it here at completion.
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_van_part_installed"):
			rm.on_van_part_installed(_pending_part_name)
		
		if components_collected >= COMPONENTS_NEEDED:
			_is_installing = false
			_repair_complete()
		else:
			# Try to automatically start next part
			_is_installing = false
			start_hold_interact()


## Override get_interact_text to show installation progress.
func get_interact_text() -> String:
	if alarm_active:
		return "[E] Investigate the car"
	if is_repaired:
		return "[E] Escape"
	if _is_installing and _pending_part_name != "":
		var pct = int((_install_progress / INSTALL_TIME) * 100.0)
		return "[E] Installing %s... %d%%" % [_pending_part_name, pct]
	if not van_investigated:
		return "[E] Examine the van"
	# Check if there's a valid part to install
	var inventory = get_node_or_null("/root/Inventory")
	if inventory:
		for i in range(inventory.items.size()):
			var item = inventory.items[i]
			if item and item.item_type == 7:
				if not _installed_parts.has(item.item_name) and item.item_name in REQUIRED_PARTS:
					return "[E] Install %s (%d/3) [Hold %.1fs]" % [item.item_name, components_collected, INSTALL_TIME]
	return "[E] Try to repair the van (%d/3)" % components_collected


## Triggers the ending sequence via EndgameManager.
func _trigger_ending() -> void:
	print("[EscapeVan] Player is escaping! Triggering ending sequence.")
	
	var endgame = get_node_or_null("/root/EndgameManager")
	if not endgame:
		print("[EscapeVan] ERROR: EndgameManager not found!")
		return
	
	# Check if the TotemAnchor was destroyed.
	# Prefer RoutineManager's is_anchor_destroyed flag (authoritative).
	var totem_destroyed = false
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and "is_anchor_destroyed" in rm:
		totem_destroyed = rm.is_anchor_destroyed
	else:
		# Fallback: check totem_anchor group nodes
		var totems = get_tree().get_nodes_in_group("totem_anchor")
		for totem in totems:
			if "is_purged" in totem and totem.is_purged:
				totem_destroyed = true
				break
	
	endgame.start_ending_sequence(totem_destroyed)


func _trigger_first_chase() -> void:
	alarm_active = false
	if _alarm_audio:
		_alarm_audio.stop()
	if _alarm_light:
		_alarm_light.visible = false
	
	van_investigated = true
	
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		gt.cycle_progress = 0.9
		gt._elapsed = gt.cycle_progress * gt.cycle_duration
		gt.is_day = false
		gt.time_changed.emit(0.9)
		print("[EscapeVan] Time re-forced to cycle_progress=0.9 (4 min into night) for Night 2.2.")
	
	_restore_environment_lighting()
	
	if gt:
		gt.is_time_paused = false
		gt.is_running = true
		print("[EscapeVan] GameTime unpaused. Night 2.2 clock starts from 04:00.")
	
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("unlock_sprint"):
		player.unlock_sprint()
	
	var objective_label = _find_objective_label()
	if objective_label:
		objective_label.text = "JOIN HIM"
		objective_label.modulate = Color(1, 0.2, 0.2, 1)
		await get_tree().create_timer(0.5).timeout
		objective_label.text = "FLEE"
		objective_label.modulate = Color(1, 0.5, 0, 1)
	
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("_show_event"):
		hud._show_event("The ignition... it's been completely torn out.")
	else:
		print("[EscapeVan] The ignition... it's been completely torn out.")
	
	await get_tree().create_timer(2.0).timeout
	
	_teleport_entity_to_van()
	
	if _night_manager:
		_night_manager.trigger_first_chase()
	
	print("[EscapeVan] Player investigated the van. First chase initiated!")


# ─── PROCESS ───────────────────────────────────────────────

func _process(delta: float) -> void:
	if alarm_active and _alarm_light:
		# Twice as strong and further reaching as before, plus a glowing
		# beacon: the van is ~105 m from the cabin, too far for light alone.
		_alarm_light.omni_range = 80.0
		var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		_alarm_light.light_energy = 2.0 + pulse * 8.0
		_update_beacon(pulse)
	elif _beacon and _beacon.visible:
		_beacon.visible = false


## A pulsing red glow over the van while the alarm sounds, unaffected by fog
## so it can be seen from the cabin.
var _beacon: MeshInstance3D = null


func _update_beacon(pulse: float) -> void:
	if not _beacon:
		_beacon = MeshInstance3D.new()
		_beacon.name = "AlarmBeacon"
		var quad := QuadMesh.new()
		quad.size = Vector2(1.6, 1.6)
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		glow.disable_fog = true
		glow.no_depth_test = false
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color(1, 0.1, 0.05, 1), Color(1, 0, 0, 0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		glow.albedo_texture = texture
		quad.material = glow
		_beacon.mesh = quad
		_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_beacon)
		_beacon.position = _alarm_light.position + Vector3.UP * 0.4
	_beacon.visible = true
	var mat := (_beacon.mesh as QuadMesh).material as StandardMaterial3D
	mat.albedo_color = Color(1, 1, 1, 0.25 + pulse * 0.75)
	_beacon.scale = Vector3.ONE * (0.8 + pulse * 0.6)


# ─── UI HELPERS ────────────────────────────────────────────

func _find_objective_label() -> Label:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_node("ObjectiveLabel"):
		return hud.get_node("ObjectiveLabel") as Label
	return null


# ─── NOTE: get_interact_text() is now defined in the HOLD-TO-INTERACT section
# ─── near the @export variables. The old version was removed
# ─── to fix duplicate function error.

# ─── ENVIRONMENT & ENTITY HELPERS ──────────────────────────

func _darken_environment_for_van_sequence() -> void:
	var ec = get_tree().get_first_node_in_group("environment_controller")
	if not ec:
		print("[EscapeVan] EnvironmentController not found — skipping darkness override.")
		return
	if ec.has_method("force_true_night"):
		ec.force_true_night()
	else:
		if ec.world_environment and ec.world_environment.environment:
			ec.world_environment.environment.ambient_light_energy = 0.02
			ec.world_environment.environment.ambient_light_color = Color(0.01, 0.01, 0.03)
		if ec.sun:
			ec.sun.light_energy = 0.0
		if ec.moon:
			ec.moon.light_energy = 0.03


func _restore_environment_lighting() -> void:
	var ec = get_tree().get_first_node_in_group("environment_controller")
	if not ec:
		return
	if ec.has_method("restore_cycle"):
		ec.restore_cycle()
	elif ec.has_method("_apply_cycle"):
		ec._apply_cycle()


## Where the player restarts after dying in Night 2.2: a few metres in front
## of the van, on the cabin's side, facing it.
func get_restart_transform() -> Transform3D:
	var toward_cabin := Vector3(9.0, 0.0, 14.0) - global_position
	toward_cabin.y = 0.0
	toward_cabin = toward_cabin.normalized() if toward_cabin.length_squared() > 0.01 else Vector3.BACK
	var spot := global_position + toward_cabin * 5.0
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 3.0, spot + Vector3.DOWN * 5.0, 1))
	spot.y = (hit.position.y if not hit.is_empty() else global_position.y) + 0.1
	return Transform3D(Basis.looking_at(-toward_cabin, Vector3.UP), spot)


func _teleport_entity_to_van() -> void:
	var entity := get_tree().get_first_node_in_group("entity") as Entity
	if not entity:
		print("[EscapeVan] ERROR: Entity not found in scene! Cannot start the chase.")
		return
	
	var spawn_marker: Marker3D = null
	var scene_root = get_tree().current_scene
	if scene_root:
		spawn_marker = scene_root.get_node_or_null("EntityVanSpawn") as Marker3D
		if not spawn_marker:
			spawn_marker = _find_marker_recursive(scene_root, "EntityVanSpawn")
	
	var spawn_position := global_position + Vector3(5, 0, -10)
	if spawn_marker:
		spawn_position = spawn_marker.global_position
	else:
		print("[EscapeVan] WARNING: EntityVanSpawn marker not found! Spawning the Entity next to the van.")
	
	# The Entity appears and pursues the player until they reach the cabin,
	# then vanishes for the rest of the night.
	entity.start_van_chase(spawn_position)
	
	# The "Hold SHIFT to run" hint appears the moment the chase starts: the
	# first time the player needs to sprint. One-shot in case the sequence
	# re-runs (e.g. scene reload).
	if not _sprint_tutorial_fired:
		_sprint_tutorial_fired = true
		var tm_sprint := get_node_or_null("/root/TutorialManager")
		if tm_sprint and tm_sprint.has_method("trigger"):
			# Forced: it replaces any other hint, and stays until the player
			# has run their stamina down to 70% (player_controller).
			tm_sprint.trigger("sprint", true)


func _find_marker_recursive(root: Node, marker_name: String) -> Marker3D:
	for child in root.get_children():
		if child is Marker3D and child.name == marker_name:
			return child as Marker3D
		var found = _find_marker_recursive(child, marker_name)
		if found:
			return found
	return null


func _show_hud_message(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(msg, self)
	else:
		print("[EscapeVan HUD]: ", msg)
