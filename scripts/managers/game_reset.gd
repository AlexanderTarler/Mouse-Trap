extends Node
## GameReset (autoload, the LAST in the list): a new game from the main menu.
##
## The game-wide managers (autoloads) outlive the game scene. A second game
## from the main menu (after quitting to it, or after an ending) used to
## start with the first game's inventory, story, night and clock, and no
## Day 1 setup at all. So at boot, before any game, this records every
## manager's state (its script variables of plain types, as Checkpoint
## does); new_game() (the main menu's Play) puts it all back, and does what
## plain values can't (the checkpoint's copies, the weather, sounds), so
## every game starts exactly like the first.

## The managers reset to how they were at boot.
const MANAGERS := [
	"GameTime", "NightManager", "HorrorSoundManager", "Inventory", "JumpscareManager",
	"RoutineManager", "EvidenceManager", "EndgameManager", "PeekerManager",
	"TutorialManager", "Checkpoint", "Monologue", "NightTwoStory",
]

## manager name -> {var: value} at boot
var _boot := {}
## How many games started from the menu (tests, logs).
var games_started := 0


func _ready() -> void:
	# Every other autoload is ready by now (this one comes last); the game
	# scene, which changes them, isn't yet.
	var checkpoint := get_node_or_null("/root/Checkpoint")
	for manager in MANAGERS:
		var node := get_node_or_null("/root/" + manager)
		if node and checkpoint:
			_boot[manager] = checkpoint._read_state(node)


## Every manager back to how it was at boot (call before loading the game
## scene for a new game).
func new_game() -> void:
	var checkpoint := get_node_or_null("/root/Checkpoint")
	if checkpoint:
		checkpoint._free_templates()
		checkpoint._states.clear()
	var weather := get_node_or_null("/root/Weather")
	if weather and weather.has_method("clear_now"):
		weather.clear_now()
	var sounds := get_node_or_null("/root/HorrorSoundManager")
	if sounds:
		for stop in ["_stop_stalk_chase", "_stop_distant_monster", "_stop_whistles", "_stop_entity_sounds"]:
			if sounds.has_method(stop):
				sounds.call(stop)
	var endgame := get_node_or_null("/root/EndgameManager")
	if endgame and endgame.has_method("reset"):
		endgame.reset()
	for manager in _boot:
		var node := get_node_or_null("/root/" + manager)
		if node and checkpoint:
			checkpoint._write_state(node, _boot[manager])
	var monologue := get_node_or_null("/root/Monologue")
	if monologue and monologue.has_method("reset"):
		monologue.reset()
	get_tree().paused = false
	Engine.time_scale = 1.0
	games_started += 1
	print("[GameReset] New game: %d managers back to how they were at boot." % _boot.size())
