extends Node

## RoomLightDetector — Global singleton for position-based lit-room queries.
##
## This autoload (singleton) provides the central API for determining whether
## any given world position is inside a lit room. It is the Layer 3 component
## of the Light Detection System.
##
## HOW IT WORKS:
##   Scans all Area3D nodes in the "Cabin_Interior" group. Each area should
##   have the CabinRoom script attached, which provides a direct reference to
##   the room's CabinLight. The detector checks if a given position overlaps
##   any CabinRoom area, and if so, queries that room's CabinLight.is_room_lit().
##
## USAGE:
##   RoomLightDetector.is_position_in_lit_room(some_position)
##   RoomLightDetector.is_player_in_lit_room()
##   RoomLightDetector.is_entity_in_lit_room()
##   RoomLightDetector.get_lit_room_at(some_position)
##
## SETUP IN PROJECT SETTINGS:
##   Add this script as an autoload in Project → Project Settings → Autoload:
##     Path: res://scripts/room_light_detector.gd
##     Name: RoomLightDetector
##
## SETUP IN THE SCENE EDITOR:
##   1. For each room in the cabin, create an Area3D node.
##   2. Attach the CabinRoom script (cabin_room.gd) to it.
##   3. Add a CollisionShape3D child that covers the room's volume.
##   4. In the Inspector, drag the corresponding CabinLight into the
##      "Room Light" export field.
##   5. Add the Area3D to the "Cabin_Interior" group.
##
## PERFORMANCE:
##   Queries scan all Cabin_Interior areas (typically 6-8 rooms) using
##   Area3D.overlaps_body() or PhysicsPointQuery. This is negligible —
##   no caching is needed.

## Cache of all CabinRoom nodes found in the scene tree.
## Populated lazily on first query and refreshed if empty.
## NOTE: Uses Array[Node] instead of Array[CabinRoom] to avoid parse-time
## type resolution issues with autoloads. CabinRoom is a class_name that
## may not be available when this autoload is parsed.
var _cabin_rooms: Array[Node] = []


## Internal: Refreshes the cached list of CabinRoom nodes.
## Called automatically when the cache is empty.
func _refresh_cabin_rooms() -> void:
	_cabin_rooms.clear()
	var interiors = get_tree().get_nodes_in_group("Cabin_Interior")
	for area in interiors:
		if area is Area3D and area.has_method("is_lit"):
			_cabin_rooms.append(area)


## Returns the CabinRoom (as Node) that contains the given world position,
## or null if the position is not inside any registered room (i.e., outside).
func get_room_at(position: Vector3) -> Node:
	if _cabin_rooms.is_empty():
		_refresh_cabin_rooms()
	
	for room in _cabin_rooms:
		if room and room.has_method("contains_point") and room.contains_point(position):
			return room
	
	return null


## Returns true if the given world position is inside a lit room.
## A room is "lit" when BOTH:
##   - The room's CabinLight is switched ON
##   - The generator is running (has power)
##
## Returns false if the position is outside or in a dark room.
func is_position_in_lit_room(position: Vector3) -> bool:
	var room := get_room_at(position)
	if room and room.has_method("is_lit"):
		return room.is_lit()
	return false


## Returns true if the player is currently in a lit room.
## Uses the player's global position to check room containment.
## Returns false if the player is outside or in a dark room.
func is_player_in_lit_room() -> bool:
	var player := _get_player()
	if not player:
		return false
	return is_position_in_lit_room(player.global_position)


## Returns true if the Entity is currently in a lit room.
## Uses the Entity's global position to check room containment.
## Returns false if the Entity is outside or in a dark room.
func is_entity_in_lit_room() -> bool:
	var entity := _get_entity()
	if not entity:
		return false
	return is_position_in_lit_room(entity.global_position)


## Returns the name of the room at the given position regardless of lighting,
## or "Outside" if the position is not inside any registered room.
func get_room_name_at(position: Vector3) -> String:
	var room := get_room_at(position)
	if room and room.has_method("get_room_name"):
		return room.get_room_name()
	return "Outside"


## Returns the CabinLight associated with the room at the given position,
## or null if the position is outside or the room has no light assigned.
func get_light_at(position: Vector3) -> Node:
	var room := get_room_at(position)
	if room and "room_light" in room:
		return room.room_light
	return null


## ─── INTERNAL HELPERS ────────────────────────────────────────────────────────

func _get_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node3D


func _get_entity() -> Node3D:
	var entities := get_tree().get_nodes_in_group("entity")
	if entities.is_empty():
		return null
	return entities[0] as Node3D


## ─── DEBUG ───────────────────────────────────────────────────────────────────
