extends CanvasLayer

## HUD overlay for the horror game showing day/night cycle and events.

@onready var night_label: Label = $NightLabel
@onready var time_label: Label = $TimeLabel
@onready var clock_label: Label = $ClockLabel
@onready var event_label: Label = $EventLabel
@onready var event_timer: Timer = $EventTimer
@onready var phase_bar: ProgressBar = $PhaseBar

## Reference to GameTime singleton (found via multiple methods)
var _game_time: Node = null

func _ready() -> void:
	# Try to find GameTime via multiple methods
	_game_time = _find_game_time()
	if _game_time:
		_connect_game_time_signals()
	else:
		print("HorrorHUD: GameTime not found in _ready(), will retry via _process")
	
	if Engine.has_singleton("NightManager"):
		var nm = Engine.get_singleton("NightManager")
		nm.night_started.connect(_on_nm_night_started)
		nm.night_ended.connect(_on_night_ended)
		nm.horror_event.connect(_on_horror_event)
		_update_night_label(nm.current_night)
	
	event_label.modulate = Color(1, 1, 1, 0)


## Finds the GameTime node via singleton or scene tree path.
func _find_game_time():
	# Method 1: Engine singleton
	if Engine.has_singleton("GameTime"):
		return Engine.get_singleton("GameTime")
	# Method 2: Scene tree path
	if has_node("/root/GameTime"):
		return get_node("/root/GameTime")
	return null


## Connects to GameTime signals.
func _connect_game_time_signals() -> void:
	if not _game_time:
		return
	if _game_time.has_signal("time_changed"):
		_game_time.time_changed.connect(_on_time_changed)
	if _game_time.has_signal("day_started"):
		_game_time.day_started.connect(_on_day_started)
	if _game_time.has_signal("night_started"):
		_game_time.night_started.connect(_on_night_started)
	_update_display(_game_time.get("cycle_progress"), _game_time.get("is_day"))
	print("HorrorHUD: Connected to GameTime signals")


# Poll GameTime every frame to ensure display updates
func _process(_delta: float) -> void:
	# Try to find GameTime if we don't have it yet
	if not _game_time:
		_game_time = _find_game_time()
		if _game_time:
			_connect_game_time_signals()
			print("HorrorHUD: Found GameTime via _process fallback")
	
	if _game_time:
		var progress = _game_time.get("cycle_progress")
		var is_day = _game_time.get("is_day")
		if progress != null and is_day != null:
			_update_display(progress, is_day)


func _on_time_changed(progress: float, is_day: bool) -> void:
	_update_display(progress, is_day)


func _update_display(progress: float, is_day: bool) -> void:
	if _game_time:
		# Time label: show elapsed game time
		var time_str = _game_time.get_time_string() if _game_time.has_method("get_time_string") else "00:00"
		time_label.text = time_str
		
		# Calculate time remaining in current phase (in seconds)
		var phase_duration = _game_time.get("phase_duration")
		if phase_duration == null:
			phase_duration = 300.0
		var remaining = phase_duration * (1.0 - progress)
		var total_seconds = int(remaining)
		var minutes = total_seconds / 60
		var seconds = total_seconds % 60
		var phase_name = "☀️ DAY" if is_day else "🌙 NIGHT"
		var time_remaining = "%02d:%02d" % [minutes, seconds]
		var percent = int(progress * 100)
		clock_label.text = "%s  %d%%  (%s remaining)" % [phase_name, percent, time_remaining]
	
	if phase_bar:
		phase_bar.value = progress * 100.0
		if is_day:
			phase_bar.modulate = Color(1, 0.9, 0.6, 1)  # Warm yellow for day
		else:
			phase_bar.modulate = Color(0.3, 0.3, 0.8, 1)  # Cool blue for night


func _on_day_started() -> void:
	_show_event("Day has broken!")


func _on_night_started() -> void:
	_show_event("Night has fallen...")


func _on_nm_night_started(night: int) -> void:
	_update_night_label(night)
	_show_event("Night %d - Survive until dawn..." % night)


func _on_night_ended(night: int) -> void:
	_show_event("Night %d survived!" % night)


func _on_horror_event(event_name: String) -> void:
	var display_name = event_name.replace("_", " ").capitalize()
	_show_event(display_name)


func _update_night_label(night: int) -> void:
	night_label.text = "Night %d / 5" % night


func _show_event(text: String) -> void:
	event_label.text = text
	event_label.modulate = Color(1, 1, 1, 1)
	# Fade out after a moment
	if event_timer:
		event_timer.start()


func _on_event_timer_timeout() -> void:
	var tween = create_tween()
	tween.tween_property(event_label, "modulate", Color(1, 1, 1, 0), 2.0)
