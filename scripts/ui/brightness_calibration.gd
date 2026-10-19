class_name BrightnessCalibration
extends CanvasLayer
## The brightness screen: on black, three figures standing at the treeline,
## each a shade darker than the last. Adjust until the faintest is just gone
## and the middle one barely there: the night then reads as it was made, dark
## but not a black screen. Shown on the first launch (main_menu.gd) and from
## Options > Video > Calibrate. Saves "video/brightness" as it moves.
## The first launch (first_launch): then a second page, the microphone and
## the objective highlights (both off unless turned on here), and where to
## find them again.

signal closed

## The figures' shades (0-1, as drawn before the brightness curve): should
## vanish, barely show, plainly show.
const SHADES := [0.008, 0.03, 0.085]
const LOW := 0.6
const HIGH := 1.8

## The first launch: the microphone and highlights page after Done.
var first_launch := false
var _slider: HSlider
var _figures: Control
var _column: VBoxContainer


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.custom_minimum_size = Vector2(620, 0)
	column.add_theme_constant_override("separation", 18)
	add_child(column)
	_column = column
	var title := Label.new()
	title.text = "Brightness"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameFonts.use_title(title)
	title.add_theme_font_size_override("font_size", 40)
	column.add_child(title)
	_figures = Control.new()
	_figures.custom_minimum_size = Vector2(620, 220)
	_figures.draw.connect(_draw_figures)
	column.add_child(_figures)
	var say := Label.new()
	say.text = "Adjust until the figure on the left is gone\nand the one in the middle is only just there."
	say.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	say.modulate = Color(1, 1, 1, 0.75)
	column.add_child(say)
	_slider = HSlider.new()
	_slider.name = "CalibrationSlider"
	_slider.min_value = LOW
	_slider.max_value = HIGH
	_slider.step = 0.02
	_slider.custom_minimum_size = Vector2(420, 0)
	_slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_slider.value = float(GameSettings.get_value("video/brightness"))
	_slider.value_changed.connect(func(v):
		GameSettings.set_value("video/brightness", v)
		_figures.queue_redraw())
	column.add_child(_slider)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
	var reset := Button.new()
	reset.text = "Default"
	reset.pressed.connect(func(): _slider.value = float(GameSettings.DEFAULTS["video/brightness"]))
	buttons.add_child(reset)
	var done := Button.new()
	done.name = "DoneButton"
	done.text = "Done"
	done.custom_minimum_size = Vector2(120, 0)
	done.pressed.connect(func(): _show_setup() if first_launch else close())
	buttons.add_child(done)
	done.grab_focus.call_deferred()


## The first launch's second page: two choices, both off to begin with.
func _show_setup() -> void:
	GameSettings.set_value("video/calibrated", true)
	for child in _column.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "Before You Start"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameFonts.use_title(title)
	title.add_theme_font_size_override("font_size", 40)
	_column.add_child(title)
	_column.add_child(_choice("Microphone", "audio/microphone", "SetupMicrophoneCheck",
		"The Entity can hear you: a gasp or a shout carries. Only loud moments count; nothing is recorded to disk or sent anywhere."
		+ (" Your browser will ask for permission." if OS.has_feature("web") else "")))
	_column.add_child(_choice("Objective Highlights", "gameplay/objective_highlights", "SetupHighlightsCheck",
		"An outline on the next thing to do, through walls. Off: find your own way."))
	var later := Label.new()
	later.text = "Changed your mind? Both are in Settings: the microphone under
Audio, the highlights under Accessibility (in the pause menu too)."
	later.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	later.modulate = Color(1, 1, 1, 0.6)
	_column.add_child(later)
	var done := Button.new()
	done.name = "SetupDoneButton"
	done.text = "Done"
	done.custom_minimum_size = Vector2(120, 0)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.pressed.connect(close)
	_column.add_child(done)
	done.grab_focus.call_deferred()


## A setting's switch (off here unless the player turns it on), and what it's for.
func _choice(text: String, key: String, node_name: String, about: String) -> VBoxContainer:
	GameSettings.set_value(key, false)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var check := CheckButton.new()
	check.name = node_name
	check.text = text
	check.button_pressed = false
	check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	check.toggled.connect(func(on): GameSettings.set_value(key, on))
	box.add_child(check)
	var tip := Label.new()
	tip.text = about
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(560, 0)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.modulate = Color(1, 1, 1, 0.75)
	tip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(tip)
	return box


func close() -> void:
	GameSettings.set_value("video/calibrated", true)
	closed.emit()
	queue_free()


## How a shade looks with this brightness (the same curve as the brightness
## layer: GameSettings._apply_brightness).
static func shown(shade: float, gamma: float) -> float:
	return pow(shade, 1.0 / gamma)


func _draw_figures() -> void:
	var gamma := _slider.value if _slider else 1.0
	var width := _figures.size.x
	for i in SHADES.size():
		var tone := shown(SHADES[i], gamma)
		var color := Color(tone, tone, tone * 1.04)
		var x := width * (0.2 + 0.3 * i)
		_draw_figure(Vector2(x, _figures.size.y - 6.0), color)


## A tall, thin figure: a head, long arms, legs.
func _draw_figure(feet: Vector2, color: Color) -> void:
	var height := 200.0
	var head := feet + Vector2(0, -height + 14.0)
	_figures.draw_circle(head, 11.0, color)
	var neck := head + Vector2(0, 12.0)
	var hips := feet + Vector2(0, -height * 0.45)
	_figures.draw_line(neck, hips, color, 9.0, true)
	var shoulders := neck + Vector2(0, 14.0)
	_figures.draw_line(shoulders, shoulders + Vector2(-16, 92), color, 5.0, true)
	_figures.draw_line(shoulders, shoulders + Vector2(15, 96), color, 5.0, true)
	_figures.draw_line(hips, feet + Vector2(-10, 0), color, 6.0, true)
	_figures.draw_line(hips, feet + Vector2(10, 0), color, 6.0, true)
