extends Node3D
class_name Generator

## Generator — Central power management for the cabin's electrical grid.
##
## Attach this script to the root node of generator.tscn.
## Controls the fuel drain rate of the generator with separate public
## variables for cabin lights and the porch light, making it easy to
## tweak the drain balance directly in the editor.
##
## HOW IT WORKS:
##   The NightManager calls recalculate_fuel_drain() whenever a light is
##   toggled or the generator state changes. This script overrides that
##   calculation by providing the total drain rate based on which lights
##   are currently switched on.
##
##   Cabin lights each contribute cabin_light_drain_rate when switched on.
##   The porch light (is_faulty = true) contributes porch_light_drain_rate
##   when the generator is running (it's permanently stuck ON).

## Fuel drain rate per cabin light (fuel units per second).
## Each interior light that is switched ON adds this much drain.
## Default: 0.5 fuel units per second per light.
@export var cabin_light_drain_rate: float = 0.5

## Fuel drain rate for the porch light (fuel units per second).
## The porch light is faulty (is_faulty = true) and permanently stuck ON
## whenever the generator is running. This drain is always active as long
## as the generator has fuel.
## Default: 0.3 fuel units per second.
@export var porch_light_drain_rate: float = 0.3

## Base fuel drain rate (fuel units per second).
## The minimum drain that occurs just from the generator running, even if
## no lights are switched on. Represents standby power loss / idle draw.
## Default: 0.12 fuel units per second.
@export var base_drain_rate: float = 0.12

## Starting fuel percentage (0.0 to 100.0).
## Controls how much fuel the generator has at the start of the game.
## Set this in the Inspector on generator.tscn to configure the initial
## fuel level without modifying code. Default: 100.0 (full tank).
## The NightManager reads this value during _ready() to set generator_fuel.
@export var starting_fuel_percent: float = 100.0


func _ready() -> void:
	add_to_group("generator_controller")
	print("[Generator] Initialized. Base drain: %.2f, Cabin light drain: %.2f, Porch light drain: %.2f, Starting fuel: %.0f%%" % [base_drain_rate, cabin_light_drain_rate, porch_light_drain_rate, starting_fuel_percent])



## Calculates the total fuel drain rate based on which lights are currently
## switched on. Called by NightManager.recalculate_fuel_drain().
##
## Iterates all nodes in the "CabinLights" group and sums their drain:
##   - Interior lights (is_faulty == false) → cabin_light_drain_rate each
##   - Porch light (is_faulty == true)     → porch_light_drain_rate
##
## Returns the total drain rate in fuel units per second.
func calculate_total_drain() -> float:
	var total: float = base_drain_rate
	var lights = get_tree().get_nodes_in_group("CabinLights")
	
	for light in lights:
		if not "is_switched_on" in light:
			continue
		if not light.is_switched_on:
			continue
		
		# Check if this is the faulty porch light
		if "is_faulty" in light and light.is_faulty:
			total += porch_light_drain_rate
		else:
			total += cabin_light_drain_rate
	
	return total
