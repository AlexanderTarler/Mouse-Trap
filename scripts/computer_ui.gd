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

## Who is currently logged in. "" = logged out, "LUND" = player, "STENBERG" = Arvid.
var current_user: String = ""

## Valid credentials. Key = username, value = password.
const VALID_CREDENTIALS: Dictionary = {
	"LUND": "PASSWORD",
	"STENBERG": "1996",
}

# ─────────────────────────────────────────────────────────────────────────────
# REFERENCES
# ─────────────────────────────────────────────────────────────────────────────

var _player: Node = null
var _original_camera_transform: Transform3D
var _camera_holder: Node3D = null

# ─────────────────────────────────────────────────────────────────────────────
# STATE FLAGS (preserved from original)
# ─────────────────────────────────────────────────────────────────────────────

var _unlocked_profiles: Dictionary = {}
var _eco_survey_completed: bool = false
var _nest_data_uploaded: bool = false
var is_arvid_log_1_unlocked: bool = false
var is_arvid_log_2_unlocked: bool = false

## Alias for external compatibility.
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
# ONREADY NODES — Main Window (applications open inside this)
# ─────────────────────────────────────────────────────────────────────────────

@onready var _main_window: Panel = $MainWindow
@onready var _content_display: RichTextLabel = $MainWindow/HBoxContainer/ContentPanel/ContentDisplay
@onready var _close_button: Button = $MainWindow/TitleBar/CloseButton
@onready var _minimize_button: Button = $MainWindow/TitleBar/MinimizeButton
@onready var _maximize_button: Button = $MainWindow/TitleBar/MaximizeButton
@onready var _status_label: Label = $MainWindow/StatusBar/StatusLabel

# Data entry (FIELD_LOG.EXE)
@onready var _data_entry_panel: Panel = $MainWindow/HBoxContainer/DataEntryPanel
@onready var _dropdown_source: OptionButton = $MainWindow/HBoxContainer/DataEntryPanel/DataEntryVBox/DropdownSource
@onready var _dropdown_anomaly: OptionButton = $MainWindow/HBoxContainer/DataEntryPanel/DataEntryVBox/DropdownAnomaly
@onready var _dropdown_frequency: OptionButton = $MainWindow/HBoxContainer/DataEntryPanel/DataEntryVBox/DropdownFrequency
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
# DATA & ANSWER KEYS (preserved from original)
# ─────────────────────────────────────────────────────────────────────────────

const NIGHT_ANSWER_KEY: Dictionary = {
	1: [0, 0, 0],
	2: [2, 2, 1],
}

const NEST_CONCEPT_ANSWER_KEY := [0, 1, 2]
const NEST_CONCEPT_CHOICES := [
	"Extreme Photophobia",
	"Active Observation",
	"Acoustic Mimicry",
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
	
	# Connect title bar buttons
	if _close_button:   _close_button.pressed.connect(_on_close_app_window)
	if _minimize_button: _minimize_button.pressed.connect(_on_minimize)
	if _maximize_button: _maximize_button.pressed.connect(_on_maximize)
	
	# Connect login
	if _login_button:   _login_button.pressed.connect(_on_login_submit)
	
	# Connect desktop icons
	if _desktop_field_log_btn: _desktop_field_log_btn.pressed.connect(_on_field_log_open)
	if _desktop_recycle_btn:   _desktop_recycle_btn.pressed.connect(_on_trash)
	if _desktop_logoff_btn:    _desktop_logoff_btn.pressed.connect(_on_log_off)
	if _power_off_btn:         _power_off_btn.pressed.connect(_on_exit_computer)
	if _desktop_shutdown_btn:  _desktop_shutdown_btn.pressed.connect(_on_exit_computer)
	
	# Connect correlation
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
	# Safety: ensure we're in the scene tree
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
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if _player:
		_player.set_process_input(false)
		_player.set_physics_process(false)
	
	# Branch: logged in → desktop, logged out → login
	if current_user == "":
		_show_login_screen()
	else:
		_show_desktop()
	
	_status_label.text = "Ready"
	print("[ComputerUI] Computer opened. current_user='%s'" % current_user)


func close_computer() -> void:
	visible = false
	
	if _camera_holder and _original_camera_transform != Transform3D():
		var tween = create_tween()
		tween.set_parallel(false)
		tween.tween_property(_camera_holder, "global_transform", _original_camera_transform, 0.5)\
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
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
	print("[ComputerUI] Login screen displayed.")


func _on_login_submit() -> void:
	var user = _username_input.text.strip_edges().to_upper()
	var pw = _password_input.text.strip_edges()
	
	if not VALID_CREDENTIALS.has(user):
		_login_error.text = "INVALID USERNAME"
		_play_error_sound()
		print("[ComputerUI] Login failed: unknown user '%s'" % user)
		return
	
	if VALID_CREDENTIALS[user] != pw:
		_login_error.text = "INVALID PASSWORD"
		_play_error_sound()
		print("[ComputerUI] Login failed: wrong password for '%s'" % user)
		return
	
	# Success
	current_user = user
	_login_error.text = ""
	print("[ComputerUI] LOGIN SUCCESS: user='%s'" % current_user)
	
	# Only trigger Day 1 progression for LUND on first login
	if user == "LUND":
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_computer_used"):
			rm.on_computer_used()
			print("[ComputerUI] RoutineManager.on_computer_used() called for LUND.")
	
	_show_desktop()


# ─────────────────────────────────────────────────────────────────────────────
# DESKTOP
# ─────────────────────────────────────────────────────────────────────────────

func _show_desktop() -> void:
	_login_screen.visible = false
	_main_window.visible = false
	
	_desktop_view.visible = true
	
	# Show/hide icons based on current_user
	if current_user == "LUND":
		_desktop_field_log_btn.visible = true
		_desktop_recycle_btn.visible = false
	elif current_user == "STENBERG":
		_desktop_field_log_btn.visible = false
		_desktop_recycle_btn.visible = true
	else:
		_desktop_field_log_btn.visible = false
		_desktop_recycle_btn.visible = false
	
	# Log Off is always visible
	_desktop_logoff_btn.visible = true
	
	print("[ComputerUI] Desktop displayed for user '%s'" % current_user)


## Called by POWER OFF / SHUT DOWN buttons and the interact key (E).
## Closes the entire computer UI and returns control to the player.
func _on_exit_computer() -> void:
	close_computer()


func _on_log_off() -> void:
	current_user = ""
	_show_login_screen()
	print("[ComputerUI] User logged off.")


# ─────────────────────────────────────────────────────────────────────────────
# RESTORE PLAYER CONTROLS
# ─────────────────────────────────────────────────────────────────────────────

func _on_stand_tween_completed() -> void:
	_restore_player_controls()

func _restore_player_controls() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
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
				_camera_holder.global_transform.basis = _camera_holder.global_transform.basis.orthonormalized()
			print("[ComputerUI] Deep matrix alignment complete.")
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

## Closes the application window and returns to the desktop.
## Bound to the MainWindow CloseButton (X).
func _on_close_app_window() -> void:
	_main_window.visible = false
	_desktop_view.visible = true
	print("[ComputerUI] Application window closed. Returning to desktop.")


# ─────────────────────────────────────────────────────────────────────────────
# FIELD_LOG.EXE — Gated behind Day 2+
# ─────────────────────────────────────────────────────────────────────────────

func _on_field_log_open() -> void:
	# ─── DAY 1 GUARD: FIELD_LOG.EXE is locked on Day 1 ───────────────
	var rm = get_node_or_null("/root/RoutineManager")
	if rm:
		# Check if eco-survey has been completed (Day 1 computer task done)
		# If phase2_computer_used isn't set, this is Day 1 — block access
		var comp_used = rm.get("phase2_computer_used") if rm else false
		var nests_done = rm.get("nests_documented") >= 3 if rm else false
		
		# On Day 1 (phase2_computer_used just set, but nests not done),
		# FIELD_LOG should show "access denied" or the eco-survey if appropriate.
		# On Day 2, the player needs to have documented nests first.
		# But if always_pass_correlation is set (debug), allow access.
		if not always_pass_correlation:
			# Block if eco-survey hasn't been completed yet
			if not _eco_survey_completed:
				_show_access_denied("FIELD_LOG.EXE requires completed eco-survey baseline.")
				return
	
	_desktop_view.visible = false
	_main_window.visible = true
	_main_window.find_child("TitleLabel", true, false).text = "FIELD_LOG.EXE"
	_status_label.text = "Opening: FIELD_LOG.EXE — Data Correlation Utility..."
	
	# Hide content, show data entry
	$MainWindow/HBoxContainer/ContentPanel.visible = false
	_data_entry_panel.visible = true
	_recovery_panel.visible = false
	
	if _dropdown_source:   _dropdown_source.selected = 0
	if _dropdown_anomaly:  _dropdown_anomaly.selected = 0
	if _dropdown_frequency: _dropdown_frequency.selected = 0
	
	# If eco-survey is completed and nests documented, show concept puzzle
	if _eco_survey_completed:
		var nests_documented := 0
		if rm: nests_documented = rm.get("nests_documented")
		
		if nests_documented >= 3 and not _nest_data_uploaded:
			_show_nest_concept_puzzle()
			return
		
		if _nest_data_uploaded:
			_status_label.text = "FIELD_LOG.EXE — Nest Data Uploaded"
			$MainWindow/HBoxContainer/ContentPanel.visible = true
			_data_entry_panel.visible = false
			_content_display.text = "[b]NEST DOCUMENTATION CORRELATION COMPLETE[/b]\n\n"
			_content_display.text += "All three Hazelnest observations have been successfully archived."
			return
		
		# Eco-survey already done — show completion
		_status_label.text = "FIELD_LOG.EXE — Eco-Survey Complete"
		$MainWindow/HBoxContainer/ContentPanel.visible = true
		_data_entry_panel.visible = false
		_content_display.text = "[b]ECO-SURVEY CORRELATION COMPLETE[/b]\n\nBaseline data archived."
		return
	
	print("[ComputerUI] FIELD_LOG.EXE opened.")


func _show_access_denied(reason: String) -> void:
	_desktop_view.visible = false
	_main_window.visible = true
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	_data_entry_panel.visible = false
	_recovery_panel.visible = false
	_status_label.text = "ACCESS DENIED"
	_content_display.text = "[color=red][b]ACCESS DENIED[/b][/color]\n\n%s" % reason
	print("[ComputerUI] ACCESS DENIED: %s" % reason)


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
# CORRELATION LOGIC (preserved)
# ─────────────────────────────────────────────────────────────────────────────

func _on_correlate_data() -> void:
	print("[ComputerUI] CORRELATE DATA BUTTON PRESSED")
	
	if always_pass_correlation:
		_on_correlation_success(_get_current_night())
		return
	
	var source_idx: int = _dropdown_source.selected if _dropdown_source else 0
	var anomaly_idx: int = _dropdown_anomaly.selected if _dropdown_anomaly else 0
	var freq_idx: int = _dropdown_frequency.selected if _dropdown_frequency else 0
	var selected_indices: Array = [source_idx, anomaly_idx, freq_idx]
	var current_night: int = _get_current_night()
	
	# Night 1 pre-check: nests must be photographed
	if current_night == 1 and selected_indices == [0, 0, 0] and not _eco_survey_completed:
		if not _all_nests_photographed():
			_play_error_sound()
			_status_label.text = "ERROR: FLOATING FIELD SAMPLES DETECTED"
			_content_display.text = "[color=red][b]ERROR: FLOATING FIELD SAMPLES DETECTED.[/b][/color]\n\n"
			_content_display.text += "[color=red]ALL PERIMETER NEST LOCATIONS MUST HAVE EXACTLY ONE LOGGED JPEG PROFILE.[/color]"
			$MainWindow/HBoxContainer/ContentPanel.visible = true
			return
		print("[ComputerUI] All nests photographed — falling through to night answer key check.")
	
	# Day 2 nest concept puzzle
	if _eco_survey_completed and not _nest_data_uploaded:
		var rm = get_node_or_null("/root/RoutineManager")
		var nests_doc = rm.get("nests_documented") if rm else 0
		if rm and nests_doc >= 3:
			if selected_indices == NEST_CONCEPT_ANSWER_KEY:
				_on_nest_concept_success()
			else:
				_on_nest_concept_failure()
			return
	
	var correct_indices = NIGHT_ANSWER_KEY.get(current_night, null)
	if correct_indices != null and selected_indices == correct_indices:
		_on_correlation_success(current_night)
	else:
		_on_correlation_failure()


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
		print("[ComputerUI] Night 1 eco-survey correlated!")
	
	# Day 2 nest upload
	var rm = get_node_or_null("/root/RoutineManager")
	var nests_done: bool = rm and rm.get("nests_documented") >= 3 if rm else false
	if night == 2 and (_eco_survey_completed or nests_done):
		if rm and rm.has_method("on_nest_data_uploaded"):
			rm.on_nest_data_uploaded()
	
	_data_entry_panel.visible = false
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	
	var reward = TACTICAL_LOG_REWARDS.get(night, null)
	if reward:
		_content_display.text = "[b]" + reward["title"] + "[/b]\n\n" + reward["body"] + "\n\n---\n[color=gray]Decryption Key: NIGHT_" + str(night) + "_CORRELATION_ACCEPTED[/color]"
	else:
		_content_display.text = "[b]NIGHT " + str(night) + " — DATA CORRELATION ACCEPTED[/b]\n\nNo additional intelligence available."
	
	print("[ComputerUI] Night %d correlation successful!" % night)


func _on_correlation_failure() -> void:
	_play_error_sound()
	_status_label.text = "CRITICAL ERROR: DATA ANOMALY DETECTED"
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	_data_entry_panel.visible = false
	_content_display.text = "[color=red][b]CRITICAL ERROR: DATA ANOMALY DETECTED.[/b][/color]\n\nCORRELATION REJECTED.\n\n---\n[color=gray]Error Code: 0xDEADBEEF[/color]"
	_nest_data_uploaded = false
	nest_data_uploaded = false


# ─────────────────────────────────────────────────────────────────────────────
# NEST CONCEPT PUZZLE
# ─────────────────────────────────────────────────────────────────────────────

func _show_nest_concept_puzzle() -> void:
	_status_label.text = "FIELD_LOG.EXE — Nest Documentation Correlation"
	if _dropdown_source:
		_dropdown_source.clear()
		for c in NEST_CONCEPT_CHOICES: _dropdown_source.add_item(c)
		_dropdown_source.selected = 0
	if _dropdown_anomaly:
		_dropdown_anomaly.clear()
		for c in NEST_CONCEPT_CHOICES: _dropdown_anomaly.add_item(c)
		_dropdown_anomaly.selected = 0
	if _dropdown_frequency:
		_dropdown_frequency.clear()
		for c in NEST_CONCEPT_CHOICES: _dropdown_frequency.add_item(c)
		_dropdown_frequency.selected = 0
	
	var sl = _dropdown_source.get_parent().get_node_or_null("SourceLabel")
	var al = _dropdown_anomaly.get_parent().get_node_or_null("AnomalyLabel")
	var fl = _dropdown_frequency.get_parent().get_node_or_null("FrequencyLabel")
	if sl: sl.text = "Nest Alpha:"
	if al: al.text = "Nest Beta:"
	if fl: fl.text = "Nest Gamma:"
	
	_data_entry_panel.visible = true
	$MainWindow/HBoxContainer/ContentPanel.visible = false
	print("[ComputerUI] Nest concept puzzle displayed.")


func _on_nest_concept_success() -> void:
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
	_content_display.text += "Nest Alpha → Extreme Photophobia ✓\nNest Beta → Active Observation ✓\nNest Gamma → Acoustic Mimicry ✓\n\nData uploaded."


func _on_nest_concept_failure() -> void:
	_play_error_sound()
	_status_label.text = "FIELD OBSERVATION MISMATCH"
	_data_entry_panel.visible = false
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	_content_display.text = "[color=red][b]FIELD OBSERVATION MISMATCH.[/b][/color]\n\nCross-reference your field notebook."


# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

func _get_current_night() -> int:
	var nm = get_node_or_null("/root/NightManager")
	if nm and "current_night" in nm: return nm.current_night
	return 1

func _all_nests_photographed() -> bool:
	var photo_cam = get_node_or_null("/root/CottageHorror/Player/CameraHolder/Camera3D/PhotoCamera")
	if not photo_cam: photo_cam = get_node_or_null("/root/Main/Player/CameraHolder/Camera3D/PhotoCamera")
	if not photo_cam:
		var nests = get_tree().get_nodes_in_group("hasselmus_nests")
		for nest in nests:
			if "is_photographed" in nest and not nest.is_photographed: return false
		return nests.size() > 0
	var count = photo_cam.get_documented_count() if photo_cam.has_method("get_documented_count") else photo_cam.documented_nests.size()
	var total = photo_cam.get("TOTAL_NESTS") if "TOTAL_NESTS" in photo_cam else 3
	return count >= total

func _trigger_phone_drop_event() -> void:
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		if gt.has_method("set_progress"): gt.set_progress(0.438)
		if gt.has_method("unpause_time"): gt.unpause_time()
	var inv_ui = get_node_or_null("/root/CottageHorror/InventoryUI")
	if not inv_ui: inv_ui = get_node_or_null("/root/Main/InventoryUI")
	if inv_ui and inv_ui.has_method("_close_inventory"): inv_ui._close_inventory()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

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


# ─────────────────────────────────────────────────────────────────────────────
# RECOVER_DATA.EXE (preserved)
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
