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
	# If no item_data assigned, create a default one
	if not item_data:
		item_data = ItemData.new()
		item_data.item_name = "Note"
		item_data.item_description = "A handwritten note."
		item_data.item_type = ItemData.ItemType.NOTE
		item_data.note_text = "It's watching..."


func set_item_data(data: ItemData) -> void:
	item_data = data


func interact() -> void:
	if _already_collected:
		print("[NotePickup] Already collected! Ignoring duplicate interact.")
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
		
		# Clean up any stale connection from a previous failed attempt
		if note_ui.note_closed.is_connected(_on_note_closed):
			note_ui.note_closed.disconnect(_on_note_closed)
		
		# Connect with bound data so the correct note is always processed
		note_ui.note_closed.connect(_on_note_closed.bind(bound_name, bound_text, bound_item))
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
		
		if note_ui.note_closed.is_connected(_on_note_closed):
			note_ui.note_closed.disconnect(_on_note_closed)
		
		note_ui.note_closed.connect(_on_note_closed)
		note_ui.display_note(item_data.note_text, item_data.item_name)
		print("[NotePickup] NoteUI found on retry! Displaying note.")
	else:
		# Still not found — fall back to direct notebook addition
		print("[NotePickup] NoteUI not found on retry. Adding directly to notebook.")
		_mark_collected()
		_show_hud_message("Note added to notebook.")
		_add_to_notebook_and_cleanup()


## Finds the NoteUI CanvasLayer in the scene tree.
func _find_note_ui() -> Node:
	var note_ui = get_node_or_null("/root/CottageHorror/NoteUI")
	if not note_ui:
		note_ui = get_node_or_null("/root/Main/NoteUI")
	# Fallback: search the scene root recursively
	if not note_ui:
		var scene = get_tree().current_scene
		if scene:
			note_ui = _find_note_ui_recursive(scene)
	return note_ui


## Recursively searches for a NoteUI node.
func _find_note_ui_recursive(node: Node) -> Node:
	if "note_closed" in node:
		return node
	for child in node.get_children():
		var result = _find_note_ui_recursive(child)
		if result:
			return result
	return null


## Marks the note as collected to prevent double-pickup.
func _mark_collected() -> void:
	_already_collected = true


## Called when the NoteUI is closed. Uses bound parameters to ensure
## the correct note's data is always processed, even if another note's
## interact() fired before this one's note_closed signal.
## The bound_name, bound_text, bound_item are passed via .bind() in interact().
func _on_note_closed(bound_name: String = "", bound_text: String = "", bound_item = null) -> void:
	# Disconnect signal to prevent dangling connections
	var note_ui = _find_note_ui()
	if note_ui and note_ui.note_closed.is_connected(_on_note_closed):
		note_ui.note_closed.disconnect(_on_note_closed)
	
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
	
	# ─── HUD FEEDBACK ──────────────────────────────────────────────
	_show_hud_message("Added to notebook.")
	
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
		hud.show_message(msg)
	else:
		print("[NotePickup HUD]: ", msg)


func get_interact_text() -> String:
	if _already_collected:
		return ""
	return "[E] Read " + (item_data.item_name if item_data else "Note")