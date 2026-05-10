extends CanvasLayer

## HUD overlay for the horror game showing night info and events.

@onready var night_label: Label = $NightLabel
@onready var time_label: Label = $TimeLabel
@onready var event_label: Label = $EventLabel
@onready var event_timer: Timer = $EventTimer

func _ready() -> void:
	if Engine.has_singleton("NightManager"):
		var nm = Engine.get_singleton("NightManager")
		nm.night_started.connect(_on_night_started)
		nm.night_ended.connect(_on_night_ended)
		nm.horror_event.connect(_on_horror_event)
		_update_night_label(nm.current_night)
	
	event_label.modulate = Color(1, 1, 1, 0)

func _process(_delta: float) -> void:
	if Engine.has_singleton("NightManager"):
		var nm = Engine.get_singleton("NightManager")
		var hours = int(nm.night_progress)
		var minutes = int((nm.night_progress - hours) * 60)
		var am_pm = "AM" if hours < 12 else "PM"
		var display_hour = hours if hours <= 12 and hours != 0 else (hours - 12 if hours > 12 else 12)
		if hours == 0:
			display_hour = 12
		time_label.text = "%02d:%02d %s" % [display_hour, minutes, am_pm]

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

func _show_event(text: String) -> void:
	event_label.text = text
	event_label.modulate = Color(1, 1, 1, 1)
	# Fade out after a moment
	if event_timer:
		event_timer.start()

func _on_event_timer_timeout() -> void:
	var tween = create_tween()
	tween.tween_property(event_label, "modulate", Color(1, 1, 1, 0), 2.0)
