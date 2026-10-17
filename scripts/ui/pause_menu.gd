extends CanvasLayer
class_name PauseMenu

## PauseMenu - Standard in-game pause menu toggled by ESC. Under the title,
## where the player is: the day or night, and what to do next (not the time:
## that's the watch's).
## (No Quit in a browser: there's nothing to quit to.)

const MAIN_MENU_PATH: String = "res://scenes/ui/main_menu.tscn"
const OPTIONS_MENU_SCENE: String = "res://scenes/ui/options_menu.tscn"

@onready var _overlay: ColorRect = %PauseOverlay
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _quit_button: Button = %QuitButton

var _options_menu: OptionsMenu = null
var _is_open: bool = false
var _where: Label
var _objective: Label


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	GameFonts.use_title($PanelContainer/VBoxContainer/TitleLabel)
	_resume_button.pressed.connect(_on_resume_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_quit_button.visible = not OS.has_feature("web")
	var box := $PanelContainer/VBoxContainer
	var title := $PanelContainer/VBoxContainer/TitleLabel
	_where = Label.new()
	_where.name = "WhereLabel"
	_where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_where.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	box.add_child(_where)
	box.move_child(_where, title.get_index() + 1)
	_objective = Label.new()
	_objective.name = "ObjectiveLabel"
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size = Vector2(300, 0)
	_objective.add_theme_font_size_override("font_size", 14)
	_objective.modulate = Color(1, 1, 1, 0.75)
	box.add_child(_objective)
	box.move_child(_objective, _where.get_index() + 1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		# ─── STASH UI PRIORITY ────────────────────────────────────────────
		# If the stash UI (scrap heap looting) is open, pressing Escape
		# closes it instead of toggling the pause menu. The stash UI's own
		# _input() handler already marks the event as handled, but this is
		# a defensive backstop in case the scene tree order differs.
		if _close_stash_ui():
			get_viewport().set_input_as_handled()
			return
		# ─── INVENTORY UI PRIORITY ───────────────────────────────────────
		# If the player inventory is open, pressing Escape closes it instead
		# of toggling the pause menu. The inventory closes itself via
		# hardware-polling in _process() and cannot consume the event, so
		# without this guard ESC would open the pause menu on top of it.
		if _close_inventory_ui():
			get_viewport().set_input_as_handled()
			return
		# ─── NOTEBOOK PRIORITY ───────────────────────────────────────────
		# An open notebook closes first (also over the computer: the next
		# Escape then leaves the computer).
		var notebook := get_tree().get_first_node_in_group("notebook_ui")
		if notebook and notebook.has_method("close") and notebook.close():
			get_viewport().set_input_as_handled()
			return
		# ─── COMPUTER UI PRIORITY ─────────────────────────────────────────
		# If the computer UI is open, pressing Escape closes it instead of
		# toggling the pause menu. This prevents the player from accidentally
		# pausing the game while using the computer. The cursor remains in
		# captured mode when the computer is closed (ComputerUI handles this).
		if _close_computer_ui():
			if _options_menu and _options_menu.visible:
				_options_menu.hide_menu()
			get_viewport().set_input_as_handled()
			return
		# ─── DEBUG CONSOLE PRIORITY ───────────────────────────────────────
		# If the debug console is open, pressing Escape closes it instead of
		# toggling the pause menu. This prevents the player from accidentally
		# pausing the game while debugging.
		if _close_debug_console():
			if _options_menu and _options_menu.visible:
				_options_menu.hide_menu()
			get_viewport().set_input_as_handled()
			return
		if _options_menu and _options_menu.visible:
			_options_menu.hide_menu()
			get_viewport().set_input_as_handled()
			return
		if _is_open:
			_resume()
		else:
			_open()
		get_viewport().set_input_as_handled()


## The debug console, if it's open (by its group).
func _open_debug_console() -> Node:
	var console := get_tree().get_first_node_in_group("debug_console")
	return console if console and console.visible and console.has_method("_close_console") else null


## Finds and closes the stash UI if it is open.
## Returns true if the stash was found and closed, false otherwise.
func _close_stash_ui() -> bool:
	var stash_ui = get_tree().get_first_node_in_group("stash_ui")
	if stash_ui and stash_ui.get("_is_open"):
		if stash_ui.has_method("_close_stash"):
			stash_ui._close_stash()
			print("[PauseMenu] Stash UI closed via Escape key.")
			return true
	return false


## Finds and closes the inventory UI if it is open.
## Returns true if the inventory was found and closed, false otherwise.
func _close_inventory_ui() -> bool:
	var inv_ui = get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui and inv_ui.get("_is_open"):
		if inv_ui.has_method("_close_inventory"):
			inv_ui._close_inventory()
			print("[PauseMenu] Inventory UI closed via Escape key.")
			return true
	return false


## Finds and closes the computer UI if it's open.
## Returns true if the computer was found and closed, false otherwise.
## (A recursive search for anything with "is_open" used to be the fallback:
## it could find a door first.)
func _close_computer_ui() -> bool:
	var computer_ui = get_tree().get_first_node_in_group("computer_ui")
	if computer_ui and "is_open" in computer_ui and computer_ui.is_open:
		if computer_ui.has_method("close_computer"):
			computer_ui.close_computer()
			print("[PauseMenu] Computer UI closed via Escape key.")
			return true
	return false


## Finds and closes the debug console if it's open and visible.
## Returns true if a console was found and closed, false otherwise.
func _close_debug_console() -> bool:
	var console := _open_debug_console()
	if console:
		console._close_console()
		return true
	return false


## "Night 2" and the objective the HUD shows.
func refresh_where() -> void:
	var nm := get_node_or_null("/root/NightManager")
	var where := ""
	if nm:
		var night := maxi(int(nm.current_night), 1)
		where = ("Night %d" if nm.is_night_active else "Day %d") % night
	_where.text = where
	var objective := ""
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and "objective_label" in hud and hud.objective_label:
		objective = hud.objective_label.text
	if objective == "":
		var routine := get_node_or_null("/root/RoutineManager")
		if routine and routine.has_method("get_current_objective"):
			objective = routine.get_current_objective()
	_objective.text = objective
	_objective.visible = objective != ""


func _open() -> void:
	_is_open = true
	refresh_where()
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	_resume_button.grab_focus()


func _resume() -> void:
	_is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _options_menu:
		_options_menu.hide_menu()


func _on_resume_pressed() -> void:
	_resume()


func _on_settings_pressed() -> void:
	if not _options_menu:
		var scene = load(OPTIONS_MENU_SCENE) as PackedScene
		if not scene:
			return
		_options_menu = scene.instantiate() as OptionsMenu
		if not _options_menu:
			return
		add_child(_options_menu)
	_options_menu.show_menu()


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_PATH)


func _on_quit_pressed() -> void:
	get_tree().quit()
