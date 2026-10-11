@tool
class_name GravelRoad
extends Node3D
## The gravel road the player drove in on and drives out on in the endings:
## from a pull-in by the parked van, east along the south of the map, then
## curving south to the "road_ending" marker at the map's edge. A flat strip
## laid on the (flat) ground, built here from its centre line; the look is
## shaders/gravel_road.gdshader. Built in the editor too (@tool), as an
## internal child that isn't saved with the scene.
##
## The bend was routed between the trees (fewest in the way, the rest are
## cleared by ForestDresser via covers()), wide and gentle enough to drive:
## no tighter than a 14 m radius. The escape cinematics drive along it
## (sample(), project()).

## Centre line, west to east (x, z). The last point is the "road_ending"
## marker in cottage_horror.tscn (move both together).
const CENTRE_LINE := [
	Vector2(-24.0, -90.6), Vector2(-12.0, -90.4), Vector2(0.0, -90.9), Vector2(14.0, -91.4),
	Vector2(30.0, -91.0), Vector2(46.0, -90.6), Vector2(62.0, -91.1), Vector2(66.9, -90.5),
	Vector2(95.0, -91.6), Vector2(105.3, -103.5), Vector2(104.58, -118.79),
]
const WIDTH := 5.0
## Wider by the van, where it was pulled in and turned (x from, to).
const PULL_IN := Vector2(-22.0, -2.0)
const PULL_IN_WIDTH := 7.5
## Just above the ground (y 0.0274 there), clear of z-fighting.
const HEIGHT := 0.045
const STEP := 1.0
const TEXTURE := "res://assets/PSX Mega Pack II/Textures/gravel_hr_1.png"
const SHADER := "res://shaders/gravel_road.gdshader"

static var _line := PackedVector2Array()
static var _along := PackedFloat32Array()

var _mesh: MeshInstance3D = null


func _ready() -> void:
	if _mesh:
		_mesh.queue_free()
	_mesh = MeshInstance3D.new()
	_mesh.name = "RoadMesh"
	_mesh.mesh = _build_mesh()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = load(SHADER)
	if ResourceLoader.exists(TEXTURE):
		material.set_shader_parameter("gravel", load(TEXTURE))
	material.set_shader_parameter("road_length", length())
	_mesh.material_override = material
	# Internal: rebuilt on load, never written into the scene file.
	add_child(_mesh, false, Node.INTERNAL_MODE_FRONT)


## The road's width at `x` (wider at the pull-in, eased).
static func width_at(x: float) -> float:
	var ease_in := smoothstep(PULL_IN.x - 6.0, PULL_IN.x, x) * (1.0 - smoothstep(PULL_IN.y, PULL_IN.y + 8.0, x))
	return lerpf(WIDTH, PULL_IN_WIDTH, ease_in)


## Smooth centre line (Catmull-Rom through CENTRE_LINE), every STEP metres.
static func centre_points() -> PackedVector2Array:
	if not _line.is_empty():
		return _line
	var pts := CENTRE_LINE
	for i in pts.size() - 1:
		var p0: Vector2 = pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, pts.size() - 1)]
		var steps := maxi(int(p1.distance_to(p2) / STEP), 1)
		for s in steps:
			var t := float(s) / steps
			var t2 := t * t
			var t3 := t2 * t
			_line.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	_line.append(pts[pts.size() - 1])
	var total := 0.0
	for i in _line.size():
		if i > 0:
			total += _line[i].distance_to(_line[i - 1])
		_along.append(total)
	return _line


## The road's length along its centre line (m).
static func length() -> float:
	centre_points()
	return _along[_along.size() - 1]


## Distance (m) from `point` to the road's centre line, flat.
static func distance_to(point: Vector3) -> float:
	var at := Vector2(point.x, point.z)
	var line := centre_points()
	var best := INF
	for i in line.size() - 1:
		best = minf(best, at.distance_to(Geometry2D.get_closest_point_to_segment(at, line[i], line[i + 1])))
	return best


## Whether `point` is on the road (with `margin` m to spare).
static func covers(point: Vector3, margin: float = 0.0) -> bool:
	return distance_to(point) < width_at(point.x) * 0.5 + margin


## How far along the road (m) the closest point to `point` is.
static func project(point: Vector3) -> float:
	var at := Vector2(point.x, point.z)
	var line := centre_points()
	var best := INF
	var best_along := 0.0
	for i in line.size() - 1:
		var on := Geometry2D.get_closest_point_to_segment(at, line[i], line[i + 1])
		var d := at.distance_to(on)
		if d < best:
			best = d
			best_along = _along[i] + line[i].distance_to(on)
	return best_along


## The centre line `distance` m along the road: {"position": Vector2 (x, z),
## "direction": Vector2}. Past the end it carries straight on.
static func sample(distance: float) -> Dictionary:
	var line := centre_points()
	var last := line.size() - 1
	if distance >= _along[last]:
		var dir := (line[last] - line[last - 1]).normalized()
		return {"position": line[last] + dir * (distance - _along[last]), "direction": dir}
	distance = maxf(distance, 0.0)
	var i := 0
	while i < last - 1 and _along[i + 1] < distance:
		i += 1
	var span := maxf(_along[i + 1] - _along[i], 0.0001)
	var t := (distance - _along[i]) / span
	return {"position": line[i].lerp(line[i + 1], t), "direction": (line[i + 1] - line[i]).normalized()}


func _build_mesh() -> ArrayMesh:
	var line := centre_points()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in line.size():
		var here: Vector2 = line[i]
		var dir: Vector2 = (line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-dir.y, dir.x) * width_at(here.x) * 0.5
		for k in 2:
			var p := here + (side if k == 0 else -side)
			verts.append(Vector3(p.x, HEIGHT, p.y))
			uvs.append(Vector2(_along[i], -1.0 if k == 0 else 1.0))
			normals.append(Vector3.UP)
		if i > 0:
			var a := (i - 1) * 2
			var b := i * 2
			indices.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built
