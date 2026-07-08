extends Control
class_name NotebookUI

## Two-page open book notebook.
## Spread 0: Index (Left) + To-Do (Right)
## Spread 1: Documentation (Left) + Notes (Right)
## Toggled with J, spread flipped with Q/E.

# ============================================================
# Spread state
# ============================================================

var _is_open: bool = false
var current_spread: int = 0
const MAX_SPREAD: int = 1

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
	# Find RoutineManager (autoload)
	var rm = get_node_or_null("/root/RoutineManager")
	if rm:
		# Connect to objective updates
		if rm.has_signal("routine_step_changed"):
			rm.routine_step_changed.connect(_on_routine_step_changed)
		
		# Register ourselves so other scripts can find us
		rm._notebook_ui = self
		
		# Fetch initial state — the notebook may load after the first
		# objectives were already set, so pull current values immediately
		var current_obj: String = rm.get_current_objective() if rm.has_method("get_current_objective") else ""
		if not current_obj.is_empty():
			_on_routine_step_changed(0, current_obj)
		
		
		
		# ─── TASK 1: Seed initial completed objectives ──────────────
		# The player starts on Day 1 having just arrived at the research
		# site. The only completed objective is driving there. The current
		# objective is to enter the cabin.
		_call_deferred_todo_seed()
	else:
		# Retry next frame
		call_deferred("_connect_to_managers")
		return
	
	# Find EvidenceManager (autoload)
	var em = get_node_or_null("/root/EvidenceManager")
	if em:
		if em.has_signal("evidence_collected"):
			em.evidence_collected.connect(_on_evidence_collected)
		
	
	# Find DocumentationManager if it exists
	var dm = get_node_or_null("/root/DocumentationManager")
	if dm and dm.has_signal("documentation_added"):
		dm.documentation_added.connect(add_documentation)
		


func _on_routine_step_changed(_step: int, objective_text: String) -> void:
	# If this is a genuinely new objective (not a duplicate), archive the
	# current one as completed before replacing it.
	if not objective_text.is_empty() and objective_text != _current_objective:
		if not _current_objective.is_empty():
			_completed_objectives.append(_current_objective)
		_current_objective = objective_text
	
	# Rebuild the To-Do display: completed items with strikethrough,
	# current active objective in bold with an unchecked box.
	var bbcode := "[center][b]TO-DO[/b][/center]\n\n"
	
	for obj in _completed_objectives:
		bbcode += "[s]  [x] %s[/s]\n" % obj
	
	if not _current_objective.is_empty():
		bbcode += "\n[b]  [ ] %s[/b]" % _current_objective
	
	_todo_label.text = bbcode
	
	
	# ─── ISSUE 2 FIX: Auto-update day label from NightManager ───
	# The HUD day label ("DAY 1", "DAY 2", etc.) was never updated
	# after the initial seed. Read NightManager.current_night and
	# compute the game day: Night 0 = Day 1, Night 1 = Day 2, etc.
	var nm = get_node_or_null("/root/NightManager")
	if nm and "current_night" in nm:
		var game_day = nm.current_night + 1
		if game_day != _current_day:
			_current_day = game_day
			_day_label.text = "[center][b]DAY %d[/b][/center]" % game_day


func _on_evidence_collected(evidence_id: String) -> void:
	if _notes_label.text.begins_with("[center][b]NOTES[/b]"):
		_notes_label.text = ""
	_notes_label.text += "[b]Evidence:[/b] %s\n" % evidence_id
	


## Deferred call after the scene tree is fully ready.
## Seeds the notebook's To-Do page with the initial Day 1 state:
## one completed objective ("Drive to the research area.") and the
## current objective ("Go to the cabin.").
func _call_deferred_todo_seed() -> void:
	await get_tree().process_frame
	update_objectives(1, ["Drive to the research area."], "Go to the cabin.")


func _initialize_pages() -> void:
	# Index page content
	_index_label.text = """[center][font_size=22][b]FIELD NOTEBOOK[/b][/font_size][/center]
[center][i]Svea Naturinstitut Ecological Survey[/i][/center]

[font_size=16][b]INDEX[/b][/font_size]

  [b]1.[/b]  To-do .................... [i]Current objectives[/i]

  [b]2.[/b]  Documentation ........... [i]Nest data & evidence[/i]

  [b]3.[/b]  Notes ................... [i]Field observations[/i]

[center]---
Press [b][J][/b] to close[/center]"""

	# To-Do page content
	_todo_label.text = "[center][b]TO-DO[/b][/center]\n\nLoading objectives..."

	# Documentation page content
	_doc_label.text = "[center][b]DOCUMENTATION[/b][/center]\n\nField notes on the Hazel Mouse Nests.\nUse the Photo Camera to document nests,\nthen validate at the computer terminal."

	# Notes page content
	_notes_label.text = "[center][b]NOTES[/b][/center]\n\nPersonal observations."


func _apply_styles() -> void:
	# ─── INK COLOR ─────────────────────────────────────────────
	var ink = Color("#1a1a1a")
	_index_label.add_theme_color_override("font_color", ink)
	_index_label.add_theme_color_override("default_color", ink)
	_todo_label.add_theme_color_override("font_color", ink)
	_todo_label.add_theme_color_override("default_color", ink)
	_doc_label.add_theme_color_override("font_color", ink)
	_doc_label.add_theme_color_override("default_color", ink)
	_notes_label.add_theme_color_override("font_color", ink)
	_notes_label.add_theme_color_override("default_color", ink)

	# ─── BOOK COVER (dark leather) ──────────────────────────────
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

	# ─── LEFT PAGE (paper + binding fold on right) ──────────────
	var left_paper = StyleBoxFlat.new()
	left_paper.bg_color = Color("#e8dcc7")
	left_paper.border_width_right = 1
	left_paper.border_color = Color("#b8a88a")
	left_paper.shadow_size = 4
	left_paper.shadow_offset = Vector2(2, 2)
	left_paper.shadow_color = Color(0, 0, 0, 0.15)
	_left_page.add_theme_stylebox_override("panel", left_paper)

	# ─── RIGHT PAGE (paper + binding fold on left) ──────────────
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
			_update_spread()
		get_viewport().set_input_as_handled()
		return

	if not _is_open:
		return

	if event.is_action_pressed("notebook_next_page"):
		current_spread = mini(current_spread + 1, MAX_SPREAD)
		_update_spread()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("notebook_prev_page"):
		current_spread = maxi(current_spread - 1, 0)
		_update_spread()
		get_viewport().set_input_as_handled()


# ============================================================
# Spread update
# ============================================================

func _update_spread() -> void:
	# Ensure both margins are visible (parent chain must be visible for children to render)
	if _left_margin:
		_left_margin.visible = true
	if _right_margin:
		_right_margin.visible = true

	# Spread 0: Index (Left) & To-Do (Right)
	_index_container.visible = (current_spread == 0)
	_todo_container.visible = (current_spread == 0)

	# Spread 1: Documentation (Left) & Notes (Right)
	_doc_container.visible = (current_spread == 1)
	_notes_container.visible = (current_spread == 1)

	


# ============================================================
# Toggle (kept for external callers like player_controller)
# ============================================================

func _toggle() -> void:
	_is_open = not _is_open
	visible = _is_open
	if _is_open:
		current_spread = 0
		_update_spread()


# ============================================================
# Objective integration (called by RoutineManager)
# ============================================================

func update_objectives(day: int, completed_objectives: Array[String], current_objective: String) -> void:
	if day != _current_day:
		_current_day = day
		_completed_objectives.clear()
		_current_objective = ""
		_day_label.text = "[center][b]DAY %d[/b][/center]" % day
		_todo_label.clear()

	var bbcode := ""
	bbcode += _day_label.text + "\n\n"

	for obj in completed_objectives:
		bbcode += "[s]  [x] " + obj + "[/s]\n"

	if not current_objective.is_empty():
		bbcode += "\n[b]  [ ] " + current_objective + "[/b]\n"

	_todo_label.text = bbcode
	# ─── Don't overwrite existing documentation with placeholder ──
	# Only reset _doc_label if it still contains the default placeholder
	# text. If real nest lore has been added, preserve it.
	if _doc_label.text.begins_with("[center][b]DOCUMENTATION[/b]") or _doc_label.text.begins_with("Nest documentation data will"):
		_doc_label.text = "Nest documentation data will appear here.\n\nUse the Photo Camera to document nests,\nthen validate at the computer terminal."


func set_documentation(text: String) -> void:
	_doc_label.text = text


## Appends a documented nest entry to the Documentation page (Spread 1, Left).
## Looks up the full field observation lore from NEST_LORE by nest_name.
## Called by hasselmus_nest.gd when the player photographs/interacts with a nest.
func add_documentation(nest_name: String) -> void:
	var lore: String = NEST_LORE.get(nest_name, "")
	if lore.is_empty():
		push_warning("[NotebookUI] No lore found for nest: %s" % nest_name)
		return
	
	# Clear placeholder text if this is the first entry
	if _doc_label.text.begins_with("[center][b]DOCUMENTATION[/b]"):
		_doc_label.text = ""
	
	_doc_label.text += "[b]%s[/b] — [i]Documented[/i]\n%s\n\n" % [nest_name, lore]
	


func add_note(text: String) -> void:
	if _notes_label.text.is_empty():
		_notes_label.text = text
	else:
		_notes_label.text += "\n\n" + text


# ============================================================
# Nest lore entries — revealed when the player documents each nest.
# The key concepts (photophobia, observation, mimicry) are clues
# for the computer terminal's FIELD_LOG.EXE puzzle on Day 2.
# ============================================================

const NEST_LORE: Dictionary = {
	"Nest Alpha": "Subject: Nest Alpha | Species: Muscardinus avellanarius\nConstruction: Woven honeysuckle bark. Usually, these nests are built to avoid predators. However, this nest and the mice inside actively and impossibly reject light. They scramble violently away from the flashlight beam, burrowing deeper into the wood. The photophobia is extreme.",
	"Nest Beta": "Subject: Nest Beta | Species: Muscardinus avellanarius\nObservation: The mice are not fleeing. They are positioned at the entrance of the nest, perfectly still, facing outward. When I move left, their heads track me. When I move right, they track me. It is a state of active observation. They are acting like scouts... it feels like something else is watching me through them.",
	"Nest Gamma": "Subject: Nest Gamma | Species: Muscardinus avellanarius\nObservation: Dormice typically emit faint, high-pitched squeaks. This colony is producing a low, rhythmic clicking. The clicking pauses the exact moment I stop walking, and resumes precisely when I shift my weight. It is acoustic mimicry. They are studying the acoustic properties of my footsteps... or masking the sound of something much heavier walking nearby.",
}
