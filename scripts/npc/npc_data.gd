extends Resource
class_name NPCData

## Data container for NPC generation parameters.
## This Resource stores all visual and behavioral traits for an NPC.
## Create instances via NPCGenerator, then pass to NPCController.initialize().

## Character type (matches glTF model name, e.g. "Adventurer", "Farmer", etc.)
@export var character_type: String = "Adventurer"

## NPC's display name
@export var npc_name: String = ""

## Personality type affects schedule and behavior
@export var personality_type: String = "NEUTRAL"

## Movement speed
@export var walk_speed: float = 3.0

## Home position (where NPC returns at night)
@export var home_position: Vector3 = Vector3.ZERO

## Work position (where NPC goes during work hours)
@export var work_position: Vector3 = Vector3.ZERO

## Shop position (where NPC goes to shop)
@export var shop_position: Vector3 = Vector3.ZERO
