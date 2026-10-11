extends Control
class_name OptionsMenu

## OptionsMenu — In-game / main-menu settings panel.
##
## Audio: a slider for every AudioServer bus. Display: the display mode
## (Windowed, Borderless, Fullscreen), brightness, field of view, head bob.
## Controls: mouse sensitivity, invert Y, and a page of the keys. Settings
## are saved and applied by GameSettings (main_menu.gd applies them at
## startup). The menu runs with PROCESS_MODE_ALWAYS so it works while the
## game is paused.

## Maps internal bus names to user-friendly display names.
const DISPLAY_NAMES: Dictionary = {
	"Master": "Master Volume",
	"SFX": "Sound Effects",
	"Music": "Music",
	"Ambient": "Ambient",
	"Voice": "Voice / Dialogue",
	"UI": "UI Sounds",
}

@onready var _slider_container: VBoxContainer = %SliderContainer
@onready var _back_button: Button = %BackButton
@onready var _highlight_toggle: CheckButton = $PanelContainer/VBoxContainer/ObjectiveHighlightsToggle

var _bus_sliders: Dictionary = {}
var _display_mode: OptionButton = null

enum DisplayMode { WINDOWED, BORDERLESS, FULLSCREEN }
const DISPLAY_MODE_NAMES := ["Windowed", "Borderless", "Fullscreen"]
## The keys, for the Controls page (Show Controls).
const CONTROLS := [
	["W A S D", "Move"],
	["Shift (hold)", "Sprint (noisy)"],
	["Ctrl", "Crouch (quiet; hides you in tall plants)"],
	["E", "Use / pick up"],
	["E (hold)", "Board, refuel, lock a door, carry things"],
	["F", "Flashlight on / off"],
	["F (hold)", "Overcharge the beam"],
	["R", "Swap in a spare battery"],
	["Tab", "Inventory"],
	["J", "Field notebook"],
	["Q / E", "Turn notebook pages"],
	["Esc", "Pause / close"],
]


## The saved display mode (Windowed if nothing is saved).
static func saved_display_mode() -> int:
	return int(GameSettings.get_value("display/mode"))


## Applies the saved settings (at startup).
static func apply_saved_settings() -> void:
	GameSettings.apply_all()


static func apply_display_mode(mode: int) -> void:
	GameSettings.apply_display_mode(mode)


static func save_display_mode(mode: int) -> void:
	GameSettings.set_value("display/mode", mode)


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	
	if _back_button:
		_back_button.pressed.connect(_on_back_pressed)
	
	# ─── TASK 5: OBJECTIVE HIGHLIGHT TOGGLE ─────────────────────────
	# Wire the CheckButton to RoutineManager.enable_object_highlights.
	# Since RoutineManager is a static var, we can reference it directly.
	if _highlight_toggle:
		# Sync the button state with the current setting on boot.
		_highlight_toggle.button_pressed = RoutineManager.enable_object_highlights
		_highlight_toggle.toggled.connect(_on_highlight_toggle_changed)
	
	GameFonts.use_title($PanelContainer/VBoxContainer/TitleLabel)
	_build_sliders()
	_build_settings()
	# The Back button last.
	if _back_button:
		_back_button.get_parent().move_child(_back_button, -1)


## Audio (the sliders above), then Display and Controls.
func _build_settings() -> void:
	var box := _slider_container.get_parent()
	var audio := _header("Audio")
	box.add_child(audio)
	box.move_child(audio, _slider_container.get_index())
	var rows: Array[Control] = []
	rows.append(_header("Display"))
	_display_mode = OptionButton.new()
	_display_mode.name = "DisplayModeOption"
	_display_mode.custom_minimum_size = Vector2(200, 0)
	for mode in DISPLAY_MODE_NAMES.size():
		if mode == DisplayMode.BORDERLESS and OS.has_feature("web"):
			continue
		_display_mode.add_item(DISPLAY_MODE_NAMES[mode], mode)
	_display_mode.select(maxi(_display_mode.get_item_index(saved_display_mode()), 0))
	_display_mode.item_selected.connect(_on_display_mode_selected)
	rows.append(_row("Display Mode", _display_mode))
	rows.append(_slider_row("Brightness", "video/brightness", 0.6, 1.8, 0.05, "BrightnessSlider",
		func(v): return "%d%%" % roundi(v * 100.0)))
	var tip := Label.new()
	tip.text = "Dark should stay dark: just enough to make out shapes in the shadows."
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 12)
	tip.modulate = Color(1, 1, 1, 0.6)
	rows.append(tip)
	rows.append(_slider_row("Field of View", "video/fov", 60.0, 100.0, 1.0, "FovSlider",
		func(v): return "%d" % roundi(v)))
	rows.append(_check_row("Head Bob", "video/head_bob", "HeadBobCheck"))
	rows.append(_header("Controls"))
	rows.append(_slider_row("Mouse Sensitivity", "controls/mouse_sensitivity", 0.25, 3.0, 0.05, "SensitivitySlider",
		func(v): return "%.2fx" % v))
	rows.append(_check_row("Invert Mouse Y", "controls/invert_y", "InvertYCheck"))
	var keys := Button.new()
	keys.name = "ControlsButton"
	keys.text = "Show Controls"
	keys.pressed.connect(_show_controls)
	rows.append(keys)
	var at := _slider_container.get_index() + 1
	for row in rows:
		box.add_child(row)
		box.move_child(row, at)
		at += 1


func _header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	return label


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	return row


func _slider_row(text: String, key: String, low: float, high: float, step: float, node_name: String, shown: Callable) -> HBoxContainer:
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.custom_minimum_size = Vector2(160, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = float(GameSettings.get_value(key))
	var value := Label.new()
	value.custom_minimum_size = Vector2(52, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.text = shown.call(slider.value)
	slider.value_changed.connect(func(v):
		GameSettings.set_value(key, v)
		value.text = shown.call(v))
	var row := _row(text, slider)
	row.add_child(value)
	return row


func _check_row(text: String, key: String, node_name: String) -> HBoxContainer:
	var check := CheckBox.new()
	check.name = node_name
	check.button_pressed = bool(GameSettings.get_value(key))
	check.toggled.connect(func(on): GameSettings.set_value(key, on))
	return _row(text, check)


func _on_display_mode_selected(index: int) -> void:
	var mode := _display_mode.get_item_id(index)
	save_display_mode(mode)
	print("[OptionsMenu] Display mode: %s." % DISPLAY_MODE_NAMES[mode])


## The keys, in a panel over the settings (Esc or Back closes it).
func _show_controls() -> void:
	if get_node_or_null("ControlsPanel"):
		return
	var panel := PanelContainer.new()
	panel.name = "ControlsPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var title := _header("Controls")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var grid := GridContainer.new()
	grid.name = "Keys"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	for entry in CONTROLS:
		var key := Label.new()
		key.text = entry[0]
		key.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
		grid.add_child(key)
		var what := Label.new()
		what.text = entry[1]
		grid.add_child(what)
	column.add_child(grid)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(panel.queue_free)
	column.add_child(back)
	add_child(panel)


func _on_highlight_toggle_changed(pressed: bool) -> void:
	RoutineManager.enable_object_highlights = pressed
	print("[OptionsMenu] Objective highlights %s." % ("ENABLED" if pressed else "DISABLED"))


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	
	if event.is_action_pressed("pause_menu"):
		var controls := get_node_or_null("ControlsPanel")
		if controls:
			controls.queue_free()
		else:
			hide_menu()
		get_viewport().set_input_as_handled()
		return
	
	# Consume all action events while the menu is open so the player
	# cannot jump, interact, or move via input while configuring options.
	# Uses _unhandled_input so UI controls (like sliders) get priority over
	# this catch-all consumer.
	if event.is_action_type():
		get_viewport().set_input_as_handled()


## Builds a slider row for each existing AudioServer bus.
func _build_sliders() -> void:
	if not _slider_container:
		return
	
	# Clear existing children (useful if rebuilt)
	for child in _slider_container.get_children():
		child.queue_free()
	_bus_sliders.clear()
	
	for i in AudioServer.bus_count:
		var bus_name := AudioServer.get_bus_name(i)
		if bus_name == "Entity":
			continue
		var slider := HSlider.new()
		
		slider.name = bus_name + "Slider"
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = db_to_linear(AudioServer.get_bus_volume_db(i))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# Label the slider with the bus name and current percentage
		var label := Label.new()
		label.name = bus_name + "Label"
		label.text = _format_bus_label(bus_name, slider.value)
		label.theme_type_variation = "HeaderSmall"
		
		var row := HBoxContainer.new()
		row.name = bus_name + "Row"
		row.add_child(label)
		row.add_child(slider)
		_slider_container.add_child(row)
		
		# Update label text when the slider changes
		slider.value_changed.connect(_on_slider_value_changed.bind(i, label))
		_bus_sliders[bus_name] = slider


func _get_display_name(bus_name: String) -> String:
	return DISPLAY_NAMES.get(bus_name, bus_name)


func _format_bus_label(bus_name: String, linear: float) -> String:
	return "%s: %d%%" % [_get_display_name(bus_name), int(linear * 100.0)]


func _on_slider_value_changed(linear: float, bus_index: int, label: Label) -> void:
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear))
	_sync_entity_to_sfx(bus_index, linear)
	label.text = _format_bus_label(AudioServer.get_bus_name(bus_index), linear)


func _on_back_pressed() -> void:
	hide_menu()


## Shows the options menu and refreshes sliders to match current bus volumes.
func show_menu() -> void:
	_refresh_slider_values()
	visible = true
	if _back_button:
		_back_button.grab_focus()


## Hides the options menu.
func hide_menu() -> void:
	visible = false


## Ensures the Entity bus volume always matches the SFX bus volume.
## Called on boot (via _refresh_slider_values) and on every SFX slider change.
func _sync_entity_to_sfx(sfx_bus_index: int, linear: float) -> void:
	var sfx_bus_name := AudioServer.get_bus_name(sfx_bus_index)
	if sfx_bus_name != "SFX":
		return
	var entity_index := AudioServer.get_bus_index("Entity")
	if entity_index == -1:
		return
	AudioServer.set_bus_volume_db(entity_index, linear_to_db(linear))

## Refreshes slider values without rebuilding the whole UI.
func _refresh_slider_values() -> void:
	for i in AudioServer.bus_count:
		var bus_name := AudioServer.get_bus_name(i)
		var slider: HSlider = _bus_sliders.get(bus_name, null) as HSlider
		if slider:
			slider.set_block_signals(true)
			slider.value = db_to_linear(AudioServer.get_bus_volume_db(i))
			slider.set_block_signals(false)
			var row := slider.get_parent() as HBoxContainer
			if row:
				var label := row.get_node_or_null(bus_name + "Label") as Label
				if label:
					label.text = _format_bus_label(bus_name, slider.value)
	
	# Boot-time sync: replicate SFX volume onto the Entity bus
	var sfx_index := AudioServer.get_bus_index("SFX")
	if sfx_index >= 0:
		_sync_entity_to_sfx(sfx_index, db_to_linear(AudioServer.get_bus_volume_db(sfx_index)))
