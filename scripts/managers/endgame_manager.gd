extends Node

## EndgameManager — Global singleton that tracks the game's ending conditions
## and orchestrates the transition from gameplay to the ending sequences.
##
## Three possible endings:
##   SURVIVAL — The player survived until dawn (all nights completed).
##   PURGE    — The player successfully destroyed the TotemAnchor.
##   DEATH    — The player was caught by the Entity.
##
## INTEGRATION:
##   - NightManager emits night_ended → we check if all nights are done → SURVIVAL
##   - TotemAnchor calls trigger_purge_ending() → PURGE
##   - JumpscareManager calls trigger_death_ending() → DEATH
##
## USAGE:
##   var em = get_node("/root/EndgameManager")
##   em.trigger_purge_ending()

signal ending_triggered(ending: Ending)
signal ending_sequence_started(ending: Ending)
signal ending_sequence_completed(ending: Ending)

## The three possible endings the player can achieve.
enum Ending {
	SURVIVAL,    # Survived until dawn (all 5 nights) without engaging the Totem
	PURGE,       # Successfully destroyed the TotemAnchor
	DEATH,       # Caught by the Entity
}

## Human-readable names for each ending (used for debug logging and UI).
const ENDING_NAMES: Dictionary = {
	Ending.SURVIVAL: "Survival",
	Ending.PURGE: "Purge",
	Ending.DEATH: "Death",
}

## The ending that was triggered (NONE until one fires).
var current_ending: Ending = -1 as Ending

## Whether an ending has been triggered (prevents double-triggers).
var is_ending_active: bool = false

## Whether the ending sequence is currently playing (cinematic, fade, etc.).
var is_sequence_playing: bool = false

## Reference to NightManager for detecting all-nights-survived.
var _night_manager: Node = null

## Reference to RoutineManager for detecting totem purge completion.
var _routine_manager: Node = null


func _ready() -> void:
	print("[EndgameManager] Initialized. Waiting for ending conditions.")
	
	# Connect to NightManager to detect when all nights are survived.
	_night_manager = get_node_or_null("/root/NightManager")
	if _night_manager:
		_night_manager.night_ended.connect(_on_night_ended)
		print("[EndgameManager] Connected to NightManager.")
	else:
		# Retry next frame — NightManager might not be ready yet
		call_deferred("_find_night_manager")
	
	# Connect to RoutineManager to detect totem purge completion.
	_routine_manager = get_node_or_null("/root/RoutineManager")
	if _routine_manager:
		_routine_manager.routine_step_changed.connect(_on_routine_step_changed)
		print("[EndgameManager] Connected to RoutineManager.")
	else:
		call_deferred("_find_routine_manager")


func _find_night_manager() -> void:
	_night_manager = get_node_or_null("/root/NightManager")
	if _night_manager:
		_night_manager.night_ended.connect(_on_night_ended)
		print("[EndgameManager] Connected to NightManager (deferred).")
	else:
		call_deferred("_find_night_manager")


func _find_routine_manager() -> void:
	_routine_manager = get_node_or_null("/root/RoutineManager")
	if _routine_manager:
		_routine_manager.routine_step_changed.connect(_on_routine_step_changed)
		print("[EndgameManager] Connected to RoutineManager (deferred).")
	else:
		call_deferred("_find_routine_manager")


## ─── ENDING TRIGGERS ──────────────────────────────────────────────────

## Called by NightManager when a night ends.
## If all 5 nights have been completed, triggers the SURVIVAL ending.
func _on_night_ended(night: int) -> void:
	if is_ending_active:
		return
	
	if _night_manager and night >= _night_manager.total_nights:
		_trigger_ending(Ending.SURVIVAL)


## Called by RoutineManager when the routine step advances.
## If the step advances to the totem-destroyed state, triggers the PURGE ending.
func _on_routine_step_changed(step: int, _objective_text: String) -> void:
	if is_ending_active:
		return
	
	# The RoutineManager advances to step 5 when the totem is destroyed.
	# (Step 0-4 are the bedtime routine; step 5 is the totem purge completion.)
	if step >= 5:
		_trigger_ending(Ending.PURGE)


## Public API: Called by TotemAnchor when the player successfully destroys the totem.
## Triggers the PURGE ending immediately.
func trigger_purge_ending() -> void:
	if is_ending_active:
		print("[EndgameManager] Ending already active. Ignoring duplicate PURGE trigger.")
		return
	_trigger_ending(Ending.PURGE)


## Public API: Called by JumpscareManager when the player is caught by the Entity.
## Triggers the DEATH ending immediately.
func trigger_death_ending() -> void:
	if is_ending_active:
		print("[EndgameManager] Ending already active. Ignoring duplicate DEATH trigger.")
		return
	_trigger_ending(Ending.DEATH)


## ─── INTERNAL ─────────────────────────────────────────────────────────

## Internal trigger that fires the ending sequence.
## Guards against double-triggers and logs the event.
func _trigger_ending(ending: Ending) -> void:
	if is_ending_active:
		print("[EndgameManager] Ending already active. Ignoring duplicate trigger: ", ENDING_NAMES.get(ending, "UNKNOWN"))
		return
	
	is_ending_active = true
	current_ending = ending
	print("[EndgameManager] ═══════════════════════════════════════════")
	print("[EndgameManager] 🏁 ENDING TRIGGERED: ", ENDING_NAMES.get(ending, "UNKNOWN"))
	print("[EndgameManager] ═══════════════════════════════════════════")
	
	ending_triggered.emit(ending)
	
	# Begin the ending sequence (cinematic, fade, etc.)
	_play_ending_sequence(ending)


## Path to the ending screen scene.
const ENDING_SCREEN_PATH: String = "res://scenes/ui/ending_screen.tscn"

## Reference to the instantiated ending screen (if any).
var _ending_screen_instance: Node = null


## Plays the ending sequence for the given ending type.
## Instantiates the EndingScreen overlay, pauses the game, frees the mouse,
## and waits for the player to choose Retry or Main Menu.
func _play_ending_sequence(ending: Ending) -> void:
	if is_sequence_playing:
		return
	
	is_sequence_playing = true
	ending_sequence_started.emit(ending)
	
	print("[EndgameManager] Playing ending sequence for: ", ENDING_NAMES.get(ending, "UNKNOWN"))
	
	# ─── ENDING-SPECIFIC LOGIC ───────────────────────────────────────
	match ending:
		Ending.SURVIVAL:
			print("[EndgameManager] SURVIVAL: All nights survived! The dawn breaks.")
		
		Ending.PURGE:
			print("[EndgameManager] PURGE: The Totem is destroyed! The Entity is banished.")
		
		Ending.DEATH:
			print("[EndgameManager] DEATH: The Entity caught the player.")
	
	# ─── INSTANTIATE ENDING SCREEN ──────────────────────────────────
	# Load and instance the ending screen overlay.
	var ending_scene = load(ENDING_SCREEN_PATH)
	if not ending_scene:
		print("[EndgameManager] ERROR: Could not load ending screen scene: ", ENDING_SCREEN_PATH)
		_complete_ending_sequence(ending)
		return
	
	_ending_screen_instance = ending_scene.instantiate()
	if not _ending_screen_instance:
		print("[EndgameManager] ERROR: Could not instantiate ending screen.")
		_complete_ending_sequence(ending)
		return
	
	# Add it to the scene tree (as a sibling of the current scene root so it
	# renders on top of everything, including the HUD CanvasLayer).
	get_tree().current_scene.add_child(_ending_screen_instance)
	
	# Configure the ending screen with the correct title/subtitle
	if _ending_screen_instance.has_method("setup_ending"):
		_ending_screen_instance.setup_ending(ending)
	
	# ─── PAUSE & FREE CURSOR ────────────────────────────────────────
	# Pause the game so the player can't move while the ending screen is up.
	# The EndingScreen has process_mode = PROCESS_MODE_ALWAYS so it still
	# processes input and animations while paused.
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	print("[EndgameManager] Game paused. Ending screen displayed.")
	
	# The ending screen handles Retry/MainMenu itself via change_scene_to_file,
	# so we don't need to wait here. The sequence is effectively complete once
	# the screen is shown.
	_complete_ending_sequence(ending)


## Completes the ending sequence and cleans up.
func _complete_ending_sequence(ending: Ending) -> void:
	print("[EndgameManager] Ending sequence completed for: ", ENDING_NAMES.get(ending, "UNKNOWN"))
	is_sequence_playing = false
	ending_sequence_completed.emit(ending)


## Returns a human-readable name for the given ending enum value.
func get_ending_name(ending: Ending) -> String:
	return ENDING_NAMES.get(ending, "Unknown")


## Returns true if the given ending has been triggered.
func has_ending_triggered(ending: Ending) -> bool:
	return is_ending_active and current_ending == ending


## Resets the EndgameManager to its initial state.
## Called when the game is restarted from the main menu.
func reset() -> void:
	current_ending = -1 as Ending
	is_ending_active = false
	is_sequence_playing = false
	print("[EndgameManager] Reset to initial state.")
