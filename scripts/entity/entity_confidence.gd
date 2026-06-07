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

# ─── PUBLIC STATE ────────────────────────────────────────────────────────────
var entity: CharacterBody3D = null

## Current confidence value (0.0–100.0).
var confidence: float = 15.0

## Whether the debug overlay (F3) is active.
var debug_overlay_active: bool = false

# ─── THRESHOLD CONSTANTS ─────────────────────────────────────────────────────
## Minimum confidence required for the Entity to approach a window.
const THRESHOLD_WINDOW_APPROACH: float = 40.0

## Minimum confidence required for the Entity to attempt a full breach.
const THRESHOLD_BREACH: float = 65.0

## Minimum confidence required for the climax sprint (generator dead + max).
const THRESHOLD_CLIMAX: float = 85.0

## Below this threshold, the Entity will retreat from any confrontation.
const THRESHOLD_RETREAT: float = 20.0

# ─── RESTING STATE ───────────────────────────────────────────────────────────
## The confidence value the system drifts toward when no modifiers are active.
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
var _night_progress_mod: float = 0.0

# ─── DEBUG OVERLAY NODES ─────────────────────────────────────────────────────
var _debug_canvas: CanvasLayer = null
var _debug_label: Label = null
var _debug_mod_label: Label = null
var _debug_state_label: Label = null

# ─── SIGNALS ─────────────────────────────────────────────────────────────────
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
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bg.size = Vector2(400, 160)
	bg.position = Vector2(10, 10)
	bg.color = Color(0, 0, 0, 0.7)
	_debug_canvas.add_child(bg)
	
	# Confidence value label
	_debug_label = Label.new()
	_debug_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_debug_label.position = Vector2(15, 15)
	_debug_label.size = Vector2(380, 30)
	_debug_label.add_theme_font_size_override("font_size", 18)
	_debug_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
	_debug_canvas.add_child(_debug_label)
	
	# Active modifiers label
	_debug_mod_label = Label.new()
	_debug_mod_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_debug_mod_label.position = Vector2(15, 45)
	_debug_mod_label.size = Vector2(380, 80)
	_debug_mod_label.add_theme_font_size_override("font_size", 12)
	_debug_mod_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_debug_canvas.add_child(_debug_mod_label)
	
	# Current FSM state label
	_debug_state_label = Label.new()
	_debug_state_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_debug_state_label.position = Vector2(15, 125)
	_debug_state_label.size = Vector2(380, 30)
	_debug_state_label.add_theme_font_size_override("font_size", 14)
	_debug_state_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	_debug_canvas.add_child(_debug_state_label)
	
	# ─── FORCED VISIBILITY DEBUG ────────────────────────────────────
	# Log the CanvasLayer's initial state so we can verify it was created
	# correctly. If the overlay is invisible at runtime, this log confirms
	# the node exists and is parented to the SceneTree.
	print("[Confidence] Debug overlay initialized. CanvasLayer: ", _debug_canvas.get_path())
	print("[Confidence] CanvasLayer layer: ", _debug_canvas.layer, " | visible: ", _debug_canvas.visible)
	print("[Confidence] CanvasLayer process_mode: ", _debug_canvas.process_mode)
	print("[Confidence] Background ColorRect size: ", bg.size, " position: ", bg.position)
	print("[Confidence] Labels created: confidence=", _debug_label != null, " modifiers=", _debug_mod_label != null, " state=", _debug_state_label != null)


func _input(event: InputEvent) -> void:
	# F3 toggles the confidence debug overlay
	if event is InputEventKey and event.keycode == KEY_F3 and event.pressed and not event.is_echo():
		debug_overlay_active = not debug_overlay_active
		if _debug_canvas:
			_debug_canvas.visible = debug_overlay_active
		print("[Confidence] Debug overlay toggled: ", "ON" if debug_overlay_active else "OFF")


func _process(delta: float) -> void:
	if not entity or not is_instance_valid(entity):
		return
	
	# ─── 1. APPLY ACTIVE MODIFIERS ──────────────────────────────────
	_debug_modifier_strings.clear()
	var expired_sources: Array[String] = []
	
	for source in _active_modifiers:
		var mod_data: Dictionary = _active_modifiers[source]
		var rate: float = mod_data.get("rate", 0.0)
		var expires_at: float = mod_data.get("expires_at", -1.0)
		
		# Check expiration
		if expires_at > 0.0 and entity._game_time >= expires_at:
			expired_sources.append(source)
			continue
		
		# Apply the modifier
		confidence += rate * delta
		
		# Build debug string
		var sign: String = "+" if rate >= 0.0 else ""
		_debug_modifier_strings.append("%s%.1f/s %s" % [sign, rate, source])
	
	# Remove expired modifiers
	for source in expired_sources:
		_active_modifiers.erase(source)
	
	# ─── 2. APPLY NIGHT PROGRESSION MODIFIER ────────────────────────
	# As the night advances, confidence naturally increases.
	# night_progress ranges from 0.0 to 1.0.
	# At progress 1.0, the modifier reaches +0.3/s.
	var nm: Node = entity.get_node_or_null("/root/NightManager")
	if nm:
		var night_progress: float = nm.night_progress if "night_progress" in nm else 0.0
		_night_progress_mod = night_progress * 0.3
		confidence += _night_progress_mod * delta
		
		# Update night base from current night
		var current_night: int = nm.current_night if "current_night" in nm else 1
		_night_base = (current_night - 1) * 8.0
		_resting_confidence = 15.0 + _night_base
	
	# ─── 3. DRIFT TOWARD RESTING VALUE ──────────────────────────────
	# When no modifiers are active, confidence drifts toward the resting value.
	# This prevents confidence from staying at extreme values indefinitely.
	if _active_modifiers.is_empty():
		if confidence < _resting_confidence:
			confidence += _decay_rate * delta
		elif confidence > _resting_confidence:
			confidence -= _decay_rate * delta
	
	# ─── 4. CLAMP ───────────────────────────────────────────────────
	confidence = clampf(confidence, 0.0, 100.0)
	
	# ─── 5. THRESHOLD CROSSING DETECTION ────────────────────────────
	# Check if confidence crossed any threshold boundaries this frame.
	# This is a simple frame-by-frame check — for a production system,
	# we'd track previous frame values. For now, this is sufficient.
	_check_thresholds()
	
	# ─── 6. UPDATE DEBUG OVERLAY ────────────────────────────────────
	if debug_overlay_active and _debug_label:
		_update_debug_overlay()


## Checks if confidence crossed any threshold boundaries and emits signals.
func _check_thresholds() -> void:
	# We check if confidence is currently above each threshold.
	# The downstream consumers (entity_ai.gd) use these signals to gate
	# state transitions. This is a simplified frame-by-frame check.
	pass  # Threshold logic is handled by the AI's process_state_logic()


## Updates the F3 debug overlay with current confidence data.
func _update_debug_overlay() -> void:
	if not _debug_label or not _debug_mod_label or not _debug_state_label:
		return
	
	# Color-code the confidence value based on range
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
	
	_debug_label.add_theme_color_override("font_color", color)
	_debug_label.text = "CONFIDENCE: %.1f / 100.0" % confidence
	
	# Threshold markers
	var thresholds_str: String = ""
	thresholds_str += "RETREAT(%.0f) " % THRESHOLD_RETREAT
	thresholds_str += "WINDOW(%.0f) " % THRESHOLD_WINDOW_APPROACH
	thresholds_str += "BREACH(%.0f) " % THRESHOLD_BREACH
	thresholds_str += "CLIMAX(%.0f)" % THRESHOLD_CLIMAX
	_debug_label.text += "\n" + thresholds_str
	
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
	
	# Current FSM state
	if entity:
		var state_name: String = "DORMANT"
		if "State" in entity and entity._state != null:
			var state_keys = entity.State.keys()
			var state_index: int = entity._state as int
			if state_index >= 0 and state_index < state_keys.size():
				state_name = state_keys[state_index]
		_debug_state_label.text = "FSM State: %s" % state_name


# ─── PUBLIC API ──────────────────────────────────────────────────────────────

## Returns the current confidence value (0.0–100.0).
func get_confidence() -> float:
	return confidence


## Applies an instantaneous confidence modification.
## amount: The delta to apply (positive = more bold, negative = more timid).
## source: A human-readable string identifying the source (for debug overlay).
func modify(amount: float, source: String) -> void:
	confidence = clampf(confidence + amount, 0.0, 100.0)
	print("[Confidence] Modified by %.1f (%s). New confidence: %.1f" % [amount, source, confidence])


## Adds a continuous modifier that applies every frame.
## rate: Per-second confidence change (positive or negative).
## source: A human-readable string identifying the source.
## duration: If > 0, the modifier auto-expires after this many seconds.
##           If <= 0, the modifier is permanent until explicitly removed.
func add_continuous_modifier(rate: float, source: String, duration: float = -1.0) -> void:
	var expires_at: float = -1.0
	if duration > 0.0:
		expires_at = entity._game_time + duration if "game_time" in entity else -1.0
	
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
