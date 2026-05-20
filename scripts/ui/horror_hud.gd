extends CanvasLayer

## HUD overlay for the horror game showing day/night cycle progression and events.

@onready var night_label: Label = $NightLabel
@onready var time_label: Label = $TimeLabel
@onready var clock_label: Label = $ClockLabel
@onready var event_label: Label = $EventLabel
@onready var event_timer: Timer = $EventTimer
@onready var phase_bar: ProgressBar = $PhaseBar

# Battery meter nodes
@onready var battery_bar: ProgressBar = $BatteryBar
@onready var battery_label: Label = $BatteryBar/BatteryLabel
@onready var low_battery_warning: Label = $LowBatteryWarning

# Stamina meter nodes
@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var stamina_label: Label = $StaminaBar/StaminaLabel

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


func _ready() -> void:
	if Engine.has_singleton("NightManager"):
		var nm = Engine.get_singleton("NightManager")
		nm.night_started.connect(_on_night_started)
		nm.night_ended.connect(_on_night_ended)
		nm.horror_event.connect(_on_horror_event)
		_update_night_label(nm.current_night)
	
	# Connect to GameTime's time_changed signal for immediate HUD refresh
	if Engine.has_singleton("GameTime"):
		var gt = Engine.get_singleton("GameTime")
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
	if Engine.has_singleton("GameTime"):
		var gt = Engine.get_singleton("GameTime")
		progress = gt.cycle_progress
		p_is_day = gt.is_day
	elif environment_controller:
		progress = environment_controller.cycle_progress
		p_is_day = environment_controller.is_day
	
	_update_display(progress, p_is_day)
	
	# Update low battery warning flicker
	_update_low_battery_warning(delta)


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
	if Engine.has_singleton("GameTime"):
		var gt = Engine.get_singleton("GameTime")
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
