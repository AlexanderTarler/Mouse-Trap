class_name FoliageBatcher
extends Node3D
## Draws the forest as a few big batches instead of one object per mesh.
## On a tree group (trees.tscn: pines, ferns, grass clumps, rocks, bushes) or
## a border block (world_map_border_block.tscn). The forest is ~26,000
## meshes; drawn one by one (and again for every shadow split) they were most
## of the frame.
##
## When the game starts every group hands its meshes to one shared list, and
## at the end of that frame they are rebuilt as one MultiMesh per model per
## CELL_SIZE square of the map (so off-screen squares are still skipped).
## With dress_forest, ForestDresser first varies the group's trees and adds
## undergrowth.
##
## Small plants and rocks cast no shadows and fade out beyond
## SMALL_DRAW_DISTANCE. See-through foliage (the pine branches are "alpha +
## depth pre-pass", blended) is drawn as alpha scissor instead: hard cut-out
## edges (PSX-style) through the opaque path, so trees hide the trees behind
## them instead of every layer of needles being shaded. The groups stay
## editable tree by tree in the editor, and their colliders are left alone.

## Side of the map squares the batches are built per (m).
const CELL_SIZE := 25.0
## Meshes smaller than this (their bounding box diagonal, m) are "small".
const SMALL_SIZE := 5.0
## Small meshes fade out beyond this distance (m), at Medium quality
## (GraphicsQuality.plant_distance() is the one used).
const SMALL_DRAW_DISTANCE := 60.0

## Off: draw every mesh separately, as authored.
@export var batch_on_ready: bool = true
## Vary this group's trees and grow undergrowth (ForestDresser).
@export var dress_forest: bool = false

## model key -> {"mesh", "material_override", "cast_shadow", "layers", "name",
## "small", "cells": {Vector2i: Array[Transform3D]}}
static var _pending := {}
static var _flush_scheduled := false
## material -> its alpha-scissor copy
static var _scissor := {}
## mesh -> the mesh as drawn (scissor materials)
static var _drawn := {}
## Meshes always drawn as small (no shadows, fading out beyond
## SMALL_DRAW_DISTANCE) whatever their size: the forest's young pines
## (ForestDresser), which only matter up close.
static var _always_small := {}


func _ready() -> void:
	if batch_on_ready and not Engine.is_editor_hint():
		collect()


## Hands this group's meshes to the shared list and removes them.
func collect() -> void:
	var replaced := {}
	if dress_forest:
		replaced = ForestDresser.dress(self, _add_mesh)
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if replaced.has(mesh_instance):
			_free_with_empty_parent(mesh_instance)
			continue
		if not _batchable(mesh_instance):
			continue
		var key := _key(mesh_instance)
		if not _pending.has(key):
			var small := mesh_instance.mesh.get_aabb().size.length() * mesh_instance.global_basis.get_scale().x < SMALL_SIZE
			_pending[key] = _entry(_mesh_with_overrides(mesh_instance), mesh_instance.material_override,
				mesh_instance.cast_shadow, mesh_instance.layers, small)
		_place(key, mesh_instance.global_transform)
		_free_with_empty_parent(mesh_instance)
	if not _flush_scheduled:
		_flush_scheduled = true
		_build.call_deferred(_batch_parent(), "ForestBatches")


## Batches `mesh` at `xform` along with everything else waiting to be
## batched (WorldDetails), built by build(): a MultiMesh per model per cell.
static func add(mesh: Mesh, xform: Transform3D) -> void:
	_add_mesh(mesh, xform)


## Draws `mesh` as small from now on (see _always_small).
static func draw_as_small(mesh: Mesh) -> void:
	_always_small[mesh] = true


## True while the forest's own batches are still waiting to be built.
static func is_build_scheduled() -> bool:
	return _flush_scheduled


## Builds everything waiting (add) into batches under `parent` now.
static func build(parent: Node, holder_name: String) -> void:
	_build(parent, holder_name)


## A mesh to draw at `xform` that has no node of its own (ForestDresser).
static func _add_mesh(mesh: Mesh, xform: Transform3D) -> void:
	var key := [mesh]
	if not _pending.has(key):
		var small := _always_small.has(mesh) or mesh.get_aabb().size.length() * xform.basis.get_scale().x < SMALL_SIZE
		_pending[key] = _entry(_drawn_mesh(mesh), null, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, 1, small)
	_place(key, xform)


static func _entry(mesh: Mesh, material_override: Material, cast_shadow: int, layers: int, small: bool) -> Dictionary:
	return {
		"mesh": mesh,
		"material_override": material_override,
		"cast_shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if small else cast_shadow,
		"layers": layers,
		"name": mesh.resource_name,
		"small": small,
		"cells": {},
	}


static func _place(key: Array, xform: Transform3D) -> void:
	var cell := Vector2i(floori(xform.origin.x / CELL_SIZE), floori(xform.origin.z / CELL_SIZE))
	var cells: Dictionary = _pending[key].cells
	if not cells.has(cell):
		cells[cell] = []
	cells[cell].append(xform)


## Frees a batched mesh, and the model's wrapper node it came in if that is
## left empty (the forest's ~26,000 wrappers otherwise stay in the scene).
func _free_with_empty_parent(mesh_instance: MeshInstance3D) -> void:
	var parent := mesh_instance.get_parent()
	mesh_instance.queue_free()
	if parent and parent != self and parent.get_class() == "Node3D" and parent.get_script() == null \
			and parent.get_child_count() == 1 and not parent.is_queued_for_deletion():
		parent.queue_free()


## Where the batches go: the scene being played.
func _batch_parent() -> Node:
	var scene := get_tree().current_scene
	return scene if scene and scene.is_ancestor_of(self) else get_parent()


static func _build(parent: Node, holder_name: String) -> void:
	_flush_scheduled = false
	if not is_instance_valid(parent):
		_pending.clear()
		return
	var holder := Node3D.new()
	holder.name = holder_name
	parent.add_child(holder)
	holder.global_transform = Transform3D.IDENTITY
	for key in _pending:
		var entry: Dictionary = _pending[key]
		for cell in entry.cells:
			var transforms: Array = entry.cells[cell]
			var origin := Vector3((cell.x + 0.5) * CELL_SIZE, 0.0, (cell.y + 0.5) * CELL_SIZE)
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = entry.mesh
			multimesh.instance_count = transforms.size()
			for i in transforms.size():
				var xform: Transform3D = transforms[i]
				xform.origin -= origin
				multimesh.set_instance_transform(i, xform)
			var batch := MultiMeshInstance3D.new()
			batch.name = "%s_%d_%d" % [String(entry.name).validate_node_name(), cell.x, cell.y]
			batch.multimesh = multimesh
			batch.material_override = entry.material_override
			batch.cast_shadow = entry.cast_shadow
			batch.layers = entry.layers
			if entry.small:
				batch.visibility_range_end = GraphicsQuality.plant_distance()
				batch.visibility_range_end_margin = 8.0
				batch.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			batch.position = origin
			holder.add_child(batch)
	_pending.clear()


## Plain, visible, static meshes only (no skinning, scripts or per-object
## visibility ranges).
func _batchable(mesh_instance: MeshInstance3D) -> bool:
	return mesh_instance.mesh != null and mesh_instance.is_visible_in_tree() \
		and mesh_instance.get_script() == null and mesh_instance.skin == null \
		and mesh_instance.visibility_range_end <= 0.0 and not mesh_instance.is_queued_for_deletion()


## Meshes batch together when they look the same: same mesh, same materials,
## same shadow and layer settings.
func _key(mesh_instance: MeshInstance3D) -> Array:
	var key: Array = [mesh_instance.mesh, mesh_instance.material_override, mesh_instance.cast_shadow, mesh_instance.layers]
	for surface in mesh_instance.get_surface_override_material_count():
		key.append(mesh_instance.get_surface_override_material(surface))
	return key


## The mesh as it will be drawn: a MultiMesh has no per-surface material
## overrides, so they are baked into a copy of the mesh, and blended foliage
## becomes alpha scissor (a copy is only made when something changes).
func _mesh_with_overrides(mesh_instance: MeshInstance3D) -> Mesh:
	var mesh := mesh_instance.mesh
	var materials: Array[Material] = []
	for surface in mesh.get_surface_count():
		materials.append(_cut_out(mesh_instance.get_active_material(surface)))
	return _with_materials(mesh, materials)


## A mesh with its own materials, blended foliage made alpha scissor.
static func _drawn_mesh(mesh: Mesh) -> Mesh:
	if not _drawn.has(mesh):
		var materials: Array[Material] = []
		for surface in mesh.get_surface_count():
			materials.append(_cut_out(mesh.surface_get_material(surface)))
		_drawn[mesh] = _with_materials(mesh, materials)
	return _drawn[mesh]


static func _with_materials(mesh: Mesh, materials: Array[Material]) -> Mesh:
	var changed := false
	for surface in materials.size():
		if materials[surface] != mesh.surface_get_material(surface):
			changed = true
	if not changed:
		return mesh
	var copy := mesh.duplicate() as Mesh
	for surface in materials.size():
		copy.surface_set_material(surface, materials[surface])
	return copy


## An alpha-blended material with a cut-off threshold -> an alpha-scissor copy.
static func _cut_out(material: Material) -> Material:
	var base := material as BaseMaterial3D
	if not base or not (base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
			or base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS):
		return material
	if not _scissor.has(base):
		var copy := base.duplicate() as BaseMaterial3D
		copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		copy.alpha_scissor_threshold = base.alpha_scissor_threshold if base.alpha_scissor_threshold > 0.0 else 0.5
		_scissor[base] = copy
	return _scissor[base]
