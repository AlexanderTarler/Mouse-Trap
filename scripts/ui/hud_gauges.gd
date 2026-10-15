class_name HudGauges
extends Control
## The HUD's two gauges, kept quiet, in the bottom-left corner:
##   - the flashlight's battery: a small torch with four segments, shown while
##     the light is on; the last segment flickers when it is nearly flat;
##   - stamina: a thin dim line, only below half (the breathing says the
##     rest).
## Fed by HorrorHUD (battery_changed, stamina_changed).

const COLOR := Color(0.92, 0.88, 0.78)
const LOW := 15.0
const SEGMENTS := 4

var battery := 100.0
var light_on := false
var stamina := 100.0
var _light_alpha := 0.0
var _stamina_alpha := 0.0
var _clock := 0.0


func _ready() -> void:
	name = "HudGauges"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 34.0
	offset_right = 234.0
	offset_top = -86.0
	offset_bottom = -30.0


func _process(delta: float) -> void:
	_clock += delta
	_light_alpha = move_toward(_light_alpha, 1.0 if light_on else 0.0, delta * 4.0)
	_stamina_alpha = move_toward(_stamina_alpha, 1.0 if stamina < 50.0 else 0.0, delta * 3.0)
	queue_redraw()


func _draw() -> void:
	if _light_alpha > 0.01:
		var a := _light_alpha * 0.85
		# The torch: a body and a wider head, pointing right.
		draw_rect(Rect2(0, 6, 22, 10), Color(COLOR, a), false, 2.0)
		draw_rect(Rect2(22, 3, 8, 16), Color(COLOR, a), false, 2.0)
		var lit := ceili(battery / (100.0 / SEGMENTS)) if battery > 0.0 else 0
		for i in SEGMENTS:
			var segment := Rect2(40 + i * 15, 5, 11, 12)
			var on := i < lit
			if on and lit == 1 and battery <= LOW:
				# The last one, nearly flat: a nervous flicker.
				on = fmod(_clock * 5.3, 1.0) > 0.35
			if on:
				draw_rect(segment, Color(COLOR, a))
			else:
				draw_rect(segment, Color(COLOR, a * 0.3), false, 1.0)
	if _stamina_alpha > 0.01:
		var width := 104.0
		draw_rect(Rect2(0, 36, width, 3), Color(0, 0, 0, 0.35 * _stamina_alpha))
		draw_rect(Rect2(0, 36, width * clampf(stamina / 100.0, 0.0, 1.0), 3), Color(COLOR, 0.55 * _stamina_alpha))
