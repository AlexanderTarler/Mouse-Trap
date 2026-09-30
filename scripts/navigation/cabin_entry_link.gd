class_name CabinEntryLink
extends NavigationLink3D

## A navigation link across one cabin entry point (the front door or a window).
##
## The yard and the cabin interior are separate navigation regions that never
## touch (the interior region has use_edge_connections = false and the
## exterior bake is carved around the cabin footprint). These links are the
## ONLY way a path can cross between them, and each one is enabled only while
## its entry is physically passable:
##   - Door:   enabled while the door is unlocked.
##   - Window: enabled while the glass is shattered and no planks remain.
##
## Pathfinding therefore can never route the Entity through a locked door or
## an intact window. Deciding WHETHER to go inside is the AI's job; the links
## only describe where it is possible.
##
## When a NavigationAgent3D reaches a link it emits link_reached with
## details["owner"] set to this node, so the AI can read `kind` and `entry`
## to play the door-open or vault animation.

enum Kind { DOOR, WINDOW }

const GROUP := &"cabin_entry_links"

## How far above/below a marker to search for the floor when projecting the
## link endpoints onto walkable ground (markers are often placed at window
## height, too far above the floor for the navmesh to connect them).
const FLOOR_PROBE_UP := 0.5
const FLOOR_PROBE_DOWN := 4.0
const FLOOR_OFFSET := 0.1

var kind: Kind = Kind.WINDOW
## An upstairs window: the Entity climbs the wall from start_position (the
## ground below) to cling outside it, then vaults in to end_position.
var climb := false
## The Door or CabinWindow that owns this link.
var entry: Node3D = null


## Creates a link owned by `entry_node`, spanning from `outside` to `inside`.
## Endpoints are captured once, in world space, so they don't move when a door
## swings open. Creation is deferred one physics frame so the floor raycast
## sees every collider.
static func create(entry_node: Node3D, link_kind: Kind, outside: Node3D, inside: Node3D, start_enabled: bool) -> CabinEntryLink:
	var link := CabinEntryLink.new()
	link.name = "EntryNavLink"
	link.kind = link_kind
	link.entry = entry_node
	link.bidirectional = true
	link.enabled = start_enabled
	# World-space endpoints: a top-level node with an identity transform.
	link.top_level = true
	entry_node.add_child(link)
	link.global_transform = Transform3D.IDENTITY
	link._place_endpoints.call_deferred(outside.global_position, inside.global_position)
	return link


func _ready() -> void:
	add_to_group(GROUP)


func _place_endpoints(outside_pos: Vector3, inside_pos: Vector3) -> void:
	await get_tree().physics_frame
	start_position = _project_to_floor(outside_pos)
	end_position = _project_to_floor(inside_pos)


func _project_to_floor(pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		pos + Vector3.UP * FLOOR_PROBE_UP, pos + Vector3.DOWN * FLOOR_PROBE_DOWN)
	# Layer 1: world/cabin geometry only, so the Entity or player can't be hit.
	query.collision_mask = 1
	var exclude: Array[RID] = []
	if entry is CollisionObject3D:
		exclude.append((entry as CollisionObject3D).get_rid())
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		push_warning("CabinEntryLink on '%s': no floor found below %s; using marker height." % [entry.name, pos])
		return pos
	return hit.position + Vector3.UP * FLOOR_OFFSET
