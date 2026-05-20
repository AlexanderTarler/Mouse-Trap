extends Resource
class_name ItemData

## Data container for inventory items.
## Defines the properties of an item that can be picked up and stored.

enum ItemType {
	BATTERY,
	NOTE,
	TOOL
}

## Display name of the item
@export var item_name: String = "Item"

## Description shown in the inventory UI
@export var item_description: String = ""

## Icon shown in the inventory grid
@export var item_icon: Texture2D

## Type of item (affects how it's used)
@export var item_type: ItemType = ItemType.TOOL

## For notes: the text content to display
@export var note_text: String = ""

## Scene to spawn when dropping the item
@export var scene_to_spawn: PackedScene
