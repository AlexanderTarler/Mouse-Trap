extends CanvasLayer

## Dedicated Note Reader UI.
## Displays note content with a paper-like background and dark overlay.
## Opened by the inventory when the player "uses" a note item.

signal note_closed

@onready var overlay: ColorRect = $Overlay
@onready var note_panel: Panel = $NotePanel
@onready var note_title: Label = $NotePanel/MarginContainer/VBoxContainer/TitleLabel
@onready var note_text: RichTextLabel = $NotePanel/MarginContainer/VBoxContainer/NoteText
@onready var close_button: Button = $NotePanel/MarginContainer/VBoxContainer/CloseButton

var _is_open: bool = false


func _ready() -> void:
	visible = false
	close_button.pressed.connect(_close_note)


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	
	# Close on left mouse click anywhere
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_close_note()
		get_viewport().set_input_as_handled()
		return
	
	# ─── KEYBOARD CLOSE: ESCAPE or E ────────────────────────────
	# Escape closes the note AND prevents the pause menu from opening
	# by consuming the event. E just closes the note.
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE, KEY_E:
				_close_note()
				get_viewport().set_input_as_handled()
				return


## Opens the note reader and displays the given content.
func display_note(content: String, title: String = "Note") -> void:
	note_text.text = content
	note_title.text = title
	_is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_note() -> void:
	_is_open = false
	visible = false
	note_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_closed.emit()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Ensure the game is unpaused if it was paused for reading
	if get_tree().paused:
		get_tree().paused = false
