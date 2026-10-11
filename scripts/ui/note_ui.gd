extends CanvasLayer

## Dedicated Note Reader UI.
## Displays note content with a paper-like background and dark overlay.
## Opened by the inventory when the player "uses" a note item.
##
## TASK 2.2 — NOTE PAGINATION:
## Long notes are split into pages of CHARS_PER_PAGE characters (word-wrap
## aware). The E key advances to the next page (or closes on the last page).
## The Q key goes back a page. A "Page X/Y" indicator is shown in the title.

signal note_closed

@onready var overlay: ColorRect = $Overlay
@onready var note_panel: Panel = $NotePanel
@onready var note_title: Label = $NotePanel/MarginContainer/VBoxContainer/TitleLabel
@onready var note_text: RichTextLabel = $NotePanel/MarginContainer/VBoxContainer/NoteText
@onready var close_button: Button = $NotePanel/MarginContainer/VBoxContainer/CloseButton

var _is_open: bool = false

# ─── TASK 2.2: PAGINATION STATE ────────────────────────────────────────
## Pages of note content. Populated by display_note() when the note is
## longer than one page. Each entry is rendered in note_text.
var _pages: Array[String] = []

## Current page index (0-based).
var _current_page: int = 0

## Maximum characters that fit on one note page before splitting.
## Matches notebook_ui.gd's CHARS_PER_PAGE so pagination feels consistent.
const CHARS_PER_PAGE: int = 1000


## Found by its group (not by a path in the level).
func _enter_tree() -> void:
	add_to_group("note_ui")


func _ready() -> void:
	visible = false
	close_button.pressed.connect(_close_note)


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	
	# Close on left mouse click anywhere
	# (A click no longer closes it: a stray one threw the note away. Esc, E
	# on the last page, or the close button.)
	
	# ─── KEYBOARD CLOSE / PAGE NAVIGATION ─────────────────────────
	# Escape closes the note AND prevents the pause menu from opening
	# by consuming the event.
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				_close_note()
				get_viewport().set_input_as_handled()
				return
			KEY_E:
				# ─── TASK 2.2: E = NEXT PAGE (or close on last) ─────
				# If there are multiple pages and we're not on the last
				# one, advance instead of closing.
				if _current_page < _pages.size() - 1:
					_current_page += 1
					_render_current_page()
					get_viewport().set_input_as_handled()
					return
				# On the last page (or single-page note), E closes.
				_close_note()
				get_viewport().set_input_as_handled()
				return
			KEY_Q:
				# ─── TASK 2.2: Q = PREV PAGE ──────────────────────
				# Only meaningful when on page 2+.
				if _current_page > 0:
					_current_page -= 1
					_render_current_page()
					get_viewport().set_input_as_handled()
					return
				# On the first page, Q closes (mirrors notebook behavior).
				if _pages.size() > 1:
					_close_note()
					get_viewport().set_input_as_handled()
					return


## Opens the note reader and displays the given content.
## Splits long notes into multiple pages (TASK 2.2).
func display_note(content: String, title: String = "Note") -> void:
	_pages = _split_into_pages(content)
	_current_page = 0
	_render_current_page()
	note_title.text = title
	_is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Renders the current page's text into the note_text RichTextLabel.
## If the note spans multiple pages, appends a "Page X/Y" footer.
func _render_current_page() -> void:
	if _pages.is_empty():
		note_text.text = ""
		return
	note_text.text = _pages[_current_page]
	if _pages.size() > 1:
		# Append a subtle page indicator footer so the player knows
		# there are more pages and how to advance.
		note_text.text += "\n\n[center][color=gray]— Page %d/%d —  [E] Next · [Q] Prev · [Esc] Close[/color][/center]" % [_current_page + 1, _pages.size()]
	else:
		note_text.text += "\n\n[center][color=gray][E] or [Esc] Close[/color][/center]"


## Splits a string into an array of CHARS_PER_PAGE-sized chunks,
## with word-wrap awareness. Mirrors notebook_ui.gd's _split_into_pages().
func _split_into_pages(text: String) -> Array[String]:
	var result: Array[String] = []
	var remaining = text
	
	while remaining.length() > 0:
		if remaining.length() <= CHARS_PER_PAGE:
			result.append(remaining)
			break
		else:
			var split_at = CHARS_PER_PAGE
			var nl_pos = remaining.rfind("\n", CHARS_PER_PAGE)
			var half_page = int(CHARS_PER_PAGE) / 2.0
			if nl_pos > half_page:
				split_at = nl_pos + 1
			else:
				var sp_pos = remaining.rfind(" ", CHARS_PER_PAGE)
				if sp_pos > half_page:
					split_at = sp_pos + 1
			result.append(remaining.substr(0, split_at))
			remaining = remaining.substr(split_at)
	
	return result


func _close_note() -> void:
	_is_open = false
	visible = false
	note_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pages.clear()
	_current_page = 0
	note_closed.emit()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Ensure the game is unpaused if it was paused for reading
	if get_tree().paused:
		get_tree().paused = false