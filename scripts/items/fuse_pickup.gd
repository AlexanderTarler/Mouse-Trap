extends RigidBody3D

## Fuse pickup item in the world.
## When the player interacts (presses E), the fuse is added to the inventory.
## The fuse can then be inserted into the FuseBox to restore generator power.

@export var item_data: ItemData


func _ready() -> void:
	# If no item_data assigned, create a default one
	if not item_data:
		item_data = ItemData.new()
		item_data.item_name = "Fuse"
		item_data.item_description = "A heavy ceramic fuse. It might fit in the fuse box."
		item_data.item_type = ItemData.ItemType.TOOL
	
	# Always ensure scene_to_spawn is set so the item can be dropped from inventory
	if item_data and not item_data.scene_to_spawn:
		item_data.scene_to_spawn = preload("res://scenes/fuse.tscn")
		print("[FusePickup] Set scene_to_spawn for: ", item_data.item_name)


func set_item_data(data: ItemData) -> void:
	item_data = data
	# Ensure scene_to_spawn is set so the item can be dropped from inventory
	if item_data and not item_data.scene_to_spawn:
		item_data.scene_to_spawn = preload("res://scenes/fuse.tscn")
		print("[FusePickup] Set scene_to_spawn via set_item_data for: ", item_data.item_name)


func interact() -> void:
	if Inventory.add_item(item_data):
		queue_free()


func get_interact_text() -> String:
	return "[E] Pick up " + item_data.item_name
