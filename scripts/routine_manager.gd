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
##   3  — (unused: "Find the flashlight" is an interruption, see below)
##   4  — Replace the broken fuse in the fuse box
##   5  — Refuel the generator, then turn it on
##   6  — Log into the computer (successfully)
##   7  — Board up the broken window
##   8  — Lock the front door
##   9  — Turn off the lights
##   10 — Go to bed
##
## Mains 4 and 5 can be done in either order. Once BOTH are done,
## the system advances to main 6.
##
## "Find the flashlight" isn't in the chain: when Night 1 falls and the
## player has no flashlight, it takes over whatever the objective is
## (flashlight_needed); finding the flashlight hands the objective back.

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
# DAY 2 SEQUENTIAL NEST TUTORIAL
# ═══════════════════════════════════════════════════════════════════════

## Day 2 step index (0 = not started, 1–5 = active sequential steps).
## 1: Read the previous nest reports on the computer.
## 2: Locate and document Nest Alpha.
## 3: Locate and document Nest Beta.
## 4: Locate and document Nest Gamma.
## 5: Log the collected nest data into the cabin's computer terminal.
var day2_step: int = 0

## Whether the player has opened the notebook on Day 2 (Step 1 gate).
var day2_notebook_opened: bool = false

## Whether the cabin front door has been unlocked for Day 2 (Step 1 reward).
var day2_door_unlocked: bool = false

## Dynamic hint injected into the Notebook To-Do list for the active Day 2 step.
var day2_hint_text: String = ""

## Lore-friendly hints for each Day 2 nest step, keyed by nest label.
const DAY2_NEST_HINTS: Dictionary = {
	"Nest Alpha": "I may need a high-intensity beam to provoke them.",
	"Nest Beta": "I should sneak while approaching the nest.",
	"Nest Gamma": "I must remain perfectly still to hear them.",
}

## Emitted when the active Day 2 hint text changes (for NotebookUI To-Do display).
signal objective_hint_changed(hint_text: String)

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

## ─── CAR PART COLLECTION TRACKING (Battery / Radiator / Wiring) ──
## Set to true by on_car_part_collected() when the player PICK UP the
## part from a scrap heap. The notebook renders a collected part as [X]
## (objective complete). These are distinct from the van_X_installed flags,
## which only become true once the part is physically installed in the van
## (escape_van.gd → on_van_part_installed()).
var van_battery_collected: bool = false
var van_radiator_collected: bool = false
var van_wiring_collected: bool = false

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
var phase2_gen_turned_on: bool = false            # Generator switch flipped ON (post-refuel step)
var phase2_computer_used: bool = false            # Logged into computer

# ═══════════════════════════════════════════════════════════════════════
# PHASE 2B: PLANK & WINDOW FLAGS
# ═══════════════════════════════════════════════════════════════════════

var phase2b_plank_picked_up: bool = false    # Picked up a Wooden Plank

## ─── TASK 3: WINDOW BOARDING PROGRESSION LOCK ──────────────────────────
## When true, windows are explicitly unlocked for boarding in the story.
## Set to true when the Day 1 "Board up the broken window" objective begins
## (on_computer_used()), and kept true from Night 2+ (on_day2_started(),
## enable_sandbox_mode()) so late-game windows are always boardable.
## CabinWindow._can_board_this_window() reads this flag — boarding must
## NEVER bypass it.
var windows_unlocked_for_boarding: bool = false

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
var phase3_hall_light_off: bool = false      # Hall light switched off (post-door-lock step)
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
	if _night_manager and _night_manager.has_signal("night_started"):
		_night_manager.night_started.connect(_on_night_started)
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
## The bed glows while the objective is to go to bed, like other objectives.
var _bed_highlighted := false


func _update_bed_highlight(objective: String) -> void:
	var wanted := "go to bed" in objective.to_lower()
	if wanted == _bed_highlighted:
		return
	_bed_highlighted = wanted
	if wanted:
		highlight_target("xray_bed")
	else:
		clear_highlight("xray_bed")


func highlight_target(group_name: String, delay: float = 0.0) -> void:
	# ─── DEBUG LOG: Trace every highlight call for nest debugging ─────
	# Always print when a nest-group highlight is scheduled so we can verify
	# that the call actually reaches this function. The call chain is:
	#   RoutineManager.on_previous_reports_read()
	#   → highlight_target("xray_nest_alpha", 35.0)
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


## ─── TASK 2.4: OBJECT HIGHLIGHT GLOBAL TOGGLE ──────────────────────────
## Static global setting controlling whether interactable objects receive
## the x-ray highlight material overlay. When false, the highlight is not
## applied — players with visual sensitivities (or those who prefer no
## highlighting) can disable it. Toggle this from the Options menu.
static var enable_object_highlights: bool = true


## Internal: applies the x-ray highlight immediately to all nodes in the group.
func _do_highlight_target(group_name: String) -> void:
	# ─── TASK 2.4: HIGHLIGHT DISABLED GUARD ─────────────────────
	# If the player disabled object highlights in Settings, skip applying
	# the x-ray material entirely. Clear_highlight() still works normally
	# (it's a no-op when nothing is highlighted), so no other logic breaks.
	if not enable_object_highlights:
		print("[RoutineManager] TASK 2.4: Object highlights disabled. Skipping highlight for group '%s'." % group_name)
		return
	
	var mat := _get_xray_material()
	if mat == null:
		push_error("[RoutineManager] X-ray material not available!")
		return
	
	var nodes := get_tree().get_nodes_in_group(group_name)
	if nodes.is_empty():
		push_warning("[RoutineManager] No nodes found in group '%s' for x-ray highlight." % group_name)
		return
	
	# ─── ISSUE 1 FIX: EXPORTED HIGHLIGHT TARGET RESTRICTION ──────────
	# Some groups (e.g. xray_generator) declare an exported NodePath
	# `highlight_target` on an interaction node in the group. When present,
	# the x-ray overlay is restricted to THAT node's subtree only, so the
	# generator's button box is highlighted instead of the entire pipe/body
	# mesh. This is more robust than name-based filtering (_should_highlight_mesh).
	var restricted_target: Node = null
	for node in nodes:
		if "highlight_target" in node and node.highlight_target is NodePath and not node.highlight_target.is_empty():
			var resolved := node.get_node_or_null(node.highlight_target)
			if resolved:
				restricted_target = resolved
				break
	
	if restricted_target:
		_apply_xray_to_subtree(restricted_target, mat, group_name)
		return
	
	for node in nodes:
		var meshes: Array = node.find_children("*", "MeshInstance3D", true)
		if node is MeshInstance3D:
			meshes.push_front(node)
		var applied_count := 0
		for mesh in meshes:
			if _should_highlight_mesh(mesh, group_name):
				_apply_xray_to_mesh(mesh, mat)
				applied_count += 1
		if applied_count > 0:
			print("[RoutineManager] X-ray highlight applied to %d mesh(es) of '%s' (group: %s)" % [applied_count, node.name, group_name])
		elif "nest" in group_name:
			push_warning("[RoutineManager] NEST HIGHLIGHT FAILED: node '%s' (type=%s, scene='%s') has no meshes." % [node.name, node.get_class(), node.scene_file_path])


## Applies the x-ray highlight to a single node and all MeshInstance3D
## descendants inside it (respecting _should_highlight_mesh filters).
## This is the restricted-subtree path used when a group declares an
## exported `highlight_target` NodePath (e.g. xray_generator → button box).
func _apply_xray_to_subtree(root: Node, mat: Material, group_name: String) -> void:
	var meshes: Array = root.find_children("*", "MeshInstance3D", true)
	if root is MeshInstance3D:
		meshes.push_front(root)
	var applied_count := 0
	for m in meshes:
		if _should_highlight_mesh(m, group_name):
			_apply_xray_to_mesh(m, mat)
			applied_count += 1
	print("[RoutineManager] X-ray highlight restricted to target '%s' (%d meshes, group: %s)." % [root.name, applied_count, group_name])


## ─── TASK 3.2: HIGHLIGHT TARGET FILTER ──────────────────────────────
## For the generator's xray_generator group, the interaction highlight must
## apply ONLY to the button box mesh (button_12), not the generator pipe
## (generator_1). This filter returns false for any mesh whose name matches
## the pipe / non-interactive parts, so the highlight never bleeds onto them.
## All other groups are highlighted normally (returns true).
func _should_highlight_mesh(mesh: MeshInstance3D, group_name: String) -> bool:
	if group_name == "xray_generator":
		var n := str(mesh.name).to_lower()
		# ─── BUG FIX: Highlight the generator_1 body, NOT the switch ──
		# The "Refuel the generator" objective must highlight the physical
		# generator_1 model. The GeneratorSwitch button box belongs to the
		# separate "xray_generator_switch" group which is highlighted only
		# in on_generator_refilled() (post-refuel "Turn on the generator").
		# So here we EXCLUDE the button/switch meshes so they never bleed
		# into the refuel highlight, and highlight everything else (the
		# generator_1 body, pipe, exhaust).
		if "button" in n or "switch" in n:
			return false
		return true
	return true


## Applies the x-ray next_pass material to a MeshInstance3D (its first
## surface). What it had before (its own surface material override, its
## culling margin and AABB) is kept in "_xray_saved" and put back by
## _clear_xray_from_mesh(). (Clearing used to set the override to null,
## wiping a material the scene had given the mesh, and the 400 m culling
## box that lets the outline show through walls was never taken off.)
func _apply_xray_to_mesh(mesh: MeshInstance3D, xray_mat: Material) -> void:
	if mesh.get_surface_override_material_count() == 0:
		return
	if not mesh.has_meta("_xray_saved"):
		mesh.set_meta("_xray_saved", {
			"override": mesh.get_surface_override_material(0),
			"margin": mesh.extra_cull_margin,
			"aabb": mesh.custom_aabb,
		})
	var saved: Dictionary = mesh.get_meta("_xray_saved")
	var base: Material = saved.override
	if not base and mesh.mesh and mesh.mesh.get_surface_count() > 0:
		base = mesh.mesh.surface_get_material(0)
	var highlighted: Material
	if base:
		highlighted = base.duplicate()
	else:
		var invisible := StandardMaterial3D.new()
		invisible.albedo_color = Color.TRANSPARENT
		invisible.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		highlighted = invisible
	highlighted.next_pass = xray_mat.duplicate()
	mesh.set_surface_override_material(0, highlighted)
	# Seen through walls from anywhere: never culled while highlighted.
	mesh.extra_cull_margin = 100.0
	mesh.custom_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))


## Removes the x-ray highlight from all nodes in the given group.
## Also cancels any pending delayed highlight for that group.
func clear_highlight(group_name: String) -> void:
	_cancel_xray_timer(group_name)
	for node in get_tree().get_nodes_in_group(group_name):
		if node is MeshInstance3D:
			_clear_xray_from_mesh(node)
		for mesh in node.find_children("*", "MeshInstance3D", true):
			_clear_xray_from_mesh(mesh)
	print("[RoutineManager] X-ray highlight cleared for group '%s'" % group_name)


## Puts back what the mesh had before it was highlighted.
func _clear_xray_from_mesh(mesh: MeshInstance3D) -> void:
	if not mesh.has_meta("_xray_saved"):
		return
	var saved: Dictionary = mesh.get_meta("_xray_saved")
	mesh.set_surface_override_material(0, saved.override)
	mesh.extra_cull_margin = saved.margin
	mesh.custom_aabb = saved.aabb
	mesh.remove_meta("_xray_saved")


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
		var was := main_objective
		main_objective = target
		print("[RoutineManager] Main objective advanced to %d." % main_objective)
		# "Lock the front door" done, however it completed (locked on the
		# objective, or locked earlier and ticked off when it came up).
		if was <= 8 and target >= 9:
			_spawn_peeker_at.call_deferred("Bedroom_Right")
		if was < 4 and target == 4:
			_think_fuse_box.call_deferred()


## As "Check the fuse box" comes up.
func _think_fuse_box() -> void:
	var monologue := get_node_or_null("/root/Monologue")
	var box := get_tree().get_first_node_in_group("xray_fuse_box") as Node3D
	if monologue:
		monologue.think("It's always the goddamn fuse box.", box, 4.0, "fuse_box")


## The scripted Peeker after a door-lock objective.
func _spawn_peeker_at(window_id: String) -> void:
	var pm = get_node_or_null("/root/PeekerManager")
	if pm and pm.has_method("force_spawn_at_window"):
		pm.force_spawn_at_window(window_id)
		print("[RoutineManager] Peeker forced to window '%s'." % window_id)

func _check_power_restored() -> void:
	if phase2_fuse_fixed and phase2_gen_refilled and phase2_gen_turned_on:
		print("[RoutineManager] Power restored! Fuse fixed, generator refueled and running.")
		_advance_main_objective(6)
		_update_hud()


## ─── OBJECTIVE TEXT ─────────────────────────────────────────────────

## Night 1 fell and the player has no flashlight: "Find the flashlight."
## stands in for the objective until they pick it up.
var flashlight_needed := false


func _on_night_started(night: int) -> void:
	if night != 1 or is_day3_sandbox or main_objective >= 99:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player and player.get("_has_flashlight"):
		return
	flashlight_needed = true
	print("[RoutineManager] Night 1 and no flashlight: \"Find the flashlight.\" takes over the objective.")
	highlight_target("xray_flashlight", 5.0)
	_update_hud()


func get_current_objective() -> String:
	if flashlight_needed:
		return "Find the flashlight."
	# ─── DAY 3+ SANDBOX MODE OVERRIDE ─────────────────────────────
	# Sandbox mode takes priority over the Night 2.2 car-alarm van
	# sequence. Once Day 3 begins, the objective must read
	# "Investigate the car again." — never the stale night-time text.
	if is_day3_sandbox:
		if not van_inspected:
			return "Investigate the car again."
		if van_fully_repaired:
			return "Start the van and escape."
		# ─── COLLECTION vs INSTALLATION PROGRESS ─────────────────────
		# Show the combined collection/installation progress so picking up
		# a part immediately updates the objective. Parts that are both
		# collected AND installed count once toward the total.
		var _combined_count := 0
		if van_battery_collected or van_battery_installed:
			_combined_count += 1
		if van_radiator_collected or van_radiator_installed:
			_combined_count += 1
		if van_wiring_collected or van_wiring_installed:
			_combined_count += 1
		if _combined_count > 0:
			return "Repair the van (%d/3 parts)" % _combined_count
		return "Find parts to repair the van."

	# ─── VAN SEQUENCE (Night 2.2) OVERRIDE ─────────────────────────
	# While the car-alarm van sequence is active, the van sequence OWNS
	# the objective ("Investigate the car alarm outside."). The Day 2
	# routine state is already complete (day2_step >= 8), so without this
	# guard any HUD refresh (e.g. the player tapping E on the locked door)
	# would overwrite the car-alarm objective with the stale
	# "Lock the door and go to bed." text.
	var nm_van: Node = _night_manager if is_instance_valid(_night_manager) else get_node_or_null("/root/NightManager")
	if nm_van and "is_van_sequence_active" in nm_van and nm_van.is_van_sequence_active:
		return "Investigate the car alarm outside."
	
	# ─── DAY 2 SEQUENTIAL NEST TUTORIAL (main_objective >= 99) ──────────
	# When the Day 1 objective history is reset, the player enters the
	# Day 2 nest documentation sequence. This replaces the old single
	# "Document the nests" objective with 5 sequential steps.
	if main_objective >= 99:
		if _is_day2_complete():
			return "Lock the door and go to bed."
		match day2_step:
			0, 1:
				return "Read the previous nest reports on the computer."
			2:
				return "Locate and document Nest Alpha."
			3:
				return "Locate and document Nest Beta."
			4:
				return "Locate and document Nest Gamma."
			5:
				return "Log the collected nest data into the cabin's computer terminal."
			6:
				return "Lock the door."
			7:
				return "Go to bed."
		return "Read the earlier nest data logs in the computer."
	
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
			return "Check the fuse box."
		5:
			if phase2_gen_turned_on:
				_advance_main_objective(6)
				return get_current_objective()
			if phase2_gen_refilled:
				return "Turn on the generator."
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
			if phase2b_plank_count >= 3:
				return "Patch the window as well as you can."
			return "Find 3 planks"
		8:
			if phase3_door_locked:
				_advance_main_objective(9)
				return get_current_objective()
			return "Lock the front door."
		9:
			if phase3_hall_light_off:
				_advance_main_objective(10)
				return get_current_objective()
			return "Turn off the lights."
		10:
			if phase3_bed_used:
				return "Day 1 complete. Rest well."
			return "Go to bed."
	
	return "Go to the cabin."


func _update_hud() -> void:
	var text = get_current_objective()
	_update_bed_highlight(str(text))
	var step: int = 0
	
	if flashlight_needed:
		step = 5
	elif is_day3_sandbox:
		if van_fully_repaired:
			step = 30
		elif van_parts_installed_count > 0:
			step = 20 + van_parts_installed_count
		else:
			step = 20
	elif main_objective >= 99:
		# Day 2 sequential nest tutorial steps (17-22)
		step = 16 + day2_step  # day2_step 1..6 → HUD steps 17..22
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
				if phase2b_plank_count >= 3: step = 14
				else: step = 13
			8: step = 15
			9: step = 16
			10: step = 17
	
	routine_step_changed.emit(step, text)
	print("[RoutineManager] HUD updated: Step %d — '%s'" % [step, text])


# ═══════════════════════════════════════════════════════════════════════
# DAY 3+ SANDBOX TRIGGERS
# ═══════════════════════════════════════════════════════════════════════

func on_car_part_collected(part_name: String) -> void:
	# ─── MARK THE OBJECTIVE COMPLETE ON PICKUP ─────────────────────
	# Previously this function was a stub — it only printed and emitted
	# van_checklist_changed without setting any state. The notebook reads
	# van_battery_collected / van_radiator_collected / van_wiring_collected
	# to render the "[X]" checkbox, so without this the UI never showed
	# the part objective as completed, blocking the player's perception
	# of endgame progression toward the van repair.
	var changed: bool = false
	match part_name:
		"Car Battery":
			if not van_battery_collected:
				van_battery_collected = true
				changed = true
		"Radiator":
			if not van_radiator_collected:
				van_radiator_collected = true
				changed = true
		"Ignition Wiring":
			if not van_wiring_collected:
				van_wiring_collected = true
				changed = true
		_:
			print("[RoutineManager] Car part collected with unknown name: '%s'" % part_name)
	
	if changed:
		print("[RoutineManager] Car part collected: %s (objective marked complete)" % part_name)
		# Refresh the HUD objective text so "Find parts to repair the van."
		# progresses as parts are collected.
		_update_hud()
		van_checklist_changed.emit()
	else:
		# Duplicate signal (same part picked up twice) — still refresh UI.
		van_checklist_changed.emit()

## Returns the number of car parts the player has COLLECTED (0–3),
## regardless of whether they have been installed in the van yet.
## Used by the HUD objective text to show collection progress.
func get_collected_parts_count() -> int:
	var count: int = 0
	if van_battery_collected:
		count += 1
	if van_radiator_collected:
		count += 1
	if van_wiring_collected:
		count += 1
	return count

func on_van_inspected() -> void:
	if van_inspected:
		return
	van_inspected = true
	print("[RoutineManager] Van inspected! Van escape checklist activated.")
	_update_hud()
	van_checklist_changed.emit()
	var monologue := get_node_or_null("/root/Monologue")
	var van := get_tree().current_scene.find_child("EscapeVan", true, false) as Node3D if get_tree().current_scene else null
	if monologue:
		monologue.think("The car's wrecked - I need to find parts to repair it.", van, 5.0, "van_wrecked")

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
	# ─── TASK 3: SANDBOX UNLOCKS WINDOW BOARDING ──────────────────────
	# Day 3+ sandbox grants full exploration freedom — all windows must
	# be boardable regardless of prior progression.
	windows_unlocked_for_boarding = true
	print("[RoutineManager] DAY 3 SANDBOX MODE ACTIVATED! Windows unlocked for boarding.")
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
	# Already carrying what the track asks for: those count straight away
	# (a fuel can picked up before the track started was never counted).
	var inventory := get_node_or_null("/root/Inventory")
	if inventory and "items" in inventory:
		for item in inventory.items:
			if item == null or not "item_name" in item:
				continue
			match item.item_name:
				"Fuel Can":
					on_fuel_can_found()
				"Portable Light":
					on_portable_light_found()
				"Cable Spool":
					on_cable_spool_found()

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
	# ─── TASK 4: SIDE-TRACK ACTIVE GATE ──────────────────────────────
	# The side-track's "Find fuel can" objective must only fire after the
	# Unsanctioned Discoveries track is active (arvid_note_2_found).
	# Fuel cans are picked up from Day 1 onward — without this gate, the
	# Day 1 fuel can would silently pre-complete the side-track objective.
	if not arvid_note_2_found:
		print("[RoutineManager] Side-track 'Find fuel can' deferred — track not active yet (arvid_note_2_found=false).")
		return
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
	# The key is under the bucket by the door: the moment to learn that
	# loose things can be lifted and moved.
	_hint_move_objects()
	# ─── X-RAY HIGHLIGHT: Cabin Key after 5 seconds ──
	highlight_target("xray_key", 5.0)

## The lift-and-move hint, until it's been on screen, learned, or the key is
## found. (Another hint still up, the "interact" one from the door, blocks it,
## and a blocked hint isn't tried again on its own.)
func _hint_move_objects() -> void:
	var tm := get_node_or_null("/root/TutorialManager")
	if not tm or not tm.has_method("trigger") or tm.is_learned("move_objects"):
		return
	if tm._shown.has("move_objects") or _player_has_item("Cabin Key"):
		return
	tm.trigger("move_objects")
	if not tm._shown.has("move_objects"):
		get_tree().create_timer(2.0).timeout.connect(_hint_move_objects)


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
	
	# ─── PHASE 1 GATING FIX ─────────────────────────────────────────────
	# The room-check fallback (player_controller.gd) fires whenever the
	# player crosses from "Outside" into a cabin interior room. On Day 1
	# that can happen while the player is still looking for the key (e.g.
	# room areas overlapping the doorway/porch, or stepping back inside
	# while searching). Without this gate, the objective would skip the
	# "find the key" → "unlock the door" sequence and jump straight to
	# "Log into the computer."
	#
	# The authoritative Phase 1 completion is on_door_unlocked() (fired by
	# the door's toggle_lock()). This room-check is ONLY a safety net for
	# when that signal doesn't fire — and it must not bypass the key gate.
	if not phase1_found_key:
		print("[RoutineManager] Cabin entry detected, but key not found yet. Phase 1 NOT complete — player must find the key and unlock the door.")
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
		# ─── TASK 7 FIX: DELAYED GENERATOR HIGHLIGHT (10 SECONDS) ──
		# The "Refill the generator" objective highlight should enable AFTER
		# 10 seconds if the player hasn't interacted with the generator.
		# Interacting with it prematurely (start_refuel → clear_highlight)
		# cancels this timer via the RoutineManager _xray_timers system.
		highlight_target("xray_generator", 10.0)

func on_generator_refilled() -> void:
	if phase2_gen_refilled:
		return
	phase2_gen_refilled = true
	print("[RoutineManager] Phase 2: Generator refilled.")
	_update_hud()
	_check_power_restored()
	# ─── X-RAY HIGHLIGHT: Clear generator highlight, highlight the switch ──
	clear_highlight("xray_generator")
	highlight_target("xray_generator_switch", 3.0)


## Called by generator.gd when the player successfully flips the generator
## switch ON. Completes the "Turn on the generator" sub-step that follows
## refueling (the generator can only start once the fuse box is repaired).
func on_generator_turned_on() -> void:
	if phase2_gen_turned_on:
		return
	phase2_gen_turned_on = true
	print("[RoutineManager] Phase 2: Generator turned on!")
	clear_highlight("xray_generator_switch")
	_check_power_restored()
	_update_hud()

func on_computer_tried_no_power() -> void:
	if phase2_computer_tried_no_power:
		return
	phase2_computer_tried_no_power = true
	
	# ─── EARLY FLASHLIGHT CHECK (Bug 2 Fix) ──────────────────────────────
	# If the player already found the flashlight before reaching this point,
	# skip objective 3 ("Find the flashlight") and go directly to objective 4
	# ("Find the fuse box"). This prevents the player from getting stuck on an
	# objective they've already completed.
	# (The flashlight is no longer a step here: Night 1 asks for it if the
	# player still hasn't found it, see flashlight_needed.)
	_advance_main_objective(4)
	print("[RoutineManager] Phase 2: Player tried computer without power. Advancing to the fuse box.")
	highlight_target("xray_fuse_box", 5.0)
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
	clear_highlight("xray_flashlight")
	if flashlight_needed:
		# The objective it stood in for comes back.
		flashlight_needed = false
		print("[RoutineManager] Flashlight found: back to \"%s\"" % get_current_objective())
		_update_hud()
		return
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
	
	# ─── TASK 3: UNLOCK WINDOW BOARDING ──────────────────────────────
	# The "Board up the broken window" objective (main 7) begins the moment
	# the player logs into the computer. From this point on, windows are
	# explicitly unlocked for boarding. CabinWindow refuses boarding until
	# this flag is set — the strict story gate.
	windows_unlocked_for_boarding = true
	print("[RoutineManager] TASK 3: Windows unlocked for boarding (objective 7 begins).")
	
	_update_hud()
	# ─── X-RAY HIGHLIGHT: Highlight planks after 10 seconds ──
	highlight_target("xray_planks", 10.0)
	# What the planks are for: a thought as the objective starts (once the
	# computer is closed and the player can see it).
	var pc := get_tree().get_first_node_in_group("computer_ui")
	if pc and "is_open" in pc and pc.is_open and pc.has_signal("computer_closed"):
		pc.computer_closed.connect(_think_about_broken_window, CONNECT_ONE_SHOT)
	else:
		_think_about_broken_window()


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

## Inner monologue (Monologue): as "Find 3 planks" starts, over the
## broken window, for 5 seconds.
func _think_about_broken_window() -> void:
	var monologue := get_node_or_null("/root/Monologue")
	# Not for the player's starting items (given while the scene loads).
	var scene := get_tree().current_scene
	if not monologue or not scene or not scene.is_node_ready():
		return
	var broken: Node3D = null
	for window in get_tree().get_nodes_in_group("WindowMarkers"):
		if "start_broken" in window and window.start_broken and window.is_glass_shattered and not window.is_boarded:
			broken = window
	monologue.think("Someone left a window for me to patch up - how kind.", broken, 5.0, "broken_window")


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

## "Lock the door" came up with the front door already locked: done.
func _tick_off_locked_door() -> void:
	var door := get_tree().get_first_node_in_group("Door")
	if door and door.get("is_locked"):
		on_door_locked()


func on_door_locked() -> void:
	# ─── DAY 2 STEP 6 → 7: Lock the door ───────────────────────────
	# On Day 2, after the nest data is uploaded, the player must lock
	# the door before going to bed. door.gd calls this whenever the
	# player locks any door. Only completes when step 6 is active.
	if main_objective >= 99 and day2_step == 6:
		day2_step = 7
		print("[RoutineManager] Day 2 Step 6 COMPLETE: Door locked. Step 7: Go to bed.")
		_spawn_peeker_at("Hall_Window_Right")
		_sync_day2_hint()
		_update_hud()
		return
	
	# ─── DAY 1 GATE: ONLY complete "Lock the front door" (step 8)
	# while it is the ACTIVE objective ───────────────────────────────
	# Locking the door early (e.g. while on the fuse/generator/plank
	# objectives) must NOT skip ahead. We record the physical locked
	# state so the objective auto-completes when the player genuinely
	# reaches step 8, but the step is never advanced out-of-order.
	phase3_door_locked = true
	if main_objective != 8:
		print("[RoutineManager] Front door locked early (main_objective=%d) — state recorded, objective NOT advanced." % main_objective)
		return
	
	print("[RoutineManager] Phase 3: Front door locked.")
	_advance_main_objective(9)
	
	# The Night 1 Peeker (at the landing window) comes with the objective
	# advancing (_advance_main_objective).
	# ─── DEFENSIVE AUTO-COMPLETE: All cabin lights already OFF ──────
	# If the player turned off every cabin light BEFORE reaching the
	# "Turn off the lights" objective (e.g. while the door step was
	# still active), that earlier toggle could not have fired
	# on_light_toggled_off() (it checks main_objective == 9). Check the
	# current cabin light states now so the player is never soft-locked.
	if not phase3_hall_light_off and _are_all_cabin_lights_off():
		phase3_hall_light_off = true
		print("[RoutineManager] Phase 3: All cabin lights were already off before the objective — auto-completed.")
	_update_hud()


## Called by cabin_light.gd whenever a light switch is toggled OFF.
## Completes the "Turn off the lights" sub-step (main objective 9) but
## only when EVERY cabin light in the "CabinLights" group has been
## switched off. Any single remaining light keeps the objective pending.
func on_light_toggled_off(light_name: String = "", node_path: NodePath = NodePath()) -> void:
	if main_objective != 9 or phase3_hall_light_off:
		return
	if not _are_all_cabin_lights_off():
		return
	phase3_hall_light_off = true
	_advance_main_objective(10)
	_update_hud()


## Returns true when every light in the "CabinLights" group is switched off.
## Used by the Day 1 "Turn off the lights" objective (main objective 9).
## The group contains all cabin light fixtures (hall, bedroom, porch, etc.),
## registered by cabin_light.gd on _ready().
##
## FAULTY LIGHTS: Fixtures with is_faulty == true are physically stuck ON
## (their toggle_light() refuses to switch them off — the faulty porch
## light is a permanent wiring hazard). They are excluded from the check
## so the objective remains completable. The objective requires every
## *toggleable* cabin light to be switched off.
func _are_all_cabin_lights_off() -> bool:
	var lights := get_tree().get_nodes_in_group("CabinLights")
	if lights.is_empty():
		return false
	for light in lights:
		if "is_faulty" in light and light.is_faulty:
			continue
		if "is_switched_on" in light and light.is_switched_on:
			return false
	return true

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

## Returns true when the full Day 2 nest sequence is complete
## (step 7 finished — the player has locked the door and gone to bed).
func _is_day2_complete() -> bool:
	return day2_step >= 8


## Resets Day 2 state for a fresh Day 2 start.
func _reset_day2_state() -> void:
	day2_step = 1
	day2_notebook_opened = false
	day2_door_unlocked = false
	nests_documented = 0
	nests_uploaded = false
	day2_hint_text = ""
	print("[RoutineManager] Day 2 sequence reset. Step 1: Read the previous nest reports on the computer.")


## Updates the active hint for the current Day 2 step and emits it to the
## Notebook To-Do list. Called whenever the step advances or changes.
func _sync_day2_hint() -> void:
	var new_hint: String = ""
	match day2_step:
		2:
			new_hint = DAY2_NEST_HINTS.get("Nest Alpha", "")
		3:
			new_hint = DAY2_NEST_HINTS.get("Nest Beta", "")
		4:
			new_hint = DAY2_NEST_HINTS.get("Nest Gamma", "")
	if new_hint != day2_hint_text:
		day2_hint_text = new_hint
		objective_hint_changed.emit(day2_hint_text)
		print("[RoutineManager] Day 2 hint updated: '%s'" % day2_hint_text)


## Called when NightManager advances to Day 2.
## Initializes the Day 2 sequential tutorial (Step 1: open the notebook)
## and starts the Nest Alpha highlight once the notebook has been opened.
func on_day2_started() -> void:
	print("[RoutineManager] Day 2 started.")
	# Force main_objective to the Day 2 sentinel (99) so the sequential
	# nest tutorial activates regardless of which night transitions path
	# fired (advance_night() vs the natural time-based day_started).
	if main_objective < 99 and not is_day3_sandbox:
		main_objective = 99
		print("[RoutineManager] Day 2 sentinel set: main_objective = 99.")
	
	# ─── TASK 3: KEEP WINDOWS UNLOCKED FROM NIGHT 2+ ─────────────
	# Once Night 1 has passed, ALL windows are always boardable. If the
	# player somehow skipped the Day 1 computer step (dev mode / debug),
	# force the flag here so late-game boarding never soft-locks.
	windows_unlocked_for_boarding = true
	print("[RoutineManager] TASK 3: Windows permanently unlocked from Day 2 onward.")
	
	_reset_day2_state()
	# Lock the cabin door until the player reads the Nest Logs in the notebook.
	_lock_cabin_door()
	_update_hud()


## Locks the cabin front door at the start of Day 2 (Step 1 gate).
## The door unlocks once the player opens the notebook and reads the logs.
func _lock_cabin_door() -> void:
	for door in get_tree().get_nodes_in_group("Door"):
		if door.has_method("is_cabin_front_door") and door.is_cabin_front_door():
			if door.has_method("lock"):
				door.lock()
				print("[RoutineManager] Cabin front door LOCKED for Day 2 Step 1.")
				return
	# Fallback: try to find the door with a matching meta/name
	for door in get_tree().get_nodes_in_group("Door"):
		var door_name: String = str(door.name).to_lower()
		if "front" in door_name or "cabin_door" in door_name:
			if door.has_method("lock"):
				door.lock()
				print("[RoutineManager] Cabin front door LOCKED for Day 2 Step 1 (fallback).")
				return


## Unlocks the cabin front door once the player opens the notebook (Step 1 reward).
func _unlock_cabin_door() -> void:
	day2_door_unlocked = true
	for door in get_tree().get_nodes_in_group("Door"):
		if door.has_method("is_cabin_front_door") and door.is_cabin_front_door():
			if door.has_method("unlock"):
				door.unlock()
				print("[RoutineManager] Cabin front door UNLOCKED for Day 2 Step 1.")
				return
	for door in get_tree().get_nodes_in_group("Door"):
		var door_name: String = str(door.name).to_lower()
		if "front" in door_name or "cabin_door" in door_name:
			if door.has_method("unlock"):
				door.unlock()
				print("[RoutineManager] Cabin front door UNLOCKED for Day 2 Step 1 (fallback).")
				return


## Called by ComputerUI when the player reads the previous nest reports on
## the lab terminal. Completes Day 2 Step 1 and unlocks the cabin door so
## the player can leave to document the nests.
func on_previous_reports_read() -> void:
	if main_objective < 99:
		return  # Only applies to Day 2+
	if day2_step == 1:
		print("[RoutineManager] Day 2 Step 1 COMPLETE: Player read the previous nest reports.")
		day2_notebook_opened = true
		day2_step = 2
		_unlock_cabin_door()
		_sync_day2_hint()
		_update_hud()
		# ─── NEST ALPHA HIGHLIGHT TIMER (+15 SECONDS) ─────────────
		# Alpha's timer is now 35.0s. This call fires EXACTLY when the
		# "Document nest alpha" objective officially starts (Day 2 step
		# advances 1 → 2 after reading the reports), so the countdown
		# begins when Document nest alpha starts — NOT when the earlier
		# "Read the previous nest reports" objective (step 1) starts.
		highlight_target("xray_nest_alpha", 35.0)


## Called by NotebookUI when the player opens the notebook on Day 2.
##
## Intentional NO-OP for Day 2 Step 1: the previous researcher's nest
## reports live on the lab computer (NEST_REPORTS.TXT), NOT in the
## player's notebook. Step 1 can only be completed by reading the
## reports on the terminal via on_previous_reports_read().
func on_notebook_opened() -> void:
	if main_objective < 99:
		return  # Only applies to Day 2+
	if day2_step == 1:
		print("[RoutineManager] Notebook opened on Day 2 Step 1 — Step 1 remains gated behind the computer terminal (NEST_REPORTS.TXT).")
	return


## Called by HasselmusNest when the player documents a nest.
## Advances the Day 2 sequential steps (2 → 3 → 4) and schedules the
## next nest's x-ray highlight.
func document_nest(nest_id: String) -> void:
	# ─── SEQUENTIAL VALIDATION GATE ──────────────────────────────────
	# The nests must be documented in order: Alpha → Beta → Gamma.
	# If the player attempts an out-of-order nest, refuse and surface
	# a HUD message pointing them to the correct nest.
	if main_objective >= 99:
		var expected: String = ""
		match day2_step:
			2: expected = "Nest Alpha"
			3: expected = "Nest Beta"
			4: expected = "Nest Gamma"
		if not expected.is_empty() and nest_id != expected:
			var hud := get_tree().get_first_node_in_group("hud")
			if hud and hud.has_method("show_message"):
				hud.show_message("I should document %s first." % expected)
			print("[RoutineManager] Nest '%s' REJECTED — expected '%s' first (day2_step=%d)." % [nest_id, expected, day2_step])
			return
	nests_documented += 1
	print("[RoutineManager] Nest '%s' documented! (%d/3)" % [nest_id, nests_documented])
	
	# ─── X-RAY HIGHLIGHT: Sequential nest highlighting ──
	# All nest highlight timers increased by 15 seconds.
	#   Nest Alpha → 35.0s (see on_previous_reports_read)
	#   Nest Beta  → 50.0s
	#   Nest Gamma → 50.0s
	match nest_id:
		"Nest Alpha":
			clear_highlight("xray_nest_alpha")
			if nests_documented < 3:
				print("[RoutineManager] Scheduling Nest Beta highlight in 50 seconds (+15).")
				highlight_target("xray_nest_beta", 50.0)
		"Nest Beta":
			clear_highlight("xray_nest_beta")
			if nests_documented < 3:
				print("[RoutineManager] Scheduling Nest Gamma highlight in 50 seconds (+15).")
				highlight_target("xray_nest_gamma", 50.0)
		"Nest Gamma":
			clear_highlight("xray_nest_gamma")
	
	# ─── DAY 2 STEP ADVANCEMENT ──────────────────────────────────────
	# Advance the sequential objectives: Alpha → Beta → Gamma → Upload.
	# IMPORTANT: _update_hud() MUST be called on EVERY step advancement so
	# the HUD immediately pushes the next objective string to the player.
	# Previously the HUD only refreshed at nests_documented >= 3, which left
	# the UI frozen on the same text while multiple nests were documented.
	if main_objective >= 99:
		match nest_id:
			"Nest Alpha":
				if day2_step == 2:
					day2_step = 3
					print("[RoutineManager] Day 2 Step 2 COMPLETE: Nest Alpha documented. Step 3: Nest Beta.")
					_sync_day2_hint()
					_update_hud()
			"Nest Beta":
				if day2_step == 3:
					day2_step = 4
					print("[RoutineManager] Day 2 Step 3 COMPLETE: Nest Beta documented. Step 4: Nest Gamma.")
					_sync_day2_hint()
					_update_hud()
			"Nest Gamma":
				if day2_step == 4:
					day2_step = 5
					print("[RoutineManager] Day 2 Step 4 COMPLETE: Nest Gamma documented. Step 5: Log data on computer.")
					_sync_day2_hint()
					_update_hud()
	
	if nests_documented >= 3:
		print("[RoutineManager] All 3 nests documented! Player should upload data on the computer.")
		_update_hud()


func on_nest_data_uploaded() -> void:
	if nests_uploaded:
		return
	# ─── DAY 2 STEP 5 COMPLETION ─────────────────────────────────────
	# The FIELD_LOG.EXE correlation success triggers this. It only counts
	# if all 3 nests have been documented first. Setting nests_uploaded
	# prematurely (before all nests are documented) would lock the player
	# out of Step 5 — so we gate the flag behind the step check.
	if main_objective >= 99 and nests_documented >= 3 and day2_step == 5:
		nests_uploaded = true
		day2_step = 6
		print("[RoutineManager] Day 2 Step 5 COMPLETE: Nest data uploaded to terminal!")
		# Night has fallen with the upload, and the game may have locked the
		# front door for them already: then "Lock the door" is done.
		_tick_off_locked_door.call_deferred()
	else:
		# Player attempted to upload before documenting all nests.
		# Keep the flag false so they can retry after documenting.
		print("[RoutineManager] Nest data upload BLOCKED: Not all nests documented (count=%d, step=%d)." % [nests_documented, day2_step])
		return
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
	
	# ─── DAY 2 SEQUENTIAL NEST TUTORIAL ────────────────────────────
	# Ensure the Day 2 step machine is initialized even if this is called
	# independently (e.g. not through on_day2_started()).
	_reset_day2_state()
	
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
	phase2_gen_turned_on = false
	phase2_computer_used = false
	
	phase2b_plank_picked_up = false
	phase2b_plank_count = 0
	phase2b_window_patched = false
	
	phase3_door_locked = false
	phase3_hall_light_off = false
	phase3_bed_used = false
	
	print("[RoutineManager] Objective history reset. Day 1 gating state cleared for new day.")
	_update_hud()


func reset_all_phases() -> void:
	main_objective = 0
	
	is_day3_sandbox = false
	van_inspected = false
	van_battery_collected = false
	van_radiator_collected = false
	van_wiring_collected = false
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
	phase2_gen_turned_on = false
	phase2_computer_used = false
	
	phase2b_plank_picked_up = false
	phase2b_plank_count = 0
	phase2b_window_patched = false
	windows_unlocked_for_boarding = false
	
	phase3_door_locked = false
	phase3_hall_light_off = false
	phase3_bed_used = false
	
	print("[RoutineManager] All phases reset.")
	_update_hud()
