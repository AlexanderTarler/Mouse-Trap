class_name PanicThoughts
extends CanvasLayer
## The player character panicking (the Night 2.2 chase, NightTwoStory):
## "Oh fuck!", "fuck!" popping up all over the screen in the thoughts' warm
## typewriter, each one quick and shaky, never over the middle (where
## they're running), faster the closer the Entity is. A gasp when it
## starts, then fast breathing (fading out once it's over).
##
##   panic.active = true; panic.distance = 12.0

const LINES := ["Oh fuck!", "fuck!", "Fuck!", "FUCK!", "fuck fuck fuck", "Oh fuck oh fuck", "oh fuck!"]
const MAX_AT_ONCE := 4
## Seconds between them with the Entity this close (NEAR m) or far (FAR m).
const INTERVAL_NEAR := 0.45
const INTERVAL_FAR := 1.4
const NEAR := 6.0
const FAR := 30.0
## The middle of the screen stays clear (half-width and half-height, as
## fractions of the screen).
const CLEAR_X := 0.2
const CLEAR_Y := 0.22
const BREATH_STREAM := preload("res://assets/audio/player/Breathing_fast.wav")
const GASP_STREAM := preload("res://assets/audio/player/Gasp.wav")
const BREATH_DB := -4.0
## Seconds for the breathing to come in, and to calm down.
const BREATH_IN := 0.6
const BREATH_OUT := 2.5

var active := false
## How far the Entity is (m).
var distance := 20.0
var _left := 0.2
var _shown: Array = []   ## Label
var breath: AudioStreamPlayer
var gasp: AudioStreamPlayer
## 0 = calm, 1 = panting.
var breath_level := 0.0
var _was_active := false


func _ready() -> void:
	layer = 149
	breath = _player("Breath", BREATH_STREAM)
	gasp = _player("Gasp", GASP_STREAM)


func _player(player_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	player.bus = &"SFX"
	add_child(player)
	return player


func _process(delta: float) -> void:
	_shown = _shown.filter(func(label) -> bool: return is_instance_valid(label))
	_update_breath(delta)
	if not active:
		return
	_left -= delta
	if _left > 0.0:
		return
	var far := clampf(inverse_lerp(NEAR, FAR, distance), 0.0, 1.0)
	_left = lerpf(INTERVAL_NEAR, INTERVAL_FAR, far) * randf_range(0.7, 1.3)
	if _shown.size() < MAX_AT_ONCE:
		pop()


## One of them, now (`text`, or any of LINES).
func pop(text: String = "") -> Label:
	var screen := get_viewport().get_visible_rect().size
	var monologue := get_node("/root/Monologue")
	var label := Label.new()
	label.text = text if text != "" else LINES.pick_random()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", monologue._get_font())
	label.add_theme_font_size_override("font_size", randi_range(30, 52))
	label.add_theme_color_override("font_color", monologue.COLOR)
	label.add_theme_color_override("font_outline_color", monologue.OUTLINE)
	label.add_theme_constant_override("outline_size", 8)
	add_child(label)
	label.reset_size()
	var spot := _spot(screen, label.size)
	label.position = spot
	label.pivot_offset = label.size * 0.5
	label.rotation = deg_to_rad(randf_range(-9.0, 9.0))
	label.modulate.a = 0.0
	label.scale = Vector2.ONE * 1.35
	var tween := label.create_tween()
	tween.set_parallel()
	tween.tween_property(label, "modulate:a", 1.0, 0.08)
	tween.tween_property(label, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# A shake while it's there.
	for i in 4:
		var jolt := Vector2(randf_range(-5.0, 5.0), randf_range(-4.0, 4.0))
		tween.chain().tween_property(label, "position", spot + jolt, 0.06)
	tween.chain().tween_property(label, "position", spot, 0.06)
	tween.chain().tween_interval(randf_range(0.15, 0.4))
	tween.chain().tween_property(label, "modulate:a", 0.0, 0.7)
	tween.chain().tween_callback(label.queue_free)
	_shown.append(label)
	return label


func _update_breath(delta: float) -> void:
	if active and not _was_active:
		gasp.play()
	_was_active = active
	breath_level = move_toward(breath_level, 1.0 if active else 0.0, delta / (BREATH_IN if active else BREATH_OUT))
	breath.volume_db = linear_to_db(maxf(breath_level, 0.0001)) + BREATH_DB
	if breath_level > 0.0 and not breath.playing:
		breath.play()
	elif breath_level <= 0.0 and breath.playing:
		breath.stop()


## All gone at once (inside, caught).
func clear() -> void:
	active = false
	for label in _shown:
		if is_instance_valid(label):
			label.queue_free()
	_shown.clear()


func count() -> int:
	return _shown.filter(func(label) -> bool: return is_instance_valid(label)).size()


## Somewhere on screen, clear of the middle.
func _spot(screen: Vector2, box: Vector2) -> Vector2:
	var room := (screen - box).max(Vector2.ZERO)
	for i in 16:
		var at := Vector2(randf_range(0.05, 0.95) * screen.x, randf_range(0.08, 0.9) * screen.y) - box * 0.5
		at = at.clamp(Vector2.ZERO, room)
		var off := (at + box * 0.5) / screen - Vector2(0.5, 0.5)
		if absf(off.x) > CLEAR_X or absf(off.y) > CLEAR_Y:
			return at
	return Vector2(screen.x * 0.06, screen.y * 0.12)
