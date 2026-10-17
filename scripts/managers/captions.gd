extends CanvasLayer
## Captions (autoload; Options > Accessibility > Captions, off by default):
## the sounds the game depends on, as a line at the bottom of the screen,
## with roughly where they came from: "[a breath, close behind]",
## "[footsteps upstairs]". For deaf players and laptop speakers.
##
##   Captions.show_at("knocking on glass", window.global_position)
##   Captions.show_text("a car alarm, outside")
##
## Off: nothing is shown (and nothing about the sounds changes).

const SETTING := "accessibility/captions"
const SIZE_SETTING := "accessibility/caption_size"
## The caption's font size: Small, Medium, Large.
const SIZES := [16, 20, 28]
## Seconds a caption stays.
const HOLD := 2.6
## The same caption again within this many seconds isn't repeated.
const REPEAT_GAP := 4.0

var _label: Label
var _left := 0.0
var _last := {}   ## caption -> Time.get_ticks_msec() it was last shown
## The last caption shown (for the tests).
var last_text := ""


func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.name = "Caption"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 6)
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_label.offset_left = -480
	_label.offset_right = 480
	_label.offset_top = -150
	_label.offset_bottom = -118
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.modulate.a = 0.0
	add_child(_label)
	apply_size(int(GameSettings.get_value(SIZE_SETTING)))


## Options > Accessibility > Caption Size: 0 Small, 1 Medium, 2 Large.
func apply_size(size: int) -> void:
	var font_size: int = SIZES[clampi(size, 0, SIZES.size() - 1)]
	_label.add_theme_font_size_override("font_size", font_size)
	_label.offset_top = -118 - font_size * 1.6


func enabled() -> bool:
	return bool(GameSettings.get_value(SETTING))


## A caption with no direction.
func show_text(text: String) -> void:
	_show("[%s]" % text)


## A caption for a sound at `at`: "[text, where]" from the player's point of
## view (close / behind / to the left / upstairs...).
func show_at(text: String, at: Vector3) -> void:
	var where := direction_words(at)
	_show("[%s]" % (text if where == "" else "%s, %s" % [text, where]))


## Where `at` is from the player's camera, in words ("" if no camera).
func direction_words(at: Vector3) -> String:
	var camera := get_viewport().get_camera_3d() if get_viewport() else null
	if camera == null:
		return ""
	var offset := at - camera.global_position
	if offset.y > 2.2:
		return "upstairs" if offset.length() < 20.0 else "above"
	if offset.y < -2.2 and Vector2(offset.x, offset.z).length() < 12.0:
		return "downstairs"
	var flat := Vector3(offset.x, 0.0, offset.z)
	var near := "close " if flat.length() < 4.0 else ""
	if flat.length() > 25.0:
		near = "far off "
	var forward := -camera.global_basis.z
	forward.y = 0.0
	var right := camera.global_basis.x
	right.y = 0.0
	var ahead := flat.normalized().dot(forward.normalized())
	var side := flat.normalized().dot(right.normalized())
	var bearing := "ahead"
	if ahead < -0.5:
		bearing = "behind"
	elif side > 0.5:
		bearing = "to the right"
	elif side < -0.5:
		bearing = "to the left"
	return (near + bearing).strip_edges()


func _show(text: String) -> void:
	if not enabled():
		return
	var now := Time.get_ticks_msec()
	if _last.has(text) and now - int(_last[text]) < REPEAT_GAP * 1000.0:
		return
	_last[text] = now
	last_text = text
	_label.text = text
	_label.modulate.a = 1.0
	_left = HOLD


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left < 0.6:
		_label.modulate.a = maxf(_left / 0.6, 0.0)
