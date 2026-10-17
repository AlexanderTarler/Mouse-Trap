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
	var out := ""
	var last := 0
	for found in _token_regex.search_all(text):
		var token := found.get_string(2).to_upper()
		var action: String = meaning.get(token, TOKENS.get(token, ""))
		if action == "" or key_of(action) == default_of(action):
			continue
		out += text.substr(last, found.get_start() - last) + "[" + found.get_string(1) + label(action) + "]"
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
