extends Resource
class_name ItemData

## Data container for inventory items.
## Defines the properties of an item that can be picked up and stored.

enum ItemType {
	BATTERY,
	NOTE,
	TOOL,
	PLANK,
	FUEL,
	KEY,
	CABLE_SPOOL,
	CAR_PART,
	PORTABLE_LIGHT
}




## Display name of the item
@export var item_name: String = "Item"

## Description shown in the inventory UI
@export var item_description: String = ""

## Icon shown in the inventory grid
@export var item_icon: Texture2D

## Type of item (affects how it's used)
@export var item_type: ItemType = ItemType.TOOL

## ─── FUEL CAN: PROPORTIONAL DEPLETION (Task 1) ──────────────────────
## Remaining fuel in this can, in can-units. Capacity is 100.0 can-units.
## The generator consumes 2 can-units per 1 generator fuel unit (1% of the
## generator's 100-unit tank costs 2% of the can's capacity).
## ONLY generator_interaction.gd reads/depletes this value. All other item
## types safely ignore it (default 100.0 is harmless).
@export var fuel_amount: float = 100.0

## For notes: the text content to display
@export var note_text: String = ""

## Scene to spawn when dropping the item
@export var scene_to_spawn: PackedScene
