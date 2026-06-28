extends Area3D
class_name CabinRoom

## CabinRoom — Room volume with a linked CabinLight reference.
##
## Attach this script to each Area3D node in the "Cabin_Interior" group.
## Each room area defines the spatial volume of a cabin room (e.g., Livingroom,
## Kitchen, ComputerRoom, Bedroom1, Bedroom2).
##
## The @export var room_light allows the level designer to assign the
## corresponding CabinLight node directly in the Inspector. This creates a
## clean, non-brittle mapping between room volumes and their light fixtures
## without relying on naming conventions or string-based lookups.
##
## USAGE IN THE EDITOR:
##   1. Create an Area3D node as a child of the cabin scene.
##   2. Add this script (cabin_room.gd) to the Area3D.
##   3. Add a CollisionShape3D child with a box/cylinder shape that covers
##      the room's interior volume.
##   4. Set the Area3D's collision layer/mask to detect the Player body
##      (typically layer 2) and the Entity body (typically layer 1).
##   5. In the Inspector, drag the corresponding CabinLight node into the
##      "Room Light" export field.
##   6. Add the Area3D to the "Cabin_Interior" group so that
##      RoomLightDetector and player_controller.gd can find it.
##
## The room_name is automatically derived from the node's name in the scene
## tree (e.g., "Livingroom", "Kitchen"). This is used by get_player_room()
## and the RoomLightDetector to identify which room a position is in.

## Reference to the CabinLight that illuminates this room.
## Assign this in the Inspector by dragging the CabinLight node from the
## scene tree into this export field.
@export var room_light: CabinLight = null

## Optional: Override the room name. If left empty, the node's name in the
## scene tree is used. Set this if you want a display name different from
## the node name (e.g., node name "Area3D_Livingroom" → room name "Livingroom").
@export var room_name_override: String = ""


func _ready() -> void:
	# Auto-register in the Cabin_Interior group if not already added
	if not is_in_group("Cabin_Interior"):
		add_to_group("Cabin_Interior")


## Returns the human-readable name of this room.
## Uses room_name_override if set, otherwise falls back to the node's name.
func get_room_name() -> String:
	if not room_name_override.is_empty():
		return room_name_override
	return name


## Returns true if this room's light is currently lit.
## Delegates to CabinLight.is_room_lit() which checks BOTH the switch state
## AND the generator power. Returns false if no room_light is assigned.
func is_lit() -> bool:
	if room_light:
		return room_light.is_room_lit()
	return false


## Returns true if the given world position is inside this room volume.
## Uses a PhysicsPointQuery to test containment against this Area3D's
## collision shape. This is more reliable than has_point() which is not
## available on Area3D in Godot 4.
func contains_point(point: Vector3) -> bool:
	var space_state: PhysicsDirectSpaceState3D = null
	var world := get_world_3d()
	if world:
		space_state = world.direct_space_state
	if not space_state:
		return false
	
	# Use intersect_point to check if the point is inside this area
	var query = PhysicsPointQueryParameters3D.new()
	query.position = point
	query.collide_with_areas = true
	query.collide_with_bodies = false
	
	# NEW: Explicitly tell the query to only look at the physics layer this room lives on!
	# This prevents the query from missing the room or getting blocked by other triggers.
	query.collision_mask = self.collision_layer 
	
	var results = space_state.intersect_point(query)
	for res in results:
		if res.collider == self:
			return true
	return false
