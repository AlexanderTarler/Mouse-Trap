@tool
extends EditorScript

## Batch fix for the VadaCross Forest Meadows asset pack.
##
## Walks all .fbx files under the VadaCross directory, instantiates each one,
## and creates a fixed .tscn with vertex_color_use_as_albedo = false on all
## materials. The fixed scenes are saved to assets/fixed_scenes/.
##
## This is a FALLBACK tool — the primary fix is the .import file change
## (materials/extract=1) combined with asset_processor.gd. Use this if you
## need to regenerate scenes without reimporting.

const SOURCE_DIR = "res://assets/PSX Forest Meadows by VadaCross/3D Models/"
const TARGET_DIR = "res://assets/fixed_scenes/"

## Recursively collected .fbx file paths.
var _fbx_files: Array[String] = []


func _run() -> void:
	_collect_fbx_files(SOURCE_DIR)
	
	if _fbx_files.is_empty():
		push_error("Batch fix: No .fbx files found in " + SOURCE_DIR)
		return
	
	if not DirAccess.dir_exists_absolute(TARGET_DIR):
		DirAccess.make_dir_absolute(TARGET_DIR)
	
	var processed_count = 0
	for fbx_path in _fbx_files:
		var file_name = fbx_path.get_file()
		var target_scene_name = file_name.get_basename() + ".tscn"
		var target_path = TARGET_DIR + target_scene_name
		
		if _extract_and_sanitize_mesh(fbx_path, target_path):
			processed_count += 1
	
	print("Batch fix processed %d assets." % processed_count)


func _collect_fbx_files(dir_path: String) -> void:
	var dir = DirAccess.open(dir_path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and entry != "." and entry != "..":
			_collect_fbx_files(dir_path.path_join(entry))
		elif entry.get_extension().to_lower() == "fbx":
			_fbx_files.append(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()


func _extract_and_sanitize_mesh(source_fbx_path: String, save_scene_path: String) -> bool:
	var fbx_scene = load(source_fbx_path)
	if not fbx_scene or not fbx_scene is PackedScene:
		push_error("Batch fix: Failed to load " + source_fbx_path)
		return false
	
	var fbx_instance = fbx_scene.instantiate()
	if not fbx_instance:
		return false
	
	var target_mesh_node: MeshInstance3D = _find_mesh_instance_recursive(fbx_instance)
	if not target_mesh_node:
		print("Batch fix: No MeshInstance3D found in " + source_fbx_path + " — skipping.")
		fbx_instance.free()
		return false
	
	# Build a clean root layout
	var pristine_root = Node3D.new()
	pristine_root.name = fbx_instance.name
	
	var clean_mesh = MeshInstance3D.new()
	clean_mesh.name = target_mesh_node.name
	clean_mesh.mesh = target_mesh_node.mesh
	pristine_root.add_child(clean_mesh)
	clean_mesh.owner = pristine_root
	
	# Apply the vertex color fix
	if clean_mesh.mesh:
		for i in range(clean_mesh.mesh.get_surface_count()):
			var old_mat = target_mesh_node.get_active_material(i)
			var source_texture: Texture2D = null
			
			if old_mat is BaseMaterial3D:
				source_texture = old_mat.albedo_texture
			
			var clean_mat = StandardMaterial3D.new()
			clean_mat.vertex_color_use_as_albedo = false
			clean_mat.vertex_color_is_srgb = false
			clean_mat.albedo_color = Color.WHITE
			
			if source_texture:
				clean_mat.albedo_texture = source_texture
			
			clean_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			clean_mesh.set_surface_override_material(i, clean_mat)
	
	var packed_scene = PackedScene.new()
	var result = packed_scene.pack(pristine_root)
	
	fbx_instance.free()
	
	if result == OK:
		ResourceSaver.save(packed_scene, save_scene_path)
		pristine_root.free()
		return true
	else:
		pristine_root.free()
		return false


func _find_mesh_instance_recursive(current_node: Node) -> MeshInstance3D:
	if current_node is MeshInstance3D:
		return current_node
	for child in current_node.get_children():
		var found = _find_mesh_instance_recursive(child)
		if found:
			return found
	return null
