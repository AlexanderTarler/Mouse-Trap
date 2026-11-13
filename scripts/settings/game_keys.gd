class_name GameKeys
extends RefCounted
## The game's keys, rebindable (Options > Controls). Every key the player
## uses is an input action (the code reads the actions, never a key), bound
## by the key's physical position: W A S D sits where it does on any layout
## (Z Q S D on an AZERTY keyboard) and is shown with that keyboard's own
## label. Changed keys are saved with the settings (user://settings.cfg,
## section "keys") and applied at startup (GameSettings.apply_all).
##
##   GameKeys.rebind("flashlight", KEY_G)
##   GameKeys.label("move_forward")   # "W" (or "Z" on AZERTY)
##   GameKeys.keys_in("[E] Open Door")  # "[G] Open Door" once Use is on G

## A gamepad works too (GamepadInput): these buttons are fixed (Options >
## Controls lists them), the sticks walk and look, and hints and prompts
## show the pad's button names while the pad is the device in use.
##   GameKeys.gamepad_active          # true once a pad was used last
##   GameKeys.pad_label("ui_interact") # "X" ("Square" on a PlayStation pad)

const SECTION := "keys"
## [action, what it does, default key (physical), extra keys always bound].
const BINDINGS := [
	["move_forward", "Move forward", KEY_W, [KEY_UP]],
	["move_back", "Move back", KEY_S, [KEY_DOWN]],
	["move_left", "Move left", KEY_A, [KEY_LEFT]],
	["move_right", "Move right", KEY_D, [KEY_RIGHT]],
	["ui_shift", "Sprint (noisy)", KEY_SHIFT, []],
	["ui_crouch", "Crouch (quiet)", KEY_CTRL, [KEY_C]],
	["jump", "Jump", KEY_SPACE, []],
	["ui_interact", "Use · hold: board, refuel, carry", KEY_E, []],
	["flashlight", "Flashlight · hold: overcharge", KEY_F, []],
	["swap_battery", "Spare battery", KEY_R, []],
	["ui_inventory", "Inventory", KEY_TAB, []],
	["toggle_notebook", "Field notebook", KEY_J, []],
	["notebook_prev_page", "Notebook: previous page", KEY_Q, []],
	["notebook_next_page", "Notebook: next page", KEY_E, []],
	["watch", "Check your watch (hold)", KEY_T, []],
]

## The key names written in hints and prompts ("[E] Open", "[Hold F]"),
## and the action each stands for.
const TOKENS := {
	"W": "move_forward", "A": "move_left", "S": "move_back", "D": "move_right",
	"SHIFT": "ui_shift", "CTRL": "ui_crouch", "SPACE": "jump", "E": "ui_interact",
	"F": "flashlight", "R": "swap_battery", "TAB": "ui_inventory", "J": "toggle_notebook",
	"Q": "notebook_prev_page", "T": "watch",
}

## Gamepad buttons (JoyButton) for each action: what the pad does.
const PAD_BUTTONS := {
	"jump": [JOY_BUTTON_A],
	"ui_crouch": [JOY_BUTTON_B],
	"ui_interact": [JOY_BUTTON_X],
	"flashlight": [JOY_BUTTON_Y],
	"ui_shift": [JOY_BUTTON_LEFT_STICK],
	"ui_inventory": [JOY_BUTTON_BACK],
	"toggle_notebook": [JOY_BUTTON_DPAD_UP],
	"ui_notebook": [JOY_BUTTON_DPAD_UP],
	"swap_battery": [JOY_BUTTON_DPAD_DOWN],
	"watch": [JOY_BUTTON_DPAD_LEFT],
	"notebook_next_page": [JOY_BUTTON_RIGHT_SHOULDER],
	"notebook_prev_page": [JOY_BUTTON_LEFT_SHOULDER],
	"pause_menu": [JOY_BUTTON_START],
	"ui_cancel": [JOY_BUTTON_B],
}
## Gamepad sticks and triggers: action -> [axis, direction, deadzone].
## The left stick walks, the right stick looks (and steers the cursor on the
## screens that need a mouse), the right trigger clicks.
const PAD_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0, 0.2],
	"move_right": [JOY_AXIS_LEFT_X, 1.0, 0.2],
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0, 0.2],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0, 0.2],
	"look_left": [JOY_AXIS_RIGHT_X, -1.0, 0.2],
	"look_right": [JOY_AXIS_RIGHT_X, 1.0, 0.2],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0, 0.2],
	"look_down": [JOY_AXIS_RIGHT_Y, 1.0, 0.2],
	"pad_click": [JOY_AXIS_TRIGGER_RIGHT, 1.0, 0.5],
}
## Button names: Xbox style, and PlayStation style for those pads.
const PAD_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu",
	JOY_BUTTON_DPAD_UP: "D-pad Up", JOY_BUTTON_DPAD_DOWN: "D-pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-pad Left", JOY_BUTTON_DPAD_RIGHT: "D-pad Right",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
}
const PAD_NAMES_PLAYSTATION := {
	JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
	JOY_BUTTON_BACK: "Create", JOY_BUTTON_START: "Options",
	JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
}

## True while the gamepad is the device last used (GamepadInput sets it).
static var gamepad_active := false
## That pad's device id (for its name).
static var pad_device := 0

static var _applied := false
## action -> physical key (the saved ones over the defaults), read once.
static var _keys := {}
static var _token_regex: RegEx


## Binds every action to its key (saved, or the default). Safe to repeat.
static func apply() -> void:
	_applied = true
	_load()
	for entry in BINDINGS:
		var action: String = entry[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				InputMap.action_erase_event(action, event)
		InputMap.action_add_event(action, _key_event(key_of(action)))
		for extra in entry[3]:
			if int(extra) != key_of(action):
				InputMap.action_add_event(action, _key_event(int(extra)))
	_apply_pad()


## The gamepad's buttons and sticks onto their actions (the keys stay).
static func _apply_pad() -> void:
	for action in PAD_AXES:
		var axis: Array = PAD_AXES[action]
		if not InputMap.has_action(action):
			InputMap.add_action(action, float(axis[2]))
		else:
			InputMap.action_set_deadzone(action, float(axis[2]))
		_erase_pad_events(action)
		var motion := InputEventJoypadMotion.new()
		motion.axis = axis[0] as JoyAxis
		motion.axis_value = float(axis[1])
		InputMap.action_add_event(action, motion)
	for action in PAD_BUTTONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		_erase_pad_events(action, true)
		for button in PAD_BUTTONS[action]:
			var event := InputEventJoypadButton.new()
			event.button_index = button as JoyButton
			InputMap.action_add_event(action, event)


static func _erase_pad_events(action: String, buttons_only := false) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or (event is InputEventJoypadMotion and not buttons_only):
			InputMap.action_erase_event(action, event)


## The action's gamepad button as the pad in use calls it ("X", "Square"),
## or "" if the pad has none for it.
static func pad_label(action: String) -> String:
	var buttons: Array = PAD_BUTTONS.get(action, [])
	if buttons.is_empty():
		return ""
	var button: int = buttons[0]
	if _playstation_pad() and PAD_NAMES_PLAYSTATION.has(button):
		return PAD_NAMES_PLAYSTATION[button]
	return PAD_NAMES.get(button, "")


static func _playstation_pad() -> bool:
	var pad := Input.get_joy_name(pad_device).to_lower()
	return "ps" in pad.split(" ") or "playstation" in pad or "dualsense" in pad or "dualshock" in pad or "sony" in pad


## The action's key (physical keycode): the saved one, or the default.
static func key_of(action: String) -> int:
	if _keys.is_empty():
		_load()
	return int(_keys.get(action, default_of(action)))


static func _load() -> void:
	_keys.clear()
	var config := ConfigFile.new()
	var loaded := config.load(GameSettings.PATH) == OK
	for entry in BINDINGS:
		var action: String = entry[0]
		_keys[action] = int(config.get_value(SECTION, action)) if loaded and config.has_section_key(SECTION, action) else int(entry[2])


static func default_of(action: String) -> int:
	for entry in BINDINGS:
		if entry[0] == action:
			return int(entry[2])
	return KEY_NONE


## Binds `action` to the key at physical position `key`, saved.
static func rebind(action: String, key: int) -> void:
	var config := ConfigFile.new()
	config.load(GameSettings.PATH)
	if key == default_of(action):
		if config.has_section_key(SECTION, action):
			config.erase_section_key(SECTION, action)
	else:
		config.set_value(SECTION, action, key)
	config.save(GameSettings.PATH)
	apply()


## Every key back to its default.
static func reset() -> void:
	var config := ConfigFile.new()
	if config.load(GameSettings.PATH) == OK and config.has_section(SECTION):
		config.erase_section(SECTION)
		config.save(GameSettings.PATH)
	apply()


## How the action's key is labelled on this keyboard ("W", or "Z" on AZERTY).
static func label(action: String) -> String:
	return key_label(key_of(action))


static func key_label(physical: int) -> String:
	var shown := physical
	if DisplayServer.get_name() != "headless":
		var mapped := DisplayServer.keyboard_get_keycode_from_physical(physical)
		if mapped != KEY_NONE:
			shown = mapped
	var text := OS.get_keycode_string(shown)
	return text if text != "" else "?"


## The text with its key names ("[E]", "[Hold F]") as the player's keys,
## where they've been changed (unchanged, the text is left as written).
## `meaning` says what a name stands for here when it isn't the usual
## ({"E": "notebook_next_page"} in the notebook).
static func keys_in(text: String, meaning: Dictionary = {}) -> String:
	if not "[" in text:
		return text
	if not _token_regex:
		_token_regex = RegEx.create_from_string("\\[(Hold )?([A-Za-z]+)\\]")
	# On a pad, the four walking keys are the left stick.
	if gamepad_active:
		text = text.replace("[W][A][S][D]", "[Left stick]")
	var out := ""
	var last := 0
	for found in _token_regex.search_all(text):
		var token := found.get_string(2).to_upper()
		var action: String = meaning.get(token, TOKENS.get(token, ""))
		if action == "":
			continue
		var shown := ""
		if gamepad_active:
			shown = pad_label(action)
		if shown == "":
			if key_of(action) == default_of(action):
				continue
			shown = label(action)
		out += text.substr(last, found.get_start() - last) + "[" + found.get_string(1) + shown + "]"
		last = found.get_end()
	return out + text.substr(last)


## Actions sharing a key with `action` (bar the notebook's pages and Use,
## which share E on purpose: one works only with the notebook open).
static func clashes(action: String) -> Array[String]:
	var found: Array[String] = []
	var key := key_of(action)
	for entry in BINDINGS:
		var other: String = entry[0]
		if other == action or key_of(other) != key:
			continue
		if [action, other].has("ui_interact") and ([action, other].has("notebook_next_page") or [action, other].has("notebook_prev_page")):
			continue
		found.append(other)
	return found


static func _key_event(physical: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical as Key
	return event
