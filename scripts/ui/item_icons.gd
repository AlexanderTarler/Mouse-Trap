class_name ItemIcons
extends Node
## Pictures for the inventory and the stash, made from each item's own 3D
## model (no icon art needed): rendered once, in a small off-screen viewport
## with its own world and light, then kept.
##
##   var icon := ItemIcons.icon_for(item)   # null until it's ready
##   ItemIcons.instance().icon_ready.connect(refresh)
##
## The model is the item's scene_to_spawn, or MODELS by name for items that
## have none. Only its meshes are copied (no scripts run, nothing falls).
## Items without a model, and the headless test runs (nothing is drawn),
## keep their text labels.

signal icon_ready(item_name: String)

const SIZE := 128
const MODELS := {
	"Battery": "res://scenes/battery.tscn",
	"Wooden Plank": "res://scenes/wooden_plank.tscn",
	"Fuse": "res://scenes/fuse.tscn",
	"Portable Light": "res://scenes/portable_light.tscn",
	"Car Battery": "res://assets/PSX Mega Pack/Models/GLB (recommended)/Small Props/car_battery_1.glb",
	"Arvid's Note 2": "res://scenes/note.tscn",
	"Scrap of Paper": "res://scenes/note.tscn",
}

static var _instance: ItemIcons = null
var _icons := {}       ## item name -> Texture2D (null: no picture possible)
var _queue: Array = []
var _busy := false


static func instance() -> ItemIcons:
	if not is_instance_valid(_instance):
		var tree := Engine.get_main_loop() as SceneTree
		_instance = ItemIcons.new()
		_instance.name = "ItemIcons"
		tree.root.add_child.call_deferred(_instance)
	return _instance


## The item's picture, or null (not ready yet, or none possible). Asking
## starts rendering it; icon_ready says when it's there.
static func icon_for(item) -> Texture2D:
	if item == null or DisplayServer.get_name() == "headless":
		return null
	var me := instance()
	var key: String = item.item_name
	if me._icons.has(key):
		return me._icons[key]
	var path := _model_path(item)
	if path == "":
		me._icons[key] = null
		return null
	if not me._queue.any(func(job): return job[0] == key):
		me._queue.append([key, path])
		me._next.call_deferred()
	return null


static func _model_path(item) -> String:
	if MODELS.has(item.item_name):
		return MODELS[item.item_name]
	if item.get("scene_to_spawn") and item.scene_to_spawn.resource_path != "":
		return item.scene_to_spawn.resource_path
	return ""


func _next() -> void:
	if _busy or _queue.is_empty() or not is_inside_tree():
		return
	_busy = true
	var job: Array = _queue.pop_front()
	var texture := await _render(job[1])
	_icons[job[0]] = texture
	_busy = false
	if texture:
		icon_ready.emit(job[0])
	_next()


## The model's meshes, framed from above and to the side, on a clear
## background.
func _render(path: String) -> Texture2D:
	var packed := load(path) as PackedScene
	if not packed:
		return null
	var source := packed.instantiate()
	var model := Node3D.new()
	_copy_meshes(source, Transform3D.IDENTITY, model)
	source.free()
	if model.get_child_count() == 0:
		model.free()
		return null
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var world := World3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.72, 0.68)
	env.ambient_light_energy = 0.9
	world.environment = env
	viewport.world_3d = world
	add_child(viewport)
	viewport.add_child(model)
	var box := _bounds(model)
	var light := DirectionalLight3D.new()
	light.light_energy = 1.3
	viewport.add_child(light)
	light.look_at_from_position(box.get_center() + Vector3(2, 3, 2), box.get_center(), Vector3.UP)
	var camera := Camera3D.new()
	camera.fov = 30.0
	viewport.add_child(camera)
	var radius := maxf(box.size.length() * 0.5, 0.05)
	var distance := radius / tan(deg_to_rad(camera.fov * 0.5)) * 1.12
	var view_dir := Vector3(1.0, 0.85, 1.25).normalized()
	camera.near = maxf(distance * 0.05, 0.01)
	camera.far = distance * 4.0
	camera.look_at_from_position(box.get_center() + view_dir * distance, box.get_center(), Vector3.UP)
	camera.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null or image.is_empty() or image.is_invisible():
		return null
	return ImageTexture.create_from_image(image)


## Copies every MeshInstance3D under `node` into `into`, keeping where it
## sits in the model (without running anything).
func _copy_meshes(node: Node, parent_xform: Transform3D, into: Node3D) -> void:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var source := node as MeshInstance3D
		var copy := MeshInstance3D.new()
		copy.mesh = source.mesh
		copy.material_override = source.material_override
		for i in source.get_surface_override_material_count():
			copy.set_surface_override_material(i, source.get_surface_override_material(i))
		copy.transform = xform
		into.add_child(copy)
	for child in node.get_children():
		_copy_meshes(child, xform, into)


func _bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in model.get_children():
		var b := mesh.transform * mesh.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
