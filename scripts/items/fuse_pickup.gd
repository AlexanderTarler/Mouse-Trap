extends RigidBody3D

## Fuse pickup item in the world.
## When the player interacts (presses E), the fuse is added to the inventory.
## The fuse can then be inserted into the FuseBox to restore generator power.

@export var item_data: ItemData


func _ready() -> void:
	add_to_group("xray_fuse")
	
	# ─── BUG 1 FIX: INTERACTABLE COLLISION LAYER ────────────────────
	# Layer 2 ("Interactable") — the interaction ray only raycasts against
	# layer 2, so this pickup must opt in (keep layer 1 for physics: 1|2 = 3).
	set_collision_layer_value(2, true)
	
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


	# BUG 1 FIX: Ensure Layer 2 ("Interactable") is active — must run AFTER any
	# bare 'collision_layer = N' assignment in _ready so it cannot be overwritten.
	set_collision_layer_value(1, true)
	set_collision_layer_value(2, true)

func set_item_data(data: ItemData) -> void:
	item_data = data
	# Ensure scene_to_spawn is set so the item can be dropped from inventory
	if item_data and not item_data.scene_to_spawn:
		item_data.scene_to_spawn = preload("res://scenes/fuse.tscn")
		print("[FusePickup] Set scene_to_spawn via set_item_data for: ", item_data.item_name)


func interact() -> void:
	if Inventory.add_item(item_data):
		# ─── CLEAR X-RAY HIGHLIGHT ON ALL FUSES ─────────────────────────
		# RoutineManager.on_fuse_picked_up() calls clear_highlight("xray_fuse")
		# which iterates ALL nodes in the "xray_fuse" group and removes the
		# x-ray next_pass material from every one. This ensures that if there
		# are multiple fuse instances in the world, ALL of them stop glowing.
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_fuse_picked_up"):
			rm.on_fuse_picked_up()
		queue_free()


func get_interact_text() -> String:
	return "[E] Pick up " + item_data.item_name
