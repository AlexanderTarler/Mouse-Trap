extends StaticBody3D

## Note pickup item in the world.
## When the player interacts (presses E), the note is displayed immediately via NoteUI.
## When the user closes the note (ESC), the note text is recorded in the notebook
## (not the inventory) and the note is removed from the world.

@export var item_data: ItemData


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
	if not item_data or item_data.note_text.is_empty():
		print("[NotePickup] No note text to display!")
		return
	
	print("[NotePickup] interact() called! Displaying note: ", item_data.item_name)
	
	# Find the NoteUI and display the note immediately
	var note_ui = get_node_or_null("/root/CottageHorror/NoteUI")
	if not note_ui:
		note_ui = get_node_or_null("/root/Main/NoteUI")
	
	if note_ui and note_ui.has_method("display_note"):
		# Connect to the note_closed signal (disconnect any previous connection first)
		if note_ui.note_closed.is_connected(_on_note_closed):
			note_ui.note_closed.disconnect(_on_note_closed)
		note_ui.note_closed.connect(_on_note_closed)
		
		# Display the note
		note_ui.display_note(item_data.note_text, item_data.item_name)
	else:
		print("[NotePickup] NoteUI not found! Falling back to direct notebook add.")
		_on_note_closed()


func _on_note_closed() -> void:
	# ─── ADD TO NOTEBOOK ────────────────────────────────────────────
	# Record the note text in the notebook's Notes section.
	var note_text = item_data.note_text
	var note_name = item_data.item_name
	if not note_text.is_empty():
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.get("_notebook_ui"):
			var notebook = rm._notebook_ui
			if notebook.has_method("add_note"):
				notebook.add_note("[b]%s[/b]\n%s" % [note_name, note_text])
				print("[NotePickup] Added '%s' to notebook Notes section." % note_name)
	
	# ─── ARVID'S NOTE: SET PERSISTENCE FLAG ──────────────────────────
	if item_data.item_name == "Arvid's Note":
		var night_manager = get_node_or_null("/root/NightManager")
		if night_manager:
			night_manager.arvid_password_found = true
			print("[NotePickup] Arvid's Note discovered! NightManager.arvid_password_found = true")
	
	# ─── EVIDENCE MANAGER ───────────────────────────────────────────
	var em = get_node_or_null("/root/EvidenceManager")
	if em and em.has_method("collect_evidence"):
		em.collect_evidence(item_data.item_name)
	
	# Remove the note from the world
	queue_free()


func get_interact_text() -> String:
	return "[E] Read " + item_data.item_name
