class_name Crosshair
extends Control
## The crosshair: a small dot in the middle of the screen.
##   - Nothing to use: a faint dot.
##   - Something you can use ("[E] ..."): it grows a little and brightens.
##   - A status only ("Generator (full)"): a dim, slightly larger dot.
##   - Holding E on something (boarding, refuelling, installing, unlocking,
##     purging): a ring around it fills with the progress (set_hold()).
## Reads what the player is aiming at from InteractionManager.target_kind.
## In group "crosshair".

const DOT_IDLE := 2.0
const DOT_ACTION := 4.0
const DOT_STATUS := 3.0
const RING_RADIUS := 15.0
const RING_WIDTH := 3.0
const COLOR := Color(1.0, 0.97, 0.9)

## How the dot looks now, eased towards the target.
var _radius := DOT_IDLE
var _alpha := 0.45
var _hold := -1.0
var _hold_shown := 0.0
var _hold_fresh := 0.0
var _interaction: Node = null


func _ready() -> void:
	add_to_group("crosshair")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Progress (0..1) of something being held; call it every frame it goes on.
## Not called for a moment, the ring goes.
func set_hold(progress: float) -> void:
	_hold = clampf(progress, 0.0, 1.0)
	_hold_fresh = 0.15


func _process(delta: float) -> void:
	if not is_instance_valid(_interaction):
		var player := get_tree().get_first_node_in_group("player")
		_interaction = player.find_child("InteractionManager", true, false) if player else null
	var kind: int = _interaction.get("target_kind") if _interaction else 0
	var radius := DOT_IDLE
	var alpha := 0.45
	match kind:
		1:  # an action
			radius = DOT_ACTION
			alpha = 0.95
		2:  # a status
			radius = DOT_STATUS
			alpha = 0.55
	var ease := clampf(delta * 14.0, 0.0, 1.0)
	_radius = lerpf(_radius, radius, ease)
	_alpha = lerpf(_alpha, alpha, ease)
	_hold_fresh -= delta
	if _hold_fresh <= 0.0:
		_hold = -1.0
	_hold_shown = lerpf(_hold_shown, maxf(_hold, 0.0), clampf(delta * 20.0, 0.0, 1.0)) if _hold >= 0.0 else 0.0
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	draw_circle(centre, _radius + 1.0, Color(0, 0, 0, _alpha * 0.5))
	draw_circle(centre, _radius, Color(COLOR, _alpha))
	if _hold >= 0.0:
		# The track, then the filled part, from the top, clockwise.
		draw_arc(centre, RING_RADIUS, 0.0, TAU, 48, Color(0, 0, 0, 0.45), RING_WIDTH + 2.0, true)
		draw_arc(centre, RING_RADIUS, 0.0, TAU, 48, Color(COLOR, 0.25), RING_WIDTH, true)
		if _hold_shown > 0.001:
			draw_arc(centre, RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * _hold_shown, 48, Color(COLOR, 0.95), RING_WIDTH, true)
