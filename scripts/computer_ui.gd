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

const ARVID_DECRYPTION_KEY: String = "STENBERG_1996"

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

const ANOMALY_OPTIONS: Array[String] = [
	"Standard Biological Behavior",
	"Photophobia",
	"Covert Observation",
	"Audio-Specific Abnormalities",
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

const ARVID_LOG_01_SURVEY: String = (
	"[b]SYSTEM RECOVERY: SECTOR 0x4F RESTORED[/b]\n"
	+ "[color=gray]LOG DATE: MARCH 14[/color]\n\n"
	+ "The regional office lied to me. This isn't an environmental assessment "
	+ "for a new logging permit. I found old corporate land surveys in the "
	+ "crawlspace dating back to the 70s. They've known about the 'Watcher' "
	+ "for decades. They didn't abandon this cabin because the timber dried up; "
	+ "they abandoned it because they couldn't keep the crews alive. \n\n"
	+ "Management left me out here alone to monitor the local grid spikes. "
	+ "They aren't trying to avoid the forest spirit—they're mapping its "
	+ "aggression threshold. I am a canary in a coal mine."
)

const ARVID_LOG_02_CRITICAL: String = (
	"[b]SYSTEM RECOVERY: MAIL_SPOOL_REBUILT[/b]\n"
	+ "[color=gray]LOG DATE: APRIL 02 (UNSENT)[/color]\n\n"
	+ "It knows I'm inside. It shadows the cabin lights every night. My "
	+ "flashlight only infuriates it now—the localized beam hurts it enough "
	+ "to trigger a blind charge. If it breaks through the shutters, a "
	+ "hand-lamp won't stop it.\n\n"
	+ "I've rewired the terminal interface to the main breaker. If I execute "
	+ "the grid override command, it will force the external porch floodlights "
	+ "to draw max voltage from the generator. It will create a blinding wall "
	+ "of light that should physically paralyze the thing in its tracks.\n\n"
	+ "But the power draw will burn through generator fuel at a catastrophic "
	+ "rate. If I trigger the trap, I'll have minutes to sprint into the yard, "
	+ "find its anchoring totem, and destroy it before the grid goes completely "
	+ "dark. If the fuel hits zero before the totem breaks..."
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
	if _desktop_logoff_btn:    _desktop_logoff_btn.pressed.connect(_on_log_off)
	if _power_off_btn:         _power_off_btn.pressed.connect(_on_exit_computer)
	if _desktop_shutdown_btn:  _desktop_shutdown_btn.pressed.connect(_on_exit_computer)
	if _btn_correlate:    _btn_correlate.pressed.connect(_on_correlate_data)
	if _submit_key_btn:   _submit_key_btn.pressed.connect(_on_submit_decryption_key)
	
	_normal_rect = Rect2(_main_window.position, _main_window.size)
	
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
	if _player and not _camera_holder:
		_camera_holder = _player.get_node_or_null("CameraHolder")


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
	
	var inv_ui = get_node_or_null("/root/CottageHorror/InventoryUI")
	if not inv_ui:
		inv_ui = get_node_or_null("/root/Main/InventoryUI")
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
	var pw = _password_input.text.strip_edges()
	
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
	
	if user == "LUND":
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_computer_used"):
			rm.on_computer_used()
		if not _eco_survey_completed:
			_eco_survey_completed = true
			print("[ComputerUI] Eco-survey marked as completed on LUND login.")
	
	_show_desktop()


# ─────────────────────────────────────────────────────────────────────────────
# DESKTOP
# ─────────────────────────────────────────────────────────────────────────────

func _show_desktop() -> void:
	_login_screen.visible = false
	_main_window.visible = false
	_desktop_view.visible = true
	
	_desktop_field_log_btn.visible = (current_user == "LUND")
	_desktop_recycle_btn.visible = (current_user == "STENBERG")
	_desktop_logoff_btn.visible = true


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
		_content_display.text += "All three Hazelnest observations have been successfully archived."
		return
	
	_status_label.text = "FIELD_LOG.EXE — Enter Nest Observation Data"
	_data_entry_panel.visible = true
	$MainWindow/HBoxContainer/ContentPanel.visible = false
	print("[ComputerUI] FIELD_LOG.EXE opened with nest correlation form.")


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

func _on_trash() -> void:
	_desktop_view.visible = false
	_main_window.visible = true
	_main_window.find_child("TitleLabel", true, false).text = "Recycle Bin"
	_status_label.text = "Opening: Recycle Bin..."
	_data_entry_panel.visible = false
	_recovery_panel.visible = false
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	
	_content_display.text = ""
	_content_display.text += "[b]RECOVERED DELETED LOG ENTRY[/b]\n"
	_content_display.text += "[color=red]WARNING: This file was marked for permanent deletion.[/color]\n\n"
	_content_display.text += "LOG ERR_04:\n\nThe nests are not natural.\n\n"
	_content_display.text += "They are arranged in a geometric pattern. "
	_content_display.text += "I've mapped seventeen of them now, and every single "
	_content_display.text += "one aligns to the same radial coordinates. "
	_content_display.text += "The center point is the cabin.\n\n"
	_content_display.text += "Something is watching the cabin.\n\n"
	_content_display.text += "I've tried reporting this to HQ three times. "
	_content_display.text += "No response. The radio only plays static — "
	_content_display.text += "the same tone, over and over.\n\n"
	_content_display.text += "I'm not supposed to be here anymore. "
	_content_display.text += "My rotation ended two weeks ago.\n\n"
	_content_display.text += "But the road... the road doesn't lead out anymore.\n\n"
	_content_display.text += "[color=red]— M. Arvidsson[/color]"


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


func _on_nest_correlation_success() -> void:
	_play_success_sound()
	_nest_data_uploaded = true
	nest_data_uploaded = true
	_status_label.text = "CORRELATION ACCEPTED"
	
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("on_nest_data_uploaded"):
		rm.on_nest_data_uploaded()
	
	_data_entry_panel.visible = false
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	_content_display.text = "[b]NEST DOCUMENTATION CORRELATION COMPLETE[/b]\n\n"
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
	var stream = load("res://assets/audio/UI/ui_click_success.ogg")
	if stream:
		var p = AudioStreamPlayer.new(); p.bus = "SFX"; p.stream = stream; add_child(p)
		p.play(); p.finished.connect(p.queue_free)

func _play_error_sound() -> void:
	var stream = load("res://assets/audio/UI/win98_error.ogg")
	if stream:
		var p = AudioStreamPlayer.new(); p.bus = "SFX"; p.stream = stream; add_child(p)
		p.play(); p.finished.connect(p.queue_free)


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

func _on_submit_decryption_key() -> void:
	var key = _key_input.text.strip_edges()
	if key == ARVID_DECRYPTION_KEY:
		_recovery_status.text = "DECRYPTION SUCCESSFUL. Arvid Stenberg's logs restored."
		is_arvid_log_1_unlocked = true
		is_arvid_log_2_unlocked = true
		_content_display.text = ARVID_LOG_01_SURVEY + "\n\n---\n\n" + ARVID_LOG_02_CRITICAL
		$MainWindow/HBoxContainer/ContentPanel.visible = true
		_recovery_panel.visible = false
		_play_success_sound()
	else:
		_recovery_status.text = "INVALID KEY — Access Denied"
		_play_error_sound()