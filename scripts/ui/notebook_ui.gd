extends Control
class_name NotebookUI

## Two-page open book notebook.
## Spread 0: Index (Left) + To-Do (Right)
## Spread 1: Content (Left + Right)
##
## REAL-BOOK PAGINATION:
##   Content flows sequentially across all pages in a single unified array.
##   Page 0 → Left side of Spread 1, Page 1 → Right side of Spread 1,
##   Page 2 → Left of next spread, Page 3 → Right, etc.
##   A "page turn" advances by 2 pages (one full spread).
##
## CHAPTER STRUCTURE:
##   When the notebook is first populated, _all_pages contains:
##     [0]: Chapter 2 — Personnel Credentials (login: LUND / PASSKEY1)
##   The Index (Spread 0 Left) and To-Do (Spread 0 Right) are static UI containers,
##   NOT part of _all_pages.
##
##   When documentation is added (add_documentation), it is inserted AFTER
##   the credentials page but BEFORE any existing notes. This guarantees:
##     Chapter 3: Nest Data always precedes Chapter 4: Picked-up Notes.
##
##   When notes are added (add_note), they always APPEND to _all_pages,
##   ensuring they come after all documentation.

# ============================================================
# Spread state
# ============================================================

var _is_open: bool = false
var current_spread: int = 0
const MAX_SPREAD: int = 1

# ─── UNIFIED PAGE STATE ────────────────────────────────────
## All content pages in sequential order. Index 0 = first page (left),
## index 1 = second page (right), index 2 = third page (left), etc.
## Layout: [0] = Credentials, [1..N] = Nest Data, [...M] = Notes
var _all_pages: Array[String] = []

## Current page index (points to the left page of the current spread).
## Always even. Right page is _current_page + 1.
var _current_page: int = 0

## Maximum characters that fit on one physical page.
const CHARS_PER_PAGE: int = 1000

## Index into _all_pages where Nest Data (Chapter 3) begins.
## Always 1 (credentials occupy page 0, nest data starts on page 1).
## Updated by add_documentation() when the first nest is added.
var _nest_data_start_page: int = 1

## Index into _all_pages where Notes (Chapter 4) begin.
## Updated by add_note() and add_documentation() as pages shift.
## Initially set to INF so empty checks work before any notes exist.
var _notes_start_page: int = 999999

# ============================================================
# Node references
# ============================================================

@onready var _index_container: Control = %IndexContainer
@onready var _doc_container: Control = %DocContainer
@onready var _todo_container: Control = %ToDoContainer
@onready var _notes_container: Control = %NotesContainer

@onready var _index_label: RichTextLabel = %IndexLabel
@onready var _todo_label: RichTextLabel = %ToDoLabel
@onready var _doc_label: RichTextLabel = %DocLabel
@onready var _notes_label: RichTextLabel = %NotesLabel
@onready var _day_label: Label = %DayLabel

@onready var _left_page: Panel = %LeftPage
@onready var _right_page: Panel = %RightPage
@onready var _left_margin: MarginContainer = %LeftMargin
@onready var _right_margin: MarginContainer = %RightMargin
@onready var _book_bg: Panel = %BookBackground

# ============================================================
# State
# ============================================================

var _current_day: int = 0
var _completed_objectives: Array[String] = []
var _current_objective: String = ""

# ============================================================
# Lifecycle
# ============================================================

func _ready() -> void:
	visible = false
	process_mode = PROCESS_MODE_ALWAYS
	
	# Apply ink color and book styling
	_apply_styles()
	
	# Initialize page content
	_initialize_pages()
	
	# Set initial spread
	_update_spread()
	
	# ─── CONNECT TO GAME MANAGERS ──────────────────────────────
	_connect_to_managers()


func _connect_to_managers() -> void:
	var rm = get_node_or_null("/root/RoutineManager")
	if rm:
		if rm.has_signal("routine_step_changed"):
			rm.routine_step_changed.connect(_on_routine_step_changed)
		rm._notebook_ui = self
		var current_obj: String = rm.get_current_objective() if rm.has_method("get_current_objective") else ""
		if not current_obj.is_empty():
			_on_routine_step_changed(0, current_obj)
		_call_deferred_todo_seed()
	else:
		call_deferred("_connect_to_managers")
		return
	
	var em = get_node_or_null("/root/EvidenceManager")
	if em:
		if em.has_signal("evidence_collected"):
			em.evidence_collected.connect(_on_evidence_collected)
	
	var dm = get_node_or_null("/root/DocumentationManager")
	if dm and dm.has_signal("documentation_added"):
		dm.documentation_added.connect(add_documentation)


func _on_routine_step_changed(_step: int, objective_text: String) -> void:
	if not objective_text.is_empty() and objective_text != _current_objective:
		if not _current_objective.is_empty():
			_completed_objectives.append(_current_objective)
		_current_objective = objective_text
	
	var bbcode := "[center][b]%s[/b][/center]\n\n" % _day_label.text
	for obj in _completed_objectives:
		bbcode += "[s]  [x] %s[/s]\n" % obj
	if not _current_objective.is_empty():
		bbcode += "\n[b]  [ ] %s[/b]" % _current_objective
	_todo_label.text = bbcode
	
	var nm = get_node_or_null("/root/NightManager")
	if nm and "current_night" in nm:
		var game_day = nm.current_night + 1
		if game_day != _current_day:
			_current_day = game_day
			_day_label.text = "DAY %d" % game_day


func _on_evidence_collected(evidence_id: String) -> void:
	add_note("[b]Evidence:[/b] %s" % evidence_id)


func _call_deferred_todo_seed() -> void:
	await get_tree().process_frame
	update_objectives(1, ["Drive to the research area."], "Go to the cabin.")


func _initialize_pages() -> void:
	# ─── STATIC INDEX (Spread 0 Left) ─────────────────────────
	# The Index is rebuilt dynamically each time content changes.
	# Initial version shows only the credentials chapter.
	_rebuild_index()
	
	_todo_label.text = "[center][b]TO-DO[/b][/center]\n\nLoading objectives..."

	# ─── UNIFIED PAGE ARRAY (Spread 1) ─────────────────────────
	# Every entry is one physical page.
	# Page 0 = left side of Spread 1, Page 1 = right side, Page 2 = left, etc.
	#
	# Chapter 2: Personnel Credentials (always page 0)
	_all_pages = []
	_all_pages.append("[center][b]PERSONNEL CREDENTIALS[/b][/center]\n\n[font_size=14][b]Svea Naturinstitut[/b][/font_size]\n[font_size=11][i]Ekologisk Fältundersökning[/i][/font_size]\n\n[font_size=12][b]Researcher:[/b] Arvid Lindqvist\n[b]ID:[/b] SNI-7742-AL\n[b]Clearance:[/b] Level 3 (Ecological)\n[b]Vehicle:[/b] Unit 12 — '92 Volvo 240\n[b]Assignment:[/b] Hazel Mouse (Muscardinus avellanarius) Population Survey — Phase 2\n\n[b]─── COMPUTER LOGIN ───[/b]\n[b]Login:[/b] LUND\n[b]Password:[/b] PASSKEY1\n\n[font_size=11][i]This notebook is the property of Svea Naturinstitut.\nUnauthorised access or reproduction is a violation of the Swedish Environmental Code (Miljöbalken, 1998:808).\n\nReport lost or damaged equipment to your supervising officer immediately.[/i][/font_size]")
	
	# Chapter 3: Nest Data — starts at page 1 (no nests yet documented)
	# Chapter 4: Notes — will be appended via add_note()
	
	_nest_data_start_page = 1
	_notes_start_page = 999999
	
	_current_page = 0


func _rebuild_index() -> void:
	# Determine Notes page number (1-based for display)
	var notes_page: int = _notes_start_page + 1  # Convert 0-based to 1-based
	if _notes_start_page >= 999999:
		notes_page = _all_pages.size() + 1  # Approximate: next available page
	
	var nest_page: int = _nest_data_start_page + 1  # 1-based
	
	_index_label.text = """[center][font_size=22][b]FIELD NOTEBOOK[/b][/font_size][/center]
[center][i]Svea Naturinstitut Ecological Survey[/i][/center]

[font_size=16][b]INDEX[/b][/font_size]

  [b]1.[/b]  To-do .................... [i]Current objectives[/i]

  [b]2.[/b]  Personnel Credentials ..... [i]Page 1[/i]

  [b]3.[/b]  Nest Data ................ [i]Page %d[/i]

  [b]4.[/b]  Field Notes .............. [i]Page %d[/i]

[center]---
Press [b][J][/b] to close[/center]""" % [nest_page, notes_page]


func _apply_styles() -> void:
	var ink = Color("#1a1a1a")
	_index_label.add_theme_color_override("font_color", ink)
	_index_label.add_theme_color_override("default_color", ink)
	_todo_label.add_theme_color_override("font_color", ink)
	_todo_label.add_theme_color_override("default_color", ink)
	_doc_label.add_theme_color_override("font_color", ink)
	_doc_label.add_theme_color_override("default_color", ink)
	_notes_label.add_theme_color_override("font_color", ink)
	_notes_label.add_theme_color_override("default_color", ink)

	var cover = StyleBoxFlat.new()
	cover.bg_color = Color("#2a2520")
	cover.shadow_size = 10
	cover.shadow_offset = Vector2(5, 5)
	cover.shadow_color = Color(0, 0, 0, 0.6)
	cover.corner_radius_top_left = 6
	cover.corner_radius_top_right = 6
	cover.corner_radius_bottom_left = 6
	cover.corner_radius_bottom_right = 6
	_book_bg.add_theme_stylebox_override("panel", cover)

	var left_paper = StyleBoxFlat.new()
	left_paper.bg_color = Color("#e8dcc7")
	left_paper.border_width_right = 1
	left_paper.border_color = Color("#b8a88a")
	left_paper.shadow_size = 4
	left_paper.shadow_offset = Vector2(2, 2)
	left_paper.shadow_color = Color(0, 0, 0, 0.15)
	_left_page.add_theme_stylebox_override("panel", left_paper)

	var right_paper = StyleBoxFlat.new()
	right_paper.bg_color = Color("#e8dcc7")
	right_paper.border_width_left = 1
	right_paper.border_color = Color("#b8a88a")
	right_paper.shadow_size = 4
	right_paper.shadow_offset = Vector2(-2, 2)
	right_paper.shadow_color = Color(0, 0, 0, 0.15)
	_right_page.add_theme_stylebox_override("panel", right_paper)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_notebook"):
		_is_open = !_is_open
		visible = _is_open
		if _is_open:
			current_spread = 0
			_current_page = 0
			_update_spread()
			var tm := get_node_or_null("/root/TutorialManager")
			if tm and tm.has_method("mark_learned"):
				tm.mark_learned("notebook")
		get_viewport().set_input_as_handled()
		return

	if not _is_open:
		return

	if event.is_action_pressed("notebook_next_page"):
		if current_spread == 1:
			# Advance by 2 pages (one spread)
			var max_page = max(0, _all_pages.size() - 1)
			if _current_page + 2 <= max_page:
				_current_page += 2
				_refresh_spread_1()
			else:
				# No more pages — wrap to Spread 0
				current_spread = 0
				_current_page = 0
				_update_spread()
		else:
			current_spread = mini(current_spread + 1, MAX_SPREAD)
			_current_page = 0
			_update_spread()
		get_viewport().set_input_as_handled()
		
	elif event.is_action_pressed("notebook_prev_page"):
		if current_spread == 1:
			if _current_page >= 2:
				_current_page -= 2
				_refresh_spread_1()
			else:
				current_spread = maxi(current_spread - 1, 0)
				_current_page = 0
				_update_spread()
		else:
			current_spread = maxi(current_spread - 1, 0)
			_current_page = 0
			_update_spread()
		get_viewport().set_input_as_handled()


# ============================================================
# Spread update
# ============================================================

func _update_spread() -> void:
	if _left_margin:
		_left_margin.visible = true
	if _right_margin:
		_right_margin.visible = true

	_index_container.visible = (current_spread == 0)
	_todo_container.visible = (current_spread == 0)
	_doc_container.visible = (current_spread == 1)
	_notes_container.visible = (current_spread == 1)

	if current_spread == 1:
		_refresh_spread_1()


## Shows the current spread: left page = _all_pages[_current_page],
## right page = _all_pages[_current_page + 1] (or blank if missing).
func _refresh_spread_1() -> void:
	var left_idx = _current_page
	var right_idx = _current_page + 1
	
	if left_idx < _all_pages.size():
		_doc_label.text = _all_pages[left_idx]
	else:
		_doc_label.text = ""
	
	if right_idx < _all_pages.size():
		_notes_label.text = _all_pages[right_idx]
	else:
		_notes_label.text = ""


# ============================================================
# Toggle (kept for external callers)
# ============================================================

func _toggle() -> void:
	_is_open = not _is_open
	if _is_open:
		var tm := get_node_or_null("/root/TutorialManager")
		if tm and tm.has_method("mark_learned"):
			tm.mark_learned("notebook")
	visible = _is_open
	if _is_open:
		current_spread = 0
		_current_page = 0
		_update_spread()


# ============================================================
# Objective integration
# ============================================================

func update_objectives(day: int, completed_objectives: Array[String], current_objective: String) -> void:
	if day != _current_day:
		_current_day = day
		_completed_objectives.clear()
		_current_objective = ""
		_day_label.text = "DAY %d" % day

	var bbcode := "[center][b]%s[/b][/center]\n\n" % _day_label.text
	for obj in completed_objectives:
		bbcode += "[s]  [x] " + obj + "[/s]\n"
	if not current_objective.is_empty():
		bbcode += "\n[b]  [ ] " + current_objective + "[/b]\n"
	_todo_label.text = bbcode


func set_documentation(text: String) -> void:
	# Deprecated single-doc mode — clear and populate
	_all_pages = [text]
	_current_page = 0
	_nest_data_start_page = 0
	_notes_start_page = 999999
	if current_spread == 1:
		_refresh_spread_1()


## Appends a documented nest entry. The lore text flows into the
## unified page array, inserted AFTER credentials but BEFORE any notes.
func add_documentation(nest_id: String) -> void:
	if NEST_LORE.has(nest_id):
		var lore_text = NEST_LORE[nest_id]
		_insert_text_before_notes(lore_text)
		_rebuild_index()
		_update_spread()
	else:
		push_error("Notebook: Could not find nest data for ID: " + nest_id)


## Appends a note entry. Always placed at the end of _all_pages,
## after all documentation entries.
func add_note(text: String) -> void:
	if text.is_empty():
		return
	
	# Append to the end of _all_pages
	_append_text(text)
	
	# Update _notes_start_page if no notes existed before
	if _notes_start_page >= 999999:
		_notes_start_page = _all_pages.size() - 1
		# Walk backwards to find the actual start of notes (the first non-blank page
		# after documentation ends). _append_text adds a blank page separator.
		var probe = _notes_start_page
		while probe > 0 and (_all_pages[probe].is_empty() or _all_pages[probe] == ""):
			probe -= 1
		_notes_start_page = probe + 1
	
	_rebuild_index()
	_update_spread()


## Inserts text into _all_pages at the notes boundary — right BEFORE the
## first notes page. Documentation always comes before notes.
func _insert_text_before_notes(new_text: String) -> void:
	# Sanitize
	new_text = new_text.replace("\\n", "\n")
	new_text = new_text.trim_prefix("\"").trim_suffix("\"")
	new_text = new_text.trim_prefix("\"\"\"").trim_suffix("\"\"\"")
	new_text = new_text.strip_edges()
	
	# Split the text into page-sized chunks
	var chunks: Array[String] = _split_into_pages(new_text)
	if chunks.is_empty():
		return
	
	# If notes already exist, insert at _notes_start_page
	if _notes_start_page < _all_pages.size():
		# Add a blank separator page before the nest data chunk
		_all_pages.insert(_notes_start_page, "")
		_notes_start_page += 1
		# Insert each chunk before the notes
		for chunk in chunks:
			_all_pages.insert(_notes_start_page, chunk)
			_notes_start_page += 1
	else:
		# No notes exist yet — append normally
		for chunk in chunks:
			if _all_pages.is_empty() or _all_pages[-1] != "":
				_all_pages.append("")
			_all_pages[_all_pages.size() - 1] = chunk


## Appends text to the end of _all_pages, splitting across pages when
## text exceeds CHARS_PER_PAGE. Maintains sequential book-like flow.
func _append_text(new_text: String) -> void:
	# Sanitize any double-escaped strings or literal quotes coming from resources/AI file writes
	new_text = new_text.replace("\\n", "\n")
	new_text = new_text.trim_prefix("\"").trim_suffix("\"")
	new_text = new_text.trim_prefix("\"\"\"").trim_suffix("\"\"\"") # Catch triple quotes just in case
	new_text = new_text.strip_edges()
	
	# Force a brand new page for every new entry if the current last page isn't entirely blank
	if _all_pages.is_empty() or _all_pages[-1] != "":
		_all_pages.append("")
		
	var last_idx = _all_pages.size() - 1
	var page_text = _all_pages[last_idx]
	var space_left = CHARS_PER_PAGE - page_text.length()

	var current = new_text
	if space_left > 0:
		var chunk = current.substr(0, space_left)
		var remainder = current.substr(space_left)
		var nl_pos = chunk.rfind("\n")
		if nl_pos > 0 and nl_pos > space_left / 2:
			chunk = current.substr(0, nl_pos + 1)
			remainder = current.substr(nl_pos + 1)
		else:
			var sp_pos = chunk.rfind(" ")
			if sp_pos > 0 and sp_pos > space_left / 2:
				chunk = current.substr(0, sp_pos + 1)
				remainder = current.substr(sp_pos + 1)
		_all_pages[last_idx] = page_text + chunk
		current = remainder
	
	# Split remaining text into full pages of CHARS_PER_PAGE
	while current.length() > 0:
		if current.length() <= CHARS_PER_PAGE:
			_all_pages.append(current)
			break
		else:
			var split_at = CHARS_PER_PAGE
			var nl_pos = current.rfind("\n", CHARS_PER_PAGE)
			if nl_pos > CHARS_PER_PAGE / 2:
				split_at = nl_pos + 1
			else:
				var sp_pos = current.rfind(" ", CHARS_PER_PAGE)
				if sp_pos > CHARS_PER_PAGE / 2:
					split_at = sp_pos + 1
			_all_pages.append(current.substr(0, split_at))
			current = current.substr(split_at)


## Splits a string into an array of CHARS_PER_PAGE-sized chunks,
## with word-wrap awareness. Does NOT modify _all_pages.
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
			if nl_pos > CHARS_PER_PAGE / 2:
				split_at = nl_pos + 1
			else:
				var sp_pos = remaining.rfind(" ", CHARS_PER_PAGE)
				if sp_pos > CHARS_PER_PAGE / 2:
					split_at = sp_pos + 1
			result.append(remaining.substr(0, split_at))
			remaining = remaining.substr(split_at)
	
	return result


# ============================================================
# Nest lore entries
# ============================================================

const NEST_LORE: Dictionary = {
	"Nest Alpha": """[b]Subject: Nest Alpha[/b]
Species: Muscardinus avellanarius
Observation: The nest and the mice actively and impossibly reject light.
[b]Conclusion: Extreme Photophobia — the colony exhibits an extreme, hostile aversion to all light sources.[/b]""",

	"Nest Beta": """[b]Subject: Nest Beta[/b]
Species: Muscardinus avellanarius
Observation: They are acting like scouts. It feels like something else is watching me through them.
[b]Conclusion: Active Observation — the mice appear to be gathering intelligence for a larger entity.[/b]""",

	"Nest Gamma": """[b]Subject: Nest Gamma[/b]
Species: Muscardinus avellanarius
Observation: The colony is producing a low, rhythmic clicking that vibrates through the cabin's exterior wood. It is mimicking the acoustic properties of my footsteps.
[b]Conclusion: Acoustic Mimicry — the colony replicates and weaponises sound patterns for tracking purposes.[/b]"""
}