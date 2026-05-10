extends Node
class_name NPCSpawner

## Spawns NPC instances in the world.
## Uses NPCGenerator to create data and NPCController for the runtime behavior.
## Spawns NPCs at safe, pre-defined positions that are guaranteed to be outside walls.

## Number of NPCs to spawn
@export var npc_count: int = 5

## The NPC scene to instantiate (must have NPCController as root)
@export var npc_scene: PackedScene

## Safe spawn positions - these are guaranteed to be outside any walls or obstacles.
## Houses are at (-6,0,-4) and (6,0,-4) with walls at x=-2 to x=2 and z=-2 to z=2 (relative).
## House interior: x: -8 to -4, z: -6 to -2 (House1) and x: 4 to 8, z: -6 to -2 (House2)
## Safe positions are in front of houses (z > -2) or on the path (z = -4)
var _safe_spawn_positions: Array[Vector3] = [
	Vector3(-6, 0, -1.0),  # In front of House1 (z > -2, outside house)
	Vector3(6, 0, -1.0),   # In front of House2
	Vector3(-6, 0, 0.0),   # Further in front of House1
	Vector3(6, 0, 0.0),    # Further in front of House2
	Vector3(-3, 0, -4.0),  # On the path near House1
	Vector3(3, 0, -4.0),   # On the path near House2
	Vector3(0, 0, -4.0),   # Center of the path
	Vector3(-6, 0, 2.0),   # Side of House1
	Vector3(6, 0, 2.0),    # Side of House2
	Vector3(-8, 0, 0.0),   # Far side of House1
	Vector3(8, 0, 0.0),    # Far side of House2
]

## Home positions (in front of houses, on the path side)
var _home_positions: Array[Vector3] = [
	Vector3(-6, 0, -1.0),  # In front of House1
	Vector3(6, 0, -1.0),   # In front of House2
]

## Work positions
var _work_positions: Array[Vector3] = [
	Vector3(-4, 0, 8),
	Vector3(0, 0, 8),
	Vector3(4, 0, 8),
]

## Shop positions
var _shop_positions: Array[Vector3] = [
	Vector3(-2, 0, -1),
	Vector3(2, 0, -1),
]

## Track used character types to ensure uniqueness
var _used_character_types: Array[String] = []

## Track used spawn positions to avoid duplicates
var _used_spawn_positions: Array[Vector3] = []

func _ready() -> void:
	# Wait a frame for the scene to be fully set up
	await get_tree().physics_frame
	_spawn_npcs()

func _spawn_npcs() -> void:
	if not npc_scene:
		push_error("NPCSpawner: No NPC scene assigned!")
		return
	
	for i in range(npc_count):
		_spawn_single_npc(i)

## Gets a safe spawn position that hasn't been used yet.
func _get_safe_spawn_position() -> Vector3:
	# Filter out already used positions
	var available = []
	for pos in _safe_spawn_positions:
		if pos not in _used_spawn_positions:
			available.append(pos)
	
	if available.is_empty():
		# All positions used, just pick a random one
		available = _safe_spawn_positions.duplicate()
	
	var chosen = available[randi() % available.size()]
	_used_spawn_positions.append(chosen)
	return chosen

func _spawn_single_npc(index: int) -> void:
	# Pick a safe spawn position (guaranteed to be outside walls)
	var home_pos = _get_safe_spawn_position()
	
	# Pick work and shop positions
	var work_pos = _work_positions[index % _work_positions.size()]
	var shop_pos = _shop_positions[index % _shop_positions.size()]
	
	# Pick a unique character type
	var available = NPCGenerator.get_available_types(_used_character_types)
	var char_type = available[randi() % available.size()]
	_used_character_types.append(char_type)
	
	# Generate NPC data
	var data = NPCGenerator.generate_full(home_pos, work_pos, shop_pos, "", char_type)
	
	# Instantiate the NPC scene
	var npc_instance = npc_scene.instantiate() as NPCController
	if not npc_instance:
		push_error("NPCSpawner: Invalid NPC scene!")
		return
	
	# Add to the scene tree first
	add_child(npc_instance)
	
	# Position the NPC at their home (after adding to scene tree for correct global_position)
	npc_instance.global_position = home_pos
	
	# Initialize the NPC (loads model, builds schedule)
	npc_instance.initialize(data)
