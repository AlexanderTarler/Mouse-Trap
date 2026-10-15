class_name Phone
extends Panel
## The player's phone: a dark body, a screen with a status bar (time, signal
## bars, service), a message thread and a text field. Used by the opening
## (the office's message, "no service") and by the escape endings' epilogue.
## Its text is in the engine's plain sans font (a phone's, not the game's
## typewriter), big enough to read at a glance.
##
##   var phone := Phone.new()
##   add_child(phone)
##   phone.build("Svea Naturinstitut · Field office", "15:02")
##   phone.bubble("Welcome to the field...", false, "Svea Naturinstitut · 12:41")

const SIZE := Vector2(440, 720)
const TEXT := Color(0.1, 0.1, 0.12)

var service: Label
var input_line: Label
var _thread: VBoxContainer
var _bars: Array[ColorRect] = []


func build(header_text: String, time_text: String, service_text: String = "No service") -> void:
	visible = false
	size = SIZE
	var look := Theme.new()
	look.default_font = ThemeDB.fallback_font
	theme = look
	var body := _flat(Color(0.07, 0.07, 0.08), 34)
	body.border_color = Color(0.2, 0.2, 0.22)
	body.set_border_width_all(3)
	add_theme_stylebox_override("panel", body)
	var screen := Panel.new()
	screen.add_theme_stylebox_override("panel", _flat(Color(0.93, 0.93, 0.95), 22))
	screen.position = Vector2(16, 18)
	screen.size = SIZE - Vector2(32, 36)
	add_child(screen)
	# Status bar.
	var time := _label(time_text, 17, TEXT)
	time.position = Vector2(22, 10)
	screen.add_child(time)
	service = _label(service_text, 15, Color(0.35, 0.35, 0.38))
	service.position = Vector2(screen.size.x - 200, 11)
	service.size = Vector2(118, 20)
	service.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	screen.add_child(service)
	for i in 4:
		var bar := ColorRect.new()
		var h := 5.0 + i * 3.5
		bar.size = Vector2(4, h)
		bar.position = Vector2(screen.size.x - 66 + i * 7, 29 - h)
		screen.add_child(bar)
		_bars.append(bar)
	set_bars(0)
	# The conversation header.
	var header := _label(header_text, 17, Color(0.15, 0.15, 0.18))
	header.position = Vector2(0, 44)
	header.size = Vector2(screen.size.x, 26)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen.add_child(header)
	var rule := ColorRect.new()
	rule.color = Color(0.8, 0.8, 0.83)
	rule.position = Vector2(0, 78)
	rule.size = Vector2(screen.size.x, 1)
	screen.add_child(rule)
	_thread = VBoxContainer.new()
	_thread.position = Vector2(14, 92)
	_thread.size = Vector2(screen.size.x - 28, screen.size.y - 166)
	_thread.add_theme_constant_override("separation", 12)
	screen.add_child(_thread)
	# The text field.
	var field := Panel.new()
	field.add_theme_stylebox_override("panel", _flat(Color(1, 1, 1), 18))
	field.position = Vector2(12, screen.size.y - 60)
	field.size = Vector2(screen.size.x - 24, 44)
	screen.add_child(field)
	input_line = _label("", 17, TEXT)
	input_line.position = Vector2(16, 9)
	input_line.size = Vector2(field.size.x - 32, 26)
	input_line.clip_text = true
	field.add_child(input_line)


func set_bars(lit: int) -> void:
	for i in _bars.size():
		_bars[i].color = Color(0.15, 0.15, 0.18) if i < lit else Color(0.75, 0.75, 0.78)


## A message bubble: grey on the left (received) or blue on the right (sent),
## with a line under it. Returns {"status": Label, "row": Control}.
func bubble(text: String, mine: bool, note: String) -> Dictionary:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var holder := HBoxContainer.new()
	holder.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	var box := PanelContainer.new()
	var style := _flat(Color(0.2, 0.45, 0.95) if mine else Color(0.82, 0.82, 0.86), 16)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	box.add_theme_stylebox_override("panel", style)
	var label := _label(text, 18, Color.WHITE if mine else TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(290, 0)
	box.add_child(label)
	holder.add_child(box)
	row.add_child(holder)
	var status := _label(note, 13, Color(0.45, 0.45, 0.5))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mine else HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(status)
	_thread.add_child(row)
	row.modulate.a = 0.0
	create_tween().tween_property(row, "modulate:a", 1.0, 0.3)
	return {"status": status, "row": row}


## Slides up into view from below the bottom edge, right of centre.
func slide_in(view: Vector2, duration: float = 0.6) -> void:
	position = Vector2(view.x * 0.5 + 120.0, view.y + 20.0)
	visible = true
	create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) \
		.tween_property(self, "position:y", view.y - SIZE.y + 70.0, duration)


func slide_out(view: Vector2, duration: float = 0.5) -> void:
	create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN) \
		.tween_property(self, "position:y", view.y + 20.0, duration)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


static func _flat(color: Color, radius: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box
