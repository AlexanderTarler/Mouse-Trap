extends CanvasLayer

## HUD overlay for the horror game showing day/night cycle progression and events.

@onready var night_label: Label = $NightLabel
@onready var time_label: Label = $TimeLabel
@onready var clock_label: Label = $ClockLabel
@onready var event_label: Label = $EventLabel
@onready var event_timer: Timer = $EventTimer
@onready var phase_bar: ProgressBar = $PhaseBar
@onready var objective_label: Label = $ObjectiveLabel

# Onboarding hint nodes
@onready var hint_label: Label = $HintLabel
@onready var hint_timer: Timer = $HintTimer

# Battery meter nodes
@onready var battery_bar: ProgressBar = $BatteryBar
@onready var battery_label: Label = $BatteryBar/BatteryLabel
@onready var low_battery_warning: Label = $LowBatteryWarning

# Stamina meter nodes
@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var stamina_label: Label = $StaminaBar/StaminaLabel

# Fuel meter nodes
@onready var fuel_bar: TextureProgressBar = $GeneratorFuelBar
@onready var fuel_label: Label = $GeneratorFuelBar/FuelLabel

## Reference to the EnvironmentController (set in the scene)
@export var environment_controller: Node

# Flashlight reference
var _flashlight: Node = null

# Low battery warning flicker timer
var _warning_flicker_timer: float = 0.0
var _warning_visible: bool = false

# Message queue for event labels — ensures each message gets its full display time
var _message_queue: Array[String] = []
var _message_busy: bool = false

# ─── PURGE PROGRESS BAR ────────────────────────────────────────────────
# A full-width progress bar displayed at the center of the screen when the
# player is actively purging the TotemAnchor. Created programmatically so
# no scene changes are needed.
var _purge_bar_bg: ColorRect = null
var _purge_bar_fill: ColorRect = null
var _purge_bar_label: Label = null
var _purge_bar_visible: bool = false

# ─── FADE-TO-BLACK SYSTEM ──────────────────────────────────────────────
# A full-screen ColorRect overlay that tweens alpha for cinematic fades.
# Created programmatically in _ready() so no scene changes are needed.
var _fade_overlay: ColorRect = null

# ─── ROOM DEBUG LABEL ──────────────────────────────────────────────────
# A small label in the top-left corner showing which room the player is in.
# Created programmatically in _ready() so no scene changes are needed.
var _room_label: Label = null
var _room_label_visible: bool = false


func _ready() -> void:
	add_to_group("hud")
	
	# Create the fade overlay programmatically
	_fade_overlay = ColorRect.new()
	_fade_overlay.color = Color(0, 0, 0, 0)  # Start fully transparent
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block clicks
	_fade_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_overlay.z_index = 100  # Render above everything
	add_child(_fade_overlay)

	# ─── IMMEDIATE DATA SYNC ───────────────────────────────────
	# GameTime starts paused (no signals emitted), so we must
	# manually pull the current state from all autoloads to
	# overwrite the .tscn placeholder text immediately.
	_sync_all_displays()

	# ─── SIGNAL CONNECTIONS ────────────────────────────────────
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		nm.night_started.connect(_on_night_started)
		nm.night_ended.connect(_on_night_ended)
		nm.horror_event.connect(_on_horror_event)
		nm.fuel_changed.connect(_on_generator_fuel_changed)
		nm.generator_state_changed.connect(_on_generator_state_changed)
		nm.first_chase_started.connect(_on_first_chase_started)

	var gt = get_node_or_null("/root/GameTime")
	if gt:
		gt.time_changed.connect(_on_game_time_changed)

	# Find EnvironmentController if not assigned
	if not environment_controller:
		environment_controller = get_node_or_null("/root/Main/EnvironmentController")
		if not environment_controller:
			environment_controller = get_node_or_null("/root/CottageHorror/EnvironmentController")

	event_label.modulate = Color(1, 1, 1, 0)

	# Connect the event timer's timeout signal so messages fade properly
	if event_timer:
		event_timer.timeout.connect(_on_event_timer_timeout)

	# Find the flashlight and connect to its battery_changed signal
	_find_and_connect_flashlight()

	# Connect to player stamina signal
	_find_and_connect_stamina()

	# Connect to RoutineManager for Night 1 bedtime routine objective
	_connect_routine_manager()


## Fades the screen to pitch black over the given duration.
## Uses a Tween on the _fade_overlay ColorRect alpha.
func fade_to_black(duration: float = 1.5) -> void:
	if not _fade_overlay:
		return
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # Block clicks during fade
	var tween = create_tween()
	tween.tween_property(_fade_overlay, "color:a", 1.0, duration)
	await tween.finished


## Fades the screen back in from pitch black over the given duration.
## Uses a Tween on the _fade_overlay ColorRect alpha.
func fade_from_black(duration: float = 2.0) -> void:
	if not _fade_overlay:
		return
	var tween = create_tween()
	tween.tween_property(_fade_overlay, "color:a", 0.0, duration)
	await tween.finished
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Restore click-through


## ─── CAMERA FLASH SNAP ─────────────────────────────────────────────────────
## High-priority white flash overlay for the photo camera's shutter.
##
## freeze_duration: How long the screen stays fully white (default 0.3s).
## decay_duration:  How long the white flash takes to fade to transparent (default 1.0s).
##
## The flash overlay is created programmatically (like _fade_overlay) so it
## works independently of the CameraHUD scene. This ensures the flash always
## renders, even if the CameraHUD has rendering issues.
var _camera_flash_overlay: ColorRect = null

func trigger_camera_flash_snap(freeze_duration: float = 0.3, decay_duration: float = 1.0) -> void:
	# Lazily create the camera flash overlay (same pattern as _fade_overlay)
	if not _camera_flash_overlay:
		_camera_flash_overlay = ColorRect.new()
		_camera_flash_overlay.color = Color(1, 1, 1, 0)  # Start transparent
		_camera_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_camera_flash_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_camera_flash_overlay.z_index = 101  # Above _fade_overlay (100)
		add_child(_camera_flash_overlay)
	
	# Phase 1: Instant white flash
	_camera_flash_overlay.color = Color(1, 1, 1, 1.0)
	_camera_flash_overlay.visible = true
	
	# Phase 2: Hold the freeze for freeze_duration seconds
	await get_tree().create_timer(freeze_duration).timeout
	
	# Phase 3: Elegant Tween decay over decay_duration seconds
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_camera_flash_overlay, "color:a", 0.0, decay_duration)
	await tween.finished
	
	# Cleanup
	_camera_flash_overlay.visible = false


func _connect_routine_manager() -> void:
	var rm = get_node_or_null("/root/RoutineManager")
	if rm:
		rm.routine_step_changed.connect(_on_routine_step_changed)
		# Initialize the objective label with the current step
		if objective_label:
			objective_label.text = rm.get_current_objective()
		print("[HUD] Connected to RoutineManager.")
	else:
		# Retry next frame — RoutineManager might not be ready yet
		call_deferred("_connect_routine_manager")


## Called when the Night 1 bedtime routine advances to a new step.
## Updates the objective label text on the HUD.
func _on_routine_step_changed(step: int, objective_text: String) -> void:
	if not objective_label:
		return
	
	objective_label.text = objective_text
	print("[HUD] Routine step updated: Step ", step, " — ", objective_text)


func _find_and_connect_flashlight() -> void:
	# Try to find the player and flashlight
	var player = get_node_or_null("/root/CottageHorror/Player")
	if not player:
		player = get_node_or_null("/root/Main/Player")
	
	if player:
		_flashlight = player.find_child("Flashlight", true, false)
		if _flashlight and _flashlight.has_signal("battery_changed"):
			_flashlight.battery_changed.connect(_on_battery_changed)
			# Initialize the battery display
			if _flashlight.has_method("get_battery_percent"):
				_on_battery_changed(_flashlight.battery_level)
		else:
			# Retry next frame
			call_deferred("_find_and_connect_flashlight")
	else:
		# Retry next frame if player not found yet
		call_deferred("_find_and_connect_flashlight")


func _find_and_connect_stamina() -> void:
	# Try to find the player
	var player = get_node_or_null("/root/CottageHorror/Player")
	if not player:
		player = get_node_or_null("/root/Main/Player")
	
	if player and player.has_signal("stamina_changed"):
		player.stamina_changed.connect(_on_stamina_changed)
		_on_stamina_changed(100.0)  # Initialize at full
	else:
		# Retry next frame
		call_deferred("_find_and_connect_stamina")


func _on_stamina_changed(percent: float) -> void:
	if not stamina_bar or not stamina_label:
		return
	
	stamina_bar.value = percent
	stamina_label.text = "⚡ %d%%" % percent
	
	# Hide stamina bar when at 100%
	if percent >= 99.9:
		stamina_bar.modulate = Color(0.3, 0.8, 0.3, 0)
		stamina_label.modulate = Color(1, 1, 1, 0)
	else:
		# Show and color based on level
		stamina_label.modulate = Color(1, 1, 1, 0.9)
		if percent <= 25.0:
			stamina_bar.modulate = Color(1.0, 0.2, 0.2, 1.0)  # Red - exhausted
		elif percent <= 50.0:
			stamina_bar.modulate = Color(1.0, 0.8, 0.2, 1.0)  # Yellow - warning
		else:
			stamina_bar.modulate = Color(0.3, 0.8, 0.3, 1.0)  # Green - good


func _on_battery_changed(level: float) -> void:
	if not battery_bar or not battery_label:
		return
	
	# Calculate percentage
	var max_battery = _flashlight.max_battery if _flashlight else 100.0
	var percent = (level / max_battery) * 100.0
	
	# Update bar
	battery_bar.value = percent
	battery_label.text = "🔋 %d%%" % percent
	
	# Color the bar based on battery level
	if percent <= 15.0:
		# Red - critical
		battery_bar.modulate = Color(1.0, 0.2, 0.2, 1.0)
		low_battery_warning.modulate = Color(1, 0.2, 0.2, 1)
	elif percent <= 30.0:
		# Yellow - warning
		battery_bar.modulate = Color(1.0, 0.8, 0.2, 1.0)
		low_battery_warning.modulate = Color(1, 0.2, 0.2, 0)
	else:
		# Green - good
		battery_bar.modulate = Color(0.3, 0.8, 0.3, 1.0)
		low_battery_warning.modulate = Color(1, 0.2, 0.2, 0)


# Poll every frame to update the display
func _process(delta: float) -> void:
	var progress: float = 0.0
	var p_is_day: bool = true
	
	# Read from GameTime directly as the primary source (most reliable).
	# Fall back to EnvironmentController if GameTime isn't available.
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		progress = gt.cycle_progress
		p_is_day = gt.is_day
	elif environment_controller:
		progress = environment_controller.cycle_progress
		p_is_day = environment_controller.is_day
	
	_update_display(progress, p_is_day)
	
	# Update low battery warning flicker
	_update_low_battery_warning(delta)
	
	# ─── ROOM DEBUG LABEL ──────────────────────────────────────────────
	# Update the room label every frame to show which room the player is in.
	# The label is created lazily on first use (like the purge bar).
	_update_room_label()


func _update_low_battery_warning(delta: float) -> void:
	if not low_battery_warning:
		return
	
	# Only flicker if the warning is visible (alpha > 0)
	if low_battery_warning.modulate.a > 0.0:
		_warning_flicker_timer -= delta
		if _warning_flicker_timer <= 0.0:
			_warning_flicker_timer = randf_range(0.1, 0.5)
			_warning_visible = not _warning_visible
			var alpha = 1.0 if _warning_visible else 0.3
			low_battery_warning.modulate = Color(1, 0.2, 0.2, alpha)


func _update_display(progress: float, p_is_day: bool) -> void:
	var phase_duration = 300.0  # 5 minutes per phase (half of 600s cycle)
	var phase_progress: float
	
	if p_is_day:
		phase_progress = progress / 0.5
	else:
		phase_progress = (progress - 0.5) / 0.5
	
	# Clamp phase_progress to valid range
	phase_progress = clampf(phase_progress, 0.0, 1.0)
	
	# Calculate time remaining in current phase
	var remaining = phase_duration * (1.0 - phase_progress)
	var total_seconds = int(remaining)
	var minutes = int(total_seconds / 60.0)
	var seconds = total_seconds % 60
	var time_remaining = "%02d:%02d" % [minutes, seconds]
	
	# Phase name and icon
	var phase_name = "☀️ DAY" if p_is_day else "🌙 NIGHT"
	var next_phase = "night" if p_is_day else "day"
	
	# Time label: show elapsed / remaining in current phase (real-time MM:SS)
	var elapsed = int(phase_duration * phase_progress)
	var e_minutes = int(elapsed / 60.0)
	var e_seconds = elapsed % 60
	time_label.text = "%02d:%02d / %s" % [e_minutes, e_seconds, time_remaining]
	
	# Clock label: show phase progress percentage + countdown to next phase
	var percent = int(phase_progress * 100)
	clock_label.text = "%s  %d%%  (%s until %s)" % [phase_name, percent, time_remaining, next_phase]
	
	# Phase bar: show full cycle progress (0-100%)
	if phase_bar:
		phase_bar.value = progress * 100.0
		if p_is_day:
			phase_bar.modulate = Color(1.0, 0.85, 0.4, 1)  # Warm gold for day
		else:
			phase_bar.modulate = Color(0.3, 0.3, 0.8, 1)  # Cool blue for night


## Called when GameTime emits time_changed — forces an immediate HUD refresh.
## This is the belt-and-suspenders guarantee that the clock updates instantly
## when time is unpaused by the phone drop event.
func _on_game_time_changed(_progress: float) -> void:
	# Re-read the latest values from GameTime and refresh the display
	var progress: float = 0.0
	var p_is_day: bool = true
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		progress = gt.cycle_progress
		p_is_day = gt.is_day
	_update_display(progress, p_is_day)


## Pulls the current state from GameTime and NightManager autoloads and
## updates every HUD label in a single atomic pass. Called once in _ready()
## to overwrite .tscn placeholder text before the scene becomes visible.
## GameTime starts paused (no signals emitted), so this manual sync is
## the only way to get correct values on the HUD at startup.
func _sync_all_displays() -> void:
	# ─── Night label ──────────────────────────────────────────────
	# Use RoutineManager's get_current_day_string() which correctly
	# maps night 0→"Day 1", night 1→"Day 1", night 2→"Day 2", etc.
	var rm = get_node_or_null("/root/RoutineManager")
	var nm = get_node_or_null("/root/NightManager")
	if rm and rm.has_method("get_current_day_string"):
		night_label.text = rm.get_current_day_string()
	elif nm:
		night_label.text = "Day 1" if nm.current_night <= 0 else "Night %d / 5" % nm.current_night
	else:
		night_label.text = "Day 1"
	# Also sync fuel display immediately
	if nm:
		_on_generator_fuel_changed(nm.generator_fuel)

	# ─── Event label clear ─────────────────────────────────────────
	if event_label:
		event_label.text = ""
		event_label.modulate = Color(1, 1, 1, 0)

	# ─── Time display ──────────────────────────────────────────────
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		_update_display(gt.cycle_progress, gt.is_day)
		# ─── DEBUG: Log the exact time the HUD shows on screen ──────────
		print("[HorrorHUD] UI Clock: clock_label='%s' time_label='%s' | GameTime: progress=%.4f, is_day=%s)" % [
			clock_label.text if clock_label else "N/A",
			time_label.text if time_label else "N/A",
			gt.cycle_progress, gt.is_day
		])


func _on_night_started(night: int) -> void:
	_update_night_label(night)
	# Event messages removed per design direction


func _on_night_ended(night: int) -> void:
	# Event messages removed per design direction
	# Defer the display sync to the next frame so that NightManager's
	# end_current_night() has fully finished incrementing current_night
	# before RoutineManager reads it. Without this, get_current_day_string()
	# can return "Day 2" because current_night hasn't been updated yet.
	call_deferred("_sync_all_displays")


func _on_horror_event(event_name: String) -> void:
	# Event messages removed per design direction
	pass


## Called when NightManager emits first_chase_started (Night 1 narrative event).
## Unlocks the player's sprint ability.
func _on_first_chase_started() -> void:
	# Find the player and unlock sprint
	var player = get_node_or_null("/root/CottageHorror/Player")
	if not player:
		player = get_node_or_null("/root/Main/Player")
	if player and "sprint_unlocked" in player:
		player.sprint_unlocked = true
		print("[HUD] Sprint unlocked for the player!")


## Updates the generator fuel bar on the HUD.
## Colors the bar green/yellow when fuel is healthy, red when below 25%.
func _on_generator_fuel_changed(current_fuel: float) -> void:
	if not fuel_bar or not fuel_label:
		return
	
	fuel_bar.value = current_fuel
	fuel_label.text = "⛽ Generator"
	
	# Color the bar based on fuel level
	if current_fuel <= 25.0:
		# Red - critical
		fuel_bar.modulate = Color(1.0, 0.2, 0.2, 1.0)
	elif current_fuel <= 50.0:
		# Yellow - warning
		fuel_bar.modulate = Color(1.0, 0.8, 0.2, 1.0)
	else:
		# Green - good
		fuel_bar.modulate = Color(0.3, 0.8, 0.3, 1.0)


## Called when the generator turns on or off.
## Shows a blackout event message when the generator stops.
func _on_generator_state_changed(is_running: bool) -> void:
	if not is_running:
		# Gray out the fuel bar to indicate the generator is off
		if fuel_bar:
			fuel_bar.modulate = Color(0.4, 0.4, 0.4, 0.6)
		if fuel_label:
			fuel_label.text = "⛽ OFF"
	else:
		# Restore fuel bar color and label (will be updated by next fuel_changed signal)
		if fuel_bar:
			fuel_bar.modulate = Color(0.3, 0.8, 0.3, 1.0)
		if fuel_label:
			fuel_label.text = "⛽ Generator"


func _update_night_label(night: int) -> void:
	# Use RoutineManager's day mapping (Night 0→"Day 1", Night 1→"Day 1",
	# Night 2→"Day 2", etc.) for the HUD label. Fall back to raw night
	# number if RoutineManager is unavailable.
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("get_current_day_string"):
		night_label.text = rm.get_current_day_string()
	else:
		night_label.text = "Night %d / 5" % night


## Shows an event message with a 3-second display time, then fades out.
## Messages are queued so each one gets its full display time.
func _show_event(text: String) -> void:
	# Event messages removed per design direction
	pass


func _display_next_message() -> void:
	# Event messages removed per design direction
	_message_busy = false


func _on_event_timer_timeout() -> void:
	# Event messages removed per design direction
	pass


# ─── PURGE PROGRESS BAR ────────────────────────────────────────────────
# Public API for the TotemAnchor to display a timed hold-to-purge progress
# meter on the HUD. The bar is created programmatically on first use.

## Shows the purge progress bar overlay at the center of the screen.
## Called by TotemAnchor.interact() when the player begins purging.
func show_purge_progress() -> void:
	if not _purge_bar_bg:
		_create_purge_bar_nodes()
	_purge_bar_bg.visible = true
	_purge_bar_fill.size.x = 0.0
	_purge_bar_fill.modulate = Color(1.0, 0.5, 0.0, 1.0)  # Orange
	_purge_bar_label.text = "Purging Totem..."
	_purge_bar_label.modulate = Color(1, 1, 1, 1)
	_purge_bar_visible = true


## Updates the purge progress bar fill to reflect the current progress ratio.
## progress_ratio: 0.0 (empty) to 1.0 (complete).
func update_purge_progress(progress_ratio: float) -> void:
	if not _purge_bar_visible or not _purge_bar_bg:
		return
	
	var clamped: float = clampf(progress_ratio, 0.0, 1.0)
	_purge_bar_fill.size.x = _purge_bar_bg.size.x * clamped
	
	# Color transitions: Orange → Yellow → Green as progress increases
	if clamped >= 1.0:
		_purge_bar_fill.modulate = Color(0.3, 1.0, 0.3, 1.0)  # Green - complete
		_purge_bar_label.text = "Totem Purged!"
	elif clamped >= 0.66:
		_purge_bar_fill.modulate = Color(1.0, 0.9, 0.2, 1.0)  # Yellow - almost there
		_purge_bar_label.text = "Purging Totem... %.0f%%" % (clamped * 100.0)
	elif clamped >= 0.33:
		_purge_bar_fill.modulate = Color(1.0, 0.7, 0.1, 1.0)  # Amber - halfway
		_purge_bar_label.text = "Purging Totem... %.0f%%" % (clamped * 100.0)
	else:
		_purge_bar_fill.modulate = Color(1.0, 0.5, 0.0, 1.0)  # Orange - starting
		_purge_bar_label.text = "Purging Totem... %.0f%%" % (clamped * 100.0)


## Hides the purge progress bar overlay.
## Called by TotemAnchor when the player releases the interact key early
## or when the purge completes.
func hide_purge_progress() -> void:
	if _purge_bar_bg:
		_purge_bar_bg.visible = false
	_purge_bar_visible = false


## Updates the room debug label every frame.
## Creates the label lazily on first call (no scene changes needed).
## Shows which room the player is currently in by calling
## player_controller.gd's get_player_room() method.
func _update_room_label() -> void:
	# Lazily create the room label on first use
	if not _room_label:
		_room_label = Label.new()
		_room_label.name = "RoomLabel"
		_room_label.theme = Theme.new()
		_room_label.theme.default_font_size = 14
		_room_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 0.7))  # Light blue, semi-transparent
		_room_label.add_theme_constant_override("outline_size", 1)
		_room_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
		_room_label.position = Vector2(20, 230)  # Below the stamina bar
		_room_label.z_index = 10
		add_child(_room_label)
		_room_label_visible = true
	
	# Find the player and get the current room
	var player = get_node_or_null("/root/CottageHorror/Player")
	if not player:
		player = get_node_or_null("/root/Main/Player")
	
	if player and player.has_method("get_player_room"):
		var room_name = player.get_player_room()
		_room_label.text = "📍 Room: %s" % room_name
	else:
		_room_label.text = "📍 Room: N/A"


## Public API: Shows a temporary message on the HUD event label.
## Called by TotemAnchor and other interactables to display feedback text
## (e.g., "The totem is protected by the Entity's presence...").
## The message is displayed for 3.0 seconds, then fades out automatically
## via the existing _show_event() message queue system.
func show_message(msg: String) -> void:
	# Event messages removed per design direction
	pass


var _hint_tween: Tween = null

## Tracks whether any hint has been shown yet. Used to distinguish a
## genuine visible hint from the HintLabel's default alpha=1.0 in the scene.
var _hint_has_been_shown: bool = false

# ─── ONBOARDING HINT SYSTEM ─────────────────────────────────────────────
# Displays a short contextual hint that fades in after a small delay.
# Designed for Day 1 onboarding triggers (e.g., HintArea near the cabin).

## Helper: formatted timestamp in seconds for debug logging.
func _timestamp() -> String:
	var ms := Time.get_ticks_msec()
	var sec := ms / 1000
	var frac := ms % 1000
	return "%d.%03d" % [sec, frac]


## Shows a hint with the given text. The hint stays invisible for `delay`
## seconds, then fades in over 0.5s. Call hide_hint() to dismiss it.
##
## If a previous hint is still fading in (timer running), the text is
## replaced in-place without restarting the timer, preventing the "flash"
## caused by competing fade animations.
##
## If a hint is already fully visible, it IGNORES the new request so the
## current hint stays on screen until dismissed by mark_learned().
func show_hint(text: String, delay: float = 0.5) -> void:
	if not hint_label:
		return
	
	# If a hint is already visible AND we've already shown one before, ignore.
	# (The first call must pass through — HintLabel starts at alpha=1.0 in the
	# scene file, so we'd skip every tutorial without this guard.)
	if _hint_has_been_shown and hint_label.modulate.a > 0.0:
		print("[HorrorHUD] T+%s show_hint BLOCKED — hint already visible: '%s'" % [_timestamp(), hint_label.text])
		return
	
	# If hint timer is still running (fade-in hasn't started yet),
	# just update the text — keep the existing timer/tween.
	if hint_timer and not hint_timer.is_stopped():
		print("[HorrorHUD] T+%s show_hint REPLACED timer text → '%s'" % [_timestamp(), text])
		hint_label.text = text
		return
	
	# Kill any existing tween so we don't get competing fade animations
	if is_instance_valid(_hint_tween):
		_hint_tween.kill()
	
	_hint_has_been_shown = true
	hint_label.text = text
	hint_label.modulate = Color(0.9, 0.9, 0.8, 0.0)
	
	print("[HorrorHUD] T+%s show_hint SET → '%s' (fade-in in %.1fs)" % [_timestamp(), text, delay])
	
	if hint_timer:
		hint_timer.stop()
		hint_timer.wait_time = delay
		# Disconnect previous connection before adding a new one to prevent
		# connection pile-up that causes competing fade tweens.
		if hint_timer.timeout.is_connected(_on_hint_timer_timeout):
			hint_timer.timeout.disconnect(_on_hint_timer_timeout)
		hint_timer.timeout.connect(_on_hint_timer_timeout)
		hint_timer.start()


## Fades the hint label from alpha 1 to 0 over 0.5 seconds.
func hide_hint() -> void:
	if not hint_label:
		return
	
	print("[HorrorHUD] T+%s hide_hint — stopped: '%s'" % [_timestamp(), hint_label.text])
	
	# CRITICAL FIX: Stop the hint_timer to prevent _on_hint_timer_timeout()
	# from re-tweening the hint back to alpha 1.0. Without this, when the
	# hint's 0.5s fade-in delay timer fires AFTER hide_hint() was called
	# (e.g., player opens the notebook during the delay), the timeout
	# kills the fade-out tween and re-shows the hint permanently.
	hint_timer.stop()
	hint_label.modulate.a = 0.0
	
	if is_instance_valid(_hint_tween):
		_hint_tween.kill()
	
	_hint_tween = create_tween()
	_hint_tween.tween_property(hint_label, "modulate:a", 0.0, 0.5)


## Called once the hint delay timer expires. Fades the hint in naturally.
func _on_hint_timer_timeout() -> void:
	if not hint_label:
		return
	
	if is_instance_valid(_hint_tween):
		_hint_tween.kill()
	
	_hint_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_hint_tween.tween_property(hint_label, "modulate:a", 1.0, 0.5)


## Creates the purge bar UI nodes programmatically on first use.
func _create_purge_bar_nodes() -> void:
	# Background bar (dark gray, full-width container)
	_purge_bar_bg = ColorRect.new()
	_purge_bar_bg.name = "PurgeBarBackground"
	_purge_bar_bg.color = Color(0.15, 0.15, 0.15, 0.85)
	_purge_bar_bg.anchor_left = 0.3
	_purge_bar_bg.anchor_right = 0.7
	_purge_bar_bg.anchor_top = 0.55
	_purge_bar_bg.anchor_bottom = 0.58
	_purge_bar_bg.offset_left = 0.0
	_purge_bar_bg.offset_right = 0.0
	_purge_bar_bg.offset_top = 0.0
	_purge_bar_bg.offset_bottom = 0.0
	_purge_bar_bg.z_index = 50
	_purge_bar_bg.visible = false
	add_child(_purge_bar_bg)
	
	# Fill bar (colored overlay that grows left-to-right)
	_purge_bar_fill = ColorRect.new()
	_purge_bar_fill.name = "PurgeBarFill"
	_purge_bar_fill.color = Color(1.0, 0.5, 0.0, 1.0)  # Orange
	_purge_bar_fill.anchor_left = 0.0
	_purge_bar_fill.anchor_right = 0.0
	_purge_bar_fill.anchor_top = 0.0
	_purge_bar_fill.anchor_bottom = 1.0
	_purge_bar_fill.offset_left = 2.0
	_purge_bar_fill.offset_right = -2.0
	_purge_bar_fill.offset_top = 2.0
	_purge_bar_fill.offset_bottom = -2.0
	_purge_bar_fill.size.x = 0.0
	_purge_bar_fill.z_index = 51
	_purge_bar_bg.add_child(_purge_bar_fill)
	
	# Label (centered text above the bar)
	_purge_bar_label = Label.new()
	_purge_bar_label.name = "PurgeBarLabel"
	_purge_bar_label.text = "Purging Totem..."
	_purge_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_purge_bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_purge_bar_label.anchor_left = 0.0
	_purge_bar_label.anchor_right = 1.0
	_purge_bar_label.anchor_top = -1.5
	_purge_bar_label.anchor_bottom = 0.0
	_purge_bar_label.offset_top = -4.0
	_purge_bar_label.offset_bottom = 4.0
	_purge_bar_label.z_index = 52
	_purge_bar_bg.add_child(_purge_bar_label)