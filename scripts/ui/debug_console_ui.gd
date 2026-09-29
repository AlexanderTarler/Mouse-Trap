extends CanvasLayer

## Debug Console UI — Overlay with buttons to manipulate game state.
## Instantiated by debug_computer.gd when the player interacts with the computer prop.

signal console_closed

# References to game systems
var _night_manager: Node = null
var _entity: Entity = null
var _player: Node = null
var _is_open: bool = false

# Entity enable/disable toggle state
var _entity_enabled: bool = true
var _entity_toggle_btn: Button = null

# Entity can_kill toggle state
var _entity_can_kill: bool = true
var _can_kill_toggle_btn: Button = null

# Peeker vanish-on-sight toggle state
var _peeker_vanish_on_sight: bool = true
var _peeker_vanish_toggle_btn: Button = null

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
	
	# Add a "Head to Bedroom" button that sets up the game state as if the
	# player has completed most Day 1 tasks and needs to go to sleep.
	var bedroom_btn = Button.new()
	bedroom_btn.text = "Head to Bedroom"
	bedroom_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bedroom_btn.pressed.connect(_setup_bedroom_state)
	night_grid.add_child(bedroom_btn)


func _setup_entity_buttons() -> void:
	var buttons_data = [
		{"text": "Force Relocate", "method": "_force_relocate"},
		{"text": "Force Window Peek", "method": "_force_window_peek"},
		{"text": "Force Door Approach", "method": "_force_door_approach"},
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
	
	# Entity can_kill toggle button (persistent state)
	_can_kill_toggle_btn = Button.new()
	_can_kill_toggle_btn.text = "Can Kill: YES"
	_can_kill_toggle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_can_kill_toggle_btn.pressed.connect(_toggle_can_kill)
	entity_section.add_child(_can_kill_toggle_btn)
	
	# Peeker vanish-on-sight toggle button (persistent state)
	_peeker_vanish_toggle_btn = Button.new()
	_peeker_vanish_toggle_btn.text = "Peeker Vanish: YES"
	_peeker_vanish_toggle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_peeker_vanish_toggle_btn.pressed.connect(_toggle_peeker_vanish)
	entity_section.add_child(_peeker_vanish_toggle_btn)


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
	_entity = get_tree().get_first_node_in_group("entity") as Entity
	
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


func _process(delta: float) -> void:
	if not _is_open:
		return
	
	# Periodically capture the latest print output
	_log_timer += delta
	if _log_timer >= LOG_UPDATE_INTERVAL:
		_log_timer = 0.0
		_refresh_log()


func _refresh_log() -> void:
	var lines: Array[String] = []
	
	# ─── FPS COUNTER ───────────────────────────────────────────────────
	var fps = Engine.get_frames_per_second()
	var frame_time = snapped(1000.0 / fps, 0.1) if fps > 0 else 0.0
	var fps_color = "green"
	if fps < 30:
		fps_color = "red"
	elif fps < 55:
		fps_color = "yellow"
	lines.append("[b]FPS:[/b] [color=%s]%d[/color] (%.1f ms/frame)" % [fps_color, fps, frame_time])
	
	# ─── MEMORY INFO ──────────────────────────────────────────────────
	var mem_mb = snapped(OS.get_static_memory_usage() / (1024.0 * 1024.0), 0.1)
	lines.append("[b]Memory:[/b] %.1f MB static" % mem_mb)
	
	# ─── NIGHT INFO ───────────────────────────────────────────────────
	if _night_manager:
		lines.append("[b]Night:[/b] %d | Active: %s | Progress: %.0f%%" % [
			_night_manager.current_night,
			"YES" if _night_manager.is_night_active else "NO",
			_night_manager.night_progress * 100.0
		])
	
	# ─── ENTITY INFO ──────────────────────────────────────────────────
	if _entity:
		var state_name: String = _entity.get_state_name()
		var pos: Vector3 = _entity.global_position
		var dist = pos.distance_to(_player.global_position) if _player else 0.0
		var state_color = "white"
		match state_name:
			"CHARGE", "HUNT", "BREACH", "ENTER":
				state_color = "red"
			"STALK", "APPROACH", "PEEK", "SEARCH":
				state_color = "orange"
			"OBSERVE", "DORMANT":
				state_color = "gray"
		lines.append("[b]Entity:[/b] [color=%s]%s[/color] | Dist=%.1f" % [state_color, state_name, dist])
		lines.append("  Pos=(%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z])
		var perception = _entity.perception
		lines.append("  Sees=%s | Heard recently=%s" % [
			"YES" if perception.can_see_player else "NO",
			"YES" if perception.has_fresh_noise(3.0) else "NO"])
		lines.append("  Confidence: %.0f%s" % [_entity.confidence.get_confidence(),
			" (relaxing)" if _entity.confidence.is_relaxing() else ""])
	
	# ─── PLAYER INFO ──────────────────────────────────────────────────
	if _player:
		var ppos = _player.global_position
		lines.append("[b]Player:[/b] Pos=(%.1f, %.1f, %.1f)" % [ppos.x, ppos.y, ppos.z])
		
		# Player movement state
		if _player.has_method("get_current_state_name"):
			lines.append("  State: %s" % _player.get_current_state_name())
	
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


## Sets up the game state as if the player has completed all Day 1 tasks
## and needs to head to the bedroom to sleep. This is a "late Day 1" state:
##   - Time is set to late afternoon (cycle_progress ~0.35, ~20:00), paused
##   - RoutineManager is at Step 4 (all 3 nests documented, data uploaded,
##     generator refueled, door locked, lights off)
##   - Generator is ON with partial fuel
##   - Fuse box is repaired (state 2 = REPAIRED)
##   - Player has a reasonable inventory (batteries, planks, fuel)
##   - Entity is dormant (not yet active — Night 1 narrative hasn't started)
##   - Player is teleported to the cabin interior near the bedroom
##   - HUD objective is set to "Head to the bedroom and sleep"
func _setup_bedroom_state() -> void:
	print("[Debug Console] Setting up 'Head to Bedroom' state...")
	
	# ─── TIME SETUP ──────────────────────────────────────────────────
	# Set time to late afternoon (cycle_progress ~0.35 = ~20:00).
	# This is before nightfall but late enough that the player should
	# be heading to bed. Time is paused so the player can explore.
	var gt = get_node_or_null("/root/GameTime")
	if gt and gt.has_method("set_progress"):
		gt.set_progress(0.35)
		gt.is_time_paused = true
		print("[Debug Console] Time set to late afternoon (progress: 0.35).")
	
	# Force the EnvironmentController to update sky/lighting immediately.
	var ec = get_node_or_null("/root/CottageHorror/EnvironmentController")
	if not ec:
		ec = get_node_or_null("/root/Main/EnvironmentController")
	if ec and ec.has_method("_apply_cycle"):
		ec._apply_cycle()
		print("[Debug Console] EnvironmentController refreshed.")
	
	# ─── NIGHT MANAGER SETUP ─────────────────────────────────────────
	if _night_manager:
		# Ensure we're on Night 1
		_night_manager.current_night = 1
		_night_manager.is_night_active = false
		_night_manager.is_day_active = true
		_night_manager.night_progress = 0.0
		_night_manager._triggered_events.clear()
		
		# Generator is ON with partial fuel (player has been using it)
		_night_manager.is_generator_on = true
		_night_manager.generator_fuel = 35.0
		_night_manager.fuel_changed.emit(_night_manager.generator_fuel)
		_night_manager.generator_state_changed.emit(true)
		print("[Debug Console] Generator ON with %.1f fuel." % _night_manager.generator_fuel)
	
	# ─── FUSE BOX SETUP ─────────────────────────────────────────────
	# Set the fuse box to REPAIRED state (state 2).
	var fuse_box = get_tree().get_first_node_in_group("interactable")
	if fuse_box and fuse_box is FuseBox:
		fuse_box.current_state = 2  # BoxState.REPAIRED
		if fuse_box.has_method("_set_generator_state"):
			fuse_box._set_generator_state(true)
		print("[Debug Console] Fuse box set to REPAIRED.")
	
	# ─── CABIN LIGHTS ───────────────────────────────────────────────
	# Turn OFF all cabin lights — the player has completed the "turn off lights" step.
	var cabin_lights = get_tree().get_nodes_in_group("CabinLights")
	for light in cabin_lights:
		if "is_switched_on" in light:
			light.is_switched_on = false
		if "turn_off" in light:
			light.turn_off()
	print("[Debug Console] All cabin lights turned off.")
	
	# ─── ROUTINE MANAGER SETUP ──────────────────────────────────────
	# Set the RoutineManager to Step 4 ("Head to the bedroom").
	# This simulates the player having completed:
	#   Step 0: Documented all 3 nests
	#   Step 1: Uploaded nest data on the computer
	#   Step 2: Refilled the generator
	#   Step 3: Locked the door and turned off lights
	var rm = get_node_or_null("/root/RoutineManager")
	if rm:
		rm.nests_documented = 3
		rm.current_step = 4
		rm.routine_completed = false
		print("[Debug Console] RoutineManager set to Step 4 (all nests documented).")
		
		# Mark all 3 nests as photographed/documented
		var nests = get_tree().get_nodes_in_group("hasselmus_nests")
		for nest in nests:
			if nest.has_method("photograph"):
				nest.is_photographed = true
				nest.is_documented = true
			elif "is_photographed" in nest:
				nest.is_photographed = true
				nest.is_documented = true
		print("[Debug Console] All %d nests marked as documented." % nests.size())
		
		# Mark the computer UI as having uploaded nest data
		var computer_ui = get_tree().get_first_node_in_group("computer_ui")
		if computer_ui and "nest_data_uploaded" in computer_ui:
			computer_ui.nest_data_uploaded = true
			print("[Debug Console] Computer UI marked as data uploaded.")
	
	# ─── DOOR SETUP ─────────────────────────────────────────────────
	# Lock the front door — the player has completed the "lock the door" step.
	var doors = get_tree().get_nodes_in_group("interactable")
	for door in doors:
		if door is AnimatableBody3D and door.has_method("interact"):
			# Check if this is the front door by looking for the required_key_name
			if "required_key_name" in door and door.required_key_name != "":
				door.is_locked = true
				print("[Debug Console] Door '%s' locked." % door.name)
	
	# ─── PLAYER SETUP ───────────────────────────────────────────────
	var player = get_tree().get_first_node_in_group("player") as Node3D
	if player:
		# Teleport to cabin interior near the bedroom hallway
		var spawn_marker = get_tree().get_first_node_in_group("BedroomSpawn") as Node3D
		if not spawn_marker:
			spawn_marker = get_tree().get_first_node_in_group("PlayerSpawn") as Node3D
		if spawn_marker:
			player.global_position = spawn_marker.global_position
		else:
			# Fallback: cabin interior position near bedroom door
			player.global_position = Vector3(9.0, 1.0, 0.4)
		
		# Restore health/sanity
		if player.has_method("reset_health"):
			player.reset_health()
		elif "health" in player:
			player.health = 100.0
		if "sanity" in player:
			player.sanity = 100.0
		
		# Restore flashlight battery
		var flashlight = player.find_child("*Flashlight*", true, false)
		if flashlight:
			if flashlight.has_method("set_battery_level"):
				flashlight.set_battery_level(100.0)
			elif "battery_level" in flashlight:
				flashlight.battery_level = 100.0
		
		print("[Debug Console] Player teleported to bedroom area.")
	
	# ─── INVENTORY SETUP ────────────────────────────────────────────
	# Give the player a reasonable "end of day" inventory.
	var inv = get_node_or_null("/root/Inventory")
	if inv:
		inv.clear()
		
		var battery_res = load("res://resources/battery_resource.tres")
		var plank_res = load("res://resources/plank_resource.tres")
		var fuel_can_res = load("res://resources/fuel_can_resource.tres")
		var fuse_res = load("res://resources/fuse_resource.tres")
		
		# 2 Batteries (player has used some)
		for i in range(2):
			if battery_res and inv.has_method("add_item"):
				inv.add_item(battery_res.duplicate())
		
		# 1 Plank (player has used one to board a window)
		if plank_res and inv.has_method("add_item"):
			inv.add_item(plank_res.duplicate())
		
		# 1 Fuel Can (player has used one)
		if fuel_can_res and inv.has_method("add_item"):
			inv.add_item(fuel_can_res.duplicate())
		
		# 1 Fuse (player has a spare)
		if fuse_res and inv.has_method("add_item"):
			inv.add_item(fuse_res.duplicate())
		
		print("[Debug Console] Inventory set to end-of-day loadout.")
	
	# ─── ENTITY SETUP ───────────────────────────────────────────────
	# Deactivate the Entity — it should be dormant during the day.
	if _entity:
		_entity.deactivate()
		_entity.set_meta("debug_disabled", false)
		print("[Debug Console] Entity deactivated (dormant).")
	
	# ─── HUD OBJECTIVE ──────────────────────────────────────────────
	# Set the HUD objective to guide the player to the bedroom.
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and "objective_text" in hud:
		hud.objective_text = "Head to the bedroom and sleep"
		print("[Debug Console] HUD objective set: 'Head to the bedroom and sleep'.")
	
	print("[Debug Console] 'Head to Bedroom' state setup complete!")


func _force_relocate() -> void:
	if not _entity:
		print("[Debug Console] Entity not found.")
		return
	_entity.debug_relocate()
	print("[Debug Console] Entity relocated to a treeline vantage point.")


## Sends the Entity to a window (preferring dark rooms) to peek in.
func _force_window_peek() -> void:
	if not _entity:
		print("[Debug Console] Entity not found.")
		return
	var windows: Array = _entity.world.entries().filter(
		func(link): return link.kind == CabinEntryLink.Kind.WINDOW)
	if windows.is_empty():
		print("[Debug Console] No window entry links found.")
		return
	var dark: Array = windows.filter(func(link): return not _entity.world.is_entry_lit(link))
	var entry = (dark if not dark.is_empty() else windows).pick_random()
	_entity.request_state(Entity.State.APPROACH, {"entry": entry})
	print("[Debug Console] Entity approaching window '%s'." % entry.entry.name)


## Unlocks the front door and sends the Entity to it.
func _force_door_approach() -> void:
	if not _entity:
		print("[Debug Console] Entity not found.")
		return
	var doors: Array = _entity.world.entries().filter(
		func(link): return link.kind == CabinEntryLink.Kind.DOOR)
	if doors.is_empty():
		print("[Debug Console] No door entry link found.")
		return
	var entry = doors[0]
	if entry.entry.is_locked:
		entry.entry.is_locked = false
		print("[Debug Console] Door was locked. Unlocked for the debug approach.")
	_entity.request_state(Entity.State.APPROACH, {"entry": entry})
	print("[Debug Console] Entity approaching the door.")


func _toggle_stalking() -> void:
	if not _entity:
		print("[Debug Console] Entity not found.")
		return
	if _entity.is_active():
		_entity.deactivate()
		print("[Debug Console] Entity deactivated (DORMANT).")
	else:
		_entity.activate()
		_entity.request_state(Entity.State.OBSERVE)
		print("[Debug Console] Entity activated (OBSERVE).")


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
		_entity.request_state(Entity.State.OBSERVE)
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


## Toggles the Entity's can_kill flag between true and false.
## When false, the Entity will CHARGE the player but NOT capture/kill them.
## The Entity stops short and transitions back to CHASE/OBSERVE instead.
## This is useful for testing chase behavior without triggering death scenes.
## Updates the toggle button text and color to reflect the current state.
func _toggle_can_kill() -> void:
	if not _entity:
		print("[Debug Console] Entity not found.")
		return
	
	_entity_can_kill = not _entity_can_kill
	
	_entity.can_kill = _entity_can_kill
	
	if _entity_can_kill:
		_can_kill_toggle_btn.text = "Can Kill: YES"
		_can_kill_toggle_btn.remove_theme_color_override("font_color")
	else:
		_can_kill_toggle_btn.text = "Can Kill: NO"
		# Color the button red when disabled for visual clarity
		_can_kill_toggle_btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	
	print("[Debug Console] Can Kill: %s." % ["YES" if _entity_can_kill else "NO"])


## Toggles the Peeker's vanish-on-sight behavior between true and false.
## When false, the peeker will NOT vanish when the player looks at it —
## it stays visible and completes its full animation cycle.
## This is useful for testing the peeker's animation without it disappearing.
## Updates the toggle button text and color to reflect the current state.
func _toggle_peeker_vanish() -> void:
	_peeker_vanish_on_sight = not _peeker_vanish_on_sight
	
	# Sync with the PeekerManager autoload
	var pm = get_node_or_null("/root/PeekerManager")
	if pm:
		pm.peeker_vanish_on_sight = _peeker_vanish_on_sight
	
	if _peeker_vanish_on_sight:
		_peeker_vanish_toggle_btn.text = "Peeker Vanish: YES"
		_peeker_vanish_toggle_btn.remove_theme_color_override("font_color")
	else:
		_peeker_vanish_toggle_btn.text = "Peeker Vanish: NO"
		# Color the button red when disabled for visual clarity
		_peeker_vanish_toggle_btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	
	print("[Debug Console] Peeker Vanish on Sight: %s." % ["YES" if _peeker_vanish_on_sight else "NO"])


func _call_entity_method(method_name: String) -> void:
	match method_name:
		"_force_relocate":
			_force_relocate()
		"_force_window_peek":
			_force_window_peek()
		"_force_door_approach":
			_force_door_approach()
		"_toggle_stalking":
			_toggle_stalking()
		_:
			print("[Debug Console] Unknown entity method: %s" % method_name)
