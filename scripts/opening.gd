class_name Opening
extends CanvasLayer
## The opening of a new game: on black, the van's engine dies and a door
## slams over a title card; the picture comes up at the van, and the
## player's phone comes up with it. A message from the Institute (received
## on the drive in) says the phone network doesn't reach the cabin and the
## terminal is the only line out: they knew. The player's own "Arrived" text
## fails: no service. The phone goes away, with a thought.
##
## The player can't move meanwhile. [Space] skips. NightManager plays it at
## the start of the first day (not in dev mode, nor in headless test runs).

signal finished

const ECHOES := "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/"
const ENGINE_SOUND := ECHOES + "SFX/Machines/machine_3_loop.ogg"
const DOOR_SOUND := ECHOES + "SFX/Doors & Drawers/heavy_door_open-close_1.ogg"
const BEEP_SOUND := ECHOES + "SFX/Electronics/analog_computer_beep_2.ogg"
const ERROR_SOUND := ECHOES + "SFX/Electronics/analog_computer_beep_5.ogg"
const KEY_SOUND := ECHOES + "SFX/Electronics/analog_computer_press_key_1.ogg"

const PHONE_SIZE := Vector2(380, 640)
const OFFICE_MESSAGE := "Welcome to the field, Lund. Heads up: the phone network doesn't reach the cabin. Use the terminal there for every report. And stay inside after dark."
const PLAYER_MESSAGE := "Arrived at the cabin. Will report in tonight."
const THOUGHT := "No signal. They did say it was remote."

var playing := false
var _player: Node = null
var _hud: Node = null
var _hud_was_visible := true
var _black: ColorRect
var _title: Label
var _subtitle: Label
var _skip_hint: Label
var _phone: Panel
var _bars: Array[ColorRect] = []
var _service: Label
var _thread: VBoxContainer
var _input_line: Label
var _engine: AudioStreamPlayer
var _skipped := false
var _done := false


func _ready() -> void:
	layer = 160
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("opening")
	_build()


func play() -> void:
	playing = true
	_lock_player(true)
	_engine = _sound(ENGINE_SOUND, -14.0, 0.8, true)
	await _wait(0.8)
	await _card(_title, "SVEA NATURINSTITUT", 2.2)
	if _skipped: return
	await _card(_subtitle, "Field survey, phase 2\nMuscardinus avellanarius", 2.6)
	if _skipped: return
	# The engine winds down and dies; a door.
	if _engine:
		var wind := create_tween().set_parallel()
		wind.tween_property(_engine, "pitch_scale", 0.45, 1.6)
		wind.tween_property(_engine, "volume_db", -40.0, 1.6)
	await _card(_title, "Day 1", 1.8)
	if _skipped: return
	if _engine:
		_engine.stop()
	_sound(DOOR_SOUND, -6.0, 1.25)
	await _wait(1.0)
	if _skipped: return
	# Up comes the forest, and the phone.
	create_tween().tween_property(_black, "color:a", 0.0, 2.0)
	await _wait(1.2)
	if _skipped: return
	await _phone_scene()
	_finish()


func _phone_scene() -> void:
	var view := get_viewport().get_visible_rect().size
	_phone.position.x = view.x * 0.5 + 140.0
	var shown_y := view.y - PHONE_SIZE.y + 70.0
	_phone.position.y = view.y + 20.0
	_phone.visible = true
	var up := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	up.tween_property(_phone, "position:y", shown_y, 0.6)
	await _wait(1.0)
	if _skipped: return
	# The office's message, from the drive in.
	_bubble(OFFICE_MESSAGE, false, "Svea Naturinstitut · 12:41")
	_sound(BEEP_SOUND, -12.0)
	await _wait(3.4)
	if _skipped: return
	# Typing a reply.
	for i in PLAYER_MESSAGE.length():
		_input_line.text = PLAYER_MESSAGE.substr(0, i + 1)
		if i % 3 == 0:
			_sound(KEY_SOUND, -22.0, randf_range(0.95, 1.1))
		await _wait(0.045)
		if _skipped: return
	await _wait(0.4)
	_input_line.text = ""
	var sent := _bubble(PLAYER_MESSAGE, true, "Sending…")
	await _wait(1.6)
	if _skipped: return
	# The bars search, and find nothing.
	for flick in 3:
		_set_bars(1)
		await _wait(0.25)
		_set_bars(0)
		await _wait(0.35)
	if _skipped: return
	sent.status.text = "Not delivered: no service"
	sent.status.add_theme_color_override("font_color", Color(0.85, 0.2, 0.2))
	_sound(ERROR_SOUND, -10.0)
	await _wait(2.4)
	if _skipped: return
	var down := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	down.tween_property(_phone, "position:y", get_viewport().get_visible_rect().size.y + 20.0, 0.5)
	await _wait(0.6)


func _finish() -> void:
	if _done:
		return
	_done = true
	playing = false
	if _engine:
		_engine.stop()
	_lock_player(false)
	var monologue := get_node_or_null("/root/Monologue")
	if monologue:
		monologue.think(THOUGHT, null, 4.0, "no_signal")
	finished.emit()
	if _black.color.a > 0.0:
		var fade := create_tween()
		fade.tween_property(_black, "color:a", 0.0, 0.6)
		fade.tween_callback(queue_free)
	else:
		queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if playing and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_skipped = true
		get_viewport().set_input_as_handled()
		_finish()


# ─── Pieces ──────────────────────────────────────────────────────────────

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


## A line of the title card: fades in, holds, fades out.
func _card(label: Label, text: String, hold: float) -> void:
	label.text = text
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.7)
	tween.tween_interval(hold)
	tween.tween_property(label, "modulate:a", 0.0, 0.7)
	await tween.finished


func _sound(path: String, volume_db: float, pitch: float = 1.0, loop: bool = false) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if loop and stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		(stream as AudioStreamOggVorbis).loop = true
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.bus = &"SFX"
	add_child(player)
	player.play()
	if not loop:
		player.finished.connect(player.queue_free)
	return player


func _lock_player(locked: bool) -> void:
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.set_process_input(not locked)
		_player.set_physics_process(not locked)
		_player.set_process_unhandled_input(not locked)
	if not _hud:
		_hud = get_tree().get_first_node_in_group("hud")
	if _hud and "visible" in _hud:
		if locked:
			_hud_was_visible = _hud.visible
			_hud.visible = false
		else:
			_hud.visible = _hud_was_visible


func _build() -> void:
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_title = _card_label(40, Color(0.92, 0.9, 0.85))
	_subtitle = _card_label(22, Color(0.75, 0.73, 0.68))
	_skip_hint = Label.new()
	_skip_hint.text = "[Space] Skip"
	_skip_hint.add_theme_font_size_override("font_size", 14)
	_skip_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	_skip_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_hint.offset_left = -140
	_skip_hint.offset_top = -40
	_skip_hint.offset_right = -20
	_skip_hint.offset_bottom = -14
	add_child(_skip_hint)
	_build_phone()


func _card_label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.modulate.a = 0.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _flat(color: Color, radius: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box


## The phone: a dark body, a screen with a status bar (time, signal bars,
## "No service"), the message thread and the text field.
func _build_phone() -> void:
	_phone = Panel.new()
	_phone.visible = false
	_phone.size = PHONE_SIZE
	var body := _flat(Color(0.07, 0.07, 0.08), 34)
	body.border_color = Color(0.2, 0.2, 0.22)
	body.set_border_width_all(3)
	_phone.add_theme_stylebox_override("panel", body)
	add_child(_phone)
	var screen := Panel.new()
	screen.add_theme_stylebox_override("panel", _flat(Color(0.93, 0.93, 0.95), 22))
	screen.position = Vector2(16, 18)
	screen.size = PHONE_SIZE - Vector2(32, 36)
	_phone.add_child(screen)
	# Status bar.
	var time := Label.new()
	time.text = "15:02"
	time.position = Vector2(22, 10)
	time.add_theme_font_size_override("font_size", 15)
	time.add_theme_color_override("font_color", Color(0.1, 0.1, 0.12))
	screen.add_child(time)
	_service = Label.new()
	_service.text = "No service"
	_service.position = Vector2(screen.size.x - 168, 10)
	_service.add_theme_font_size_override("font_size", 14)
	_service.add_theme_color_override("font_color", Color(0.35, 0.35, 0.38))
	screen.add_child(_service)
	for i in 4:
		var bar := ColorRect.new()
		var h := 5.0 + i * 3.5
		bar.size = Vector2(4, h)
		bar.position = Vector2(screen.size.x - 66 + i * 7, 27 - h)
		screen.add_child(bar)
		_bars.append(bar)
	_set_bars(0)
	# The conversation header.
	var header := Label.new()
	header.text = "Svea Naturinstitut · Field office"
	header.position = Vector2(0, 42)
	header.size = Vector2(screen.size.x, 24)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.15, 0.15, 0.18))
	screen.add_child(header)
	var rule := ColorRect.new()
	rule.color = Color(0.8, 0.8, 0.83)
	rule.position = Vector2(0, 72)
	rule.size = Vector2(screen.size.x, 1)
	screen.add_child(rule)
	_thread = VBoxContainer.new()
	_thread.position = Vector2(14, 86)
	_thread.size = Vector2(screen.size.x - 28, screen.size.y - 160)
	_thread.add_theme_constant_override("separation", 10)
	screen.add_child(_thread)
	# The text field.
	var field := Panel.new()
	field.add_theme_stylebox_override("panel", _flat(Color(1, 1, 1), 16))
	field.position = Vector2(12, screen.size.y - 56)
	field.size = Vector2(screen.size.x - 24, 40)
	screen.add_child(field)
	_input_line = Label.new()
	_input_line.position = Vector2(14, 9)
	_input_line.size = Vector2(field.size.x - 28, 22)
	_input_line.clip_text = true
	_input_line.add_theme_font_size_override("font_size", 14)
	_input_line.add_theme_color_override("font_color", Color(0.1, 0.1, 0.12))
	field.add_child(_input_line)


func _set_bars(lit: int) -> void:
	for i in _bars.size():
		_bars[i].color = Color(0.15, 0.15, 0.18) if i < lit else Color(0.75, 0.75, 0.78)


## A message bubble: grey on the left (received) or blue on the right (sent),
## with a line under it. Returns {"status": Label}.
func _bubble(text: String, mine: bool, note: String) -> Dictionary:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var holder := HBoxContainer.new()
	holder.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	var bubble := PanelContainer.new()
	var style := _flat(Color(0.2, 0.45, 0.95) if mine else Color(0.82, 0.82, 0.86), 14)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(240, 0)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE if mine else Color(0.1, 0.1, 0.12))
	bubble.add_child(label)
	holder.add_child(bubble)
	row.add_child(holder)
	var status := Label.new()
	status.text = note
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mine else HORIZONTAL_ALIGNMENT_LEFT
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5))
	row.add_child(status)
	_thread.add_child(row)
	row.modulate.a = 0.0
	create_tween().tween_property(row, "modulate:a", 1.0, 0.3)
	return {"status": status}
