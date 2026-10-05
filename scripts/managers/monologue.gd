extends Node
## Monologue (autoload): the player's inner thoughts. A thought floats over
## the thing it is about (think(text, subject)): italic, warm and quoted, so it
## never reads like an objective or a tutorial prompt, drifting up and fading
## away. It shows through walls (it's in the player's head). With no subject,
## or a subject that is off screen, the thought floats in place a couple of
## metres ahead of where the player is looking (it stays there; the player
## can walk away from it). Each thought (by key, or by its text) is only ever
## thought once.
##
##   Monologue.think("Someone left a window for me to patch up - how kind.", window)

const COLOR := Color(1.0, 0.86, 0.62)
const OUTLINE := Color(0.06, 0.04, 0.02, 0.9)
## How high above the subject's centre the thought floats (m).
const HEIGHT := 1.2
const FADE_IN := 0.6
const FADE_OUT := 1.2
const DRIFT := 0.35
## With no subject on screen: this far ahead of the camera (m), and this far
## above the centre of view, clear of the crosshair.
const AHEAD := 2.2
const AHEAD_RAISE := 0.3

var _thought: Node = null
var _had := {}
## The line say() is showing ("" while a story thought from think() is).
var _said := ""
var _font: SystemFont = null


## Thinks `text` over `subject` for `duration` seconds (once per `key`).
## Returns false if it was already thought.
func think(text: String, subject: Node3D = null, duration: float = 5.0, key: String = "") -> bool:
	var id := key if key != "" else text
	if _had.has(id):
		return false
	_had[id] = true
	_clear()
	_show(text, subject, duration)
	print("[Monologue] \"%s\"" % text)
	return true


## A passing remark (feedback like "I can't carry any more." or "I should
## lock the door first."), over `subject` (usually the thing interacted with)
## in the same style. Unlike think() it can come again, but the same line
## isn't restarted while it's showing, and a story thought on screen isn't
## interrupted.
func say(text: String, duration: float = 3.5, subject: Node3D = null) -> void:
	if text.strip_edges().is_empty():
		return
	if is_instance_valid(_thought):
		if _said.is_empty() or _said == text:
			return
	_clear()
	_said = text
	_show(text, subject, duration)


## Over the subject if it's on screen, else in place ahead of the camera
## (on the screen only without a camera).
func _show(text: String, subject: Node3D, duration: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		_on_screen_line(text, duration)
		return
	if subject and is_instance_valid(subject):
		var anchor := _anchor(subject)
		if not camera.is_position_behind(anchor) and _on_screen(camera, anchor):
			_float(text, anchor, duration)
			return
	var view := camera.global_transform
	_float(text, view.origin - view.basis.z * AHEAD + view.basis.y * AHEAD_RAISE, duration)


## Forgets which thoughts were had (a new game).
func reset() -> void:
	_had.clear()
	_clear()


func has_thought(key: String) -> bool:
	return _had.has(key)


func _anchor(subject: Node3D) -> Vector3:
	if not subject:
		return Vector3.ZERO
	var box := AABB()
	var first := true
	for mesh in subject.find_children("*", "MeshInstance3D", true, false):
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	var centre: Vector3 = box.get_center() if not first else subject.global_position
	return centre + Vector3.UP * HEIGHT


func _on_screen(camera: Camera3D, point: Vector3) -> bool:
	var size := get_viewport().get_visible_rect().size
	var p := camera.unproject_position(point)
	return p.x > 0.0 and p.y > 0.0 and p.x < size.x and p.y < size.y


func _get_font() -> SystemFont:
	if not _font:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Times New Roman", "serif"])
		_font.font_italic = true
	return _font


func _float(text: String, at: Vector3, duration: float) -> void:
	var label := Label3D.new()
	label.name = "Thought"
	label.text = "“%s”" % text
	label.font = _get_font()
	label.font_size = 40
	label.outline_size = 10
	label.modulate = Color(COLOR, 0.0)
	label.outline_modulate = Color(OUTLINE, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.width = 900.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.render_priority = 10
	var scene := get_tree().current_scene
	if not scene:
		return
	scene.add_child(label)
	label.global_position = at
	_thought = label
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "modulate:a", 1.0, FADE_IN)
	tween.tween_property(label, "outline_modulate:a", 0.9, FADE_IN)
	tween.tween_property(label, "global_position:y", at.y + DRIFT, duration + FADE_OUT)
	tween.chain().tween_interval(maxf(duration - FADE_IN, 0.0))
	var out := tween.chain().set_parallel()
	out.tween_property(label, "modulate:a", 0.0, FADE_OUT)
	out.tween_property(label, "outline_modulate:a", 0.0, FADE_OUT)
	tween.chain().tween_callback(label.queue_free)


func _on_screen_line(text: String, duration: float) -> void:
	var layer := CanvasLayer.new()
	layer.name = "ThoughtLayer"
	layer.layer = 150
	var label := Label.new()
	label.text = "“%s”" % text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	label.anchor_left = 0.2
	label.anchor_right = 0.8
	label.offset_left = 0.0
	label.offset_right = 0.0
	label.offset_top = -200.0
	label.offset_bottom = -150.0
	label.add_theme_font_override("font", _get_font())
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", COLOR)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", 6)
	label.modulate.a = 0.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	var scene := get_tree().current_scene
	if not scene:
		return
	scene.add_child(layer)
	_thought = layer
	var tween := label.create_tween()
	tween.tween_property(label, "modulate:a", 1.0, FADE_IN)
	tween.tween_interval(maxf(duration - FADE_IN, 0.0))
	tween.tween_property(label, "modulate:a", 0.0, FADE_OUT)
	tween.tween_callback(layer.queue_free)


func _clear() -> void:
	if is_instance_valid(_thought):
		_thought.queue_free()
	_thought = null
	_said = ""
