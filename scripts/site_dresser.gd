class_name SiteDresser
extends Node3D
## The man-made places of the map, furnished: the barn, the wreck yard, the
## tunnel and the willow (the totem's clearing). Built when the level loads
## (WorldDetails adds it), so the level scene itself is left alone.
##
##   - The barn: its doors were drawn shut over solid wall a few metres
##     from its doorway (which stood empty). They're moved onto the doorway
##     and stand open.
##     Inside: racking, hay, a workbench, crates; outside: hay bales, a
##     broken-down Land Rover, firewood, pallets, a utility pole.
##   - The wreck yard: a second container on the first, furniture and white
##     goods dumped around, drums, bricks and gravel, cones, a lamp post, a
##     broken run of chain-link fence.
##   - The tunnel: someone camped inside (mattress, crates, a shelf, a lamp);
##     concrete blocks, wire and junk at the mouth; a pile of pipes.
##   - The willow: a ring of stones around the clearing, stakes with bloody
##     straw, an old fire pit.
##
## Every prop sits on the ground (or on what's under it: stacks stack), gets
## a box collider when it has none, and is skipped if it would crowd
## something the player uses (scrap heaps, pickups, nests) or clip into
## something solid. Walkways and doorways are kept free by where things go. Things already in these places that
## had no collider (drums, traffic barriers) get one. The node is in the
## "navmesh_source" group, so the baked navmesh walks around all of it
## (tools/bake_navmesh.gd).

const F := "res://assets/Fixed .fbx/"
const B := "res://assets/PSX Bunkers/Models/other-formats/GLB/"
const M1 := "res://assets/PSX Mega Pack/Models/GLB (recommended)/"
const M2 := "res://assets/PSX Mega Pack II/Models/GLB (recommended)/"
const N := "res://assets/PSX Nature/Models/GLB/"

## Areas (centre x, z, radius): existing props without colliders in these
## get one.
const AREAS := [
	Vector3(36.8, -74.7, 16.0),   # barn
	Vector3(-84.0, -15.0, 16.0),  # wreck yard
	Vector3(-29.0, 64.0, 14.0),   # tunnel
	Vector3(103.0, 85.3, 13.0),   # willow
]
## Kept free around things the player uses (m, flat).
const INTERACTABLE_CLEARANCE := 1.8
## The totem: nothing within this of it (the trap goes here).
const TOTEM := Vector3(103.0, 0.0, 85.3)
const TOTEM_CLEAR := 5.5

## The barn: its north wall (z), where its door leaves were drawn (x range)
## and where its doorway actually is (x, from its west edge).
const BARN := "SM_EC_Barn_02_Body"
const BARN_NORTH_Z := -82.4
const BARN_DOOR_X := Vector2(35.39, 38.31)
const BARN_DOORWAY_X := Vector2(31.42, 34.34)

## The tunnel: centre, axis (toward the barred end) and across. It's half
## buried and slopes down: there's headroom only from its mouth (along about
## -6.5) to about its middle.
const TUNNEL_C := Vector3(-31.2, 0.0, 65.2)
const TUNNEL_A := Vector3(0.53, 0.0, 0.85)
const TUNNEL_S := Vector3(0.85, 0.0, -0.53)

var placed := 0
var skipped: Array[String] = []
var _space: PhysicsDirectSpaceState3D
var _interactables: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
## The scene's props this added colliders to.
var fixed_colliders := 0
var built := false
var _last_clip := ""
signal finished


func _ready() -> void:
	add_to_group("navmesh_source")
	if Engine.is_editor_hint():
		return
	await get_tree().physics_frame
	build()


func build() -> void:
	_space = get_world_3d().direct_space_state
	_rng.seed = 20261002
	_collect_interactables()
	_fix_barn()
	_add_missing_colliders()
	_dress_barn()
	_dress_yard()
	_dress_tunnel()
	_dress_willow()
	built = true
	print("[SiteDresser] %d props placed, %d skipped, %d existing props given colliders." % [placed, skipped.size(), fixed_colliders])
	finished.emit()


# ─── The places ──────────────────────────────────────────────────────────

func _dress_barn() -> void:
	var inside := {"ray_from": 3.2}
	# Racking along the west wall (the drums by the door stay), a short one
	# further along.
	_put(F + "SM_EC_BarnShelf_3", "z", Vector2(30.5, -76.6), 90.0, inside)
	_put(F + "SM_EC_BarnShelf_0", "z", Vector2(30.5, -70.4), 90.0, inside)
	_put(F + "SM_EC_55L_Drum_03", "z", Vector2(30.1, -80.0), 0.0, inside)
	# Hay along the east wall: big bales with small ones on top, a round bale.
	_put(F + "SM_EC_Hay_2", "z", Vector2(43.3, -80.2), 90.0, inside)
	_put(F + "SM_EC_Hay_2", "z", Vector2(43.3, -77.5), 90.0, inside)
	_put(F + "SM_EC_Hay_0", "z", Vector2(43.4, -80.3), 90.0, inside)
	_put(F + "SM_EC_Hay_1", "z", Vector2(43.4, -77.4), 87.0, inside)
	_put(F + "SM_EC_Hay_0", "z", Vector2(42.7, -74.4), 0.0, inside)
	_put(F + "SM_EC_Hay_4", "z", Vector2(43.4, -72.6), 92.0, inside)
	_put(F + "SM_EC_Hay_Ball_0", "z", Vector2(42.6, -70.2), 0.0, inside)
	# Loose hay on the floor; something bled here.
	for spot in [Vector2(40.6, -79.4), Vector2(31.8, -75.2), Vector2(41.6, -72.4), Vector2(38.2, -76.0)]:
		_put(F + "SM_EC_Hay_Patch_0", "z", spot, _rng.randf_range(0.0, 360.0), {"ray_from": 3.2, "collide": false, "lift": -0.02})
	_put(F + "SM_EC_Horror_Hay_Patch_0", "z", Vector2(35.4, -73.6), 40.0, {"ray_from": 3.2, "collide": false, "lift": -0.02})
	# A workbench by the south wall with odds and ends on it; crates and
	# pallets in the corners.
	_put(B + "table_large_3", "-z", Vector2(31.2, -67.9), 0.0, inside)
	_put(B + "supply_box_1", "-z", Vector2(30.8, -67.9), 12.0, inside)
	_put(B + "lamp_0", "-z", Vector2(31.7, -67.8), 0.0, {"ray_from": 3.2, "collide": false})
	_put(B + "canned_food_3", "-z", Vector2(31.95, -68.05), 0.0, {"ray_from": 3.2, "collide": false})
	_put(B + "wooden_crate_8", "-z", Vector2(40.5, -81.5), 4.0, inside)
	_put(B + "wooden_crate_9", "-z", Vector2(41.7, -81.6), -6.0, inside)
	_put(B + "wooden_crate_8", "-z", Vector2(41.1, -81.55), 20.0, inside)
	_put(B + "wood_pallet_1", "-z", Vector2(43.6, -68.2), 0.0, inside)
	_put(B + "wood_pallet_2", "-z", Vector2(43.6, -68.2), 7.0, inside)

	# Outside. By the doors: pallets and drums on one side, hay on the other.
	_put(B + "wood_pallet_1", "-z", Vector2(28.6, -84.0), 15.0)
	_put(B + "wood_pallet_2", "-z", Vector2(28.6, -84.0), 9.0)
	_put(F + "SM_EC_55L_Drum_10", "z", Vector2(36.6, -83.6), 0.0)
	_put(F + "SM_EC_55L_Drum_03", "z", Vector2(37.3, -84.2), 0.0)
	_put(F + "SM_EC_Hay_2", "z", Vector2(41.8, -84.4), 0.0)
	_put(F + "SM_EC_Hay_Ball_0", "z", Vector2(44.6, -85.2), 70.0)
	# The west side: a Land Rover left to rot, round bales.
	_put(F + "SM_EC_LR90_Broken_Down_00", "z", Vector2(25.4, -76.5), 12.0)
	_put(F + "SM_EC_Hay_Ball_0", "z", Vector2(25.8, -70.6), 85.0)
	_put(F + "SM_EC_Hay_Ball_0", "z", Vector2(25.9, -68.0), 95.0)
	# South: a woodpile, an overgrown crop patch.
	for i in 3:
		_put(N + "tree_log_1", "y", Vector2(32.5 + i * 0.05, -64.8 + i * 0.7), 90.0)
	_put(N + "tree_log_1", "y", Vector2(32.55, -64.45), 92.0)
	for row in 3:
		for col in 4:
			_put(F + "SM_EC_Crop_0", "z", Vector2(40.0 + col * 2.0, -64.6 + row * 1.7), 0.0, {"collide": false, "lift": -0.02})
	# East: an old utility pole.
	_put(F + "SM_EC_WoodenPole_Large_00", "y", Vector2(47.6, -83.4), 0.0, {"scale": Vector3(1.0, 0.6, 1.0)})


func _dress_yard() -> void:
	# A second container dumped on the first, askew.
	_put(F + "SM_EC_ShippingContainer_3", "z", Vector2(-92.4, -13.9), 4.0, {"allow_overlap": true, "on_scene": true})
	# A Land Rover wreck, furniture and white goods.
	_put(F + "SM_EC_LR90_Broken_Down_00", "z", Vector2(-87.6, -23.4), 32.0)
	_put(F + "SM_EC_Cooker_0", "z", Vector2(-86.4, -17.6), 25.0)
	_put(F + "SM_EC_WashingMachine_Complete_0", "z", Vector2(-85.7, -18.6), -15.0)
	_put(F + "SM_EC_Mattress_3", "z", Vector2(-85.8, -20.6), 20.0)
	_put(F + "SM_EC_Sofa_1", "z", Vector2(-88.9, -11.8), 70.0)
	_put(F + "SM_EC_KitchenBin_TrashBag_0", "z", Vector2(-86.6, -12.6), 0.0)
	_put(F + "SM_EC_KitchenBin_TrashBag_0", "z", Vector2(-87.1, -13.3), 50.0)
	# Drums, bricks, gravel, rubble.
	_put(F + "SM_EC_55L_Drum_03", "z", Vector2(-80.8, -9.3), 0.0)
	_put(F + "SM_EC_55L_Drum_10", "z", Vector2(-80.1, -9.9), 0.0)
	_put(F + "SM_EC_55L_Drum_05", "z", Vector2(-81.4, -10.0), 0.0)
	_put(M2 + "Debris & Misc/bricks_stacked_mx_1.glb", "y", Vector2(-76.8, -12.4), 20.0)
	_put(M2 + "Debris & Misc/gravel_pile_hr_1.glb", "y", Vector2(-90.6, -25.6), 0.0)
	_put(M2 + "Debris & Misc/debris_bricks_mx_1.glb", "y", Vector2(-75.6, -21.2), 60.0, {"collide": false})
	# Pallets and crates by the container.
	_put(B + "wood_pallet_1", "-z", Vector2(-89.8, -8.4), 10.0)
	_put(B + "wood_pallet_2", "-z", Vector2(-89.8, -8.4), 2.0)
	_put(B + "wooden_crate_9", "-z", Vector2(-89.4, -19.8), 15.0)
	_put(B + "wooden_crate_8", "-z", Vector2(-89.5, -21.0), -10.0)
	# Cones, and a lamp post at the edge of the yard.
	_put(F + "SM_EC_Traffic_Cone_0", "z", Vector2(-77.6, -21.9), 0.0)
	_put(F + "SM_EC_Traffic_Cone_0", "z", Vector2(-76.0, -19.6), 0.0)
	_put(F + "SM_EC_Lampost_0", "z", Vector2(-77.2, -10.4), 90.0)
	# A broken run of chain-link fence along the south edge.
	for x in [-93.0, -90.9, -88.8, -86.7]:
		_put(F + "SM_EC_ChainFence_0", "z", Vector2(x, -27.4), 0.0)
	# Litter.
	for spot in [Vector2(-84.0, -13.0), Vector2(-80.5, -14.2), Vector2(-87.4, -15.6), Vector2(-83.0, -22.0)]:
		_put(B + ["trash_1", "trash_4"][_rng.randi() % 2], "-z", spot, _rng.randf_range(0.0, 360.0))


func _dress_tunnel() -> void:
	var inside := {"ray_from": 2.4, "nudge": true}
	# Someone camped inside: a mattress, crates, a shelf, a lamp, litter.
	_put(M1 + "Furniture/old_mattress_mp_1.glb", "y", _tunnel(-4.8, -0.85), _tunnel_yaw(0.0), {"ray_from": 2.4, "collide": false})
	_put(B + "wooden_crate_8", "-z", _tunnel(-4.6, 1.0), _tunnel_yaw(5.0), inside)
	_put(B + "wooden_crate_9", "-z", _tunnel(-3.45, 1.05), _tunnel_yaw(-8.0), inside)
	_put(F + "SM_EC_55L_Drum_10", "z", _tunnel(-5.7, 1.05), 0.0, inside)
	_put(B + "lamp_0", "-z", _tunnel(-4.55, 1.0), 0.0, {"ray_from": 2.4, "collide": false})
	_put(B + "supply_box_1", "-z", _tunnel(-2.3, -1.1), _tunnel_yaw(80.0), inside)
	_put(B + "canned_food_3", "-z", _tunnel(-3.9, -0.3), 0.0, {"ray_from": 2.4, "collide": false})
	_put(B + "trash_1", "-z", _tunnel(-5.6, 0.3), 30.0, {"ray_from": 2.4})
	_put(B + "trash_4", "-z", _tunnel(1.0, 0.0), 70.0, {"ray_from": 2.4})
	# The mouth: concrete blocks either side, wire, cones, drums, gravel.
	_put(F + "SM_EC_ConcreteBlock_0", "z", _tunnel(-7.4, 2.7), _tunnel_yaw(0.0))
	_put(F + "SM_EC_ConcreteBlock_0", "z", _tunnel(-8.2, -3.6), _tunnel_yaw(8.0))
	_put(F + "SM_EC_BarbwireFence_00", "z", _tunnel(-9.6, 5.6), _tunnel_yaw(-20.0))
	_put(F + "SM_EC_BarbwireFence_00", "z", _tunnel(-10.0, -6.2), _tunnel_yaw(15.0))
	_put(F + "SM_EC_Traffic_Cone_0", "z", _tunnel(-9.2, 2.0), 0.0)
	_put(F + "SM_EC_Traffic_Cone_0", "z", _tunnel(-9.5, -2.3), 0.0)
	_put(F + "SM_EC_55L_Drum_03", "z", _tunnel(-7.0, 4.8), 0.0)
	_put(F + "SM_EC_55L_Drum_05", "z", _tunnel(-6.4, 5.3), 0.0)
	_put(M2 + "Debris & Misc/gravel_pile_hr_1.glb", "y", _tunnel(-3.0, -6.2), 0.0)
	# A stack of pipes and pallets by the old SUV.
	for i in 3:
		_put(B + "pipe_1", "y", Vector2(-23.6, 61.2) + Vector2(0.27, 0.0) * i, 0.0)
	for i in 2:
		_put(B + "pipe_1", "y", Vector2(-23.51, 61.2) + Vector2(0.27, 0.0) * i, 0.0)
	_put(B + "wood_pallet_1", "-z", Vector2(-21.4, 60.0), 35.0)


func _dress_willow() -> void:
	# A broken ring of standing stones around the clearing.
	for i in 11:
		var angle := TAU * i / 11.0 + 0.2
		if i == 3 or i == 8:
			continue
		var tall := _rng.randf_range(0.9, 1.6)
		var rock := F + "SM_EC_Rock_%02d" % _rng.randi_range(0, 95)
		# A tree in the way: a little further in.
		for radius in [9.6, 8.6, 7.8]:
			var spot: Vector2 = Vector2(TOTEM.x, TOTEM.z) + Vector2(cos(angle), sin(angle)) * float(radius)
			if _put(rock, "z", spot, _rng.randf_range(0.0, 360.0), {"scale": Vector3(1.0, 1.0, 1.4), "height": tall, "lift": -0.1, "ground_only": true}):
				break
	# Stakes with bloody straw at their feet, between the stones and the tree.
	for i in 4:
		var angle := TAU * i / 4.0 + 0.6
		var spot := Vector2(TOTEM.x, TOTEM.z) + Vector2(cos(angle), sin(angle)) * 7.0
		if not _put(F + "SM_EC_WoodenPole_Large_00", "y", spot, _rng.randf_range(0.0, 360.0), {"scale": Vector3(0.8, 0.36, 0.8), "lean": 6.0}):
			spot = Vector2(TOTEM.x, TOTEM.z) + Vector2(cos(angle), sin(angle)) * 6.2
			_put(F + "SM_EC_WoodenPole_Large_00", "y", spot, _rng.randf_range(0.0, 360.0), {"scale": Vector3(0.8, 0.36, 0.8), "lean": 6.0})
		_put(F + "SM_EC_Horror_Hay_Patch_0", "z", spot + Vector2(0.6, 0.3), _rng.randf_range(0.0, 360.0), {"collide": false, "lift": -0.02})
	for spot in [Vector2(TOTEM.x - 8.4, TOTEM.z + 0.8), Vector2(TOTEM.x + 6.6, TOTEM.z + 4.6), Vector2(TOTEM.x + 2.0, TOTEM.z - 7.6)]:
		if _put(F + "SM_EC_HorrorHay_Ball_0", "z", spot, 30.0):
			break
	# An old fire pit: a ring of small stones, burnt straw, a log.
	var pit := Vector2(TOTEM.x - 6.0, TOTEM.z - 5.2)
	for i in 7:
		var angle := TAU * i / 7.0
		_put(F + "SM_EC_Rock_%02d" % (10 + i), "z", pit + Vector2(cos(angle), sin(angle)) * 0.75, _rng.randf_range(0.0, 360.0),
			{"height": 0.28, "collide": false, "lift": -0.04, "allow_overlap": true})
	_put(F + "SM_EC_Horror_Hay_Patch_0", "z", pit, 20.0, {"scale": Vector3(0.5, 0.5, 0.5), "collide": false})
	_put(N + "tree_log_1", "y", pit + Vector2(1.6, 0.5), 30.0)


# ─── Placing ─────────────────────────────────────────────────────────────

## Places `model` (a scene or .glb path; a bare path gets ".tscn") with its
## up axis `up` ("y", "z" or "-z": the packs differ), its footprint centred
## on `at` (x, z), turned `yaw` degrees, standing on whatever is below.
## Options: "scale", "collide" (default true), "lift" (m, after landing),
## "ray_from" (m above the ground guess to look down from; under a roof),
## "nudge" (inside the tunnel: move toward its middle if it clips the
## shell), "lean" (degrees, random direction), "allow_overlap", "height"
## (m: scaled to stand this tall), "on_scene" (may stack on the level's own
## things), "ground_only" (never on another prop).
func _put(model: String, up: String, at: Vector2, yaw: float, options: Dictionary = {}) -> Node3D:
	var path := model if model.get_extension() != "" else model + (".tscn" if model.begins_with(F) else ".glb")
	var label := "%s at (%.1f, %.1f)" % [path.get_file(), at.x, at.y]
	var point := Vector3(at.x, 0.0, at.y)
	if not _spot_ok(point):
		skipped.append(label + ": crowds an interactable")
		return null
	if not ResourceLoader.exists(path):
		skipped.append(label + ": missing")
		return null
	var instance := (load(path) as PackedScene).instantiate() as Node3D
	var basis := Basis(Vector3.UP, deg_to_rad(yaw))
	if options.has("lean"):
		basis = Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), deg_to_rad(options.lean)) * basis
	match up:
		"z":
			basis = basis * Basis(Vector3.RIGHT, -PI / 2.0)
		"-z":
			basis = basis * Basis(Vector3.RIGHT, PI / 2.0)
	var scale_by: Vector3 = options.get("scale", Vector3.ONE)
	add_child(instance)
	instance.global_transform = Transform3D(basis * Basis.from_scale(scale_by), point)
	# Sized to a height (the rock models differ wildly in size).
	if options.has("height"):
		var tall := _world_box(instance).size.y
		if tall > 0.01:
			instance.global_transform = Transform3D(basis * Basis.from_scale(scale_by * (float(options.height) / tall)), point)
	# Centre the footprint on the spot, land it.
	var box := _world_box(instance)
	instance.global_position += Vector3(at.x - box.get_center().x, 0.0, at.y - box.get_center().z)
	var tries := 4 if options.get("nudge", false) else 1
	for attempt in tries:
		box = _world_box(instance)
		var ground := _ground(Vector3(box.get_center().x, 0.0, box.get_center().z), options.get("ray_from", 8.0), options.get("on_scene", false), options.get("ground_only", false))
		instance.global_position.y += ground - box.position.y + float(options.get("lift", 0.0))
		# Flat things (straw, litter) lie over whatever is there.
		if options.get("allow_overlap", false) or box.size.y < 0.4 or not _clips(instance):
			break
		if attempt == tries - 1:
			skipped.append(label + ": clips into " + _last_clip)
			instance.queue_free()
			return null
		# Toward the middle of the tunnel.
		var offset := instance.global_position - TUNNEL_C
		var across := offset.dot(TUNNEL_S)
		instance.global_position -= TUNNEL_S * signf(across) * 0.3
	if options.get("collide", true):
		_add_box_collider(instance)
	placed += 1
	return instance


## Placed by hand (the yard and the barn floor are painted as path: dirt),
## so only kept clear of the totem and of what the player uses.
## The level (current_scene in game; when it's instanced some other way,
## e.g. by the navmesh bake tool, the scene WorldDetails belongs to).
func _level() -> Node:
	var scene := get_tree().current_scene
	if scene:
		return scene
	var parent := get_parent()
	return parent.owner if parent and parent.owner else parent


func _spot_ok(point: Vector3) -> bool:
	if Vector2(point.x - TOTEM.x, point.z - TOTEM.z).length() < TOTEM_CLEAR:
		return false
	for thing in _interactables:
		if Vector2(point.x - thing.x, point.z - thing.z).length() < INTERACTABLE_CLEARANCE:
			return false
	return true


func _collect_interactables() -> void:
	_interactables.clear()
	for group_name in ["interactable", "pickup", "scrap_heap", "portable_trap"]:
		for thing in get_tree().get_nodes_in_group(group_name):
			if thing is Node3D:
				_interactables.append((thing as Node3D).global_position)
	var scene := _level()
	var nests := scene.get_node_or_null("NestLocations") if scene else null
	if nests:
		for nest in nests.get_children():
			if nest is Node3D:
				_interactables.append((nest as Node3D).global_position)


## The height of whatever is under `point`: the ground, or one of these
## props (stacks stack), or with `on_scene` anything of the level's (a
## container to dump another on). Looks down from height `from`; trees and
## the like in between are looked through.
func _ground(point: Vector3, from: float, on_scene: bool, ground_only: bool = false) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, from, point.z), Vector3(point.x, -20.0, point.z))
	query.hit_back_faces = false
	var exclude: Array[RID] = []
	for i in 8:
		query.exclude = exclude
		var hit := _space.intersect_ray(query)
		if hit.is_empty():
			return 0.0
		var collider: Object = hit.collider
		var own := collider is Node and is_ancestor_of(collider as Node)
		if _is_terrain(collider) or (not ground_only and (on_scene or own)):
			return (hit.position as Vector3).y
		exclude.append(hit.rid)
	return 0.0


## Whether the instance's box overlaps something solid other than the
## ground (the terrain) and what it stands on.
func _clips(instance: Node3D) -> bool:
	var box := _local_box(instance)
	if box.size.y < 0.2:
		return false
	var shape := BoxShape3D.new()
	shape.size = (box.size * 0.8).max(Vector3.ONE * 0.05)
	shape.size.y = maxf(box.size.y * 0.6, 0.05)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	var centre := box.get_center()
	centre.y = box.position.y + box.size.y * 0.55
	query.transform = instance.global_transform.orthonormalized() * Transform3D(Basis(), centre * instance.global_transform.basis.get_scale())
	for hit in _space.intersect_shape(query, 8):
		var collider: Object = hit.collider
		if collider and collider.get_class() != "StaticBody3D":
			continue
		if collider and _is_terrain(collider):
			continue
		_last_clip = String((collider as Node).name) if collider is Node else "?"
		return true
	return false


func _is_terrain(collider: Object) -> bool:
	if not collider is Node:
		return true
	var node := collider as Node
	while node:
		var name_l := String(node.name).to_lower()
		if "terra" in name_l or "terrain" in name_l or "ground" in name_l:
			return true
		node = node.get_parent()
	return false


## The instance's meshes' bounds, in world space.
func _world_box(instance: Node3D) -> AABB:
	var box := AABB(instance.global_position, Vector3.ZERO)
	var first := true
	for mesh in instance.find_children("*", "MeshInstance3D", true, false):
		var bounds: AABB = (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	return box


## The instance's meshes' bounds in its own (unscaled-basis) space.
func _local_box(instance: Node3D) -> AABB:
	var inverse := instance.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mesh in instance.find_children("*", "MeshInstance3D", true, false):
		var bounds: AABB = (inverse * (mesh as MeshInstance3D).global_transform) * (mesh as MeshInstance3D).get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	return box


## A box collider around the instance's meshes (unless it has a collider).
func _add_box_collider(instance: Node3D) -> bool:
	if not instance.find_children("*", "CollisionShape3D", true, false).is_empty():
		return false
	var box := _local_box(instance)
	if box.size.length() < 0.2:
		return false
	var body := StaticBody3D.new()
	body.name = "SiteCollider"
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = (box.size * 0.92).max(Vector3.ONE * 0.04)
	shape.shape = box_shape
	shape.position = box.get_center()
	body.add_child(shape)
	instance.add_child(body)
	return true


func _tunnel(along: float, across: float) -> Vector2:
	var p := TUNNEL_C + TUNNEL_A * along + TUNNEL_S * across
	return Vector2(p.x, p.z)


## A yaw (degrees) lined up with the tunnel, plus `extra`.
func _tunnel_yaw(extra: float) -> float:
	return rad_to_deg(atan2(TUNNEL_A.x, TUNNEL_A.z)) + extra


# ─── Fixes to what's there ───────────────────────────────────────────────

## The barn's doors were placed ~4 m along the north wall from its doorway
## (drawn shut over solid wall, while the real opening beside them stood
## empty). They're moved onto the doorway and swing open (with colliders).
func _fix_barn() -> void:
	var scene := _level()
	var barn := scene.get_node_or_null(BARN) if scene else null
	if not barn:
		return
	var y0 := (barn as Node3D).global_position.y
	var shift := Vector3(BARN_DOORWAY_X.x - BARN_DOOR_X.x, 0.0, 0.0)
	for door_name in ["SM_EC_Barn_Door_04", "SM_EC_Barn_Door_05"]:
		var door := barn.get_node_or_null(door_name) as Node3D
		if door:
			door.global_position += shift
	# One wide open, one half.
	_swing_door(barn.get_node_or_null("SM_EC_Barn_Door_05") as Node3D, Vector3(BARN_DOORWAY_X.x, y0, BARN_NORTH_Z), 100.0)
	_swing_door(barn.get_node_or_null("SM_EC_Barn_Door_04") as Node3D, Vector3(BARN_DOORWAY_X.x + BARN_DOOR_X.y - BARN_DOOR_X.x, y0, BARN_NORTH_Z), -70.0)


func _swing_door(door: Node3D, hinge: Vector3, degrees: float) -> void:
	if not door:
		return
	var swing := Transform3D(Basis(), hinge) * Transform3D(Basis(Vector3.UP, deg_to_rad(degrees)), Vector3.ZERO) * Transform3D(Basis(), -hinge)
	door.global_transform = swing * door.global_transform
	var body := StaticBody3D.new()
	body.name = "DoorCollider"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var mesh := door as MeshInstance3D
	var local := mesh.get_aabb() if mesh else AABB(Vector3.ZERO, Vector3(1.4, 3.4, 0.1))
	box.size = local.size.max(Vector3.ONE * 0.08)
	shape.shape = box
	shape.position = local.get_center()
	body.add_child(shape)
	door.add_child(body)


## Props already in these places with no collider (drums, traffic barriers,
## signs) get a box one.
func _add_missing_colliders() -> void:
	var scene := _level()
	if not scene:
		return
	var roots: Array[Node] = [scene]
	var details := scene.get_node_or_null("Details/Outside Cabin")
	if details:
		roots.append(details)
	for root_node in roots:
		for node in root_node.get_children():
			if not node is Node3D or node.scene_file_path == "":
				continue
			var file: String = node.scene_file_path
			if not (file.begins_with(F) or file.begins_with(B)):
				continue
			if "Plant" in file or "Grass" in file or "Bush" in file or "Tree" in file or "Path" in file or "Crop" in file or "Patch" in file:
				continue
			var at := (node as Node3D).global_position
			var in_area := false
			for area in AREAS:
				if Vector2(at.x - area.x, at.z - area.y).length() < area.z:
					in_area = true
			if not in_area:
				continue
			if _local_box(node).size.y < 0.25 and _world_box(node).size.y < 0.25:
				continue
			if _add_box_collider(node):
				fixed_colliders += 1
