class_name Wristwatch
extends CanvasLayer
## The player's wristwatch: hold [T] and it comes up in the lower right
## corner, an old analogue face with its hands at the game's time. The game's
## clock read as a believable one: dawn is 06:00 (GameTime progress 0.0),
## dusk 20:00 (0.5), dawn again 06:00 (1.0); a night runs from 20:00 to
## 06:00, so the player can count down to morning.
##
## Taught once, when the first night falls (TutorialManager "watch"); learned
## by looking. The player adds it (player_controller.gd).

## Its key (T unless rebound).
const ACTION := "watch"
const SIZE := 150.0
## Seconds to raise it, and to lower it.
const RAISE_TIME := 0.18
const LOWER_TIME := 0.25

var raised := 0.0
var _face: Control
var _taught := false


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_face = Control.new()
	_face.name = "WatchFace"
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.custom_minimum_size = Vector2(SIZE, SIZE)
	_face.size = Vector2(SIZE, SIZE)
	_face.draw.connect(_draw_face)
	add_child(_face)
	_place()
	var nm := get_node_or_null("/root/NightManager")
	if nm and nm.has_signal("night_started"):
		nm.night_started.connect(_on_night_started)


## The hours on the watch (0-24) at cycle `progress` (GameTime).
static func clock_hours(progress: float) -> float:
	progress = fposmod(progress, 1.0)
	if progress < 0.5:
		return 6.0 + progress / 0.5 * 14.0
	return fposmod(20.0 + (progress - 0.5) / 0.5 * 10.0, 24.0)


## "HH:MM" at cycle `progress`.
static func clock_text(progress: float) -> String:
	var hours := clock_hours(progress)
	return "%02d:%02d" % [int(hours), int(fmod(hours, 1.0) * 60.0)]


func is_held() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	return InputMap.has_action(ACTION) and Input.is_action_pressed(ACTION) and player != null and player.is_processing_input() and not get_tree().paused


func _process(delta: float) -> void:
	var held := is_held()
	if held and not _taught:
		_taught = true
		var tm := get_node_or_null("/root/TutorialManager")
		if tm and tm.has_method("mark_learned"):
			tm.mark_learned("watch")
	raised = move_toward(raised, 1.0 if held else 0.0, delta / (RAISE_TIME if held else LOWER_TIME))
	_place()
	if raised > 0.0:
		_face.queue_redraw()


## Down below the screen when lowered, up in the corner when raised.
func _place() -> void:
	var view := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
	var up := Vector2(view.x - SIZE - 40.0, view.y - SIZE - 40.0)
	var down := Vector2(up.x + 30.0, view.y + 20.0)
	var eased := 1.0 - pow(1.0 - raised, 3.0)
	_face.position = down.lerp(up, eased)
	_face.rotation = deg_to_rad(lerpf(14.0, -6.0, eased))
	_face.pivot_offset = Vector2(SIZE, SIZE) * 0.5
	_face.visible = raised > 0.0


func _draw_face() -> void:
	var centre := Vector2(SIZE, SIZE) * 0.5
	var radius := SIZE * 0.5
	# The strap, the steel case, the yellowed dial.
	_face.draw_rect(Rect2(centre.x - radius * 0.42, -SIZE * 0.2, radius * 0.84, SIZE * 1.4), Color(0.16, 0.11, 0.08))
	_face.draw_circle(centre, radius, Color(0.32, 0.31, 0.29))
	_face.draw_circle(centre, radius * 0.88, Color(0.82, 0.77, 0.64))
	for hour in 12:
		var angle := TAU * hour / 12.0
		var outward := Vector2(sin(angle), -cos(angle))
		var inner := 0.7 if hour % 3 == 0 else 0.76
		_face.draw_line(centre + outward * radius * inner, centre + outward * radius * 0.82, Color(0.12, 0.1, 0.08), 3.0 if hour % 3 == 0 else 1.5)
	var gt := get_node_or_null("/root/GameTime")
	var hours := clock_hours(gt.cycle_progress if gt else 0.0)
	var minute_angle := TAU * fmod(hours, 1.0)
	var hour_angle := TAU * fmod(hours, 12.0) / 12.0
	_face.draw_line(centre, centre + Vector2(sin(hour_angle), -cos(hour_angle)) * radius * 0.45, Color(0.08, 0.07, 0.06), 5.0)
	_face.draw_line(centre, centre + Vector2(sin(minute_angle), -cos(minute_angle)) * radius * 0.7, Color(0.08, 0.07, 0.06), 3.0)
	_face.draw_circle(centre, 4.0, Color(0.08, 0.07, 0.06))


func _on_night_started(_night: int) -> void:
	var tm := get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("trigger") and not tm.is_learned("watch"):
		tm.trigger("watch")
