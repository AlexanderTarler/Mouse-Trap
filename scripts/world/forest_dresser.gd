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
	# The forest floor: real ferns and fallen branches (no stumps: the nests
	# are the stumps; no logs: these have no collider, the trails' do).
	[MEADOWS + "Fern/Fern.fbx", 0.2, 0.8, 4.5, 0.7, 1.2],
	["res://assets/Fixed .fbx/SM_EC_Tree_Part_Cross_00.tscn", 0.12, 0.8, 4.5, 0.9, 1.6],
]
## Models batched as small whatever their size (FoliageBatcher.draw_as_small).
const SMALL_MODELS := ["tree_7"]

## The forest the logging camp cut in 1974, east of the barn (its last
## season: Lore): where the pines stood, their stumps (the trunk's collider
## shrunk to the stump), and what has grown up in 25 years, young pine and
## birch, and ferns. [centre, radius]; the edge is ragged by CLEARCUT_EDGE m.
const CLEARCUT := [Vector3(88.0, 0.0, -92.0), 13.0]
const CLEARCUT_EDGE := 3.0
const CLEARCUT_STUMP_SCALE := Vector2(1.3, 1.7)
## Per stump: up to this many young trees beside it, each this likely
## (young pine, else birch: birch is first back after a cut).
const CLEARCUT_REGROWTH := [2, 0.7]
const CLEARCUT_YOUNG_PINE := 0.45
## The stumps don't stand where the old rows were planted to the metre.
const CLEARCUT_JITTER := 0.8

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
## The forest is baked ahead of time (ForestBake, tools/bake_forest.gd), and
## the bake is only used while these settings are the ones it was made with.
## Changed how the dressing works without changing a setting? Raise this, and
## bake again.
const BAKE_VERSION := 2


## Every setting the dressing uses (ForestBake's check).
static func settings() -> Array:
	return [GLB, PINE_SOURCE, PINE_FAMILIES, PINE_FAMILY_WEIGHTS, DEAD_TREE_CHANCE, DEAD_TREES,
		BROADLEAF_CHANCE, BROADLEAVES, BIRCH, BIRCH_CHANCE, BIRCH_EDGE_DISTANCE, BIRCH_EDGE_CHANCE,
		TREE_MODEL_SCALE, TREE_SCALE, TREE_LEAN_DEGREES, UNDERGROWTH, SMALL_MODELS, CLEARCUT,
		CLEARCUT_EDGE, CLEARCUT_STUMP_SCALE, CLEARCUT_REGROWTH, CLEARCUT_YOUNG_PINE, CLEARCUT_JITTER,
		CLEAR_ZONES, FENCE_LINES, FENCE_TREE_CLEARANCE, FENCE_CLEARANCE, ROAD_TREE_CLEARANCE,
		ROAD_CLEARANCE, INTERACTABLE_CLEARANCE, TREE_ON_PATH, STONE_TRUNK_CLEARANCE, TRUNK_CELL, TRUNK_RADIUS]

static var _models := {}
## Where undergrowth was placed and how many trees were cleared off paths
## (for the tests).
static var undergrowth_spots := PackedVector3Array()
## The stones placed, (x, y, z, scale) (for the tests).
static var stone_spots: Array[Vector4] = []
static var trees_cleared := 0
## The clear-cut's stumps (for the tests).
static var clearcut_stumps := PackedVector3Array()
static var _interactables: Array[Vector3] = []
static var _interactables_frame := -1


## Dresses `group`, handing every mesh to draw to add(mesh, transform).
## Returns the group's MeshInstance3Ds it replaced (the caller drops them).
static func dress(group: Node3D, add: Callable) -> Dictionary:
	var nodes := group.find_children("*", "MeshInstance3D", true, false)
	var placed := []
	for node in nodes:
		placed.append([(node as MeshInstance3D).mesh, (node as MeshInstance3D).global_transform])
	var replaced := {}
	for i in dress_list(group, placed, add):
		replaced[nodes[i]] = true
	return replaced


## dress() for a list of the group's meshes ([mesh, transform] each, in the
## group's order): the indices of those it replaces.
static func dress_list(group: Node3D, placed: Array, add: Callable) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(group.global_position.round()))
	refresh_interactables(group)
	var replaced := {}
	var colliders := _tree_colliders(group)
	for index in placed.size():
		var mesh: Mesh = placed[index][0]
		var global_xform: Transform3D = placed[index][1]
		var source := mesh.resource_path.get_file() if mesh else ""
		var at := global_xform.origin
		if not source.begins_with(PINE_SOURCE):
			# The group's own small things: off the paths.
			if mesh and (TerrainMask.near_path(at, 0.6) or near_fence(at, FENCE_CLEARANCE)
				or GravelRoad.covers(at, ROAD_CLEARANCE)):
				replaced[index] = true
			elif mesh and _rock_through_trunk(mesh, global_xform, colliders):
				replaced[index] = true
				rocks_cleared += 1
			continue
		replaced[index] = true
		if TerrainMask.path(at) >= TREE_ON_PATH or near_fence(at, FENCE_TREE_CLEARANCE) 				or GravelRoad.covers(at, ROAD_TREE_CLEARANCE):
			_remove_collider_near(colliders, at)
			trees_cleared += 1
			continue
		# (After the road and the paths: no stump left on either.)
		if in_clearcut(at):
			_cut(rng, global_xform.origin, colliders, add)
			continue
		var base := global_xform
		var model := _tree_model(rng, source, at)
		var lean := Basis(Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized(),
			deg_to_rad(rng.randf_range(0.0, TREE_LEAN_DEGREES)))
		var size := rng.randf_range(TREE_SCALE.x, TREE_SCALE.y)
		var model_scale: Vector2 = TREE_MODEL_SCALE.get(model, Vector2.ONE)
		var basis := lean * Basis(Vector3.UP, rng.randf() * TAU) 			* Basis.from_scale(Vector3(model_scale.x, model_scale.y, model_scale.x) * size)
		_emit(model, Transform3D(basis, base.origin), add)
		_undergrowth(rng, base.origin, add)
	return replaced


## The group's own big rocks: one whose footprint reaches a trunk (they were
## set by the original pines; the trees that grow there now are their own
## size and lean) goes. How far a trunk reaches (m).
const TRUNK_RADIUS := 0.45
static var rocks_cleared := 0


static func _rock_through_trunk(mesh: Mesh, xform: Transform3D, colliders: Array) -> bool:
	var name := (mesh.resource_path + " " + mesh.resource_name).to_lower()
	if not "rock" in name:
		return false
	var box := xform * mesh.get_aabb()
	var centre := box.get_center()
	var reach := maxf(box.size.x, box.size.z) * 0.5 + TRUNK_RADIUS
	for entry in colliders:
		var trunk: Vector3 = entry[1]
		if Vector2(trunk.x - centre.x, trunk.z - centre.z).length() < reach:
			return true
	return false


## A stone this big (its scale) is kept this far (m, per unit of scale) from
## the middle of any trunk.
const STONE_TRUNK_CLEARANCE := 0.75
## Trunk positions by TRUNK_CELL-metre cell (Vector2i -> PackedVector2Array).
static var _trunks := {}
static var _trunks_frame := -1
const TRUNK_CELL := 2.0


## Whether `spot` is within `margin` (m, flat) of a tree trunk of any of the
## forest's groups (gathered once per frame from their trunk colliders).
static func near_trunk(spot: Vector3, margin: float) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and Engine.get_process_frames() != _trunks_frame:
		_trunks_frame = Engine.get_process_frames()
		_trunks.clear()
		for batcher in tree.root.find_children("*", "FoliageBatcher", true, false):
			for entry in _tree_colliders(batcher):
				# (A tree that was taken away keeps its collider, turned off.)
				if (entry[0] as CollisionShape3D).disabled:
					continue
				var at: Vector3 = entry[1]
				var cell := Vector2i(floori(at.x / TRUNK_CELL), floori(at.z / TRUNK_CELL))
				if not _trunks.has(cell):
					_trunks[cell] = PackedVector2Array()
				_trunks[cell].append(Vector2(at.x, at.z))
	var flat := Vector2(spot.x, spot.z)
	var reach := ceili(margin / TRUNK_CELL)
	var home := Vector2i(floori(spot.x / TRUNK_CELL), floori(spot.z / TRUNK_CELL))
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for trunk in _trunks.get(home + Vector2i(dx, dz), PackedVector2Array()):
				if flat.distance_squared_to(trunk) < margin * margin:
					return true
	return false


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
	var shape := _collider_near(colliders, at)
	if shape:
		shape.set_deferred("disabled", true)


## The trunk collider standing at `at` (or null).
static func _collider_near(colliders: Array, at: Vector3) -> CollisionShape3D:
	var best: CollisionShape3D = null
	var best_distance := 1.0
	for entry in colliders:
		var d := Vector2(entry[1].x - at.x, entry[1].z - at.z).length()
		if d < best_distance:
			best_distance = d
			best = entry[0]
	return best


## Whether `at` is in the 1974 clear-cut (its edge ragged, not a circle).
static func in_clearcut(at: Vector3) -> bool:
	var ragged := (sin(at.x * 0.7) + cos(at.z * 0.9)) * 0.5 * CLEARCUT_EDGE
	return Vector2(at.x - CLEARCUT[0].x, at.z - CLEARCUT[0].z).length() < CLEARCUT[1] + ragged


## The pine at `base` was cut in 1974: a stump (its trunk collider cut down
## to the stump's size; a new shape, the group's is shared), and what grew
## up since.
static func _cut(rng: RandomNumberGenerator, tree_at: Vector3, colliders: Array, add: Callable) -> void:
	var trunk := _collider_near(colliders, tree_at)
	var base := tree_at + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * CLEARCUT_JITTER
	if not clear(base):
		base = tree_at
	var size := rng.randf_range(CLEARCUT_STUMP_SCALE.x, CLEARCUT_STUMP_SCALE.y)
	_emit("tree_stump_1", Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * size),
		base + Vector3.DOWN * 0.05), add)
	clearcut_stumps.append(base)
	if trunk:
		var stump := CylinderShape3D.new()
		stump.radius = 0.4 * size
		stump.height = 0.5 * size
		trunk.shape = stump
		trunk.global_position = base + Vector3.UP * stump.height * 0.5
	for young in CLEARCUT_REGROWTH[0]:
		if rng.randf() >= CLEARCUT_REGROWTH[1]:
			continue
		var angle := rng.randf() * TAU
		var spot := base + Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(1.2, 3.0)
		if clear(spot):
			var turn := Basis(Vector3.UP, rng.randf() * TAU)
			if rng.randf() < CLEARCUT_YOUNG_PINE:
				_emit("tree_7", Transform3D(turn * Basis.from_scale(Vector3.ONE * rng.randf_range(0.5, 0.9)), spot), add)
			else:
				var grown := rng.randf_range(0.8, 1.1)
				_emit(BIRCH, Transform3D(turn * Basis.from_scale(Vector3(0.75, 1.2, 0.75) * grown), spot), add)
	for shrub in [["fern_1", 0.5], ["fern_3", 0.35], [MEADOWS + "Fern/Fern.fbx", 0.3]]:
		if rng.randf() < shrub[1]:
			var angle := rng.randf() * TAU
			var spot := base + Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.8, 3.5)
			if clear(spot):
				_emit(shrub[0], Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * rng.randf_range(0.8, 1.2)), spot), add)


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
		# (Drawn in the same order as always, so the rest of the forest
		# stays where it was.)
		var yaw := rng.randf() * TAU
		var size := rng.randf_range(entry[4], entry[5])
		# Stones are solid: never through a trunk (this group's or the next).
		if String(entry[0]).begins_with("stone") and near_trunk(spot, STONE_TRUNK_CLEARANCE * size):
			continue
		var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * size)
		if String(entry[0]).begins_with("stone"):
			stone_spots.append(Vector4(spot.x, spot.y, spot.z, size))
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
	# The nests. (The level the node is in: the current scene isn't set yet
	# while a level added by hand gets ready.)
	var scene := node.owner if node.owner else node.get_tree().current_scene
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
