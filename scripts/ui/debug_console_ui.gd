extends CanvasLayer

## Debug Console UI — Overlay with buttons to manipulate game state.
## Instantiated by debug_computer.gd when the player interacts with the computer prop.

signal console_closed

# References to game systems
var _night_manager: Node = null
var _entity: Node = null
var _player: Node = null
var _is_open: bool = false

# Entity enable/disable toggle state
var _entity_enabled: bool = true
var _entity_toggle_btn: Button = null

# UI node references
@onready var panel: Panel = $Panel
@onready var header: Label = $Panel/MarginContainer/VBoxContainer/Header
@onready var night_grid: GridContainer = $Panel/MarginContainer/VBoxContainer/NightSection/NightGrid
@onready var entity_section: VBoxContainer = $Panel/MarginContainer/VBoxContainer/EntitySection
@onready var debug_log: RichTextLabel = $Panel/MarginContainer/VBoxContainer/DebugLog
@onready var close_btn: Button = $Panel/MarginContainer/VBoxContainer/CloseButton

# Log capture
var _log_timer: float = 0.0
const LOG_UPDATE_INTERVAL: float = 0.5
var _log_buffer: Array[String] = []
const MAX_LOG_LINES: int = 50


func _ready() -> void:
	visible = false
	close_btn.pressed.connect(_close_console)
	
	# Connect to the global debug log signal if available
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		_night_manager = nm
	
	# Set up night buttons
	_setup_night_buttons()
	
	# Set up entity buttons
	_setup_entity_buttons()


func _setup_night_buttons() -> void:
	for i in range(1, 6):
		var btn = Button.new()
		btn.text = "Night %d" % i
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var night_num = i  # Capture for closure
		btn.pressed.connect(func(): _force_night(night_num))
		night_grid.add_child(btn)


func _setup_entity_buttons() -> void:
	var buttons_data = [
		{"text": "Force Relocate", "method": "_force_relocate"},
		{"text": "Force Window Peek", "method": "_force_window_peek"},
		{"text": "Toggle Stalking", "method": "_toggle_stalking"},
	]
	
	for data in buttons_data:
		var btn = Button.new()
		btn.text = data.text
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var method_name = data.method  # Capture for closure
		btn.pressed.connect(func(): _call_entity_method(method_name))
		entity_section.add_child(btn)
	
	# Entity enable/disable toggle button (persistent state)
	_entity_toggle_btn = Button.new()
	_entity_toggle_btn.text = "Entity: ENABLED"
	_entity_toggle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entity_toggle_btn.pressed.connect(_toggle_entity_enabled)
	entity_section.add_child(_entity_toggle_btn)


func open(player: Node) -> void:
	_player = player
	_is_open = true
	visible = true
	
	# Lock player input
	if _player and _player.has_method("set_process_input"):
		_player.set_process_input(false)
	
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Refresh references
	_night_manager = get_node_or_null("/root/NightManager")
	_entity = get_tree().get_first_node_in_group("entity")
	
	# Clear and update log
	debug_log.text = ""
	_log_buffer.clear()
	
	print("[Debug Console] Opened.")


func close() -> void:
	_is_open = false
	visible = false
	
	# Unlock player input
	if _player and _player.has_method("set_process_input"):
		_player.set_process_input(true)
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	console_closed.emit()
	print("[Debug Console] Closed.")


func _close_console() -> void:
	# Notify the computer node so it can clean up
	var computer = get_tree().get_first_node_in_group("debug_computer")
	if computer and computer.has_method("close_console"):
		computer.close_console()
	else:
		close()


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	
	# Close on Escape
	if event.is_action_pressed("ui_cancel"):
		_close_console()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _is_open:
		return
	
	# Periodically capture the latest print output
	_log_timer += delta
	if _log_timer >= LOG_UPDATE_INTERVAL:
		_log_timer = 0.0
		_refresh_log()


func _refresh_log() -> void:
	# The debug log RichTextLabel shows the latest game output.
	# Since we can't easily capture print() output in Godot 4,
	# we'll show the Entity heartbeat and state transitions that
	# are already being printed.
	# For now, we display a placeholder that updates with the current state.
	
	var lines: Array[String] = []
	
	# Night info
	if _night_manager:
		lines.append("[b]Night:[/b] %d | Active: %s | Progress: %.0f%%" % [
			_night_manager.current_night,
			"YES" if _night_manager.is_night_active else "NO",
			_night_manager.night_progress * 100.0
		])
	
	# Entity info
	if _entity:
		var state_name = "N/A"
		if _entity.has_method("get_current_state_name"):
			state_name = _entity.get_current_state_name()
		elif "current_night" in _entity:
			state_name = str(_entity.get("_state"))
		
		var pos = _entity.global_position if _entity.has_method("get_global_position") else Vector3.ZERO
		var dist = pos.distance_to(_player.global_position) if _player else 0.0
		
		lines.append("[b]Entity:[/b] State=%s | Pos=(%.1f, %.1f, %.1f) | Dist=%.1f" % [
			state_name, pos.x, pos.y, pos.z, dist
		])
	
	# Player info
	if _player:
		var ppos = _player.global_position
		lines.append("[b]Player:[/b] Pos=(%.1f, %.1f, %.1f)" % [ppos.x, ppos.y, ppos.z])
	
	debug_log.text = "\n".join(lines)


# --- Button Action Methods ---

func _force_night(night: int) -> void:
	print("[Debug Console] Forcing Night %d..." % night)
	
	if _night_manager:
		# End current night if active
		if _night_manager.is_night_active:
			_night_manager.end_current_night()
		
		# Force the night
		_night_manager.start_night(night)
		
		# Also force the GameTime to night if available
		var gt = get_node_or_null("/root/GameTime")
		if gt and gt.has_method("set_progress"):
			gt.set_progress(0.51)
			if gt.has_method("unpause_time"):
				gt.unpause_time()
		
		print("[Debug Console] Night %d forced!" % night)


func _force_relocate() -> void:
	print("[Debug Console] Forcing Entity relocate...")
	if _entity and _entity.has_method("_relocate_behind_player"):
		_entity._relocate_behind_player()
		print("[Debug Console] Entity relocated.")
	else:
		print("[Debug Console] Entity not found or missing _relocate_behind_player.")


func _force_window_peek() -> void:
	print("[Debug Console] Forcing Entity window peek...")
	if _entity and _entity.has_method("_start_window_peek"):
		_entity._start_window_peek()
		print("[Debug Console] Window peek triggered.")
	else:
		print("[Debug Console] Entity not found or missing _start_window_peek.")


func _toggle_stalking() -> void:
	print("[Debug Console] Toggling Entity stalking...")
	if not _entity:
		print("[Debug Console] Entity not found.")
		return
	
	if _entity.get("_is_active"):
		_entity.deactivate()
		print("[Debug Console] Entity deactivated (DORMANT).")
	else:
		_entity.activate()
		print("[Debug Console] Entity activated (OBSERVE_FROM_TREELINE).")


## Toggles the Entity between enabled (active) and disabled (dormant).
## Updates the toggle button text and color to reflect the current state.
## Also sets a "debug_disabled" meta flag on the Entity node so the
## NightManager can check it before auto-activating on night transitions.
func _toggle_entity_enabled() -> void:
	if not _entity:
		print("[Debug Console] Entity not found.")
		return
	
	_entity_enabled = not _entity_enabled
	
	if _entity_enabled:
		_entity.activate()
		_entity_toggle_btn.text = "Entity: ENABLED"
		# Reset to default button color
		_entity_toggle_btn.remove_theme_color_override("font_color")
		# Clear the debug-disabled meta flag so NightManager can re-activate
		_entity.set_meta("debug_disabled", false)
	else:
		_entity.deactivate()
		_entity_toggle_btn.text = "Entity: DISABLED"
		# Color the button red when disabled for visual clarity
		_entity_toggle_btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		# Set the debug-disabled meta flag so NightManager skips auto-activation
		_entity.set_meta("debug_disabled", true)
	
	print("[Debug Console] Entity %s." % ["ENABLED" if _entity_enabled else "DISABLED"])


func _call_entity_method(method_name: String) -> void:
	match method_name:
		"_force_relocate":
			_force_relocate()
		"_force_window_peek":
			_force_window_peek()
		"_toggle_stalking":
			_toggle_stalking()
		_:
			print("[Debug Console] Unknown entity method: %s" % method_name)
