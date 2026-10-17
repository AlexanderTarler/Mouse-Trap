@tool
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
## them instead of every layer of needles being shaded.
##
## A tree group's contents live in a template (trees_template.tscn: edit the
## trees there), not in the group: the level has ~150 groups of ~270 nodes,
## and making all of those only to take them apart again was most of the
## level's loading. The first group to start reads the template once (its
## meshes and where they sit, its trunk colliders, its grass); every group
## then batches from that, and gets its trunks as one body ("Trunks") and its
## grass. In the editor a group shows the template's trees as a preview (not
## saved with the level).

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
## What the group is made of (trees_template.tscn), read instead of being
## instanced.
@export var template: PackedScene = null

## template -> what it's made of: {"meshes": [...], "trunks": [...],
## "others": [Node, ...]} (_read_template)
static var _templates := {}

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


## (Every group's trunks are up before any group starts dressing: all of
## them enter the tree before the first is ready, and ForestDresser looks at
## them all.)
func _enter_tree() -> void:
	if template and not Engine.is_editor_hint() and not _built:
		_built = true
		_build_from_template()


var _built := false


func _ready() -> void:
	if Engine.is_editor_hint():
		if template:
			# The trees, to see and place the group by (not saved).
			add_child(template.instantiate(), false, Node.INTERNAL_MODE_FRONT)
		return
	if not batch_on_ready:
		return
	# The forest dressed ahead of time, if it matches (ForestBake).
	if template and dress_forest:
		var bake := ForestBake.for_level(self)
		if bake:
			_use_bake(bake)
			return
	collect()


static var _bake_added := false


## From the bake: this group's trunks that were cleared, and (the first
## group) the whole forest's batches.
func _use_bake(bake: ForestBake) -> void:
	var body := get_node_or_null("Trunks")
	if body:
		for change in bake.trunk_changes.get(ForestBake.key_of(self), []):
			if change.index < body.get_child_count():
				var shape := body.get_child(change.index) as CollisionShape3D
				shape.disabled = change.disabled
				if change.shape:
					shape.shape = change.shape
				shape.transform = change.transform
	if _bake_added:
		return
	_bake_added = true
	var data := _template_data()
	for baked in bake.entries:
		var key: Array
		var drawn: Mesh
		if baked.template >= 0:
			key = data.meshes[baked.template].key
			drawn = data.meshes[baked.template].drawn
		else:
			key = [baked.mesh]
			drawn = _drawn_mesh(baked.mesh)
		var entry := _entry(drawn, baked.material_override, baked.cast_shadow, baked.layers, baked.small, true, baked.mesh, baked.template)
		entry["buffers"] = baked.cells
		_pending[key] = entry
	if not _flush_scheduled:
		_flush_scheduled = true
		_build.call_deferred(_batch_parent(), "ForestBatches")


## The template's contents, read once (from a copy made for the moment).
func _template_data() -> Dictionary:
	if _templates.has(template):
		return _templates[template]
	# (Read outside the tree: added and freed at once, its meshes' drawing
	# was left behind.)
	var root := template.instantiate() as Node3D
	var meshes := []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var batchable := _batchable_in(mesh_instance, root)
		meshes.append({
			"mesh": mesh_instance.mesh,
			"chain": _chain(mesh_instance, root),
			"batchable": batchable,
			"key": _key(mesh_instance) if batchable else [],
			"drawn": _mesh_with_overrides(mesh_instance) if batchable else null,
			"material_override": mesh_instance.material_override,
			"cast_shadow": mesh_instance.cast_shadow,
			"layers": mesh_instance.layers,
			"size": mesh_instance.mesh.get_aabb().size.length() if mesh_instance.mesh else 0.0,
			"copy": null if batchable else _packed(mesh_instance),
		})
	var trunks := []
	var props := []
	var others: Array[PackedScene] = []
	for child in root.get_children():
		if child is StaticBody3D:
			for shape in child.get_children():
				if shape is CollisionShape3D:
					trunks.append({
						"shape": (shape as CollisionShape3D).shape,
						"transform": (child as Node3D).transform * (shape as Node3D).transform,
						"disabled": (shape as CollisionShape3D).disabled,
						"layer": (child as CollisionObject3D).collision_layer,
						"mask": (child as CollisionObject3D).collision_mask,
					})
		elif child.find_children("*", "MeshInstance3D", true, false).is_empty() and not child is MeshInstance3D:
			others.append(_packed(child))
		else:
			# A model's own collider (the fallen log's): solid, but no trunk.
			for body in child.find_children("*", "StaticBody3D", true, false):
				for shape in body.get_children():
					if shape is CollisionShape3D:
						props.append({
							"shape": (shape as CollisionShape3D).shape,
							"chain": _chain(shape, root),
							"disabled": (shape as CollisionShape3D).disabled,
							"layer": (body as CollisionObject3D).collision_layer,
							"mask": (body as CollisionObject3D).collision_mask,
						})
	root.free()
	_templates[template] = {"meshes": meshes, "trunks": trunks, "props": props, "others": others}
	return _templates[template]


## A copy of `node` (and what's under it) to make again later. (Kept packed:
## a node kept outside the tree would be left over when the game closes.)
func _packed(node: Node) -> PackedScene:
	var copy := node.duplicate()
	for child in copy.find_children("*", "", true, false):
		child.owner = copy
	var packed := PackedScene.new()
	packed.pack(copy)
	copy.free()
	return packed


## The transforms from the template's root down to `node` (its own last).
func _chain(node: Node, root: Node) -> Array[Transform3D]:
	var chain: Array[Transform3D] = []
	var walk := node
	while walk and walk != root:
		if walk is Node3D:
			chain.push_front((walk as Node3D).transform)
		walk = walk.get_parent()
	return chain


## Where a template mesh stands in the world for this group: composed parent
## by parent, as the engine would have.
func _placed(chain: Array) -> Transform3D:
	var xform := global_transform
	for step: Transform3D in chain:
		xform = xform * step
	return xform


## The group's trunks (one body for all of them, per collision layer) and
## its grass; meshes that can't be batched as copies of their own.
func _build_from_template() -> void:
	var data := _template_data()
	var bodies := {}
	for trunk in data.trunks:
		var layers := Vector2i(trunk.layer, trunk.mask)
		if not bodies.has(layers):
			var body := StaticBody3D.new()
			body.name = "Trunks" if bodies.is_empty() else "Trunks%d" % bodies.size()
			body.collision_layer = trunk.layer
			body.collision_mask = trunk.mask
			add_child(body)
			bodies[layers] = body
		var shape := CollisionShape3D.new()
		shape.shape = trunk.shape
		shape.transform = trunk.transform
		shape.disabled = trunk.disabled
		bodies[layers].add_child(shape)
	if not data.props.is_empty():
		var holder := Node3D.new()
		holder.name = "Props"
		add_child(holder)
		for prop in data.props:
			var body := StaticBody3D.new()
			body.collision_layer = prop.layer
			body.collision_mask = prop.mask
			holder.add_child(body)
			body.global_transform = _placed(prop.chain)
			var shape := CollisionShape3D.new()
			shape.shape = prop.shape
			shape.disabled = prop.disabled
			body.add_child(shape)
	for other: PackedScene in data.others:
		add_child(other.instantiate())
	for entry in data.meshes:
		if entry.copy:
			var copy := (entry.copy as PackedScene).instantiate() as Node3D
			add_child(copy)
			copy.global_transform = _placed(entry.chain)


## Hands this group's meshes to the shared list and removes them.
func collect() -> void:
	if template:
		_collect_template()
		return
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


## collect() for a group made from a template: the same, from the template's
## list instead of nodes.
func _collect_template() -> void:
	var data := _template_data()
	var placed := []
	for entry in data.meshes:
		placed.append([entry.mesh, _placed(entry.chain)])
	var replaced := {}
	if dress_forest:
		replaced = ForestDresser.dress_list(self, placed, _add_mesh)
	for i in data.meshes.size():
		var entry: Dictionary = data.meshes[i]
		if replaced.has(i) or not entry.batchable:
			continue
		var xform: Transform3D = placed[i][1]
		var key: Array = entry.key
		if not _pending.has(key):
			var small: bool = entry.size * xform.basis.get_scale().x < SMALL_SIZE
			_pending[key] = _entry(entry.drawn, entry.material_override, entry.cast_shadow, entry.layers, small, true, entry.mesh, i)
		_place(key, xform)
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
		_pending[key] = _entry(_drawn_mesh(mesh), null, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, 1, small, true, mesh)
	_place(key, xform)


## (`forest`, `source_mesh` and `template_index`: how to make it again, for
## ForestBake.)
static func _entry(mesh: Mesh, material_override: Material, cast_shadow: int, layers: int, small: bool,
		forest := false, source_mesh: Mesh = null, template_index := -1) -> Dictionary:
	return {
		"mesh": mesh,
		"material_override": material_override,
		"cast_shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if small else cast_shadow,
		"source_cast_shadow": cast_shadow,
		"layers": layers,
		"name": mesh.resource_name,
		"small": small,
		"cells": {},
		"forest": forest,
		"source_mesh": source_mesh,
		"template_index": template_index,
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
	if holder_name == "ForestBatches":
		if ForestBake.baking:
			ForestBake.captured = _pending.values().filter(func(e): return e.forest)
		# (The next level start looks at the bake afresh, and reads the
		# template again: nothing of it held on to meanwhile.)
		ForestBake.reset()
		_bake_added = false
		_templates.clear()
	if not is_instance_valid(parent):
		_pending.clear()
		return
	var holder := Node3D.new()
	holder.name = holder_name
	parent.add_child(holder)
	holder.global_transform = Transform3D.IDENTITY
	for key in _pending:
		var entry: Dictionary = _pending[key]
		# (Baked: each cell's instances ready as a MultiMesh buffer.)
		var cells: Dictionary = entry.buffers if entry.has("buffers") else entry.cells
		for cell in cells:
			var origin := Vector3((cell.x + 0.5) * CELL_SIZE, 0.0, (cell.y + 0.5) * CELL_SIZE)
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = entry.mesh
			if entry.has("buffers"):
				var buffer: PackedFloat32Array = cells[cell]
				multimesh.instance_count = buffer.size() / 12
				multimesh.buffer = buffer
			else:
				var transforms: Array = cells[cell]
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


## _batchable() for a mesh in a template copy that isn't in the tree.
func _batchable_in(mesh_instance: MeshInstance3D, root: Node) -> bool:
	var walk: Node = mesh_instance
	while walk and walk != root:
		if walk is Node3D and not (walk as Node3D).visible:
			return false
		walk = walk.get_parent()
	return mesh_instance.mesh != null and mesh_instance.get_script() == null and mesh_instance.skin == null 		and mesh_instance.visibility_range_end <= 0.0


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
