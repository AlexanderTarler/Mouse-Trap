extends CanvasLayer
class_name ComputerUI

## ComputerUI — Windows 98-style Archival System interface.
## Displays lore entries, evidence correlation, and deleted logs.
## The player accesses this by interacting with the PC monitor in the cabin.
##
## FIELD_LOG.EXE — Manual dropdown validation form.
## The player selects evidence from 3 dropdowns and presses "CORRELATE DATA"
## to verify their findings against the known profile for the current night.
##
## Dropdown 1: _dropdown_source
##   Index 0: "Nest Alpha"
##   Index 1: "Nest Beta"
##   Index 2: "Window 3 Sill"
##
## Dropdown 2: _dropdown_anomaly
##   Index 0: "Bio-Crystalline"
##   Index 1: "Organic Decay"
##   Index 2: "Corrosive Trace"
##
## Dropdown 3: _dropdown_frequency
##   Index 0: "14.2 Hz"
##   Index 1: "8.8 Hz"
##   Index 2: "22.1 Hz"
##
## Answer Key (read from /root/NightManager.current_night):
##   Night 1: Nest Alpha (0), Bio-Crystalline (0), 14.2 Hz (0)
##   Night 2: Window 3 Sill (2), Corrosive Trace (2), 8.8 Hz (1)


signal computer_closed

## Reference to the player controller so we can lock/unlock movement
var _player: Node = null

## Whether the Day 1 eco-survey objective has been completed (Profile A)
var nest_data_uploaded: bool = false

## The CameraHolder's original global transform before the sitting animation.
## Set by PCInteractable before opening the UI.
var _original_camera_transform: Transform3D

## Reference to the player's CameraHolder node (found at runtime)
var _camera_holder: Node3D = null

## Set of evidence profile IDs that have been successfully unlocked.
## Used to prevent re-unlocking the same profile and to track progress.
var _unlocked_profiles: Dictionary = {}

## Whether the eco-survey (Profile A) has been completed.
## This gates the Day 1 phone drop / time start progression.
var _eco_survey_completed: bool = false

## Set by PCInteractable to pass the player and camera_holder references directly.
## This is more reliable than looking them up via absolute paths.
func set_player_references(player: Node, camera_holder: Node3D) -> void:
	_player = player
	_camera_holder = camera_holder

@onready var _main_window: Panel = $MainWindow
@onready var _content_display: RichTextLabel = $MainWindow/HBoxContainer/ContentPanel/ContentDisplay
@onready var _close_button: Button = $MainWindow/TitleBar/CloseButton
@onready var _minimize_button: Button = $MainWindow/TitleBar/MinimizeButton
@onready var _maximize_button: Button = $MainWindow/TitleBar/MaximizeButton
@onready var _field_log_btn: Button = $MainWindow/HBoxContainer/NavButtons/LogNestData
@onready var _archive_logs_btn: Button = $MainWindow/HBoxContainer/NavButtons/ArchiveLogs
@onready var _trash_btn: Button = $MainWindow/HBoxContainer/NavButtons/Trash
@onready var _status_label: Label = $MainWindow/StatusBar/StatusLabel

# --- FIELD_LOG.EXE nodes ---
@onready var _data_entry_panel: Panel = $MainWindow/HBoxContainer/DataEntryPanel
@onready var _dropdown_source: OptionButton = $MainWindow/HBoxContainer/DataEntryPanel/DataEntryVBox/DropdownSource
@onready var _dropdown_anomaly: OptionButton = $MainWindow/HBoxContainer/DataEntryPanel/DataEntryVBox/DropdownAnomaly
@onready var _dropdown_frequency: OptionButton = $MainWindow/HBoxContainer/DataEntryPanel/DataEntryVBox/DropdownFrequency
@onready var _btn_correlate: Button = $MainWindow/HBoxContainer/DataEntryPanel/DataEntryVBox/CorrelateButton

## Tracks whether the window is minimized (only title bar visible)
var _is_minimized: bool = false

## Tracks whether the window is maximized (full screen)
var _is_maximized: bool = false

## Stores the window's normal (non-maximized) rect for restore
var _normal_rect: Rect2

## ─────────────────────────────────────────────────────────────────────────────
## NIGHT ANSWER KEY — Manual dropdown validation
## ─────────────────────────────────────────────────────────────────────────────
## Maps each night number to the correct [source_idx, anomaly_idx, freq_idx]
## combination that the player must select to pass validation.
##
## Dropdown options (3 items each):
##   Source:   0=Nest Alpha, 1=Nest Beta, 2=Window 3 Sill
##   Anomaly:  0=Bio-Crystalline, 1=Organic Decay, 2=Corrosive Trace
##   Frequency: 0=14.2 Hz, 1=8.8 Hz, 2=22.1 Hz
##
## Answer Key:
##   Night 1: [0, 0, 0] — Nest Alpha, Bio-Crystalline, 14.2 Hz
##   Night 2: [2, 2, 1] — Window 3 Sill, Corrosive Trace, 8.8 Hz

const NIGHT_ANSWER_KEY: Dictionary = {
	1: [0, 0, 0],
	2: [2, 2, 1],
}

## ─────────────────────────────────────────────────────────────────────────────
## TACTICAL LOG REWARDS — Unlocked on successful correlation
## ─────────────────────────────────────────────────────────────────────────────
## Each entry maps a night number to the decrypted text reward shown when
## the player correctly correlates data for that night.

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



func _ready() -> void:
	# Start hidden
	visible = false
	
	# Connect button signals
	if _close_button:
		_close_button.pressed.connect(close_computer)
	if _minimize_button:
		_minimize_button.pressed.connect(_on_minimize)
	if _maximize_button:
		_maximize_button.pressed.connect(_on_maximize)
	if _field_log_btn:
		_field_log_btn.pressed.connect(_on_field_log_open)
	if _archive_logs_btn:
		_archive_logs_btn.pressed.connect(_on_archive_logs)
	if _trash_btn:
		_trash_btn.pressed.connect(_on_trash)
	if _btn_correlate:
		_btn_correlate.pressed.connect(_on_correlate_data)
	
	# Save the normal window rect for restore
	_normal_rect = Rect2(_main_window.position, _main_window.size)
	
	# Find the player using groups (more reliable than absolute paths)
	# PCInteractable may also pass these references via set_player_references()
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
	
	# Find the CameraHolder for the standing-up tween
	if _player and not _camera_holder:
		_camera_holder = _player.get_node_or_null("CameraHolder")
	
	# Debug: log if references are still missing
	if not _player:
		print("[ComputerUI] WARNING: Could not find Player node in _ready()")
	if not _camera_holder:
		print("[ComputerUI] WARNING: Could not find CameraHolder node in _ready()")


## Called by PCInteractable to pass the CameraHolder's original transform
## before the sitting animation began. We save it so we can restore it on close.
func set_original_camera_transform(transform: Transform3D) -> void:
	_original_camera_transform = transform


## Opens the computer UI: shows the overlay, pauses player movement,
## and unlocks the mouse cursor so the player can click buttons.
func open_computer() -> void:

	# Last-resort fallback: try to find player/camera_holder if still missing
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
	if _player and not _camera_holder:
		_camera_holder = _player.get_node_or_null("CameraHolder")
	
	# Safety check: if we're not in the scene tree, re-add ourselves.
	# This can happen if the UI was instantiated during _ready() before the
	# scene tree was fully initialized, leaving the node orphaned.
	if not is_inside_tree():
		var main_loop = Engine.get_main_loop()
		if main_loop is SceneTree:
			var root = main_loop.root
			if root:
				root.add_child(self)
		
		# If still not in tree, try current_scene
		if not is_inside_tree():
			var main_loop2 = Engine.get_main_loop()
			if main_loop2 is SceneTree:
				var scene = main_loop2.current_scene
				if scene:
					scene.add_child(self)
	
	visible = true
	
	# Pause player movement by setting mouse mode to visible
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Disable player input processing
	if _player:
		_player.set_process_input(false)
		_player.set_physics_process(false)
	
	_status_label.text = "Ready"
	print("[ComputerUI] Computer opened.")


## Closes the computer UI: hides the overlay, tweens the camera back to
## the original position, then restores player movement.
func close_computer() -> void:
	visible = false
	
	# Only tween the camera back if we have a valid original transform
	# (i.e., the player actually sat down at the computer).
	# If close_computer() is called from _ready() during initialization,
	# _original_camera_transform is still the default identity transform,
	# so we skip the tween and restore controls immediately.
	if _camera_holder and _original_camera_transform != Transform3D():
		var tween = create_tween()
		tween.set_parallel(false)
		tween.tween_property(_camera_holder, "global_transform", _original_camera_transform, 0.5)\
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		
		# Restore controls after the tween finishes
		tween.finished.connect(_on_stand_tween_completed)
	else:
		# No CameraHolder found or no original transform saved — restore controls immediately
		_restore_player_controls()
	
	computer_closed.emit()
	print("[ComputerUI] Computer closed.")


## Called when the standing-up tween animation completes.
## Restores player movement and re-captures the mouse cursor.
func _on_stand_tween_completed() -> void:
	_restore_player_controls()


## Restores player movement and re-captures the mouse cursor.
func _restore_player_controls() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	if _player:
		_player.set_process_input(true)
		_player.set_physics_process(true)


## Minimize button: collapses the window to just the title bar.
func _on_minimize() -> void:
	if _is_minimized:
		# Restore
		_main_window.size = _normal_rect.size
		_is_minimized = false
		_status_label.text = "Restored"
	else:
		# Save current size and collapse to title bar
		_normal_rect.size = _main_window.size
		_main_window.size.y = 22  # Just the title bar height
		_is_minimized = true
		_status_label.text = "Minimized"


## Maximize button: toggles between normal size and full screen.
func _on_maximize() -> void:
	if _is_maximized:
		# Restore to normal size
		_main_window.position = _normal_rect.position
		_main_window.size = _normal_rect.size
		_is_maximized = false
		_status_label.text = "Restored"
	else:
		# Save normal rect and expand to fill the screen
		_normal_rect = Rect2(_main_window.position, _main_window.size)
		var viewport_size = get_viewport().get_visible_rect().size
		_main_window.position = Vector2(0, 0)
		_main_window.size = viewport_size
		_is_maximized = true
		_status_label.text = "Maximized"


## "FIELD_LOG.EXE" button — opens the data entry form panel.
## Populates all dropdowns with the full evidence matrix.
## The player can only select options for evidence they've actually collected.
func _on_field_log_open() -> void:
	_status_label.text = "Opening: FIELD_LOG.EXE — Data Correlation Utility..."
	
	# Hide the content display panel, show the data entry panel
	$MainWindow/HBoxContainer/ContentPanel.visible = false
	_data_entry_panel.visible = true
	
	# Populate all dropdowns with the full 4-item evidence matrix.
	# The scene already has the items defined; we just reset selection.
	if _dropdown_source:
		_dropdown_source.selected = 0
	if _dropdown_anomaly:
		_dropdown_anomaly.selected = 0
	if _dropdown_frequency:
		_dropdown_frequency.selected = 0
	
	# If eco-survey is already completed, show the success state
	if _eco_survey_completed:
		_status_label.text = "FIELD_LOG.EXE — Eco-Survey Complete"
		_content_display.text = "[b]ECO-SURVEY CORRELATION COMPLETE[/b]\n\n"
		_content_display.text += "Baseline hazel mouse distribution data has been "
		_content_display.text += "successfully archived. Additional evidence profiles "
		_content_display.text += "may be unlocked by collecting physical samples "
		_content_display.text += "from the environment."
		_content_display.visible = true
		_data_entry_panel.visible = false
		$MainWindow/HBoxContainer/ContentPanel.visible = true



## Checks whether all hazel mouse nests have been photographed by checking
## the PhotoCamera's documented_nests array (the virtual floppy disk).
## Returns true if all nests are documented, false otherwise.
func _all_nests_photographed() -> bool:
	# Find the PhotoCamera node in the scene
	var photo_cam = get_node_or_null("/root/CottageHorror/Player/CameraHolder/Camera3D/PhotoCamera")
	if not photo_cam:
		photo_cam = get_node_or_null("/root/Main/Player/CameraHolder/Camera3D/PhotoCamera")
	
	if not photo_cam:
		# Fallback: check nest nodes directly
		print("[ComputerUI] PhotoCamera not found! Falling back to nest node check.")
		var nests = get_tree().get_nodes_in_group("hasselmus_nests")
		if nests.is_empty():
			print("[ComputerUI] No nests found in the world!")
			return false
		
		for nest in nests:
			if "is_photographed" in nest:
				if not nest.is_photographed:
					print("[ComputerUI] Nest %s is not yet photographed!" % nest.nest_id)
					return false
			else:
				print("[ComputerUI] Nest missing is_photographed property!")
				return false
		
		print("[ComputerUI] All %d nests photographed!" % nests.size())
		return true
	
	# Check the camera's documented_nests array
	var count = photo_cam.get_documented_count() if photo_cam.has_method("get_documented_count") else photo_cam.documented_nests.size()
	var total = photo_cam.TOTAL_NESTS if "TOTAL_NESTS" in photo_cam else 3
	
	if count < total:
		print("[ComputerUI] Only %d/%d nests photographed!" % [count, total])
		return false
	
	print("[ComputerUI] All %d nests photographed!" % total)
	return true



## Returns the current night number from /root/NightManager.
## Falls back to 1 if NightManager is not found.
func _get_current_night() -> int:
	var nm = get_node_or_null("/root/NightManager")
	if nm and "current_night" in nm:
		return nm.current_night
	return 1


## "CORRELATE DATA" button — validates the dropdown selections against
## the answer key for the current night.
##
## If the choices MATCH the correct profile:
##   - Plays a positive OS click sound effect
##   - Sets nest_data_uploaded = true and calls _trigger_phone_drop_event()
##   - Displays the tactical log reward for that night
##
## If the choices MISMATCH:
##   - Plays a retro Windows 98 system warning error buzzer sound
##   - Clears the content display and shows a critical error message
##   - Keeps nest_data_uploaded = false
func _on_correlate_data() -> void:
	# Get the selected indices from the dropdowns
	var source_idx: int = _dropdown_source.selected if _dropdown_source else 0
	var anomaly_idx: int = _dropdown_anomaly.selected if _dropdown_anomaly else 0
	var freq_idx: int = _dropdown_frequency.selected if _dropdown_frequency else 0
	
	var selected_indices: Array = [source_idx, anomaly_idx, freq_idx]
	
	# Determine the current night
	var current_night: int = _get_current_night()
	
	# Pre-check guard: On Night 1, if the player selected the eco-survey
	# profile (indices [0,0,0]), verify that all nests have been physically
	# photographed first.
	if current_night == 1 and selected_indices == [0, 0, 0] and not _eco_survey_completed:
		if not _all_nests_photographed():
			# Block validation — nests not all documented
			_play_error_sound()
			_status_label.text = "ERROR: FLOATING FIELD SAMPLES DETECTED"
			nest_data_uploaded = false
			
			# Show the error text in the content display
			_content_display.text = ""
			_content_display.text += "[color=red][b]ERROR: FLOATING FIELD SAMPLES DETECTED.[/b][/color]\n\n"
			_content_display.text += "[color=red]ALL PERIMETER NEST LOCATIONS MUST HAVE EXACTLY ONE "
			_content_display.text += "LOGGED JPEG PROFILE RECORDED TO THE DESIGNATED DATA SLOTS "
			_content_display.text += "IN DRIVE A:/ BEFORE CORRELATION CAN COMPUTE.[/color]"
			
			# Ensure the content panel is visible to show the error
			$MainWindow/HBoxContainer/ContentPanel.visible = true
			
			print("[ComputerUI] Pre-check failed: Not all nests photographed!")
			return
	
	# Look up the correct answer for the current night
	var correct_indices = NIGHT_ANSWER_KEY.get(current_night, null)
	
	if correct_indices != null and selected_indices == correct_indices:
		_on_correlation_success(current_night)
	else:
		_on_correlation_failure()




## Plays a positive OS click sound effect for successful correlation.
func _play_success_sound() -> void:
	var hsm = get_node_or_null("/root/HorrorSoundManager")
	if hsm:
		# Use the distant monster player's approach — play a 2D sound
		# For now, we use a simple AudioStreamPlayer with a UI click sound
		# The actual sound file should be placed at:
		# res://assets/audio/UI/ui_click_success.ogg
		var stream = load("res://assets/audio/UI/ui_click_success.ogg")
		if stream:
			var player = AudioStreamPlayer.new()
			player.bus = "SFX"
			player.stream = stream
			add_child(player)
			player.play()
			# Auto-cleanup when finished
			player.finished.connect(player.queue_free)


## Plays a retro Windows 98 system warning error buzzer sound for failed correlation.
func _play_error_sound() -> void:
	var hsm = get_node_or_null("/root/HorrorSoundManager")
	if hsm:
		# The actual sound file should be placed at:
		# res://assets/audio/UI/win98_error.ogg
		var stream = load("res://assets/audio/UI/win98_error.ogg")
		if stream:
			var player = AudioStreamPlayer.new()
			player.bus = "SFX"
			player.stream = stream
			add_child(player)
			player.play()
			# Auto-cleanup when finished
			player.finished.connect(player.queue_free)


## Handles a successful data correlation for the given night.
## Plays a success sound, sets nest_data_uploaded = true, triggers the
## phone drop event (Day 1 progression), and displays the tactical log reward.
func _on_correlation_success(night: int) -> void:
	# Play success sound effect
	_play_success_sound()
	
	# Mark as uploaded
	nest_data_uploaded = true
	
	# Build a profile_id for tracking unlocks
	var profile_id: String = "night_%d" % night
	
	# Check if this night's log was already unlocked
	if _unlocked_profiles.has(profile_id):
		_status_label.text = "LOG ALREADY DECRYPTED — Reviewing Tactical Brief..."
	else:
		_status_label.text = "CORRELATION ACCEPTED — Decrypting Tactical Log..."
		_unlocked_profiles[profile_id] = true
	
	# Night 1: Trigger Day 1 progression (eco-survey complete, phone drop, time start)
	if night == 1 and not _eco_survey_completed:
		_eco_survey_completed = true
		
		# Emit a global event so NightManager or other systems can react
		var nm = get_node_or_null("/root/NightManager")
		if nm:
			nm.horror_event.emit("nest_data_uploaded")
		
		# Advance the Night 1 bedtime routine to Step 2 (Refill Generator)
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("advance_step"):
			rm.advance_step()
		
		# --- PHONE DROP + TIME START ---
		_trigger_phone_drop_event()
		
		print("[ComputerUI] Night 1 eco-survey correlated! Day 1 progression triggered.")
	
	# Switch back to content display view
	_data_entry_panel.visible = false
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	
	# Look up the tactical log reward for this night
	var reward = TACTICAL_LOG_REWARDS.get(night, null)
	if reward:
		# Display the decrypted tactical log
		_content_display.text = ""
		_content_display.text += "[b]" + reward["title"] + "[/b]\n\n"
		_content_display.text += reward["body"] + "\n\n"
		_content_display.text += "---\n"
		_content_display.text += "[color=gray]Decryption Key: NIGHT_" + str(night) + "_CORRELATION_ACCEPTED[/color]"
	else:
		# Fallback if no reward is defined for this night
		_content_display.text = ""
		_content_display.text += "[b]NIGHT " + str(night) + " — DATA CORRELATION ACCEPTED[/b]\n\n"
		_content_display.text += "Field data successfully cross-referenced against archival records.\n\n"
		_content_display.text += "No additional tactical intelligence available for this sector profile."
	
	print("[ComputerUI] Night %d correlation successful!" % night)



## Handles a failed data correlation.
## Shows a retro Windows 98 critical error message.
func _on_correlation_failure() -> void:
	# Play error sound effect
	_play_error_sound()
	
	_status_label.text = "CRITICAL ERROR: DATA ANOMALY DETECTED"
	
	# Clear the content display and show error message
	_content_display.text = ""
	_content_display.text += "[color=red][b]CRITICAL ERROR: DATA ANOMALY DETECTED.[/b][/color]\n\n"
	_content_display.text += "[color=red]CORRELATION REJECTED.[/color]\n\n"
	_content_display.text += "CHECK ARCHIVAL REFERENCE DOCUMENTS.\n\n"
	_content_display.text += "---\n"
	_content_display.text += "[color=gray]Error Code: 0xDEADBEEF — Field data mismatch.\n"
	_content_display.text += "The selected evidence profile does not match\n"
	_content_display.text += "any known archival records for this sector.[/color]"
	
	# Ensure the content panel is visible to show the error
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	
	# Keep nest_data_uploaded = false so they cannot advance
	nest_data_uploaded = false
	
	print("[ComputerUI] Data correlation FAILED. Player must try again.")



## "Archive Logs" button — displays mundane forest observation logs.
## These are the "official" records that hide the darker truth.
func _on_archive_logs() -> void:
	_status_label.text = "Opening: Forestry Archive Logs..."
	
	# Hide data entry panel, show content panel
	_data_entry_panel.visible = false
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	
	_content_display.text = ""
	_content_display.text += "[b]SVENSKA SKOGSBRUKSARKIVET[/b]\n"
	_content_display.text += "[b]Swedish Forestry Archive — Log Entry 1996-04-12[/b]\n\n"
	_content_display.text += "Weather: Overcast, 8°C, light precipitation.\n"
	_content_display.text += "Zone: Tiveden National Park, Sector 7G.\n\n"
	_content_display.text += "Routine survey of Sector 7G complete. Standard "
	_content_display.text += "growth patterns observed across all monitored "
	_content_display.text += "quadrants. Pine and spruce populations remain "
	_content_display.text += "within expected density parameters.\n\n"
	_content_display.text += "No unusual wildlife activity to report. "
	_content_display.text += "The cabin remains unoccupied per standard "
	_content_display.text += "off-season protocol.\n\n"
	_content_display.text += "[i]— M. Arvidsson, Field Observer[/i]\n\n"
	_content_display.text += "---\n\n"
	_content_display.text += "[b]Log Entry 1996-04-19[/b]\n\n"
	_content_display.text += "Weather: Clear, 11°C.\n\n"
	_content_display.text += "Second survey of the month. All clear. "
	_content_display.text += "The equipment shed requires minor repairs — "
	_content_display.text += "will submit a maintenance request.\n\n"
	_content_display.text += "[i]— M. Arvidsson, Field Observer[/i]"


## Starts the day/night cycle from 4:30 PM.
## Called when the player completes the eco-survey (Profile A) on the computer.
## This is the "time start" trigger — the day/night cycle begins here.
func _trigger_phone_drop_event() -> void:
	print("[ComputerUI] Time start triggered!")
	
	# Advance time to 4:30 PM (progress ~0.438) and unpause the cycle
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		if gt.has_method("set_progress"):
			gt.set_progress(0.438)  # 4:30 PM
		if gt.has_method("unpause_time"):
			gt.unpause_time()       # Unfreeze the clock — time now advances
		print("[ComputerUI] Set progress to 0.438 (4:30 PM) and unpaused time!")
	
	# Disable the player's Phone/Map UI
	_disable_phone_ui()


## Disables the player's Phone/Map UI and NoteUI.
## NOTE: _close_inventory() sets mouse mode to CAPTURED, but the computer
## UI is still open, so we re-set it to VISIBLE afterwards.
func _disable_phone_ui() -> void:
	# Find the InventoryUI (which acts as the phone/map) and disable it
	var inv_ui = get_node_or_null("/root/CottageHorror/InventoryUI")
	if not inv_ui:
		inv_ui = get_node_or_null("/root/Main/InventoryUI")
	
	if inv_ui:
		# Close it if it's open
		if inv_ui.has_method("_close_inventory"):
			inv_ui._close_inventory()
		print("[ComputerUI] Phone/Map UI disabled!")
	
	# Also disable the NoteUI
	var note_ui = get_node_or_null("/root/CottageHorror/NoteUI")
	if not note_ui:
		note_ui = get_node_or_null("/root/Main/NoteUI")
	
	if note_ui:
		note_ui.visible = false
		if note_ui.has_method("_close_note"):
			note_ui._close_note()
	
	# Re-set mouse to VISIBLE since the computer UI is still open
	# (_close_inventory() above sets it to CAPTURED)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## "Trash (Deleted)" button — displays the chilling deleted lore entry.
## This is the hidden truth that was scrubbed from the official records.
func _on_trash() -> void:
	_status_label.text = "Opening: Recycle Bin..."
	
	# Hide data entry panel, show content panel
	_data_entry_panel.visible = false
	$MainWindow/HBoxContainer/ContentPanel.visible = true
	
	_content_display.text = ""
	_content_display.text += "[b]RECOVERED DELETED LOG ENTRY[/b]\n"
	_content_display.text += "[color=red]WARNING: This file was marked for permanent deletion.[/color]\n"
	_content_display.text += "Recovered from disk sector 0x4F 0x42 0x53 0x43 0x55 0x52 0x45\n\n"
	_content_display.text += "---\n\n"
	_content_display.text += "LOG ERR_04:\n\n"
	_content_display.text += "The nests are not natural.\n\n"
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
	_content_display.text += "[color=red]— M. Arvidsson[/color]\n\n"
	_content_display.text += "---\n"
	_content_display.text += "[color=gray]File recovered from Recycle Bin. "
	_content_display.text += "Original deletion date: 1996-05-03.[/color]"
