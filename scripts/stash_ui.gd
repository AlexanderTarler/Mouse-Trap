extends CanvasLayer
class_name StashUI

## Two-panel stash interface for container looting.
## Left side: player's inventory grid.
## Right side: container's contents grid.
## Items can be clicked to transfer between the two.
##
## The stash UI is instantiated lazily by ScrapHeap when the player
## first interacts with a scrap heap. It persists in the scene tree
## and is reused for subsequent interactions.
##
## The container's contents array is mutated directly (by reference),
## so changes persist on the world object automatically.

# ─── STATE ─────────────────────────────────────────────────

## Reference to the currently open ScrapHeap instance.
## When items are transferred, the script directly updates the
## original contents array inside this specific world object.
var _current_scrap_heap: ScrapHeap = null

## Whether the stash UI is currently open.
var _is_open: bool = false

## Reference to the player node (found at runtime).
var _player: Node3D = null

## Array of buttons in the player inventory grid.
var _player_item_buttons: Array[Button] = []

## Array of buttons in the container contents grid.
var _container_item_buttons: Array[Button] = []

# ─── NODE REFERENCES ───────────────────────────────────────

@onready var _background: ColorRect = $Background
@onready var _stash_panel: Panel = $StashPanel
@onready var _player_grid: GridContainer = $StashPanel/PlayerInventoryPanel/PlayerGridContainer
@onready var _container_grid: GridContainer = $StashPanel/ContainerPanel/ContainerGridContainer
@onready var _close_button: Button = $StashPanel/CloseButton
@onready var _title_label: Label = $StashPanel/TitleLabel
@onready var _take_all_button: Button = $StashPanel/TransferButtons/TakeAllButton
@onready var _store_all_button: Button = $StashPanel/TransferButtons/StoreAllButton


## Found by its group (not by a path in the level).
func _enter_tree() -> void:
	add_to_group("stash_ui")


func _ready() -> void:
	# Start hidden
	visible = false
	self.layer = 200  # Above inventory_ui (100) and HUD

	# Connect signals
	_close_button.pressed.connect(_on_close_pressed)
	_take_all_button.pressed.connect(_on_take_all_pressed)
	_store_all_button.pressed.connect(_on_store_all_pressed)

	# Listen for inventory changes to refresh the player grid
	Inventory.inventory_changed.connect(_refresh_player_grid)


# ─── OPEN ──────────────────────────────────────────────────

## Opens the stash UI for the given scrap heap.
## Passes the scrap heap's contents array by reference so mutations
## persist on the world object.
func open_container_stash(scrap_heap: ScrapHeap, contents: Array) -> void:
	_current_scrap_heap = scrap_heap
	_is_open = true
	visible = true
	_background.mouse_filter = Control.MOUSE_FILTER_STOP

	# Find the player if not already cached
	if not _player:
		_player = get_tree().get_first_node_in_group("player")

	# Set the title to identify which scrap heap we're looting
	_title_label.text = "Scrap Heap — %s" % scrap_heap.scrap_heap_id

	# Refresh both grids
	_refresh_player_grid()
	_refresh_container_grid(contents)

	print("[StashUI] Opened for scrap heap: %s" % scrap_heap.scrap_heap_id)


# ─── GRID REFRESH ──────────────────────────────────────────

## Refreshes the player inventory grid from the Inventory autoload.
func _refresh_player_grid() -> void:
	_clear_grid(_player_grid, _player_item_buttons)

	for i in range(Inventory.items.size()):
		var item = Inventory.items[i]
		if not item:
			continue

		var btn = _create_item_button(item)
		btn.pressed.connect(_on_player_item_pressed.bind(i))
		_player_grid.add_child(btn)
		_player_item_buttons.append(btn)


## Refreshes the container contents grid from the scrap heap's
## internal contents array.
func _refresh_container_grid(contents: Array) -> void:
	_clear_grid(_container_grid, _container_item_buttons)

	for i in range(contents.size()):
		var entry = contents[i]
		var item_data = entry.get("item_data")
		var quantity = entry.get("quantity", 1)

		if not item_data:
			continue

		var btn = _create_item_button(item_data)

		# Show quantity badge if stacked
		if quantity > 1:
			btn.text = "%s
x%d" % [item_data.short_label() if item_data.has_method("short_label") else item_data.item_name.left(2), quantity]

		btn.pressed.connect(_on_container_item_pressed.bind(i))
		_container_grid.add_child(btn)
		_container_item_buttons.append(btn)


## Creates a styled button for an item in either grid.
## The slot uses the scrap-heap theme: dark rusty-brown background with
## metallic grey-brown borders, matching stash_ui.tscn's StyleBoxFlat
## palette. Text/icon colors are kept warm and bright for readability.
func _create_item_button(item_data) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(64, 64)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	if item_data.item_icon:
		btn.icon = item_data.item_icon
	else:
		btn.text = item_data.short_label() if item_data.has_method("short_label") else item_data.item_name.left(2)
		btn.add_theme_font_size_override("font_size", 12)
	# A fuel can shows how full it is.
	if item_data.has_method("is_fuel_can") and item_data.is_fuel_can():
		btn.text = "%s
%d%%" % [btn.text, item_data.fuel_percent()] if not item_data.item_icon else "%d%%" % item_data.fuel_percent()

	btn.tooltip_text = item_data.get_display_name() if item_data.has_method("get_display_name") else item_data.item_name

	# ─── SCRAP-HEAP SLOT STYLE (normal) ─────────────────────────────
	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = Color(0.16, 0.1, 0.055, 1)
	slot_style.border_width_left = 1
	slot_style.border_width_top = 1
	slot_style.border_width_right = 1
	slot_style.border_width_bottom = 1
	slot_style.border_color = Color(0.42, 0.28, 0.15, 0.8)
	slot_style.corner_radius_top_left = 3
	slot_style.corner_radius_top_right = 3
	slot_style.corner_radius_bottom_right = 3
	slot_style.corner_radius_bottom_left = 3
	btn.add_theme_stylebox_override("normal", slot_style)

	# ─── SCRAP-HEAP SLOT STYLE (hover / pressed) ────────────────────
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.28, 0.18, 0.1, 1)
	hover_style.border_width_left = 1
	hover_style.border_width_top = 1
	hover_style.border_width_right = 1
	hover_style.border_width_bottom = 1
	hover_style.border_color = Color(0.72, 0.5, 0.28, 1)
	hover_style.corner_radius_top_left = 3
	hover_style.corner_radius_top_right = 3
	hover_style.corner_radius_bottom_right = 3
	hover_style.corner_radius_bottom_left = 3
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)

	# Ensure text/icons stay readable on the dark rusty background
	btn.add_theme_color_override("font_color", Color(1, 0.9, 0.72, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 0.96, 0.85, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 0.96, 0.85, 1))

	return btn


## Clears all children from a grid container and empties the
## corresponding button array.
func _clear_grid(grid: GridContainer, button_array: Array) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	button_array.clear()


# ─── TRANSFER: PLAYER → CONTAINER ─────────────────────────

## Called when the player clicks an item in their inventory grid.
## Transfers the item from the player's inventory to the container.
func _on_player_item_pressed(index: int) -> void:
	if not _is_open or not _current_scrap_heap:
		return
	if index < 0 or index >= Inventory.items.size():
		return

	var item = Inventory.items[index]
	if not item:
		return

	# Remove from player inventory
	Inventory.remove_at(index)

	# Add to container contents (with stacking support)
	_add_to_container_contents(item)

	# Refresh both grids
	_refresh_player_grid()
	_refresh_container_grid(_current_scrap_heap.contents)

	print("[StashUI] Transferred %s to scrap heap." % item.item_name)


## Adds an item to the container's contents array.
## If the same ItemData resource already exists, increments quantity
## instead of adding a new slot (stacking).
func _add_to_container_contents(item) -> void:
	if not _current_scrap_heap:
		return

	# Check if this item type already exists in the container (stacking)
	for entry in _current_scrap_heap.contents:
		if entry.get("item_data") == item:
			entry["quantity"] = entry.get("quantity", 1) + 1
			return

	# New entry
	_current_scrap_heap.contents.append({
		"item_data": item,
		"quantity": 1
	})


# ─── TRANSFER: CONTAINER → PLAYER ─────────────────────────

## Called when the player clicks an item in the container grid.
## Transfers the item from the container to the player's inventory.
func _on_container_item_pressed(index: int) -> void:
	if not _is_open or not _current_scrap_heap:
		return
	if index < 0 or index >= _current_scrap_heap.contents.size():
		return

	var entry = _current_scrap_heap.contents[index]
	var item_data = entry.get("item_data")
	var quantity = entry.get("quantity", 1)

	if not item_data:
		return

	# Try to add to player inventory
	var added = Inventory.add_item(item_data)
	if not added:
		# Inventory is full — show message
		_show_hud_message("I can't carry any more.")
		print("[StashUI] Transfer failed: Player inventory full.")
		return

	# Decrement or remove from container
	if quantity > 1:
		entry["quantity"] = quantity - 1
	else:
		_current_scrap_heap.contents.remove_at(index)

	# Refresh both grids
	_refresh_player_grid()
	_refresh_container_grid(_current_scrap_heap.contents)

	print("[StashUI] Transferred %s to player inventory." % item_data.item_name)


# ─── BULK TRANSFERS ────────────────────────────────────────

## Takes all items from the container into the player's inventory.
func _on_take_all_pressed() -> void:
	if not _is_open or not _current_scrap_heap:
		return

	var contents = _current_scrap_heap.contents
	var i = 0
	while i < contents.size():
		var entry = contents[i]
		var item_data = entry.get("item_data")
		var quantity = entry.get("quantity", 1)

		if not item_data:
			i += 1
			continue

		# Try to add items to player inventory, respecting quantity
		var items_added_this_entry := 0
		var take_success := true
		
		for _q in range(quantity):
			var added = Inventory.add_item(item_data)
			if not added:
				# Inventory full — stop entire Take All
				if items_added_this_entry > 0 and quantity > 1:
					_show_hud_message("I could only carry %d of the %d." % [items_added_this_entry, quantity])
				else:
					_show_hud_message("I can't carry any more.")
				take_success = false
				break
			items_added_this_entry += 1
		
		if not take_success:
			# Update or preserve the remaining quantity
			var remaining = quantity - items_added_this_entry
			if remaining > 0:
				entry["quantity"] = remaining
			else:
				contents.remove_at(i)
				continue  # Don't increment i — next entry shifted into this index
			break  # Stop all further processing — inventory is full
		
		# All quantity items were transferred — remove the entry
		contents.remove_at(i)
		continue  # Don't increment i — next entry shifted into this index

	# Refresh both grids
	_refresh_player_grid()
	_refresh_container_grid(contents)

	print("[StashUI] Take All completed.")


## Stores all items from the player's inventory into the container.
func _on_store_all_pressed() -> void:
	if not _is_open or not _current_scrap_heap:
		return

	# Iterate backwards to avoid index shifting issues
	for i in range(Inventory.items.size() - 1, -1, -1):
		var item = Inventory.items[i]
		if not item:
			continue

		# Remove from player inventory
		Inventory.remove_at(i)

		# Add to container
		_add_to_container_contents(item)

	# Refresh both grids
	_refresh_player_grid()
	_refresh_container_grid(_current_scrap_heap.contents)

	print("[StashUI] Store All completed.")


# ─── CLOSE ─────────────────────────────────────────────────

## Called when the close button is pressed.
func _on_close_pressed() -> void:
	_close_stash()


## Closes the stash UI and restores player controls.
func _close_stash() -> void:
	if not _is_open:
		return

	_is_open = false
	visible = false
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Tell the scrap heap to unfreeze the player
	if _current_scrap_heap and _current_scrap_heap.has_method("close_container"):
		_current_scrap_heap.close_container(_player)

	_current_scrap_heap = null

	print("[StashUI] Closed.")


# ─── INPUT HANDLING ────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _is_open:
		return

	# E key, Tab, or Escape to close
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_E, KEY_TAB, KEY_ESCAPE:
				_close_stash()
				# ─── ESC INPUT HANDLING ─────────────────────────────
				# Mark the Escape press as handled so it does NOT bubble
				# up to PauseMenu's _unhandled_input (which would open
				# the pause menu on top of the stash). E/Tab cause no
				# conflicting global handlers, so they are left alone.
				if event.keycode == KEY_ESCAPE:
					get_viewport().set_input_as_handled()


# ─── UI HELPERS ────────────────────────────────────────────

## Pushes a text message to the HUD overlay.
func _show_hud_message(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(msg)
	else:
		print("[StashUI HUD]: ", msg)
