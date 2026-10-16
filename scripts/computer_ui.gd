extends CanvasLayer
class_name ComputerUI

## ComputerUI — Windows 98-style Archival System interface with multi-user login.
##
## Two-Phase Architecture:
##   Phase 1 (Login): Terminal-style login screen. Player must enter credentials.
##     - LUND / PASSWORD → logs in as the player, triggers Day 1 progression.
##     - STENBERG / 1996 → logs in as Arvid (secret), no Day 1 trigger.
##   Phase 2 (Desktop): Retro desktop with icons that change based on current_user.
##     - LUND: FIELD_LOG.EXE, Log Off
##     - STENBERG: Recycle Bin, Log Off
##
## FIELD_LOG.EXE is GATED behind Day 2+ conditions — it cannot be used on Day 1.

signal computer_closed

# ─────────────────────────────────────────────────────────────────────────────
# MULTI-USER SYSTEM
# ─────────────────────────────────────────────────────────────────────────────

var is_open: bool = false
var current_user: String = ""

const VALID_CREDENTIALS: Dictionary = {
	"LUND": "PASSKEY1",
	"STENBERG": "1996",
}

# ─────────────────────────────────────────────────────────────────────────────
# REFERENCES
# ─────────────────────────────────────────────────────────────────────────────

var _player: Node = null
var _original_camera_transform: Transform3D
var _camera_holder: Node3D = null

# ─────────────────────────────────────────────────────────────────────────────
# STATE FLAGS
# ─────────────────────────────────────────────────────────────────────────────

var _unlocked_profiles: Dictionary = {}
var _eco_survey_completed: bool = false
var _nest_data_uploaded: bool = false
var is_arvid_log_1_unlocked: bool = false
var is_arvid_log_2_unlocked: bool = false

var nest_data_uploaded: bool:
	get: return _nest_data_uploaded
	set(v): _nest_data_uploaded = v

@export var always_pass_correlation: bool = false

const ARVID_DECRYPTION_KEY: String = "Linnea_and_Maja"

# ─────────────────────────────────────────────────────────────────────────────
# ONREADY NODES — Login Screen
# ─────────────────────────────────────────────────────────────────────────────

@onready var _login_screen: Panel = $LoginScreen
@onready var _username_input: LineEdit = $LoginScreen/LoginVBox/UsernameInput
@onready var _password_input: LineEdit = $LoginScreen/LoginVBox/PasswordInput
@onready var _login_button: Button = $LoginScreen/LoginVBox/LoginButton
@onready var _login_error: Label = $LoginScreen/LoginVBox/ErrorLabel
@onready var _power_off_btn: Button = $LoginScreen/PowerOffButton

# ─────────────────────────────────────────────────────────────────────────────
# ONREADY NODES — Desktop View
# ─────────────────────────────────────────────────────────────────────────────

@onready var _desktop_view: Panel = $DesktopView
@onready var _desktop_field_log_btn: Button = $DesktopView/FieldLogIcon
@onready var _desktop_recycle_btn: Button = $DesktopView/RecycleBinIcon
@onready var _desktop_logoff_btn: Button = $DesktopView/LogOffIcon
@onready var _desktop_shutdown_btn: Button = $DesktopView/ShutDownIcon
@onready var _desktop_previous_reports_btn: Button = $DesktopView/PreviousReportsIcon

# ─────────────────────────────────────────────────────────────────────────────
# ONREADY NODES — Main Window
# ─────────────────────────────────────────────────────────────────────────────

@onready var _main_window: Panel = $MainWindow
@onready var _content_display: RichTextLabel = $MainWindow/HBoxContainer/ContentPanel/ContentDisplay
@onready var _close_button: Button = $MainWindow/TitleBar/CloseButton
@onready var _minimize_button: Button = $MainWindow/TitleBar/MinimizeButton
@onready var _maximize_button: Button = $MainWindow/TitleBar/MaximizeButton
@onready var _status_label: Label = $MainWindow/StatusBar/StatusLabel

# Data entry (FIELD_LOG.EXE) — 3 static nest rows from .tscn
@onready var _data_entry_panel: Panel = $MainWindow/HBoxContainer/DataEntryPanel
@onready var _dropdown_anomaly_a: OptionButton = $MainWindow/HBoxContainer/DataEntryPanel/DataEntryVBox/DropdownAnomalyA
@onready var _pop_input_a: LineEdit = $MainWindow/HBoxContainer/DataEntryPanel/DataEntryVBox/PopulationInputA
@onready var _dropdown_anomaly_b: OptionButton = $MainWindow/HBoxContainer/DataEntryPanel/DataEntryVBox/DropdownAnomalyB
@onready var _pop_input_b: LineEdit = $MainWindow/HBoxContainer/DataEntryPanel/DataEntryVBox/PopulationInputB
@onready var _dropdown_anomaly_c: OptionButton = $MainWindow/HBoxContainer/DataEntryPanel/DataEntryVBox/DropdownAnomalyC
@onready var _pop_input_c: LineEdit = $MainWindow/HBoxContainer/DataEntryPanel/DataEntryVBox/PopulationInputC
@onready var _btn_correlate: Button = $MainWindow/HBoxContainer/DataEntryPanel/DataEntryVBox/CorrelateButton

# Recovery (RECOVER_DATA.EXE)
@onready var _recovery_panel: Panel = $MainWindow/HBoxContainer/RecoveryPanel
@onready var _key_input: LineEdit = $MainWindow/HBoxContainer/RecoveryPanel/RecoveryVBox/KeyInput
@onready var _submit_key_btn: Button = $MainWindow/HBoxContainer/RecoveryPanel/RecoveryVBox/SubmitKeyButton
@onready var _recovery_status: Label = $MainWindow/HBoxContainer/RecoveryPanel/RecoveryVBox/RecoveryStatus

var _is_minimized: bool = false
var _is_maximized: bool = false
var _normal_rect: Rect2

# ─────────────────────────────────────────────────────────────────────────────
# DATA & ANSWER KEYS
# ─────────────────────────────────────────────────────────────────────────────

const NIGHT_ANSWER_KEY: Dictionary = {
	1: [0, 0, 0],
	2: [2, 2, 1],
}

const NEST_ANSWER_KEY: Dictionary = {
	"Nest Alpha":  { "pop": "6",      "anomaly": "Photophobia" },
	"Nest Beta":   { "pop": "unknown","anomaly": "Covert Observation" },
	"Nest Gamma":  { "pop": "3",      "anomaly": "Audio-Specific Abnormalities" },
}

## Behavioral/anomaly options for the FIELD_LOG.EXE correlation form.
## These are framed as scientific field-survey categories — ways of
## recording abnormal or potentially supernatural behaviour without
## labelling it as such. The first four entries match the classic
## baseline; they are kept (with "Standard Biological Behavior" as the
## no-symptom baseline) and expanded with additional survey categories.
const ANOMALY_OPTIONS: Array[String] = [
	"Standard Biological Behavior",
	"Photophobia",
	"Covert Observation",
	"Audio-Specific Abnormalities",
	"Unseasonal Circadian Inversion",
	"Spatial Displacement Patterns",
	"Thermal Anomaly Signature",
	"Electrostatic Field Distortion",
	"Mirror-Image Stimulus Response",
	"Geotactic Bypass Behavior",
	"Irregular Vocalization Rhythms",
	"Territorial Threshold Transgression",
]

const TACTICAL_LOG_REWARDS: Dictionary = {
	1: {
		"title": "SUBJECT LOG_01 — Flashlight Clicking Tactical Brief",
		"body": (
			"SUBJECT LOG_01: Target responds aggressively to continuous focused "
			+ "light vectors. Quickly switching off power sources breaks vector "
			+ "calculations and tracking bounds."
		)
	},
	2: {
		"title": "SUBJECT LOG_02 — Flare Baiting Tactical Brief",
		"body": (
			"SUBJECT LOG_02: High-intensity thermal magnesium burns (Flares) mimic "
			+ "moving human bio-signatures. Target prioritizes point-light sources "
			+ "over physical assets, initiating an immediate standoff and strike "
			+ "cycle on the flare."
		)
	},
}

## Previous researcher's nest reports — the Day 2 Step 1 document the player
## must read on the computer before heading out to document the nests.
const PREVIOUS_NEST_REPORTS: String = (
	"[b]PREVIOUS NEST REPORTS — FIELD ARCHIVE[/b]\n"
	+ "[color=gray]Phase 1 · Baseline survey · Filed 28 March[/color]\n\n"
	+ "[color=red]RESTRICTED: Institute staff only. Do not redistribute.[/color]\n\n"
	+ "Three active hazel dormouse (Muscardinus avellanarius) colonies have "
	+ "been charted around the cabin, each in a hollow stump marked with the "
	+ "old survey's orange tape. All three were awake and feeding weeks before "
	+ "the species should leave hibernation, and each shows behaviour "
	+ "inconsistent with the species.\n\n"
	+ "[b]NEST ALPHA — Hollow stump, east of the cabin[/b]\n"
	+ "Population estimate: 6. Violent photophobia. In ordinary light the "
	+ "colony stays dormant; a high-intensity beam provokes it at once. "
	+ "Subjects lunge at the light source instead of fleeing it.\n\n"
	+ "[b]NEST BETA — Hollow stump, west of the cabin[/b]\n"
	+ "Population estimate: Unknown (no full count possible). Hyper-vigilant. "
	+ "Subjects track the observer and reposition to remain hidden. Any upright "
	+ "movement near the stump triggers a defensive lockdown: approach low "
	+ "and quietly.\n\n"
	+ "[b]NEST GAMMA — Hollow stump, far south-west, by the sunken tunnel[/b]\n"
	+ "Population estimate: 3. Abnormal vocalizations. The colony answers "
	+ "sounds made near it (footsteps, the click of a flashlight) a moment "
	+ "later and slightly altered. Make a sound, then stay still and listen.\n\n"
	+ "[color=gray]— A. Stenberg, Field Researcher, Svea Naturinstitut[/color]"
)

const ARVID_LOG_01_SURVEY: String = (
	"[b]SYSTEM RECOVERY: SECTOR 0x4F RESTORED[/b]\n"
	+ "[color=gray]LOG DATE: MARCH 14[/color]\n\n"
	+ "The Institute lied to me. This was never a population survey. I found "
	+ "old land surveys in the crawlspace, dated 1974, stamped by the same "
	+ "office that hired me. They've known about the 'Watcher' for twenty-five "
	+ "years. The logging crews didn't leave because the timber ran out; they "
	+ "left because the Institute couldn't keep them alive. This terminal "
	+ "still boots as the old forestry archive. It came with the cabin, "
	+ "like everything else here.\n\n"
	+ "Nobody is coming to relieve me. They aren't trying to keep people away "
	+ "from it. They're measuring how it hunts. I'm the canary in the mine, "
	+ "and the dormice are just the paperwork."
)

const ARVID_LOG_02_CRITICAL: String = (
	"[b]SYSTEM RECOVERY: MAIL_SPOOL_REBUILT[/b]\n"
	+ "[color=gray]LOG DATE: APRIL 02 (UNSENT)[/color]\n\n"
	+ "It knows I'm inside. Every night it circles the cabin just past the "
	+ "edge of the light. A flashlight only enrages it now: a quick beam hurts "
	+ "it enough to make it charge blind. A steady flood of light is "
	+ "different. That holds it.\n\n"
	+ "The plan: the portable floodlight from the Institute's kit and a cable "
	+ "spool, run from the generator. Fill the tank first. When it comes for "
	+ "the cabin, EXECUTE OVERLOAD from this terminal: the lamp burns far past "
	+ "its rating, a wall of light that should pin the thing where it "
	+ "stands.\n\n"
	+ "That's the window. Run for the willow (the anchor only rises out of "
	+ "the ground at night) and tear it out before the overload drinks the "
	+ "generator dry. When the light dies, it's free again.\n\n"
	+ "My battery is almost gone. I'm going to the tunnel to write the rest "
	+ "down where the network can't see it."
)

## What Arvid deleted (the STENBERG Recycle Bin): a report he didn't dare
## send, and the office's answer to his asking to go home.
const RECYCLE_BIN_CONTENTS: String = (
	"[b]RECYCLE BIN — 2 deleted items[/b]\n"
	+ "[color=red]WARNING: These files are marked for permanent deletion.[/color]\n\n"
	+ "[b]DRAFT_REPORT_ERR04.TXT[/b]\n"
	+ "[color=gray]Deleted 28 March[/color]\n\n"
	+ "The nests are not natural.\n\n"
	+ "The old survey's stakes mark seventeen stumps around the cabin. Fourteen "
	+ "are empty. Three hold colonies, awake a month before any dormouse in "
	+ "Sweden should be. Somebody planted those stakes in 1974 knowing exactly "
	+ "where to put them.\n\n"
	+ "Something is watching the cabin, and the colonies are learning from it.\n\n"
	+ "I've sent this to the office three times. Each time the terminal says "
	+ "DELIVERED, and nobody answers.\n\n"
	+ "My rotation ended two weeks ago. Unit 9 wouldn't start this morning: "
	+ "something had pulled the ignition wiring out through the grille. "
	+ "The road is right there, and I can't get down it.\n\n"
	+ "— A. Stenberg\n"
	+ "[color=gray][i](Not sent. They read the drafts too.)[/i][/color]\n\n"
	+ "---\n\n"
	+ "[b]RE_RELIEF_REQUEST.MSG[/b]\n"
	+ "[color=gray]Received 30 March · From: Svea Naturinstitut, Field Office[/color]\n\n"
	+ "Dr Stenberg,\n\n"
	+ "Your request for relief has been noted. A Phase 2 researcher is being "
	+ "prepared. Until they arrive, please continue your observations, "
	+ "particularly after dark. Your data from the past fortnight has been of "
	+ "exceptional value.\n\n"
	+ "Regarding Unit 9: please do not attempt repairs yourself.\n\n"
	+ "— Field Office"
)

## The Phase 2 welcome memo on the LUND desktop (MEMO.TXT): the Institute's
## version of the story, polite and careful about what it leaves out.
const LUND_MEMO: String = (
	"[b]MEMO.TXT[/b]\n"
	+ "[color=gray]From: Svea Naturinstitut, Field Office\n"
	+ "To: Lund, Field Researcher (Phase 2)\n"
	+ "Re: Hazel dormouse survey, Phase 2[/color]\n\n"
	+ "Welcome to the site. Please read the following before you begin.\n\n"
	+ "1. Report all observations through FIELD_LOG.EXE. The phone network "
	+ "does not reach the cabin; this terminal is your only line to the office. "
	+ "It runs the former forestry archive system. Ignore its legacy menus.\n\n"
	+ "2. Your predecessor, A. Stenberg, has been reassigned. His records are "
	+ "archived. Do not attempt to access other staff accounts.\n\n"
	+ "3. Fieldwork is to be done between sunrise and sunset. After dark, "
	+ "remain inside the cabin with the generator running. Any activity "
	+ "near the cabin at night is to be logged, not investigated.\n\n"
	+ "4. The colony sites are marked with the old survey's orange tape. "
	+ "Do not remove or move the stakes.\n\n"
	+ "5. The cabin, its generator and Unit 12 are Institute property. "
	+ "Report any damage on your return.\n\n"
	+ "Phase 2 is planned for three nights.\n\n"
	+ "— Field Office"
)

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────────────────

func set_player_references(player: Node, camera_holder: Node3D) -> void:
	_player = player
	_camera_holder = camera_holder

func set_original_camera_transform(transform: Transform3D) -> void:
	_original_camera_transform = transform


# ─────────────────────────────────────────────────────────────────────────────
# INITIALIZATION
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	visible = false
	add_to_group("computer_ui")
	always_pass_correlation = false
	
	# ─── FIELD_LOG.EXE FORM INIT: ANOMALY OPTIONS + POPULATION HINTS ──
	# The anomaly dropdowns and population placeholders are configured in
	# the scene, but ANOMALY_OPTIONS is the single source of truth. Refresh
	# each dropdown from it at runtime so newly added survey categories are
	# always present, and set the population prompt text.
	for dropdown in [_dropdown_anomaly_a, _dropdown_anomaly_b, _dropdown_anomaly_c]:
		if not dropdown:
			continue
		dropdown.clear()
		for i in ANOMALY_OPTIONS.size():
			dropdown.add_item(ANOMALY_OPTIONS[i], i)
		dropdown.selected = 0
	for pop_input in [_pop_input_a, _pop_input_b, _pop_input_c]:
		if pop_input:
			pop_input.placeholder_text = "Enter number of specimens here..."
	
	if _close_button:   _close_button.pressed.connect(_on_close_app_window)
	if _minimize_button: _minimize_button.pressed.connect(_on_minimize)
	if _maximize_button: _maximize_button.pressed.connect(_on_maximize)
	if _login_button:   _login_button.pressed.connect(_on_login_submit)
	if _username_input:
		_username_input.text_submitted.connect(func(_text): _on_login_submit())
	if _password_input:
		_password_input.text_submitted.connect(func(_text): _on_login_submit())
	if _desktop_field_log_btn: _desktop_field_log_btn.pressed.connect(_on_field_log_open)
	if _desktop_recycle_btn:   _desktop_recycle_btn.pressed.connect(_on_trash)
	# ─── TASK 4 FIX: ENTER SUBMITS THE DECRYPTION KEY ──────────────
	# The RECOVER_DATA.EXE key input must accept the Enter key to
	# confirm, matching the login screen's LineEdit behavior.
	# NOTE: _submit_key_btn.pressed is connected further below (avoid
	# a duplicate connection that would double-fire on press).
	if _key_input:
		_key_input.text_submitted.connect(func(_text): _on_submit_decryption_key())
	if _desktop_logoff_btn:    _desktop_logoff_btn.pressed.connect(_on_log_off)
	if _desktop_previous_reports_btn: _desktop_previous_reports_btn.pressed.connect(_on_previous_reports_open)
	if _power_off_btn:         _power_off_btn.pressed.connect(_on_exit_computer)
	if _desktop_shutdown_btn:  _desktop_shutdown_btn.pressed.connect(_on_exit_computer)
	
	# ─── CONNECT RECOVER_DATA.EXE ICON (if it exists in the scene) ──
	var recover_btn = _desktop_view.find_child("RecoverDataIcon", true, false)
	if recover_btn:
		recover_btn.pressed.connect(_on_recover_data_open)
	_add_memo_icon()

	# Check if an EXECUTE OVERLOAD button was already added (from a previous session)
	var overload_btn = _desktop_view.find_child("OverloadExec", true, false)
	if overload_btn and is_arvid_log_2_unlocked:
		overload_btn.visible = true
	elif overload_btn:
		overload_btn.visible = false
	if _btn_correlate:    _btn_correlate.pressed.connect(_on_correlate_data)
	if _submit_key_btn:   _submit_key_btn.pressed.connect(_on_submit_decryption_key)
	
	_normal_rect = Rect2(_main_window.position, _main_window.size)
	
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
	if _player and not _camera_holder:
		_camera_holder = _player.get_node_or_null("CameraHolder")
	
	# ─── TASK: GLOBAL BUTTON CLICK SOUND ─────────────────────────
	# Wire every Button under the computer UI to play ui_click_mx_3.ogg.
	_connect_ui_click_sounds()
	_apply_win95_look()


# ─────────────────────────────────────────────────────────────────────────────
# OPEN / CLOSE
# ─────────────────────────────────────────────────────────────────────────────

func open_computer() -> void:
	if not is_inside_tree():
		var main_loop = Engine.get_main_loop()
		if main_loop is SceneTree:
			var root = main_loop.root
			if root: root.add_child(self)
		if not is_inside_tree():
			var ml2 = Engine.get_main_loop()
			if ml2 is SceneTree:
				var scene = ml2.current_scene
				if scene: scene.add_child(self)
	
	visible = true
	is_open = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	var inv_ui = get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui and inv_ui.has_method("_close_inventory") and inv_ui.get("_is_open"):
		inv_ui._close_inventory()
	
	var hud_nodes = get_tree().get_nodes_in_group("hud")
	for h in hud_nodes:
		h.visible = false
	
	if _player:
		_player.set_process_input(false)
		_player.set_physics_process(false)
	
	if current_user == "":
		_show_login_screen()
	else:
		_show_desktop()
	
	_status_label.text = "Ready"
	print("[ComputerUI] Computer opened. current_user='%s'" % current_user)


func close_computer() -> void:
	visible = false
	is_open = false
	
	if _camera_holder and _original_camera_transform != Transform3D():
		var tween = create_tween()
		tween.set_parallel(false)
		tween.tween_property(_camera_holder, "global_transform", _original_camera_transform, 0.5)
		tween.finished.connect(_on_stand_tween_completed)
	else:
		_restore_player_controls()
	
	computer_closed.emit()
	print("[ComputerUI] Computer closed.")


# ─────────────────────────────────────────────────────────────────────────────
# LOGIN SCREEN
# ─────────────────────────────────────────────────────────────────────────────

func _show_login_screen() -> void:
	_login_screen.visible = true
	_desktop_view.visible = false
	_main_window.visible = false
	_username_input.text = ""
	_password_input.text = ""
	_login_error.text = ""


func _on_login_submit() -> void:
	var user = _username_input.text.strip_edges().to_upper()
	# ─── BUG 5 FIX: CASE-INSENSITIVE PASSWORD ──────────────────────
	# Passwords are now normalized to UPPERCASE before comparison, so
	# "passkey1", "PassKey1", and "PASSKEY1" all work.
	var pw = _password_input.text.strip_edges().to_upper()
	
	if not VALID_CREDENTIALS.has(user):
		_login_error.text = "INVALID USERNAME"
		_play_error_sound()
		_trigger_login_tutorial()
		return
	
	if VALID_CREDENTIALS[user] != pw:
		_login_error.text = "INVALID PASSWORD"
		_play_error_sound()
		_trigger_login_tutorial()
		return
	
	current_user = user
	_login_error.text = ""
	print("[ComputerUI] LOGIN SUCCESS: user='%s'" % current_user)
	
	# ─── TASK: LOGIN SUCCESS SOUND ─────────────────────────────
	# Plays login_successful.ogg only on valid credentials.
	_play_login_success_sound()
	
	if user == "LUND":
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_computer_used"):
			rm.on_computer_used()
		if not _eco_survey_completed:
			_eco_survey_completed = true
			print("[ComputerUI] Eco-survey marked as completed on LUND login.")
	elif user == "STENBERG":
		# ─── ISSUE 3 FIX: UNSANCTIONED DISCOVERIES SIDE-TRACK ──────────
		# Logging in with Arvid's credentials must advance the side-track
		# objective "Log in with Arvid's credentials". RoutineManager's
		# on_arvid_logged_in() handler exists but was never called, so the
		# objective stayed permanently unchecked. Fire it now.
		var rm_arvid = get_node_or_null("/root/RoutineManager")
		if rm_arvid and rm_arvid.has_method("on_arvid_logged_in"):
			rm_arvid.on_arvid_logged_in()
			print("[ComputerUI] STENBERG login notified to RoutineManager (side-track step unlocked).")
	
	_show_desktop()


# ─────────────────────────────────────────────────────────────────────────────
# DESKTOP
# ─────────────────────────────────────────────────────────────────────────────

## Whether the Day 2 previous-reports file has been fully read (opened once).
## When true, RoutineManager.on_previous_reports_read() has been fired and the
## desktop icon can be hidden so the player cannot re-read it accidentally.
var _previous_reports_read: bool = false

## Opens the NEST_REPORTS.TXT archive containing the previous researcher's
## nest survey data. Reading this file completes Day 2 Step 1.
func _on_previous_reports_open() -> void:
	_desktop_view.visible = false
	_main_window.visible = true
	_main_window.find_child("TitleLabel", true, false).text = "NEST_REPORTS.TXT"
	_status_label.text = "Opening: NEST_REPORTS.TXT — Previous Survey Archive..."
	_data_entry_panel.visible = false
	_recovery_panel.visible = false
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	_content_display.text = PREVIOUS_NEST_REPORTS

	# ─── DAY 2 STEP 1 COMPLETION ──────────────────────────────────
	# Opening the report is the "read all" trigger for the first Day 2
	# objective. Notify the RoutineManager so it can unlock the cabin
	# door and transition to the Nest Alpha objective.
	if not _previous_reports_read:
		_previous_reports_read = true
		var rm := get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_previous_reports_read"):
			rm.on_previous_reports_read()
			print("[ComputerUI] Previous nest reports read. Day 2 Step 1 notified to RoutineManager.")


## MEMO.TXT on the LUND desktop, right after FIELD_LOG.EXE: the office's
## welcome to Phase 2 (LUND_MEMO).
func _add_memo_icon() -> void:
	if _desktop_view.find_child("MemoIcon", false, false):
		return
	var memo := Button.new()
	memo.name = "MemoIcon"
	memo.text = "MEMO.TXT"
	memo.visible = false
	memo.pressed.connect(_on_memo_open)
	_desktop_view.add_child(memo)
	if _desktop_field_log_btn:
		_desktop_view.move_child(memo, _desktop_field_log_btn.get_index() + 1)


func _on_memo_open() -> void:
	_desktop_view.visible = false
	_main_window.visible = true
	_main_window.find_child("TitleLabel", true, false).text = "MEMO.TXT"
	_status_label.text = "Opening: MEMO.TXT — Field Office..."
	_data_entry_panel.visible = false
	_recovery_panel.visible = false
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	_content_display.text = LUND_MEMO


func _show_desktop() -> void:
	_login_screen.visible = false
	_main_window.visible = false
	_desktop_view.visible = true
	_reflow_desktop_icons.call_deferred()

	# ─── PREVIOUS NEST REPORTS (Day 2 Step 1 gate) ──────────────────
	# The NEST_REPORTS.TXT icon is only available to the LUND profile and
	# only while the Day 2 report-reading objective is still pending.
	var show_reports := false
	if current_user == "LUND":
		var rm := get_node_or_null("/root/RoutineManager")
		if rm and "day2_step" in rm and rm.day2_step == 1:
			show_reports = true
	_desktop_previous_reports_btn.visible = show_reports
	
	_desktop_field_log_btn.visible = (current_user == "LUND")
	var memo_btn := _desktop_view.find_child("MemoIcon", false, false) as Button
	if memo_btn:
		memo_btn.visible = (current_user == "LUND")
	_desktop_recycle_btn.visible = (current_user == "STENBERG")
	_desktop_logoff_btn.visible = true
	
	# Show RECOVER_DATA.EXE for the STENBERG user
	var recover_btn = _desktop_view.find_child("RecoverDataIcon", true, false)
	if recover_btn:
		recover_btn.visible = (current_user == "STENBERG")
	
	# Show EXECUTE OVERLOAD if logs have been decrypted
	var overload_btn = _desktop_view.find_child("OverloadExec", true, false)
	if overload_btn:
		overload_btn.visible = (current_user == "STENBERG" and is_arvid_log_2_unlocked)
	
	# ─── TASK 5: SHOW RESTORED_DATA.TXT IF LOGS WERE RESTORED ──────
	# Once Arvid's logs have been successfully restored, the persistent
	# restored_data.txt icon stays on the STENBERG desktop so the player
	# can re-read the notes without re-entering the password.
	var restored_icon := _desktop_view.find_child("RestoredDataIcon", true, false) as Button
	if restored_icon:
		restored_icon.visible = (current_user == "STENBERG" and is_arvid_log_1_unlocked)


func _on_exit_computer() -> void:
	close_computer()

func _on_log_off() -> void:
	current_user = ""
	_show_login_screen()


# ─────────────────────────────────────────────────────────────────────────────
# RESTORE PLAYER CONTROLS
# ─────────────────────────────────────────────────────────────────────────────

func _on_stand_tween_completed() -> void:
	_restore_player_controls()

func _restore_player_controls() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var hud_nodes = get_tree().get_nodes_in_group("hud")
	for h in hud_nodes:
		h.visible = true
	if _player:
		_player.set_process_input(true)
		_player.set_physics_process(true)
		if _original_camera_transform != Transform3D():
			var orig_euler = _original_camera_transform.basis.get_euler()
			_player.global_rotation.y = orig_euler.y
			_player.global_rotation.x = 0.0
			_player.global_rotation.z = 0.0
			if _camera_holder:
				_camera_holder.rotation = Vector3(orig_euler.x, 0.0, 0.0)
		else:
			if _camera_holder:
				_camera_holder.rotation.z = 0.0


# ─────────────────────────────────────────────────────────────────────────────
# WINDOW CONTROLS
# ─────────────────────────────────────────────────────────────────────────────

func _on_minimize() -> void:
	if _is_minimized:
		_main_window.size = _normal_rect.size
		_is_minimized = false
		_status_label.text = "Restored"
	else:
		_normal_rect.size = _main_window.size
		_main_window.size.y = 22
		_is_minimized = true
		_status_label.text = "Minimized"

func _on_maximize() -> void:
	if _is_maximized:
		_main_window.position = _normal_rect.position
		_main_window.size = _normal_rect.size
		_is_maximized = false
		_status_label.text = "Restored"
	else:
		_normal_rect = Rect2(_main_window.position, _main_window.size)
		var vp_size = get_viewport().get_visible_rect().size
		_main_window.position = Vector2(0, 0)
		_main_window.size = vp_size
		_is_maximized = true
		_status_label.text = "Maximized"

func _on_close_app_window() -> void:
	_main_window.visible = false
	_desktop_view.visible = true


# ─────────────────────────────────────────────────────────────────────────────
# FIELD_LOG.EXE
# ─────────────────────────────────────────────────────────────────────────────

func _on_field_log_open() -> void:
	var rm = get_node_or_null("/root/RoutineManager")
	if rm:
		if not always_pass_correlation:
			if not _eco_survey_completed:
				_show_access_denied("FIELD_LOG.EXE requires completed eco-survey baseline.")
				return
	
	_desktop_view.visible = false
	_main_window.visible = true
	_main_window.find_child("TitleLabel", true, false).text = "FIELD_LOG.EXE"
	_status_label.text = "Opening: FIELD_LOG.EXE — Data Correlation Utility..."
	
	$MainWindow/HBoxContainer/ContentPanel.visible = false
	_data_entry_panel.visible = true
	_recovery_panel.visible = false
	
	# ─── SHUFFLE ANOMALY OPTIONS (Issue 7) ────────────────────────
	# The three correct answers (Photophobia, Covert Observation,
	# Audio-Specific Abnormalities) previously sat at indices 1-3 —
	# clustered right after the default "Standard Biological Behavior".
	# Each form open now randomizes the non-baseline options so the
	# correct answers are never all grouped at the top, making the
	# puzzle harder to brute-force. Validation uses text (not index),
	# so shuffling is safe.
	_populate_shuffled_anomaly_dropdowns()
	
	# Reset all dropdowns to index 0 and clear all population inputs
	if _dropdown_anomaly_a: _dropdown_anomaly_a.selected = 0
	if _pop_input_a: _pop_input_a.text = ""
	if _dropdown_anomaly_b: _dropdown_anomaly_b.selected = 0
	if _pop_input_b: _pop_input_b.text = ""
	if _dropdown_anomaly_c: _dropdown_anomaly_c.selected = 0
	if _pop_input_c: _pop_input_c.text = ""
	
	if _nest_data_uploaded:
		_status_label.text = "FIELD_LOG.EXE — Nest Data Uploaded"
		$MainWindow/HBoxContainer/ContentPanel.visible = true
		_data_entry_panel.visible = false
		_content_display.text = "[b]NEST DOCUMENTATION CORRELATION COMPLETE[/b]\n\n"
		_content_display.text += "All three nest observations have been successfully archived."
		return
	
	_status_label.text = "FIELD_LOG.EXE — Enter Nest Observation Data"
	_data_entry_panel.visible = true
	$MainWindow/HBoxContainer/ContentPanel.visible = false
	print("[ComputerUI] FIELD_LOG.EXE opened with nest correlation form.")


## ─── ANOMALY OPTION SHUFFLING (Issue 7) ───────────────────────────────
## Repopulates all three anomaly dropdowns with "Standard Biological
## Behavior" pinned at index 0 (the no-symptom baseline) and the remaining
## 11 survey categories in a RANDOM order. Called every time FIELD_LOG.EXE
## is opened so the correct answers (Photophobia, Covert Observation,
## Audio-Specific Abnormalities) are never clustered at the top.
## Validation in _validate_nest_correlation() matches by TEXT, not index,
## so shuffling is safe.
func _populate_shuffled_anomaly_dropdowns() -> void:
	# Build a pool of all non-baseline options
	var baseline: String = ANOMALY_OPTIONS[0]
	var shuffled: Array[String] = []
	for i in range(1, ANOMALY_OPTIONS.size()):
		shuffled.append(ANOMALY_OPTIONS[i])
	
	# Fisher-Yates shuffle
	for i in range(shuffled.size() - 1, 0, -1):
		var j: int = randi_range(0, i)
		var tmp: String = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	
	# Rebuild each dropdown: baseline at index 0, shuffled after
	for dropdown in [_dropdown_anomaly_a, _dropdown_anomaly_b, _dropdown_anomaly_c]:
		if not dropdown:
			continue
		dropdown.clear()
		dropdown.add_item(baseline, 0)
		for i in shuffled.size():
			dropdown.add_item(shuffled[i], i + 1)
		dropdown.selected = 0


func _show_access_denied(reason: String) -> void:
	_desktop_view.visible = false
	_main_window.visible = true
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	_data_entry_panel.visible = false
	_recovery_panel.visible = false
	_status_label.text = "ACCESS DENIED"
	_content_display.text = "[color=red][b]ACCESS DENIED[/b][/color]\n\n%s" % reason


# ─────────────────────────────────────────────────────────────────────────────
# RECYCLE BIN
# ─────────────────────────────────────────────────────────────────────────────

var _arvid_recycle_bin_read: bool = false

func _on_trash() -> void:
	_desktop_view.visible = false
	_main_window.visible = true
	_main_window.find_child("TitleLabel", true, false).text = "Recycle Bin"
	_status_label.text = "Opening: Recycle Bin..."
	_data_entry_panel.visible = false
	_recovery_panel.visible = false
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	
	# ─── ISSUE 3 FIX: MARK ARVID'S LOGS AS READ ────────────────────
	# Opening the Recycle Bin (Arvid's recovered log entries) is the
	# "Read logs" trigger for the Unsanctioned Discoveries side-track.
	# RoutineManager's on_arvid_logs_read() handler exists but was never
	# wired to this UI action, so the objective stayed permanently
	# unchecked. Fire it on first open only.
	if not _arvid_recycle_bin_read:
		_arvid_recycle_bin_read = true
		var rm_logs = get_node_or_null("/root/RoutineManager")
		if rm_logs and rm_logs.has_method("on_arvid_logs_read"):
			rm_logs.on_arvid_logs_read()
			print("[ComputerUI] Arvid's Recycle Bin logs read — notified RoutineManager (side-track step unlocked).")
	
	_content_display.text = RECYCLE_BIN_CONTENTS


# ─────────────────────────────────────────────────────────────────────────────
# CORRELATION LOGIC — Validates ALL 3 static nest rows from .tscn
# ─────────────────────────────────────────────────────────────────────────────

## Validates all 3 nest rows against NEST_ANSWER_KEY.
## Each row has its own anomaly dropdown and population LineEdit.
## All 3 must be correct for the correlation to succeed.
func _validate_nest_correlation() -> bool:
	var all_correct := true
	
	var nest_rows := [
		{ "name": "Nest Alpha", "anomaly": _dropdown_anomaly_a, "pop": _pop_input_a },
		{ "name": "Nest Beta",  "anomaly": _dropdown_anomaly_b, "pop": _pop_input_b },
		{ "name": "Nest Gamma", "anomaly": _dropdown_anomaly_c, "pop": _pop_input_c },
	]
	
	for row in nest_rows:
		var nest_name: String = row.name
		var dropdown: OptionButton = row.anomaly
		var line_edit: LineEdit = row.pop
		
		var selected_anomaly: String = dropdown.get_item_text(dropdown.selected) if dropdown else ""
		var entered_pop: String = line_edit.text.strip_edges() if line_edit else ""
		
		var expected = NEST_ANSWER_KEY.get(nest_name, {})
		if expected.is_empty():
			all_correct = false
			continue
		
		var expected_anomaly: String = expected.get("anomaly", "")
		var expected_pop: String = expected.get("pop", "")
		
		var anomaly_ok: bool = (selected_anomaly == expected_anomaly)
		var pop_ok: bool = (entered_pop.to_lower() == expected_pop.to_lower())
		
		if not anomaly_ok or not pop_ok:
			all_correct = false
	
	return all_correct


func _on_correlate_data() -> void:
	print("[ComputerUI] CORRELATE DATA BUTTON PRESSED")
	
	_nest_correlation_check()


## Validates all 3 nest rows. On success: calls _on_nest_correlation_success().
## On failure: shows error text.
func _nest_correlation_check() -> void:
	if _validate_nest_correlation():
		_on_nest_correlation_success()
	else:
		_on_nest_correlation_failure()


## Determines whether the current correlation is the Day 2 nest-data upload
## (the trigger for the cinematic loading → fade → Night 2 time-skip).
## Returns true only while the linear Day 2 sequence is active (main_objective
## >= 99 via RoutineManager), the sandbox mode has NOT started, and no night
## is currently active.
func _is_day2_nest_upload_trigger() -> bool:
	var rm := get_node_or_null("/root/RoutineManager")
	if rm and "is_day3_sandbox" in rm and rm.is_day3_sandbox:
		return false
	if not rm or "main_objective" not in rm or rm.main_objective < 99:
		return false
	var nm := get_node_or_null("/root/NightManager")
	if nm and nm.is_night_active:
		return false
	return true


## Runs the Day 2 cinematic time-skip from the black screen: snaps the
## loading bar to 100%, swaps the text to "Data processed.", fast-forwards
## to Night 2.1, holds in darkness for 3 seconds, then fades back over 3s.
## The skip only executes if it is currently Day 2 — otherwise it no-ops.
func _run_day2_night_skip_sequence(load_bar: ProgressBar = null, loading_label: Label = null, eyes: SleepCinematic = null) -> void:
	var nm := get_node_or_null("/root/NightManager")
	
	# ─── 1. SNAP BAR TO 100% + SWAP TEXT DURING BLACK HOLD ────────────
	# The screen is fully black at this point. The loading bar jumps to
	# 100% and the label reads "Data processed." while the player cannot
	# see it — matching the requested "3 seconds of completely dark screen"
	# phase. When the screen fades back in, the completed state is shown.
	if load_bar and is_instance_valid(load_bar):
		load_bar.value = 100.0
	if loading_label and is_instance_valid(loading_label):
		loading_label.text = "Data processed."
	
	# ─── 2. WHILE BLACK: FAST-FORWARD TIME TO NIGHT 2.1 ───────────────
	# Guard: only skip if we are still on Day 2 (night NOT yet active).
	# start_night(2) sets current_night=2, is_night_active=true, and calls
	# _force_game_time_to_night() which moves GameTime to dusk (0.5) and
	# emits night_started — the full transition into Night 2.
	if nm and not nm.is_night_active:
		if nm.has_method("start_night"):
			nm.start_night(2)
			print("[ComputerUI] Day 2 nest data uploaded — time fast-forwarded to Night 2.")
		else:
			print("[ComputerUI] NightManager has no start_night() — time-skip skipped.")
	else:
		print("[ComputerUI] Skipping Night 2 time-skip — it is no longer Day 2.")
	
	# ─── 3. HOLD IN BLACK FOR 3 SECONDS ────────────────────────────────
	# This starts AFTER start_night(2) so the time transition itself is
	# hidden behind the black screen. The bar/text change above is also
	# invisible during this hold — the player sees it only after the
	# fade-back begins.
	await get_tree().create_timer(3.0).timeout
	
	# ─── 4. FADE BACK OVER 3 SECONDS ─────────────────────────────────
	# (Dozed off at the computer: the eyes open again instead.)
	var hud := get_tree().get_first_node_in_group("hud")
	if eyes:
		if hud and hud.has_method("fade_from_black"):
			await hud.fade_from_black(0.05)
		await eyes.open_eyes()
	elif hud and hud.has_method("fade_from_black"):
		await hud.fade_from_black(3.0)
	else:
		await get_tree().create_timer(3.0).timeout


func _on_nest_correlation_success() -> void:
	_play_success_sound()
	_nest_data_uploaded = true
	nest_data_uploaded = true
	_status_label.text = "CORRELATION ACCEPTED"
	
	# ─── CINEMATIC LOADING + TIME-SKIP SEQUENCE ──────────────────────
	# On the Day 2 nest-data upload, run the full loading-bar cinematic
	# (progress bar → fade to black → Night 2.1 time skip → fade back →
	# "Analysis complete"). The RoutineManager advance (which unlocks the
	# "Lock the door" step) is deferred until the sequence finishes so the
	# objective doesn't flip mid-transition.
	var is_day2_upload := _is_day2_nest_upload_trigger()
	
	if is_day2_upload:
		# Hide the correlation form and show the loading screen.
		_data_entry_panel.visible = false
		$MainWindow/HBoxContainer/ContentPanel.visible = false
		
		# ─── CINEMATIC LOADING + FADE-TO-BLACK TIMELINE ─────────────
		# EXACT desired sequence:
		#   0.0s   Loading screen appears: "Processing data, please wait..."
		#          above a loading bar (before any fade).
		#   0.0→3s Loading bar fills slowly (~0.5%/s = 1% every 2s) WHILE
		#          the whole screen fades to black over 3s (as if falling
		#          asleep). Bar reaches ~1.5% by full black.
		#   3.0→6s Complete black screen. During these 3 seconds the bar
		#          jumps to 100%, the text changes to "Data processed.",
		#          and Day 2 advances to Night 2.1.
		#   6.0→9s Fade back from black over 3s. Player now sees the
		#          "Data processed." screen and night has fallen.
		
		# ─── 0. SHOW LOADING SCREEN (visible before the fade starts) ─
		var loading_label := Label.new()
		loading_label.name = "LoadingLabel"
		loading_label.text = "Processing data, please wait..."
		loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		loading_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		loading_label.offset_top = 70.0
		loading_label.offset_bottom = 100.0
		_main_window.add_child(loading_label)
		
		var load_bar := ProgressBar.new()
		load_bar.name = "LoadingBar"
		load_bar.min_value = 0.0
		load_bar.max_value = 100.0
		load_bar.value = 0.0
		load_bar.show_percentage = true
		load_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		load_bar.offset_left = -140.0
		load_bar.offset_top = -10.0
		load_bar.offset_right = 140.0
		load_bar.offset_bottom = 10.0
		_main_window.add_child(load_bar)
		
		# ─── PHASE 1: SLOW BAR FILL + FADE TO BLACK OVER 3s ─────────
		# The bar fills at 0.5%/s (1% every 2 seconds) → 1.5% by the time
		# the screen reaches full black. The slow-fill tween runs in
		# parallel with the fade-to-black.
		# ─── FADE-OVERLAY VISIBILITY FIX ─────────────────────────────
		# open_computer() sets every node in the "hud" group to
		# visible=false (so the game UI doesn't cover the computer screen).
		# The HUD's _fade_overlay is a CHILD of the HUD CanvasLayer, so
		# it is also hidden. When fade_to_black() tweened the overlay's
		# alpha below, nothing rendered — the screen never went black.
		# Temporarily re-show the HUD during the cinematic so the fade
		# overlay is visible, then re-hide it once the sequence completes.
		var hud := get_tree().get_first_node_in_group("hud")
		var hud_nodes_before_fade: Array[Node] = get_tree().get_nodes_in_group("hud")
		for h in hud_nodes_before_fade:
			h.visible = true
		
		var slow_fill := create_tween()
		slow_fill.tween_property(load_bar, "value", 1.5, 3.0)
		
		# Dozing off while it loads: heavy blinks (as going to bed does,
		# SleepCinematic), the eyes shut, then black behind them.
		var eyes := SleepCinematic.new()
		eyes.name = "UploadDoze"
		eyes.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(eyes)
		await eyes.doze_off()
		if hud and hud.has_method("fade_to_black"):
			await hud.fade_to_black(0.05)
		
		# Kill the slow-fill tween (should already be near 1.5%) — the
		# black-screen phase will snap it to 100%.
		if slow_fill and slow_fill.is_valid():
			slow_fill.kill()
		
		# ─── PHASE 2-3: BLACK HOLD + NIGHT TRANSITION + FADE BACK ────
		await _run_day2_night_skip_sequence(load_bar, loading_label, eyes)
		eyes.queue_free()
		
		# ─── TASK: LOGGING COMPLETE SOUND ─────────────────────────────
		# The loading bar hit 100%, the data was processed, and Night 2
		# has fallen. Play logging_complete.ogg at this exact moment.
		_on_logging_done()
		
		# ─── RE-HIDE THE HUD ─────────────────────────────────────────
		# The computer UI is still open, so the game HUD must be hidden
		# again now that the fade sequence has completed.
		for h in hud_nodes_before_fade:
			if is_instance_valid(h):
				h.visible = false
		
		# Cleanup loading nodes (safe no-ops if already freed)
		if is_instance_valid(loading_label):
			loading_label.queue_free()
		if is_instance_valid(load_bar):
			load_bar.queue_free()
	
	# ─── 5. COMPLETE: Notify RoutineManager + show "Analysis complete" ──
	var rm := get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("on_nest_data_uploaded"):
		rm.on_nest_data_uploaded()
	
	_status_label.text = "ANALYSIS COMPLETE"
	_data_entry_panel.visible = false
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	_content_display.text = "[b]ANALYSIS COMPLETE — NEST DOCUMENTATION CORRELATION SUCCESSFUL[/b]\n\n"
	_content_display.text += "Nest Alpha → Photophobia ✓ (Pop: 6)\n"
	_content_display.text += "Nest Beta → Covert Observation ✓ (Pop: Unknown)\n"
	_content_display.text += "Nest Gamma → Audio-Specific Abnormalities ✓ (Pop: 3)\n\n"
	_content_display.text += "Data uploaded."


func _on_nest_correlation_failure() -> void:
	_play_error_sound()
	_status_label.text = "ERROR: Data correlation mismatch. Review notebook entries."
	_content_display.text = "[color=red][b]ERROR: Data correlation mismatch. Review notebook entries.[/b][/color]"


func _on_correlation_success(night: int) -> void:
	_play_success_sound()
	_nest_data_uploaded = true
	nest_data_uploaded = true
	
	var profile_id = "night_%d" % night
	if _unlocked_profiles.has(profile_id):
		_status_label.text = "LOG ALREADY DECRYPTED"
	else:
		_status_label.text = "CORRELATION ACCEPTED"
		_unlocked_profiles[profile_id] = true
	
	if night == 1 and not _eco_survey_completed:
		_eco_survey_completed = true
		_trigger_phone_drop_event()
	
	var rm = get_node_or_null("/root/RoutineManager")
	if night == 2 and (_eco_survey_completed or (rm and rm.get("nests_documented") >= 3)):
		if rm and rm.has_method("on_nest_data_uploaded"):
			rm.on_nest_data_uploaded()
	
	_data_entry_panel.visible = false
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	
	var reward = TACTICAL_LOG_REWARDS.get(night, null)
	if reward:
		_content_display.text = "[b]" + reward["title"] + "[/b]\n\n" + reward["body"]
	else:
		_content_display.text = "[b]NIGHT " + str(night) + " — DATA CORRELATION ACCEPTED[/b]\n\nNo additional intelligence available."


func _on_correlation_failure() -> void:
	_play_error_sound()
	_status_label.text = "CRITICAL ERROR: DATA ANOMALY DETECTED"
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	_data_entry_panel.visible = false
	_content_display.text = "[color=red][b]CRITICAL ERROR: DATA ANOMALY DETECTED.[/b][/color]\n\nCORRELATION REJECTED.\n\n---\n[color=gray]Error Code: 0xDEADBEEF[/color]"
	_nest_data_uploaded = false
	nest_data_uploaded = false


# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

func _get_current_night() -> int:
	var nm = get_node_or_null("/root/NightManager")
	if nm and "current_night" in nm: return nm.current_night
	return 1

func _play_success_sound() -> void:
	var stream = load("res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Electronics/computer_beep_1.ogg")
	if stream:
		var p = AudioStreamPlayer.new(); p.bus = "SFX"; p.stream = stream; add_child(p)
		p.play(); p.finished.connect(p.queue_free)

func _play_error_sound() -> void:
	var stream = load("res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Electronics/analog_computer_beep_3.ogg")
	if stream:
		var p = AudioStreamPlayer.new(); p.bus = "SFX"; p.stream = stream; add_child(p)
		p.play(); p.finished.connect(p.queue_free)

## Plays login_successful.ogg when credentials are accepted.
func _play_login_success_sound() -> void:
	var stream = load("res://assets/audio/objects/login_successful.ogg")
	if stream:
		var p = AudioStreamPlayer.new(); p.bus = "SFX"; p.stream = stream; add_child(p)
		p.play(); p.finished.connect(p.queue_free)

## The data is logged and night has fallen: the chime, then a thought.
func _on_logging_done() -> void:
	_play_logging_complete_sound()
	get_tree().create_timer(1.5).timeout.connect(Monologue.think.bind(
		"One more night in this luxurious cottage and then back to my own place.", null, 5.0, "one_more_night"))


## Plays logging_complete.ogg when the nest-data loading bar reaches 100%.
func _play_logging_complete_sound() -> void:
	var stream = load("res://assets/audio/objects/logging_complete.ogg")
	if stream:
		var p = AudioStreamPlayer.new(); p.bus = "SFX"; p.stream = stream; add_child(p)
		p.play(); p.finished.connect(p.queue_free)

## Plays ui_click_mx_3.ogg for any computer UI button press.
func _play_ui_click() -> void:
	var stream = load("res://assets/audio/computer/ui_click_mx_3.ogg")
	if stream:
		var p = AudioStreamPlayer.new(); p.bus = "SFX"; p.stream = stream; add_child(p)
		p.play(); p.finished.connect(p.queue_free)

## Connects _play_ui_click to every Button under this CanvasLayer.
## Idempotent via a per-button meta flag. Called at the end of _ready().
func _connect_ui_click_sounds() -> void:
	for btn in find_children("*", "Button", true, false):
		if btn is Button and not btn.has_meta("_ui_click_connected"):
			btn.set_meta("_ui_click_connected", true)
			btn.pressed.connect(_play_ui_click)


func _trigger_phone_drop_event() -> void:
	# Kept for compatibility with _on_correlation_success.
	# The phone drop is now handled by the eco-survey completion on login.
	pass


func _trigger_login_tutorial() -> void:
	var tm := get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("trigger"):
		tm.trigger("pc_login_hint")
	if _login_error:
		_login_error.text = "ACCESS DENIED. HINT: Press [J] to check your Notebook for credentials."


# ─────────────────────────────────────────────────────────────────────────────
# RECOVER_DATA.EXE
# ─────────────────────────────────────────────────────────────────────────────

## Called when the RECOVER_DATA.EXE desktop icon is clicked.
## Shows the recovery panel (key input + submit button).
func _on_recover_data_open() -> void:
	_desktop_view.visible = false
	_main_window.visible = true
	_main_window.find_child("TitleLabel", true, false).text = "RECOVER_DATA.EXE"
	_status_label.text = "Opening: RECOVER_DATA.EXE — File Restoration Utility..."
	
	$MainWindow/HBoxContainer/ContentPanel.visible = false
	_data_entry_panel.visible = false
	_recovery_panel.visible = true
	_key_input.text = ""
	_recovery_status.text = ""

func _on_submit_decryption_key() -> void:
	# ─── TASK 4 FIX: CASE-INSENSITIVE DECRYPTION KEY ────────────────
	# The password is normalized to lowercase on both sides, so
	# "linnea_and_maja", "Linnea_and_Maja" and "LINNEA_AND_MAJA" all work.
	var key = _key_input.text.strip_edges().to_lower()
	if key == ARVID_DECRYPTION_KEY.to_lower():
		_recovery_status.text = "DECRYPTION SUCCESSFUL. Arvid Stenberg's logs restored."
		is_arvid_log_1_unlocked = true
		is_arvid_log_2_unlocked = true
		# ─── TASKS 5 & 6: SHARE THE RESTORED-NOTES DISPLAY ──────────
		# The restored notes are now rendered through the shared
		# _show_arvid_restored_notes() helper, which:
		#   - Displays ARVID_LOG_01 + ARVID_LOG_02 (Task 5 persistence)
		#   - Creates the persistent restored_data.txt desktop icon
		#   - Fires RoutineManager.on_arvid_logs_read() to complete the
		#     "Read logs" objective (Task 6)
		_show_arvid_restored_notes()
		_play_success_sound()
		
		# ─── SHOW EXECUTE OVERLOAD BUTTON ON DESKTOP ────────────────
		# After decrypting Arvid's logs, the player gains access to the
		# Anchor Grid Overload executable. This button triggers the
		# overload on the deployed portable lamp.
		_show_overload_button()
	else:
		_recovery_status.text = "INVALID KEY — Access Denied"
		_play_error_sound()


## ─── TASKS 5 & 6: SHARED RESTORED-NOTES DISPLAY ─────────────────────
## Displays Arvid's restored logs in the content panel and creates the
## persistent restored_data.txt desktop icon. Once the data is restored
## the player does NOT need to re-enter the password — clicking the
## restored_data.txt icon calls this same helper directly.
##
## Also fires RoutineManager.on_arvid_logs_read() (Task 6) so the
## "Unsanctioned Discoveries" side-track objective "Read logs" officially
## clears. RoutineManager's internal arvid_logs_read guard prevents
## double-firing if the player views the notes multiple times.
func _show_arvid_restored_notes() -> void:
	_content_display.text = ARVID_LOG_01_SURVEY + "\n---\n\n" + ARVID_LOG_02_CRITICAL
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	_recovery_panel.visible = false
	_main_window.visible = true
	_desktop_view.visible = false
	_status_label.text = "RESTORED_DATA.TXT — Arvid Stenberg's recovered logs"
	
	# ─── TASK 5: CREATE PERSISTENT RESTORED_DATA.TXT DESKTOP ICON ──
	# Only create the icon once (guarded by is_arvid_log_1_unlocked).
	_show_restored_data_icon()
	
	# ─── TASK 6: ADVANCE THE "READ LOGS" OBJECTIVE ──────────────────
	# This is the exact point where the restored notes are displayed to
	# the player — the official "read" moment for the Unsanctioned
	# Discoveries side-track. RoutineManager's on_arvid_logs_read()
	# handler is idempotent (its arvid_logs_read flag prevents re-fire).
	var rm := get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("on_arvid_logs_read"):
		rm.on_arvid_logs_read()
		print("[ComputerUI] TASK 6: Restored Arvid logs read — RoutineManager notified on_arvid_logs_read().")


## Creates the restored_data.txt desktop button (idempotent).
## The button is only visible to the STENBERG user after the logs have
## been restored at least once. Clicking it re-opens the notes directly
## without requiring the password sequence again.
func _show_restored_data_icon() -> void:
	if not is_arvid_log_1_unlocked:
		return
	var icon := _desktop_view.find_child("RestoredDataIcon", true, false) as Button
	if not icon:
		icon = Button.new()
		icon.name = "RestoredDataIcon"
		icon.text = "restored_data.txt"
		icon.size.x = 140
		icon.add_theme_font_size_override("font_size", 11)
		# Position below RECOVER_DATA.EXE (160, 60) and EXECUTE OVERLOAD (160, 140)
		icon.position = Vector2(160, 220)
		icon.pressed.connect(_on_restored_data_open)
		if not icon.has_meta("_ui_click_connected"):
			icon.set_meta("_ui_click_connected", true)
			icon.pressed.connect(_play_ui_click)
		_desktop_view.add_child(icon)
		_reflow_desktop_icons()
		print("[ComputerUI] TASK 5: restored_data.txt desktop icon created.")


## Opens the restored data directly (skips the password sequence entirely).
## Called when the player clicks the restored_data.txt desktop icon.
func _on_restored_data_open() -> void:
	_desktop_view.visible = false
	_main_window.visible = true
	_show_arvid_restored_notes()


## Shows the EXECUTE OVERLOAD button on the desktop after Arvid's logs are decrypted.
func _show_overload_button() -> void:
	# Create the EXECUTE OVERLOAD button programmatically
	var overload_btn = Button.new()
	overload_btn.name = "OverloadExec"
	overload_btn.text = "EXECUTE OVERLOAD"
	overload_btn.size.x = 140
	overload_btn.add_theme_font_size_override("font_size", 11)
	# Position next to RECOVER_DATA.EXE icon
	overload_btn.position = Vector2(160, 140)
	overload_btn.pressed.connect(_on_execute_overload)
	if not overload_btn.has_meta("_ui_click_connected"):
		overload_btn.set_meta("_ui_click_connected", true)
		overload_btn.pressed.connect(_play_ui_click)
	_desktop_view.add_child(overload_btn)
	_reflow_desktop_icons()
	
	_status_label.text = "New executable available: EXECUTE OVERLOAD"
	print("[ComputerUI] EXECUTE OVERLOAD button added to desktop.")


## The portable light to overload: every lamp joins "portable_trap" when it
## loads (also ones still lying undeployed in the world), so the first one
## found could be the wrong one. Prefer a deployed and powered lamp, then a
## deployed one, then any.
func _best_portable_lamp() -> Node:
	var best: Node = null
	var best_score := -1
	for group_name in ["portable_lamp", "portable_trap"]:
		for lamp in get_tree().get_nodes_in_group(group_name):
			var score := 0
			if "is_deployed" in lamp and lamp.is_deployed:
				score += 2
			if "is_powered" in lamp and lamp.is_powered:
				score += 1
			if score > best_score:
				best = lamp
				best_score = score
	return best


## Called when the EXECUTE OVERLOAD button is pressed.
## Finds the portable lamp in the scene and triggers the overload.
## The lamp must be deployed for the overload to work.
func _on_execute_overload() -> void:
	print("[ComputerUI] EXECUTE OVERLOAD button pressed!")
	
	# ─── ISSUE 1 FIX: FIND THE LAMP IN BOTH GROUPS ────────────────
	# The portable lamp registers itself in the "portable_trap" group
	# (portable_lamp.gd _ready()), NOT "portable_lamp". Search both
	# groups so the overload button always finds the deployed lamp.
	var lamp = _best_portable_lamp()
	if not lamp:
		_show_access_denied("ERROR: No portable light source detected in the grid.")
		return
	
	# ─── DIAGNOSTIC: Log lamp state before guards ────────────────
	# Helpful for tracing which property causes a rejection. Shows the
	# exact lamp node found and its connection state.
	var lamp_has_deployed: bool = "is_deployed" in lamp
	var lamp_deployed: bool = lamp_has_deployed and lamp.is_deployed
	var lamp_has_powered: bool = "is_powered" in lamp
	var lamp_powered: bool = lamp_has_powered and lamp.is_powered
	print("[ComputerUI] Overload guard: lamp_name=%s | has_deployed=%s deployed=%s | has_powered=%s powered=%s" % [
		lamp.name, lamp_has_deployed, lamp_deployed, lamp_has_powered, lamp_powered])
	
	# Check if the lamp is deployed
	# FIX: Use the property-in-object check (Godot 4) instead of
	# has_method() — is_deployed is a plain bool var, not a method.
	# Also drop the invalid () call (a bool is a value, not a function).
	if not lamp_has_deployed or not lamp_deployed:
		_show_access_denied("ERROR: Portable light source is not deployed. Place it on the ground first.")
		return
	
	# ─── ISSUE 1 FIX: VERIFY THE LAMP IS POWERED ─────────────────
	# The portable light must be physically connected to the generator
	# via the PowerCable for the overload to actually drain fuel. If it
	# isn't powered, the overload would "succeed" silently but do nothing.
	if lamp_has_powered and not lamp_powered:
		_show_access_denied("ERROR: Portable light source is not connected to the generator grid. Connect the cable first.")
		return
	
	# Check if the lamp is already overloaded
	if lamp.has_method("is_overloaded") and lamp.is_overloaded:
		_show_access_denied("OVERLOAD ALREADY ACTIVE. Grid is at maximum draw.")
		return
	
	# Execute the overload
	if lamp.has_method("trigger_overload"):
		lamp.trigger_overload()
		_play_success_sound()
		_status_label.text = "OVERLOAD INITIATED — Grid at catastrophic draw."
		
		# ─── TASK 4: "TRIGGER TRAP" OBJECTIVE ─────────────────────────
		# The side-track's "Trigger trap" completes exactly when the
		# EXECUTE OVERLOAD button is successfully clicked. Notify
		# RoutineManager now that the grid override has been executed.
		var rm_trap = get_node_or_null("/root/RoutineManager")
		if rm_trap and rm_trap.has_method("on_trap_triggered"):
			rm_trap.on_trap_triggered()
			print("[ComputerUI] TASK 4: 'Trigger trap' objective fired.")
		
		# Show status in content display
		_desktop_view.visible = false
		_main_window.visible = true
		_content_display.text = "[b]ANCHOR GRID OVERLOAD INITIATED[/b]\n\n"
		_content_display.text += "The portable light source is now drawing maximum voltage.\n"
		_content_display.text += "Lamp output: 340% of rated load.\n\n"
		_content_display.text += "[color=red]WARNING: Generator fuel is draining at catastrophic rate![/color]\n\n"
		_content_display.text += "[color=gray][i]If you're reading this, it worked. It can't move while the light holds. Don't stand here watching it. Run for the willow. — A.[/i][/color]"
		$MainWindow/HBoxContainer/ContentPanel.visible = true
		_data_entry_panel.visible = false
		_recovery_panel.visible = false
	else:
		_show_access_denied("ERROR: Grid interface error. Cannot execute overload protocol.")


# ─────────────────────────────────────────────────────────────────────────────
# WINDOWS 95 LOOK (Win95Theme)
# ─────────────────────────────────────────────────────────────────────────────

const DESKTOP_ICON_KINDS := {
	"FieldLogIcon": "exe", "RecoverDataIcon": "exe", "RecycleBinIcon": "bin",
	"PreviousReportsIcon": "txt", "LogOffIcon": "logoff", "ShutDownIcon": "power",
	"RestoredDataIcon": "txt", "OverloadExec": "warn", "MemoIcon": "txt",
}
var _taskbar: Panel = null
var _start_menu: PopupMenu = null
var _clock_label: Label = null
var _start_entries: Array[Button] = []


func _apply_win95_look() -> void:
	var theme := Win95Theme.build()
	for child in get_children():
		if child is Control:
			(child as Control).theme = theme
			# The bevels are pixel art: no smoothing when they stretch.
			(child as Control).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# The scene's own boxes and colours would beat the theme: drop them
	# (keeping red warning text).
	for node in find_children("*", "Control", true, false):
		var control := node as Control
		for style in ["normal", "hover", "pressed", "focus", "disabled", "panel", "read_only"]:
			control.remove_theme_stylebox_override(style)
		for colour in ["font_color", "font_placeholder_color", "font_hover_color", "font_pressed_color"]:
			if control.has_theme_color_override(colour):
				var c := control.get_theme_color(colour)
				if not (c.r > 0.7 and c.g < 0.4 and c.b < 0.4):
					control.remove_theme_color_override(colour)
	var background := get_node_or_null("DesktopBackground") as ColorRect
	if background:
		background.color = Win95Theme.TEAL
	_desktop_view.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var desktop_title := _desktop_view.get_node_or_null("DesktopTitle") as Label
	if desktop_title:
		desktop_title.visible = false
	for button in _desktop_view.find_children("*", "Button", false, false):
		_style_icon(button)
	# The application window: a navy title bar, bevelled title buttons, a
	# flat menu bar, a grey status bar.
	var title_bar := _main_window.get_node_or_null("TitleBar") as ColorRect
	if title_bar:
		title_bar.color = Win95Theme.NAVY
		var title := title_bar.get_node_or_null("TitleLabel") as Label
		if title:
			title.add_theme_font_override("font", Win95Theme.font(true))
			title.add_theme_color_override("font_color", Win95Theme.LIGHT)
		for button in [_minimize_button, _maximize_button, _close_button]:
			if button:
				button.add_theme_stylebox_override("normal", Win95Theme.bevel(true, Win95Theme.FACE, 0))
				button.add_theme_stylebox_override("hover", Win95Theme.bevel(true, Win95Theme.FACE, 0))
				button.add_theme_stylebox_override("pressed", Win95Theme.bevel(false, Win95Theme.FACE, 0))
				button.add_theme_font_override("font", Win95Theme.font(true))
				button.add_theme_font_size_override("font_size", 13)
	var menu_bar := _main_window.get_node_or_null("MenuBar")
	if menu_bar:
		for entry in menu_bar.get_children():
			if entry is Button:
				Win95Theme.style_menu_entry(entry)
	var status_bar := _main_window.get_node_or_null("StatusBar") as ColorRect
	if status_bar:
		status_bar.color = Win95Theme.FACE
	# The login: a dialog with its own title bar.
	var dialog_title := ColorRect.new()
	dialog_title.name = "Win95TitleBar"
	dialog_title.color = Win95Theme.NAVY
	dialog_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	dialog_title.offset_left = 4
	dialog_title.offset_right = -4
	dialog_title.offset_top = 4
	dialog_title.offset_bottom = 30
	dialog_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dialog_label := Label.new()
	dialog_label.text = "  Enter Network Password"
	dialog_label.add_theme_font_override("font", Win95Theme.font(true))
	dialog_label.add_theme_color_override("font_color", Win95Theme.LIGHT)
	dialog_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dialog_title.add_child(dialog_label)
	_login_screen.add_child(dialog_title)
	var login_box := _login_screen.get_node_or_null("LoginVBox") as Control
	if login_box:
		login_box.offset_top = maxf(login_box.offset_top, 40.0)
	if _power_off_btn:
		_power_off_btn.position.y = maxf(_power_off_btn.position.y, 40.0)
	_build_taskbar(theme)


func _style_icon(button: Button) -> void:
	Win95Theme.style_desktop_icon(button, DESKTOP_ICON_KINDS.get(String(button.name), "exe"))


## Desktop icons in a column down the left, the way Windows lays them out.
func _reflow_desktop_icons() -> void:
	var y := 16.0
	for button in _desktop_view.find_children("*", "Button", false, false):
		if button.icon == null:
			_style_icon(button)
		if not button.visible:
			continue
		button.position = Vector2(16.0, y)
		y += 100.0


func _build_taskbar(theme: Theme) -> void:
	_taskbar = Panel.new()
	_taskbar.name = "Taskbar"
	_taskbar.theme = theme
	_taskbar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_taskbar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_taskbar.offset_top = -40
	add_child(_taskbar)
	var start := Button.new()
	start.name = "StartButton"
	start.text = "Start"
	start.icon = Win95Theme.start_logo()
	start.add_theme_font_override("font", Win95Theme.font(true))
	start.position = Vector2(4, 4)
	start.custom_minimum_size = Vector2(96, 32)
	start.size = start.custom_minimum_size
	start.pressed.connect(_open_start_menu)
	start.pressed.connect(_play_ui_click)
	_taskbar.add_child(start)
	var clock_box := Panel.new()
	clock_box.add_theme_stylebox_override("panel", Win95Theme.bevel(false, Win95Theme.FACE, 2))
	clock_box.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	clock_box.offset_left = -100
	clock_box.offset_right = -4
	clock_box.offset_top = 4
	clock_box.offset_bottom = -4
	_taskbar.add_child(clock_box)
	_clock_label = Label.new()
	_clock_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clock_box.add_child(_clock_label)
	_start_menu = PopupMenu.new()
	_start_menu.theme = theme
	_start_menu.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_start_menu.id_pressed.connect(_on_start_menu)
	_taskbar.add_child(_start_menu)
	_taskbar.visible = false


func _open_start_menu() -> void:
	_start_menu.clear()
	_start_entries.clear()
	for button in _desktop_view.find_children("*", "Button", false, false):
		if button.visible and button != _desktop_logoff_btn and button != _desktop_shutdown_btn:
			_start_menu.add_icon_item(button.icon, button.text, _start_entries.size())
			_start_entries.append(button)
	_start_menu.add_separator()
	for button in [_desktop_logoff_btn, _desktop_shutdown_btn]:
		if button and button.visible:
			_start_menu.add_icon_item(button.icon, button.text, _start_entries.size())
			_start_entries.append(button)
	for i in _start_menu.item_count:
		_start_menu.set_item_icon_max_width(i, 32)
	_start_menu.reset_size()
	var bar := _taskbar.get_global_rect()
	_start_menu.position = Vector2i(int(bar.position.x) + 4, int(bar.position.y) - _start_menu.size.y)
	_start_menu.popup()


func _on_start_menu(id: int) -> void:
	if id >= 0 and id < _start_entries.size() and is_instance_valid(_start_entries[id]):
		_start_entries[id].pressed.emit()


## The taskbar belongs to the desktop (not the login), and its clock runs on
## game time.
func _process(_delta: float) -> void:
	if not _taskbar:
		return
	_taskbar.visible = visible and not _login_screen.visible
	if _taskbar.visible and _clock_label:
		_clock_label.text = _clock_text()


func _clock_text() -> String:
	var gt := get_node_or_null("/root/GameTime")
	var progress: float = gt.cycle_progress if gt else 0.25
	# GameTime's clock: the day runs 06:00 (0.0) to midnight (0.5), 0.25
	# being 15:00; the night runs midnight to 05:00 (0.7 is 02:00).
	var hours: float = 6.0 + progress * 36.0 if progress < 0.5 else (progress - 0.5) * 10.0
	var h := int(hours) % 24
	var m := int((hours - floorf(hours)) * 60.0)
	return "%d:%02d %s" % [12 if h % 12 == 0 else h % 12, m, "AM" if h < 12 else "PM"]
