extends StaticBody3D
class_name NotePickup

## Note pickup item in the world.
## When the player interacts (presses E), the note is displayed immediately via NoteUI.
## When the user closes the note (ESC), the note text is recorded in the notebook
## (not the inventory) and the note is removed from the world.
##
## FIXES:
##   - Deferred retry: if NoteUI isn't ready on first interact(), retries next frame
##   - Double-pickup guard: _already_collected prevents the note from being picked
##     up twice (e.g., if the player rapidly presses E)
##   - HUD feedback: shows a message when the note is added so the player always
##     knows the interaction succeeded
##   - Clean signal lifecycle: disconnects note_closed after processing

@export var item_data: ItemData

## Whether this note has already been collected. Prevents double-pickup from
## rapid E-presses or signal timing issues.
var _already_collected: bool = false


func _ready() -> void:
	# BUG 1 FIX: Interactable Layer 2 (interaction ray only sees layer 2)
	set_collision_layer_value(2, true)
	# If no item_data assigned, create a default one
	if not item_data:
		item_data = ItemData.new()
		item_data.item_name = "Note"
		item_data.item_description = "A handwritten note."
		item_data.item_type = ItemData.ItemType.NOTE
		item_data.note_text = "It's watching..."
	
	# ─── BUG 4 FIX: APPLY DIAGONAL LIGHT-WAVE PICKUP HIGHLIGHT ──────
	# Adds the pickup_highlight.gdshader as a next_pass on the note's
	# MeshInstance3D (or any child meshes), so a subtle diagonal wave of
	# light periodically sweeps across the note to catch the player's eye.
	# The shader runs on top of the existing material via next_pass, so the
	# base texture/shading is preserved. Brightness is intentionally subtle.


	call_deferred("_apply_pickup_highlight")


## Applies the diagonal light-wave shader as a next_pass on the note mesh.
## Runs deferred so child MeshInstance3D nodes exist when called.
	# BUG 1 FIX: Ensure Layer 2 ("Interactable") is active — must run AFTER any
	# bare 'collision_layer = N' assignment in _ready so it cannot be overwritten.
	set_collision_layer_value(1, true)
	set_collision_layer_value(2, true)

func _apply_pickup_highlight() -> void:
	var shader := load("res://shaders/pickup_highlight.gdshader") as Shader
	if not shader:
		push_warning("[NotePickup] Could not load pickup_highlight.gdshader!")
		return
	
	var highlight_mat := ShaderMaterial.new()
	highlight_mat.shader = shader
	
	# NotePickup extends StaticBody3D — the actual visual mesh is always a
	# child MeshInstance3D, so find_children is the only source needed.
	var mesh_nodes: Array[Node] = find_children("*", "MeshInstance3D", true, false)
	
	for mesh_node in mesh_nodes:
		var mi := mesh_node as MeshInstance3D
		if not mi or not mi.mesh:
			continue
		# Apply via next_pass on the surface material so the base texture stays.
		var surf_mat := mi.get_surface_override_material(0)
		if not surf_mat and mi.mesh:
			surf_mat = mi.mesh.surface_get_material(0)
		if surf_mat:
			var clone := surf_mat.duplicate()
			clone.next_pass = highlight_mat
			mi.set_surface_override_material(0, clone)
		else:
			mi.material_override = highlight_mat
		print("[NotePickup] Applied pickup light-wave highlight to '%s'." % mi.name)


func set_item_data(data: ItemData) -> void:
	item_data = data


func interact() -> void:
	if _already_collected:
		print("[NotePickup] Already collected! Ignoring duplicate interact.")
		return
	
	# ─── TASK 2.1: EXHAUSTED GATE ────────────────────────────────
	# When the player is exhausted (Day 3+), they are too tired to read
	# notes. The interaction is blocked with a greyed-out message.
	var player_ref = get_tree().get_first_node_in_group("player")
	if player_ref and "is_exhausted" in player_ref and player_ref.is_exhausted:
		_show_hud_message("I am too tired to read this right now...")
		print("[NotePickup] BLOCKED: Player is exhausted.")
		return
	
	if not item_data or item_data.note_text.is_empty():
		print("[NotePickup] No note text to display!")
		_show_hud_message("This note is blank...")
		return
	
	print("[NotePickup] interact() called! Displaying note: ", item_data.item_name)
	
	# ─── BIND THIS NOTE'S DATA TO THE SIGNAL ──────────────────────
	# Before connecting to note_closed, capture the current note's
	# item_data in a local variable. We bind it to the lambda so that
	# even if another note's interact() fires before this one closes,
	# the correct cleanup runs for the correct note.
	# This prevents the "wrong note queued" bug where rapid interaction
	# with two notes causes one note's cleanup to be lost.
	var bound_name = item_data.item_name
	var bound_text = item_data.note_text
	var bound_item = item_data
	
	# Find the NoteUI and display the note immediately
	var note_ui = _find_note_ui()
	
	if note_ui and note_ui.has_method("display_note"):
		_mark_collected()
		
		# With this note's data bound, once (CONNECT_ONE_SHOT: it disconnects
		# itself when the note is closed).
		note_ui.note_closed.connect(_on_note_closed.bind(bound_name, bound_text, bound_item), CONNECT_ONE_SHOT)
		note_ui.display_note(item_data.note_text, item_data.item_name)
	else:
		# NoteUI not found — retry deferred in case it's loading
		print("[NotePickup] NoteUI not found immediately. Retrying deferred...")
		call_deferred("_retry_interact")


## Retries finding NoteUI one frame later. This handles the case where
## NoteUI is still being constructed when the player picks up the note.
func _retry_interact() -> void:
	if _already_collected:
		return
	
	var note_ui = _find_note_ui()
	if note_ui and note_ui.has_method("display_note"):
		_mark_collected()
		
		note_ui.note_closed.connect(_on_note_closed, CONNECT_ONE_SHOT)
		note_ui.display_note(item_data.note_text, item_data.item_name)
		print("[NotePickup] NoteUI found on retry! Displaying note.")
	else:
		# Still not found — fall back to direct notebook addition
		print("[NotePickup] NoteUI not found on retry. Adding directly to notebook.")
		_mark_collected()
		_show_hud_message("I'll keep this in my notebook.")
		_add_to_notebook_and_cleanup()


## The NoteUI (by its group).
func _find_note_ui() -> Node:
	return get_tree().get_first_node_in_group("note_ui")


## Marks the note as collected to prevent double-pickup.
func _mark_collected() -> void:
	_already_collected = true


## Called when the NoteUI is closed. Uses bound parameters to ensure
## the correct note's data is always processed, even if another note's
## interact() fired before this one's note_closed signal.
## The bound_name, bound_text, bound_item are passed via .bind() in interact().
func _on_note_closed(bound_name: String = "", bound_text: String = "", bound_item = null) -> void:
	# Use bound data if provided (protects against cross-note signal contamination)
	var note_name = bound_name if not bound_name.is_empty() else (item_data.item_name if item_data else "Note")
	var note_text = bound_text if not bound_text.is_empty() else (item_data.note_text if item_data else "")
	var note_item = bound_item if bound_item else item_data
	
	_add_to_notebook_and_cleanup(note_name, note_text, note_item)


## Adds the note text to the notebook, fires triggers, and removes the world object.
## Accepts optional override params for cross-note signal safety.
func _add_to_notebook_and_cleanup(note_name_override: String = "", note_text_override: String = "", note_item_override = null) -> void:
	# Use override data if provided, otherwise fall back to instance vars
	var note_name = note_name_override if not note_name_override.is_empty() else (item_data.item_name if item_data else "Note")
	var note_text = note_text_override if not note_text_override.is_empty() else (item_data.note_text if item_data else "")
	var note_item = note_item_override if note_item_override else item_data
	
	# ─── ADD TO NOTEBOOK ────────────────────────────────────────────
	if not note_text.is_empty():
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.get("_notebook_ui"):
			var notebook = rm._notebook_ui
			if notebook.has_method("add_note"):
				notebook.add_note("[b]%s[/b]\n%s" % [note_name, note_text])
				print("[NotePickup] Added '%s' to notebook Notes section." % note_name)
		else:
			# Notebook not ready yet — try deferred
			call_deferred("_add_to_notebook_and_cleanup")
			return
	
	# (The notebook plays its writing sound in add_note(). A player made
	# here never sounded: this node frees itself below, taking it along.)
	
	# ─── HUD FEEDBACK ──────────────────────────────────────────────
	_show_hud_message("I'll keep this in my notebook.")
	
	# ─── ARVID'S NOTE: SET PERSISTENCE FLAG ─────────────────────────
	if note_name == "Arvid's Note":
		var night_manager = get_node_or_null("/root/NightManager")
		if night_manager:
			night_manager.arvid_password_found = true
			print("[NotePickup] Arvid's Note discovered! NightManager.arvid_password_found = true")
	
	# ─── ARVID'S NOTE 2: ACTIVATE SIDE-TRACK ─────────────────────────
	if note_name == "Arvid's Note 2":
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_arvid_note_2_found"):
			rm.on_arvid_note_2_found()
			print("[NotePickup] Arvid's Note 2 discovered! Side-track activated.")
	
	# ─── EVIDENCE MANAGER ───────────────────────────────────────────
	if note_item and "item_name" in note_item:
		var em = get_node_or_null("/root/EvidenceManager")
		if em and em.has_method("collect_evidence"):
			em.collect_evidence(note_item.item_name)
	
	# Remove the note from the world
	queue_free()


## Shows a temporary message on the HUD.
func _show_hud_message(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(msg, self)
	else:
		print("[NotePickup HUD]: ", msg)


func get_interact_text() -> String:
	if _already_collected:
		return ""
	# ─── TASK 2.1: EXHAUSTED INTERACTION PROMPT ──────────────────
	# When exhausted, grey out the interaction prompt instead of
	# showing the normal "Press E" text. The player is too tired.
	var player_ref = get_tree().get_first_node_in_group("player")
	if player_ref and "is_exhausted" in player_ref and player_ref.is_exhausted:
		return "[color=gray]I am too tired to do this[/color]"
	return "[E] Read " + (item_data.item_name if item_data else "Note")
