extends RigidBody3D

## Wooden Plank pickup item in the world.
## When the player interacts (presses E), the plank is added to the inventory.
## Planks can be used to board up windows via CabinWindow.interact().

@export var item_data: ItemData


func _ready() -> void:
	# If no item_data assigned, create a default one
	if not item_data:
		item_data = ItemData.new()
		item_data.item_name = "Wooden Plank"
		item_data.item_description = "A sturdy wooden plank. Can be used to board up windows."
		item_data.item_type = ItemData.ItemType.PLANK
	
	# Always ensure scene_to_spawn is set so the item can be dropped from inventory
	if item_data and not item_data.scene_to_spawn:
		item_data.scene_to_spawn = preload("res://scenes/wooden_plank.tscn")
		print("[PlankPickup] Set scene_to_spawn for: ", item_data.item_name)


func set_item_data(data: ItemData) -> void:
	item_data = data
	# Ensure scene_to_spawn is set so the item can be dropped from inventory
	if item_data and not item_data.scene_to_spawn:
		item_data.scene_to_spawn = preload("res://scenes/wooden_plank.tscn")
		print("[PlankPickup] Set scene_to_spawn via set_item_data for: ", item_data.item_name)


func interact() -> void:
	if Inventory.add_item(item_data):
		queue_free()


func get_interact_text() -> String:
	return "[E] Pick up " + item_data.item_name
