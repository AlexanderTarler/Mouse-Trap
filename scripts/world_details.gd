extends Node3D
## Small natural detail across the whole map, by what the ground is painted
## with (TerrainMask): dry tall grass, wildflowers, thistles and blueberry
## bushes in the clearings; weeds and grass clumps along the path verges;
## mushrooms, blueberry bushes and weeds on the forest floor.
##
## Nothing lands on or next to a walking path, in the cabin yard, on the road,
## at the totem, next to anything the player interacts with or the nests
## (ForestDresser.clear), or where something solid already stands (a quick
## physics check, so buildings, fences, rocks and trunks keep clear). Nothing
## it adds has a collider. Placed the same way every time (fixed seed), drawn
## in batches (FoliageBatcher).

const MEADOWS := "res://assets/PSX Forest Meadows by VadaCross/3D Models/"
const CARDS := "res://assets/Fixed .fbx/"

## Candidate spots: one per GRID_STEP square (jittered), across the map.
const GRID_STEP := 1.6
const MAP_HALF := 122.0

## Per kind of ground: [model, chance per candidate spot, min scale, max scale].
## A spot gets at most one thing.
const CLEARING := [
	["wheat_1", 0.07, 0.8, 1.3],
	["grass_3", 0.04, 0.8, 1.2],
	["grass_4", 0.04, 0.8, 1.2],
	[MEADOWS + "Daisys/Daisys.fbx", 0.05, 1.0, 1.6],
	[MEADOWS + "Coreopsis/Coreopsis.fbx", 0.04, 1.0, 1.6],
	[MEADOWS + "Thistles/Thistles.fbx", 0.025, 0.8, 1.2],
	[MEADOWS + "Blueberry Bush/Blueberry Bush.fbx", 0.015, 0.8, 1.2],
	[MEADOWS + "Wild Lavinder/Wild Lavinder.fbx", 0.004, 0.5, 0.8],
]
const VERGE := [
	[CARDS + "SM_EC_Plant_Card_Cross_00.tscn", 0.06, 0.8, 1.3],
	[CARDS + "SM_EC_Plant_Card_Cross_05.tscn", 0.05, 0.8, 1.3],
	[CARDS + "SM_EC_Plant_Card_Cross_10.tscn", 0.05, 0.8, 1.3],
	["grass_1", 0.06, 0.8, 1.2],
	["grass_2", 0.04, 0.8, 1.2],
	[MEADOWS + "Thistles/Thistles.fbx", 0.02, 0.7, 1.1],
	["stone_5", 0.03, 1.0, 2.0],
]
## (Blueberry carpets the floor of a Swedish pine forest; ferns where it's
## damper.)
const FOREST_FLOOR := [
	[MEADOWS + "Mushrooms/Mushrooms.fbx", 0.03, 1.0, 1.8],
	[MEADOWS + "Blueberry Bush/Blueberry Bush.fbx", 0.06, 0.8, 1.2],
	[MEADOWS + "Fern/Fern.fbx", 0.03, 0.7, 1.1],
	[CARDS + "SM_EC_Plant_Card_Cross_00.tscn", 0.025, 0.8, 1.3],
	[CARDS + "SM_EC_Plant_Card_Cross_10.tscn", 0.02, 0.8, 1.3],
]

## Kept clear of the edges of walking paths (m), beyond TerrainMask.near_path's default.
const PATH_MARGIN := 1.2
## Something solid within this radius of a spot: skip it.
const SOLID_CHECK_RADIUS := 0.6

## Emitted once the detail is scattered and batched (FoliageRustle waits
## for it).
signal scattered

## The other flocks: [name, centre, birds, perch, the player this close
## sends them up, the area searched for a ridge (HIGH), Day 1 only].
const FLOCKS := [
	["CrowsCabinRoof", Vector3(9.0, 0.0, 17.0), 5, Crows.Perch.HIGH, 50.0, Vector2(6.0, 3.0), true],
	["CrowsBarnRoof", Vector3(36.8, 0.0, -74.7), 6, Crows.Perch.HIGH, 16.0, Vector2(8.0, 8.0), false],
	["CrowsWreckYard", Vector3(-84.0, 0.0, -15.0), 5, Crows.Perch.HIGH, 14.0, Vector2(9.0, 9.0), false],
	["CrowsClearcut", Vector3(84.0, 0.4, -90.0), 6, Crows.Perch.GROUND, 14.0, Vector2(8.0, 8.0), false],
]

var placed := 0
var is_scattered := false
## Where things were placed (for the tests).
var spots := PackedVector3Array()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# The man-made places get furnished too (SiteDresser); if the level has
	# them already (tools/bake_sites.gd writes them into it), only the
	# cabin, its yard and the trails.
	# (Once tools/bake_details.gd has written the cabin's and the trails'
	# into the level too, "CabinDetails": nothing more.)
	if not (owner and owner.has_node("CabinDetails")):
		var sites := SiteDresser.new()
		sites.name = "SiteDresser"
		sites.extras_only = owner != null and owner.has_node("Sites")
		add_child(sites)
	# Crows at the willow (Crows), and other flocks by day: the cabin's roof
	# ridge on Day 1 (up when the player is ~50 m off), the barn roof, the
	# wreck yard, the old clear-cut.
	var crows := Crows.new()
	crows.name = "Crows"
	add_child(crows)
	for flock: Array in FLOCKS:
		var more := Crows.new().setup(flock[1], flock[2], flock[3], flock[4], flock[5], flock[6])
		more.name = flock[0]
		add_child(more)
	# The cabin, night by night: settling, creaking, a handle tried (HouseUnease).
	var unease := HouseUnease.new()
	unease.name = "HouseUnease"
	add_child(unease)
	# The hall clock ticks, louder at night (ClockTick).
	var clock := owner.get_node_or_null("CabinDetails/clock_1") if owner else null
	var tick := ClockTick.new()
	tick.name = "ClockTick"
	add_child(tick)
	tick.global_position = (clock as Node3D).global_position if clock else ClockTick.FALLBACK
	# Plants rustle when walked into (FoliageRustle).
	var rustle := FoliageRustle.new()
	rustle.name = "FoliageRustle"
	add_child(rustle)
	# The physics space needs a step before it can be queried, and the
	# forest's batches are built first (they share FoliageBatcher's list).
	await get_tree().physics_frame
	while FoliageBatcher.is_build_scheduled():
		await get_tree().process_frame
	scatter()


func scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261001
	ForestDresser.refresh_interactables(self)
	var space := get_world_3d().direct_space_state
	var probe := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = SOLID_CHECK_RADIUS
	probe.shape = sphere
	probe.collision_mask = 1
	var terrain := _terrain_bodies()
	probe.exclude = terrain

	var steps := int(MAP_HALF * 2.0 / GRID_STEP)
	for iz in steps:
		for ix in steps:
			var spot := Vector3(-MAP_HALF + (ix + rng.randf()) * GRID_STEP, 0.0, -MAP_HALF + (iz + rng.randf()) * GRID_STEP)
			var roll := rng.randf()
			var model := _pick(TerrainMask.sample(spot), roll)
			if model.is_empty():
				continue
			if TerrainMask.near_path(spot, PATH_MARGIN, 0.05) or not ForestDresser.clear(spot):
				continue
			probe.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * (SOLID_CHECK_RADIUS + 0.1))
			if not space.intersect_shape(probe, 1).is_empty():
				continue
			var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * rng.randf_range(model[2], model[3]))
			for part in ForestDresser.model_parts(model[0]):
				FoliageBatcher.add(part[0], Transform3D(basis, spot) * part[1])
			placed += 1
			spots.append(spot)
	FoliageBatcher.build(get_parent(), "WorldDetailBatches")
	is_scattered = true
	scattered.emit()


## What grows at a spot with these ground weights, for this roll (or nothing).
func _pick(ground: Color, roll: float) -> Array:
	var table: Array
	if ground.a > 0.35:
		table = VERGE
	elif ground.b > 0.45:
		table = FOREST_FLOOR
	elif ground.r > 0.6:
		table = CLEARING
	else:
		return []
	for entry in table:
		roll -= entry[1]
		if roll < 0.0:
			return entry
	return []


## The terrain's collision bodies (they are the ground, not obstacles).
func _terrain_bodies() -> Array[RID]:
	var rids: Array[RID] = []
	var scene := get_tree().current_scene
	if not scene:
		return rids
	for terrain in scene.find_children("*", "TerraBrush", true, false):
		for body in terrain.find_children("*", "CollisionObject3D", true, false):
			rids.append((body as CollisionObject3D).get_rid())
	return rids
