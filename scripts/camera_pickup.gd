extends RigidBody3D

## CameraPickup — Floppy Disk Camera world pickup item.
##
## The player finds this camera somewhere in the cabin (e.g., on a desk,
## in a drawer, or on a shelf). When they interact with it (press E),
## the player's built-in PhotoCamera node is activated, allowing them
## to hold RMB to enter viewfinder mode and photograph nests.
##
## The camera is NOT an inventory item — it's a permanent tool that
## stays equipped once found, similar to the flashlight.

@export var item_data: ItemData


func _ready() -> void:
	# Ensure this RigidBody3D can be detected by the interaction manager's raycast
	collision_layer = 1
	
	# Make the item glow slightly so it's noticeable
	var mesh = get_node_or_null("MeshInstance3D")
	if mesh:
		var mat = mesh.get_surface_override_material(0)
		if not mat:
			mat = StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.8, 1.0, 0.3)  # Soft blue glow
		mat.emission_energy_multiplier = 0.5
		mesh.set_surface_override_material(0, mat)


func interact() -> void:
	print("[CameraPickup] interact() called!")
	
	# Find the player via group lookup (works regardless of scene path)
	var player = get_tree().get_first_node_in_group("player")
	
	if player and player.has_method("enable_camera"):
		player.enable_camera()
		print("[CameraPickup] PhotoCamera enabled for player!")
		queue_free()
	else:
		print("[CameraPickup] Could not find player or enable_camera method!")


func get_interact_text() -> String:
	return "[E] Pick up Floppy Disk Camera"
