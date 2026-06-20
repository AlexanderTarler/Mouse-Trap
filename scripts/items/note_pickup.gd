extends StaticBody3D

## Note pickup item in the world.
## When the player interacts (presses E), the note is displayed immediately via NoteUI.
## When the user closes the note (ESC), it is added to the inventory.

@export var item_data: ItemData

var _pending_item_data: ItemData = null


func _ready() -> void:
	# If no item_data assigned, create a default one
	if not item_data:
		item_data = ItemData.new()
		item_data.item_name = "Note"
		item_data.item_description = "A handwritten note."
		item_data.item_type = ItemData.ItemType.NOTE
		item_data.note_text = "It's watching..."
	
	# Always ensure scene_to_spawn is set so the item can be dropped from inventory
	if item_data and not item_data.scene_to_spawn:
		item_data.scene_to_spawn = preload("res://scenes/note.tscn")
		print("[NotePickup] Set scene_to_spawn for: ", item_data.item_name)


func set_item_data(data: ItemData) -> void:
	item_data = data
	# Ensure scene_to_spawn is set so the item can be dropped from inventory
	if item_data and not item_data.scene_to_spawn:
		item_data.scene_to_spawn = preload("res://scenes/note.tscn")
		print("[NotePickup] Set scene_to_spawn via set_item_data for: ", item_data.item_name)


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
		# Store the item data so we can add to inventory when note is closed
		_pending_item_data = item_data
		
		# Connect to the note_closed signal (disconnect any previous connection first)
		if note_ui.note_closed.is_connected(_on_note_closed):
			note_ui.note_closed.disconnect(_on_note_closed)
		note_ui.note_closed.connect(_on_note_closed)
		
		# Display the note
		note_ui.display_note(item_data.note_text, item_data.item_name)
	else:
		print("[NotePickup] NoteUI not found, falling back to direct inventory add")
		if Inventory.add_item(item_data):
			queue_free()


func _on_note_closed() -> void:
	# Add the pending item to inventory now that the note has been read
	if _pending_item_data and Inventory.add_item(_pending_item_data):
		print("[NotePickup] Note added to inventory after closing: ", _pending_item_data.item_name)
		
		# ─── ARVID'S NOTE: SET PERSISTENCE FLAG ──────────────────────
		# If the player just read Arvid's Note, set the arvid_password_found
		# flag on NightManager. This tells the ComputerUI's RECOVER_DATA.EXE
		# to auto-fill the decryption key, so the player doesn't need to
		# memorize and manually type "STENBERG_1996".
		if _pending_item_data.item_name == "Arvid's Note":
			var night_manager = get_node_or_null("/root/NightManager")
			if night_manager:
				night_manager.arvid_password_found = true
				print("[NotePickup] Arvid's Note discovered! NightManager.arvid_password_found = true")
		
		_pending_item_data = null
		queue_free()
	else:
		print("[NotePickup] Could not add item to inventory (full or invalid)")
		_pending_item_data = null


func get_interact_text() -> String:
	return "[E] Read " + item_data.item_name
