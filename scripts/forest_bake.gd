class_name ForestBake
extends Resource
## The forest, dressed ahead of time (tools/bake_forest.gd): what ForestDresser
## and FoliageBatcher work out as the level starts (which tree goes where, the
## undergrowth, the trees cleared off the paths) costs most of a second there;
## this keeps the result, and the level draws the forest from it.
##
## It's only used while it matches the level: `inputs` is a hash of
## everything the dressing depends on (the groups and where they stand, the
## template, the painted paths, the road, the fence, the clear zones and the
## things kept clear of, ForestDresser's settings). If any of it has changed
## the forest is dressed as the level starts, as before, and a warning says to
## bake again. (Change how ForestDresser works without changing a setting:
## raise ForestDresser.BAKE_VERSION.)

const PATH := "res://scenes/forest_bake.res"

## The hash of what it was baked from (inputs_hash()).
@export var inputs := 0
## The batches: one entry per model ({"mesh": the source Mesh, "template":
## index in the template's mesh list or -1, "material_override",
## "cast_shadow", "layers", "small", "cells": {Vector2i: PackedFloat32Array of
## 12 floats per transform}}).
@export var entries: Array = []
## group node path (from the level) -> its trunks the dressing changed:
## [{"index", "disabled", "shape" (null: the template's), "transform" (in
## the group's Trunks body)}]
## (cleared off a path: turned off; in the clear-cut: a stump).
@export var trunk_changes: Dictionary = {}
@export var undergrowth_spots := PackedVector3Array()
@export var stone_spots: Array[Vector4] = []
@export var trees_cleared := 0
@export var clearcut_stumps := PackedVector3Array()

## The bake in use this run (null: dress as the level starts), checked once.
static var active: ForestBake = null
static var _checked := false
## Whether the last level started drew its forest from the bake.
static var last_used := false
## Set by the bake tool: dress as usual, whatever's baked; the inputs and
## the forest's batch list are kept for it (inputs_when_baked, captured).
static var baking := false
static var inputs_when_baked := 0
static var captured: Array = []


## The bake, if there is one and it matches the level (once per level start).
static func for_level(any_group: Node) -> ForestBake:
	if _checked:
		return active
	_checked = true
	active = null
	last_used = false
	if baking:
		inputs_when_baked = inputs_hash(any_group)
		return null
	if not ResourceLoader.exists(PATH):
		return null
	var bake := load(PATH) as ForestBake
	if not bake:
		return null
	var now := inputs_hash(any_group)
	if bake.inputs != now:
		push_warning("ForestBake: the level's forest has changed since it was baked: dressing it now (slower). Run tools/bake_forest.gd.")
		return null
	active = bake
	last_used = true
	ForestDresser.undergrowth_spots = bake.undergrowth_spots
	ForestDresser.stone_spots = bake.stone_spots
	ForestDresser.trees_cleared = bake.trees_cleared
	ForestDresser.clearcut_stumps = bake.clearcut_stumps
	return active


## Next level start, check again.
static func reset() -> void:
	_checked = false
	active = null


## A group's path in the level (the key in trunks_off).
static func key_of(group: Node) -> String:
	var scene := group.owner if group.owner else group.get_tree().current_scene
	return String(scene.get_path_to(group)) if scene else String(group.name)


## Everything the dressing depends on, hashed.
static func inputs_hash(any_group: Node) -> int:
	var parts := []
	parts.append(ForestDresser.BAKE_VERSION)
	parts.append(ForestDresser.settings())
	parts.append([GravelRoad.CENTRE_LINE, GravelRoad.WIDTH, GravelRoad.PULL_IN, GravelRoad.PULL_IN_WIDTH])
	parts.append([FoliageBatcher.CELL_SIZE, FoliageBatcher.SMALL_SIZE])
	var mask := TerrainMask.image()
	parts.append(hash(mask.get_data()) if mask else 0)
	# The groups: where, and what they're made of.
	var groups := []
	for batcher in any_group.get_tree().root.find_children("*", "FoliageBatcher", true, false):
		if batcher.template and batcher.dress_forest:
			groups.append([key_of(batcher), (batcher as Node3D).global_transform, batcher.template.resource_path])
	groups.sort_custom(func(a, b): return a[0] < b[0])
	parts.append(groups)
	if any_group.template:
		var data: Dictionary = any_group._template_data()
		var meshes := []
		for entry in data.meshes:
			meshes.append([entry.mesh.resource_path if entry.mesh else "", entry.chain, entry.batchable])
		parts.append(meshes)
		parts.append(data.trunks.map(func(t): return t.transform))
	# The things undergrowth keeps clear of.
	ForestDresser.refresh_interactables(any_group)
	parts.append(ForestDresser._interactables)
	return hash(var_to_str(parts))


## The bake of the level just dressed (in a baking run: captured, the
## inputs, ForestDresser's results; `trunk_changes` from the groups).
static func capture(trunk_changes: Dictionary) -> ForestBake:
	var bake := ForestBake.new()
	bake.inputs = inputs_when_baked
	bake.trunk_changes = trunk_changes
	for entry: Dictionary in captured:
		# Each cell's transforms as the MultiMesh buffer they become (relative
		# to the cell's middle, as FoliageBatcher builds them).
		var cells := {}
		for cell: Vector2i in entry.cells:
			var origin := Vector3((cell.x + 0.5) * FoliageBatcher.CELL_SIZE, 0.0, (cell.y + 0.5) * FoliageBatcher.CELL_SIZE)
			var floats := PackedFloat32Array()
			for xform: Transform3D in entry.cells[cell]:
				var o := xform.origin - origin
				var b := xform.basis
				floats.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z])
			cells[cell] = floats
		bake.entries.append({
			"mesh": entry.source_mesh,
			"template": entry.template_index,
			"material_override": entry.material_override,
			"cast_shadow": entry.source_cast_shadow,
			"layers": entry.layers,
			"small": entry.small,
			"cells": cells,
		})
	bake.undergrowth_spots = ForestDresser.undergrowth_spots
	bake.stone_spots = ForestDresser.stone_spots
	bake.trees_cleared = ForestDresser.trees_cleared
	bake.clearcut_stumps = ForestDresser.clearcut_stumps
	return bake


