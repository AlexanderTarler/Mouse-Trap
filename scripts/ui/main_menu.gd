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

## Options menu scene path.
const OPTIONS_MENU_SCENE: String = "res://scenes/ui/options_menu.tscn"

## Lazily-instanced options menu.
var _options_menu: OptionsMenu = null


func _ready() -> void:
	# Ensure the mouse is visible and the game is unpaused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	# The display mode chosen in the options last time.
	OptionsMenu.apply_saved_settings()
	GameFonts.use_title($TitleLabel)
	
	# Button signals are already connected in main_menu.tscn via the
	# [connection] entries, so no programmatic connection is needed here.
	print("[MainMenu] Main menu loaded.")
	# "-- --autoplay" (or "?autoplay" in the browser): straight into the
	# game (testing an exported build).
	var autoplay := "--autoplay" in OS.get_cmdline_user_args()
	# The web build: "?autoplay" on the page's address.
	if OS.has_feature("web"):
		var query = JavaScriptBridge.eval("window.location.search")
		autoplay = autoplay or (query is String and "autoplay" in query)
	if autoplay:
		_on_play_pressed.call_deferred()


## Called by the PlayButton when pressed.
## Loads the main game scene.
func _on_play_pressed() -> void:
	print("[MainMenu] Attempting to load: ", GAME_SCENE_PATH)
	# A new game: every game-wide manager as it was at boot (a second game
	# would otherwise carry the first one's inventory, story and night).
	var reset := get_node_or_null("/root/GameReset")
	if reset:
		reset.new_game()
	
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
	# Black until the game is set up and the opening has begun.
	var nm := get_node_or_null("/root/NightManager")
	if nm and nm.has_method("show_start_cover"):
		nm.show_start_cover()
	var err = get_tree().change_scene_to_packed(packed_scene)
	if err != OK:
		printerr("[MainMenu] ERROR: change_scene_to_packed failed! Error code: ", err)


## Called by the SettingsButton when pressed.
## Instances and shows the options menu over the main menu.
func _on_settings_pressed() -> void:
	if not _options_menu:
		var scene = load(OPTIONS_MENU_SCENE) as PackedScene
		if not scene:
			printerr("[MainMenu] ERROR: Could not load options menu scene.")
			return
		_options_menu = scene.instantiate() as OptionsMenu
		if not _options_menu:
			printerr("[MainMenu] ERROR: Options menu scene did not instance correctly.")
			return
		add_child(_options_menu)
		print("[MainMenu] Options menu instantiated.")
	
	_options_menu.show_menu()
	print("[MainMenu] Options menu shown.")


## Called by the QuitButton when pressed.
## Exits the application.
func _on_quit_pressed() -> void:
	print("[MainMenu] Quitting game.")
	get_tree().quit()
