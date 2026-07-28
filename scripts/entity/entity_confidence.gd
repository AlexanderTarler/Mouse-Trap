extends Node
class_name EntityConfidence

## Entity Confidence System — The hidden utility variable that dictates the
## Entity's boldness. Confidence INCREASES when the player is occupied (using
## the terminal, repairing the generator) or when cabin lights go out.
## Confidence DECREASES when the player actively wards it off, repairs lights,
## or shines a flashlight out the window.
##
## High confidence unlocks more aggressive states (window approach, breach,
## climax). Low confidence forces passive stalking (observe from treeline,
## patrol, retreat).
##
## Confidence ranges from 0.0 (cowering, terrified of light) to 100.0
## (relentless, sprinting through pitch-black darkness).
##
## The system uses a resting value that confidence drifts toward when no
## modifiers are active. The resting value increases per night and as the
## night progresses, creating natural escalation.
##
## ─── ENTITY DEBUG UI (F3) ──────────────────────────────────────────────────
## Press F3 to toggle the Entity Debug overlay.

# ─── PRELOADS ────────────────────────────────────────────────────────────────
const EntityAI := preload("entity_ai.gd")

# ─── PUBLIC STATE ────────────────────────────────────────────────────────────
var entity: CharacterBody3D = null

## Current confidence value (0.0–100.0).
var confidence: float = 0.0:
	set(value):
		var new_val = clampf(value, 0.0, 100.0)
		if confidence != new_val:
			confidence = new_val
			confidence_changed.emit(confidence)

var debug_overlay_active: bool = false

# ─── THRESHOLD CONSTANTS ─────────────────────────────────────────────────────
const THRESHOLD_WINDOW_APPROACH: float = 30.0
const THRESHOLD_BREACH: float = 65.0
const THRESHOLD_CLIMAX: float = 85.0
const THRESHOLD_RETREAT: float = 20.0

# ─── RESTING STATE ───────────────────────────────────────────────────────────
var _resting_confidence: float = 0.0
var _decay_rate: float = 2.0

# ─── MODIFIER TRACKING ───────────────────────────────────────────────────────
var _active_modifiers: Dictionary = {}
var _debug_modifier_strings: Array[String] = []

# ─── NIGHT PROGRESSION ───────────────────────────────────────────────────────
var _night_base: float = 0.0
var _night_progress_mod: float = 0.0

# ─── DEBUG OVERLAY NODES ─────────────────────────────────────────────────────
var _debug_canvas: CanvasLayer = null
var _debug_bg: ColorRect = null
var _debug_confidence_label: Label = null
var _debug_mod_label: Label = null
var _debug_state_label: Label = null
var _debug_night_label: Label = null
var _debug_sensory_label: Label = null
var _debug_nav_label: Label = null
var _debug_ai_label: Label = null

# ─── PERSISTENT FPS COUNTER ──────────────────────────────────────────────────
var _fps_canvas: CanvasLayer = null
var _fps_label: Label = null
var _fps_update_timer: float = 0.0
const FPS_UPDATE_INTERVAL: float = 0.25

# ─── F3 DEBOUNCE ─────────────────────────────────────────────────────────────
var _f3_was_pressed: bool = false

# ─── SIGNALS ─────────────────────────────────────────────────────────────────
signal confidence_changed(new_value: float)
signal confidence_threshold_crossed(threshold_name: String, direction: String)


func setup(parent: CharacterBody3D) -> void:
	entity = parent
	# Reset to 0 at start — Entity starts with no confidence
	confidence = 0.0
	process_mode = PROCESS_MODE_ALWAYS
	_setup_debug_overlay()


func _setup_debug_overlay() -> void:
	_debug_canvas = CanvasLayer.new()
	_debug_canvas.layer = 200
	_debug_canvas.visible = false
	_debug_canvas.process_mode = PROCESS_MODE_ALWAYS
	add_child(_debug_canvas)
	
	_debug_bg = ColorRect.new()
	_debug_bg.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_bg.size = Vector2(520, 520)
	_debug_bg.position = Vector2(-530, 10)
	_debug_bg.color = Color(0, 0, 0, 0.75)
	_debug_canvas.add_child(_debug_bg)
	
	_debug_confidence_label = Label.new()
	_debug_confidence_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_confidence_label.position = Vector2(-515, 15)
	_debug_confidence_label.size = Vector2(490, 50)
	_debug_confidence_label.add_theme_font_size_override("font_size", 18)
	_debug_confidence_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
	_debug_canvas.add_child(_debug_confidence_label)
	
	_debug_mod_label = Label.new()
	_debug_mod_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_mod_label.position = Vector2(-515, 65)
	_debug_mod_label.size = Vector2(490, 60)
	_debug_mod_label.add_theme_font_size_override("font_size", 11)
	_debug_mod_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_debug_canvas.add_child(_debug_mod_label)
	
	_debug_state_label = Label.new()
	_debug_state_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_state_label.position = Vector2(-515, 125)
	_debug_state_label.size = Vector2(490, 40)
	_debug_state_label.add_theme_font_size_override("font_size", 14)
	_debug_state_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	_debug_canvas.add_child(_debug_state_label)
	
	_debug_night_label = Label.new()
	_debug_night_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_night_label.position = Vector2(-515, 165)
	_debug_night_label.size = Vector2(490, 50)
	_debug_night_label.add_theme_font_size_override("font_size", 12)
	_debug_night_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	_debug_canvas.add_child(_debug_night_label)
	
	_debug_sensory_label = Label.new()
	_debug_sensory_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_sensory_label.position = Vector2(-515, 215)
	_debug_sensory_label.size = Vector2(490, 70)
	_debug_sensory_label.add_theme_font_size_override("font_size", 11)
	_debug_sensory_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.6))
	_debug_canvas.add_child(_debug_sensory_label)
	
	_debug_nav_label = Label.new()
	_debug_nav_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_nav_label.position = Vector2(-515, 285)
	_debug_nav_label.size = Vector2(490, 70)
	_debug_nav_label.add_theme_font_size_override("font_size", 11)
	_debug_nav_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	_debug_canvas.add_child(_debug_nav_label)
	
	_debug_ai_label = Label.new()
	_debug_ai_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_ai_label.position = Vector2(-515, 355)
	_debug_ai_label.size = Vector2(490, 150)
	_debug_ai_label.add_theme_font_size_override("font_size", 11)
	_debug_ai_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	_debug_canvas.add_child(_debug_ai_label)
	
	# FPS counter
	_fps_canvas = CanvasLayer.new()
	_fps_canvas.layer = 300
	_fps_canvas.process_mode = PROCESS_MODE_ALWAYS
	add_child(_fps_canvas)
	
	_fps_label = Label.new()
	_fps_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_fps_label.position = Vector2(10, 8)
	_fps_label.size = Vector2(160, 24)
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_fps_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1.0))
	_fps_label.text = "FPS: --"
	_fps_canvas.add_child(_fps_label)


func _update_fps_only(_delta: float) -> void:
	# Only update FPS counter + F3 toggle when dormant
	_fps_update_timer += _delta
	if _fps_update_timer >= FPS_UPDATE_INTERVAL:
		_fps_update_timer = 0.0
		var fps = Engine.get_frames_per_second()
		var frame_time = snapped(1000.0 / fps, 0.1) if fps > 0 else 0.0
		var fps_color: Color
		if fps < 30:
			fps_color = Color(1.0, 0.2, 0.2)
		elif fps < 55:
			fps_color = Color(1.0, 1.0, 0.2)
		else:
			fps_color = Color(0.3, 1.0, 0.3)
		_fps_label.add_theme_color_override("font_color", fps_color)
		_fps_label.text = "FPS: %d (%.1f ms)" % [fps, frame_time]
	
	var f3_down: bool = Input.is_key_pressed(KEY_F3)
	if f3_down and not _f3_was_pressed:
		debug_overlay_active = not debug_overlay_active
		if _debug_canvas:
			_debug_canvas.visible = debug_overlay_active
	_f3_was_pressed = f3_down


func _process(delta: float) -> void:
	if not entity or not is_instance_valid(entity):
		return
	
	# ─── DORMANT/DAYTIME GUARD ─────────────────────────────────────
	# Confidence does NOT accumulate while the Entity is dormant.
	if not entity.get("_is_active"):
		_update_fps_only(delta)
		return
	
	# ─── FPS COUNTER ─────────────────────────────────────────────
	_fps_update_timer += delta
	if _fps_update_timer >= FPS_UPDATE_INTERVAL:
		_fps_update_timer = 0.0
		var fps = Engine.get_frames_per_second()
		var frame_time = snapped(1000.0 / fps, 0.1) if fps > 0 else 0.0
		var fps_color: Color
		if fps < 30:
			fps_color = Color(1.0, 0.2, 0.2)
		elif fps < 55:
			fps_color = Color(1.0, 1.0, 0.2)
		else:
			fps_color = Color(0.3, 1.0, 0.3)
		_fps_label.add_theme_color_override("font_color", fps_color)
		_fps_label.text = "FPS: %d (%.1f ms)" % [fps, frame_time]
	
	# ─── F3 TOGGLE ──────────────────────────────────────────────
	var f3_down: bool = Input.is_key_pressed(KEY_F3)
	if f3_down and not _f3_was_pressed:
		debug_overlay_active = not debug_overlay_active
		if _debug_canvas:
			_debug_canvas.visible = debug_overlay_active
	_f3_was_pressed = f3_down
	
	# ─── APPLY ACTIVE MODIFIERS ──────────────────────────────────
	_debug_modifier_strings.clear()
	var current_time: float = Time.get_ticks_msec() / 1000.0
	var keys_to_remove: Array[String] = []
	
	for source in _active_modifiers:
		var mod_data: Dictionary = _active_modifiers[source]
		var rate: float = mod_data.get("rate", 0.0)
		var expires_at: float = mod_data.get("expires_at", -1.0)
		
		if expires_at > 0.0 and current_time >= expires_at:
			keys_to_remove.append(source)
			continue
		
		confidence += rate * delta
		var sign: String = "+" if rate >= 0.0 else ""
		_debug_modifier_strings.append("%s%.1f/s %s" % [sign, rate, source])
	
	for key in keys_to_remove:
		remove_continuous_modifier(key)
	
	# ─── NIGHT PROGRESSION MODIFIER ──────────────────────────────
	var nm: Node = entity.get_night_manager()
	if nm:
		var night_progress: float = nm.night_progress if "night_progress" in nm else 0.0
		var current_night: int = nm.current_night if "current_night" in nm else 1
		
		_night_progress_mod = night_progress * 0.3
		if current_night >= 2:
			_night_progress_mod += night_progress * 0.5
		
		confidence += _night_progress_mod * delta
		
		_night_base = (current_night - 1) * 8.0
		_resting_confidence = 15.0 + _night_base
	
	# ─── DRIFT TOWARD RESTING VALUE ──────────────────────────────
	if _active_modifiers.is_empty():
		if confidence < _resting_confidence:
			confidence += _decay_rate * delta
	
	# ─── UPDATE DEBUG OVERLAY ────────────────────────────────────
	if debug_overlay_active:
		_update_debug_overlay()


func _update_debug_overlay() -> void:
	if not _debug_confidence_label or not _debug_mod_label or not _debug_state_label:
		return
	if not _debug_night_label or not _debug_sensory_label or not _debug_nav_label or not _debug_ai_label:
		return
	
	var color: Color
	if confidence >= THRESHOLD_CLIMAX:
		color = Color(1.0, 0.2, 0.2)
	elif confidence >= THRESHOLD_BREACH:
		color = Color(1.0, 0.6, 0.0)
	elif confidence >= THRESHOLD_WINDOW_APPROACH:
		color = Color(1.0, 1.0, 0.0)
	elif confidence <= THRESHOLD_RETREAT:
		color = Color(0.4, 0.4, 1.0)
	else:
		color = Color(0.2, 1.0, 0.2)
	
	_debug_confidence_label.add_theme_color_override("font_color", color)
	_debug_confidence_label.text = "CONFIDENCE: %.1f / 100.0" % confidence
	_debug_confidence_label.text += "\nTHRESHOLDS: RETREAT(%.0f) | WINDOW(%.0f) | BREACH(%.0f) | CLIMAX(%.0f)" % [
		THRESHOLD_RETREAT, THRESHOLD_WINDOW_APPROACH, THRESHOLD_BREACH, THRESHOLD_CLIMAX
	]
	
	if _debug_modifier_strings.is_empty():
		_debug_mod_label.text = "No active modifiers\nResting: %.1f | Night Base: +%.1f | Progress: +%.1f/s" % [
			_resting_confidence, _night_base, _night_progress_mod
		]
	else:
		_debug_mod_label.text = "Active Modifiers:\n"
		for mod_str in _debug_modifier_strings:
			_debug_mod_label.text += "  " + mod_str + "\n"
		_debug_mod_label.text += "Resting: %.1f | Night Base: +%.1f | Progress: +%.1f/s" % [
			_resting_confidence, _night_base, _night_progress_mod
		]
	
	if entity:
		var state_name: String = "DORMANT"
		var state_index: int = entity._state as int
		var state_keys = EntityAI.State.keys()
		if state_index >= 0 and state_index < state_keys.size():
			state_name = state_keys[state_index]
		
		var velocity: Vector3 = entity.velocity
		var speed_val: float = velocity.length()
		var is_active_str: String = "ACTIVE" if entity._is_active else "INACTIVE"
		
		_debug_state_label.text = "STATE: %s [%s] | Speed: %.1f m/s | Vel: (%.1f, %.1f, %.1f)" % [
			state_name, is_active_str, speed_val, velocity.x, velocity.y, velocity.z
		]
	
	var night_mgr: Node = entity.get_night_manager()
	if night_mgr:
		var night_progress_pct: float = night_mgr.night_progress * 100.0 if "night_progress" in night_mgr else 0.0
		var gen_status: String = "ON" if night_mgr.is_generator_on else "OFF"
		var gen_fuel: float = night_mgr.generator_fuel if "generator_fuel" in night_mgr else 0.0
		var can_approach: String = "YES" if night_mgr.can_approach_windows() else "NO (Night 1)"
		
		_debug_night_label.text = "NIGHT: %d/5 | Progress: %.0f%% | Gen: %s (%.1f fuel)" % [
			night_mgr.current_night, night_progress_pct, gen_status, gen_fuel
		]
		_debug_night_label.text += "\nWindow Approach: %s | Drain Rate: %.2f/s" % [
			can_approach, night_mgr.current_drain_rate if "current_drain_rate" in night_mgr else 0.0
		]
	
	var sensory = entity.get_sensory_module()
	var player_spotting: bool = sensory and sensory.has_method("is_player_spotting_entity") and sensory.is_player_spotting_entity()
	var can_see_player: bool = sensory and sensory.has_method("can_entity_see_player") and sensory.can_entity_see_player()
	var player_outside: bool = entity.get_navigation_module() and entity.get_navigation_module().is_player_outside()
	
	var player_ref = entity.get_player()
	var dist_to_player: float = INF
	if player_ref:
		dist_to_player = entity.global_position.distance_to(player_ref.global_position)
	
	_debug_sensory_label.text = "SENSORY:"
	_debug_sensory_label.text += "\n  Flashlight on Entity: %s | LOS: %s | Player Outside: %s" % [
		"YES" if player_spotting else "no",
		"YES" if can_see_player else "no",
		"YES" if player_outside else "no"
	]
	_debug_sensory_label.text += "\n  Dist to Player: %.1f m | Vision Cone: %.0f°" % [
		dist_to_player, rad_to_deg(entity.get_vision_cone_angle())
	]
	
	var nav = entity.get_navigation_module()
	var nav_finished: bool = entity.get_nav_agent().is_navigation_finished()
	var target_pos: Vector3 = entity.get_nav_agent().target_position
	var dist_to_target: float = entity.global_position.distance_to(target_pos)
	
	_debug_nav_label.text = "NAVIGATION:"
	_debug_nav_label.text += "\n  Nav Finished: %s | Dist to Target: %.1f m" % [
		"YES" if nav_finished else "no", dist_to_target
	]
	
	var ai = entity.get_ai_module()
	_debug_ai_label.text = "AI INTERNALS:"
	if ai:
		_debug_ai_label.text += "\n  Charge CD: %.2fs | Siege Timer: %.2fs" % [
			ai._charge_countdown if "_charge_countdown" in ai else 0.0,
			ai._siege_duration_timer if "_siege_duration_timer" in ai else 0.0
		]


# ─── PUBLIC API ──────────────────────────────────────────────────────────────

func get_confidence() -> float:
	return confidence

func set_confidence(value: float) -> void:
	confidence = value

func modify(amount: float, source: String) -> void:
	confidence += amount

func add_continuous_modifier(rate: float, source: String, duration: float = -1.0) -> void:
	var expires_at: float = -1.0
	if duration > 0.0:
		expires_at = (Time.get_ticks_msec() / 1000.0) + duration
	_active_modifiers[source] = {"rate": rate, "expires_at": expires_at}

func remove_continuous_modifier(source: String) -> void:
	if _active_modifiers.has(source):
		_active_modifiers.erase(source)

func reset() -> void:
	confidence = 0.0
	_active_modifiers.clear()
	_debug_modifier_strings.clear()