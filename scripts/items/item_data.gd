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

## For notes: what the player thinks once they've read it (Monologue),
## in place of "I'll keep this in my notebook." Empty: no thought.
@export_multiline var read_thought: String = ""

## Scene to spawn when dropping the item
@export var scene_to_spawn: PackedScene


## True for a fuel can (the only item with a fuel level).
func is_fuel_can() -> bool:
	return item_type == ItemType.FUEL or item_name == "Fuel Can"


## Its fuel left as a whole percentage (fuel cans).
func fuel_percent() -> int:
	return int(round(clampf(fuel_amount, 0.0, 100.0)))


## Slot labels, distinct at a glance (the first two letters made "Fuse" and
## "Fuel Can" both "Fu").
const SHORT_LABELS := {
	"Wooden Plank": "PLANK", "Battery": "BATT", "Fuse": "FUSE", "Fuel Can": "FUEL",
	"Cable Spool": "CABLE", "Cabin Key": "KEY", "Portable Light": "LAMP",
	"Radiator": "RAD", "Ignition Wiring": "WIRES", "Car Battery": "CAR\nBATT",
	"Research Map": "MAP", "Field Journal": "BOOK",
}


## The short label shown on an inventory or stash slot.
func short_label() -> String:
	if SHORT_LABELS.has(item_name):
		return SHORT_LABELS[item_name]
	if item_type == ItemType.NOTE:
		return "NOTE"
	# Otherwise: the first word, cut to five letters.
	return item_name.get_slice(" ", 0).left(5).to_upper()


## The name as shown to the player: "Fuel Can (75%)" for a fuel can.
func get_display_name() -> String:
	if is_fuel_can():
		return "%s (%d%%)" % [item_name, fuel_percent()]
	return item_name
