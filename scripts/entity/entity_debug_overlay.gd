class_name EntityDebugOverlay
extends CanvasLayer

## Developer overlay (debug builds only). F3 toggles it.
## F4 (temporary, for testing): the Entity climbs up to the LandingRoom's
## window and tries to break in (debug_landing_breach).
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
	# (Development only.)
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F4:
		debug_landing_breach()


## TEMPORARY (F4): the Entity, put on the ground a few metres out from the
## LandingRoom's window, walks up, climbs the wall and tries to break in
## (APPROACH -> PEEK -> BREACH -> ENTER, as on a real night). Any night or
## day. False if the window isn't there.
func debug_landing_breach() -> bool:
	var link: CabinEntryLink = null
	for window in get_tree().get_nodes_in_group("TopFloorWindows"):
		if window.name == "LandingWindow" and window.get("_entry_link"):
			link = window._entry_link
	if link == null:
		push_warning("[Entity debug] F4: no LandingWindow entry found.")
		return false
	var out := link.start_position - link.end_position
	out.y = 0.0
	var spot := entity.world.snap_to_navmesh(link.start_position + out.normalized() * 6.0)
	entity.request_state(Entity.State.OBSERVE)
	entity.teleport(spot)
	entity.debug_breach = true
	_breach_states_seen = false
	entity.request_state(Entity.State.APPROACH, {EntityState.ENTRY: link})
	print("[Entity debug] F4: climbing to the LandingRoom window from %s." % spot)
	return true


const BREACH_STATES := [Entity.State.APPROACH, Entity.State.PEEK, Entity.State.BREACH, Entity.State.ENTER]
var _breach_states_seen := false


func _process(delta: float) -> void:
	# The F4 break-in is over (in, or given up): the night's rules again.
	if entity and entity.debug_breach:
		if entity.get_state() in BREACH_STATES:
			_breach_states_seen = true
		elif _breach_states_seen:
			entity.debug_breach = false
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
	lines.append("sees player: %s   range %.1fm   dist %.1fm%s" % [p.can_see_player, p.vision_range(), p.distance_to_player,
		"   (player in bush cover)" if p.player_in_cover() else ""])
	lines.append("last seen %.1fs ago   last heard %.1fs ago" % [minf(p.time_since_seen(), 999.0), minf(p.time_since_heard(), 999.0)])
	var n: Dictionary = p.last_noise
	if n.is_empty():
		lines.append("last noise: none yet")
	else:
		lines.append("last noise: %s %.1fm away, carries %.1fm (%d wall(s), %d obstacle(s), via %s) -> %s%s   %.1fs ago" % [
			n.kind, n.distance, n.range, n.walls, n.obstacles, n.via, "HEARD" if n.heard else "missed",
			("  off by %.1fm" % n.error) if n.heard and n.has("error") else "", p._clock - n.clock])
	var suspected: String = p.believed_player_room()
	lines.append("thinks the player is in: %s" % (suspected if suspected != "" else "?"))
	if entity.get_state() == Entity.State.LURE:
		var lure = entity.brain.current
		lines.append("LURE: knocking at %s to draw them from %s  (phase %s)" % [
			lure._decoy.entry.name if lure._decoy else "?", lure._target.entry.name if lure._target else "?",
			["go", "knock", "hide"][lure._phase]])
	lines.append("player room: %s   entity room: %s%s" % [p.player_room, p.entity_room, " (LIT)" if p.entity_in_lit_room else ""])
	lines.append("on player's screen: %s   watched: %s" % [p.in_player_view, p.player_watching])
	lines.append("flashlight: %s  overcharged: %s  strength %.2f  stare pressure %.2f  overcharge %.1fs  standoff cooldown %.1fs" % [
		p.illuminated, p.overcharged, p.beam_strength, p.stare_pressure, p.overcharge_time, entity.brain.standoff_cooldown])
	lines.append("")
	lines.append("recent transitions:")
	for entry in entity.brain.history:
		lines.append("  " + entry)
	return "\n".join(lines)
