extends CanvasLayer
class_name ComputerUI

## ComputerUI — Windows 98-style Archival System interface.
## Displays lore entries, nest data uploads, and deleted logs.
## The player accesses this by interacting with the PC monitor in the cabin.

signal computer_closed

## Reference to the player controller so we can lock/unlock movement
var _player: Node = null

## Whether the Day 1 nest data objective has been completed
var nest_data_uploaded: bool = false

## The CameraHolder's original global transform before the sitting animation.
## Set by PCInteractable before opening the UI.
var _original_camera_transform: Transform3D

## Reference to the player's CameraHolder node (found at runtime)
var _camera_holder: Node3D = null

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
@onready var _log_nest_data_btn: Button = $MainWindow/HBoxContainer/NavButtons/LogNestData
@onready var _archive_logs_btn: Button = $MainWindow/HBoxContainer/NavButtons/ArchiveLogs
@onready var _trash_btn: Button = $MainWindow/HBoxContainer/NavButtons/Trash
@onready var _status_label: Label = $MainWindow/StatusBar/StatusLabel

## Tracks whether the window is minimized (only title bar visible)
var _is_minimized: bool = false

## Tracks whether the window is maximized (full screen)
var _is_maximized: bool = false

## Stores the window's normal (non-maximized) rect for restore
var _normal_rect: Rect2


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
	if _log_nest_data_btn:
		_log_nest_data_btn.pressed.connect(_on_log_nest_data)
	if _archive_logs_btn:
		_archive_logs_btn.pressed.connect(_on_archive_logs)
	if _trash_btn:
		_trash_btn.pressed.connect(_on_trash)
	
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


## "Log Nest Data" button — uploads nest observation data.
## On first click, triggers the phone drop event and advances the routine.
## This is the trigger for "time start" — the day/night cycle begins here.
func _on_log_nest_data() -> void:
	_status_label.text = "Opening: Nest Data Archive..."
	if not nest_data_uploaded:
		_content_display.text = "[b]UPLOADING NEST DATA...[/b]\n\n"
		_content_display.text += "Scanning nest coordinates...\n"
		_content_display.text += "Cross-referencing with archival records...\n"
		_content_display.text += "Data packet #1 of 3 uploaded successfully.\n"
		_content_display.text += "Data packet #2 of 3 uploaded successfully.\n"
		_content_display.text += "Data packet #3 of 3 uploaded successfully.\n\n"
		_content_display.text += "[color=green]Nest data transmission complete.[/color]\n"
		_content_display.text += "Awaiting further instructions from HQ."
		
		nest_data_uploaded = true
		
		# Emit a global event so NightManager or other systems can react
		var nm = get_node_or_null("/root/NightManager")
		if nm:
			nm.horror_event.emit("nest_data_uploaded")
		
		# Advance the Night 1 bedtime routine to Step 2 (Refill Generator)
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("advance_step"):
			rm.advance_step()
		
		# --- PHONE DROP + TIME START ---
		# When the player uploads nest data, trigger the phone drop event
		# and advance time to golden hour. This was previously triggered
		# by documenting the 3rd nest, but now the computer is the trigger.
		_trigger_phone_drop_event()
		
		print("[ComputerUI] Nest data uploaded! Day 1 objective complete.")
	else:
		_content_display.text = "[b]NEST DATA ARCHIVE[/b]\n\n"
		_content_display.text += "All nest data packets have been transmitted.\n"
		_content_display.text += "No pending uploads remaining.\n"
		_content_display.text += "Stand by for HQ response."


## "Archive Logs" button — displays mundane forest observation logs.
## These are the "official" records that hide the darker truth.
func _on_archive_logs() -> void:
	_status_label.text = "Opening: Forestry Archive Logs..."
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
## Called when the player uploads nest data on the computer.
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
