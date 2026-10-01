extends OccluderInstance3D
## Lets the renderer skip what the cabin's walls hide (occlusion culling): from
## inside, the forest behind the walls (it was all drawn); from outside, the
## rooms and furniture. Built when the game starts from the cabin's wall
## collision (TwoFloorCollision), which has real openings at every window and
## at the door, so whatever shows through them is still drawn.
##
## Needs Project Settings > Rendering > Occlusion Culling > Use Occlusion
## Culling.

## The collision shape (a ConcavePolygonShape3D) to build the occluder from.
@export var source_path: NodePath = ^"../CollisionShape3D"


func _ready() -> void:
	var source := get_node_or_null(source_path) as CollisionShape3D
	var shape := source.shape as ConcavePolygonShape3D if source else null
	if not shape:
		push_warning("CabinOccluder: no ConcavePolygonShape3D at %s" % source_path)
		return
	var vertices := shape.get_faces()
	var indices := PackedInt32Array()
	indices.resize(vertices.size())
	for i in vertices.size():
		indices[i] = i
	var array_occluder := ArrayOccluder3D.new()
	array_occluder.set_arrays(vertices, indices)
	occluder = array_occluder
	global_transform = source.global_transform
