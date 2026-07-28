extends Node

## RoutineManager — Day 1 Onboarding Phase System + Day 3+ Sandbox Mode.
##
## DAY 1–2: Linear gated main-objective system (objectives 0–8) plus
## Day 2 nest documentation tracked via nests_documented / nests_uploaded.
##
## DAY 3+ SANDBOX:
## Activated when is_day3_sandbox is set to true (by BedInteractable's
## exhaustion sleep). The linear schedule is paused and the player has
## total exploration freedom. Two parallel objective tracks appear:
##
##   MAIN PATH (Van Escape):  Find 3 car parts → repair van → escape
##   SIDE TRACK (Arvid's Purge): 9-step sequence ending in totem burning
##
## Both endings route through the van: ESCAPE_MEDIOCRE if totem not destroyed,
## ESCAPE_GOOD if totem was destroyed.
##
## MAIN OBJECTIVES (Day 1, fixed order):
##   0  — Go to the cabin
##   1  — Unlock the front door
##   2  — Log into the computer (first try — fails, auto-advances)
##   3  — Find the flashlight
##   4  — Replace the broken fuse in the fuse box
##   5  — Refuel the generator
##   6  — Log into the computer (successfully)
##   7  — Board up the broken window
##   8  — Lock the front door
##   9  — Go to bed
##
## Mains 4 and 5 can be done in either order. Once BOTH are done,
## the system advances to main 6.

signal routine_step_changed(step: int, objective_text: String)

# ─── DAY 3+ SANDBOX SIGNALS ──────────────────────────────────────────
## Emitted when the van repair checklist changes (part installed, repaired).
signal van_checklist_changed

## Emitted when the side-track progress changes (step advanced).
signal side_track_changed

# ═══════════════════════════════════════════════════════════════════════
# MAIN OBJECTIVE TRACKING
# ═══════════════════════════════════════════════════════════════════════

## Current main objective index (0–8). See docstring above for mapping.
## This is the single source of truth for where the player is in Day 1.
var main_objective: int = 0

# ═══════════════════════════════════════════════════════════════════════
# DAY 3+ SANDBOX MODE
# ═══════════════════════════════════════════════════════════════════════

## When true, the linear Day 1–2 schedule is paused and the player has
## full exploration freedom. Set by BedInteractable on exhaustion wake-up.
var is_day3_sandbox: bool = false

# ─── VAN ESCAPE CHECKLIST ────────────────────────────────────────────

## Whether the player has inspected the stranded van (activates the
## van checklist objective).
var van_inspected: bool = false

## Individual part installation tracking for notebook display.
var van_battery_installed: bool = false
var van_radiator_installed: bool = false
var van_wiring_installed: bool = false

## Total parts installed (0–3).
var van_parts_installed_count: int = 0

## Whether all 3 parts are installed and the van is ready to escape.
var van_fully_repaired: bool = false

# ─── SIDE-TRACK (Arvid's Legacy) FLAGS ───────────────────────────────
# These are stubs for Phase 2. Full side-track logic will be implemented
# separately, but the flags are declared here so NotebookUI can reference
# them and so EndgameManager can read is_anchor_destroyed.

## Side-track step index (0 = inactive, 1–9 = active sequence).
var side_track_step: int = 0

## Whether Arvid_Note_2 has been found (activates the side-track).
var arvid_note_2_found: bool = false

# — Arvid credentials & logs
var arvid_logged_in: bool = false        # STENBERG/1996 login
var arvid_logs_read: bool = false        # Recycle Bin logs opened

# — Quest item collection
var arvid_portable_light_found: bool = false
var arvid_cable_spool_found: bool = false
var arvid_fuel_can_found: bool = false   # Jerrycan — exclusively for totem
var arvid_anchor_located: bool = false   # Approached the TotemAnchor

# — Trap setup & execution
var is_cable_to_gen_connected: bool = false
var is_cable_to_light_connected: bool = false
var is_trap_triggered: bool = false      # Grid override executed on computer

# — Final state
var is_anchor_destroyed: bool = false    # Totem burned, Entity banished

# ═══════════════════════════════════════════════════════════════════════
# PHASE 1: ENTRY FLAGS
# ═══════════════════════════════════════════════════════════════════════

var phase1_approached_cabin: bool = false   # Walked near the cabin
var phase1_tried_door: bool = false          # Tried the locked door
var phase1_found_key: bool = false           # Picked up the Cabin Key
var phase1_entered_cabin: bool = false       # Stepped inside the cabin

# ═══════════════════════════════════════════════════════════════════════
# PHASE 2: POWER & LOG FLAGS
# ═══════════════════════════════════════════════════════════════════════

var phase2_computer_tried_no_power: bool = false  # Tried computer without power
var phase2_fuse_box_interacted: bool = false      # First interaction with fuse box
var phase2_fuse_picked_up: bool = false           # Picked up a fuse item
var phase2_fuse_inserted: bool = false            # Fuse inserted into box (switch not thrown yet)
var phase2_fuse_fixed: bool = false               # Fuse inserted + switch thrown
var phase2_fuel_can_picked_up: bool = false       # Picked up a fuel can (generic)
var phase2_gen_refilled: bool = false             # Generator refueled
var phase2_computer_used: bool = false            # Logged into computer

# ═══════════════════════════════════════════════════════════════════════
# PHASE 2B: PLANK & WINDOW FLAGS
# ═══════════════════════════════════════════════════════════════════════

var phase2b_plank_picked_up: bool = false    # Picked up a Wooden Plank

## Counter for how many Wooden Planks the player has picked up during Day 1.
## The x-ray highlight for planks persists until the player has collected 3
## planks (enough to fully board the broken tutorial window).
## Reset to 0 in reset_all_phases() and reset_objective_history().
var phase2b_plank_count: int = 0

var phase2b_window_patched: bool = false     # Barricaded the broken window

# ═══════════════════════════════════════════════════════════════════════
# PHASE 3: LOCKDOWN FLAGS
# ═══════════════════════════════════════════════════════════════════════

var phase3_door_locked: bool = false         # Front door locked
var phase3_bed_used: bool = false            # Went to bed

# ═══════════════════════════════════════════════════════════════════════
# NEST DOCUMENTATION (Day 2)
# ═══════════════════════════════════════════════════════════════════════

var nests_documented: int = 0
var nests_uploaded: bool = false

# ═══════════════════════════════════════════════════════════════════════
# INTERNAL
# ═══════════════════════════════════════════════════════════════════════

var _night_manager: Node = null
var _notebook_ui: Node = null

# ─── TUTORIAL / LEARNED MECHANICS ──────────────────────────────────────
## Tracks which mechanics the player has learned (e.g. "sprint", "interact").
## TutorialManager calls these to check if prompts should still show.
var _learned_mechanics: Dictionary = {}

# ─── X-RAY DELAYED HIGHLIGHT TIMERS ─────────────────────────────────
## Stores Timer references keyed by group_name so we can cancel pending
## highlights if the player finds the target before the delay expires.
var _xray_timers: Dictionary = {}


func _ready() -> void:
	_night_manager = get_node_or_null("/root/NightManager")
	print("[RoutineManager] Initialized. Main-objective gating active. Waiting for Phase 1 triggers.")


## ─── X-RAY HIGHLIGHT SYSTEM ─────────────────────────────────────────
## Preloaded ShaderMaterial for the x-ray overlay. Created once and
## duplicated for each target so per-instance uniforms don't conflict.
var _xray_material: Material = null


## Loads the x-ray highlight shader material lazily.
func _get_xray_material() -> Material:
	if _xray_material == null:
		var shader := load("res://shaders/xray_highlight.gdshader") as Shader
		if shader:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("highlight_color", Color(1.0, 0.9, 0.3, 0.5))
			_xray_material = mat
	return _xray_material


## Cancels a pending delayed highlight for the given group, if one exists.
func _cancel_xray_timer(group_name: String) -> void:
	if _xray_timers.has(group_name):
		var timer: Timer = _xray_timers[group_name]
		if is_instance_valid(timer):
			timer.stop()
			timer.queue_free()
		_xray_timers.erase(group_name)


## Schedules a delayed x-ray highlight for the given group.
## If delay is 0, applies immediately (no timer).
func highlight_target(group_name: String, delay: float = 0.0) -> void:
	# ─── DEBUG LOG: Trace every highlight call for nest debugging ─────
	# Always print when a nest-group highlight is scheduled so we can verify
	# that the call actually reaches this function. The call chain is:
	#   NightManager → RoutineManager.on_day2_started()
	#   → highlight_target("xray_nest_alpha", 20.0)
	#   → Timer fires → _on_xray_timer_timeout → _do_highlight_target
	if "nest" in group_name:
		print("[RoutineManager] NEST HIGHLIGHT CALLED: group='%s', delay=%.1fs" % [group_name, delay])
	
	# Cancel any existing timer for this group first
	_cancel_xray_timer(group_name)
	
	if delay <= 0.0:
		_do_highlight_target(group_name)
		return
	
	# Create a one-shot timer to apply the highlight after the delay
	var timer := Timer.new()
	timer.name = "_xray_timer_%s" % group_name
	timer.one_shot = true
	timer.wait_time = delay
	timer.timeout.connect(_on_xray_timer_timeout.bind(group_name))
	add_child(timer)
	_xray_timers[group_name] = timer
	timer.start()
	print("[RoutineManager] X-ray highlight scheduled for '%s' in %.1f seconds." % [group_name, delay])


## Called when a delayed x-ray timer fires.
func _on_xray_timer_timeout(group_name: String) -> void:
	_xray_timers.erase(group_name)
	_do_highlight_target(group_name)


## Internal: applies the x-ray highlight immediately to all nodes in the group.
func _do_highlight_target(group_name: String) -> void:
	var mat := _get_xray_material()
	if mat == null:
		push_error("[RoutineManager] X-ray material not available!")
		return
	
	var nodes := get_tree().get_nodes_in_group(group_name)
	if nodes.is_empty():
		push_warning("[RoutineManager] No nodes found in group '%s' for x-ray highlight." % group_name)
		return
	
	for node in nodes:
		if node is MeshInstance3D:
			_apply_xray_to_mesh(node, mat)
			node.extra_cull_margin = 100.0
			if "custom_aabb" in node:
				node.custom_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))
			var internal_meshes := node.find_children("*", "MeshInstance3D", true)
			for im in internal_meshes:
				_apply_xray_to_mesh(im, mat)
				im.extra_cull_margin = 100.0
				im.custom_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))
			print("[RoutineManager] X-ray highlight applied via next_pass to '%s' (group: %s)" % [node.name, group_name])
		else:
			var mesh_children := node.find_children("*", "MeshInstance3D", true)
			var applied_count := 0
			for mesh_child in mesh_children:
				_apply_xray_to_mesh(mesh_child, mat)
				mesh_child.extra_cull_margin = 100.0
				if "custom_aabb" in mesh_child:
					mesh_child.custom_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))
				applied_count += 1
			if applied_count > 0:
				print("[RoutineManager] X-ray highlight applied to %d MeshInstance3D children of '%s' (group: %s)" % [applied_count, node.name, group_name])
			elif "nest" in group_name:
				# ─── NEST DEBUG: Log when a nest node was found but had NO mesh children ──
				var scene_path: String = node.scene_file_path if node.has_method("get_scene_file_path") else node.scene_file_path if "scene_file_path" in node else "?"
				push_warning("[RoutineManager] NEST HIGHLIGHT FAILED: node '%s' (type=%s, scene='%s') has 0 MeshInstance3D children. find_children recursive found %d total descendants." % [node.name, node.get_class(), scene_path, node.get_child_count(true)])


## Applies x-ray next_pass material to a specific MeshInstance3D.
## Uses next_pass on the surface override material instead of material_overlay.
func _apply_xray_to_mesh(mesh: MeshInstance3D, xray_mat: Material) -> void:
	var existing_mat = null
	var mat_idx = 0
	
	if mesh.get_surface_override_material_count() > 0:
		existing_mat = mesh.get_surface_override_material(mat_idx)
	
	if not existing_mat and mesh.mesh:
		existing_mat = mesh.mesh.surface_get_material(mat_idx)
	
	if existing_mat:
		var clone = existing_mat.duplicate()
		var inst_xray = xray_mat.duplicate()
		clone.next_pass = inst_xray
		if mesh.has_meta("_xray_original_material"):
			mesh.remove_meta("_xray_original_material")
		mesh.set_meta("_xray_original_material", existing_mat.resource_path if existing_mat.resource_path else "")
		mesh.set_surface_override_material(mat_idx, clone)
		print("[RoutineManager] next_pass x-ray applied via surface_override_material on '%s'" % mesh.name)
	else:
		var base = StandardMaterial3D.new()
		base.albedo_color = Color.TRANSPARENT
		base.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var inst_xray = xray_mat.duplicate()
		base.next_pass = inst_xray
		if mesh.has_meta("_xray_original_material"):
			mesh.remove_meta("_xray_original_material")
		mesh.set_surface_override_material(mat_idx, base)
		print("[RoutineManager] next_pass x-ray applied via new fallback material on '%s'" % mesh.name)


## Removes the x-ray highlight from all nodes in the given group.
## Also cancels any pending delayed highlight for that group.
func clear_highlight(group_name: String) -> void:
	# Cancel any pending timer
	_cancel_xray_timer(group_name)
	
	var nodes := get_tree().get_nodes_in_group(group_name)
	for node in nodes:
		if node is MeshInstance3D:
			_clear_xray_from_mesh(node)
			var internal_meshes := node.find_children("*", "MeshInstance3D", true)
			for im in internal_meshes:
				_clear_xray_from_mesh(im)
			if node.has_meta("_xray_original_material"):
				node.remove_meta("_xray_original_material")
		else:
			var mesh_children := node.find_children("*", "MeshInstance3D", true)
			for mc in mesh_children:
				_clear_xray_from_mesh(mc)
	print("[RoutineManager] X-ray highlight cleared for group '%s'" % group_name)


## Clears the x-ray next_pass from a single MeshInstance3D.
func _clear_xray_from_mesh(mesh: MeshInstance3D) -> void:
	var mat_idx = 0
	if mesh.has_meta("_xray_original_material"):
		mesh.set_surface_override_material(mat_idx, null)
		mesh.remove_meta("_xray_original_material")
	else:
		var override_mat = mesh.get_surface_override_material(mat_idx)
		if override_mat:
			override_mat.next_pass = null


## ─── INVENTORY HELPERS ──────────────────────────────────────────────

func _player_has_item(item_name: String) -> bool:
	var inv = get_node_or_null("/root/Inventory")
	if not inv:
		return false
	for item in inv.items:
		if item and "item_name" in item and item.item_name == item_name:
			return true
	return false


## ─── MAIN OBJECTIVE ADVANCEMENT ─────────────────────────────────────

func _advance_main_objective(target: int) -> void:
	if target > main_objective:
		main_objective = target
		print("[RoutineManager] Main objective advanced to %d." % main_objective)

func _check_power_restored() -> void:
	if phase2_fuse_fixed and phase2_gen_refilled:
		print("[RoutineManager] Power restored! Both fuse and generator are done.")
		_advance_main_objective(6)
		_update_hud()


## ─── OBJECTIVE TEXT ─────────────────────────────────────────────────

func get_current_objective() -> String:
	if is_day3_sandbox:
		if not van_inspected:
			return "Investigate the car again."
		if van_fully_repaired:
			return "Start the van and escape."
		if van_parts_installed_count > 0:
			return "Repair the van (%d/3 parts)" % van_parts_installed_count
		return "Find parts to repair the van."
	
	if nests_uploaded:
		return "Lock the door and go to bed."
	if nests_documented >= 3:
		return "Upload nest data on the computer."
	if nests_documented > 0:
		return "Document the nests."
	
	if main_objective >= 99:
		return "Document the nests."
	
	match main_objective:
		0:
			return "Go to the cabin."
		1:
			if phase1_entered_cabin:
				_advance_main_objective(2)
				return get_current_objective()
			if _player_has_item("Cabin Key"):
				return "Unlock the front door."
			if phase1_tried_door:
				return "Find the key to the cabin."
			if phase1_approached_cabin:
				return "Go inside the cabin."
			return "Go to the cabin."
		2:
			return "Log into the computer."
		3:
			return "Find the flashlight."
		4:
			if phase2_fuse_fixed:
				_advance_main_objective(5)
				_check_power_restored()
				return get_current_objective()
			if phase2_fuse_inserted:
				return "Throw the switch to restore power."
			if _player_has_item("Fuse"):
				if phase2_fuse_box_interacted:
					return "Replace the broken fuse with the new fuse."
				else:
					return "Check the fuse box. You have a new fuse."
			if phase2_fuse_box_interacted:
				return "Find a fuse in the cabin."
			if phase2_computer_tried_no_power:
				return "Check the fuse box. It's always the god damn fuse box."
			return "Check the fuse box. It's always the god damn fuse box."
		5:
			if phase2_gen_refilled:
				_check_power_restored()
				return get_current_objective()
			if _player_has_item("Fuel Can"):
				return "Refill the generator."
			return "Find a fuel can to refill the generator."
		6:
			if phase2_computer_used:
				_advance_main_objective(7)
				return get_current_objective()
			return "Log into the computer."
		7:
			if phase2b_window_patched:
				_advance_main_objective(8)
				return get_current_objective()
			if _player_has_item("Wooden Plank"):
				return "Patch the window as well as you can."
			if phase2b_plank_picked_up:
				return "Patch the window as well as you can."
			return "Get some planks to patch the broken window."
		8:
			if phase3_door_locked:
				_advance_main_objective(9)
				return get_current_objective()
			return "Lock the front door."
		9:
			if phase3_bed_used:
				return "Day 1 complete. Rest well."
			return "Go to bed."
	
	return "Go to the cabin."


func _update_hud() -> void:
	var text = get_current_objective()
	var step: int = 0
	
	if is_day3_sandbox:
		if van_fully_repaired:
			step = 30
		elif van_parts_installed_count > 0:
			step = 20 + van_parts_installed_count
		else:
			step = 20
	elif nests_uploaded:
		step = 19
	elif nests_documented >= 3:
		step = 18
	elif nests_documented > 0:
		step = 17
	else:
		match main_objective:
			0: step = 0
			1:
				if _player_has_item("Cabin Key"): step = 3
				elif phase1_tried_door: step = 2
				else: step = 1
			2: step = 4
			3: step = 5
			4:
				if phase2_fuse_fixed: step = 8
				elif phase2_fuse_inserted: step = 8
				elif _player_has_item("Fuse"): step = 8
				elif phase2_fuse_box_interacted: step = 7
				else: step = 6
			5:
				if phase2_gen_refilled: step = 11
				elif _player_has_item("Fuel Can"): step = 10
				else: step = 9
			6: step = 12
			7:
				if _player_has_item("Wooden Plank") or phase2b_plank_picked_up: step = 14
				else: step = 13
			8: step = 15
			9: step = 16
	
	routine_step_changed.emit(step, text)
	print("[RoutineManager] HUD updated: Step %d — '%s'" % [step, text])


# ═══════════════════════════════════════════════════════════════════════
# DAY 3+ SANDBOX TRIGGERS
# ═══════════════════════════════════════════════════════════════════════

func on_car_part_collected(part_name: String) -> void:
	print("[RoutineManager] Car part collected: %s" % part_name)
	van_checklist_changed.emit()

func on_van_inspected() -> void:
	if van_inspected:
		return
	van_inspected = true
	print("[RoutineManager] Van inspected! Van escape checklist activated.")
	_update_hud()
	van_checklist_changed.emit()

func on_van_part_installed(part_name: String) -> void:
	match part_name:
		"Car Battery":
			van_battery_installed = true
		"Radiator":
			van_radiator_installed = true
		"Ignition Wiring":
			van_wiring_installed = true
	van_parts_installed_count += 1
	print("[RoutineManager] Van part installed: %s (%d/3)" % [part_name, van_parts_installed_count])
	_update_hud()
	van_checklist_changed.emit()

func on_van_repaired() -> void:
	if van_fully_repaired:
		return
	van_fully_repaired = true
	print("[RoutineManager] VAN FULLY REPAIRED! Ready to escape.")
	_update_hud()
	van_checklist_changed.emit()

func has_car_part_in_inventory(part_name: String) -> bool:
	return _player_has_item(part_name)

func enable_sandbox_mode() -> void:
	if is_day3_sandbox:
		return
	is_day3_sandbox = true
	print("[RoutineManager] DAY 3 SANDBOX MODE ACTIVATED!")
	_update_hud()


# ═══════════════════════════════════════════════════════════════════════
# SIDE-TRACK TRIGGERS
# ═══════════════════════════════════════════════════════════════════════

func on_arvid_note_2_found() -> void:
	if arvid_note_2_found:
		return
	arvid_note_2_found = true
	side_track_step = 1
	print("[RoutineManager] Arvid_Note_2 found! Unsanctioned Discoveries side-track activated.")
	side_track_changed.emit()

func on_arvid_logged_in() -> void:
	if arvid_logged_in:
		return
	arvid_logged_in = true
	if side_track_step < 2:
		side_track_step = 2
	print("[RoutineManager] Side-track: Logged in as STENBERG.")
	side_track_changed.emit()

func on_arvid_logs_read() -> void:
	if arvid_logs_read:
		return
	arvid_logs_read = true
	if side_track_step < 3:
		side_track_step = 3
	print("[RoutineManager] Side-track: Arvid's logs read.")
	side_track_changed.emit()

func on_portable_light_found() -> void:
	if arvid_portable_light_found:
		return
	arvid_portable_light_found = true
	if side_track_step < 4:
		side_track_step = 4
	print("[RoutineManager] Side-track: Portable light found.")
	side_track_changed.emit()

func on_cable_spool_found() -> void:
	if arvid_cable_spool_found:
		return
	arvid_cable_spool_found = true
	if side_track_step < 5:
		side_track_step = 5
	print("[RoutineManager] Side-track: Cable spool found.")
	side_track_changed.emit()

func on_fuel_can_found() -> void:
	if arvid_fuel_can_found:
		return
	arvid_fuel_can_found = true
	if side_track_step < 6:
		side_track_step = 6
	print("[RoutineManager] Side-track: Jerrycan of fuel found.")
	side_track_changed.emit()

func on_anchor_located() -> void:
	if arvid_anchor_located:
		return
	arvid_anchor_located = true
	if side_track_step < 7:
		side_track_step = 7
	print("[RoutineManager] Side-track: Totem Anchor located.")
	side_track_changed.emit()

func on_cable_connected_to_gen() -> void:
	if is_cable_to_gen_connected:
		return
	is_cable_to_gen_connected = true
	if side_track_step < 8:
		side_track_step = 8
	print("[RoutineManager] Side-track: Cable connected to generator.")
	side_track_changed.emit()

func on_cable_connected_to_light() -> void:
	if is_cable_to_light_connected:
		return
	is_cable_to_light_connected = true
	if side_track_step < 9:
		side_track_step = 9
	print("[RoutineManager] Side-track: Cable connected to portable light. Trap ready!")
	side_track_changed.emit()

func on_trap_triggered() -> void:
	if is_trap_triggered:
		return
	is_trap_triggered = true
	side_track_step = 10
	print("[RoutineManager] Side-track: Grid override executed!")
	side_track_changed.emit()

func on_anchor_destroyed() -> void:
	if is_anchor_destroyed:
		return
	is_anchor_destroyed = true
	side_track_step = 11
	print("[RoutineManager] Side-track COMPLETE! Totem Anchor destroyed!")
	side_track_changed.emit()


# ═══════════════════════════════════════════════════════════════════════
# PHASE 1 TRIGGERS
# ═══════════════════════════════════════════════════════════════════════

func on_cabin_approached() -> void:
	if phase1_approached_cabin:
		return
	phase1_approached_cabin = true
	_advance_main_objective(1)
	print("[RoutineManager] Phase 1: Player approached the cabin.")
	if _night_manager and _night_manager.has_method("unpause_time"):
		_night_manager.unpause_time()
	_update_hud()
	
	# ─── TUTORIAL FLOW: Force-dismiss notebook hint, show interact hint ──
	# The notebook hint ("Press J for Notebook") should be replaced by the
	# interact hint ("Press [E] to interact") when the player reaches the cabin.
	# This ensures the interact prompt takes priority at the cabin door.
	_force_dismiss_notebook_tutorial()
	_trigger_interact_tutorial()

func on_door_tried_locked() -> void:
	if phase1_tried_door:
		return
	phase1_tried_door = true
	print("[RoutineManager] Phase 1: Player tried the locked door.")
	_update_hud()
	# ─── X-RAY HIGHLIGHT: Cabin Key after 5 seconds ──
	highlight_target("xray_key", 5.0)

func on_key_picked_up() -> void:
	if phase1_found_key:
		return
	phase1_found_key = true
	print("[RoutineManager] Phase 1: Player found the Cabin Key.")
	_update_hud()
	# ─── X-RAY HIGHLIGHT: Clear key highlight ──
	clear_highlight("xray_key")

## Force-dismisses the notebook tutorial hint by marking it learned.
## Called when the player reaches the cabin approach trigger, so the
## interact hint can replace the notebook hint on screen.
func _force_dismiss_notebook_tutorial() -> void:
	var tm := get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("mark_learned"):
		tm.mark_learned("notebook")

func _trigger_notebook_tutorial() -> void:
	var tm := get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("trigger"):
		tm.trigger("notebook")

func _trigger_interact_tutorial() -> void:
	var tm := get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("trigger"):
		tm.trigger("interact")

func on_door_unlocked() -> void:
	if phase1_entered_cabin:
		return
	phase1_entered_cabin = true
	_advance_main_objective(2)
	print("[RoutineManager] Phase 1 COMPLETE! Player unlocked and entered the cabin.")
	_update_hud()

func on_player_entered_cabin() -> void:
	if phase1_entered_cabin:
		return
	phase1_entered_cabin = true
	_advance_main_objective(2)
	print("[RoutineManager] Phase 1 COMPLETE! Player entered the cabin (detected by room check).")
	_update_hud()


# ═══════════════════════════════════════════════════════════════════════
# PHASE 2 TRIGGERS
# ═══════════════════════════════════════════════════════════════════════

func on_fuse_box_interacted() -> void:
	if phase2_fuse_box_interacted:
		return
	phase2_fuse_box_interacted = true
	print("[RoutineManager] Phase 2: Player interacted with fuse box.")
	_update_hud()
	# ─── X-RAY HIGHLIGHT: Clear fuse box, highlight fuse after 10s ──
	clear_highlight("xray_fuse_box")
	highlight_target("xray_fuse", 10.0)

func on_fuse_picked_up() -> void:
	if phase2_fuse_picked_up:
		return
	phase2_fuse_picked_up = true
	print("[RoutineManager] Phase 2: Player picked up a fuse.")
	_update_hud()
	# ─── X-RAY HIGHLIGHT: Clear fuse highlight ──
	clear_highlight("xray_fuse")

func on_fuse_inserted() -> void:
	if phase2_fuse_inserted:
		return
	phase2_fuse_inserted = true
	print("[RoutineManager] Phase 2: Fuse inserted into fuse box.")
	_update_hud()

func on_fuse_fixed() -> void:
	if phase2_fuse_fixed:
		return
	phase2_fuse_fixed = true
	print("[RoutineManager] Phase 2: Fuse box fixed.")
	_update_hud()
	_check_power_restored()
	# ─── X-RAY HIGHLIGHT: Highlight fuel can after 10s (if generator not done) ──
	if not phase2_gen_refilled:
		highlight_target("xray_fuel_can", 10.0)

func on_fuel_can_picked_up() -> void:
	if phase2_fuel_can_picked_up:
		return
	phase2_fuel_can_picked_up = true
	print("[RoutineManager] Phase 2: Player picked up a fuel can.")
	_update_hud()
	# ─── X-RAY HIGHLIGHT: Clear fuel can highlight ──
	clear_highlight("xray_fuel_can")
	# Only highlight the generator if the player has already interacted with
	# the fuse box (i.e., they're actually on the fuel/generator objective).
	# Without this guard, picking up a fuel can early (before fuse objective)
	# or during dev mode startup would prematurely highlight the generator.
	if phase2_fuse_box_interacted:
		highlight_target("xray_generator", 5.0)

func on_generator_refilled() -> void:
	if phase2_gen_refilled:
		return
	phase2_gen_refilled = true
	print("[RoutineManager] Phase 2: Generator refilled.")
	_update_hud()
	_check_power_restored()
	# ─── X-RAY HIGHLIGHT: Clear generator highlight ──
	clear_highlight("xray_generator")

func on_computer_tried_no_power() -> void:
	if phase2_computer_tried_no_power:
		return
	phase2_computer_tried_no_power = true
	
	# ─── EARLY FLASHLIGHT CHECK (Bug 2 Fix) ──────────────────────────────
	# If the player already found the flashlight before reaching this point,
	# skip objective 3 ("Find the flashlight") and go directly to objective 4
	# ("Find the fuse box"). This prevents the player from getting stuck on an
	# objective they've already completed.
	if phase2_flashlight_early:
		_advance_main_objective(4)
		print("[RoutineManager] Phase 2: Player tried computer without power. Flashlight already found early — skipping to fuse objective.")
		highlight_target("xray_fuse_box", 5.0)
	else:
		_advance_main_objective(3)
		print("[RoutineManager] Phase 2: Player tried computer without power. Advancing to flashlight objective.")
		highlight_target("xray_flashlight", 5.0)
	_update_hud()

## Tracks whether the player picked up the flashlight before reaching
## the "Find the flashlight" objective (objective 3). When true,
## on_computer_tried_no_power() will skip objective 3 and go directly
## to objective 4 ("Find the fuse box").
var phase2_flashlight_early: bool = false

## Called by flashlight_pickup.gd when the player picks up the flashlight.
##
## If the player is already on objective 3 ("Find the flashlight"), advance
## to objective 4 ("Find the fuse box"). If the player picked it up early
## (objective < 3), set a flag so on_computer_tried_no_power() can skip
## objective 3 entirely when it arrives.
func on_flashlight_picked_up() -> void:
	if phase2_flashlight_early:
		return  # Already handled, prevent double-trigger
	if main_objective == 3:
		_advance_main_objective(4)
		print("[RoutineManager] Phase 2: Player found the flashlight. Advancing to fuse objective.")
		# ─── X-RAY HIGHLIGHT: Clear flashlight, highlight fuse box after 5s ──
		clear_highlight("xray_flashlight")
		highlight_target("xray_fuse_box", 5.0)
		_update_hud()
	else:
		# Player picked up the flashlight before reaching objective 3.
		# Set a flag so on_computer_tried_no_power() can skip objective 3.
		phase2_flashlight_early = true
		print("[RoutineManager] Phase 2: Player found the flashlight EARLY (objective %d). Will skip flashlight objective when reached." % main_objective)
		clear_highlight("xray_flashlight")

func on_computer_used() -> void:
	if phase2_computer_used:
		return
	phase2_computer_used = true
	_advance_main_objective(7)
	print("[RoutineManager] Phase 2 COMPLETE! Player logged into the computer.")
	_update_hud()
	# ─── X-RAY HIGHLIGHT: Highlight planks after 10 seconds ──
	highlight_target("xray_planks", 10.0)


# ═══════════════════════════════════════════════════════════════════════
# PHASE 2B TRIGGERS (Plank & Window)
# ═══════════════════════════════════════════════════════════════════════

func on_plank_picked_up() -> void:
	phase2b_plank_picked_up = true
	phase2b_plank_count += 1
	print("[RoutineManager] Phase 2B: Player picked up a Wooden Plank (count: %d/3)." % phase2b_plank_count)
	_update_hud()
	# ─── X-RAY HIGHLIGHT: Clear plank highlight only after 3 planks ──
	if phase2b_plank_count >= 3:
		clear_highlight("xray_planks")
		print("[RoutineManager] Phase 2B: Player has 3 planks. X-ray highlight cleared.")

func on_window_patched() -> void:
	if phase2b_window_patched:
		return
	phase2b_window_patched = true
	_advance_main_objective(8)
	print("[RoutineManager] Phase 2B COMPLETE! Player patched the broken window.")
	_update_hud()


# ═══════════════════════════════════════════════════════════════════════
# PHASE 3 TRIGGERS
# ═══════════════════════════════════════════════════════════════════════

func on_door_locked() -> void:
	if phase3_door_locked:
		return
	phase3_door_locked = true
	_advance_main_objective(9)
	print("[RoutineManager] Phase 3: Front door locked.")
	_update_hud()

func on_bed_interacted() -> bool:
	if not phase2b_window_patched:
		print("[RoutineManager] Phase 3: Player tried bed but window is not patched.")
		return false
	
	if not phase3_door_locked:
		var door_nodes = get_tree().get_nodes_in_group("Door")
		var door_is_locked = false
		for d in door_nodes:
			if "is_locked" in d and d.is_locked:
				door_is_locked = true
				phase3_door_locked = true
				break
		if not door_is_locked:
			print("[RoutineManager] Phase 3: Player tried bed but front door is NOT locked.")
			return false
	
	phase3_bed_used = true
	print("[RoutineManager] Phase 3 COMPLETE! Player went to bed. Transitioning to Day 2.")
	_update_hud()
	return true


# ═══════════════════════════════════════════════════════════════════════
# NEST DOCUMENTATION (Day 2)
# ═══════════════════════════════════════════════════════════════════════

## Called when NightManager advances to Day 2.
## Starts the nest highlighting sequence: Nest Alpha after 20s.
func on_day2_started() -> void:
	print("[RoutineManager] Day 2 started. Scheduling Nest Alpha highlight in 20 seconds.")
	highlight_target("xray_nest_alpha", 20.0)

func document_nest(nest_id: String) -> void:
	nests_documented += 1
	print("[RoutineManager] Nest '%s' documented! (%d/3)" % [nest_id, nests_documented])
	
	# ─── X-RAY HIGHLIGHT: Sequential nest highlighting ──
	match nest_id:
		"Nest Alpha":
			clear_highlight("xray_nest_alpha")
			if nests_documented < 3:
				print("[RoutineManager] Scheduling Nest Beta highlight in 20 seconds.")
				highlight_target("xray_nest_beta", 20.0)
		"Nest Beta":
			clear_highlight("xray_nest_beta")
			if nests_documented < 3:
				print("[RoutineManager] Scheduling Nest Gamma highlight in 20 seconds.")
				highlight_target("xray_nest_gamma", 20.0)
		"Nest Gamma":
			clear_highlight("xray_nest_gamma")
	
	if nests_documented >= 3:
		print("[RoutineManager] All 3 nests documented! Player should upload data on the computer.")
		_update_hud()


func on_nest_data_uploaded() -> void:
	if nests_uploaded:
		return
	nests_uploaded = true
	print("[RoutineManager] Nest data uploaded on computer! Player should go to bed.")
	_update_hud()


# ═══════════════════════════════════════════════════════════════════════
# UTILITY
# ═══════════════════════════════════════════════════════════════════════

func get_current_day_string() -> String:
	var nm = get_node_or_null("/root/NightManager")
	if not nm:
		return "Day ?"
	var night: int = nm.current_night
	if night <= 0:
		return "Day 1"
	if nm.is_night_active:
		return "Night " + str(night)
	return "Day " + str(night)

func advance_step() -> void:
	print("[RoutineManager] advance_step() called (deprecated).")
	_update_hud()

func mark_mechanic_learned(mechanic_id: String) -> void:
	_learned_mechanics[mechanic_id] = true

func is_mechanic_learned(mechanic_id: String) -> bool:
	return _learned_mechanics.get(mechanic_id, false)

func reset_objective_history() -> void:
	main_objective = 99
	
	phase1_approached_cabin = false
	phase1_tried_door = false
	phase1_found_key = false
	phase1_entered_cabin = false
	
	phase2_computer_tried_no_power = false
	phase2_fuse_box_interacted = false
	phase2_fuse_picked_up = false
	phase2_fuse_inserted = false
	phase2_fuse_fixed = false
	phase2_fuel_can_picked_up = false
	phase2_gen_refilled = false
	phase2_computer_used = false
	
	phase2b_plank_picked_up = false
	phase2b_plank_count = 0
	phase2b_window_patched = false
	
	phase3_door_locked = false
	phase3_bed_used = false
	
	print("[RoutineManager] Objective history reset. Day 1 gating state cleared for new day.")
	_update_hud()


func reset_all_phases() -> void:
	main_objective = 0
	
	is_day3_sandbox = false
	van_inspected = false
	van_battery_installed = false
	van_radiator_installed = false
	van_wiring_installed = false
	van_parts_installed_count = 0
	van_fully_repaired = false
	
	side_track_step = 0
	arvid_note_2_found = false
	arvid_logged_in = false
	arvid_logs_read = false
	arvid_portable_light_found = false
	arvid_cable_spool_found = false
	arvid_fuel_can_found = false
	arvid_anchor_located = false
	is_cable_to_gen_connected = false
	is_cable_to_light_connected = false
	is_trap_triggered = false
	is_anchor_destroyed = false
	
	phase1_approached_cabin = false
	phase1_tried_door = false
	phase1_found_key = false
	phase1_entered_cabin = false
	
	phase2_computer_tried_no_power = false
	phase2_fuse_box_interacted = false
	phase2_fuse_picked_up = false
	phase2_fuse_inserted = false
	phase2_fuse_fixed = false
	phase2_fuel_can_picked_up = false
	phase2_gen_refilled = false
	phase2_computer_used = false
	
	phase2b_plank_picked_up = false
	phase2b_plank_count = 0
	phase2b_window_patched = false
	
	phase3_door_locked = false
	phase3_bed_used = false
	
	print("[RoutineManager] All phases reset.")
	_update_hud()