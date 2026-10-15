extends Area3D
class_name GeneratorOutlet

## GeneratorOutlet — Cable connection point on the generator.
##
## AUTO-CONNECT FLOW (Request 3):
##   When the player interacts with this outlet while holding BOTH a
##   "Cable Spool" AND a "Portable Light" in their inventory, the outlet:
##     1. Consumes the Cable Spool from inventory
##     2. Consumes the Portable Light from inventory
##     3. Spawns a fresh portable_light.tscn near the outlet
##     4. Automatically PHYSICALLY GRABS the lamp (as if the player held E)
##        via PhysicalGrab.pick_up() — the lamp appears in the player's hand
##     5. Spawns the PowerCable, plugs it into this outlet, and attaches
##        the free end to the player's hand marker
##     6. The player then carries the lamp to a spot and releases E to drop/
##        deploy it, then taps E on the lamp base to connect the cable free end.
##
## LEGACY CABLE-ONLY FLOW (fallback):
##   If the player only has a Cable Spool (no Portable Light in inventory),
##   the original behavior is preserved: spawn the PowerCable, plug it in,
##   and let the player carry the free end to a lamp already in the world.

## Reference to the active PowerCable instance (if one has been spawned).
var _active_cable: Node = null

## Preload the PowerCable scene so we can instantiate it.
const POWER_CABLE_SCENE: PackedScene = preload("res://scenes/power_cable.tscn")

## Preload the PortableLamp scene.
const PORTABLE_LIGHT_SCENE: PackedScene = preload("res://scenes/portable_light.tscn")

## Reference to the portable lamp spawned by the auto-connect flow.
var _spawned_lamp: Node = null


func _ready() -> void:
	# Ensure this Area3D can be detected by the interaction manager's raycast
	collision_layer = 2
	# Add to the generator_outlet group so PowerCable can auto-find us
	add_to_group("generator_outlet")


func interact() -> void:
	# ─── CHECK IF CABLE IS ALREADY CONNECTED ─────────────────────────────
	if _active_cable:
		print("[GeneratorOutlet] Cable already connected! Disconnect it first.")
		return

	# ─── DUAL-ITEM AUTO-CONNECT FLOW ─────────────────────────────────────
	# If the player has BOTH a Cable Spool AND a Portable Light, run the
	# full auto-connect pipeline: consume items, spawn lamp + cable, and
	# physically grab the lamp as if the player held E.
	var has_cable: bool = _player_has_cable_spool()
	var has_lamp: bool = _player_has_portable_light()

	if has_cable and has_lamp:
		_try_auto_connect()
		return

	# ─── LEGACY CABLE-ONLY FLOW ─────────────────────────────────────────
	if not has_cable:
		print("[GeneratorOutlet] Need a Cable Spool to connect the power cable.")
		return

	# ─── FIND THE PLAYER'S HAND MARKER ───────────────────────────────────
	var hand_marker: Marker3D = _find_player_hand_marker()
	if not hand_marker:
		print("[GeneratorOutlet] ERROR: Could not find player hand marker!")
		return

	# ─── SPAWN THE POWER CABLE ───────────────────────────────────────────
	var cable: Node = POWER_CABLE_SCENE.instantiate()
	get_tree().current_scene.add_child(cable)

	# Plug the cable into this outlet and attach the free end to the player's hand
	if cable.has_method("plug_to_source"):
		cable.plug_to_source(self, hand_marker)

	_active_cable = cable

	# Consume the cable spool from inventory
	_consume_cable_spool()

	# ─── TASK 4: "SET TRAP" — CABLE CONNECTED TO GENERATOR ────────────
	# The side-track's "Set trap" objective requires both the generator
	# and lamp cable ends. Notify RoutineManager the generator end is in.
	var rm_gen = get_node_or_null("/root/RoutineManager")
	if rm_gen and rm_gen.has_method("on_cable_connected_to_gen"):
		rm_gen.on_cable_connected_to_gen()

	print("[GeneratorOutlet] Cable plugged in! Drag the free end to a lamp.")


## ─── AUTO-CONNECT PIPELINE ────────────────────────────────────────────────
## Consumes both items, spawns the portable light, physically grabs it, and
## spawns the power cable with the free end in the player's hand.
func _try_auto_connect() -> void:
	print("[GeneratorOutlet] AUTO-CONNECT: Player has Cable Spool + Portable Light!")

	# 1. Find the player's hand marker before spawning anything.
	var hand_marker: Marker3D = _find_player_hand_marker()
	if not hand_marker:
		print("[GeneratorOutlet] ERROR: Could not find player hand marker!")
		return

	# 2. Consume both inventory items.
	_consume_cable_spool()
	_consume_portable_light()
	print("[GeneratorOutlet] Cable Spool + Portable Light consumed from inventory.")

	# 3. Spawn the PortableLamp near the outlet.
	var lamp: Node = PORTABLE_LIGHT_SCENE.instantiate()
	get_tree().current_scene.add_child(lamp)

	# Position the lamp at the outlet (it will snap to the player's hand via pick_up).
	var spawn_pos: Vector3 = global_position + Vector3(0, 0.8, 0)
	# Try to find a PortableLightSpawn marker first (same as generator_interaction.gd).
	var spawn_marker := get_node_or_null("../PortableLightSpawn") as Marker3D
	if spawn_marker:
		spawn_pos = spawn_marker.global_position
	lamp.global_position = spawn_pos

	_spawned_lamp = lamp
	print("[GeneratorOutlet] Portable light spawned at: ", lamp.global_position)

	# 4. PHYSICALLY GRAB THE LAMP (as if the player held E).
	# The PortableLamp.pick_up(hand_marker) call freezes physics, connects
	# to the hand marker lerp loop, and prepares it for physical carry.
	var physical_grab := get_tree().get_first_node_in_group("physical_grab")
	if physical_grab and physical_grab.has_method("grab_lamp"):
		physical_grab.grab_lamp(lamp)
		print("[GeneratorOutlet] Portable light auto-grabbed via PhysicalGrab!")
	elif lamp.has_method("pick_up"):
		lamp.pick_up(hand_marker)
		print("[GeneratorOutlet] Portable light auto-grabbed to player's hand (fallback)!")

	# ─── AUTO-GRAB FALLBACK ─────────────────────────────────────────────
	# If pick_up isn't available or the player isn't set up for physical
	# grab, at least mark it deployed so it can be interacted with.
	if not lamp.has_method("pick_up"):
		lamp.is_deployed = true
		print("[GeneratorOutlet] WARNING: pick_up() unavailable. Lamp left deployed at spawn.")

	# 5. SPAWN THE POWER CABLE, plug it into this outlet, AND connect the
	# other end to the spawned lamp so the cable reaches the light too.
	var cable: Node = POWER_CABLE_SCENE.instantiate()
	get_tree().current_scene.add_child(cable)

	if cable.has_method("plug_to_source"):
		cable.plug_to_source(self, hand_marker)

	if cable.has_method("connect_to_lamp"):
		cable.connect_to_lamp(lamp)

	_active_cable = cable

	# ─── TASK 4: "SET TRAP" — BOTH ENDS CONNECTED (auto flow) ─────────
	# Here the cable is plugged into the generator AND the light at once,
	# so both halves of "Set trap" are done (the light end was never
	# reported in this flow, so the objective could not complete).
	var rm_gen2 = get_node_or_null("/root/RoutineManager")
	if rm_gen2 and rm_gen2.has_method("on_cable_connected_to_gen"):
		rm_gen2.on_cable_connected_to_gen()
	if rm_gen2 and rm_gen2.has_method("on_cable_connected_to_light"):
		rm_gen2.on_cable_connected_to_light()

	print("[GeneratorOutlet] Cable plugged in! Free end in player's hand. Carry the lamp and drop it to deploy.")


## Checks if the player has a Cable Spool in their inventory.
func _player_has_cable_spool() -> bool:
	for item in Inventory.items:
		if item != null and "item_name" in item and item.item_name == "Cable Spool":
			return true
	return false


## Checks if the player has a Portable Light in their inventory.
func _player_has_portable_light() -> bool:
	for item in Inventory.items:
		if item != null and "item_name" in item and item.item_name == "Portable Light":
			return true
	return false


## Consumes one Cable Spool from the player's inventory.
func _consume_cable_spool() -> void:
	for i in range(Inventory.items.size()):
		var item = Inventory.items[i]
		if item != null and "item_name" in item and item.item_name == "Cable Spool":
			Inventory.remove_at(i)
			print("[GeneratorOutlet] Cable Spool consumed.")
			return


## Consumes one Portable Light from the player's inventory.
func _consume_portable_light() -> void:
	for i in range(Inventory.items.size()):
		var item = Inventory.items[i]
		if item != null and "item_name" in item and item.item_name == "Portable Light":
			Inventory.remove_at(i)
			print("[GeneratorOutlet] Portable Light consumed.")
			return


## Finds the player's hand marker (CarryMarker) for the cable's free end.
## Walks up the scene tree to find the PhysicalGrab, then gets its carry marker.
func _find_player_hand_marker() -> Marker3D:
	# Try to find PhysicalGrab in the scene
	var physical_grab: Node = get_tree().get_first_node_in_group("physical_grab")
	if physical_grab and physical_grab.has_method("_get_or_create_carry_marker"):
		return physical_grab._get_or_create_carry_marker()

	# Fallback: search for a CarryMarker under the camera
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		var marker: Marker3D = camera.get_node_or_null("CarryMarker")
		if marker:
			return marker

	return null


## Public API: Called by PortableLamp when the Entity destroys the cable
## on the 3rd strike. Clears the internal _active_cable reference and
## resets the interaction state back to AVAILABLE so the player can
## forge a fresh connection from scratch using a new Cable Spool.
func on_cable_destroyed() -> void:
	_active_cable = null
	print("[GeneratorOutlet] Cable destroyed by Entity! Outlet reset to AVAILABLE. Player must reconnect from scratch.")


func get_interact_text() -> String:
	if _active_cable:
		return "[E] Disconnect Cable"
	if not _player_has_cable_spool() and not _player_has_portable_light():
		return ""
	# If the player has a cable spool but no portable light, still allow the
	# legacy cable-only connection.
	if _player_has_cable_spool() and not _player_has_portable_light():
		return "[E] Connect Power Cable"
	# If the player has both, show the auto-connect prompt.
	if _player_has_cable_spool() and _player_has_portable_light():
		return "[E] Connect Portable Light + Cable"
	# Fallback: has the lamp but no cable — need a cable spool.
	return "Needs a cable spool"