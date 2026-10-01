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
## Small plants and rocks stop casting shadows (they barely show, and cost a
## draw per shadow split). See-through foliage (the pine branches are
## "alpha + depth pre-pass", blended) is drawn as alpha scissor instead: hard
## cut-out edges (PSX-style) through the opaque path, so trees hide the trees
## behind them instead of every layer of needles being shaded. The groups stay editable tree by tree in the
## editor, and their colliders are left alone.

## Side of the map squares the batches are built per (m).
const CELL_SIZE := 25.0
## Meshes smaller than this (their bounding box diagonal, m) cast no shadow.
const SHADOW_MIN_SIZE := 5.0

## Off: draw every mesh separately, as authored.
@export var batch_on_ready: bool = true

## model key -> {"mesh", "material_override", "cast_shadow", "layers",
## "name", "cells": {Vector2i: Array[Transform3D]}}
static var _pending := {}
static var _flush_scheduled := false
## material -> its alpha-scissor copy
static var _scissor := {}


func _ready() -> void:
	if batch_on_ready and not Engine.is_editor_hint():
		collect()


## Hands this group's meshes to the shared list and removes them.
func collect() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if not _batchable(mesh_instance):
			continue
		var key := _key(mesh_instance)
		if not _pending.has(key):
			var size := mesh_instance.mesh.get_aabb().size.length() * mesh_instance.global_basis.get_scale().x
			_pending[key] = {
				"mesh": _mesh_with_overrides(mesh_instance),
				"material_override": mesh_instance.material_override,
				"cast_shadow": mesh_instance.cast_shadow if size >= SHADOW_MIN_SIZE else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"layers": mesh_instance.layers,
				"name": mesh_instance.mesh.resource_name,
				"cells": {},
			}
		var xform := mesh_instance.global_transform
		var cell := Vector2i(floori(xform.origin.x / CELL_SIZE), floori(xform.origin.z / CELL_SIZE))
		var cells: Dictionary = _pending[key].cells
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(xform)
		_free_with_empty_parent(mesh_instance)
	if not _flush_scheduled:
		_flush_scheduled = true
		_build.call_deferred(_batch_parent())


## Frees a batched mesh, and the model's wrapper node it came in if that is
## left empty (the forest's ~26,000 wrappers otherwise stay in the scene).
func _free_with_empty_parent(mesh_instance: MeshInstance3D) -> void:
	var parent := mesh_instance.get_parent()
	mesh_instance.queue_free()
	if parent and parent != self and parent.get_class() == "Node3D" and parent.get_script() == null 			and parent.get_child_count() == 1 and not parent.is_queued_for_deletion():
		parent.queue_free()


## Where the batches go: the scene being played.
func _batch_parent() -> Node:
	var scene := get_tree().current_scene
	return scene if scene and scene.is_ancestor_of(self) else get_parent()


static func _build(parent: Node) -> void:
	_flush_scheduled = false
	if not is_instance_valid(parent):
		_pending.clear()
		return
	var holder := Node3D.new()
	holder.name = "ForestBatches"
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
	var changed := false
	for surface in mesh.get_surface_count():
		var material := mesh_instance.get_active_material(surface)
		var drawn := _cut_out(material)
		materials.append(drawn)
		if drawn != mesh.surface_get_material(surface):
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
	if not base or not (base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA 			or base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS):
		return material
	if not _scissor.has(base):
		var copy := base.duplicate() as BaseMaterial3D
		copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		copy.alpha_scissor_threshold = base.alpha_scissor_threshold if base.alpha_scissor_threshold > 0.0 else 0.5
		_scissor[base] = copy
	return _scissor[base]
