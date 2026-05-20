extends Node3D

## Spawns batteries and notes at predefined Marker3D spawn points.
## Place Marker3D nodes as children of this node to define spawn locations.
## Optionally assign unique note texts via note_texts array (cycled through spawns).
## Items are raycast-snapped to the ground so they always rest on the surface.

@export var battery_scene: PackedScene
@export var note_scene: PackedScene
@export var battery_count: int = 3
@export var note_count: int = 2
@export var battery_item_data: ItemData
@export var note_item_data: ItemData
@export var note_texts: Array[String] = []

## How high above the spawn point to start the ground-snap raycast
@export var raycast_start_height: float = 10.0

## How far down the raycast goes to find the ground
@export var raycast_distance: float = 20.0

## Collision layers to check for ground snapping (default: layer 1 = world/terrain)
@export_flags_3d_physics var ground_collision_mask: int = 1


func _ready() -> void:
	# Defer spawning to ensure the world and physics are fully initialized
	call_deferred("_spawn_items")


func _spawn_items() -> void:
	# Collect all Marker3D children as spawn points
	var spawn_points: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D:
			spawn_points.append(child)
	
	if spawn_points.is_empty():
		print("ItemSpawner: No Marker3D spawn points found!")
		return
	
	# Shuffle spawn points for random placement
	spawn_points.shuffle()
	
	var space_state = null
	if get_world_3d():
		space_state = get_world_3d().direct_space_state
	
	var spawn_idx = 0
	
	# Spawn batteries
	for i in range(battery_count):
		if spawn_idx >= spawn_points.size():
			spawn_idx = 0  # Wrap around if we have more items than points
		
		if battery_scene:
			var battery = battery_scene.instantiate()
			add_child(battery)
			
			# Snap to ground using raycast
			var ground_pos = _snap_to_ground(space_state, spawn_points[spawn_idx].global_position)
			battery.global_position = ground_pos
			
			# Assign item data if provided
			if battery_item_data and battery.has_method("set_item_data"):
				battery.set_item_data(battery_item_data)
			elif battery.has_method("set_item_data"):
				# Create a default battery item data
				var data = ItemData.new()
				data.item_name = "Battery"
				data.item_description = "A spare battery for the flashlight."
				data.item_type = ItemData.ItemType.BATTERY
				battery.set_item_data(data)
			
			spawn_idx += 1
	
	# Spawn notes
	for i in range(note_count):
		if spawn_idx >= spawn_points.size():
			spawn_idx = 0
		
		if note_scene:
			var note = note_scene.instantiate()
			add_child(note)
			
			# Snap to ground using raycast
			var ground_pos = _snap_to_ground(space_state, spawn_points[spawn_idx].global_position)
			note.global_position = ground_pos
			
			if note_item_data and note.has_method("set_item_data"):
				note.set_item_data(note_item_data)
			elif note.has_method("set_item_data"):
				var data = ItemData.new()
				data.item_name = "Note"
				data.item_description = "A handwritten note."
				data.item_type = ItemData.ItemType.NOTE
				
				# Use unique note text if available, cycling through the array
				if not note_texts.is_empty():
					data.note_text = note_texts[i % note_texts.size()]
				else:
					data.note_text = "The entity feeds on fear... Stay in the light."
				
				note.set_item_data(data)
			
			spawn_idx += 1
	
	print("ItemSpawner: Spawned ", battery_count, " batteries and ", note_count, " notes")



## Casts a ray downward from above the given position to find the ground surface.
## Returns the snapped position (just above ground) or the original position if no ground found.
func _snap_to_ground(space_state: PhysicsDirectSpaceState3D, original_pos: Vector3) -> Vector3:
	var from = Vector3(original_pos.x, original_pos.y + raycast_start_height, original_pos.z)
	var to = Vector3(original_pos.x, original_pos.y - raycast_distance, original_pos.z)
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = ground_collision_mask
	
	var result = space_state.intersect_ray(query)
	
	if result:
		# Place item slightly above the ground surface to avoid z-fighting
		return result.position + Vector3(0, 0.05, 0)
	else:
		# No ground found, use original position as fallback
		print("ItemSpawner: No ground found below ", original_pos, " — using original position")
		return original_pos
