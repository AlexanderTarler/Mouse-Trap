extends Node
## Monologue (autoload): the player's inner thoughts. A thought appears at
## the left of the screen, where it can't be missed: italic, warm and quoted,
## so it never reads like an objective or a tutorial prompt, drifting slowly
## up as it fades in and away. Each thought (by key, or by its text) is only
## ever thought once.
##
##   Monologue.think("Someone left a window for me to patch up - how kind.", window)
##
## The subject (what the thought is about) is still passed by callers, but
## no longer decides where it shows.

const COLOR := Color(1.0, 0.86, 0.62)
const OUTLINE := Color(0.06, 0.04, 0.02, 0.9)
const FADE_IN := 0.6
const FADE_OUT := 1.2
## Where on the screen (fractions of its size): the left side, below the
## HUD's bars, and how far it drifts up while showing (px).
const LEFT := 0.04
const RIGHT := 0.36
const TOP := 0.42
const DRIFT_PX := 26.0
const FONT_SIZE := 26

var _thought: Node = null
var _had := {}
## The line say() is showing ("" while a story thought from think() is).
var _said := ""
var _font: Font = null


## Thinks `text` for `duration` seconds (once per `key`).
## Returns false if it was already thought.
func think(text: String, _subject: Node3D = null, duration: float = 5.0, key: String = "") -> bool:
	var id := key if key != "" else text
	if _had.has(id):
		return false
	_had[id] = true
	_clear()
	_show(text, duration)
	print("[Monologue] \"%s\"" % text)
	return true


## A passing remark (feedback like "I can't carry any more." or "I should
## lock the door first."), in the same place and style. Unlike think() it can come again, but the same line
## isn't restarted while it's showing, and a story thought on screen isn't
## interrupted.
func say(text: String, duration: float = 3.5, _subject: Node3D = null) -> void:
	if text.strip_edges().is_empty():
		return
	if is_instance_valid(_thought):
		if _said.is_empty() or _said == text:
			return
	_clear()
	_said = text
	_show(text, duration)


## Forgets which thoughts were had (a new game).
func reset() -> void:
	_had.clear()
	_clear()


func has_thought(key: String) -> bool:
	return _had.has(key)


## The thoughts' face: the game's typewriter, in italic (bundled, so it is
## the same in the browser).
func _get_font() -> Font:
	if not _font:
		_font = GameFonts.italic()
	return _font


## The thought at the left of the screen, drifting up as it fades in and out.
func _show(text: String, duration: float) -> void:
	var scene := get_tree().current_scene
	if not scene:
		return
	var layer := CanvasLayer.new()
	layer.name = "ThoughtLayer"
	layer.layer = 150
	var label := Label.new()
	label.text = "“%s”" % text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.anchor_left = LEFT
	label.anchor_right = RIGHT
	label.anchor_top = TOP
	label.anchor_bottom = TOP
	label.add_theme_font_override("font", _get_font())
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", COLOR)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", 7)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.modulate.a = 0.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	scene.add_child(layer)
	_thought = layer
	label.create_tween().tween_property(label, "position:y", label.position.y - DRIFT_PX, duration + FADE_OUT) 		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
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
