extends Node

## EndgameManager — Global singleton that tracks the game's ending conditions
## and orchestrates the transition from gameplay to the ending sequences.
##
## Three possible endings:
##   DEATH           — The player was caught by the Entity. (BAD)
##   ESCAPE_MEDIOCRE — The player repaired the van and escaped, but did NOT
##                     destroy the TotemAnchor. The Entity is still out there.
##   ESCAPE_GOOD     — The player repaired the van AND destroyed the TotemAnchor
##                     before escaping. The Entity is banished.
##
## INTEGRATION:
##   - JumpscareManager calls trigger_death_ending() → DEATH
##   - EscapeVan calls start_ending_sequence(totem_destroyed) → ESCAPE_GOOD or ESCAPE_MEDIOCRE
##
## USAGE:
##   var em = get_node("/root/EndgameManager")
##   em.trigger_death_ending()

signal ending_triggered(ending: Ending)
signal ending_sequence_started(ending: Ending)
signal ending_sequence_completed(ending: Ending)

## The three possible endings the player can achieve.
enum Ending {
	DEATH,           # Caught by the Entity (BAD)
	ESCAPE_MEDIOCRE, # Repaired the van and escaped, but did NOT destroy the Totem
	ESCAPE_GOOD,     # Repaired the van AND destroyed the Totem before escaping
}

## Human-readable names for each ending (used for debug logging and UI).
const ENDING_NAMES: Dictionary = {
	Ending.DEATH: "Death",
	Ending.ESCAPE_MEDIOCRE: "Escape (Mediocre)",
	Ending.ESCAPE_GOOD: "Escape (Good)",
}

## The ending that was triggered (NONE until one fires).
var current_ending: Ending = -1 as Ending

## Whether an ending has been triggered (prevents double-triggers).
var is_ending_active: bool = false

## Whether the ending sequence is currently playing (cinematic, fade, etc.).
var is_sequence_playing: bool = false


func _ready() -> void:
	print("[EndgameManager] Initialized. Waiting for ending conditions.")


## ─── ENDING TRIGGERS ──────────────────────────────────────────────────

## Public API: Called by JumpscareManager when the player is caught by the Entity.
## Triggers the DEATH ending immediately.
func trigger_death_ending() -> void:
	if is_ending_active:
		print("[EndgameManager] Ending already active. Ignoring duplicate DEATH trigger.")
		return
	_trigger_ending(Ending.DEATH)


## Public API: Called by EscapeVan when the player escapes in the repaired van.
## Triggers ESCAPE_GOOD (if totem was destroyed) or ESCAPE_MEDIOCRE (if not).
func start_ending_sequence(totem_destroyed: bool) -> void:
	if is_ending_active:
		print("[EndgameManager] Ending already active. Ignoring duplicate escape trigger.")
		return
	
	if totem_destroyed:
		print("[EndgameManager] Player escaped with totem destroyed! GOOD ending.")
		_trigger_ending(Ending.ESCAPE_GOOD)
	else:
		print("[EndgameManager] Player escaped without destroying the totem. MEDIOCRE ending.")
		_trigger_ending(Ending.ESCAPE_MEDIOCRE)


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
		Ending.DEATH:
			print("[EndgameManager] DEATH: The Entity caught the player. (BAD)")
		
		Ending.ESCAPE_MEDIOCRE:
			print("[EndgameManager] ESCAPE_MEDIOCRE: Player escaped in the van, but the Entity is still out there.")
		
		Ending.ESCAPE_GOOD:
			print("[EndgameManager] ESCAPE_GOOD: Player escaped in the van AND destroyed the Totem! The Entity is banished!")
	
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
