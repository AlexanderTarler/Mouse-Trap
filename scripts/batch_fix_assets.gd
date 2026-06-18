@tool
extends EditorScript

# SETTINGS: Point this to your asset folder
const ASSET_PATH = "C:/Users/Tarle/OneDrive/Dokument/3d-game-experiment/assets/PSX_Rural_Environment_Pack/PSX_Rural_E nvironment_Pack/EC/FBX/"
const OUTPUT_PATH = "res://assets/Fixed .fbx/"

func _run():
	var dir = DirAccess.open(ASSET_PATH)
	if not dir:
		printerr("Directory not found! Check ASSET_PATH.")
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		# Ensure we only process files, not hidden folders or .import files
		if file_name.ends_with(".fbx"):
			_process_fbx(ASSET_PATH + file_name)
		file_name = dir.get_next()
	print("--- Batch extraction complete! ---")

func _process_fbx(path: String):
	# 1. Load the messy FBX scene
	var messy_scene = load(path).instantiate()
	
	# 2. Find all meshes, no matter how deeply nested they are
	var found_meshes = []
	_find_meshes_recursive(messy_scene, found_meshes)
	
	if found_meshes.is_empty():
		print("Skipped (No meshes found): ", path.get_file())
		return
		
	# 3. Create a brand new, perfectly centered Root Node
	var clean_root = Node3D.new()
	clean_root.name = path.get_file().get_basename()
	
	# 4. Rip the meshes out and attach them to the clean root
	for mesh in found_meshes:
		# Duplicate the mesh so it loses all its messy parent offsets
		var clean_mesh = mesh.duplicate()
		clean_root.add_child(clean_mesh)
		clean_mesh.owner = clean_root # Owner MUST be set for Godot to save it
		
		# 5. Force the position and scale to absolute zero/one
		clean_mesh.position = Vector3.ZERO
		clean_mesh.rotation = Vector3.ZERO
		clean_mesh.scale = Vector3.ONE

	# 6. Save the new, clean scene
	var packed_scene = PackedScene.new()
	packed_scene.pack(clean_root)
	ResourceSaver.save(packed_scene, OUTPUT_PATH + clean_root.name + ".tscn")
	print("Extracted and saved: ", clean_root.name, ".tscn")

# Recursive helper function to dig through nested folders/bones
func _find_meshes_recursive(node: Node, result: Array):
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_find_meshes_recursive(child, result)
