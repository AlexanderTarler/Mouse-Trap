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

const OFFICE_MESSAGE := "Welcome to the field, Lund. Heads up: the phone network doesn't reach the cabin. Use the terminal there for every report. And stay inside after dark."
## A second message, a moment later: where the key is (Day 1's first task).
const KEY_MESSAGE := "The key to the cabin should be under the bucket."
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
var _phone: Phone
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
	_phone.slide_in(view)
	await _wait(1.0)
	if _skipped: return
	# The office's message, from the drive in. Long enough to read: it's the
	# one place the story is spelled out.
	_phone.bubble(OFFICE_MESSAGE, false, "Svea Naturinstitut · 12:41")
	_sound(BEEP_SOUND, -12.0)
	await _wait(5.5)
	if _skipped: return
	_phone.bubble(KEY_MESSAGE, false, "Svea Naturinstitut · 12:42")
	_sound(BEEP_SOUND, -12.0)
	await _wait(3.0)
	if _skipped: return
	# Typing a reply.
	for i in PLAYER_MESSAGE.length():
		_phone.input_line.text = PLAYER_MESSAGE.substr(0, i + 1)
		if i % 3 == 0:
			_sound(KEY_SOUND, -22.0, randf_range(0.95, 1.1))
		await _wait(0.045)
		if _skipped: return
	await _wait(0.4)
	_phone.input_line.text = ""
	var sent := _phone.bubble(PLAYER_MESSAGE, true, "Sending…")
	await _wait(1.6)
	if _skipped: return
	# The bars search, and find nothing.
	for flick in 3:
		_phone.set_bars(1)
		await _wait(0.25)
		_phone.set_bars(0)
		await _wait(0.35)
	if _skipped: return
	sent.status.text = "Not delivered: no service"
	sent.status.add_theme_color_override("font_color", Color(0.85, 0.2, 0.2))
	_sound(ERROR_SOUND, -10.0)
	await _wait(2.4)
	if _skipped: return
	_phone.slide_out(get_viewport().get_visible_rect().size)
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
	_skip_hint.add_theme_font_size_override("font_size", 16)
	_skip_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_skip_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_hint.offset_left = -140
	_skip_hint.offset_top = -40
	_skip_hint.offset_right = -20
	_skip_hint.offset_bottom = -14
	add_child(_skip_hint)
	_phone = Phone.new()
	add_child(_phone)
	_phone.build("Svea Naturinstitut · Field office", "15:02")


func _card_label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	GameFonts.use_title(label)
	label.modulate.a = 0.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
