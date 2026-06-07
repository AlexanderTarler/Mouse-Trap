extends Node

## Manages the night progression and horror events.
## Tracks which night the player is on and triggers escalating events.
## Listens to GameTime for day/night transitions.
## Each night lasts one full GameTime night cycle (5 minutes by default).

signal night_started(night: int)
signal night_ended(night: int)
signal horror_event(event_name: String)
signal generator_state_changed(is_running: bool)
signal fuel_changed(current_fuel: float)
signal first_chase_started

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

## Night progress (0.0 to 1.0 within the current night phase)
var night_progress: float = 0.0

## Whether the current night is active
var is_night_active: bool = false

## Whether the current day phase is active (between nights)
var is_day_active: bool = false

## Events that have been triggered this night
var _triggered_events: Array[String] = []

## Timer for triggering events during the night
var _event_timer: float = 0.0

## Reference to GameTime autoload
var _game_time: Node = null

## Maximum retry attempts for finding GameTime
var _find_gt_attempts: int = 0
const _MAX_FIND_GT_ATTEMPTS: int = 60

# --- POWER GRID ---
var is_generator_on: bool = true
var generator_fuel: float = 50.0
var max_fuel: float = 100.0
var base_fuel_drain: float = 0.12
var current_drain_rate: float = 0.12


func _ready() -> void:
	# Try to find GameTime via the scene tree (autoloads are children of /root)
	_find_game_time()


func _find_game_time() -> void:
	_find_gt_attempts += 1
	if _find_gt_attempts > _MAX_FIND_GT_ATTEMPTS:
		print("NightManager: GameTime not found after %d attempts." % _MAX_FIND_GT_ATTEMPTS)
		return
	
	# Find GameTime via the scene tree (autoloads are children of /root)
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		_game_time = gt
		_game_time.night_started.connect(_on_game_night_started)
		_game_time.day_started.connect(_on_game_day_started)
		
		# If it's already night, start immediately
		if not _game_time.is_day:
			start_night(current_night)
		print("NightManager: Connected to GameTime.")
	else:
		# Retry next frame — GameTime might not be ready yet
		call_deferred("_find_game_time")


func _process(delta: float) -> void:
	# Allow processing during both night and day phases.
	# During day, we skip horror events and generator drain so the
	# cabin grid sits in a passive, non-depleting safety state.
	if not is_night_active and not is_day_active:
		return
	
	# Update night progress from GameTime
	if _game_time:
		night_progress = _game_time.get_phase_progress()
	
	# --- POWER GRID: REAL-TIME FUEL DRAIN ---
	# Only drain fuel during active nights. During the day, the generator
	# sits in a passive state — no fuel consumed, lights stay on for free.
	if is_night_active:
		if is_generator_on:
			generator_fuel -= current_drain_rate * delta
			generator_fuel = clampf(generator_fuel, 0.0, max_fuel)
			fuel_changed.emit(generator_fuel)
			
			# Blackout when fuel hits zero
			if generator_fuel <= 0.0:
				is_generator_on = false
				generator_state_changed.emit(false)
				fuel_changed.emit(0.0)
				print("[Power Grid] Blackout! The generator has run completely out of fuel.")
				
				# Notify the Entity of the blackout — if it was stunned by the
				# overload trap, it will be released into an ENRAGED state.
				# If it wasn't stunned, this call is a no-op.
				var entity = get_tree().get_first_node_in_group("entity")
				if entity and entity.has_method("on_generator_blackout"):
					entity.on_generator_blackout()

	
	# Check for time-based events (only during active nights)
	if is_night_active:
		_event_timer += delta
		if _event_timer >= 5.0:
			_event_timer = 0.0
			_check_time_events()


func _on_game_night_started() -> void:
	start_night(current_night)


func _on_game_day_started() -> void:
	end_current_night()


## Starts a specific night.
## Flips is_day_active to false, sets is_night_active to true,
## and awakens the monster controller.
## On Night 1, the Entity is NOT activated — the car alarm narrative
## event plays first, and the Entity only appears when the player
## interacts with the car.
func start_night(night: int) -> void:
	current_night = night
	night_progress = 0.0
	_triggered_events.clear()
	_event_timer = 0.0
	is_day_active = false
	is_night_active = true
	night_started.emit(night)
	
	# Night 1 exception: Entity stays hidden for the car alarm narrative
	if night == 1:
		print("Night 1: Entity remains hidden for the car alarm narrative event.")
	else:
		# Check if the Entity has been manually disabled via the debug console.
		# The debug console sets a meta flag "debug_disabled" on the Entity node
		# when the player toggles it off. If set, we skip auto-activation so the
		# Entity stays dormant even when a new night starts.
		var entity_nodes = get_tree().get_nodes_in_group("entity")
		var should_activate = true
		for e in entity_nodes:
			if e.has_meta("debug_disabled") and e.get_meta("debug_disabled"):
				should_activate = false
				print("Night %d: Entity is debug-disabled. Skipping auto-activation." % night)
				break
		
		if should_activate:
			# Awaken the entity for the night
			get_tree().call_group("entity", "activate")
	
	print("Night %d has begun..." % night)


## Ends the current night and transitions to the day phase.
## During the dawn sequence:
##   - Deactivates the monster (stores it away safely)
##   - Clears uncollected pickups from the environment
##   - Spawns fresh daylight survival items (batteries, fuel cans, etc.)
##   - If more nights remain, increments the night counter
##   - If all nights are survived, triggers the game-over sequence
func end_current_night() -> void:
	if not is_night_active:
		return
	is_night_active = false
	is_day_active = true
	night_ended.emit(current_night)
	
	# Deactivate the entity — safely store the monster away during the day
	get_tree().call_group("entity", "deactivate")
	
	print("Night %d has ended! Dawn breaks." % current_night)
	
	# --- DAWN RESUPPLY: Clear old pickups and spawn fresh day items ---
	_clear_environment_pickups()
	_respawn_day_items()
	
	if current_night < total_nights:
		current_night += 1
		print("Preparing for Night %d..." % current_night)
	else:
		print("All nights survived! Game over.")


## Removes all uncollected pickup items from the environment.
## Iterates children of the ItemSpawner and frees any pickup nodes
## that are still lying around (batteries, fuel cans, notes, etc.).
func _clear_environment_pickups() -> void:
	var spawner = get_node_or_null("/root/CottageHorror/ItemSpawner")
	if not spawner:
		spawner = get_node_or_null("/root/Main/ItemSpawner")
	if not spawner:
		return
	
	# Free all pickup children (batteries, notes, etc.) that weren't collected
	for child in spawner.get_children():
		if child is Marker3D:
			continue  # Keep spawn point markers
		if child.has_method("queue_free"):
			child.queue_free()
	
	print("[Dawn Resupply] Cleared uncollected pickups from the environment.")


## Spawns fresh survival items for the upcoming day/night cycle.
## Calls the ItemSpawner's deferred spawn method so items appear
## after the old ones have been cleaned up.
func _respawn_day_items() -> void:
	var spawner = get_node_or_null("/root/CottageHorror/ItemSpawner")
	if not spawner:
		spawner = get_node_or_null("/root/Main/ItemSpawner")
	if not spawner:
		return
	
	if spawner.has_method("_spawn_items"):
		spawner.call_deferred("_spawn_items")
		print("[Dawn Resupply] Spawned fresh survival items for the new cycle.")


## Recalculates the dynamic fuel drain rate based on active cabin lights.
## Iterates all nodes in the "CabinLights" group and sums their energy_drain_rate
## for any light that is switched on while the generator is running.
## Returns the new total drain rate.
func recalculate_fuel_drain() -> float:
	var active_drain = base_fuel_drain
	var lights = get_tree().get_nodes_in_group("CabinLights")
	
	for light in lights:
		if "is_switched_on" in light and light.is_switched_on and is_generator_on:
			active_drain += light.energy_drain_rate
	
	current_drain_rate = active_drain
	return current_drain_rate


## Checks for time-based horror events.
func _check_time_events() -> void:
	var progress = night_progress
	
	match current_night:
		1:
			# Night 1: Car alarm is now driven exclusively by the bed interaction
			# (bed_interactable.gd → _trigger_sleep_intro_sequence).
			# No time-based auto-trigger — the player must choose to sleep.
			pass
		
		2:
			# Night 2: Entity appears briefly
			if progress > 0.3 and not "entity_glimpse" in _triggered_events:
				_trigger_event("entity_glimpse")
			if progress > 0.7 and not "door_creak" in _triggered_events:
				_trigger_event("door_creak")
		
		3:
			# Night 3: Entity inside
			if progress > 0.2 and not "entity_inside" in _triggered_events:
				_trigger_event("entity_inside")
			if progress > 0.5 and not "object_moved" in _triggered_events:
				_trigger_event("object_moved")
			if progress > 0.8 and not "footsteps" in _triggered_events:
				_trigger_event("footsteps")
		
		4:
			# Night 4: Aggressive
			if progress > 0.1 and not "entity_appears" in _triggered_events:
				_trigger_event("entity_appears")
			if progress > 0.4 and not "lights_flicker" in _triggered_events:
				_trigger_event("lights_flicker")
			if progress > 0.7 and not "entity_charge" in _triggered_events:
				_trigger_event("entity_charge")
		
		5:
			# Night 5: Final night - constant activity
			if progress > 0.1 and not "entity_constant" in _triggered_events:
				_trigger_event("entity_constant")
			if progress > 0.4 and not "poltergeist" in _triggered_events:
				_trigger_event("poltergeist")
			if progress > 0.8 and not "final_confrontation" in _triggered_events:
				_trigger_event("final_confrontation")


## Triggers a horror event.
func _trigger_event(event_name: String) -> void:
	_triggered_events.append(event_name)
	horror_event.emit(event_name)
	
	# Special logging for lights_flicker — this event triggers the cabin
	# lights to physically flicker (via CabinLight's power-on flicker sequence
	# or the HorrorSoundManager's lights_flicker sound effect).
	if event_name == "lights_flicker":
		print("[Horror Event] LIGHTS FLICKER! The cabin lights are flickering! Night %d at progress %.0f%%" % [current_night, night_progress * 100.0])
	else:
		print("Horror event: %s" % event_name)


## Called by the EscapeVan when the player interacts with the car.
## Emits first_chase_started so the Entity can make its cinematic arrival
## and the player's sprint gets unlocked.
## Also plays the distant monster howl (monster_distant_mx_1.ogg) to signal
## the Entity's arrival — this is suppressed on Night 1's night_started event
## so it plays here instead for maximum dramatic impact.
func trigger_first_chase() -> void:
	print("[NightManager] First chase triggered! Entity is arriving.")
	
	# Play the distant monster howl to signal the Entity's arrival.
	# On Night 1, this sound is suppressed during night_started so it
	# plays here instead — right when the Entity spawns.
	var hsm = get_node_or_null("/root/HorrorSoundManager")
	if hsm and hsm.has_method("play_distant_monster"):
		hsm.play_distant_monster()
	
	first_chase_started.emit()


## Restarts the current night from scratch.
## Called by the Game Over screen when the player clicks "Restart Night".
## Resets the night state, refills the generator, and re-enters the night cycle.
func restart_night() -> void:
	print("[NightManager] Restarting Night %d..." % current_night)
	
	# Reset night state
	is_night_active = false
	is_day_active = false
	night_progress = 0.0
	_triggered_events.clear()
	_event_timer = 0.0
	
	# Refill the generator so the player has a fair chance
	is_generator_on = true
	generator_fuel = max_fuel
	fuel_changed.emit(generator_fuel)
	generator_state_changed.emit(true)
	
	# Reset GameTime progress to the start of the night
	var gt = get_node_or_null("/root/GameTime")
	if gt and gt.has_method("reset_to_night_start"):
		gt.reset_to_night_start()
	
	# Start the night fresh
	start_night(current_night)


## Resets the game state to the morning baseline of the current day.
## Called by JumpscareManager after the jumpscare fade-out completes.
## This is the player's "wake up in bed" reset — NOT a full night restart.
##
## The reset performs four phases:
##   A. TIME & WEATHER RESET — Rewind the clock to morning/daytime.
##   B. CHARACTER & INVENTORY RESET — Teleport player to bed, restore health,
##      wipe inventory, and rebuild baseline morning items.
##   C. WORLD MACHINE RESET — Clear deployed traps/cables, reset fuse box,
##      turn off all lights, force Entity to DORMANT.
##   D. FADE BACK IN — Tween the JumpscareManager's fade_rect from black
##      to transparent over 2.0 seconds.
func reset_to_daybreak() -> void:
	print("[NightManager] reset_to_daybreak() — Resetting to morning baseline of Day %d." % current_night)
	
	# ─── PHASE A: TIME & WEATHER RESET ──────────────────────────────
	# Rewind the clock to morning. On Night 1, force to 14:30 (2:30 PM).
	# For subsequent days, roll back to the baseline morning hour.
	var gt: Node = get_node_or_null("/root/GameTime")
	if gt and gt.has_method("set_progress"):
		if current_night == 1:
			# Night 1: Force to 14:30 (cycle_progress ≈ 0.25 for a 24-hour cycle)
			# cycle_progress = 14.5 / 24.0 ≈ 0.604
			gt.set_progress(14.5 / 24.0)
		else:
			# Subsequent days: Roll back to early morning (cycle_progress ≈ 0.125 = 6:00 AM)
			gt.set_progress(0.125)
		print("[NightManager] Time reset to morning (progress: %.3f)." % gt.cycle_progress)
	
	# Force the EnvironmentController to update sky/lighting immediately.
	# The GameTime.set_progress() call above emits time_changed, which the
	# EnvironmentController listens to, so this should happen automatically.
	# If not, we manually trigger a refresh.
	var ec: Node = get_node_or_null("/root/CottageHorror/EnvironmentController")
	if not ec:
		ec = get_node_or_null("/root/Main/EnvironmentController")
	if ec and ec.has_method("_apply_cycle"):
		ec._apply_cycle()
		print("[NightManager] EnvironmentController refreshed to daytime lighting.")
	
	# ─── PHASE B: CHARACTER & INVENTORY RESET ───────────────────────
	# Teleport the player back to the bedroom spawn point.
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player:
		# Find the bedroom spawn marker
		var spawn_marker: Node3D = get_tree().get_first_node_in_group("BedroomSpawn") as Node3D
		if not spawn_marker:
			# Fallback: search for a Marker3D named "BedroomSpawn" or "PlayerSpawn"
			spawn_marker = get_tree().get_first_node_in_group("PlayerSpawn") as Node3D
		if not spawn_marker:
			# Hardcoded fallback position (bedroom coordinates)
			spawn_marker = get_tree().current_scene.get_node_or_null("BedroomSpawn") as Node3D
		
		if spawn_marker:
			player.global_position = spawn_marker.global_position
			print("[NightManager] Player teleported to spawn: ", spawn_marker.global_position)
		else:
			# Ultimate fallback: hardcoded bedroom position
			player.global_position = Vector3(9.0, 1.0, 0.4)
			print("[NightManager] No spawn marker found. Using fallback position.")
		
		# Reset player health/sanity to 100%
		if player.has_method("reset_health"):
			player.reset_health()
		elif "health" in player:
			player.health = 100.0
		if "sanity" in player:
			player.sanity = 100.0
		print("[NightManager] Player health/sanity reset to 100%.")
		
		# Reset flashlight battery to full
		var flashlight: Node = player.find_child("*Flashlight*", true, false)
		if flashlight:
			if flashlight.has_method("set_battery_level"):
				flashlight.set_battery_level(100.0)
			elif "battery_level" in flashlight:
				flashlight.battery_level = 100.0
			print("[NightManager] Flashlight battery restored to 100%.")
	
	# Wipe the inventory and rebuild baseline morning items.
	# Baseline: 3 Batteries, 2 Planks, 2 Fuel Cans, 1 Fuse.
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv:
		inv.clear()
		print("[NightManager] Inventory wiped.")
		
		# Load item resources and add them to the inventory
		var battery_res: Resource = load("res://resources/battery_resource.tres")
		var plank_res: Resource = load("res://resources/plank_resource.tres")
		var fuel_can_res: Resource = load("res://resources/fuel_can_resource.tres")
		var fuse_res: Resource = load("res://resources/fuse_resource.tres")
		
		# Add 3 Batteries
		for i in range(3):
			if battery_res and inv.has_method("add_item"):
				inv.add_item(battery_res.duplicate())
		
		# Add 2 Planks
		for i in range(2):
			if plank_res and inv.has_method("add_item"):
				inv.add_item(plank_res.duplicate())
		
		# Add 2 Fuel Cans
		for i in range(2):
			if fuel_can_res and inv.has_method("add_item"):
				inv.add_item(fuel_can_res.duplicate())
		
		# Add 1 Fuse
		if fuse_res and inv.has_method("add_item"):
			inv.add_item(fuse_res.duplicate())
		
		print("[NightManager] Baseline morning items added: 3 Batteries, 2 Planks, 2 Fuel Cans, 1 Fuse.")
	
	# ─── PHASE C: WORLD MACHINE RESET ──────────────────────────────
	# Clear deployed portable traps and power cables from the yard.
	var traps: Array[Node] = get_tree().get_nodes_in_group("portable_trap")
	for trap in traps:
		if trap and is_instance_valid(trap):
			trap.queue_free()
			print("[NightManager] Cleared portable trap: ", trap.name)
	
	var cables: Array[Node] = get_tree().get_nodes_in_group("power_cable")
	for cable in cables:
		if cable and is_instance_valid(cable):
			cable.queue_free()
			print("[NightManager] Cleared power cable: ", cable.name)
	
	# Reset the FuseBox to BROKEN state and turn off all room lights.
	var fuse_box: Node = get_tree().get_first_node_in_group("interactable")
	if fuse_box and fuse_box is FuseBox:
		fuse_box.current_state = 0  # BoxState.BROKEN
		if fuse_box.has_method("_set_generator_state"):
			fuse_box._set_generator_state(false)
		print("[NightManager] FuseBox reset to BROKEN. Generator turned off.")
	
	# Turn off all cabin lights.
	var cabin_lights: Array[Node] = get_tree().get_nodes_in_group("CabinLights")
	for light in cabin_lights:
		if "is_switched_on" in light:
			light.is_switched_on = false
		if "turn_off" in light:
			light.turn_off()
	print("[NightManager] All cabin lights turned off.")
	
	# Reset the generator fuel to full so the player has a fair chance.
	is_generator_on = false
	generator_fuel = max_fuel
	fuel_changed.emit(generator_fuel)
	generator_state_changed.emit(false)
	print("[NightManager] Generator fuel reset to %.1f (off state)." % max_fuel)
	
	# Force the Entity back to DORMANT state, stopping all active pathfinding.
	var entity_nodes: Array[Node] = get_tree().get_nodes_in_group("entity")
	for entity_node in entity_nodes:
		if entity_node and entity_node.has_method("deactivate"):
			entity_node.deactivate()
			print("[NightManager] Entity deactivated to DORMANT.")
		elif "State" in entity_node:
			# Direct state manipulation fallback
			entity_node._state = 0  # State.DORMANT
			entity_node._is_active = false
			print("[NightManager] Entity state forced to DORMANT (fallback).")
	
	# Reset night state flags so the night cycle can restart cleanly.
	is_night_active = false
	is_day_active = true
	night_progress = 0.0
	_triggered_events.clear()
	_event_timer = 0.0
	
	print("[NightManager] Daybreak reset complete. Player is safe in bed.")
	
	# ─── PHASE D: FADE BACK IN ─────────────────────────────────────
	# Find the JumpscareManager's fade_rect and tween it from black to transparent.
	var jm: Node = get_node_or_null("/root/JumpscareManager")
	if jm and "fade_rect" in jm and jm.fade_rect:
		var fade_rect: ColorRect = jm.fade_rect as ColorRect
		if fade_rect:
			var wake_tween: Tween = create_tween()
			wake_tween.tween_property(fade_rect, "color:a", 0.0, 2.0)
			await wake_tween.finished
			print("[NightManager] Fade-in complete. Player can see again.")
	else:
		print("[NightManager] JumpscareManager fade_rect not found. Skipping fade-in.")


## Returns the current night's intensity (0.0 to 1.0).
func get_intensity() -> float:
	var night_factor = float(current_night) / float(total_nights)
	var time_factor = night_progress
	return min(1.0, night_factor * 0.6 + time_factor * 0.4)
