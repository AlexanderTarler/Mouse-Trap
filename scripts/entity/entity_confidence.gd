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
## Press F3 to toggle the Entity Debug overlay. Displays:
##   - Confidence value, thresholds, active modifiers
##   - Current FSM state and velocity
##   - Night info (current night, progress, generator status)
##   - Sensory data (player spotting, line of sight, vision cone)
##   - Navigation data (light grid cells, path cost, vantage point)
##   - AI internals (charge countdown, barricade timer, siege timer, etc.)

# ─── PRELOADS ────────────────────────────────────────────────────────────────
const EntityAI := preload("entity_ai.gd")

# ─── PUBLIC STATE ────────────────────────────────────────────────────────────
var entity: CharacterBody3D = null

## Current confidence value (0.0–100.0).
## Uses a setter to automatically clamp between 0.0 and 100.0,
## and emits confidence_changed signal whenever the value changes.
var confidence: float = 15.0:
	set(value):
		var new_val = clampf(value, 0.0, 100.0)
		if confidence != new_val:
			confidence = new_val
			confidence_changed.emit(confidence)

## Whether the debug overlay (F3) is active.
var debug_overlay_active: bool = false

# ─── THRESHOLD CONSTANTS ─────────────────────────────────────────────────────
## Minimum confidence required for the Entity to approach a window.
const THRESHOLD_WINDOW_APPROACH: float = 30.0

## Minimum confidence required for the Entity to attempt a full breach.
const THRESHOLD_BREACH: float = 65.0

## Minimum confidence required for the climax sprint (generator dead + max).
const THRESHOLD_CLIMAX: float = 85.0

## Below this threshold, the Entity will retreat from any confrontation.
const THRESHOLD_RETREAT: float = 20.0

# ─── RESTING STATE ───────────────────────────────────────────────────────────
## The confidence value the system drifts toward when no modifiers are active.
## On Night 1 this starts at 15.0. On Night 2+ it starts at 15.0 + night_base
## and additionally crawls up to 30.0 over the course of the night via
## _night_progress_mod, making the Entity increasingly bold as the night
## wears on even without player interaction.
var _resting_confidence: float = 15.0

## Rate at which confidence drifts toward the resting value (per second).
var _decay_rate: float = 2.0

# ─── MODIFIER TRACKING ───────────────────────────────────────────────────────
## Active modifier sources and their per-second rates.
## Key: source string (e.g. "player_busy_terminal")
## Value: Dictionary with "rate" (float) and "expires_at" (float, -1 = permanent)
var _active_modifiers: Dictionary = {}

## List of modifier descriptions for the debug overlay.
var _debug_modifier_strings: Array[String] = []

# ─── NIGHT PROGRESSION ───────────────────────────────────────────────────────
## Per-night base confidence bonus.
## Night 1 = 0, Night 2 = 8, Night 3 = 16, Night 4 = 24, Night 5 = 32
var _night_base: float = 0.0

## Night progress modifier (0.0–0.3, increases as night advances).
## On Night 2+, this is boosted so that resting confidence crawls up to 30.0
## over the course of the night. This means even if the player hides and does
## nothing, the Entity will eventually become bold enough to approach windows.
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

# ─── PERSISTENT FPS COUNTER (always visible, even when F3 overlay is off) ───
var _fps_canvas: CanvasLayer = null
var _fps_label: Label = null
var _fps_update_timer: float = 0.0
const FPS_UPDATE_INTERVAL: float = 0.25

# ─── F3 DEBOUNCE ─────────────────────────────────────────────────────────────
## Prevents rapid toggling from holding F3.
var _f3_was_pressed: bool = false

# ─── SIGNALS ─────────────────────────────────────────────────────────────────
## Emitted when confidence value changes (via setter).
signal confidence_changed(new_value: float)

## Emitted when confidence crosses a threshold boundary.
## threshold_name: "WINDOW_APPROACH", "BREACH", "CLIMAX", "RETREAT"
## direction: "above" or "below"
signal confidence_threshold_crossed(threshold_name: String, direction: String)


func setup(parent: CharacterBody3D) -> void:
	entity = parent
	_setup_debug_overlay()


func _setup_debug_overlay() -> void:
	# Create a CanvasLayer for the debug HUD
	_debug_canvas = CanvasLayer.new()
	_debug_canvas.layer = 200  # Above everything (HUD is typically 1-10, jumpscare is ~50)
	_debug_canvas.visible = false
	# Force the CanvasLayer to process even when the SceneTree is paused or
	# the Entity is in a frozen state. This ensures the F3 overlay always
	# responds to input and renders on screen regardless of game state.
	_debug_canvas.process_mode = PROCESS_MODE_ALWAYS
	add_child(_debug_canvas)
	
	# Background panel — semi-transparent black for readability
	# Anchored to the RIGHT side of the screen, 10px from the right edge
	_debug_bg = ColorRect.new()
	_debug_bg.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_bg.size = Vector2(520, 520)
	_debug_bg.position = Vector2(-530, 10)  # 10px from right edge (520 width + 10 padding)
	_debug_bg.color = Color(0, 0, 0, 0.75)
	_debug_canvas.add_child(_debug_bg)
	
	# ─── SECTION 1: CONFIDENCE (Top) ────────────────────────────────
	_debug_confidence_label = Label.new()
	_debug_confidence_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_confidence_label.position = Vector2(-515, 15)
	_debug_confidence_label.size = Vector2(490, 50)
	_debug_confidence_label.add_theme_font_size_override("font_size", 18)
	_debug_confidence_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
	_debug_canvas.add_child(_debug_confidence_label)
	
	# Active modifiers label
	_debug_mod_label = Label.new()
	_debug_mod_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_mod_label.position = Vector2(-515, 65)
	_debug_mod_label.size = Vector2(490, 60)
	_debug_mod_label.add_theme_font_size_override("font_size", 11)
	_debug_mod_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_debug_canvas.add_child(_debug_mod_label)
	
	# ─── SECTION 2: FSM STATE ───────────────────────────────────────
	_debug_state_label = Label.new()
	_debug_state_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_state_label.position = Vector2(-515, 125)
	_debug_state_label.size = Vector2(490, 40)
	_debug_state_label.add_theme_font_size_override("font_size", 14)
	_debug_state_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	_debug_canvas.add_child(_debug_state_label)
	
	# ─── SECTION 3: NIGHT INFO ──────────────────────────────────────
	_debug_night_label = Label.new()
	_debug_night_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_night_label.position = Vector2(-515, 165)
	_debug_night_label.size = Vector2(490, 50)
	_debug_night_label.add_theme_font_size_override("font_size", 12)
	_debug_night_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	_debug_canvas.add_child(_debug_night_label)
	
	# ─── SECTION 4: SENSORY DATA ────────────────────────────────────
	_debug_sensory_label = Label.new()
	_debug_sensory_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_sensory_label.position = Vector2(-515, 215)
	_debug_sensory_label.size = Vector2(490, 70)
	_debug_sensory_label.add_theme_font_size_override("font_size", 11)
	_debug_sensory_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.6))
	_debug_canvas.add_child(_debug_sensory_label)
	
	# ─── SECTION 5: NAVIGATION DATA ─────────────────────────────────
	_debug_nav_label = Label.new()
	_debug_nav_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_nav_label.position = Vector2(-515, 285)
	_debug_nav_label.size = Vector2(490, 70)
	_debug_nav_label.add_theme_font_size_override("font_size", 11)
	_debug_nav_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	_debug_canvas.add_child(_debug_nav_label)
	
	# ─── SECTION 6: AI INTERNALS ────────────────────────────────────
	_debug_ai_label = Label.new()
	_debug_ai_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_ai_label.position = Vector2(-515, 355)
	_debug_ai_label.size = Vector2(490, 150)
	_debug_ai_label.add_theme_font_size_override("font_size", 11)
	_debug_ai_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	_debug_canvas.add_child(_debug_ai_label)
	
	# ─── FORCED VISIBILITY DEBUG ────────────────────────────────────
	# ─── FPS COUNTER (persistent, always visible) ────────────────────
	_fps_canvas = CanvasLayer.new()
	_fps_canvas.layer = 300  # Above everything including debug overlay
	_fps_canvas.process_mode = PROCESS_MODE_ALWAYS
	add_child(_fps_canvas)
	
	_fps_label = Label.new()
	_fps_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_fps_label.position = Vector2(10, 8)
	_fps_label.size = Vector2(160, 24)
	_fps_label.add_theme_font_size_override("font_size", 14)
	# Semi-transparent bg for readability
	_fps_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_fps_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1.0))
	_fps_label.text = "FPS: --"
	_fps_canvas.add_child(_fps_label)
	
	print("[Confidence] Entity Debug UI initialized. CanvasLayer: ", _debug_canvas.get_path())
	print("[Confidence] CanvasLayer layer: ", _debug_canvas.layer, " | visible: ", _debug_canvas.visible)
	print("[Confidence] CanvasLayer process_mode: ", _debug_canvas.process_mode)
	print("[Confidence] Background ColorRect size: ", _debug_bg.size, " position: ", _debug_bg.position)


func _process(delta: float) -> void:
	if not entity or not is_instance_valid(entity):
		return
	
	# ─── 0. PERSISTENT FPS COUNTER (always visible) ─────────────────
	_fps_update_timer += delta
	if _fps_update_timer >= FPS_UPDATE_INTERVAL:
		_fps_update_timer = 0.0
		var fps = Engine.get_frames_per_second()
		var frame_time = snapped(1000.0 / fps, 0.1) if fps > 0 else 0.0
		var fps_color: Color
		if fps < 30:
			fps_color = Color(1.0, 0.2, 0.2)  # Red
		elif fps < 55:
			fps_color = Color(1.0, 1.0, 0.2)  # Yellow
		else:
			fps_color = Color(0.3, 1.0, 0.3)  # Green
		_fps_label.add_theme_color_override("font_color", fps_color)
		_fps_label.text = "FPS: %d (%.1f ms)" % [fps, frame_time]
	
	# ─── 1. F3 TOGGLE (polled in _process for reliability) ──────────
	var f3_down: bool = Input.is_key_pressed(KEY_F3)
	if f3_down and not _f3_was_pressed:
		debug_overlay_active = not debug_overlay_active
		if _debug_canvas:
			_debug_canvas.visible = debug_overlay_active
		print("[Confidence] Entity Debug UI toggled: ", "ON" if debug_overlay_active else "OFF")
	_f3_was_pressed = f3_down
	
	# ─── 1. APPLY ACTIVE MODIFIERS ──────────────────────────────────
	_debug_modifier_strings.clear()
	var current_time: float = Time.get_ticks_msec() / 1000.0
	var keys_to_remove: Array[String] = []
	
	for source in _active_modifiers:
		var mod_data: Dictionary = _active_modifiers[source]
		var rate: float = mod_data.get("rate", 0.0)
		var expires_at: float = mod_data.get("expires_at", -1.0)
		
		# Check expiration using engine time (decoupled from entity._game_time)
		if expires_at > 0.0 and current_time >= expires_at:
			keys_to_remove.append(source)
			continue
		
		# Apply the modifier (setter auto-clamps and emits signal)
		confidence += rate * delta
		
		# Build debug string
		var sign: String = "+" if rate >= 0.0 else ""
		_debug_modifier_strings.append("%s%.1f/s %s" % [sign, rate, source])
	
	# Remove expired modifiers safely (after iteration)
	for key in keys_to_remove:
		remove_continuous_modifier(key)
	
	# ─── 2. APPLY NIGHT PROGRESSION MODIFIER ────────────────────────
	var nm: Node = entity.get_night_manager()
	if nm:
		var night_progress: float = nm.night_progress if "night_progress" in nm else 0.0
		var current_night: int = nm.current_night if "current_night" in nm else 1
		
		# Night-scaled drift: On Night 2+, the progress modifier is boosted
		# so that resting confidence crawls up to 30.0 over the course of the
		# night. This means even if the player hides and does nothing, the
		# Entity will eventually become bold enough to approach windows.
		# Base progress mod is 0.3 * night_progress (max 0.3 at end of night).
		# On Night 2+, we add an extra 0.5 * night_progress so the total
		# reaches ~0.8/s by dawn, pushing confidence from ~23 to ~30 over
		# the night's duration.
		_night_progress_mod = night_progress * 0.3
		if current_night >= 2:
			_night_progress_mod += night_progress * 0.5
		
		confidence += _night_progress_mod * delta
		
		_night_base = (current_night - 1) * 8.0
		_resting_confidence = 15.0 + _night_base
	
	# ─── 3. DRIFT TOWARD RESTING VALUE ──────────────────────────────
	# Drift only pulls confidence UP toward the resting value when no
	# active modifiers are present. It does NOT pull confidence DOWN,
	# because the night progress modifier (applied above) is designed to
	# push confidence past the resting value over time. Without this guard,
	# the drift would fight the night progress modifier and keep confidence
	# stuck at the resting value (e.g., 23.0 on Night 2).
	#
	# This means:
	#   - If confidence < resting and no modifiers: drift UP at decay_rate/s
	#   - If confidence > resting: stay there (night progress pushes it up)
	#   - If active modifiers are present: drift is disabled entirely
	#     (modifiers take full control)
	if _active_modifiers.is_empty():
		if confidence < _resting_confidence:
			confidence += _decay_rate * delta
		# NOTE: Removed the "elif confidence > _resting_confidence" branch.
		# The night progress modifier is designed to push confidence past
		# the resting value. Without this removal, the drift would pull
		# confidence back down to 23.0, fighting the night progress modifier.
	
	# ─── 4. UPDATE DEBUG OVERLAY ────────────────────────────────────
	# NOTE: No manual clamp needed — the setter on `confidence` handles it.
	if debug_overlay_active:
		_update_debug_overlay()


## Updates the F3 Entity Debug UI with all behavioral data.
func _update_debug_overlay() -> void:
	if not _debug_confidence_label or not _debug_mod_label or not _debug_state_label:
		return
	if not _debug_night_label or not _debug_sensory_label or not _debug_nav_label or not _debug_ai_label:
		return
	
	# ─── SECTION 1: CONFIDENCE ──────────────────────────────────────
	var color: Color
	if confidence >= THRESHOLD_CLIMAX:
		color = Color(1.0, 0.2, 0.2)  # Red = climax
	elif confidence >= THRESHOLD_BREACH:
		color = Color(1.0, 0.6, 0.0)  # Orange = breach
	elif confidence >= THRESHOLD_WINDOW_APPROACH:
		color = Color(1.0, 1.0, 0.0)  # Yellow = window approach
	elif confidence <= THRESHOLD_RETREAT:
		color = Color(0.4, 0.4, 1.0)  # Blue = retreat
	else:
		color = Color(0.2, 1.0, 0.2)  # Green = passive
	
	_debug_confidence_label.add_theme_color_override("font_color", color)
	_debug_confidence_label.text = "CONFIDENCE: %.1f / 100.0" % confidence
	_debug_confidence_label.text += "\nTHRESHOLDS: RETREAT(%.0f) | WINDOW(%.0f) | BREACH(%.0f) | CLIMAX(%.0f)" % [
		THRESHOLD_RETREAT, THRESHOLD_WINDOW_APPROACH, THRESHOLD_BREACH, THRESHOLD_CLIMAX
	]
	
	# Active modifiers
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
	
	# ─── SECTION 2: FSM STATE ───────────────────────────────────────
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
	
	# ─── SECTION 3: NIGHT INFO ──────────────────────────────────────
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
	
	# ─── SECTION 4: SENSORY DATA ────────────────────────────────────
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
	
	# ─── SECTION 5: NAVIGATION DATA ─────────────────────────────────
	var nav = entity.get_navigation_module()
	var nav_finished: bool = entity.get_nav_agent().is_navigation_finished()
	var target_pos: Vector3 = entity.get_nav_agent().target_position
	var dist_to_target: float = entity.global_position.distance_to(target_pos)
	
	var light_cost: float = 0.0
	if nav and nav.has_method("get_light_cost_at"):
		light_cost = nav.get_light_cost_at(entity.global_position)
	
	_debug_nav_label.text = "NAVIGATION:"
	_debug_nav_label.text += "\n  Nav Finished: %s | Dist to Target: %.1f m" % [
		"YES" if nav_finished else "no", dist_to_target
	]
	_debug_nav_label.text += "\n  Light Cost Here: %.2f | Grid Cells: %d" % [
		light_cost, nav._light_cost_grid.size() if nav and "_light_cost_grid" in nav else 0
	]
	
	# ─── SECTION 6: AI INTERNALS ────────────────────────────────────
	var ai = entity.get_ai_module()
	var charge_cd: float = ai._charge_countdown if ai and "_charge_countdown" in ai else 0.0
	var barricade_timer: float = ai._barricade_damage_timer if ai and "_barricade_damage_timer" in ai else 0.0
	var siege_timer: float = ai._siege_duration_timer if ai and "_siege_duration_timer" in ai else 0.0
	var standoff_guard: bool = ai._standoff_retreat_triggered if ai and "_standoff_retreat_triggered" in ai else false
	var has_pending_damage: bool = ai._has_pending_damage if ai and "_has_pending_damage" in ai else false
	var pending_delay: float = ai._pending_damage_delay if ai and "_pending_damage_delay" in ai else 0.0
	var anim_lock: float = ai._barricade_anim_lock if ai and "_barricade_anim_lock" in ai else 0.0
	var wall_climb_phase2: bool = ai._wall_climb_phase_2 if ai and "_wall_climb_phase_2" in ai else false
	var harass_timer: float = entity.get_meta("_harass_timer", 0.0) if entity.has_meta("_harass_timer") else 0.0
	
	_debug_ai_label.text = "AI INTERNALS:"
	_debug_ai_label.text += "\n  Charge CD: %.2fs | Barricade Timer: %.2fs | Siege Timer: %.2fs" % [
		charge_cd, barricade_timer, siege_timer
	]
	_debug_ai_label.text += "\n  Standoff Guard: %s | Pending Dmg: %s (%.2fs) | Anim Lock: %.2fs" % [
		"SET" if standoff_guard else "clear",
		"YES" if has_pending_damage else "no",
		pending_delay, anim_lock
	]
	_debug_ai_label.text += "\n  Wall Climb P2: %s | Harass Timer: %.1fs | Flinch Timer: %.1fs" % [
		"YES" if wall_climb_phase2 else "no",
		harass_timer,
		entity._flinched_timer if "_flinched_timer" in entity else 0.0
	]


# ─── PUBLIC API ──────────────────────────────────────────────────────────────

## Returns the current confidence value (0.0–100.0).
func get_confidence() -> float:
	return confidence


## Sets the confidence to an absolute value (0.0–100.0).
## Used by the Master Director to apply psychological penalties (e.g., -20%
## after FLINCH) or by external systems that need to override confidence.
## This bypasses the modifier system and directly sets the value.
## NOTE: The setter on `confidence` auto-clamps and emits the signal.
func set_confidence(value: float) -> void:
	confidence = value


## Applies an instantaneous confidence modification.
## amount: The delta to apply (positive = more bold, negative = more timid).
## source: A human-readable string identifying the source (for debug overlay).
## NOTE: The setter on `confidence` auto-clamps and emits the signal.
func modify(amount: float, source: String) -> void:
	confidence += amount
	# NOTE: Debug log removed to reduce console spam during flashlight stare.
	# The F3 Entity Debug overlay shows real-time confidence changes.
	# Uncomment the line below if you need to debug confidence modifications:
	# print("[Confidence] Modified by %.1f (%s). New confidence: %.1f" % [amount, source, confidence])


## Adds a continuous modifier that applies every frame.
## rate: Per-second confidence change (positive or negative).
## source: A human-readable string identifying the source.
## duration: If > 0, the modifier auto-expires after this many seconds.
##           If <= 0, the modifier is permanent until explicitly removed.
## NOTE: Uses Time.get_ticks_msec() for expiration (decoupled from entity._game_time).
func add_continuous_modifier(rate: float, source: String, duration: float = -1.0) -> void:
	var expires_at: float = -1.0
	if duration > 0.0:
		expires_at = (Time.get_ticks_msec() / 1000.0) + duration
	
	_active_modifiers[source] = {
		"rate": rate,
		"expires_at": expires_at
	}
	print("[Confidence] Continuous modifier added: %.1f/s (%s) for %.1fs" % [rate, source, duration if duration > 0 else -1.0])


## Removes a continuous modifier by source string.
func remove_continuous_modifier(source: String) -> void:
	if _active_modifiers.has(source):
		_active_modifiers.erase(source)
		print("[Confidence] Continuous modifier removed: %s" % source)


## Resets confidence to the baseline for the current night.
func reset() -> void:
	confidence = _resting_confidence
	_active_modifiers.clear()
	_debug_modifier_strings.clear()
	print("[Confidence] Reset to baseline: %.1f" % _resting_confidence)
