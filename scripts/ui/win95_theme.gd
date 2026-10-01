class_name Win95Theme
extends RefCounted
## A Windows 95 look for the cabin computer (computer_ui.gd): grey bevelled
## buttons that press in, sunken white fields, navy title bars, a crisp
## system font, pixel-drawn desktop icons with labels on the teal desktop,
## and a taskbar with a Start button and a clock.

const FACE := Color8(192, 192, 192)
const LIGHT := Color8(255, 255, 255)
const SHADE := Color8(128, 128, 128)
const DARK := Color8(0, 0, 0)
const TEAL := Color8(0, 128, 128)
const NAVY := Color8(0, 0, 128)
## Bevel lines are this many pixels wide (1 looks lost at 1080p).
const PX := 2

static var _font: SystemFont = null
static var _bold: SystemFont = null


static func font(bold: bool = false) -> SystemFont:
	if bold and _bold:
		return _bold
	if not bold and _font:
		return _font
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["MS Sans Serif", "Microsoft Sans Serif", "Tahoma", "Arial"])
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NORMAL
	f.font_weight = 700 if bold else 400
	if bold:
		_bold = f
	else:
		_font = f
	return f


## A bevelled box: `raised` (buttons, windows) or sunken (fields, pressed).
## `fill` is the face colour. Drawn as a 9-slice texture: the four lines of a
## real Win95 bevel (light/shade inside, white/black outside).
static func bevel(raised: bool, fill: Color = FACE, margin: int = 6) -> StyleBoxTexture:
	var size := 6 * PX
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	var outer_tl := LIGHT if raised else SHADE
	var outer_br := DARK if raised else LIGHT
	var inner_tl := FACE.lightened(0.15) if raised else DARK
	var inner_br := SHADE if raised else FACE
	for i in size:
		for w in PX:
			# Outer ring.
			img.set_pixel(i, w, outer_tl)
			img.set_pixel(w, i, outer_tl)
			img.set_pixel(i, size - 1 - w, outer_br)
			img.set_pixel(size - 1 - w, i, outer_br)
	for i in range(PX, size - PX):
		for w in range(PX, 2 * PX):
			img.set_pixel(i, w, inner_tl)
			img.set_pixel(w, i, inner_tl)
			img.set_pixel(i, size - 1 - w, inner_br)
			img.set_pixel(size - 1 - w, i, inner_br)
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(img)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_texture_margin(side, 2 * PX)
		box.set_content_margin(side, margin)
	return box


static func flat(color: Color, margin: int = 4) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_content_margin_all(margin)
	return box


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = font()
	theme.default_font_size = 15
	for type in ["Label", "Button", "LineEdit", "OptionButton", "RichTextLabel", "CheckBox", "PopupMenu"]:
		theme.set_color("font_color", type, DARK)
	theme.set_color("font_hover_color", "Button", DARK)
	theme.set_color("font_pressed_color", "Button", DARK)
	theme.set_color("font_focus_color", "Button", DARK)
	theme.set_color("font_disabled_color", "Button", SHADE)
	theme.set_color("default_color", "RichTextLabel", DARK)
	theme.set_color("font_placeholder_color", "LineEdit", SHADE)
	theme.set_color("caret_color", "LineEdit", DARK)
	theme.set_color("selection_color", "LineEdit", NAVY)
	theme.set_color("font_selected_color", "LineEdit", LIGHT)
	for type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, bevel(true))
		theme.set_stylebox("hover", type, bevel(true))
		theme.set_stylebox("pressed", type, bevel(false))
		theme.set_stylebox("disabled", type, bevel(true))
		theme.set_stylebox("focus", type, StyleBoxEmpty.new())
	theme.set_stylebox("normal", "LineEdit", bevel(false, LIGHT))
	theme.set_stylebox("focus", "LineEdit", StyleBoxEmpty.new())
	theme.set_stylebox("read_only", "LineEdit", bevel(false, FACE))
	theme.set_stylebox("normal", "RichTextLabel", bevel(false, LIGHT, 8))
	theme.set_stylebox("panel", "Panel", bevel(true))
	theme.set_stylebox("panel", "PanelContainer", bevel(true))
	theme.set_stylebox("panel", "PopupMenu", bevel(true))
	theme.set_stylebox("hover", "PopupMenu", flat(NAVY))
	theme.set_color("font_hover_color", "PopupMenu", LIGHT)
	var line := StyleBoxLine.new()
	line.color = SHADE
	line.thickness = PX
	theme.set_stylebox("separator", "HSeparator", line)
	return theme


## A flat menu-bar entry (File, Edit...): no bevel, navy when hovered.
static func style_menu_entry(button: Button) -> void:
	button.flat = false
	for state in ["normal", "disabled"]:
		button.add_theme_stylebox_override(state, flat(Color(0, 0, 0, 0), 4))
	button.add_theme_stylebox_override("hover", flat(NAVY, 4))
	button.add_theme_stylebox_override("pressed", flat(NAVY, 4))
	button.add_theme_color_override("font_hover_color", LIGHT)
	button.add_theme_color_override("font_pressed_color", LIGHT)
	button.add_theme_color_override("font_color", DARK)


## A desktop icon: a pixel glyph with its label underneath, on the teal.
## `kind`: "exe", "txt", "bin", "logoff", "power", "warn".
static func style_desktop_icon(button: Button, kind: String) -> void:
	button.icon = icon(kind)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.expand_icon = false
	button.custom_minimum_size = Vector2(150, 84)
	button.size = button.custom_minimum_size
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var clear := flat(Color(0, 0, 0, 0), 2)
	button.add_theme_stylebox_override("normal", clear)
	button.add_theme_stylebox_override("hover", clear)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var selected := flat(Color(NAVY, 0.55), 2)
	button.add_theme_stylebox_override("pressed", selected)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, LIGHT)
	button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	button.add_theme_constant_override("outline_size", 2)
	button.add_theme_font_size_override("font_size", 14)


## A 32x32 (drawn at 2x) pixel icon.
static func icon(kind: String) -> ImageTexture:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match kind:
		"exe":
			_rect(img, 3, 6, 26, 21, DARK)
			_rect(img, 4, 7, 24, 19, FACE)
			_rect(img, 4, 7, 24, 4, NAVY)
			_rect(img, 6, 13, 20, 11, LIGHT)
			_rect(img, 7, 15, 10, 1, SHADE)
			_rect(img, 7, 18, 14, 1, SHADE)
		"txt":
			_rect(img, 7, 3, 18, 26, DARK)
			_rect(img, 8, 4, 16, 24, LIGHT)
			for row in [8, 11, 14, 17, 20, 23]:
				_rect(img, 10, row, 12, 1, SHADE)
		"bin":
			_rect(img, 8, 6, 16, 3, SHADE)
			_rect(img, 9, 9, 14, 19, DARK)
			_rect(img, 10, 10, 12, 17, FACE)
			for col in [12, 15, 18]:
				_rect(img, col, 11, 1, 15, SHADE)
		"logoff":
			_rect(img, 9, 4, 14, 24, DARK)
			_rect(img, 10, 5, 12, 22, Color8(128, 64, 0))
			_rect(img, 18, 15, 2, 2, Color8(255, 255, 0))
		"power":
			for a in 40:
				var t := float(a) / 40.0 * TAU
				if t > 0.6 and t < TAU - 0.6:
					var x := int(16 + sin(t) * 10)
					var y := int(17 - cos(t) * 10)
					_rect(img, x - 1, y - 1, 3, 3, Color8(200, 0, 0))
			_rect(img, 15, 4, 3, 12, Color8(200, 0, 0))
		"warn":
			for row in 20:
				_rect(img, 16 - row / 2, 6 + row, row + 1, 1, Color8(255, 210, 0))
			_rect(img, 15, 12, 2, 8, DARK)
			_rect(img, 15, 22, 2, 2, DARK)
	img.resize(64, 64, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


## The four-colour flag on the Start button.
static func start_logo() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_rect(img, 1, 1, 6, 6, Color8(255, 0, 0))
	_rect(img, 8, 1, 6, 6, Color8(0, 160, 0))
	_rect(img, 1, 8, 6, 6, Color8(0, 0, 255))
	_rect(img, 8, 8, 6, 6, Color8(255, 220, 0))
	img.resize(24, 24, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


static func _rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for yy in range(maxi(y, 0), mini(y + h, img.get_height())):
		for xx in range(maxi(x, 0), mini(x + w, img.get_width())):
			img.set_pixel(xx, yy, color)
