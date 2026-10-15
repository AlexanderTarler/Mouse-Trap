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
##   - The cabin, lived in: plates and jars on the kitchen counter, a shelf,
##     books, boxes, a map and clocks on the walls, a suitcase upstairs.
##     Small things have no collider (kept off doorways, windows and what
##     the player uses).
##   - Around the cabin: firewood and a chopping block out the back, a
##     bench by the porch, a rain barrel, crates, tyres by the generator.
##     Nothing under a window (the Entity climbs there).
##   - Along the walking paths, where the player goes: fallen logs, stumps,
##     rocks, and the old survey's stakes (orange tape) by the nests.
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
var _windows: Array[Vector3] = []
## Only the cabin, its yard and the trails (the level has the rest baked in
## already: its "Sites" node, tools/bake_sites.gd).
var extras_only := false
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
	if not extras_only:
		_fix_barn()
		_add_missing_colliders()
		_dress_barn()
		_dress_yard()
		_dress_tunnel()
		_dress_willow()
	_collect_windows()
	_dress_cabin()
	_dress_cabin_yard()
	_dress_trails()
	_dress_boulders()
	_dress_clearcut()
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


## The cabin's rooms (inner walls, measured): ground floor at 0.73 (ceiling
## 3.58), upper floor at 3.73 (ceiling 6.58).
##   hall x 4.47-8.98, z 8.11-14.11 (front door in the east wall, z ~9.4;
##     to the living room, x ~6.8-8.0)
##   living room / kitchen x 2.98-8.98, z 14.41-20.41 (counters along the
##     north wall; to the computer room, z ~15.3-16.3)
##   computer room x 9.28-15.28, z 14.41-20.41
##   upstairs the same: upper hall, landing, bedroom.
const GROUND_FLOOR := 0.73
const UPPER_FLOOR := 3.73


func _dress_cabin() -> void:
	var g := {"ray_from": 3.0, "on_scene": true, "clear": 0.9, "floor": GROUND_FLOOR, "avoid_windows": true, "collide": false}
	var u := {"ray_from": 6.0, "on_scene": true, "clear": 0.9, "floor": UPPER_FLOOR, "avoid_windows": true, "collide": false}
	# The hall: a rug inside the front door, a clock, a painting.
	_put(F + "SM_EC_House_Rug_01", "z", Vector2(8.25, 9.6), 90.0, _with(g, {"allow_overlap": true, "lift": -0.01}))
	_put(M1 + "Small Props/clock_1.glb", "y", Vector2(5.8, 8.11), 0.0, _with(g, {"y": 2.35, "back": Vector3(0, 0, 1)}))
	_put(M1 + "Small Props/painting_1.glb", "y", Vector2(5.3, 14.11), 180.0, _with(g, {"y": 1.75, "back": Vector3(0, 0, -1)}))
	# The kitchen: plates and jars on the counter, a stool.
	_put(M1 + "Small Props/plate_mp_1.glb", "y", Vector2(5.25, 20.1), 0.0, g)
	_put(M1 + "Small Props/plate_mp_1.glb", "y", Vector2(5.27, 20.1), 10.0, g)
	_put(M2 + "Props/jam_jar_mp_1_small.glb", "y", Vector2(5.75, 20.15), 0.0, g)
	_put(M2 + "Props/pickles_jar_mp_1_medium.glb", "y", Vector2(5.95, 20.2), 30.0, g)
	_put(M1 + "Items & Weapons/canned_food_mp_2.glb", "y", Vector2(4.05, 20.15), 0.0, g)
	_put(M2 + "Props/stool_mx_1.glb", "y", Vector2(6.7, 19.35), 20.0, g)
	# The living room: books on the shelf by the west wall, a clock, a
	# painting, books on the floor.
	_put(M1 + "Small Props/book_mp_2.glb", "y", Vector2(3.25, 18.1), 90.0, g)
	_put(M1 + "Small Props/book_mp_5.glb", "y", Vector2(3.25, 18.45), 80.0, g)
	_put(M1 + "Small Props/clock_2.glb", "y", Vector2(4.3, 14.41), 0.0, _with(g, {"y": 2.4, "back": Vector3(0, 0, 1)}))
	_put(M1 + "Small Props/painting_1.glb", "y", Vector2(2.98, 17.6), 90.0, _with(g, {"y": 1.8, "back": Vector3(1, 0, 0)}))
	_put(M1 + "Small Props/book_mp_3.glb", "y", Vector2(8.45, 17.6), 30.0, g)
	_put(M1 + "Small Props/book_mp_7.glb", "y", Vector2(8.45, 17.6), 75.0, g)
	# The computer room: the survey map on the wall, boxes of files in a
	# corner, a radio and an ashtray on the table, a toolbox.
	_put(M2 + "Props/map_mx_1.glb", "y", Vector2(11.6, 20.41), 180.0, _with(g, {"y": 1.6, "back": Vector3(0, 0, -1)}))
	_put(M2 + "Props/cardboard_box_1.glb", "y", Vector2(9.85, 19.85), 5.0, _with(g, {"collide": true}))
	_put(M2 + "Props/cardboard_box_2.glb", "y", Vector2(9.9, 19.8), -8.0, _with(g, {"collide": true}))
	_put(M2 + "Props/handheld_fm_radio_etx_1.glb", "y", Vector2(12.5, 17.7), 160.0, g)
	_put(M1 + "Small Props/ashtray_1.glb", "y", Vector2(11.9, 17.2), 0.0, g)
	_put(M2 + "Props/toolbox_mx_1.glb", "y", Vector2(14.5, 20.0), 15.0, g)
	# The upper hall: boxes, a painting.
	_put(M2 + "Props/cardboard_box_1.glb", "y", Vector2(8.4, 13.5), 12.0, _with(u, {"collide": true}))
	_put(M1 + "Small Props/painting_1.glb", "y", Vector2(5.6, 8.11), 0.0, _with(u, {"y": 5.0, "back": Vector3(0, 0, 1)}))
	# The landing: books on the shelf, a lamp, a box, a clock.
	_put(M1 + "Small Props/book_mp_4.glb", "y", Vector2(3.3, 17.2), 90.0, u)
	_put(M1 + "Small Props/book_mp_8.glb", "y", Vector2(3.3, 17.55), 95.0, u)
	_put(M2 + "Light Sources/lamp_mx_1_a_off.glb", "y", Vector2(3.5, 19.9), 0.0, u)
	_put(M2 + "Props/cardboard_box_2.glb", "y", Vector2(3.5, 14.95), 20.0, _with(u, {"collide": true}))
	_put(M1 + "Small Props/clock_1.glb", "y", Vector2(4.6, 20.41), 180.0, _with(u, {"y": 5.3, "back": Vector3(0, 0, -1)}))
	# The bedroom: the suitcase, books by the bed, a chair, a painting.
	_put(M2 + "Props/luggage_mp_1.glb", "y", Vector2(12.0, 14.41), 0.0, _with(u, {"back": Vector3(0, 0, 1), "collide": true}))
	_put(M1 + "Small Props/book_mp_6.glb", "y", Vector2(13.0, 19.95), 20.0, u)
	_put(M1 + "Small Props/open_book_mp_1.glb", "y", Vector2(13.4, 19.9), -15.0, u)
	_put(M1 + "Furniture/chair_mp_1.glb", "y", Vector2(11.0, 19.8), 200.0, u)
	_put(M1 + "Small Props/painting_1.glb", "y", Vector2(15.28, 17.4), -90.0, _with(u, {"y": 5.35, "back": Vector3(-1, 0, 0)}))


## Around the cabin (outer walls: west x ~2.65, front z ~7.8, the hall's
## east side x ~9.3, the main block's south side z ~14.1, east x ~15.5,
## back z ~20.7).
func _dress_cabin_yard() -> void:
	var o := {"avoid_windows": true}
	# Out the back: a stack of firewood, a chopping block with the axe.
	for i in 3:
		_put(N + "tree_log_1", "y", Vector2(9.8 + i * 0.7, 21.45), 0.0, _with(o, {"height": 0.32}))
	for i in 2:
		_put(N + "tree_log_1", "y", Vector2(10.15 + i * 0.7, 21.45), 0.0, _with(o, {"height": 0.32}))
	_put(N + "tree_log_1", "y", Vector2(10.5, 21.45), 0.0, _with(o, {"height": 0.32}))
	_put(N + "tree_stump_1", "y", Vector2(11.2, 23.4), 0.0, _with(o, {"height": 0.5}))
	_put(M2 + "Weapons & Tools/axe_mx_1.glb", "y", Vector2(11.2, 23.4), 35.0, _with(o, {"collide": false, "pitch": 90.0}))
	# A rain barrel at the corner; crates stacked by the west wall.
	_put(B + "water_barrel_1", "-z", Vector2(16.35, 21.35), 0.0, o)
	_put(B + "wooden_crate_8", "-z", Vector2(1.75, 19.95), 8.0, o)
	_put(B + "wooden_crate_9", "-z", Vector2(1.75, 19.95), -6.0, o)
	# The porch side: a bench against the wall, a jerrycan.
	_put(M2 + "Props/bench_mx_1.glb", "y", Vector2(12.6, 13.85), 0.0, _with(o, {"back": Vector3(0, 0, -1), "clear": 1.0}))
	_put(M2 + "Props/jerrycan_mx_1.glb", "y", Vector2(14.4, 13.35), 25.0, o)
	# By the generator's drums: tyres, a gas bottle.
	_put(M2 + "Props/tire_1.glb", "y", Vector2(21.8, 18.6), 0.0, o)
	_put(M2 + "Props/tire_2.glb", "y", Vector2(21.8, 18.6), 30.0, o)
	_put(M2 + "Props/gas_cylinder_mx_1.glb", "y", Vector2(22.9, 18.9), 0.0, o)


## Along the walking paths (TerrainMask), where the player walks: now and
## then a fallen log, a stump or a few rocks just off the path; by the
## nests, the old survey's stakes with orange tape.
const TRAIL_CHANCE := 0.07
const TRAIL_OFFSET := Vector2(2.0, 3.4)


func _dress_trails() -> void:
	var img := TerrainMask.image()
	if img == null:
		return
	ForestDresser.refresh_interactables(self)
	var trail_rng := RandomNumberGenerator.new()
	trail_rng.seed = 20261015
	for py in img.get_height():
		for px in img.get_width():
			if img.get_pixel(px, py).g < 0.6 or trail_rng.randf() > TRAIL_CHANCE:
				continue
			var on := Vector3(px - TerrainMask.HALF, 0.0, py - TerrainMask.HALF)
			# Off to the side the path falls away to.
			var across := Vector3(TerrainMask.path(on + Vector3.RIGHT) - TerrainMask.path(on + Vector3.LEFT), 0.0,
				TerrainMask.path(on + Vector3.BACK) - TerrainMask.path(on + Vector3.FORWARD))
			if across.length() < 0.01:
				across = Vector3.RIGHT.rotated(Vector3.UP, trail_rng.randf() * TAU)
			var side := -across.normalized()
			if trail_rng.randf() < 0.5:
				side = -side
			var spot := on + side * trail_rng.randf_range(TRAIL_OFFSET.x, TRAIL_OFFSET.y)
			if not ForestDresser.clear(spot):
				continue
			var at := Vector2(spot.x, spot.z)
			var yaw := trail_rng.randf_range(0.0, 360.0)
			match trail_rng.randi() % 4:
				0, 1:
					_keep_off_path(_put(N + "tree_log_1", "y", at, yaw, {"height": trail_rng.randf_range(0.3, 0.45), "ground_only": true, "avoid_windows": true}))
				2:
					_keep_off_path(_put(N + "tree_stump_1", "y", at, yaw, {"height": trail_rng.randf_range(0.35, 0.6), "ground_only": true}))
				3:
					for k in 3:
						var rock := at + Vector2(trail_rng.randf_range(-0.6, 0.6), trail_rng.randf_range(-0.6, 0.6))
						_keep_off_path(_put(N + "stone_%d" % trail_rng.randi_range(1, 5), "y", rock, trail_rng.randf_range(0.0, 360.0),
							{"height": trail_rng.randf_range(0.2, 0.5), "ground_only": true, "collide": k == 0, "lift": -0.05}))
	# The old survey's stakes around each nest.
	var scene := _level()
	var nests := scene.get_node_or_null("NestLocations") if scene else null
	if nests:
		for nest in nests.get_children():
			if not nest is Node3D:
				continue
			var centre := (nest as Node3D).global_position
			for i in 3:
				var angle := TAU * i / 3.0 + trail_rng.randf_range(0.0, 1.0)
				# Not on the path up to it: round a little further if so.
				for turn in 8:
					var at := Vector2(centre.x, centre.z) + Vector2(cos(angle), sin(angle)) * 3.2
					if TerrainMask.path(Vector3(at.x, 0.0, at.y)) < 0.3:
						_survey_stake(at, trail_rng.randf_range(-6.0, 6.0))
						break
					angle += 0.35


## Boulders through the forest (what the ice left behind, all over a Swedish
## forest): BOULDERS of them, some with a smaller one beside, on the forest
## floor, off the paths and the road, clear of the cabin and of what the
## player uses. Solid (the navmesh walks around them: tools/bake_navmesh.gd).
const BOULDERS := 40
const BOULDER_MODELS := ["SM_EC_Rock_01", "SM_EC_Rock_02", "SM_EC_Rock_26", "SM_EC_Rock_27"]
const BOULDER_HEIGHT := Vector2(1.6, 3.2)
const BOULDER_PATH_MARGIN := 2.5
const BOULDER_ROAD_MARGIN := 3.0
const BOULDER_CABIN_CLEAR := 25.0


func _dress_boulders() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261016
	var count := 0
	for attempt in 1200:
		if count >= BOULDERS:
			break
		var spot := Vector3(rng.randf_range(-115.0, 115.0), 0.0, rng.randf_range(-115.0, 115.0))
		if TerrainMask.sample(spot).b < 0.5 or TerrainMask.near_path(spot, BOULDER_PATH_MARGIN) 				or GravelRoad.covers(spot, BOULDER_ROAD_MARGIN) or not ForestDresser.clear(spot) 				or Vector2(spot.x - 9.0, spot.z - 14.0).length() < BOULDER_CABIN_CLEAR:
			continue
		var tall := rng.randf_range(BOULDER_HEIGHT.x, BOULDER_HEIGHT.y)
		# A spot that doesn't fit (a trunk in the way) is just a try: not a
		# skipped prop.
		var tried := skipped.size()
		var boulder := _put(F + BOULDER_MODELS[rng.randi() % BOULDER_MODELS.size()], "z", Vector2(spot.x, spot.z),
			rng.randf_range(0.0, 360.0), {"height": tall, "lean": 10.0, "lift": -0.12 * tall, "ground_only": true, "clear": 3.0})
		if boulder == null:
			skipped.resize(tried)
			continue
		count += 1
		if rng.randf() < 0.35:
			var angle := rng.randf() * TAU
			var beside := Vector2(spot.x, spot.z) + Vector2(cos(angle), sin(angle)) * tall * 0.9
			tried = skipped.size()
			if not _put(F + BOULDER_MODELS[rng.randi() % BOULDER_MODELS.size()], "z", beside, rng.randf_range(0.0, 360.0),
					{"height": tall * rng.randf_range(0.35, 0.6), "lean": 15.0, "lift": -0.1 * tall, "ground_only": true, "clear": 3.0}):
				skipped.resize(tried)


## By the 1974 clear-cut (ForestDresser.CLEARCUT): the logging camp's last
## pile, never collected, greying where it lies. At the first of a few
## spots on its edge where it fits.
const CLEARCUT_PILES := [Vector2(76.0, -86.0), Vector2(78.0, -99.0), Vector2(92.0, -80.0), Vector2(86.0, -92.0)]


func _dress_clearcut() -> void:
	for at in CLEARCUT_PILES:
		var yaw := 20.0
		var tried := skipped.size()
		var bottom := _put(N + "tree_log_1", "y", at, yaw, {"ground_only": true, "clear": 3.0})
		if bottom == null:
			skipped.resize(tried)
			continue
		var across := Vector2(cos(deg_to_rad(-yaw)), sin(deg_to_rad(-yaw))).orthogonal()
		_put(N + "tree_log_1", "y", at + across * 0.55, yaw + 3.0, {"ground_only": true, "clear": 3.0})
		_put(N + "tree_log_1", "y", at - across * 0.55, yaw - 2.0, {"ground_only": true, "clear": 3.0})
		_put(N + "tree_log_1", "y", at + across * 0.25, yaw + 1.0, {"clear": 3.0, "allow_overlap": true})
		_put(N + "tree_log_1", "y", at - across * 0.3, yaw - 4.0, {"clear": 3.0, "allow_overlap": true})
		_put(F + "SM_EC_55L_Drum_03", "z", at + across * 2.4 + Vector2(1.0, 0.5), 0.0, {"lean": 8.0, "clear": 3.0})
		return


## Takes `instance` away again if any of its footprint is on a walking path
## (a long log, a rock off to one side).
func _keep_off_path(instance: Node3D) -> void:
	if instance == null:
		return
	var box := _world_box(instance)
	for corner in [box.position, box.position + Vector3(box.size.x, 0, 0), box.position + Vector3(0, 0, box.size.z),
			box.position + Vector3(box.size.x, 0, box.size.z), box.get_center()]:
		if TerrainMask.path(corner) > 0.3:
			skipped.append("%s at (%.1f, %.1f): on a path" % [instance.name, box.get_center().x, box.get_center().z])
			instance.queue_free()
			remove_child(instance)
			placed -= 1
			return


## A thin wooden stake with a strip of faded orange tape tied near its top.
func _survey_stake(at: Vector2, lean: float) -> Node3D:
	var point := Vector3(at.x, 0.0, at.y)
	if Vector2(point.x - TOTEM.x, point.z - TOTEM.z).length() < TOTEM_CLEAR:
		return null
	var ground := _ground(point, 8.0, false, true)
	var stake := Node3D.new()
	stake.name = "SurveyStake"
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.32, 0.2)
	wood.roughness = 1.0
	var post := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.04, 0.9, 0.04)
	box.material = wood
	post.mesh = box
	post.position.y = 0.45
	stake.add_child(post)
	var tape := MeshInstance3D.new()
	var strip := QuadMesh.new()
	strip.size = Vector2(0.05, 0.32)
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.85, 0.36, 0.1)
	orange.cull_mode = BaseMaterial3D.CULL_DISABLED
	orange.roughness = 0.8
	strip.material = orange
	tape.mesh = strip
	tape.position = Vector3(0.03, 0.68, 0.0)
	tape.rotation = Vector3(0.0, deg_to_rad(_rng.randf_range(0.0, 180.0)), deg_to_rad(12.0))
	stake.add_child(tape)
	add_child(stake)
	stake.global_transform = Transform3D(Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), deg_to_rad(lean)), Vector3(point.x, ground - 0.05, point.z))
	placed += 1
	return stake


## `base` with `extra`'s options on top.
func _with(base: Dictionary, extra: Dictionary) -> Dictionary:
	var merged := base.duplicate()
	merged.merge(extra, true)
	return merged


func _collect_windows() -> void:
	_windows.clear()
	for window in get_tree().get_nodes_in_group("WindowMarkers"):
		# (The windows themselves, not their markers: duck-typed, so this
		# compiles without the game's autoloads, as the tests need.)
		if window is Node3D and window.has_method("is_passable"):
			_windows.append((window as Node3D).global_position)


## Too close to a window (flat; with `floor`, only that floor's windows):
## the Entity peeks, breaks in and climbs there.
func _by_window(point: Vector3, floor_y: float) -> bool:
	for window in _windows:
		if floor_y > -100.0 and absf(window.y - floor_y - 1.6) > 1.5:
			continue
		var reach := 1.3 if floor_y > -100.0 else 1.7
		if Vector2(point.x - window.x, point.z - window.z).length() < reach:
			return true
	return false


# ─── Placing ─────────────────────────────────────────────────────────────

## Places `model` (a scene or .glb path; a bare path gets ".tscn") with its
## up axis `up` ("y", "z" or "-z": the packs differ), its footprint centred
## on `at` (x, z), turned `yaw` degrees, standing on whatever is below.
## Options: "scale", "collide" (default true), "lift" (m, after landing),
## "ray_from" (m above the ground guess to look down from; under a roof),
## "nudge" (inside the tunnel: move toward its middle if it clips the
## shell), "lean" (degrees, random direction), "allow_overlap", "height"
## (m: scaled to stand this tall), "on_scene" (may stack on the level's own
## things), "ground_only" (never on another prop), "clear" (m kept from
## what the player uses; default INTERACTABLE_CLEARANCE), "floor" (only
## things on this floor count), "avoid_windows", "y" (its bottom at this
## height instead of landing: on a wall), "back" (a direction into the
## room: its back against the wall at `at`'s coordinate that way), "pitch"
## (degrees, tipped over about its own x).
func _put(model: String, up: String, at: Vector2, yaw: float, options: Dictionary = {}) -> Node3D:
	var path := model if model.get_extension() != "" else model + (".tscn" if model.begins_with(F) else ".glb")
	var label := "%s at (%.1f, %.1f)" % [path.get_file(), at.x, at.y]
	var point := Vector3(at.x, 0.0, at.y)
	var floor_y: float = options.get("floor", -1000.0)
	if not _spot_ok(point, options.get("clear", INTERACTABLE_CLEARANCE), floor_y):
		skipped.append(label + ": crowds an interactable")
		return null
	if options.get("avoid_windows", false) and _by_window(point, floor_y):
		skipped.append(label + ": by a window")
		return null
	if not ResourceLoader.exists(path):
		skipped.append(label + ": missing")
		return null
	var instance := (load(path) as PackedScene).instantiate() as Node3D
	var basis := Basis(Vector3.UP, deg_to_rad(yaw))
	if options.has("pitch"):
		basis = basis * Basis(Vector3.RIGHT, deg_to_rad(options.pitch))
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
	# Back against a wall.
	if options.has("back"):
		var into: Vector3 = options.back
		box = _world_box(instance)
		if into.x > 0.5:
			instance.global_position.x += at.x + 0.02 - box.position.x
		elif into.x < -0.5:
			instance.global_position.x += at.x - 0.02 - box.end.x
		elif into.z > 0.5:
			instance.global_position.z += at.y + 0.02 - box.position.z
		elif into.z < -0.5:
			instance.global_position.z += at.y - 0.02 - box.end.z
	# On a wall: at a height, not landed.
	if options.has("y"):
		box = _world_box(instance)
		instance.global_position.y += float(options.y) - box.position.y
		if options.get("collide", true):
			_add_box_collider(instance)
		placed += 1
		return instance
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


func _spot_ok(point: Vector3, clearance: float = INTERACTABLE_CLEARANCE, floor_y: float = -1000.0) -> bool:
	if Vector2(point.x - TOTEM.x, point.z - TOTEM.z).length() < TOTEM_CLEAR:
		return false
	for thing in _interactables:
		if floor_y > -100.0 and (thing.y < floor_y - 0.5 or thing.y > floor_y + 2.6):
			continue
		if Vector2(point.x - thing.x, point.z - thing.z).length() < clearance:
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
