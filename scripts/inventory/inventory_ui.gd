extends CanvasLayer

## Inventory UI overlay.
## Toggled with TAB, closed with ESC.
## Shows items in a grid, allows using (batteries on flashlight, reading notes) and dropping.

@onready var panel: Panel = $Panel
@onready var grid_container: GridContainer = $Panel/MarginContainer/GridContainer
@onready var close_button: Button = $Panel/CloseButton
@onready var use_button: Button = $Panel/UseButton
@onready var drop_button: Button = $Panel/DropButton
@onready var item_name_label: Label = $Panel/ItemNameLabel
@onready var item_desc_label: Label = $Panel/ItemDescLabel

# Reference to the NoteUI (set in _ready)
var _note_ui: Node = null

var _is_open: bool = false
var _selected_index: int = -1
var _item_buttons: Array[Button] = []
var _tab_pressed_last_frame: bool = false

# Reference to the player's flashlight (set externally)
var _flashlight: Node = null


func _ready() -> void:
	panel.visible = false
	self.layer = 100  # Guarantee this CanvasLayer draws on top of everything
	
	close_button.pressed.connect(_close_inventory)
	use_button.pressed.connect(_on_use_pressed)
	drop_button.pressed.connect(_on_drop_pressed)
	
	# Connect to inventory changes
	Inventory.inventory_changed.connect(_refresh_grid)
	print("[InventoryUI] Connected to Inventory.inventory_changed signal")
	
	# Find the flashlight
	_find_flashlight()
	
	# Find the NoteUI (added to the main scene)
	_find_note_ui()


func _find_flashlight() -> void:
	var player = get_node_or_null("/root/CottageHorror/Player")
	if not player:
		player = get_node_or_null("/root/Main/Player")
	if player:
		_flashlight = player.find_child("Flashlight", true, false)


func _find_note_ui() -> void:
	_note_ui = get_node_or_null("/root/CottageHorror/NoteUI")
	if not _note_ui:
		_note_ui = get_node_or_null("/root/Main/NoteUI")
	if not _note_ui:
		# Retry next frame if the scene isn't ready yet
		call_deferred("_find_note_ui")


func _process(_delta: float) -> void:
	# Hardware-poll TAB key directly — bypasses fragile _input() event consumption
	var tab_down = Input.is_physical_key_pressed(KEY_TAB)
	
	if not _tab_pressed_last_frame and tab_down:
		_tab_pressed_last_frame = true
		if _is_open:
			_close_inventory()
		else:
			_open_inventory()
	elif not tab_down and _tab_pressed_last_frame:
		_tab_pressed_last_frame = false
	
	# Hardware-poll ESC to close inventory (bypasses _input() event consumption)
	if _is_open and Input.is_physical_key_pressed(KEY_ESCAPE):
		_close_inventory()
	
	# Force the mouse to stay visible as long as inventory is open, overriding the Player's camera lock
	if _is_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _open_inventory() -> void:
	_is_open = true
	panel.visible = true
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_grid()
	print("[InventoryUI] Inventory OPENED")


func _close_inventory() -> void:
	_is_open = false
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selected_index = -1
	_update_selection()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Ensure the game is unpaused if it was paused for reading
	if get_tree().paused:
		get_tree().paused = false
	print("[InventoryUI] Inventory CLOSED")


func _refresh_grid() -> void:
	# Clear existing buttons
	for child in grid_container.get_children():
		grid_container.remove_child(child)
		child.queue_free()
	_item_buttons.clear()
	
	print("[InventoryUI] Refreshing grid, items count: ", Inventory.items.size())
	
	for i in range(Inventory.items.size()):
		var item = Inventory.items[i]
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(64, 64)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		
		if item.item_icon:
			btn.icon = item.item_icon
		else:
			btn.text = item.item_name.left(2)
		
		btn.tooltip_text = item.item_name
		btn.pressed.connect(_on_item_selected.bind(i))
		grid_container.add_child(btn)
		_item_buttons.append(btn)
	
	_update_selection()


func _on_item_selected(index: int) -> void:
	_selected_index = index
	_update_selection()


func _update_selection() -> void:
	# Highlight selected button
	for i in range(_item_buttons.size()):
		var btn = _item_buttons[i]
		if i == _selected_index:
			btn.modulate = Color(1, 1, 0.5, 1)
		else:
			btn.modulate = Color(1, 1, 1, 1)
	
	if _selected_index >= 0 and _selected_index < Inventory.items.size():
		var item = Inventory.items[_selected_index]
		item_name_label.text = item.item_name
		item_desc_label.text = item.item_description
		use_button.disabled = false
		drop_button.disabled = false
	else:
		item_name_label.text = ""
		item_desc_label.text = ""
		use_button.disabled = true
		drop_button.disabled = true


func _on_use_pressed() -> void:
	if _selected_index < 0 or _selected_index >= Inventory.items.size():
		return
	
	var item = Inventory.items[_selected_index]
	
	match item.item_type:
		0:  # ItemData.ItemType.BATTERY
			_use_battery(item)
		1:  # ItemData.ItemType.NOTE
			_read_note(item)
		2:  # ItemData.ItemType.TOOL
			print("Tool used: ", item.item_name)


func _use_battery(item) -> void:
	# Find the flashlight and refill it
	if not _flashlight:
		_find_flashlight()
	
	if _flashlight and _flashlight.has_method("refill"):
		_flashlight.refill(50.0)  # Refill 50% per battery
		print("Battery used! Flashlight refilled.")
		
		# Play battery-swap sound via HorrorSoundManager
		var sm = get_node_or_null("/root/HorrorSoundManager")
		if sm:
			sm.play_footstep("wooden")
		
		# Remove the battery from inventory
		Inventory.remove_item(item)
	else:
		print("No flashlight found to refill!")


func _read_note(item) -> void:
	if item.note_text.is_empty():
		return
	
	# Use the dedicated NoteUI if available
	if _note_ui and _note_ui.has_method("display_note"):
		# Close inventory first so the NoteUI takes over
		_close_inventory()
		_note_ui.display_note(item.note_text, item.item_name)
	else:
		print("[InventoryUI] NoteUI not found, cannot display note: ", item.item_name)


func _on_drop_pressed() -> void:
	if _selected_index < 0 or _selected_index >= Inventory.items.size():
		return
	
	var item = Inventory.items[_selected_index]
	print("[InventoryUI] Dropping item: ", item.item_name, " scene_to_spawn=", item.scene_to_spawn)
	
	# Find the player to get drop position
	var player = get_node_or_null("/root/CottageHorror/Player")
	if not player:
		player = get_node_or_null("/root/Main/Player")
	print("[InventoryUI] Player found: ", player)
	
	if player and item.scene_to_spawn:
		# Calculate drop position: player position + forward offset
		var forward = -player.global_transform.basis.z
		var drop_pos = player.global_position + forward * 1.5
		drop_pos.y = player.global_position.y + 0.5
		
		var dropped = item.scene_to_spawn.instantiate()
		get_tree().current_scene.add_child(dropped)
		dropped.global_position = drop_pos
		print("[InventoryUI] Spawned dropped item at: ", drop_pos)
		
		# If it's a RigidBody3D, give it a slight push forward
		if dropped is RigidBody3D:
			dropped.linear_velocity = forward * 2.0
	else:
		print("[InventoryUI] Cannot drop: player=", player, " scene_to_spawn=", item.scene_to_spawn)
	
	# Remove from inventory
	Inventory.remove_at(_selected_index)
	_selected_index = -1
