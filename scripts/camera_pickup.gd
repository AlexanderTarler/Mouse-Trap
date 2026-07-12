extends RigidBody3D

## CameraPickup — DEPRECATED. The camera system has been removed.
## Nests are now documented by holding E for 3 seconds.
## This pickup item is kept for scene compatibility but does nothing.

@export var item_data: ItemData


func _ready() -> void:
	# Remove from collision detection so it doesn't show prompts
	collision_layer = 0


func interact() -> void:
	print("[CameraPickup] Camera system is deprecated. Nests are documented via Hold E.")
	queue_free()


func get_interact_text() -> String:
	return ""
