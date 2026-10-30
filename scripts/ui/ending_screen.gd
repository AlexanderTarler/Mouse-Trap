extends Control
class_name EndingScreen

## EndingScreen — Overlay displayed when the game ends.
##
## Shows the ending title, subtitle, and two buttons:
##   - Retry / Play Again: back to the last checkpoint (the scene reloads)
##   - Main Menu: Returns to the main menu
##
## The screen is designed to overlay on top of the game world (semi-transparent
## black background) so the player can see the final game state behind it.
##
## IMPORTANT: This node's process_mode must be set to PROCESS_MODE_ALWAYS so
## it continues to function while the game tree is paused.

signal retry_pressed
signal main_menu_pressed

## Path to the main game scene for retry.
const GAME_SCENE_PATH: String = "res://scenes/cottage_horror.tscn"

## Path to the main menu scene.
const MAIN_MENU_PATH: String = "res://scenes/ui/main_menu.tscn"

## Title label reference.
@onready var title_label: Label = $VBoxContainer/TitleLabel

## Subtitle label reference.
@onready var subtitle_label: Label = $VBoxContainer/SubtitleLabel

## Retry button reference.
@onready var retry_button: Button = $VBoxContainer/RetryButton

## Main menu button reference.
@onready var main_menu_button: Button = $VBoxContainer/MainMenuButton


func _ready() -> void:
	# Ensure this screen processes even when the game is paused
	process_mode = PROCESS_MODE_ALWAYS
	
	# Connect button signals
	retry_button.pressed.connect(_on_retry_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	
	print("[EndingScreen] Ready.")


## The endings, by name, in the game's own words; the escapes open with an
## epilogue on the player's phone (the one from the opening): days later
## for "It Follows", on the road at dawn for "Dawn". Any key skips it.
const ENDINGS := {
	0: ["The Forest Keeps You", "No one came looking for days.\nBy then the cabin was empty again."],
	1: ["It Follows", "You got away from the cabin. It came with you."],
	2: ["Dawn", "The willow is ash, and the woods are quiet. You're going home."],
}

var _epilogue_skipped := false
var _in_epilogue := false


## Configures the ending screen UI based on which ending was triggered.
## Called by EndgameManager when the ending sequence begins.
func setup_ending(ending_type: int) -> void:
	# The game is over: Continue no longer offers its last night (a game
	# started from the menu; the tests keep whatever save there is).
	var checkpoint := get_node_or_null("/root/Checkpoint")
	if checkpoint and checkpoint.get("save_to_disk"):
		SaveGame.delete()
	var em = get_node_or_null("/root/EndgameManager")
	var ending_name: String = "Unknown"
	if em and em.has_method("get_ending_name"):
		ending_name = em.get_ending_name(ending_type)

	var words: Array = ENDINGS.get(ending_type, ["Game Over", ""])
	title_label.text = words[0]
	subtitle_label.text = words[1]
	GameFonts.use_title(title_label)
	title_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))

	# The escapes play again from the last checkpoint, and say which ending this was (so the
	# player knows there is another one).
	if ending_type == 1 or ending_type == 2:
		retry_button.text = "Play Again"
		var caption := Label.new()
		caption.name = "EndingCountLabel"
		caption.text = "Ending %d of 2" % ending_type
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.modulate = Color(1, 1, 1, 0.6)
		$VBoxContainer.add_child(caption)
		$VBoxContainer.move_child(caption, title_label.get_index())
		if ending_type == 1:
			var hint := Label.new()
			hint.name = "AnotherWayLabel"
			hint.text = "There is another way out."
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.modulate = Color(1, 1, 1, 0.45)
			hint.add_theme_font_size_override("font_size", 16)
			$VBoxContainer.add_child(hint)
			$VBoxContainer.move_child(hint, subtitle_label.get_index() + 1)
		_play_epilogue(ending_type)

	print("[EndingScreen] Displaying ending: ", ending_name)


func _input(event: InputEvent) -> void:
	if _in_epilogue and event.is_pressed() and not event.is_echo() \
			and (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton):
		_epilogue_skipped = true
		get_viewport().set_input_as_handled()


## The phone first, then the title, words and buttons fade in.
func _play_epilogue(ending_type: int) -> void:
	var box: Control = $VBoxContainer
	box.modulate.a = 0.0
	box.visible = true
	_in_epilogue = true
	var phone := Phone.new()
	add_child(phone)
	var view := get_viewport().get_visible_rect().size
	if ending_type == 1:
		await _it_follows(phone, view)
	else:
		await _dawn(phone, view)
	_in_epilogue = false
	var out := create_tween()
	out.tween_property(phone, "modulate:a", 0.0, 0.8)
	out.tween_callback(phone.queue_free)
	await _wait(0.6)
	create_tween().tween_property(box, "modulate:a", 1.0, 1.2)


## Days later, back in town. The office asks where the player is... and
## something answers from the player's phone, at three in the morning.
func _it_follows(phone: Phone, view: Vector2) -> void:
	phone.build("Svea Naturinstitut · Field office", "03:12", "")
	phone.set_bars(4)
	phone.position = Vector2((view.x - Phone.SIZE.x) * 0.5, (view.y - Phone.SIZE.y) * 0.5)
	phone.modulate.a = 0.0
	phone.visible = true
	create_tween().tween_property(phone, "modulate:a", 1.0, 1.0)
	await _wait(1.4)
	phone.bubble("Lund, the van was found on the forest road this morning. Where are you?", false, "Thursday 08:12")
	await _wait(3.2)
	phone.bubble("Please call the office.", false, "Friday 17:30")
	await _wait(2.6)
	var line := "it followed me home"
	for i in line.length():
		phone.input_line.text = line.substr(0, i + 1)
		await _wait(0.12)
	await _wait(0.5)
	phone.input_line.text = ""
	phone.bubble(line, true, "Delivered · 03:12")
	await _wait(3.0)


## On the road out at dawn: the signal comes back, the message from the
## first day finally goes, and the player reports in.
func _dawn(phone: Phone, view: Vector2) -> void:
	phone.build("Svea Naturinstitut · Field office", "06:48")
	phone.position = Vector2((view.x - Phone.SIZE.x) * 0.5, (view.y - Phone.SIZE.y) * 0.5)
	phone.modulate.a = 0.0
	phone.visible = true
	create_tween().tween_property(phone, "modulate:a", 1.0, 1.0)
	var first := phone.bubble("Arrived at the cabin. Will report in tonight.", true, "Not delivered: no service")
	first.status.add_theme_color_override("font_color", Color(0.85, 0.2, 0.2))
	await _wait(2.2)
	for bars in range(1, 5):
		phone.set_bars(bars)
		await _wait(0.35)
	phone.service.text = ""
	first.status.text = "Delivered"
	first.status.remove_theme_color_override("font_color")
	await _wait(1.6)
	var line := "Leaving the site. The nests are empty. Stenberg was right."
	for i in line.length():
		phone.input_line.text = line.substr(0, i + 1)
		await _wait(0.04)
	await _wait(0.4)
	phone.input_line.text = ""
	phone.bubble(line, true, "Delivered")
	await _wait(2.0)
	phone.bubble("Lund? Thank God. Come straight to the office.", false, "Svea Naturinstitut · 06:51")
	await _wait(3.2)


## Waits `seconds` (also while the game is paused), or not at all once the
## epilogue is skipped.
func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not (_in_epilogue and _epilogue_skipped):
		await get_tree().process_frame
		left -= get_process_delta_time()


## Called when the Retry button is pressed.
## Reloads the game scene, put back to the last checkpoint (the start of
## this day or night).
func _on_retry_pressed() -> void:
	print("[EndingScreen] Retry pressed. Reloading game scene.")
	retry_pressed.emit()

	# Reset the EndgameManager so endings can trigger again
	var em = get_node_or_null("/root/EndgameManager")
	if em and em.has_method("reset"):
		em.reset()
	# Back to the last checkpoint (the start of this day or night): the
	# scene reloads fresh and NightManager restores the snapshot into it.
	var nm = get_node_or_null("/root/NightManager")
	if nm and nm.has_method("reload_from_checkpoint"):
		nm.reload_from_checkpoint()
	
	# Unpause and reload
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var err = get_tree().change_scene_to_file(GAME_SCENE_PATH)
	if err != OK:
		printerr("[EndingScreen] ERROR: Failed to load scene! Error code: ", err)


## Called when the Main Menu button is pressed.
## Returns to the main menu.
func _on_main_menu_pressed() -> void:
	print("[EndingScreen] Main Menu pressed. Returning to main menu.")
	main_menu_pressed.emit()
	
	# Reset the EndgameManager so endings can trigger again
	var em = get_node_or_null("/root/EndgameManager")
	if em and em.has_method("reset"):
		em.reset()
	
	# Unpause and load main menu
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_PATH)
