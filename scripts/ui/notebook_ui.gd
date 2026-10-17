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

## Tracks which nest documentation entries have already been added,
## keyed by nest_label string (e.g. "Nest Alpha"). Prevents duplicate
## entries when the same nest is documented or signalled twice.
var _unlocked_nests: Dictionary = {}

## Tracks which note items have already been added to the notebook,
## keyed by a content-hash or unique note ID. Prevents the same note
## text from appearing twice when note_pickup.gd fires duplicate
## add_note calls.
var _unlocked_notes: Dictionary = {}
## Chapter 5, "The Entity": what the player has learned about it, in his own
## words (EntityJournal), by key, in the order learned.
var _entity_entries: Dictionary = {}
## Where it starts in _all_pages.
var _entity_start_page: int = 999999

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

## Dynamic hint text from RoutineManager for the active Day 2 step.
## Rendered in italics beneath the current objective in the To-Do list.
var _day2_hint_text: String = ""

# ============================================================
# Lifecycle
# ============================================================

## Found by its group (not by a path in the level).
func _enter_tree() -> void:
	add_to_group("notebook_ui")


func _ready() -> void:
	visible = false
	process_mode = PROCESS_MODE_ALWAYS
	
	# Apply ink color and book styling
	_apply_styles()
	_improve_layout()
	
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
		# ─── DAY 2 HINT SIGNAL ───────────────────────────────────────
		# The RoutineManager emits a dynamic hint string when the active
		# Day 2 step changes (e.g. "I may need a high-intensity beam...").
		if rm.has_signal("objective_hint_changed"):
			rm.objective_hint_changed.connect(_on_objective_hint_changed)
		# ─── DAY 3+ SIGNALS ──────────────────────────────────────────
		if rm.has_signal("van_checklist_changed"):
			rm.van_checklist_changed.connect(_refresh_van_checklist)
		if rm.has_signal("side_track_changed"):
			rm.side_track_changed.connect(_refresh_side_track)
		rm._notebook_ui = self
		var current_obj: String = rm.get_current_objective() if rm.has_method("get_current_objective") else ""
		if not current_obj.is_empty():
			_on_routine_step_changed(0, current_obj)
		_call_deferred_todo_seed()
	else:
		call_deferred("_connect_to_managers")
		return
	
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		if nm.has_signal("night_ended"):
			nm.night_ended.connect(_on_night_ended)
	
	var em = get_node_or_null("/root/EvidenceManager")
	if em:
		if em.has_signal("evidence_collected"):
			em.evidence_collected.connect(_on_evidence_collected)
	
	var dm = get_node_or_null("/root/DocumentationManager")
	if dm and dm.has_signal("documentation_added"):
		dm.documentation_added.connect(add_documentation)


## Called when NightManager emits night_ended. Clears the old day's
## objectives so the To-Do list is fresh when the new day starts.
## Connected from _connect_to_managers().
func _on_night_ended(night: int) -> void:
	_completed_objectives.clear()
	_current_objective = ""
	_current_day = night + 1
	_day_label.text = "DAY %d" % _current_day
	print("[Notebook] Night ended. Objectives cleared for Day %d." % _current_day)


func _on_routine_step_changed(_step: int, objective_text: String) -> void:
	# ─── DAY 3 SANDBOX OVERRIDE ────────────────────────────────────
	# When sandbox mode is active, the To-Do section is managed by the
	# dynamic van checklist / side-track formatters instead of the Day 1–2
	# linear objectives. We skip the standard objective list logic.
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and rm.is_day3_sandbox:
		# The step number / objective text from routine_step_changed is still
		# used by the HUD, but the notebook uses its own checklist formatter.
		_refresh_van_checklist()
		return
	
	if not objective_text.is_empty() and objective_text != _current_objective:
		if not _current_objective.is_empty():
			_completed_objectives.append(_current_objective)
		_current_objective = objective_text
	
	var bbcode := "[center][b]%s[/b][/center]\n\n" % _day_label.text
	for obj in _completed_objectives:
		bbcode += "[s]  [x] %s[/s]\n" % obj
	if not _current_objective.is_empty():
		bbcode += "\n[b]  [ ] %s[/b]" % _current_objective
	# ─── DAY 2 DYNAMIC HINT ──────────────────────────────────────
	# The RoutineManager injects a lore-friendly hint for the active
	# nest documentation step (Alpha/Beta/Gamma). Rendered in italics.
	if not _day2_hint_text.is_empty():
		bbcode += "\n[i][color=#6e655a]%s[/color][/i]" % _day2_hint_text
	_todo_label.text = bbcode


## Called when RoutineManager emits objective_hint_changed.
## Stores the new hint text and refreshes the To-Do list so the
## hint appears beneath the current objective.
func _on_objective_hint_changed(hint_text: String) -> void:
	_day2_hint_text = hint_text
	_on_routine_step_changed(0, _current_objective)


func _on_evidence_collected(evidence_id: String) -> void:
	# Note text is already added by note_pickup.gd's _add_to_notebook_and_cleanup()
	# with full title + content formatting. This handler only triggers evidence
	# tracking for the INDEX — it should NOT add a duplicate note.
	# The notebook's index is rebuilt by add_note() which is called by the pickup flow.
	pass


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
	_all_pages.append(CREDENTIALS_PAGE)
	
	# Chapter 3: Nest Data — starts at page 1 (no nests yet documented)
	# Chapter 4: Notes — will be appended via add_note()
	
	_nest_data_start_page = 1
	_notes_start_page = 999999
	
	_current_page = 0


func _rebuild_index() -> void:
	# Each chapter with where it starts and how far along it is.
	_index_label.text = """[center][font_size=22][b]FIELD NOTEBOOK[/b][/font_size][/center]
[center][i]Svea Naturinstitut Ecological Survey[/i][/center]

[font_size=16][b]INDEX[/b][/font_size]

  [b]1.[/b]  To-do   [color=#6e655a][i]opposite[/i][/color]

  [b]2.[/b]  Personnel Credentials   [color=#6e655a][i]p. 1[/i][/color]

  [b]3.[/b]  Nest Data   [color=#6e655a][i]p. %d · %d of 3 documented[/i][/color]

  [b]4.[/b]  Field Notes   [color=#6e655a][i]%s[/i][/color]

  [b]5.[/b]  The Entity   [color=#6e655a][i]%s[/i][/color]

[center]---
[color=#6e655a]%s[/color][/center]""" % [
		_nest_data_start_page + 1,
		_unlocked_nests.size(),
		"p. %d · %d %s" % [_notes_start_page + 1, _unlocked_notes.size(), "entry" if _unlocked_notes.size() == 1 else "entries"] if not _unlocked_notes.is_empty() else "none yet",
		"p. %d · %d %s" % [_entity_start_page + 1, _entity_entries.size(), "entry" if _entity_entries.size() == 1 else "entries"] if not _entity_entries.is_empty() else "nothing yet",
		GameKeys.keys_in("[Q] / [E] turn the pages · [J] close", {"E": "notebook_next_page"}),
	]


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
		_play_toggle()
		if _is_open:
			current_spread = 0
			_current_page = 0
			_rebuild_index()
			_update_spread()
			var tm := get_node_or_null("/root/TutorialManager")
			if tm and tm.has_method("mark_learned"):
				tm.mark_learned("notebook")
			# ─── DAY 2 STEP 1 GATE ─────────────────────────────────
			# Opening the notebook on Day 2 completes Step 1
			# ("Review the previous researcher's Nest Logs") and
			# unlocks the cabin door via RoutineManager.
			var rm := get_node_or_null("/root/RoutineManager")
			if rm and rm.has_method("on_notebook_opened"):
				rm.on_notebook_opened()
		get_viewport().set_input_as_handled()
		return

	if not _is_open:
		return

	if event.is_action_pressed("notebook_next_page") or event.is_action_pressed("notebook_prev_page"):
		_play_toggle()
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
			# EXPLICIT CHECK: If on the first content page (index 0), wrap to last page.
			# This mirrors the E-key wrap behavior symmetrically: pressing Q on the
			# first page goes to the last page, just like E on the last page goes
			# to the first page.
			if _current_page == 0:
				var max_page = max(0, _all_pages.size() - 1)
				var last_even = max_page if max_page % 2 == 0 else max_page - 1
				if last_even > 0 and _all_pages.size() >= 2:
					_current_page = last_even
					_refresh_spread_1()
				else:
					# 0 or 1 content pages only — no wrap available, go to Spread 0
					current_spread = maxi(current_spread - 1, 0)
					_current_page = 0
					_update_spread()
			elif _current_page >= 2:
				_current_page -= 2
				_refresh_spread_1()
			else:
				# Safety: should not be reached with the explicit 0-check above,
				# but acts as a graceful fallback to the index spread.
				current_spread = maxi(current_spread - 1, 0)
				_current_page = 0
				_update_spread()
		else:
			# On spread 0 (Index/To-Do). If there are content pages, wrap to last spread.
			if _all_pages.size() > 0:
				current_spread = 1
				var max_page = max(0, _all_pages.size() - 1)
				_current_page = max_page if max_page % 2 == 0 else max_page - 1
				_update_spread()
			else:
				current_spread = maxi(current_spread - 1, 0)
				_current_page = 0
				_update_spread()
		get_viewport().set_input_as_handled()


# ============================================================
# Layout: backdrop, paper, page numbers, page-turn sound
# ============================================================

const INK := Color("#1a1a1a")
const PENCIL := Color("#6e655a")
var _page_numbers: Array[Label] = []


## The book on a dimmed screen, paper with a gutter shade and a margin
## rule, page numbers, the stray day label hidden, page hints in ink.
func _improve_layout() -> void:
	# The day is shown on the To-do page; the bare label sat in the screen
	# corner.
	_day_label.visible = false
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	move_child(backdrop, 0)
	for page in [_left_page, _right_page]:
		page.draw.connect(_draw_paper.bind(page))
		page.queue_redraw()
		var number := Label.new()
		number.name = "PageNumber"
		number.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		number.offset_left = -60
		number.offset_right = 60
		number.offset_top = -36
		number.offset_bottom = -14
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.add_theme_color_override("font_color", PENCIL)
		number.add_theme_font_size_override("font_size", 14)
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(number)
		_page_numbers.append(number)
	for hint_name in ["PrevHint", "NextHint"]:
		var hint := get_node_or_null("%" + hint_name) as Label
		if hint:
			hint.add_theme_color_override("font_color", PENCIL)
			hint.add_theme_constant_override("outline_size", 0)
			hint.add_theme_constant_override("shadow_outline_size", 0)
			hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
			hint.add_theme_font_size_override("font_size", 14)


## Paper: shaded toward the spine, a faint red margin rule on the outer
## side.
func _draw_paper(page: Panel) -> void:
	var size := page.size
	var left := page == _left_page
	var gutter := 26.0
	for i in 8:
		var a := 0.06 * (1.0 - float(i) / 8.0)
		var w := gutter / 8.0
		var x := size.x - (i + 1) * w if left else i * w
		page.draw_rect(Rect2(x, 0, w, size.y), Color(0.35, 0.25, 0.12, a))
	var rule_x := 22.0 if left else size.x - 22.0
	page.draw_line(Vector2(rule_x, 0), Vector2(rule_x, size.y), Color(0.7, 0.25, 0.2, 0.25), 1.5)


func _update_page_numbers() -> void:
	if _page_numbers.size() < 2:
		return
	if current_spread == 0:
		_page_numbers[0].text = ""
		_page_numbers[1].text = ""
		return
	var left := _current_page
	_page_numbers[0].text = "— %d —" % (left + 1) if left < _all_pages.size() else ""
	_page_numbers[1].text = "— %d —" % (left + 2) if left + 1 < _all_pages.size() else ""


## Checkpoint restored the unlocked nests and notes: the pages again, shut.
func _on_checkpoint_restored() -> void:
	_is_open = false
	visible = false
	current_spread = 0
	_current_page = 0
	_rebuild_all_pages()
	_update_spread()


## Shuts the notebook (Escape, from pause_menu.gd). False if it wasn't open.
func close() -> bool:
	if not _is_open:
		return false
	_is_open = false
	visible = false
	_play_toggle()
	return true


func is_open() -> bool:
	return _is_open


## Opening or closing the notebook, and turning its pages.
const TOGGLE_SOUND := "res://assets/audio/objects/Toggle Journal.ogg"


func _play_toggle() -> void:
	if not ResourceLoader.exists(TOGGLE_SOUND):
		return
	var player := AudioStreamPlayer.new()
	player.bus = "SFX"
	player.stream = load(TOGGLE_SOUND)
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)




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
	else:
		_update_page_numbers()


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
	_update_page_numbers()


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
		if not _paged_by_size:
			_repage_when_laid_out()


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


# ============================================================
# Day 3+ Dynamic Checklists
# ============================================================

## Refreshes the van repair checklist in the To-Do section.
## Reads RoutineManager's van flags and renders [X]/[ ] checkboxes.
## Called when van_checklist_changed signal fires.
func _refresh_van_checklist() -> void:
	var rm = get_node_or_null("/root/RoutineManager")
	if not rm:
		return
	
	# ─── SAFETY: Only show the van checklist in sandbox mode ───────
	if not rm.is_day3_sandbox:
		return
	
	var bbcode := "[center][b]%s[/b][/center]\n\n" % _day_label.text
	
	# ─── GATED PROGRESSION: Must inspect the car first ──────────
	if not rm.van_inspected:
		bbcode += "\n[b]  [ ] Investigate the car again.[/b]\n"
		if rm.arvid_note_2_found:
			bbcode += "\n------------------------\n"
			bbcode += _build_side_track_text(rm)
		_todo_label.text = bbcode
		return
	
	bbcode += "[b]Find parts to repair the van:[/b]\n\n"
	
	# Check installed status from RoutineManager flags
	var battery_done = rm.van_battery_installed
	var radiator_done = rm.van_radiator_installed
	var wiring_done = rm.van_wiring_installed
	
	# Check if part has been COLLECTED (picked up from a scrap heap).
	# These flags are set by RoutineManager.on_car_part_collected() when the
	# player picks up the part — they render [X] as soon as the pickup
	# happens, even before the part is installed in the van. Fall back to
	# the inventory check for robustness (a part in the backpack is also
	# considered collected).
	var battery_collected = rm.van_battery_collected if "van_battery_collected" in rm else false
	var radiator_collected = rm.van_radiator_collected if "van_radiator_collected" in rm else false
	var wiring_collected = rm.van_wiring_collected if "van_wiring_collected" in rm else false
	if not battery_collected:
		battery_collected = rm.has_car_part_in_inventory("Car Battery")
	if not radiator_collected:
		radiator_collected = rm.has_car_part_in_inventory("Radiator")
	if not wiring_collected:
		wiring_collected = rm.has_car_part_in_inventory("Ignition Wiring")
	
	# Render checkboxes: [X] if installed, [/] if collected but not installed, [ ] otherwise
	bbcode += "  %s Battery (0/1)\n" % _checkbox_char(battery_done, battery_collected)
	bbcode += "  %s Radiator (0/1)\n" % _checkbox_char(radiator_done, radiator_collected)
	bbcode += "  %s Ignition Wiring (0/1)\n" % _checkbox_char(wiring_done, wiring_collected)
	
	# If all 3 parts are installed, show the escape objective
	if rm.van_fully_repaired:
		bbcode += "\n[b]  [ ] Start the van and escape.[/b]\n"
	
	# ─── Append side-track section if active ───────────────────────
	if rm.arvid_note_2_found:
		bbcode += "\n------------------------\n"
		bbcode += _build_side_track_text(rm)
	
	_todo_label.text = bbcode


## Returns the appropriate checkbox character for a part:
##   [X] if installed
##   [/] if in inventory but not installed
##   [ ] otherwise
func _checkbox_char(is_installed: bool, is_in_inventory: bool) -> String:
	if is_installed:
		return "[X]"
	elif is_in_inventory:
		return "[/]"
	return "[ ]"


## Builds the side-track (Unsanctioned Discoveries) BBcode text.
## Shows the 9-step sequence with checkboxes reflecting current progress.
func _build_side_track_text(rm: Node) -> String:
	var text := "[b]UNSANCTIONED DISCOVERIES:[/b]\n\n"
	
	var steps = [
		["Log in with Arvid's credentials", rm.arvid_logged_in],
		["Read logs", rm.arvid_logs_read],
		["Find portable light", rm.arvid_portable_light_found],
		["Find cable spool", rm.arvid_cable_spool_found],
		["Find fuel can", rm.arvid_fuel_can_found],
		["Locate anchor", rm.arvid_anchor_located],
		["Set trap", rm.is_cable_to_gen_connected and rm.is_cable_to_light_connected],
		["Trigger trap", rm.is_trap_triggered],
		["Destroy anchor", rm.is_anchor_destroyed],
	]
	
	for step in steps:
		var check = "[X]" if step[1] else "[ ]"
		text += "  %s %s\n" % [check, step[0]]
	
	return text


## Refreshes the side-track section in the To-Do list.
## Called when side_track_changed signal fires.
func _refresh_side_track() -> void:
	# The side-track is rendered as part of the van checklist.
	# Just refresh the entire todo display.
	_refresh_van_checklist()


func set_documentation(text: String) -> void:
	# Deprecated single-doc mode — clear and populate
	_all_pages = [text]
	_current_page = 0
	_nest_data_start_page = 0
	_notes_start_page = 999999
	if current_spread == 1:
		_refresh_spread_1()


## Lore-friendly hint lines for each nest, mirroring RoutineManager's
## DAY2_NEST_HINTS. Shown permanently at the top of each nest's dedicated
## page in the Notebook, even before the documentation data is collected.
## Data populates below the hint once the nest is documented.
const NEST_HINTS: Dictionary = {
	"Nest Alpha": "I may need a high-intensity beam to provoke them.",
	"Nest Beta": "They watch. I should stay low and approach quietly.",
	"Nest Gamma": "They answer back. I should make a sound, then listen.",
}

const NEST_ORDER: Array[String] = ["Nest Alpha", "Nest Beta", "Nest Gamma"]

const CREDENTIALS_PAGE := "[center][b]PERSONNEL CREDENTIALS[/b][/center]\n\n[font_size=16][b]Svea Naturinstitut[/b][/font_size]\n[font_size=13][i]Ekologisk Fältundersökning[/i][/font_size]\n\n[font_size=14][b]Researcher:[/b] Lund\n[b]ID:[/b] SNI-7742-L\n[b]Clearance:[/b] Level 3 (Ecological)\n[b]Vehicle:[/b] Unit 12 — field van\n[b]Assignment:[/b] Hazel dormouse (Muscardinus avellanarius) population survey — Phase 2, replacing A. Stenberg\n\n[b]─── COMPUTER LOGIN ───[/b]\n[b]Login:[/b] LUND\n[b]Password:[/b] PASSKEY1[/font_size]\n\n[font_size=12][i]This notebook is the property of Svea Naturinstitut.\nUnauthorised access or reproduction is a violation of the Swedish Environmental Code (Miljöbalken, 1998:808).\n\nReport lost or damaged equipment to your supervising officer immediately.[/i][/font_size]"


## ─── STATE-DRIVEN REBUILD ──────────────────────────────────────
## Completely clears and rebuilds _all_pages from the two backend
## dictionaries (_unlocked_nests, _unlocked_notes). This guarantees
## mathematical ordering: Chapter 2 (Credentials) → Chapter 3 (Nest
## Data) → Chapter 4 (Notes), regardless of pickup order.
##
## NEST DEDICATED PAGES:
## Every nest gets its own dedicated page (in fixed Alpha → Beta → Gamma
## order). The header + hint line is ALWAYS present. Once a nest is
## documented, the collected data populates below the hint.
func _rebuild_all_pages() -> void:
	_all_pages.clear()
	
	# Chapter 2: Personnel Credentials (always page 0)
	_all_pages.append(CREDENTIALS_PAGE)
	
	_nest_data_start_page = 1
	
	# Chapter 3: Nest Data — one dedicated page per nest, in fixed order.
	# The hint is permanent; the documented data populates below it once
	# the nest has been documented in the field.
	for nest_key in NEST_ORDER:
		var page_text := _build_nest_page(nest_key)
		if not page_text.is_empty():
			_append_page_content(page_text)
	
	# Chapter 4: Notes — insert all unlocked notes
	_notes_start_page = _all_pages.size()
	for note_text in _unlocked_notes.values():
		_append_page_content(note_text)
	
	# Chapter 5: The Entity — what he's learned about it (EntityJournal).
	_entity_start_page = _all_pages.size()
	if not _entity_entries.is_empty():
		_append_page_content(_entity_chapter_text())

	_rebuild_index()


## Chapter 5's text: a heading, then each entry in the order learned.
func _entity_chapter_text() -> String:
	var text := "[center][b]THE ENTITY[/b][/center]\n[center][i][color=#6e655a]What I know about it. Written as I learn it.[/color][/i][/center]\n\n"
	for entry in _entity_entries.values():
		text += "— %s\n\n" % entry
	return text.strip_edges()


## Writes (or rewrites) an entry of chapter 5. False if it was already
## written exactly so.
func add_entity_entry(key: String, text: String) -> bool:
	if _entity_entries.get(key, "") == text:
		return false
	_entity_entries[key] = text
	_rebuild_all_pages()
	_update_spread()
	_play_scribble_sfx()
	return true


func entity_entry_count() -> int:
	return _entity_entries.size()


func has_entity_entry(key: String) -> bool:
	return _entity_entries.has(key)


## Builds the BBCode content for a single nest's dedicated page:
## header + permanent hint at the top, then the collected documentation
## data below it (or a "not yet documented" placeholder).
func _build_nest_page(nest_key: String) -> String:
	var hint: String = NEST_HINTS.get(nest_key, "")
	var header := "[b]Subject: %s[/b]" % nest_key
	if _unlocked_nests.has(nest_key):
		header += "   [color=#8a2b1d][b]DOCUMENTED[/b][/color]"
	var page := header + "\n"
	if not hint.is_empty():
		page += "[i][color=#6e655a]Hint: %s[/color][/i]\n\n" % hint
	
	if _unlocked_nests.has(nest_key):
		var lore_text: String = NEST_LORE.get(nest_key, "")
		if not lore_text.is_empty():
			# Strip the leading "Subject:" header from the lore (the hint
			# already carries it) so the data populates cleanly below.
			var data_body := lore_text
			if data_body.begins_with("[b]Subject:"):
				var header_end := data_body.find("\n")
				if header_end >= 0:
					data_body = data_body.substr(header_end + 1)
			page += data_body.strip_edges()
	else:
		page += "[color=#6e655a][i]No data recorded yet. Observations will be written here once the nest is documented.[/i][/color]"
	return page


## Appends a text block to _all_pages, splitting across page boundaries
## when the content exceeds CHARS_PER_PAGE. Word-wrap aware.
func _append_page_content(content: String) -> void:
	# ─── TEXT SANITIZATION ─────────────────────────────────────────
	# GDScript's Resource loader escapes backslashes in .tres files.
	# A string like "line1\\n\\nline2" in the .tres becomes
	# "line1\\n\\nline2" in the loaded string (the backslash is preserved).
	# Replace all forms:
	#   \\n → actual newline (GDScript Resource load escape)
	#   /n → actual newline (forward-slash variant that sometimes appears)
	#   \\r\\n → actual newline (Windows line endings)
	#   \n (literal backslash-n as separate chars) → newline
	content = content.replace("\\n", "\n")     # "\\n" in GDScript string -> actual newline
	content = content.replace("/n", "\n")      # forward-slash variant
	content = content.replace("\\r\\n", "\n")  # Windows CR+LF
	content = content.replace("\\r", "\n")     # standalone CR
	content = content.trim_prefix("\"").trim_suffix("\"")
	content = content.trim_prefix("\"\"\"").trim_suffix("\"\"\"")
	content = content.strip_edges()
	if content.is_empty():
		return
	
	var chunks: Array[String] = _split_into_pages(content)
	for chunk in chunks:
		if _all_pages.is_empty() or _all_pages[-1] != "":
			_all_pages.append("")
		_all_pages[_all_pages.size() - 1] = chunk


## Appends a documented nest entry. Stores the nest ID in the backend
## dictionary and triggers a full rebuild of all pages.
func add_documentation(nest_id: String) -> void:
	# ─── DUPLICATE GUARD ──────────────────────────────────────────
	if _unlocked_nests.has(nest_id):
		print("[Notebook] Nest '%s' already documented. Skipping duplicate." % nest_id)
		return
	
	if not NEST_LORE.has(nest_id):
		push_error("Notebook: Could not find nest data for ID: " + nest_id)
		return
	
	_unlocked_nests[nest_id] = true
	_rebuild_all_pages()
	_update_spread()
	print("[Notebook] Nest '%s' documented. State-driven rebuild complete." % nest_id)


## Appends a note entry. Stores the note text in the backend dictionary
## and triggers a full rebuild of all pages.
func add_note(text: String) -> void:
	if text.is_empty():
		return
	
	# ─── DUPLICATE GUARD ──────────────────────────────────────────
	var note_key = text.hash()
	if _unlocked_notes.has(note_key):
		print("[Notebook] Note already added (hash=%d). Skipping duplicate." % note_key)
		return
	
	_unlocked_notes[note_key] = text
	_rebuild_all_pages()
	_update_spread()
	
	# ─── PLAY SCRIBBLE SOUND ──────────────────────────────────────
	# Play the notebook writing sound effect whenever a note is added,
	# regardless of the source (NotePickup, tutorial, debug console).
	# This is a complementary sound to the one in note_pickup.gd —
	# this one catches all entry paths while note_pickup.gd's version
	# catches the direct pickup case.
	_play_scribble_sfx()
	
	print("[Notebook] Note appended. State-driven rebuild complete.")


## Plays the notebook_writing.ogg scribble sound effect via a transient
## AudioStreamPlayer. The player is auto-freed when the sound finishes.
## Duplicates the logic from note_pickup.gd's _play_notebook_sfx() so
## that the sound plays regardless of how the note is added.
func _play_scribble_sfx() -> void:
	var stream := load("res://assets/audio/notebook_writing.ogg")
	if not stream:
		# Fallback: try UI click sound if notebook writing sound is missing
		stream = load("res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/GUI/gui_click_1.ogg")
	if not stream:
		return
	var player := AudioStreamPlayer.new()
	player.bus = "SFX"
	player.stream = stream
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


## Splits a text into pages that fit the page as it's drawn (measured in a
## hidden copy of the page's label): as many whole paragraphs as fit, then a
## paragraph that doesn't fit at all is split between words. Until the
## notebook has a size (before it's first laid out) it falls back to
## CHARS_PER_PAGE characters; it's paged again, measured, when it's opened.
## Does NOT modify _all_pages.
func _split_into_pages(text: String) -> Array[String]:
	var page := _page_size()
	if page.x < 50.0 or page.y < 50.0:
		return _split_by_chars(text)
	_paged_by_size = true
	var result: Array[String] = []
	var remaining := text
	while remaining != "":
		if _fits(remaining, page):
			result.append(remaining)
			break
		# The longest run of whole paragraphs that fits...
		var cut := _longest_fit(remaining, page, "\n")
		# ...or of words, if not even the first paragraph does.
		if cut <= 0:
			cut = _longest_fit(remaining, page, " ")
		if cut <= 0:
			cut = mini(remaining.length(), CHARS_PER_PAGE)
		result.append(remaining.substr(0, cut).strip_edges(false, true))
		remaining = remaining.substr(cut).strip_edges(true, false)
	return result


## Paged by character count so far (it had no size yet): once it's laid
## out (a frame after it first opens), paged again by what fits.
func _repage_when_laid_out() -> void:
	await get_tree().process_frame
	if _paged_by_size or not _is_open or _page_size().y < 50.0:
		return
	_rebuild_all_pages()
	_update_spread()


## Whether the text pages were measured (else they're paged again on opening).
var _paged_by_size := false
var _measure: RichTextLabel = null


## Room left at the foot of a page for the "Prev Page"/"Next Page" hints.
const PAGE_FOOT := 26.0


## The size the text has on a page: the left page inside its margins (the
## page's own label may be hidden, on the index spread, and have no size).
func _page_size() -> Vector2:
	if not _doc_label:
		return Vector2.ZERO
	var margin := _doc_label.get_parent().get_parent() as MarginContainer
	if margin == null or margin.size.y < 1.0:
		return _doc_label.size
	var inner := margin.size - Vector2(
		margin.get_theme_constant("margin_left") + margin.get_theme_constant("margin_right"),
		margin.get_theme_constant("margin_top") + margin.get_theme_constant("margin_bottom") + PAGE_FOOT)
	return inner


## Whether `text` fits on a page `page` big.
func _fits(text: String, page: Vector2) -> bool:
	if _measure == null:
		_measure = _doc_label.duplicate() as RichTextLabel
		_measure.name = "PageMeasure"
		_measure.visible = true
		_measure.modulate.a = 0.0
		_measure.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_measure.fit_content = false
		_measure.scroll_active = false
		_measure.top_level = true
		_measure.position = Vector2(-10000.0, -10000.0)
		add_child(_measure)
	_measure.size = Vector2(page.x, page.y)
	_measure.text = text
	return _measure.get_content_height() <= page.y


## Where to cut `text` (after one of `breaks`) for the most of it that fits
## on a page; 0 if not even the first piece does.
func _longest_fit(text: String, page: Vector2, breaks: String) -> int:
	var cuts: Array[int] = []
	var at := text.find(breaks)
	while at > 0:
		cuts.append(at + 1)
		at = text.find(breaks, at + 1)
	# Binary search for the last cut that still fits.
	var low := 0
	var high := cuts.size() - 1
	var best := 0
	while low <= high:
		var middle := (low + high) / 2
		if _fits(text.substr(0, cuts[middle]), page):
			best = cuts[middle]
			low = middle + 1
		else:
			high = middle - 1
	return best


## The old way: CHARS_PER_PAGE characters a page, cut at a line or a word.
func _split_by_chars(text: String) -> Array[String]:
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


# ============================================================
# Nest lore entries
# ============================================================

const NEST_LORE: Dictionary = {
	"Nest Alpha": """[b]Subject: Nest Alpha[/b]
[b]Population:[/b] 6
[b]Anomaly:[/b] Photophobia
[b]Notebook Observations:[/b]
Nest constructed inside a hollowed tree stump, but the colony displays violent photophobia. Upon shining the flashlight into the cavity, the six specimens panicked. Rather than seeking natural cover, two attempted to burrow blindly into pitch darkness while the others hissed and lunged directly toward the beam, aggressively trying to extinguish or attack the light source.""" ,

	"Nest Beta": """[b]Subject: Nest Beta[/b]
[b]Population:[/b] Unknown
[b]Anomaly:[/b] Covert Observation
[b]Notebook Observations:[/b]
The nest is built deep within a hollowed tree stump, making an exact count impossible. Whenever I adjusted my position, eyes glinted from within the dark fissures of the wood, instantly adjusting to remain hidden behind bark. They aren't running away—they are almost spying on me, positioning themselves so they can observe my every movement without being seen. I had the same feeling at the cabin window last night.""" ,

	"Nest Gamma": """[b]Subject: Nest Gamma[/b]
[b]Population:[/b] 3
[b]Anomaly:[/b] Audio-Specific Abnormalities
[b]Notebook Observations:[/b]
Only three specimens were present inside this tree stump nest. Their vocalizations are deeply unnatural: no squeaks or rustles, only raspy clicks and a low resonance. When I stopped walking, footsteps carried on inside the stump. When I clicked the flashlight, it clicked back, a moment late and slightly off. They aren't calling to each other. They are copying me, as if something taught them how."""
}
