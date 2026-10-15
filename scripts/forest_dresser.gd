class_name ForestDresser
extends RefCounted
## Turns each tree group (trees.tscn) into its own patch of forest. The map is
## 147 copies of one group, so the same layout of identical pines repeated
## everywhere; now every group is varied by a seed from its position:
##   - every pine keeps its spot (and its collider), but becomes a random pine
##     of one of three colourings, its own size, turn and a slight lean;
##     some become dead trees or autumn broadleaves;
##   - undergrowth grows around the trunks (shrubs, mushrooms at the roots,
##     pebbles, saplings), kept off the walking paths (TerrainMask) and clear
##     of the cabin, the road, the totem and anything the player interacts
##     with.
##   - so are the gravel road (GravelRoad) and the barn yard's fence line
##     (FENCE_LINES): no trunk on the road or through a fence, no shrub on them.
##   - the walking paths are kept clear: trees standing on one are removed
##     with their colliders (rebake the navmesh to drop their holes), and the
##     group's own ferns, grass, rocks and logs on or next to one are dropped.
## Nothing it adds has a collider, so navigation and sight lines are as before.
## Used by FoliageBatcher (dress_forest) before the forest is batched.

const GLB := "res://assets/PSX Nature/Models/GLB/"
## The pines in trees.tscn, and the colourings they become (same shapes).
const PINE_SOURCE := "pine_tree_n_1"
const PINE_FAMILIES := ["pine_tree_n_1", "pine_tree_n_2", "pine_tree_n_3"]
const PINE_FAMILY_WEIGHTS := [0.4, 0.35, 0.25]
const DEAD_TREE_CHANCE := 0.07
const DEAD_TREES := ["tree_8", "tree_9"]
## Rare: their canopies hang at head height.
const BROADLEAF_CHANCE := 0.04
const BROADLEAVES := ["tree_5", "tree_6"]
## A Swedish forest is pine with birch through it: birches here and there,
## more of them by the road and at the edges of clearings (where the light
## is). (No autumn birches: it's spring, the end of April.)
const MEADOWS := "res://assets/PSX Forest Meadows by VadaCross/3D Models/"
const BIRCH := MEADOWS + "Birch Tree/Birch Tree.fbx"
const BIRCH_CHANCE := 0.09
## Within this of the road, or on clearing paint, birches are this likely.
const BIRCH_EDGE_DISTANCE := 9.0
const BIRCH_EDGE_CHANCE := 0.3
## The models are not all made to one scale: this brings each to a mature
## tree's height (the pines are ~10 m; the birch model is 5.8 m): [across,
## up]. Less across than up, or the trunk swells with the height (a birch
## is tall and slender).
const TREE_MODEL_SCALE := {BIRCH: Vector2(1.1, 1.8)}
const TREE_SCALE := Vector2(0.88, 1.18)
const TREE_LEAN_DEGREES := 2.5

## Around each tree: [model, chance, min distance, max distance, min scale,
## max scale]. Nothing big (it has no collider): the boulders stay out.
const UNDERGROWTH := [
	["fern_1", 0.6, 1.0, 4.5, 0.8, 1.4],    # green shrub
	["fern_3", 0.3, 1.2, 4.5, 0.7, 1.1],    # bare twigs
	["fern_2", 0.06, 1.5, 4.5, 0.8, 1.2],   # red-flowering shrub, now and then
	["mushroom_n_1", 0.2, 0.45, 1.1, 1.0, 1.8],
	["mushroom_n_2", 0.15, 0.45, 1.1, 1.0, 1.8],
	["mushroom_n_3", 0.12, 0.45, 1.3, 1.5, 2.5],
	["mushroom_n_4", 0.12, 0.45, 1.3, 1.2, 2.0],
	["stone_5", 0.25, 1.0, 5.0, 1.0, 2.2],  # pebbles
	["tree_1", 0.05, 2.5, 5.5, 0.6, 0.9],   # sapling
	# Head height, between the ferns and the crowns: young pines (tree_7 is
	# an 8 m pine, here 3.5-6 m), so the eye doesn't run straight through
	# the trunks to the edge of the map. Drawn as small things are (no
	# shadow, gone beyond FoliageBatcher.SMALL_DRAW_DISTANCE): SMALL_MODELS.
	["tree_7", 0.09, 2.5, 6.0, 0.42, 0.72],
	# The forest floor: real ferns, fallen branches and now and then a fallen
	# trunk (no stumps: the nests are the stumps).
	[MEADOWS + "Fern/Fern.fbx", 0.2, 0.8, 4.5, 0.7, 1.2],
	["res://assets/Fixed .fbx/SM_EC_Tree_Part_Cross_00.tscn", 0.12, 0.8, 4.5, 0.9, 1.6],
	["tree_log_1", 0.025, 2.0, 5.0, 0.8, 1.1],
]
## Models batched as small whatever their size (FoliageBatcher.draw_as_small).
const SMALL_MODELS := ["tree_7"]

## Kept clear: [centre, radius]. The cabin and its yard, the totem's clearing.
const CLEAR_ZONES := [
	[Vector3(9.0, 0.0, 14.0), 15.0],
	[Vector3(103.0, 0.0, 85.3), 12.0],
]
## The barn yard's fence (cottage_horror.tscn "Barn Fence"), post line to
## post line: trees closer than FENCE_TREE_CLEARANCE go, undergrowth keeps
## FENCE_CLEARANCE away.
const FENCE_LINES := [
	[Vector2(11.2, -86.9), Vector2(62.26, -86.9)],
	[Vector2(62.26, -86.9), Vector2(62.26, -60.12)],
	[Vector2(62.26, -60.12), Vector2(11.2, -60.12)],
	[Vector2(11.2, -60.12), Vector2(11.2, -86.9)],
]
const FENCE_TREE_CLEARANCE := 1.1
const FENCE_CLEARANCE := 0.8
## Trees closer than this to the gravel road's edge go (GravelRoad), and
## undergrowth keeps ROAD_CLEARANCE off it; and around interactable things (m).
const ROAD_TREE_CLEARANCE := 1.2
const ROAD_CLEARANCE := 1.0
const INTERACTABLE_CLEARANCE := 2.5

## model name -> Array of [Mesh, local Transform3D]
## A tree trunk on this much path paint (or more) is in the way and goes.
const TREE_ON_PATH := 0.3

static var _models := {}
## Where undergrowth was placed and how many trees were cleared off paths
## (for the tests).
static var undergrowth_spots := PackedVector3Array()
static var trees_cleared := 0
static var _interactables: Array[Vector3] = []
static var _interactables_frame := -1


## Dresses `group`, handing every mesh to draw to add(mesh, transform).
## Returns the group's MeshInstance3Ds it replaced (the caller drops them).
static func dress(group: Node3D, add: Callable) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(group.global_position.round()))
	refresh_interactables(group)
	var replaced := {}
	var colliders := _tree_colliders(group)
	for node in group.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var source := mesh_instance.mesh.resource_path.get_file() if mesh_instance.mesh else ""
		var at := mesh_instance.global_position
		if not source.begins_with(PINE_SOURCE):
			# The group's own small things: off the paths.
			if mesh_instance.mesh and (TerrainMask.near_path(at, 0.6) or near_fence(at, FENCE_CLEARANCE)
				or GravelRoad.covers(at, ROAD_CLEARANCE)):
				replaced[mesh_instance] = true
			continue
		replaced[mesh_instance] = true
		if TerrainMask.path(at) >= TREE_ON_PATH or near_fence(at, FENCE_TREE_CLEARANCE) 				or GravelRoad.covers(at, ROAD_TREE_CLEARANCE):
			_remove_collider_near(colliders, at)
			trees_cleared += 1
			continue
		var base := mesh_instance.global_transform
		var model := _tree_model(rng, source, at)
		var lean := Basis(Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized(),
			deg_to_rad(rng.randf_range(0.0, TREE_LEAN_DEGREES)))
		var size := rng.randf_range(TREE_SCALE.x, TREE_SCALE.y)
		var model_scale: Vector2 = TREE_MODEL_SCALE.get(model, Vector2.ONE)
		var basis := lean * Basis(Vector3.UP, rng.randf() * TAU) 			* Basis.from_scale(Vector3(model_scale.x, model_scale.y, model_scale.x) * size)
		_emit(model, Transform3D(basis, base.origin), add)
		_undergrowth(rng, base.origin, add)
	return replaced


## The group's tree trunk colliders: [CollisionShape3D, position].
static func _tree_colliders(group: Node3D) -> Array:
	var found := []
	for body in group.get_children():
		if body is StaticBody3D:
			for shape in body.get_children():
				if shape is CollisionShape3D:
					found.append([shape, (shape as Node3D).global_position])
	return found


## Whether `spot` is within `margin` (m) of the barn yard's fence.
static func near_fence(spot: Vector3, margin: float) -> bool:
	var at := Vector2(spot.x, spot.z)
	for line in FENCE_LINES:
		if at.distance_to(Geometry2D.get_closest_point_to_segment(at, line[0], line[1])) < margin:
			return true
	return false


## Turns off the trunk collider standing at `at` (the tree is gone).
static func _remove_collider_near(colliders: Array, at: Vector3) -> void:
	var best := -1
	var best_distance := 1.0
	for i in colliders.size():
		var d := Vector2(colliders[i][1].x - at.x, colliders[i][1].z - at.z).length()
		if d < best_distance:
			best_distance = d
			best = i
	if best >= 0:
		(colliders[best][0] as CollisionShape3D).set_deferred("disabled", true)


## The tree a pine at `at` becomes: mostly a pine of a random colouring
## (same size variant: pine_tree_n_1_3 -> pine_tree_n_2_3), some birches
## (more by the road and clearings), the other pine shape, sometimes a dead
## tree or an autumn broadleaf.
static func _tree_model(rng: RandomNumberGenerator, source: String, at: Vector3) -> String:
	var roll := rng.randf()
	if roll < DEAD_TREE_CHANCE:
		return DEAD_TREES[rng.randi() % DEAD_TREES.size()]
	roll -= DEAD_TREE_CHANCE
	if roll < BROADLEAF_CHANCE:
		return BROADLEAVES[rng.randi() % BROADLEAVES.size()]
	roll -= BROADLEAF_CHANCE
	var edge := GravelRoad.covers(at, BIRCH_EDGE_DISTANCE) or TerrainMask.sample(at).r > 0.4
	var birch := BIRCH_EDGE_CHANCE if edge else BIRCH_CHANCE
	if roll < birch:
		return BIRCH
	var size_variant := source.get_basename().trim_prefix(PINE_SOURCE)
	var pick := rng.randf()
	var family: String = PINE_FAMILIES[0]
	for i in PINE_FAMILIES.size():
		pick -= PINE_FAMILY_WEIGHTS[i]
		if pick <= 0.0:
			family = PINE_FAMILIES[i]
			break
	return family + size_variant


static func _undergrowth(rng: RandomNumberGenerator, at: Vector3, add: Callable) -> void:
	for entry in UNDERGROWTH:
		if rng.randf() >= entry[1]:
			continue
		var angle := rng.randf() * TAU
		var spot: Vector3 = at + Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(entry[2], entry[3])
		if not clear(spot):
			continue
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * rng.randf_range(entry[4], entry[5]))
		_emit(entry[0], Transform3D(basis, spot), add)
		undergrowth_spots.append(spot)


## False where nothing should grow (the walking paths, the cabin, the totem,
## the road, next to interactable things).
static func clear(spot: Vector3) -> bool:
	if TerrainMask.near_path(spot) or near_fence(spot, FENCE_CLEARANCE):
		return false
	for zone in CLEAR_ZONES:
		if Vector2(spot.x - zone[0].x, spot.z - zone[0].z).length() < zone[1]:
			return false
	if GravelRoad.covers(spot, ROAD_CLEARANCE):
		return false
	for point in _interactables:
		if Vector2(spot.x - point.x, spot.z - point.z).length() < INTERACTABLE_CLEARANCE:
			return false
	return true


static func refresh_interactables(node: Node) -> void:
	var frame := Engine.get_process_frames()
	if frame == _interactables_frame:
		return
	_interactables_frame = frame
	_interactables.clear()
	for group_name in ["interactable", "pickup", "scrap_heap"]:
		for thing in node.get_tree().get_nodes_in_group(group_name):
			if thing is Node3D:
				_interactables.append((thing as Node3D).global_position)
	# The nests.
	var scene := node.get_tree().current_scene
	var nests := scene.get_node_or_null("NestLocations") if scene else null
	if nests:
		for nest in nests.get_children():
			if nest is Node3D:
				_interactables.append((nest as Node3D).global_position)


static func _emit(model: String, xform: Transform3D, add: Callable) -> void:
	for part in model_parts(model):
		add.call(part[0], xform * part[1])


## The meshes of a model (and where they sit inside it), loaded once. A
## name is a PSX Nature model; a res:// path any scene.
static func model_parts(model: String) -> Array:
	if _models.has(model):
		return _models[model]
	var parts := []
	var path := model if model.begins_with("res://") else GLB + model + ".glb"
	if ResourceLoader.exists(path):
		var root := (load(path) as PackedScene).instantiate() as Node3D
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh:
				var local := Transform3D.IDENTITY
				var walk: Node = mesh_instance
				while walk and walk != root:
					local = (walk as Node3D).transform * local if walk is Node3D else local
					walk = walk.get_parent()
				# The model's own root may be scaled or turned (FBX imports).
				local = Transform3D(root.basis, Vector3.ZERO) * local
				parts.append([mesh_instance.mesh, local])
				if model in SMALL_MODELS:
					FoliageBatcher.draw_as_small(mesh_instance.mesh)
		root.free()
	else:
		push_warning("ForestDresser: missing model %s" % path)
	_models[model] = parts
	return parts
