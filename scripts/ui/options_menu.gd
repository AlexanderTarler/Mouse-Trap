extends Control
class_name OptionsMenu

## OptionsMenu — the settings, on the main menu and in the pause menu.
##
## Four tabs, each a scrolling list of rows (the label on the left, the
## control, its value on the right):
##   Audio          the volumes, the microphone (with a level meter)
##   Video          display mode, graphics quality, brightness (and its
##                  calibration screen), field of view
##   Controls       mouse sensitivity, invert Y, and every key (click one,
##                  press a new key; GameKeys)
##   Accessibility  captions and their size, objective highlights, head bob,
##                  screen shake
## "Reset to Defaults" puts every setting and key back. Settings are saved and
## applied by GameSettings (main_menu.gd applies them at startup). The menu
## runs with PROCESS_MODE_ALWAYS so it works while the game is paused.

enum DisplayMode { WINDOWED, BORDERLESS, FULLSCREEN }
const DISPLAY_MODE_NAMES := ["Windowed", "Borderless", "Fullscreen"]
const TAB_NAMES := ["Audio", "Video", "Controls", "Accessibility"]
## [setting, label, slider node name].
const VOLUMES := [
	["audio/master", "Master Volume", "MasterSlider"],
	["audio/ambient", "Ambient", "AmbientSlider"],
	["audio/sfx", "Sound Effects", "SFXSlider"],
	["audio/room_echo", "Room Echo", "RoomEchoSlider"],
]
## Keys that can't be changed, listed under the rest.
const FIXED_KEYS := [["Esc", "Pause / close"]]
const CAPTION_SIZES := ["Small", "Medium", "Large"]
const ACCENT := Color(1.0, 0.9, 0.7)
const CLASH := Color(1.0, 0.55, 0.35)
const CONTROL_WIDTH := 240.0
const VALUE_WIDTH := 64.0
## The panel (in the 1920x1080 layout: fits a 720p screen).
const PANEL_SIZE := Vector2(780, 640)
## The switches' pictures (the theme has none: CheckButtons were a dot).
static var _switch_on: Texture2D
static var _switch_off: Texture2D

@onready var _back_button: Button = %BackButton

var _tabs: TabContainer
var _display_mode: OptionButton = null
## The microphone's level meter (it listens only while the microphone is on).
var _mic_meter: ProgressBar
var _mic_fill: StyleBoxFlat
var _mic_listener: PlayerVoice
## The key buttons (action -> Button), and the one waiting for a key.
var _key_buttons := {}
var _rebinding := ""
var _key_note: Label
var _reset_button: Button
var _reset_armed := 0.0


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
	if not GameKeys._applied:
		GameKeys.apply()
	GameFonts.use_title($PanelContainer/VBoxContainer/TitleLabel)
	var panel := $PanelContainer as PanelContainer
	panel.custom_minimum_size = PANEL_SIZE
	panel.offset_left = -PANEL_SIZE.x * 0.5
	panel.offset_right = PANEL_SIZE.x * 0.5
	panel.offset_top = -PANEL_SIZE.y * 0.5
	panel.offset_bottom = PANEL_SIZE.y * 0.5
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.07, 0.07, 0.065, 0.97)
	frame.border_color = Color(1.0, 0.9, 0.7, 0.18)
	frame.set_border_width_all(1)
	frame.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", frame)
	($PanelContainer/VBoxContainer/TitleLabel as Label).add_theme_font_size_override("font_size", 30)
	var box := $PanelContainer/VBoxContainer
	_tabs = TabContainer.new()
	_tabs.name = "Tabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	box.move_child(_tabs, $PanelContainer/VBoxContainer/HSeparator.get_index() + 1)
	_mic_listener = PlayerVoice.new()
	_mic_listener.name = "MicLevel"
	_mic_listener.meter_only = true
	add_child(_mic_listener)
	_build_tabs()
	# Reset to Defaults and Back along the bottom.
	var bottom := HBoxContainer.new()
	bottom.name = "Bottom"
	bottom.add_theme_constant_override("separation", 12)
	box.add_child(bottom)
	_reset_button = Button.new()
	_reset_button.name = "ResetButton"
	_reset_button.text = "Reset to Defaults"
	_reset_button.pressed.connect(_on_reset_pressed)
	bottom.add_child(_reset_button)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap)
	_back_button.reparent(bottom)
	_back_button.custom_minimum_size = Vector2(120, 0)
	_back_button.pressed.connect(_on_back_pressed)


func _build_tabs() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_key_buttons.clear()
	_mic_meter = null
	_build_audio(_tab("Audio"))
	_build_video(_tab("Video"))
	_build_controls(_tab("Controls"))
	_build_accessibility(_tab("Accessibility"))


## A tab: a scrolling column of rows.
func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.name = "Rows"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	return column


func _build_audio(column: VBoxContainer) -> void:
	for volume in VOLUMES:
		column.add_child(_slider_row(volume[1], volume[0], 0.0, 1.0, 0.05, volume[2],
			func(v): return "%d%%" % roundi(v * 100.0)))
	column.add_child(_header("Microphone"))
	column.add_child(_check_row("Microphone", "audio/microphone", "MicrophoneCheck"))
	column.add_child(_tip("The Entity can hear you: a gasp or a shout carries. Only loud moments count; nothing is recorded to disk or sent anywhere."))
	column.add_child(_slider_row("Mic Threshold", "audio/mic_threshold_db", -45.0, -6.0, 1.0, "MicThresholdSlider",
		func(v): return "%d dB" % roundi(v)))
	_mic_meter = ProgressBar.new()
	_mic_meter.name = "MicMeter"
	_mic_meter.min_value = -60.0
	_mic_meter.max_value = 0.0
	_mic_meter.show_percentage = false
	_mic_meter.custom_minimum_size = Vector2(CONTROL_WIDTH, 12)
	_mic_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.45)
	back.border_color = Color(1, 1, 1, 0.25)
	back.set_border_width_all(1)
	_mic_fill = StyleBoxFlat.new()
	_mic_fill.bg_color = ACCENT
	_mic_meter.add_theme_stylebox_override("background", back)
	_mic_meter.add_theme_stylebox_override("fill", _mic_fill)
	column.add_child(_row("Level (say something)", _mic_meter))
	column.add_child(_tip("Over the threshold the bar turns red: that's loud enough for the Entity."))


func _build_video(column: VBoxContainer) -> void:
	_display_mode = OptionButton.new()
	_display_mode.name = "DisplayModeOption"
	for mode in DISPLAY_MODE_NAMES.size():
		if mode == DisplayMode.BORDERLESS and OS.has_feature("web"):
			continue
		_display_mode.add_item(DISPLAY_MODE_NAMES[mode], mode)
	_display_mode.select(maxi(_display_mode.get_item_index(saved_display_mode()), 0))
	_display_mode.item_selected.connect(_on_display_mode_selected)
	column.add_child(_row("Display Mode", _display_mode))
	column.add_child(_option_row("Graphics Quality", "video/quality", GraphicsQuality.NAMES, "QualityOption"))
	column.add_child(_tip("Shadows, ground fog, how far the small plants are drawn." + (" Low runs smoothest in a browser." if OS.has_feature("web") else "")))
	column.add_child(_slider_row("Brightness", "video/brightness", 0.6, 1.8, 0.05, "BrightnessSlider",
		func(v): return "%d%%" % roundi(v * 100.0)))
	var calibrate := Button.new()
	calibrate.name = "CalibrateButton"
	calibrate.text = "Calibrate..."
	calibrate.pressed.connect(_calibrate)
	column.add_child(_row("Dark should stay dark", calibrate))
	column.add_child(_slider_row("Field of View", "video/fov", 60.0, 100.0, 1.0, "FovSlider",
		func(v): return "%d" % roundi(v)))


func _build_controls(column: VBoxContainer) -> void:
	column.add_child(_slider_row("Mouse Sensitivity", "controls/mouse_sensitivity", 0.25, 3.0, 0.05, "SensitivitySlider",
		func(v): return "%.2fx" % v))
	column.add_child(_check_row("Invert Mouse Y", "controls/invert_y", "InvertYCheck"))
	column.add_child(_header("Keys"))
	column.add_child(_tip("Click a key, then press the new one (Esc to cancel)."))
	var grid := GridContainer.new()
	grid.name = "Keys"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	for entry in GameKeys.BINDINGS:
		var what := Label.new()
		what.text = entry[1]
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(what)
		var button := Button.new()
		button.name = String(entry[0]) + "Key"
		button.custom_minimum_size = Vector2(150, 0)
		button.add_theme_stylebox_override("normal", _key_style(0.25))
		button.add_theme_stylebox_override("hover", _key_style(0.6))
		button.add_theme_stylebox_override("pressed", _key_style(0.9))
		button.add_theme_stylebox_override("focus", _key_style(0.6))
		button.pressed.connect(_start_rebind.bind(entry[0]))
		grid.add_child(button)
		_key_buttons[entry[0]] = button
	for entry in FIXED_KEYS:
		var what := Label.new()
		what.text = entry[1]
		grid.add_child(what)
		var key := Label.new()
		key.text = entry[0]
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.add_theme_color_override("font_color", ACCENT)
		grid.add_child(key)
	column.add_child(grid)
	_key_note = _tip("")
	_key_note.name = "KeyNote"
	_key_note.add_theme_color_override("font_color", CLASH)
	column.add_child(_key_note)
	var reset_keys := Button.new()
	reset_keys.name = "ResetKeysButton"
	reset_keys.text = "Reset Keys"
	reset_keys.pressed.connect(func():
		_rebinding = ""
		GameKeys.reset()
		_refresh_keys())
	column.add_child(reset_keys)
	_refresh_keys()


func _build_accessibility(column: VBoxContainer) -> void:
	column.add_child(_check_row("Captions", "accessibility/captions", "CaptionsCheck"))
	column.add_child(_tip("Important sounds as text, with where they came from."))
	column.add_child(_option_row("Caption Size", "accessibility/caption_size", CAPTION_SIZES, "CaptionSizeOption"))
	column.add_child(_check_row("Objective Highlights", "gameplay/objective_highlights", "HighlightsCheck"))
	column.add_child(_tip("An outline on the next thing to do, through walls."))
	column.add_child(_check_row("Head Bob", "video/head_bob", "HeadBobCheck"))
	column.add_child(_check_row("Screen Shake", "video/screen_shake", "ScreenShakeCheck"))
	column.add_child(_tip("The camera shaking when you stare it down, and at the end."))


func _process(delta: float) -> void:
	if _reset_armed > 0.0:
		_reset_armed -= delta
		if _reset_armed <= 0.0:
			_reset_button.text = "Reset to Defaults"
	if _mic_meter and is_instance_valid(_mic_meter) and _mic_listener:
		_mic_meter.value = _mic_listener.level_db
		var over: bool = _mic_listener.level_db > PlayerVoice.threshold_db()
		_mic_fill.bg_color = Color(1.0, 0.35, 0.28) if over else ACCENT


# ─── ROWS ──────────────────────────────────────────────────────

func _header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", ACCENT)
	return label


func _tip(text: String) -> Label:
	var tip := Label.new()
	tip.text = text
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 12)
	tip.modulate = Color(1, 1, 1, 0.6)
	return tip


## The label on the left, the control, the value on the right (blank for
## controls that show their own).
func _row(text: String, control: Control, value: Label = null) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	control.custom_minimum_size.x = CONTROL_WIDTH
	row.add_child(control)
	if not value:
		value = Label.new()
	value.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return row


func _slider_row(text: String, key: String, low: float, high: float, step: float, node_name: String, shown: Callable) -> HBoxContainer:
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = float(GameSettings.get_value(key))
	var value := Label.new()
	value.text = shown.call(slider.value)
	slider.value_changed.connect(func(v):
		GameSettings.set_value(key, v)
		value.text = shown.call(v))
	return _row(text, slider, value)


## A switch: plainly on or off.
func _check_row(text: String, key: String, node_name: String) -> HBoxContainer:
	var check := CheckButton.new()
	check.name = node_name
	check.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if not _switch_on:
		_switch_on = _switch_icon(true)
		_switch_off = _switch_icon(false)
	for state in ["", "_disabled", "_mirrored"]:
		check.add_theme_icon_override("checked" + state, _switch_on)
		check.add_theme_icon_override("unchecked" + state, _switch_off)
	check.button_pressed = bool(GameSettings.get_value(key))
	var value := Label.new()
	value.text = "On" if check.button_pressed else "Off"
	check.toggled.connect(func(on):
		GameSettings.set_value(key, on)
		value.text = "On" if on else "Off")
	return _row(text, check, value)


## A switch, drawn: a pill with its knob left (off) or right and lit (on).
static func _switch_icon(on: bool) -> Texture2D:
	var w := 44
	var h := 22
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := Color(0.85, 0.62, 0.3) if on else Color(0.28, 0.28, 0.27)
	var knob := Color(1.0, 0.96, 0.88) if on else Color(0.62, 0.62, 0.6)
	var r := h * 0.5
	var knob_x := w - r if on else r
	for y in h:
		for x in w:
			var cx := clampf(x + 0.5, r, w - r)
			var inside := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(cx, r)) <= r - 0.5
			if not inside:
				continue
			var color := track
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(knob_x, r)) <= r - 3.0:
				color = knob
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _option_row(text: String, key: String, names: Array, node_name: String) -> HBoxContainer:
	var option := OptionButton.new()
	option.name = node_name
	for i in names.size():
		option.add_item(names[i], i)
	option.select(clampi(int(GameSettings.get_value(key)), 0, names.size() - 1))
	option.item_selected.connect(func(index): GameSettings.set_value(key, option.get_item_id(index)))
	return _row(text, option)


# ─── KEYS ──────────────────────────────────────────────────────

## A key: a box with a light border (brighter under the mouse).
func _key_style(border: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.11)
	style.border_color = Color(ACCENT, border)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(4)
	return style


func _start_rebind(action: String) -> void:
	_rebinding = action
	_refresh_keys()


## Each key's label (on this keyboard), the one being changed asking for a
## key, and keys used twice marked.
func _refresh_keys() -> void:
	var clashes: Array[String] = []
	for action in _key_buttons:
		var button: Button = _key_buttons[action]
		var shared := GameKeys.clashes(action)
		button.text = "Press a key..." if action == _rebinding else GameKeys.label(action)
		button.add_theme_color_override("font_color", CLASH if not shared.is_empty() else ACCENT)
		if not shared.is_empty():
			clashes.append(GameKeys.label(action))
	if _key_note:
		_key_note.text = "" if clashes.is_empty() else "Used twice: %s. Both actions will happen on that key." % ", ".join(_unique(clashes))


func _unique(items: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for item in items:
		if not out.has(item):
			out.append(item)
	return out


func _input(event: InputEvent) -> void:
	if not visible or _rebinding == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode != KEY_ESCAPE:
			var physical := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			GameKeys.rebind(_rebinding, physical)
		_rebinding = ""
		_refresh_keys()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_rebinding = ""
		_refresh_keys()


## The Controls tab (the keys).
func _show_controls() -> void:
	_tabs.current_tab = TAB_NAMES.find("Controls")


# ─── ACTIONS ───────────────────────────────────────────────────

func _on_display_mode_selected(index: int) -> void:
	var mode := _display_mode.get_item_id(index)
	save_display_mode(mode)
	print("[OptionsMenu] Display mode: %s." % DISPLAY_MODE_NAMES[mode])


func _calibrate() -> void:
	var screen := BrightnessCalibration.new()
	screen.name = "Calibration"
	add_child(screen)
	screen.closed.connect(_on_calibrated)


## The brightness slider shows what the calibration chose.
func _on_calibrated() -> void:
	var slider := find_child("BrightnessSlider", true, false) as HSlider
	if slider:
		slider.set_value_no_signal(float(GameSettings.get_value("video/brightness")))
		var value := slider.get_parent().get_child(2) as Label
		value.text = "%d%%" % roundi(slider.value * 100.0)


## Twice to be sure: the first press asks.
func _on_reset_pressed() -> void:
	if _reset_armed <= 0.0:
		_reset_armed = 3.0
		_reset_button.text = "Click again to reset"
		return
	_reset_armed = 0.0
	_reset_button.text = "Reset to Defaults"
	var tab := _tabs.current_tab
	_rebinding = ""
	GameSettings.reset_all()
	_build_tabs()
	_tabs.current_tab = tab


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause_menu"):
		var calibration := get_node_or_null("Calibration")
		if calibration:
			calibration.close()
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


func _on_back_pressed() -> void:
	hide_menu()


func show_menu() -> void:
	visible = true
	if _back_button:
		_back_button.grab_focus()


func hide_menu() -> void:
	_rebinding = ""
	# (The brightness screen is a layer of its own: it doesn't hide with us.)
	var calibration := get_node_or_null("Calibration")
	if calibration:
		calibration.close()
	visible = false
