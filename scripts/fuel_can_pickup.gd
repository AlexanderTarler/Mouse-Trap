extends Area3D

## Fuel Can pickup item in the world.
## When the player interacts (presses E), the fuel can is added to the inventory.
## Uses the jerrycan_1.glb 3D model as its visual representation.
##
## Scene layout:
##   Area3D (root, this script)
##     ├─ CollisionShape3D (box shape matching the canister dimensions)
##     └─ JerrycanModel (instance of jerrycan_1.glb)

## Reference to the Fuel Can ItemData resource (assigned in the scene via @export)
@export var item_data: ItemData


func _ready() -> void:
	add_to_group("xray_fuel_can")
	
	# Ensure this Area3D can be detected by the interaction manager's raycast
	collision_layer = 2
	
	# If no item_data assigned, create a default one inline (self-contained, no external resource dependency)
	if not item_data:
		item_data = ItemData.new()
		item_data.item_name = "Fuel Can"
		item_data.item_description = "A can of fuel for the generator. Each can refills 50 units."
		item_data.item_type = ItemData.ItemType.FUEL
		item_data.scene_to_spawn = preload("res://scenes/fuel_can.tscn")
		print("[FuelCanPickup] Created inline item_data (no external resource dependency)")


func interact() -> void:
	print("[FuelCanPickup] interact() called! item_data=", item_data, " name=", item_data.item_name if item_data else "null")
	if not item_data:
		print("[FuelCanPickup] ERROR: item_data is null!")
		return
	
	if Inventory.add_item(item_data):
		print("[FuelCanPickup] Item added to inventory, removing from scene")
		queue_free()
	else:
		print("[FuelCanPickup] Could not add item (inventory full or invalid), staying in world")


func get_interact_text() -> String:
	if item_data:
		return "[E] Pick up " + item_data.get_display_name()
	return "[E] Pick up Fuel Can"
