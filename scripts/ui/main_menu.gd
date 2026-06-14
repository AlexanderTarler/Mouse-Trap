extends Control
class_name MainMenu

## MainMenu — The game's main menu screen.
##
## Provides Play, Settings (placeholder), and Quit buttons.
## The Play button loads the main game scene (cottage_horror.tscn).
## The Quit button exits the application.

## Path to the main game scene.
const GAME_SCENE_PATH: String = "res://scenes/cottage_horror.tscn"

## UID-based path to the main game scene (fallback).
const GAME_SCENE_UID: String = "uid://bc5qrh4dx4yi1"

## Play button reference.
@onready var play_button: Button = $VBoxContainer/PlayButton

## Settings button reference.
@onready var settings_button: Button = $VBoxContainer/SettingsButton

## Quit button reference.
@onready var quit_button: Button = $VBoxContainer/QuitButton


func _ready() -> void:
	# Ensure the mouse is visible and the game is unpaused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	
	# Connect button signals programmatically
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	print("[MainMenu] Main menu loaded.")


## Called by the PlayButton when pressed.
## Loads the main game scene.
func _on_play_pressed() -> void:
	print("[MainMenu] Attempting to load: ", GAME_SCENE_PATH)
	
	# Try loading via ResourceLoader first to get a meaningful error
	var packed_scene = load(GAME_SCENE_PATH) as PackedScene
	if packed_scene == null:
		printerr("[MainMenu] ERROR: load() returned null for path: ", GAME_SCENE_PATH)
		printerr("[MainMenu] Attempting fallback with UID: ", GAME_SCENE_UID)
		packed_scene = load(GAME_SCENE_UID) as PackedScene
		if packed_scene == null:
			printerr("[MainMenu] ERROR: UID fallback also returned null!")
			return
	
	print("[MainMenu] Scene loaded successfully. Changing scene...")
	var err = get_tree().change_scene_to_packed(packed_scene)
	if err != OK:
		printerr("[MainMenu] ERROR: change_scene_to_packed failed! Error code: ", err)


## Called by the SettingsButton when pressed.
## Placeholder — no settings screen implemented yet.
func _on_settings_pressed() -> void:
	print("[MainMenu] Settings not yet implemented.")
	# TODO: Open settings menu


## Called by the QuitButton when pressed.
## Exits the application.
func _on_quit_pressed() -> void:
	print("[MainMenu] Quitting game.")
	get_tree().quit()
