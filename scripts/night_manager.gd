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


## Returns the current night's intensity (0.0 to 1.0).
func get_intensity() -> float:
	var night_factor = float(current_night) / float(total_nights)
	var time_factor = night_progress
	return min(1.0, night_factor * 0.6 + time_factor * 0.4)
