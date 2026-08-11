extends CanvasLayer
class_name PauseMenu

## PauseMenu - Standard in-game pause menu toggled by ESC.

const MAIN_MENU_PATH: String = "res://scenes/ui/main_menu.tscn"
const OPTIONS_MENU_SCENE: String = "res://scenes/ui/options_menu.tscn"

@onready var _overlay: ColorRect = %PauseOverlay
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _quit_button: Button = %QuitButton

var _options_menu: OptionsMenu = null
var _is_open: bool = false


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	_resume_button.pressed.connect(_on_resume_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)


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


## Checks whether the Debug Console UI is currently open in the scene tree.
## Returns true if a DebugConsoleUI CanvasLayer is visible.
func _is_debug_console_open() -> bool:
	return _find_debug_console_recursive(get_tree().root) != null


## Recursively searches a node and its children for the DebugConsoleUI script.
## Returns the node if found and visible, null otherwise.
func _find_debug_console_recursive(node: Node) -> Node:
	if node.has_method("_close_console") and node.visible:
		return node
	for child in node.get_children():
		var result = _find_debug_console_recursive(child)
		if result:
			return result
	return null

## Finds and closes the stash UI if it is open.
## Returns true if the stash was found and closed, false otherwise.
func _close_stash_ui() -> bool:
	var stash_ui = get_node_or_null("/root/CottageHorror/StashUI")
	if not stash_ui:
		stash_ui = get_node_or_null("/root/Main/StashUI")
	if not stash_ui:
		stash_ui = get_tree().get_first_node_in_group("stash_ui")
	if stash_ui and stash_ui.get("_is_open"):
		if stash_ui.has_method("_close_stash"):
			stash_ui._close_stash()
			print("[PauseMenu] Stash UI closed via Escape key.")
			return true
	return false


## Finds and closes the inventory UI if it is open.
## Returns true if the inventory was found and closed, false otherwise.
func _close_inventory_ui() -> bool:
	var inv_ui = get_node_or_null("/root/CottageHorror/InventoryUI")
	if not inv_ui:
		inv_ui = get_node_or_null("/root/Main/InventoryUI")
	if inv_ui and inv_ui.get("_is_open"):
		if inv_ui.has_method("_close_inventory"):
			inv_ui._close_inventory()
			print("[PauseMenu] Inventory UI closed via Escape key.")
			return true
	return false


## Finds and closes the computer UI if it's open.
## Returns true if the computer was found and closed, false otherwise.
func _close_computer_ui() -> bool:
	# Check multiple possible paths for the ComputerUI
	var computer_ui = get_node_or_null("/root/CottageHorror/ComputerUI")
	if not computer_ui:
		computer_ui = get_node_or_null("/root/Main/ComputerUI")
	if not computer_ui:
		# Search the scene root recursively as a fallback
		var scene = get_tree().current_scene
		if scene:
			computer_ui = _find_computer_ui_recursive(scene)
	
	if computer_ui and "is_open" in computer_ui and computer_ui.is_open:
		if computer_ui.has_method("close_computer"):
			computer_ui.close_computer()
			print("[PauseMenu] Computer UI closed via Escape key.")
			return true
	return false


## Recursively searches a node and its children for the ComputerUI script.
func _find_computer_ui_recursive(node: Node) -> Node:
	if "is_open" in node:
		return node
	for child in node.get_children():
		var result = _find_computer_ui_recursive(child)
		if result:
			return result
	return null


## Finds and closes the debug console if it's open and visible.
## Returns true if a console was found and closed, false otherwise.
func _close_debug_console() -> bool:
	var console = _find_debug_console_recursive(get_tree().root)
	if console and console.has_method("_close_console") and console.visible:
		console._close_console()
		return true
	return false


func _open() -> void:
	_is_open = true
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
