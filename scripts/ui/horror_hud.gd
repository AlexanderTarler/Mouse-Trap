extends CanvasLayer

## HUD overlay for the horror game showing day/night cycle progression and events.

@onready var night_label: Label = $NightLabel
@onready var time_label: Label = $TimeLabel
@onready var clock_label: Label = $ClockLabel
@onready var event_label: Label = $EventLabel
@onready var event_timer: Timer = $EventTimer
@onready var phase_bar: ProgressBar = $PhaseBar
@onready var objective_label: Label = $ObjectiveLabel

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
	# Create the fade overlay programmatically
	_fade_overlay = ColorRect.new()
	_fade_overlay.color = Color(0, 0, 0, 0)  # Start fully transparent
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block clicks
	_fade_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_overlay.z_index = 100  # Render above everything
	add_child(_fade_overlay)
	
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		nm.night_started.connect(_on_night_started)
		nm.night_ended.connect(_on_night_ended)
		nm.horror_event.connect(_on_horror_event)
		nm.fuel_changed.connect(_on_generator_fuel_changed)
		nm.generator_state_changed.connect(_on_generator_state_changed)
		nm.first_chase_started.connect(_on_first_chase_started)
		_update_night_label(nm.current_night)
		# Initialize fuel bar with current fuel value
		_on_generator_fuel_changed(nm.generator_fuel)
	
	# Connect to GameTime's time_changed signal for immediate HUD refresh
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
	
	# Time label: show elapsed time in current phase
	var elapsed = int(phase_duration * phase_progress)
	var e_minutes = int(elapsed / 60.0)
	var e_seconds = elapsed % 60
	time_label.text = "%02d:%02d / %s" % [e_minutes, e_seconds, time_remaining]
	
	# Clock label: show countdown to next phase
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


func _on_night_started(night: int) -> void:
	_update_night_label(night)
	_show_event("Night %d - Survive until dawn..." % night)


func _on_night_ended(night: int) -> void:
	_show_event("Night %d survived!" % night)


func _on_horror_event(event_name: String) -> void:
	var display_name = event_name.replace("_", " ").capitalize()
	_show_event(display_name)


## Called when NightManager emits first_chase_started (Night 1 narrative event).
## Unlocks the player's sprint ability and displays a prominent UI hint.
func _on_first_chase_started() -> void:
	# Find the player and unlock sprint
	var player = get_node_or_null("/root/CottageHorror/Player")
	if not player:
		player = get_node_or_null("/root/Main/Player")
	if player and "sprint_unlocked" in player:
		player.sprint_unlocked = true
		print("[HUD] Sprint unlocked for the player!")
	
	# Display a massive, highly visible UI hint
	_show_event("⚠️ PRESS SHIFT TO RUN ⚠️")


## Updates the generator fuel bar on the HUD.
## Colors the bar green/yellow when fuel is healthy, red when below 25%.
func _on_generator_fuel_changed(current_fuel: float) -> void:
	if not fuel_bar or not fuel_label:
		return
	
	fuel_bar.value = current_fuel
	fuel_label.text = "⛽ %d%%" % current_fuel
	
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
		_show_event("⚠️ Generator offline! Lights out!")
		# Gray out the fuel bar to indicate the generator is off
		if fuel_bar:
			fuel_bar.modulate = Color(0.4, 0.4, 0.4, 0.6)
		if fuel_label:
			fuel_label.text = "⛽ OFF"
	else:
		_show_event("⚡ Generator restarted!")
		# Restore fuel bar color and label (will be updated by next fuel_changed signal)
		if fuel_bar:
			fuel_bar.modulate = Color(0.3, 0.8, 0.3, 1.0)
		if fuel_label:
			fuel_label.text = "⛽ %d%%" % fuel_bar.value


func _update_night_label(night: int) -> void:
	night_label.text = "Night %d / 5" % night


## Shows an event message with a 3-second display time, then fades out.
## Messages are queued so each one gets its full display time.
func _show_event(text: String) -> void:
	_message_queue.append(text)
	if not _message_busy:
		_display_next_message()


func _display_next_message() -> void:
	if _message_queue.is_empty():
		_message_busy = false
		return
	
	_message_busy = true
	var text = _message_queue.pop_front()
	
	event_label.text = text
	event_label.modulate = Color(1, 1, 1, 1)
	if event_timer:
		event_timer.wait_time = 3.0  # Show for 3 seconds before fade
		event_timer.start()


func _on_event_timer_timeout() -> void:
	var tween = create_tween()
	tween.tween_property(event_label, "modulate:a", 0.0, 1.0)
	# After the fade completes, show the next message in the queue
	tween.finished.connect(_display_next_message.bind(), CONNECT_ONE_SHOT)


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
	_show_event(msg)


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
