extends Node
class_name NPCGenerator

## Static helper for generating random NPCData resources.
## Provides functions to roll random NPC data and create NPCs with
## different personality types and character models.

## NPC name parts for random name generation
const FIRST_NAMES := [
	"Alex", "Bailey", "Casey", "Dakota", "Ellis", "Finley", "Gray", "Harper",
	"Indigo", "Jade", "Kai", "Logan", "Morgan", "Nico", "Oakley", "Parker",
	"Quinn", "Reese", "Sage", "Taylor", "Uma", "Val", "Winter", "Xen",
	"Yuki", "Zion", "Avery", "Blake", "Cameron", "Drew"
]

const LAST_NAMES := [
	"Smith", "Jones", "Rivera", "Kim", "Chen", "Patel", "Brooks", "Foster",
	"Hayes", "Stone", "Reed", "Cole", "Hart", "Fox", "Gray", "Wells",
	"Knight", "Bishop", "Lane", "Pierce", "Hale", "Ford", "Shaw", "Webb"
]

const PERSONALITY_TYPES := ["WORKER", "SHOPPER", "LOAFER", "NEUTRAL"]

## Available character types (matching glTF model names in assets)
const CHARACTER_TYPES := [
	"Adventurer", "Beach", "Casual_2", "Casual_Hoodie", "Farmer",
	"King", "Punk", "Spacesuit", "Suit", "Swat", "Worker"
]

## Generates a completely random NPCData resource.
static func generate_random() -> NPCData:
	var data = NPCData.new()
	
	# Random name
	data.npc_name = FIRST_NAMES[randi() % FIRST_NAMES.size()] + " " + LAST_NAMES[randi() % LAST_NAMES.size()]
	
	# Random character type
	data.character_type = CHARACTER_TYPES[randi() % CHARACTER_TYPES.size()]
	
	# Random personality
	data.personality_type = PERSONALITY_TYPES[randi() % PERSONALITY_TYPES.size()]
	
	# Random walk speed
	data.walk_speed = randf_range(2.5, 4.0)
	
	return data

## Generates an NPCData with a specific personality type.
static func generate_with_personality(type: String) -> NPCData:
	var data = generate_random()
	data.personality_type = type
	return data

## Generates an NPCData with specific position assignments.
static func generate_at_positions(home: Vector3, work: Vector3, shop: Vector3) -> NPCData:
	var data = generate_random()
	data.home_position = home
	data.work_position = work
	data.shop_position = shop
	return data

## Generates a fully configured NPCData with all parameters.
static func generate_full(home: Vector3, work: Vector3, shop: Vector3, personality: String = "", character_type: String = "") -> NPCData:
	var data = generate_at_positions(home, work, shop)
	if personality and personality in PERSONALITY_TYPES:
		data.personality_type = personality
	if character_type and character_type in CHARACTER_TYPES:
		data.character_type = character_type
	return data

## Returns the path to a character's glTF scene based on type.
static func get_character_scene_path(character_type: String) -> String:
	return "res://assets/Ultimate Modular Men- Feb 2022/Individual Characters/glTF/%s.gltf" % character_type

## Returns a list of character types excluding the given ones (for unique NPCs).
static func get_available_types(exclude: Array[String] = []) -> Array[String]:
	var available: Array[String] = []
	for t in CHARACTER_TYPES:
		available.append(t)
	for t in exclude:
		available.erase(t)
	if available.is_empty():
		for t in CHARACTER_TYPES:
			available.append(t)  # Wrap around if all used
	return available
