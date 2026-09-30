class_name EntityDebugOverlay
extends CanvasLayer

## Developer overlay (debug builds only). F3 toggles it.
## Shows the Entity's state, confidence, perception and recent transitions,
## plus an FPS counter.

const REFRESH_INTERVAL := 0.2

var entity: Entity
var _label: Label
var _refresh := 0.0


func setup(owner_entity: Entity) -> void:
	entity = owner_entity
	layer = 200
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-440, 10)
	panel.custom_minimum_size = Vector2(430, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.75)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	panel.add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = REFRESH_INTERVAL
	_label.text = _build_text()


func _build_text() -> String:
	var p := entity.perception
	var c := entity.confidence
	var lines: Array[String] = []
	lines.append("FPS %d" % Engine.get_frames_per_second())
	lines.append("STATE  %s  (%.1fs)%s" % [entity.get_state_name(), entity.brain.current.time,
		"  [VAN CHASE]" if entity.van_chase_active else ""])
	lines.append("active=%s  enraged=%s  can_kill=%s" % [entity.is_active(), entity.is_enraged, entity.can_kill])
	lines.append("CONFIDENCE  %.1f  (rest %.1f, approach at %.0f)%s" % [
		c.confidence, c.resting, entity.config.approach_threshold, "  RELAXING" if c.is_relaxing() else ""])
	lines.append("")
	lines.append("sees player: %s   range %.1fm   dist %.1fm" % [p.can_see_player, p.vision_range(), p.distance_to_player])
	lines.append("last seen %.1fs ago   last heard %.1fs ago" % [minf(p.time_since_seen(), 999.0), minf(p.time_since_heard(), 999.0)])
	lines.append("player room: %s   entity room: %s%s" % [p.player_room, p.entity_room, " (LIT)" if p.entity_in_lit_room else ""])
	lines.append("on player's screen: %s   watched: %s" % [p.in_player_view, p.player_watching])
	lines.append("flashlight: %s  overcharged: %s  strength %.2f  stare pressure %.2f  overcharge %.1fs  standoff cooldown %.1fs" % [
		p.illuminated, p.overcharged, p.beam_strength, p.stare_pressure, p.overcharge_time, entity.brain.standoff_cooldown])
	lines.append("")
	lines.append("recent transitions:")
	for entry in entity.brain.history:
		lines.append("  " + entry)
	return "\n".join(lines)
