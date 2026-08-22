extends RigidBody3D

## Cable Spool pickup item in the world.
## When the player interacts (presses E), the cable spool is added to the inventory.
## Cable spools are used at the GeneratorOutlet to connect a power cable to a
## PortableLamp.

@export var item_data: ItemData


func _ready() -> void:
	# ─── BUG 1 FIX: INTERACTABLE COLLISION LAYER ────────────────────
	# Layer 2 ("Interactable") — the interaction ray only raycasts against
	# layer 2, so this pickup must opt in (keep layer 1 for physics: 1|2 = 3).
	set_collision_layer_value(2, true)
	
	# If no item_data assigned, create a default one
	if not item_data:
		item_data = ItemData.new()
		item_data.item_name = "Cable Spool"
		item_data.item_description = "A spool of heavy-duty electrical cable. Could be used to connect the portable lamp to the generator."
		item_data.item_type = ItemData.ItemType.CABLE_SPOOL
	
	# Always ensure scene_to_spawn is set so the item can be dropped from inventory
	if item_data and not item_data.scene_to_spawn:
		item_data.scene_to_spawn = preload("res://scenes/cable_spool.tscn")
		print("[CableSpoolPickup] Set scene_to_spawn for: ", item_data.item_name)



	# BUG 1 FIX: Ensure Layer 2 ("Interactable") is active — must run AFTER any
	# bare 'collision_layer = N' assignment in _ready so it cannot be overwritten.
	set_collision_layer_value(1, true)
	set_collision_layer_value(2, true)

func set_item_data(data: ItemData) -> void:
	item_data = data
	# Ensure scene_to_spawn is set so the item can be dropped from inventory
	if item_data and not item_data.scene_to_spawn:
		item_data.scene_to_spawn = preload("res://scenes/cable_spool.tscn")
		print("[CableSpoolPickup] Set scene_to_spawn via set_item_data for: ", item_data.item_name)


func interact() -> void:
	if Inventory.add_item(item_data):
		queue_free()


func get_interact_text() -> String:
	return "[E] Pick up " + item_data.item_name
