extends Area3D
class_name GeneratorOutlet

## GeneratorOutlet — Cable connection point on the generator.
##
## This is a multi-step interaction:
##   1. Player must have a "Cable Spool" item in inventory.
##   2. Player interacts with this outlet → spawns a PowerCable instance,
##      sets state to PLUGGED_TO_SOURCE, attaches the free end to the
##      player's hand marker.
##   3. Player carries the free end to a deployed PortableLamp and interacts
##      with its base → cable state becomes FULLY_CONNECTED.
##
## The outlet node should be added to the "generator_outlet" group so the
## PowerCable can auto-find it at runtime.

## Reference to the active PowerCable instance (if one has been spawned).
var _active_cable: Node = null

## Preload the PowerCable scene so we can instantiate it.
const POWER_CABLE_SCENE: PackedScene = preload("res://scenes/power_cable.tscn")


func _ready() -> void:
	# Ensure this Area3D can be detected by the interaction manager's raycast
	collision_layer = 1
	# Add to the generator_outlet group so PowerCable can auto-find us
	add_to_group("generator_outlet")


func interact() -> void:
	# ─── CHECK IF CABLE IS ALREADY CONNECTED ─────────────────────────────
	if _active_cable:
		print("[GeneratorOutlet] Cable already connected! Disconnect it first.")
		return
	
	# ─── CHECK IF PLAYER HAS CABLE SPOOL ─────────────────────────────────
	if not _player_has_cable_spool():
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
	
	print("[GeneratorOutlet] Cable plugged in! Drag the free end to a lamp.")


## Checks if the player has a Cable Spool in their inventory.
func _player_has_cable_spool() -> bool:
	for item in Inventory.items:
		if item != null and "item_name" in item and item.item_name == "Cable Spool":
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


func get_interact_text() -> String:
	if _active_cable:
		return "[E] Disconnect Cable"
	return "[E] Connect Power Cable"
