extends CanvasLayer

## Inventory UI overlay.
## Toggled with TAB, closed with ESC.
## Shows items in a grid, allows using (batteries on flashlight, reading notes) and dropping.

@onready var panel: Panel = $Panel
@onready var grid_container: GridContainer = $Panel/MarginContainer/GridContainer
@onready var close_button: Button = $Panel/CloseButton
@onready var use_button: Button = $Panel/UseButton
@onready var drop_button: Button = $Panel/DropButton
@onready var info_box: Panel = $Panel/InfoBox
@onready var item_name_label: Label = $Panel/ItemNameLabel
@onready var item_desc_label: Label = $Panel/ItemDescLabel
@onready var info_item_name_label: Label = $Panel/InfoBox/InfoItemName
@onready var info_item_desc_label: Label = $Panel/InfoBox/InfoItemDesc
@onready var tooltip_label: Label = $TooltipLabel

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


func _input(event: InputEvent) -> void:
	# ─── ESC CLOSE WITH INPUT CONSUMPTION ─────────────────────────
	# When the inventory is open, pressing Escape closes it and marks
	# the input event as handled via get_viewport().set_input_as_handled().
	# This prevents the event from bubbling up to PauseMenu's
	# _unhandled_input(), which would otherwise open the pause menu
	# on top of the inventory — exactly like computer_ui.gd / stash_ui.gd.
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_inventory()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# ─── STASH UI GUARD ────────────────────────────────────
	# Prevent TAB from opening the inventory while the stash UI
	# (scrap heap looting interface) is open. The stash UI handles
	# its own E/Tab/ESC close logic.
	if _is_stash_ui_open():
		if _is_open:
			_close_inventory()
		return
	
	# ─── COMPUTER UI GUARD ─────────────────────────────────
	# Prevent TAB from toggling the inventory while the computer
	# (computer_ui.gd) is open. The player should not be able to
	# open the inventory while interacting with the computer.
	var computer_ui = get_node_or_null("/root/CottageHorror/ComputerUI")
	if not computer_ui:
		computer_ui = get_tree().get_first_node_in_group("computer_ui")
	if computer_ui and computer_ui.get("is_open"):
		if _is_open:
			_close_inventory()
		return

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
	
	# ─── HOVER TOOLTIP ─────────────────────────────────────
	# Update the tooltip label position and text when hovering over a slot.
	if _is_open:
		_update_tooltip()


## Builds the display string for an inventory item. Fuel cans append their
## remaining fuel percentage (ItemData.fuel_amount uses 100 = full can):
##   "Fuel Can (75%)". All other items return their plain name.
func _build_item_display_name(item) -> String:
	if item and item.item_name == "Fuel Can" and "fuel_amount" in item:
		var pct := int(clampf(item.fuel_amount, 0.0, 100.0))
		return "%s (%d%%)" % [item.item_name, pct]
	return item.item_name if item else ""


## Updates the hover tooltip: finds the slot under the mouse cursor and
## shows its item name next to the cursor.
func _update_tooltip() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var found_hover := false
	
	for i in range(_item_buttons.size()):
		var btn := _item_buttons[i]
		if not btn or not btn.visible:
			continue
		
		# Check if the mouse is within the button's screen rect
		var btn_rect := Rect2(btn.global_position, btn.size)
		if btn_rect.has_point(mouse_pos):
			if i < Inventory.items.size():
				var item = Inventory.items[i]
				if item:
					tooltip_label.text = _build_item_display_name(item)
					# Position the tooltip offset from the cursor (16, 16)
					tooltip_label.global_position = mouse_pos + Vector2(16, 16)
					tooltip_label.visible = true
					found_hover = true
			break
	
	if not found_hover:
		tooltip_label.visible = false


## Checks if the StashUI (scrap heap looting interface) is currently open.
## Returns true if the stash UI exists and is visible, false otherwise.
func _is_stash_ui_open() -> bool:
	var stash_ui = get_node_or_null("/root/CottageHorror/StashUI")
	if not stash_ui:
		stash_ui = get_node_or_null("/root/Main/StashUI")
	if stash_ui and stash_ui.get("_is_open"):
		return true
	return false


## Plays a simple sound effect via a transient AudioStreamPlayer.
## The player is auto-freed when the sound finishes.
func _play_sfx(res_path: String) -> void:
	var stream := load(res_path)
	if not stream:
		return
	var player := AudioStreamPlayer.new()
	player.bus = "SFX"
	player.stream = stream
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func _open_inventory() -> void:
	# The "Press [TAB]" hint is done with (TAB opens the inventory here, so
	# the player controller's toggle that used to clear it never ran).
	var tm := get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("mark_learned"):
		tm.mark_learned("inventory")
	_is_open = true
	panel.visible = true
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_grid()
	_play_sfx("res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Player/Misc/inventory_open.ogg")
	print("[InventoryUI] Inventory OPENED")


func _close_inventory() -> void:
	_is_open = false
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_label.visible = false
	_selected_index = -1
	_update_selection()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_play_sfx("res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Player/Misc/inventory_close.ogg")
	# Ensure the game is unpaused if it was paused for reading
	if get_tree().paused:
		get_tree().paused = false
	print("[InventoryUI] Inventory CLOSED")


# ─── ITEM TYPE COLORS (PSX retro palette) ──────────────────────────────
# These colors tint the slot border based on item type for quick visual ID.
const TYPE_COLORS: Dictionary = {
	0: Color(0.9, 0.6, 0.15, 1),  # BATTERY — warm amber
	1: Color(0.85, 0.8, 0.6, 1),  # NOTE — parchment cream
	2: Color(0.7, 0.7, 0.7, 1),   # TOOL — steel gray
	3: Color(0.6, 0.4, 0.2, 1),   # PLANK — wood brown
	4: Color(0.9, 0.2, 0.1, 1),   # FUEL — danger red
	5: Color(0.85, 0.75, 0.3, 1), # KEY — brass gold
	6: Color(0.4, 0.6, 0.8, 1),   # CABLE_SPOOL — copper blue
	7: Color(0.5, 0.7, 0.9, 1),   # CAR_PART — cool steel blue
}

## Returns a StyleBoxFlat configured as an inventory slot for the given item type.
## Normal state uses a dark background with a type-colored border.
## Hover state brightens the background and border.
func _create_slot_style(item_type: int, selected: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	var type_color = TYPE_COLORS.get(item_type, Color(0.4, 0.4, 0.4, 1))
	
	if selected:
		s.bg_color = Color(0.2, 0.12, 0.06, 1)
		s.border_width_left = 2
		s.border_width_top = 2
		s.border_width_right = 2
		s.border_width_bottom = 2
		s.border_color = Color(1, 0.85, 0.4, 1)
	else:
		s.bg_color = Color(0.08, 0.04, 0.02, 1)
		s.border_width_left = 1
		s.border_width_top = 1
		s.border_width_right = 1
		s.border_width_bottom = 1
		s.border_color = type_color
		s.border_color.a = 0.6
	
	return s


## Returns a StyleBoxFlat for an EMPTY inventory slot.
## Empty slots are tinted slightly DARKER than the surrounding UI panel
## background (a dark yellow/brown) so the available capacity reads as
## recessed, non-interactive cells instead of blank space.
func _create_empty_slot_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.035, 0.016, 0.008, 1)
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = Color(0.16, 0.08, 0.035, 0.6)
	s.corner_radius_top_left = 2
	s.corner_radius_top_right = 2
	s.corner_radius_bottom_right = 2
	s.corner_radius_bottom_left = 2
	return s


func _refresh_grid() -> void:
	# Clear existing buttons
	for child in grid_container.get_children():
		grid_container.remove_child(child)
		child.queue_free()
	_item_buttons.clear()
	
	print("[InventoryUI] Refreshing grid, items count: ", Inventory.items.size(), "/", Inventory.MAX_ITEMS)
	
	# ─── DYNAMIC SLOT COUNT ─────────────────────────────────────────
	# Render one button for EVERY possible inventory slot (based on
	# Inventory.MAX_ITEMS), not just the filled ones. Empty slots get a
	# darker, non-interactive style so the player can see their capacity.
	var max_slots: int = Inventory.MAX_ITEMS
	
	for i in range(max_slots):
		var item = Inventory.items[i] if i < Inventory.items.size() else null
		
		# Create a Button for the slot (72x72) — filled or empty
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(72, 72)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		
		if item:
			if item.item_icon:
				btn.icon = item.item_icon
				btn.expand_icon = true
			else:
				btn.text = item.short_label() if item.has_method("short_label") else item.item_name.left(2)
				btn.add_theme_font_size_override("font_size", 13)
			# A fuel can shows how full it is on its slot.
			if item.has_method("is_fuel_can") and item.is_fuel_can():
				btn.text = "%s
%d%%" % [btn.text, item.fuel_percent()] if not item.item_icon else "%d%%" % item.fuel_percent()
				btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			btn.tooltip_text = item.get_display_name() if item.has_method("get_display_name") else item.item_name
			
			# Apply the type-colored slot style
			var slot_style = _create_slot_style(item.item_type, false)
			btn.add_theme_stylebox_override("normal", slot_style)
			
			btn.pressed.connect(_on_item_selected.bind(i))
		else:
			# ─── EMPTY SLOT ─────────────────────────────────────────
			# Disabled + darker than the surrounding panel background so
			# unfilled capacity reads as recessed dead cells.
			btn.disabled = true
			var empty_style := _create_empty_slot_style()
			btn.add_theme_stylebox_override("normal", empty_style)
			btn.add_theme_stylebox_override("hover", empty_style)
			btn.add_theme_stylebox_override("pressed", empty_style)
			btn.add_theme_stylebox_override("disabled", empty_style)
		
		grid_container.add_child(btn)
		_item_buttons.append(btn)
	
	_update_selection()


func _on_item_selected(index: int) -> void:
	_selected_index = index
	_update_selection()


func _update_selection() -> void:
	# If the previously selected index no longer holds an item, clear it
	if _selected_index >= Inventory.items.size():
		_selected_index = -1
	
	# Update slot styles based on selection/empty state
	for i in range(_item_buttons.size()):
		var btn = _item_buttons[i]
		
		if i >= Inventory.items.size():
			# Empty slot — always keep the dark recessed style
			var empty_style := _create_empty_slot_style()
			btn.add_theme_stylebox_override("normal", empty_style)
			btn.add_theme_stylebox_override("hover", empty_style)
			btn.add_theme_stylebox_override("pressed", empty_style)
			btn.add_theme_stylebox_override("disabled", empty_style)
			continue
		
		var is_selected = (i == _selected_index)
		btn.add_theme_stylebox_override("normal", _create_slot_style(
			Inventory.items[i].item_type,
			is_selected
		))
	
	if _selected_index >= 0 and _selected_index < Inventory.items.size():
		var item = Inventory.items[_selected_index]
		item_name_label.text = _build_item_display_name(item)
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
			sm.play_footstep_at("wooden", Vector3.ZERO)
		
		# Remove the battery from inventory
		Inventory.remove_item(item)
		var tm := get_node_or_null("/root/TutorialManager")
		if tm and tm.has_method("mark_learned"):
			tm.mark_learned("low_battery")
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
	
	# A dropped fuel can keeps its own fuel level (it came back full before).
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
		if "item_data" in dropped and item.has_method("is_fuel_can") and item.is_fuel_can():
			dropped.item_data = item
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