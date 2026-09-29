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

@export var is_dev_mode: bool = false

## Current night (0 = Day 1 pre-night, 1-5 = Night 1 through Night 5)
## Starts at 0 representing Day 1 (before any night begins).
## Night 1 begins when start_night(1) is called.
var current_night: int = 0


## Total nights to survive
var total_nights: int = 5

## Night progress (0.0 to 1.0 within the current night phase)
var night_progress: float = 0.0

## Whether the current night is active
var is_night_active: bool = false

## Returns true if the Entity is allowed to approach windows on the current night.
## Night 1 is purely passive observation — the Entity stays in the treeline.
## From Night 2 onward, window approaches are permitted.
##
## DEV MODE: Always returns true, allowing the Entity to approach windows
## on any night for testing navigation and behavior immediately.
func can_approach_windows() -> bool:
	if is_dev_mode:
		return true
	return current_night > 1

## Whether the player has found Arvid's Note in the world.
## When true, the ComputerUI's RECOVER_DATA.EXE will auto-fill the
## decryption key, allowing the player to unlock Arvid's hidden logs
## without needing to manually type "STENBERG_1996".
var arvid_password_found: bool = false

## Whether the current day phase is active (between nights)
var is_day_active: bool = false

## Events that have been triggered this night
var _triggered_events: Array[String] = []

## Timer for triggering events during the night
var _event_timer: float = 0.0

## Tick accumulator for throttling _process() to 5 Hz (0.2s intervals)
var _night_tick_timer: float = 0.0

## Reference to GameTime autoload
var _game_time: Node = null

## Maximum retry attempts for finding GameTime
var _find_gt_attempts: int = 0
const _MAX_FIND_GT_ATTEMPTS: int = 60

# --- TUTORIAL: BROKEN WINDOW FLAG ---
## Persisted flag that tracks whether the tutorial broken window (start_broken)
## has been fixed by the player. Once set to true, the window will NOT reset
## to broken state on scene reloads (death → restart, save/load, etc.).
##
## This flag is set to true when the player boards up the tutorial window,
## and is reset to false when a new game starts (start_night() with night == 1).
##
## CabinWindow reads this flag in _ready() to decide whether to initialize
## the window as broken or boarded.
var tutorial_window_fixed: bool = false

# --- DAY 1 ONBOARDING ---
## Whether time is paused during the Day 1 onboarding sequence.
## Set to true at game start. The clock stays frozen until the player
## unlocks the cabin door with the CabinKey.
var is_time_paused: bool = true

# ─── DEFERRED DOOR LOCK (Day 3+ Exhaustion) ──────────────────────────────
## When true, the night ended and the dawn exhaustion mechanic is waiting
## for the player to reach the HallRoom before closing + locking the door.
## Set by _apply_dawn_exhaustion(). Cleared when the door locks.
var _awaiting_door_lock: bool = false

## Seconds the player has been continuously inside the HallRoom while
## _awaiting_door_lock is active. Resets to 0 if the player leaves.
var _door_lock_delay_timer: float = 0.0

## Whether the Day 1 cabin setup tasks (Fuse, Generator, Computer) have
## been completed. Set to true by RoutineManager when all tasks are done.
## The bed checks this flag before allowing the player to sleep.
var day1_onboarding_complete: bool = false

## Whether the Night 2.2 van sequence (car alarm → chase) is currently active.
## Set to true when the bed triggers the car alarm sequence (current_night 1→2).
## Used by HorrorSoundManager to suppress the distant monster scream, and by
## EnvironmentController to force unnaturally dark lighting.
## Cleared when the Entity's van-sequence FLINCH resolves (the Director's
## Tier 5 DORMANT gate), or defensively when a new night >= 3 starts.
var is_van_sequence_active: bool = false

## Persistent guard that the Night 2.2 van sequence has STARTED this playthrough.
## Unlike is_van_sequence_active (which is CLEARED once the chase resolves), this
## stays true for the rest of the game so the bed can never re-trigger the
## Night 2.2 sequence a second time. Reset to false only when a fresh Night 1
## begins (start_night(1)).
var van_sequence_started: bool = false


# --- NIGHT 1 PEEKER ---
## Timer counting up to the peeker spawn delay (5 seconds into Night 1).
var _peeker_timer: float = 0.0

## Whether the Night 1 peeker has already been spawned this night.
## Prevents multiple spawns from the same night.
var _peeker_spawned: bool = false

## Delay in seconds before the Night 1 peeker spawns after the night starts.
const PEEKER_SPAWN_DELAY: float = 5.0

# --- POWER GRID ---
var is_generator_on: bool = true
var generator_fuel: float = 50.0
var max_fuel: float = 100.0
var base_fuel_drain: float = 0.12
var current_drain_rate: float = 0.12


func _ready() -> void:
	# Try to find GameTime via the scene tree (autoloads are children of /root)
	_find_game_time()
	
	# ─── READ STARTING FUEL FROM GENERATOR NODE ──────────────────────────
	# The Generator node (generator.gd) has a starting_fuel_percent export
	# that controls the initial fuel level. Read it here and apply it to
	# generator_fuel. This allows the designer to set the starting fuel
	# percentage directly in the Inspector on generator.tscn.
	_apply_starting_fuel()
	
	# ─── SET INITIAL TIME TO MID-AFTERNOON ───────────────────────────────
	# The game starts at cycle_progress = 0.35 (~8:24 AM in the game's
	# 24-hour cycle) with time paused. This is safely in the day phase
	# (< 0.5) so game_time.gd's _process() correctly identifies it as
	# daytime and does NOT emit night_started on the first frame.
	# Time is unpaused when the player unlocks the cabin door in Phase 1
	# of the onboarding routine.

	_set_initial_time()
	
	# ─── SPAWN & ONBOARDING (deferred to next frame) ─────────────────────
	# Wait one frame for the scene tree to fully initialize, then set up
	# the player spawn position and start the Day 1 onboarding sequence.
	# This ensures all Marker3D nodes and groups are available.
	call_deferred("_on_scene_ready")
	
	
## Whether the player spawn and dev mode setup has been completed.
## Used by _process() to poll for the player node once per frame.
var _spawn_setup_done: bool = false

# ─── TASK 3: INVENTORY CHECKPOINT GUARD ────────────────────────────────
## When true, the inventory checkpoint snapshot has already been captured
## for the current night cycle. Set in start_night() on first entry; cleared
## in end_current_night()/advance_night() so the next cycle re-snapshots.
## This prevents restart_night() (which re-calls start_night()) from
## overwriting the original snapshot with the post-consumption state.
var _checkpoint_saved: bool = false


## Called one frame after _ready() to ensure the scene tree is fully loaded.
## Sets up the player spawn position and starts the Day 1 onboarding sequence.
##
## Instead of a fixed-frame wait loop (which fails when the main menu scene
## is active and the player hasn't been instantiated yet), this method sets
## a flag that _process() checks every frame. Once the player appears in the
## scene tree (after the main menu transitions to cottage_horror.tscn), the
## spawn, dev mode, and onboarding setup runs automatically.
func _on_scene_ready() -> void:
	# Set the flag so _process() starts polling for the player.
	# The player may not exist yet (main menu scene is still active),
	# so we let _process() handle the wait.
	_spawn_setup_done = false




## Sets the initial game time to mid-afternoon with time paused.
## The clock stays frozen until the player unlocks the cabin door.
##
## IMPORTANT: Uses direct property assignment instead of gt.set_progress()
## to avoid triggering the night_started signal. set_progress() emits
## night_started when cycle_progress > 0.5 (night phase), which would
## cause an unwanted "Night 0 has begun..." event.
##
## We use cycle_progress = 0.35 (~8:24 AM) which is safely in the day
## phase (< 0.5). This ensures game_time.gd's _process() correctly
## identifies it as daytime (is_day = true) and does NOT emit
## night_started on the first frame.
func _set_initial_time() -> void:
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		# Non-dev mode: Day 1 starts 4 minutes into the 5-minute day phase.
		# cycle_progress = 0.4 → 4:00 elapsed, 1:00 remaining until night.
		# Dev mode overrides this to 0.0 (start of day).
		var start_progress: float = 0.4
		if is_dev_mode:
			start_progress = 0.0
		gt.cycle_progress = start_progress
		gt._elapsed = gt.cycle_progress * gt.cycle_duration
		gt.is_day = true
		gt._was_day = true
		# ─── TIME STAYS FROZEN AT BOOT ─────────────────────────────────
		# NightManager is an autoload, so _ready() runs while the main menu
		# is still on screen. The clock must NOT start ticking until the
		# player presses Play and the game scene actually loads. _start_time_running()
		# (called from _process() when the player node appears) unfreezes it
		# the moment gameplay begins.
		gt.is_time_paused = true
		gt.is_running = false
		gt.time_changed.emit(gt.cycle_progress)
		print("[NightManager] Dev=%s: Initial time set to progress=%.4f. Time is FROZEN until the game scene loads." % [is_dev_mode, gt.cycle_progress])
		
		# ─── DEBUG: Log the UI day display ─────────────────────────────
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("get_current_day_string"):
			print("[NightManager] UI Day Label: '%s' (current_night=%d, cycle_progress=%.4f)" % [rm.get_current_day_string(), current_night, gt.cycle_progress])
		else:
			print("[NightManager] UI Day Label: RoutineManager not available (cycle_progress=%.4f)" % gt.cycle_progress)
	
	# Keep our own flag in sync with GameTime — time starts FROZEN at boot.
	is_time_paused = true




## ─── TIME START (GAME LOADED) ──────────────────────────────────────────────
## Called when the player node first appears — which only happens after the
## main menu transitions to the game scene (cottage_horror.tscn). This is the
## true "start" of gameplay, so the day/night clock begins ticking here.
func _start_time_running() -> void:
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		gt.is_time_paused = false
		gt.is_running = true
		gt.time_changed.emit(gt.cycle_progress)
		print("[NightManager] Game scene loaded. GameTime clock is now RUNNING (progress=%.4f)." % gt.cycle_progress)
	
	# Keep NightManager in sync with GameTime
	is_time_paused = false


## ─── DEV MODE SETTINGS ─────────────────────────────────────────────────────
## Applies the starting world state based on is_dev_mode.
##
## If is_dev_mode is true:
##   - Player spawns with sprint, flashlight, key, and starting items
##   - Door is unlocked
##   - Fuse box is powered on
##   - Generator has fuel
##   - Entity AI is unrestricted
##
## If is_dev_mode is false (normal game):
##   - Player starts with NO sprint, NO flashlight, NO key, empty inventory
##   - Front door is locked
##   - Fuse box is broken
##   - Generator has 0% fuel
##   - Entity stays hidden
func _apply_dev_mode_settings() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if not player:
		print("[NightManager] Player not found for dev mode settings!")
		return
	
	if is_dev_mode:
		# ─── DEV MODE: Everything unlocked ──────────────────────────────
		print("[NightManager] DEV MODE: Applying unrestricted settings.")
		
		# Player abilities
		if "start_with_sprint" in player:
			player.start_with_sprint = true
		if "start_with_flashlight" in player:
			player.start_with_flashlight = true
		if "start_with_key" in player:
			player.start_with_key = true
		
		# Unlock the front door
		var doors = get_tree().get_nodes_in_group("Door")
		for d in doors:
			if "start_locked" in d:
				d.start_locked = false
				if "is_locked" in d:
					d.is_locked = false
				print("[NightManager] Dev Mode: Door '%s' unlocked." % d.name)
		
		# Power on the fuse box
		var fuse_box = _find_fuse_box()
		if fuse_box:
			fuse_box.start_broken = false
			fuse_box.current_state = 2  # BoxState.POWER_ON
			if fuse_box.has_method("_set_generator_state"):
				fuse_box._set_generator_state(true)
			print("[NightManager] Dev Mode: Fuse box powered on.")
		else:
			print("[NightManager] Dev Mode: No FuseBox found in scene.")
		
		# Fill the generator
		generator_fuel = max_fuel
		is_generator_on = true
		fuel_changed.emit(generator_fuel)
		generator_state_changed.emit(true)
		print("[NightManager] Dev Mode: Generator at 100% fuel.")
		
	else:
		# ─── NORMAL MODE: Locked down, player must work for everything ──
		print("[NightManager] NORMAL MODE: Applying locked-down settings.")
		
		if "start_with_sprint" in player:
			player.start_with_sprint = false
		if "start_with_flashlight" in player:
			player.start_with_flashlight = false
		if "start_with_key" in player:
			player.start_with_key = false
		
		if "starting_items" in player:
			player.starting_items.clear()
		
		var inv = get_node_or_null("/root/Inventory")
		if inv and inv.has_method("clear"):
			inv.clear()
			print("[NightManager] Normal Mode: Inventory cleared.")
		
		var doors = get_tree().get_nodes_in_group("Door")
		for d in doors:
			if "start_locked" in d:
				d.start_locked = true
				if "is_locked" in d:
					d.is_locked = true
				print("[NightManager] Normal Mode: Door '%s' locked." % d.name)
		
		var fuse_box = _find_fuse_box()
		if fuse_box:
			fuse_box.start_broken = true
			fuse_box.current_state = 0  # BoxState.BROKEN
			if fuse_box.has_method("_set_generator_state"):
				fuse_box._set_generator_state(false)
			print("[NightManager] Normal Mode: Fuse box broken.")
		else:
			print("[NightManager] Normal Mode: No FuseBox found in scene.")
		
		generator_fuel = 0.0
		is_generator_on = false
		fuel_changed.emit(generator_fuel)
		generator_state_changed.emit(false)
		print("[NightManager] Normal Mode: Generator at 0% fuel.")
		
		# Time was started by _start_time_running() when the player spawned
		# (called from _process() just before this method). The clock ticks
		# immediately on scene load — no door interaction required.
		print("[NightManager] Normal Mode: Time is RUNNING. Clock ticks immediately on scene load.")


## ─── SPAWN SYSTEM ──────────────────────────────────────────────────────────

## Teleports the player to the appropriate spawn marker based on dev mode.
func setup_player_spawn() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if not player:
		player = get_tree().get_first_node_in_group("Player")
	if not player:
		print("[NightManager] Player not found! Cannot set spawn position.")
		return
	
	var marker_name: String = "PlayerSpawnDev" if is_dev_mode else "PlayerSpawn"
	
	var spawn_marker: Marker3D = null
	var scene_root: Node = get_tree().current_scene
	if scene_root:
		spawn_marker = scene_root.get_node_or_null("PlayerSpawnpoints/" + marker_name) as Marker3D
		if not spawn_marker:
			spawn_marker = _find_marker_recursive(scene_root, marker_name)
	
	if spawn_marker:
		player.global_transform = spawn_marker.global_transform
		print("[NightManager] Spawned at %s: %s" % [marker_name, spawn_marker.global_position])
	else:
		print("[NightManager] Marker '%s' not found in current scene. Using fallback position." % marker_name)
		player.global_position = Vector3(9.0, 1.0, 0.4)


## Recursively searches for a Marker3D with the given name in the node tree.
func _find_marker_recursive(root: Node, name: String) -> Marker3D:
	for child in root.get_children():
		if child is Marker3D and child.name == name:
			return child as Marker3D
		var found = _find_marker_recursive(child, name)
		if found:
			return found
	return null



## ─── ONBOARDING SEQUENCE ───────────────────────────────────────────────────
func start_onboarding_sequence() -> void:
	if is_dev_mode:
		print("[NightManager] Dev Mode: SKIPPING Onboarding. Entity AI is unrestricted.")
		return
	
	print("[NightManager] Starting Day 1 Onboarding Sequence...")
	
	var horror_hud = get_node_or_null("/root/CottageHorror/HorrorHUD")
	if horror_hud:
		_hide_horror_ui_elements(horror_hud)
	
	_set_objective("Enter the cabin.")
	
	var routine_manager = get_node_or_null("/root/RoutineManager")
	if routine_manager and routine_manager.has_method("reset_all_phases"):
		routine_manager.reset_all_phases()
		print("[NightManager] RoutineManager phases reset for Day 1 onboarding.")
	else:
		print("[NightManager] RoutineManager not found or missing reset_all_phases().")



func _hide_horror_ui_elements(horror_hud: Node) -> void:
	if horror_hud.has_method("hide_confidence"):
		horror_hud.hide_confidence()
	if horror_hud.has_method("hide_sanity"):
		horror_hud.hide_sanity()
	
	if "confidence_bar" in horror_hud and horror_hud.confidence_bar:
		horror_hud.confidence_bar.visible = false
	if "sanity_bar" in horror_hud and horror_hud.sanity_bar:
		horror_hud.sanity_bar.visible = false
	
	print("[NightManager] Horror UI elements hidden for onboarding.")


func _set_objective(text: String) -> void:
	var labels = get_tree().get_nodes_in_group("objective_label")
	if not labels.is_empty():
		for label in labels:
			if label is Label:
				label.text = text
				print("[NightManager] Objective set via group: '%s'" % text)
				return
	
	var scene_root: Node = get_tree().current_scene
	if scene_root:
		var obj_label = scene_root.get_node_or_null("HUD/ObjectiveLabel")
		if obj_label and obj_label is Label:
			obj_label.text = text
			print("[NightManager] Objective set via fallback path: '%s'" % text)
			return
	
	print("[NightManager] Could not find objective label to set text: '%s'" % text)


func _apply_starting_fuel() -> void:
	var generators = get_tree().get_nodes_in_group("generator_controller")
	if not generators.is_empty():
		var gen = generators[0]
		if gen and "starting_fuel_percent" in gen:
			var fuel_pct = gen.starting_fuel_percent
			generator_fuel = max_fuel * (fuel_pct / 100.0)
			generator_fuel = clampf(generator_fuel, 0.0, max_fuel)
			print("[NightManager] Starting fuel set to %.1f%% (%.1f / %.1f) from Generator node." % [fuel_pct, generator_fuel, max_fuel])
		else:
			print("[NightManager] Generator node has no starting_fuel_percent. Using default: %.1f / %.1f" % [generator_fuel, max_fuel])
	else:
		print("[NightManager] No Generator node found. Using default fuel: %.1f / %.1f" % [generator_fuel, max_fuel])



func _find_game_time() -> void:
	_find_gt_attempts += 1
	if _find_gt_attempts > _MAX_FIND_GT_ATTEMPTS:
		print("NightManager: GameTime not found after %d attempts." % _MAX_FIND_GT_ATTEMPTS)
		return
	
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		_game_time = gt
		_game_time.night_started.connect(_on_game_night_started)
		_game_time.day_started.connect(_on_game_day_started)
		
		if current_night > 0 and not _game_time.is_day:
			start_night(current_night)
		print("NightManager: Connected to GameTime.")
	else:
		call_deferred("_find_game_time")



func _process(delta: float) -> void:
	# ─── THROTTLE OPTIMIZATION ──────────────────────────────────────────────
	# Night progression runs on simulated time, not frame time.
	# Updating at 5 Hz (0.2s intervals) is more than sufficient.
	_night_tick_timer += delta
	if _night_tick_timer < 0.2:
		return
	_night_tick_timer = 0.0

	if not _spawn_setup_done:
		var player = get_tree().get_first_node_in_group("player")
		if player:
			_spawn_setup_done = true
			_start_time_running()
			setup_player_spawn()
			_apply_dev_mode_settings()
			start_onboarding_sequence()
		return
	
	if not is_night_active and not is_day_active:
		return

	if _awaiting_door_lock:
		var _poll_player = get_tree().get_first_node_in_group("player") as Node3D
		if not _poll_player:
			_poll_player = get_tree().get_first_node_in_group("Player") as Node3D
		if _poll_player and _poll_player.has_method("get_player_room"):
			var room = _poll_player.get_player_room()
			if room == "HallRoom":
				_door_lock_delay_timer += delta
				if _door_lock_delay_timer >= 3.0:
					var door = get_tree().get_first_node_in_group("Door")
					if door and door.has_method("close_and_lock"):
						print("[NightManager] Calling door.close_and_lock(). is_open=%s" % str(door.is_open))
						door.close_and_lock()
						print("[NightManager] Player entered HallRoom. Door closed and locked after 3s delay.")
					elif door:
						print("[NightManager] Calling raw property close. is_open=%s" % str(door.is_open))
						door.is_open = false
						door.rotation_degrees.y = door.default_rotation_y
						door.is_locked = true
					_awaiting_door_lock = false
					_door_lock_delay_timer = 0.0
			else:
				_door_lock_delay_timer = 0.0

	if is_time_paused:
		return
	
	if _game_time:
		night_progress = _game_time.get_phase_progress()
	
	if is_night_active:
		if is_generator_on:
			# ─── TASK 2: OVERLOAD EXACT 3.0/s DRAIN ─────────────────────
			# This _process() block is throttled to 5 Hz (0.2s ticks, see
			# _night_tick_timer above). `delta` here is still the raw per-frame
			# delta (~0.016s), so draining `rate * delta` once per 0.2s tick
			# would run at only ~8% of the intended rate. We therefore scale
			# by the throttle interval (0.2s) so the math is exact:
			#   overload: 3.0 units/sec → 0.6 units per 0.2s tick
			#   baseline: current_drain_rate /sec → rate * 0.2 per tick
			const THROTTLE_INTERVAL: float = 0.2
			
			# While an overloaded portable trap lamp is active, the drain
			# rate is FORCED to exactly 3.0 units/sec (3% of max_fuel per
			# second → full tank in ~33.3s). The accumulated
			# current_drain_rate (base + lights + lamp 3.0) is bypassed so
			# baseline drains never stack on top, which previously emptied
			# the tank faster than the intended 3%/s.
			var overload_active: bool = false
			for lamp in get_tree().get_nodes_in_group("portable_trap"):
				if lamp and "is_overloaded" in lamp and lamp.is_overloaded:
					overload_active = true
					break
			
			if overload_active:
				generator_fuel -= 3.0 * THROTTLE_INTERVAL
			else:
				generator_fuel -= current_drain_rate * THROTTLE_INTERVAL
			generator_fuel = clampf(generator_fuel, 0.0, max_fuel)
			fuel_changed.emit(generator_fuel)
			
			if generator_fuel <= 0.0:
				is_generator_on = false
				generator_state_changed.emit(false)
				fuel_changed.emit(0.0)
				print("[Power Grid] Blackout! The generator has run completely out of fuel.")
				
				var entity = get_tree().get_first_node_in_group("entity")
				if entity and entity.has_method("on_generator_blackout"):
					entity.on_generator_blackout()

	
	if is_night_active:
		_event_timer += delta
		if _event_timer >= 5.0:
			_event_timer = 0.0
			_check_time_events()
	
	# ─── TASK 5: NIGHT 1 PEEKER FORCED SPAWN ─────────────────────────
	# The Night 1 Peeker is now a SCRIPTED, ONE-OFF event. The automatic
	# timer-based spawn (previously firing 5s into Night 1) has been
	# COMPLETELY REMOVED so the peeker can NEVER appear randomly during
	# Night 1. The ONLY trigger is RoutineManager.on_door_locked() when
	# the Day 1 "Lock the door" objective completes, which forces the
	# peeker specifically to the LivingRoom window via
	# PeekerManager.force_spawn_at_window("LivingRoom").



func _on_game_night_started() -> void:
	if current_night <= 0:
		current_night = 1
		print("[NightManager] Auto-bumped current_night from %d to 1 for first night transition. (Night 0 guard)" % current_night)
	
	if current_night <= 0:
		push_warning("[NightManager] _on_game_night_started() received invalid night=%d. Ignoring." % current_night)
		return
	
	start_night(current_night)


func _on_game_day_started() -> void:
	if not is_night_active:
		print("[NightManager] Ignoring spurious day_started — no night is active.")
		return
	
	# ─── SAVE ORIGINAL NIGHT BEFORE END ──────────────────────────────
	# end_current_night() bumps current_night by 1 after emitting
	# night_ended. We need the original value to determine which night
	# just ended for transition-specific logic like nest highlighting.
	var _ended_night = current_night
	
	end_current_night()

	if current_night >= 3:
		_apply_dawn_exhaustion()
	
	# ─── DAY 2 START: Trigger nest highlighting ──
	# When Night 1 ends and Day 2 begins, notify RoutineManager
	# so it can schedule the nest alpha highlight after 20 seconds.
	if _ended_night == 1:
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_day2_started"):
			rm.on_day2_started()


## ─── DAY 3+ DAWN EXHAUSTION ────────────────────────────────────────────────
func _apply_dawn_exhaustion() -> void:
	is_time_paused = true
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		gt.is_time_paused = true
		gt.is_running = false

	var player = get_tree().get_first_node_in_group("player") as Node3D
	if not player:
		player = get_tree().get_first_node_in_group("Player") as Node3D
	if player:
		player.is_exhausted = true
		print("[NightManager] Dawn exhaustion applied to player.")

	var player_is_outside = false
	if player and player.has_method("get_player_room"):
		var room = player.get_player_room()
		print("[NightManager] Dawn exhaustion: player room = '%s'" % room)
		if room == "Outside":
			player_is_outside = true
	
	if player_is_outside:
		print("[NightManager] Dawn exhaustion: Player is OUTSIDE at dawn. Deferred door lock NOT armed — player won't be locked out.")
		_awaiting_door_lock = false
	else:
		_awaiting_door_lock = true
		_door_lock_delay_timer = 0.0
		print("[NightManager] Dawn exhaustion: Deferred door lock armed. Waiting for player to reach HallRoom for 3 seconds.")

	_set_objective("I'm exhausted, I need to go to bed.")
	print("[NightManager] Day %d dawn exhaustion applied. Time is frozen." % current_night)


## Starts a specific night.
func start_night(night: int) -> void:
	if night <= 0:
		push_warning("[NightManager] start_night() called with invalid night=%d. Ignoring. (Night 0 guard)" % night)
		return
	
	current_night = night
	night_progress = 0.0
	_triggered_events.clear()
	_event_timer = 0.0
	_peeker_timer = 0.0
	_peeker_spawned = false
	is_day_active = false
	is_night_active = true
	
	# ─── VAN SEQUENCE OVERRIDE GUARD ──────────────────────────────────
	if not is_van_sequence_active:
		is_time_paused = false
		_force_game_time_to_night()
	else:
		print("[NightManager] VAN SEQUENCE ACTIVE: Skipping time unpause & GameTime sync. Bed script owns the clock.")
	
	# ─── DEFENSE-IN-DEPTH: RESET VAN FLAG FOR NIGHT 3+ ──────────────
	# If the van sequence flag somehow survived into Night 3+ (e.g., a
	# scene reload between Night 2 and Night 3 reset _night_2_van_sequence_resolved
	# but not is_van_sequence_active), force-clear it. The van narrative
	# is ONLY for Night 2.2 — it must never leak into late-game nights.
	if night >= 3:
		is_van_sequence_active = false
		print("[NightManager] Defense-in-depth: is_van_sequence_active forced false for Night %d." % night)
	
	# ─── TASK 3: CAPTURE INVENTORY CHECKPOINT (once per night) ─────
	# Snapshot the player's inventory at the TRUE start of the night.
	# The _checkpoint_saved guard ensures restart_night() (which re-enters
	# start_night()) does NOT overwrite the original snapshot with the
	# post-consumption state. The guard is cleared in end_current_night()
	# so the next genuine night cycle captures a fresh snapshot.
	if not _checkpoint_saved:
		var inv_snapshot: Node = get_node_or_null("/root/Inventory")
		if inv_snapshot and inv_snapshot.has_method("save_checkpoint"):
			inv_snapshot.save_checkpoint()
			_checkpoint_saved = true
			print("[NightManager] TASK 3: Inventory checkpoint captured for Night %d." % night)
	
	night_started.emit(night)
	
	recalculate_fuel_drain()
	
	if night == 1:
		tutorial_window_fixed = false
		van_sequence_started = false
		print("[NightManager] Tutorial window flag reset for Night 1. van_sequence_started cleared.")
	
	if night <= 2 and not is_dev_mode:
		print("Night %d: Entity remains hidden for the car alarm narrative event." % night)
	else:
		print("Night %d: Entity activation delegated to signal-connected _on_night_started()." % night)
	
	print("Night %d has begun..." % night)


func end_current_night() -> void:
	if not is_night_active:
		return
	is_night_active = false
	is_day_active = true
	night_ended.emit(current_night)
	
	get_tree().call_group("entity", "deactivate")
	
	# ─── TASK 3: CLEAR CHECKPOINT GUARD FOR NEXT NIGHT CYCLE ────────
	# The night genuinely ended (not a death restart). Clear the guard so
	# start_night() captures a FRESH inventory snapshot when the next
	# night begins — the previous snapshot is no longer relevant to the
	# upcoming cycle's restart checkpoint.
	_checkpoint_saved = false
	
	# ─── CLEAN UP PEEKER ────────────────────────────────────────────
	# If a Night 1 peeker is still active when the night ends (e.g. the
	# player never looked at it), force-remove it so it doesn't persist
	# into the day or subsequent nights.
	var pm = get_node_or_null("/root/PeekerManager")
	if pm and pm.has_method("remove_active_peeker"):
		pm.remove_active_peeker()
	
	print("Night %d has ended! Dawn breaks." % current_night)
	
	_clear_environment_pickups()
	_respawn_day_items()
	
	if current_night < total_nights:
		current_night += 1
		print("Preparing for Night %d..." % current_night)
	else:
		print("All nights survived! Game over.")


func _clear_environment_pickups() -> void:
	var spawner = get_node_or_null("/root/CottageHorror/ItemSpawner")
	if not spawner:
		spawner = get_node_or_null("/root/Main/ItemSpawner")
	if not spawner:
		return
	
	for child in spawner.get_children():
		if child is Marker3D:
			continue
		if child.has_method("queue_free"):
			child.queue_free()
	
	print("[Dawn Resupply] Cleared uncollected pickups from the environment.")


func _respawn_day_items() -> void:
	var spawner = get_node_or_null("/root/CottageHorror/ItemSpawner")
	if not spawner:
		spawner = get_node_or_null("/root/Main/ItemSpawner")
	if not spawner:
		return
	
	if spawner.has_method("_spawn_items"):
		spawner.call_deferred("_spawn_items")
		print("[Dawn Resupply] Spawned fresh survival items for the new cycle.")


func recalculate_fuel_drain() -> float:
	var generators = get_tree().get_nodes_in_group("generator_controller")
	if not generators.is_empty():
		var gen = generators[0]
		if gen and gen.has_method("calculate_total_drain"):
			current_drain_rate = gen.calculate_total_drain()
			return current_drain_rate
	
	var active_drain = base_fuel_drain
	var lights = get_tree().get_nodes_in_group("CabinLights")
	
	for light in lights:
		if "is_switched_on" in light and light.is_switched_on and is_generator_on:
			active_drain += light.energy_drain_rate
	
	current_drain_rate = active_drain
	return current_drain_rate


func _check_time_events() -> void:
	var progress = night_progress
	
	match current_night:
		1:
			pass
		2:
			if progress > 0.3 and not "entity_glimpse" in _triggered_events:
				_trigger_event("entity_glimpse")
			if progress > 0.7 and not "door_creak" in _triggered_events:
				_trigger_event("door_creak")
		3:
			if progress > 0.2 and not "entity_inside" in _triggered_events:
				_trigger_event("entity_inside")
			if progress > 0.5 and not "object_moved" in _triggered_events:
				_trigger_event("object_moved")
			if progress > 0.8 and not "footsteps" in _triggered_events:
				_trigger_event("footsteps")
		4:
			if progress > 0.1 and not "entity_appears" in _triggered_events:
				_trigger_event("entity_appears")
			if progress > 0.4 and not "lights_flicker" in _triggered_events:
				_trigger_event("lights_flicker")
			if progress > 0.7 and not "entity_charge" in _triggered_events:
				_trigger_event("entity_charge")
		5:
			if progress > 0.1 and not "entity_constant" in _triggered_events:
				_trigger_event("entity_constant")
			if progress > 0.4 and not "poltergeist" in _triggered_events:
				_trigger_event("poltergeist")
			if progress > 0.8 and not "final_confrontation" in _triggered_events:
				_trigger_event("final_confrontation")


## Synchronizes GameTime to the start of the night phase.
## Night 1 starts at 00:00 (dusk, progress=0.5) and ticks normally.
## When the clock reaches 02:00 (progress=0.7), it automatically freezes
## so the peeker and car alarm narrative play out. This gives the player
## a natural dusk-to-night transition instead of an instant pitch-black sky.
##
## CLOCK MATH:
##   Night starts at progress 0.5 (00:00). 02:00 = 0.7 progress.
##   Each minute of real time advances the night by 0.1 progress.
func _force_game_time_to_night() -> void:
	var gt = get_node_or_null("/root/GameTime")
	if not gt:
		return
	
	# ─── START AT DUSK ─────────────────────────────────────────────
	# Night begins at 00:00 (progress=0.5). The clock ticks forward
	# normally until it reaches 02:00 (progress=0.7), then pauses.
	gt.cycle_progress = 0.5
	gt._elapsed = 0.5 * gt.cycle_duration
	gt.is_day = false
	gt._was_day = false
	
	# ─── LET TIME TICK NORMALLY ─────────────────────────────────────
	# The clock advances in game_time.gd's _process() tick at 0.2s intervals.
	# When it reaches 0.7 (02:00), game_time.gd will automatically pause
	# via the _night_1_freeze_trigger check we add below.
	gt.is_time_paused = false
	gt.is_running = true
	
	gt.time_changed.emit(0.5)
	print("[NightManager] GameTime synced to night phase (progress=0.5 = 00:00 dusk). Time is RUNNING.")


func _trigger_event(event_name: String) -> void:
	_triggered_events.append(event_name)
	horror_event.emit(event_name)
	
	if event_name == "lights_flicker":
		print("[Horror Event] LIGHTS FLICKER! The cabin lights are flickering! Night %d at progress %.0f%%" % [current_night, night_progress * 100.0])
	else:
		print("Horror event: %s" % event_name)


func _trigger_night_1_peeker() -> void:
	var pm = get_node_or_null("/root/PeekerManager")
	if pm and pm.has_method("spawn_night_1_peeker"):
		pm.spawn_night_1_peeker()
		print("[NightManager] Night 1 Peeker event triggered after %.1f seconds." % PEEKER_SPAWN_DELAY)
	else:
		print("[NightManager] PeekerManager not found! Cannot spawn Night 1 Peeker.")


## ─── DAY 1 ONBOARDING: UNPAUSE TIME ────────────────────────────────────────
func unpause_time() -> void:
	if not is_time_paused:
		print("[NightManager] Time is already unpaused. Ignoring duplicate call.")
		return
	
	is_time_paused = false
	
	var gt: Node = get_node_or_null("/root/GameTime")
	if gt and gt.has_method("unpause_time"):
		gt.unpause_time()
		gt.is_running = true
		print("[NightManager] GameTime unpaused. Clock continues from current time.")
	
	print("[NightManager] Time unpaused! The Day 1 onboarding clock is now running.")



func trigger_first_chase() -> void:
	print("[NightManager] First chase triggered! Entity is arriving.")
	
	# ─── VAN SEQUENCE FLAG LIFECYCLE (CORRECTED) ─────────────────────
	# NOTE: We deliberately do NOT clear is_van_sequence_active here.
	# The flag must remain true THROUGH the cabin-entry FLINCH so the
	# Director's Tier 5 gate (FLINCH completion → DORMANT) can detect
	# the end of the van narrative and force the Entity dormant.
	# If we cleared it here (as the old documentation implied), the
	# flag would be false by the time the player enters the cabin and
	# the FLINCH finishes — the Tier 5 DORMANT gate would never fire,
	# and the Entity would oscillate between OBSERVE/STALK/FINCH.
	#
	# The flag is cleared by:
	#   1. The Director's Tier 5 DORMANT gate (primary, at cabin entry
	#      + FLINCH resolution)
	#   2. start_night() for night >= 3 (defense-in-depth)
	var hsm = get_node_or_null("/root/HorrorSoundManager")
	if hsm and hsm.has_method("play_distant_monster"):
		hsm.play_distant_monster()
	
	first_chase_started.emit()


func advance_night() -> void:
	print("[NightManager] advance_night() called. Advancing from Night %d..." % current_night)
	
	# ─── SAVE NIGHT NUMBER BEFORE BRANCH ─────────────────────────────
	# end_current_night() bumps current_night by 1, and the else branch
	# calls it. We need the original value to determine the new day's
	# target progress. Save it here BEFORE the branch.
	var _original_night: int = current_night
	
	# ─── PHASE TRANSITION ──────────────────────────────────────────────
	# Emit the night_ended signal FIRST so all listeners (RoutineManager,
	# the Entity, etc.) can react to the transition. Only THEN do we
	# set the authoritative time for the new day. This prevents signal
	# handlers from clobbering the time reset.
	
	if current_night == 0:
		# Transition: Day 1 → Day 2 (survived Night 1)
		current_night = 1
		is_day_active = true
		night_ended.emit(1)
		print("[NightManager] Transitioned from Day 1 to Day 2 (current_night = 1). Night 1 survived!")
	else:
		end_current_night()
	
	# ─── TRIGGER NEST HIGHLIGHTING ON DAY 2 ──────────────────────────
	# _original_night == 1 means Night 1 just ended and Day 2 is starting.
	# This must run AFTER the if/else branch because:
	#   - The natural cycle path sets current_night to 1 via _on_game_night_started,
	#     so the `current_night == 0` branch is NEVER taken during real gameplay.
	#   - The else branch calls end_current_night() which bumps current_night to 2.
	#   - _original_night was saved BEFORE the branch, so it correctly holds 1.
	# This single location covers BOTH code paths (first-time and natural) and
	# ensures on_day2_started() fires exactly when Night 1 transitions to Day 2.
	if _original_night == 1:
		var _rm_day2: Node = get_node_or_null("/root/RoutineManager")
		if _rm_day2 and _rm_day2.has_method("on_day2_started"):
			_rm_day2.on_day2_started()
	
	# ─── AUTHORITATIVE TIME RESET ─────────────────────────────────────
	# Set the new day's start time in a SINGLE block, after all signals
	# have been processed.
	#   - Day 2 (original_night == 0 or 1): cycle_progress = 0.0 (00:00)
	#   - Day 3+ (original_night >= 2): cycle_progress = 0.125 (morning)
	# We use _original_night (saved BEFORE the branch) because the branch
	# may have already bumped current_night via end_current_night().
	is_time_paused = false
	var gt: Node = get_node_or_null("/root/GameTime")
	if gt:
		var target_progress: float = 0.0 if _original_night <= 1 else 0.125
		
		gt.cycle_progress = target_progress
		gt._elapsed = gt.cycle_progress * gt.cycle_duration
		gt.is_day = true
		gt._was_day = true
		gt.is_time_paused = false
		gt.is_running = true
		gt.time_changed.emit(target_progress)
		print("[NightManager] Day %d time forced to cycle_progress=%.3f. (original_night=%d)" % [current_night, target_progress, _original_night])
	
	# ─── RESET ROUTINEMANAGER OBJECTIVE HISTORY ──────────────────────
	# Clear the Day 1 gating state so the notebook doesn't repopulate
	# with "Go to bed" or other stale Day 1 objectives on Day 2+.
	var rm: Node = get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("reset_objective_history"):
		rm.reset_objective_history()
		print("[NightManager] RoutineManager objective history reset for new day.")
	
	print("[NightManager] Advanced to Day %d. Preparing for Night %d..." % [current_night, current_night + 1])


func restart_night() -> void:
	print("[NightManager] Restarting Night %d..." % current_night)
	
	is_night_active = false
	is_day_active = false
	night_progress = 0.0
	_triggered_events.clear()
	_event_timer = 0.0
	
	is_generator_on = true
	generator_fuel = max_fuel
	fuel_changed.emit(generator_fuel)
	generator_state_changed.emit(true)
	
	# ─── TASK 3: RESTORE INVENTORY TO CHECKPOINT ─────────────────────
	# The player died during the night — restore the inventory to the exact
	# state captured at night start (Inventory.save_checkpoint()). This
	# reverts any consumed items (e.g. the Cable Spool connected to the
	# generator) so nothing is permanently lost. The _checkpoint_saved
	# guard in start_night() prevents this restore from being overwritten
	# by a fresh (post-consumption) snapshot.
	var inv_restore: Node = get_node_or_null("/root/Inventory")
	if inv_restore and inv_restore.has_method("reset_to_checkpoint"):
		inv_restore.reset_to_checkpoint()
		print("[NightManager] TASK 3: Inventory restored to checkpoint snapshot.")
	
	# ─── TASK 3: RESET ENTITY CONFIDENCE ─────────────────────────────
	# The Entity's confidence must return to its baseline after a defeat.
	# EntityConfidence.reset() zeroes confidence and clears all modifiers,
	# so the restarted night begins from the default state instead of the
	# escalated value the Entity had accumulated when it caught the player.
	_reset_entity_confidence()
	
	var gt = get_node_or_null("/root/GameTime")
	if gt and gt.has_method("reset_to_night_start"):
		gt.reset_to_night_start()
	
	start_night(current_night)


## ─── TASK 3: RESET ENTITY CONFIDENCE ────────────────────────────────
## Finds the Entity (group "entity") and resets its confidence module to
## the default baseline. EntityConfidence.reset() zeroes the current value
## AND clears all active continuous modifiers, so the Entity's boldness is
## fully restored on restart rather than carrying over from the failed night.
func _reset_entity_confidence() -> void:
	var entity_nodes: Array[Node] = get_tree().get_nodes_in_group("entity")
	for entity_node in entity_nodes:
		if not entity_node:
			continue
		var conf = null
		if entity_node.has_method("get_confidence_module"):
			conf = entity_node.get_confidence_module()
		elif entity_node.has_node("EntityConfidence"):
			conf = entity_node.get_node("EntityConfidence")
		if conf and conf.has_method("reset"):
			conf.reset()
			print("[NightManager] TASK 3: Entity confidence reset to baseline (%s)." % entity_node.name)
		else:
			print("[NightManager] TASK 3: Entity confidence module not found on '%s'." % (entity_node.name if entity_node else "null"))


## FEATURE 1 — "Restart from Checkpoint" death-menu option.
## Branch on the current phase:
##   - Night active → reset to the EXACT start of the current night
##     (GameTime back to dusk + start_night(current_night), restoring the
##     state/time the night began).
##   - Day active → reset to the beginning of the current day
##     (morning baseline, player in bed, world reset).
func restart_from_checkpoint() -> void:
	if is_night_active:
		print("[NightManager] Restart from checkpoint: NIGHT %d active — resetting to night start." % current_night)
		restart_night()
	else:
		print("[NightManager] Restart from checkpoint: Day active — resetting to day start.")
		restart_from_morning()
	
	# FOLLOW-UP 1: Always place the player on PlayerSpawnDev after a defeat/
	# restart, regardless of whether the checkpoint branch reset the night or
	# the day. This guarantees a consistent, clean-facing spawn with a fully
	# reset camera.
	_spawn_player_at("PlayerSpawnDev")


## Teleports the player to a named PlayerSpawnpoints marker (with recursive
## fallback), then fully resets the camera so the player is not left facing
## a stale direction. Returns true on success.
func _spawn_player_at(marker_name: String) -> bool:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if not player:
		player = get_tree().get_first_node_in_group("Player") as Node3D
	if not player:
		print("[NightManager] _spawn_player_at(): Player not found in groups 'player'/'Player'.")
		return false
	
	var spawn_marker: Marker3D = null
	var scene_root: Node = get_tree().current_scene
	if scene_root:
		spawn_marker = scene_root.get_node_or_null("PlayerSpawnpoints/" + marker_name) as Marker3D
		if not spawn_marker:
			spawn_marker = _find_marker_recursive(scene_root, marker_name)
	
	if spawn_marker:
		player.global_transform = spawn_marker.global_transform
		if player.has_method("reset_camera"):
			player.reset_camera()
		print("[NightManager] Player spawned at '%s': %s" % [marker_name, spawn_marker.global_position])
		return true
	
	print("[NightManager] Marker '%s' not found in current scene. Using fallback position." % marker_name)
	player.global_position = Vector3(9.0, 1.0, 0.4)
	if player.has_method("reset_camera"):
		player.reset_camera()
	return false


func restart_from_morning() -> void:
	print("[NightManager] restart_from_morning() — Resetting to morning baseline of Day %d." % current_night)
	
	var gt: Node = get_node_or_null("/root/GameTime")
	if gt and gt.has_method("set_progress"):
		gt.set_progress(0.125)
		print("[NightManager] Time reset to morning (progress: 0.125).")
	
	var ec: Node = get_node_or_null("/root/CottageHorror/EnvironmentController")
	if not ec:
		ec = get_node_or_null("/root/Main/EnvironmentController")
	if ec and ec.has_method("_apply_cycle"):
		ec._apply_cycle()
		print("[NightManager] EnvironmentController refreshed to daytime lighting.")
	
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player:
		var spawn_marker: Node3D = get_tree().get_first_node_in_group("BedroomSpawn") as Node3D
		if not spawn_marker:
			spawn_marker = get_tree().get_first_node_in_group("PlayerSpawn") as Node3D
		if not spawn_marker:
			spawn_marker = get_tree().current_scene.get_node_or_null("BedroomSpawn") as Node3D
		
		if spawn_marker:
			player.global_position = spawn_marker.global_position
		else:
			player.global_position = Vector3(9.0, 1.0, 0.4)
		
		# ─── RESET CAMERA ──────────────────────────────────────────────
		# The jumpscare mechanic may have tilted the camera (h_offset, v_offset,
		# global_transform.basis, FOV). Call reset_camera() to restore defaults
		# so the player doesn't see an askew view on respawn.
		if player.has_method("reset_camera"):
			player.reset_camera()
		
		if player.has_method("reset_health"):
			player.reset_health()
		elif "health" in player:
			player.health = 100.0
		if "sanity" in player:
			player.sanity = 100.0
		
		var flashlight: Node = player.find_child("*Flashlight*", true, false)
		if flashlight:
			if flashlight.has_method("set_battery_level"):
				flashlight.set_battery_level(100.0)
			elif "battery_level" in flashlight:
				flashlight.battery_level = 100.0
	
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv:
		inv.clear()
		
		var battery_res: Resource = load("res://resources/battery_resource.tres")
		var plank_res: Resource = load("res://resources/plank_resource.tres")
		var fuel_can_res: Resource = load("res://resources/fuel_can_resource.tres")
		var fuse_res: Resource = load("res://resources/fuse_resource.tres")
		
		for i in range(3):
			if battery_res and inv.has_method("add_item"):
				inv.add_item(battery_res.duplicate())
		for i in range(2):
			if plank_res and inv.has_method("add_item"):
				inv.add_item(plank_res.duplicate())
		for i in range(2):
			if fuel_can_res and inv.has_method("add_item"):
				inv.add_item(fuel_can_res.duplicate())
		if fuse_res and inv.has_method("add_item"):
			inv.add_item(fuse_res.duplicate())
		
		print("[NightManager] Inventory reset to baseline morning items.")
	
	var traps: Array[Node] = get_tree().get_nodes_in_group("portable_trap")
	for trap in traps:
		if trap and is_instance_valid(trap):
			trap.queue_free()
	
	var cables: Array[Node] = get_tree().get_nodes_in_group("power_cable")
	for cable in cables:
		if cable and is_instance_valid(cable):
			cable.queue_free()
	
	var fuse_box: Node = _find_fuse_box()
	if fuse_box:
		fuse_box.current_state = 0
		if fuse_box.has_method("_set_generator_state"):
			fuse_box._set_generator_state(false)
	
	var cabin_lights: Array[Node] = get_tree().get_nodes_in_group("CabinLights")
	for light in cabin_lights:
		if "is_switched_on" in light:
			light.is_switched_on = false
		if "turn_off" in light:
			light.turn_off()
	
	is_generator_on = false
	generator_fuel = max_fuel
	fuel_changed.emit(generator_fuel)
	generator_state_changed.emit(false)
	
	var entity_nodes: Array[Node] = get_tree().get_nodes_in_group("entity")
	for entity_node in entity_nodes:
		if entity_node and entity_node.has_method("deactivate"):
			entity_node.deactivate()
	
	# ─── TASK 3: RESET ENTITY CONFIDENCE ON MORNING RESTART ────────
	# The morning baseline path must also reset the Entity's confidence so
	# a failed night doesn't leak escalated boldness into the next cycle.
	_reset_entity_confidence()
	
	is_night_active = false
	is_day_active = true
	night_progress = 0.0
	_triggered_events.clear()
	_event_timer = 0.0
	
	print("[NightManager] Morning restart complete. Player is safe in bed.")


func reset_to_daybreak() -> void:
	print("[NightManager] reset_to_daybreak() — Resetting to morning baseline of Day %d." % current_night)
	
	var gt: Node = get_node_or_null("/root/GameTime")
	if gt and gt.has_method("set_progress"):
		if current_night == 1:
			gt.set_progress(0.25)
		else:
			gt.set_progress(0.125)
		print("[NightManager] Time reset to morning (progress: %.3f)." % gt.cycle_progress)
	
	var ec: Node = get_node_or_null("/root/CottageHorror/EnvironmentController")
	if not ec:
		ec = get_node_or_null("/root/Main/EnvironmentController")
	if ec and ec.has_method("_apply_cycle"):
		ec._apply_cycle()
		print("[NightManager] EnvironmentController refreshed to daytime lighting.")
	
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player:
		var spawn_marker: Node3D = get_tree().get_first_node_in_group("BedroomSpawn") as Node3D
		if not spawn_marker:
			spawn_marker = get_tree().get_first_node_in_group("PlayerSpawn") as Node3D
		if not spawn_marker:
			spawn_marker = get_tree().current_scene.get_node_or_null("BedroomSpawn") as Node3D
		
		if spawn_marker:
			player.global_position = spawn_marker.global_position
			print("[NightManager] Player teleported to spawn: ", spawn_marker.global_position)
		else:
			player.global_position = Vector3(9.0, 1.0, 0.4)
			print("[NightManager] No spawn marker found. Using fallback position.")
		
		if player.has_method("reset_health"):
			player.reset_health()
		elif "health" in player:
			player.health = 100.0
		if "sanity" in player:
			player.sanity = 100.0
		print("[NightManager] Player health/sanity reset to 100%.")
		
		var flashlight: Node = player.find_child("*Flashlight*", true, false)
		if flashlight:
			if flashlight.has_method("set_battery_level"):
				flashlight.set_battery_level(100.0)
			elif "battery_level" in flashlight:
				flashlight.battery_level = 100.0
			print("[NightManager] Flashlight battery restored to 100%.")
		
		# ─── CAMERA RESET: Fix jumpscare-tainted rotation ────────────
		# BUG 4 FIX: Delegate to player_controller.reset_camera() instead of
		# independently re-writing the camera basis/rotation here. The old
		# inline block transferred yaw into the body capsule and re-set the
		# holder basis, which fought with (and duplicated) the player's own
		# reset_camera() logic and could leave body/holder yaw inconsistent
		# (camera facing wrong way after restart, then spinning out).
		# reset_camera() now zeroes BOTH the body yaw AND the camera holder
		# local rotation so body + camera are perfectly aligned on respawn.
		if player.has_method("reset_camera"):
			player.reset_camera()
			print("[NightManager] Camera reset delegated to player.reset_camera().")
		
		# Re-enable player input and capture mouse
		if player.has_method("set_process_input"):
			player.set_process_input(true)
		if player.has_method("set_physics_process"):
			player.set_physics_process(true)
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv:
		inv.clear()
		print("[NightManager] Inventory wiped.")
		
		var battery_res: Resource = load("res://resources/battery_resource.tres")
		var plank_res: Resource = load("res://resources/plank_resource.tres")
		var fuel_can_res: Resource = load("res://resources/fuel_can_resource.tres")
		var fuse_res: Resource = load("res://resources/fuse_resource.tres")
		
		for i in range(3):
			if battery_res and inv.has_method("add_item"):
				inv.add_item(battery_res.duplicate())
		
		for i in range(2):
			if plank_res and inv.has_method("add_item"):
				inv.add_item(plank_res.duplicate())
		
		for i in range(2):
			if fuel_can_res and inv.has_method("add_item"):
				inv.add_item(fuel_can_res.duplicate())
		
		if fuse_res and inv.has_method("add_item"):
			inv.add_item(fuse_res.duplicate())
		
		print("[NightManager] Baseline morning items added: 3 Batteries, 2 Planks, 2 Fuel Cans, 1 Fuse.")
	
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
	
	var fuse_box: Node = _find_fuse_box()
	if fuse_box:
		fuse_box.current_state = 0
		if fuse_box.has_method("_set_generator_state"):
			fuse_box._set_generator_state(false)
		print("[NightManager] FuseBox reset to BROKEN. Generator turned off.")
	
	var cabin_lights: Array[Node] = get_tree().get_nodes_in_group("CabinLights")
	for light in cabin_lights:
		if "is_switched_on" in light:
			light.is_switched_on = false
		if "turn_off" in light:
			light.turn_off()
	print("[NightManager] All cabin lights turned off.")
	
	is_generator_on = false
	generator_fuel = max_fuel
	fuel_changed.emit(generator_fuel)
	generator_state_changed.emit(false)
	print("[NightManager] Generator fuel reset to %.1f (off state)." % max_fuel)
	
	var entity_nodes: Array[Node] = get_tree().get_nodes_in_group("entity")
	for entity_node in entity_nodes:
		if entity_node and entity_node.has_method("deactivate"):
			entity_node.deactivate()
			print("[NightManager] Entity deactivated to DORMANT.")
	
	is_night_active = false
	is_day_active = true
	night_progress = 0.0
	_triggered_events.clear()
	_event_timer = 0.0
	
	print("[NightManager] Daybreak reset complete. Player is safe in bed.")
	
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


func _find_fuse_box():
	var scene_root = get_tree().current_scene
	if not scene_root:
		return null
	return _find_fuse_box_recursive(scene_root)


func _find_fuse_box_recursive(root: Node):
	for child in root.get_children():
		if child is FuseBox:
			return child
		var found = _find_fuse_box_recursive(child)
		if found:
			return found
	return null


func get_intensity() -> float:
	var night_factor = float(current_night) / float(total_nights)
	var time_factor = night_progress
	return min(1.0, night_factor * 0.6 + time_factor * 0.4)
