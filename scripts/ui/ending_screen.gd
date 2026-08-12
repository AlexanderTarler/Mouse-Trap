extends Control
class_name EndingScreen

## EndingScreen — Overlay displayed when the game ends.
##
## Shows the ending title, subtitle, and two buttons:
##   - Retry: Reloads the main game scene
##   - Main Menu: Returns to the main menu
##
## The screen is designed to overlay on top of the game world (semi-transparent
## black background) so the player can see the final game state behind it.
##
## IMPORTANT: This node's process_mode must be set to PROCESS_MODE_ALWAYS so
## it continues to function while the game tree is paused.

signal retry_pressed
signal main_menu_pressed

## Path to the main game scene for retry.
const GAME_SCENE_PATH: String = "res://scenes/cottage_horror.tscn"

## Path to the main menu scene.
const MAIN_MENU_PATH: String = "res://scenes/ui/main_menu.tscn"

## Title label reference.
@onready var title_label: Label = $VBoxContainer/TitleLabel

## Subtitle label reference.
@onready var subtitle_label: Label = $VBoxContainer/SubtitleLabel

## Retry button reference.
@onready var retry_button: Button = $VBoxContainer/RetryButton

## Main menu button reference.
@onready var main_menu_button: Button = $VBoxContainer/MainMenuButton


func _ready() -> void:
	# Ensure this screen processes even when the game is paused
	process_mode = PROCESS_MODE_ALWAYS
	
	# Connect button signals
	retry_button.pressed.connect(_on_retry_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	
	print("[EndingScreen] Ready.")


## Configures the ending screen UI based on which ending was triggered.
## Called by EndgameManager when the ending sequence begins.
func setup_ending(ending_type: int) -> void:
	# Use the EndgameManager's Ending enum for human-readable names
	var em = get_node_or_null("/root/EndgameManager")
	var ending_name: String = "Unknown"
	if em and em.has_method("get_ending_name"):
		ending_name = em.get_ending_name(ending_type)
	
	match ending_type:
		0:  # Ending.DEATH
			title_label.text = "YOU DIED"
			subtitle_label.text = "The Entity caught you.\nThe darkness claims another soul."
		
		1:  # Ending.ESCAPE_MEDIOCRE
			# TASK 4: Exact required placeholder text for the Mediocre Ending.
			title_label.text = "MEDIOCRE ENDING"
			subtitle_label.text = "The player escaped the cabin, but the Entity remained - and it followed the player home. The player disappeared after a few days and were never seen again."
		
		2:  # Ending.ESCAPE_GOOD
			# TASK 4: Exact required placeholder text for the Good Ending.
			title_label.text = "GOOD ENDING"
			subtitle_label.text = "The player managed to banish the Entity from this world, and were able to return home to a safe haven, knowing there are things out there that they do not want to meet."
		
		_:
			title_label.text = "GAME OVER"
			subtitle_label.text = "An unknown ending occurred."
	
	print("[EndingScreen] Displaying ending: ", ending_name)


## Called when the Retry button is pressed.
## Reloads the main game scene.
func _on_retry_pressed() -> void:
	print("[EndingScreen] Retry pressed. Reloading game scene.")
	retry_pressed.emit()
	
	# Reset the EndgameManager so endings can trigger again
	var em = get_node_or_null("/root/EndgameManager")
	if em and em.has_method("reset"):
		em.reset()
	
	# Unpause and reload
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var err = get_tree().change_scene_to_file(GAME_SCENE_PATH)
	if err != OK:
		printerr("[EndingScreen] ERROR: Failed to load scene! Error code: ", err)


## Called when the Main Menu button is pressed.
## Returns to the main menu.
func _on_main_menu_pressed() -> void:
	print("[EndingScreen] Main Menu pressed. Returning to main menu.")
	main_menu_pressed.emit()
	
	# Reset the EndgameManager so endings can trigger again
	var em = get_node_or_null("/root/EndgameManager")
	if em and em.has_method("reset"):
		em.reset()
	
	# Unpause and load main menu
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_PATH)
