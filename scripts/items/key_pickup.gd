extends RigidBody3D

## Key pickup item in the world.
## When the player interacts (presses E), the key is added to the inventory.
## Keys can be used to unlock locked doors via LockedDoor.interact().

@export var item_data: ItemData


func _ready() -> void:
	# If no item_data assigned, create a default one
	if not item_data:
		item_data = ItemData.new()
		item_data.item_name = "Cabin Key"
		item_data.item_description = "A rusty old key. It might open something in the cabin."
		item_data.item_type = ItemData.ItemType.KEY
	
	# Always ensure scene_to_spawn is set so the item can be dropped from inventory
	if item_data and not item_data.scene_to_spawn:
		item_data.scene_to_spawn = preload("res://scenes/key.tscn")
		print("[KeyPickup] Set scene_to_spawn for: ", item_data.item_name)


func set_item_data(data: ItemData) -> void:
	item_data = data
	# Ensure scene_to_spawn is set so the item can be dropped from inventory
	if item_data and not item_data.scene_to_spawn:
		item_data.scene_to_spawn = preload("res://scenes/key.tscn")
		print("[KeyPickup] Set scene_to_spawn via set_item_data for: ", item_data.item_name)


func interact() -> void:
	print("[KeyPickup] interact() called! item_data=", item_data, " name=", item_data.item_name if item_data else "null")
	if Inventory.add_item(item_data):
		print("[KeyPickup] Item added to inventory, removing from scene")
		queue_free()
	else:
		print("[KeyPickup] Could not add item (inventory full or invalid), staying in world")


func get_interact_text() -> String:
	return "[E] Pick up " + item_data.item_name
