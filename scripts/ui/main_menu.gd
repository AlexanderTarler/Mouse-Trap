extends Control
class_name MainMenu

## MainMenu — The game's main menu screen.
##
## Behind it the cabin at night from the treeline (MenuBackdrop). Continue
## (the last checkpoint, saved to disk: SaveGame), Play / New Game, Settings
## and Quit (not in a browser: there's nothing to quit to). The first time
## the game starts, the brightness screen comes up (BrightnessCalibration).

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
## The game's level, loaded in the background from the moment the menu is up
## (it takes seconds: Play used to wait for all of it). Kept, so going back
## to the menu and playing again doesn't load it again.
static var _game_packed: PackedScene = null
var _starting := false
var _continue_button: Button
## New Game over a save asks first (seconds left to click again).
var _new_game_armed := 0.0


func _ready() -> void:
	# Ensure the mouse is visible and the game is unpaused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	# The display mode chosen in the options last time.
	OptionsMenu.apply_saved_settings()
	GameFonts.use_title($TitleLabel)
	_dress()
	# Not the game's forest sounds behind the menu.
	_quiet_game_sounds(true)
	# Start loading the game now, while the player looks at the menu (after
	# the menu's first frame is on screen).
	_preload_game.call_deferred()
	
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
	elif not bool(GameSettings.get_value("video/calibrated")) and get_parent() == get_tree().root and DisplayServer.get_name() != "headless":
		# The first launch: set the brightness before anything.
		var calibration := BrightnessCalibration.new()
		calibration.name = "Calibration"
		add_child(calibration)


## The backdrop (when the menu is the scene), Continue, and no Quit on the web.
func _dress() -> void:
	if get_parent() == get_tree().root and DisplayServer.get_name() != "headless":
		var backdrop := MenuBackdrop.new()
		backdrop.name = "Backdrop"
		add_child(backdrop)
		move_child(backdrop, 0)
		$Background.visible = false
		# A shadow down the middle so the words read over the picture.
		var shade := TextureRect.new()
		shade.name = "Shade"
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0, 0, 0, 0.55))
		gradient.set_color(1, Color(0, 0, 0, 0.0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.27, 0.42)
		texture.fill_to = Vector2(0.75, 0.95)
		shade.texture = texture
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		add_child(shade)
		move_child(shade, $Background.get_index() + 1)
		# The words on the left, the cabin on the right.
		for node in [$TitleLabel, $VBoxContainer]:
			(node as Control).anchor_left = 0.27
			(node as Control).anchor_right = 0.27
	$TitleLabel.add_theme_color_override("font_color", Color(0.86, 0.82, 0.72))
	$TitleLabel.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	$TitleLabel.add_theme_constant_override("shadow_offset_y", 4)
	if OS.has_feature("web"):
		quit_button.visible = false
	var box := $VBoxContainer as VBoxContainer
	_continue_button = play_button.duplicate() as Button
	_continue_button.name = "ContinueButton"
	box.add_child(_continue_button)
	box.move_child(_continue_button, 0)
	_continue_button.pressed.connect(_on_continue_pressed)
	_refresh_continue()
	_add_clicks(self)


## A click for every button pressed on the menu (and in its options).
const CLICK := "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/GUI/gui_click_1.ogg"
var _click: AudioStreamPlayer


func _add_clicks(under: Node) -> void:
	if not _click:
		_click = AudioStreamPlayer.new()
		_click.name = "Click"
		_click.stream = load(CLICK)
		_click.volume_db = -8.0
		_click.bus = &"SFX"
		_click.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_click)
	for node in under.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if not button.pressed.is_connected(_play_click):
			button.pressed.connect(_play_click)


func _play_click() -> void:
	if _click and _click.is_inside_tree():
		_click.play()


func _refresh_continue() -> void:
	var saved := SaveGame.describe()
	_continue_button.visible = saved != ""
	_continue_button.text = "Continue  ·  %s" % saved
	play_button.text = "New Game" if saved != "" else "Play"


func _process(delta: float) -> void:
	if _new_game_armed > 0.0:
		_new_game_armed -= delta
		if _new_game_armed <= 0.0:
			_refresh_continue()


func _exit_tree() -> void:
	_quiet_game_sounds(false)


func _quiet_game_sounds(quiet: bool) -> void:
	var sounds := get_node_or_null("/root/HorrorSoundManager")
	if sounds and sounds.has_method("set_menu_quiet"):
		sounds.set_menu_quiet(quiet)


func _preload_game() -> void:
	# (Only as the game's own menu: not in the tests, where loading the level
	# on a thread while they load it themselves trips over itself.)
	if get_parent() != get_tree().root or DisplayServer.get_name() == "headless":
		return
	if _game_packed or ResourceLoader.load_threaded_get_status(GAME_SCENE_PATH) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if ResourceLoader.load_threaded_request(GAME_SCENE_PATH, "PackedScene") != OK:
		printerr("[MainMenu] Couldn't start loading the game in the background.")


## The game's level: loaded already, or the rest of it now (with "Loading..."
## on the pressed button for the moment it takes).
func _game_scene(button: Button) -> PackedScene:
	if _game_packed:
		return _game_packed
	var status := ResourceLoader.load_threaded_get_status(GAME_SCENE_PATH)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		button.text = "Loading..."
		# (Waited for frame by frame: some of it finishes on the main thread.)
		while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
			status = ResourceLoader.load_threaded_get_status(GAME_SCENE_PATH)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_game_packed = ResourceLoader.load_threaded_get(GAME_SCENE_PATH) as PackedScene
	if not _game_packed:
		print("[MainMenu] Loading the game now: ", GAME_SCENE_PATH)
		_game_packed = load(GAME_SCENE_PATH) as PackedScene
	if not _game_packed:
		printerr("[MainMenu] ERROR: load() returned null for path: ", GAME_SCENE_PATH, "; trying the UID.")
		_game_packed = load(GAME_SCENE_UID) as PackedScene
	return _game_packed


## Into the game, once it's loaded: black until it's set up.
func _start(button: Button) -> void:
	var packed_scene := await _game_scene(button)
	if packed_scene == null:
		printerr("[MainMenu] ERROR: the game scene couldn't be loaded!")
		_starting = false
		return
	var nm := get_node_or_null("/root/NightManager")
	if nm and nm.has_method("show_start_cover"):
		nm.show_start_cover()
	var err := get_tree().change_scene_to_packed(packed_scene)
	if err != OK:
		printerr("[MainMenu] ERROR: change_scene_to_packed failed! Error code: ", err)
		_starting = false


## The last checkpoint, from disk.
func _on_continue_pressed() -> void:
	if _starting:
		return
	var reset := get_node_or_null("/root/GameReset")
	if reset:
		reset.new_game()
	var checkpoint := get_node_or_null("/root/Checkpoint")
	if not checkpoint or not SaveGame.read_into(checkpoint):
		_refresh_continue()
		return
	checkpoint.save_to_disk = true
	print("[MainMenu] Continue: the %s checkpoint." % checkpoint.kind)
	_starting = true
	_start(_continue_button)


## Called by the PlayButton when pressed.
## Loads the main game scene.
func _on_play_pressed() -> void:
	if _starting:
		return
	# Over a save: click twice (the save goes at the new game's first
	# checkpoint).
	if _continue_button and _continue_button.visible and _new_game_armed <= 0.0:
		_new_game_armed = 3.0
		play_button.text = "Start over? Click again"
		return
	# A new game: every game-wide manager as it was at boot (a second game
	# would otherwise carry the first one's inventory, story and night).
	var reset := get_node_or_null("/root/GameReset")
	if reset:
		reset.new_game()
	var checkpoint := get_node_or_null("/root/Checkpoint")
	if checkpoint:
		checkpoint.save_to_disk = true
	_starting = true
	if DisplayServer.get_name() == "headless":
		_start(play_button)   # (the tests: no opening)
		return
	# The opening at once, on black; the level comes in under it.
	var opening := Opening.new()
	opening.name = "Opening"
	opening.level_ready = false
	opening.start_level = _change_to_game
	get_tree().root.add_child(opening)
	opening.play()
	# (The cabin behind the menu is under the black now: let it go.)
	var backdrop := get_node_or_null("Backdrop")
	if backdrop:
		backdrop.queue_free()


## Into the level if it has loaded (true), for the opening: it calls this in
## the dark between its cards until it has.
func _change_to_game() -> bool:
	if not _game_packed:
		var status := ResourceLoader.load_threaded_get_status(GAME_SCENE_PATH)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return false
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_game_packed = ResourceLoader.load_threaded_get(GAME_SCENE_PATH) as PackedScene
		if not _game_packed:
			_game_packed = load(GAME_SCENE_PATH) as PackedScene
	if not _game_packed:
		printerr("[MainMenu] ERROR: the game scene couldn't be loaded!")
		return false
	get_tree().change_scene_to_packed(_game_packed)
	return true


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
		_add_clicks(_options_menu)
		print("[MainMenu] Options menu instantiated.")
	
	_options_menu.show_menu()
	print("[MainMenu] Options menu shown.")


## Called by the QuitButton when pressed.
## Exits the application.
func _on_quit_pressed() -> void:
	print("[MainMenu] Quitting game.")
	get_tree().quit()
