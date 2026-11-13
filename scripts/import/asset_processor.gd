@tool
extends EditorScenePostImport

## Post-import processor for the VadaCross Forest Meadows asset pack.
##
## PROBLEM:
##   These FBX models contain a solid-red vertex color channel that Godot
##   multiplies against the albedo texture when vertex_color_use_as_albedo
##   is true (the default). This produces a flat, alien red render.
##
## SOLUTION:
##   Set vertex_color_use_as_albedo = false on every material at import time
##   and PERSIST the change via ResourceSaver. This works because the
##   materials/extract=1 setting in the .import files causes Godot to write
##   each material as a standalone .tres file, which we can then save to.
##
## CAVEAT:
##   This runs AFTER Godot has already generated the extracted .tres files.
##   If the .tres files don't exist yet (first import after extract=1 was
##   set), the materials will still be embedded. In that case we just set
##   the flag in memory and let the next editor save cycle persist it.

func _post_import(scene):
	_fix_all_materials(scene)
	return scene


func _fix_all_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh = node.mesh
		if mesh:
			for i in range(mesh.get_surface_count()):
				var mat = mesh.surface_get_material(i)
				if mat is BaseMaterial3D:
					# Only fix if vertex colors are currently overriding albedo
					if mat.vertex_color_use_as_albedo:
						mat.vertex_color_use_as_albedo = false
						
						# Try to persist the change back to disk.
						var path = mat.resource_path
						if path and path.ends_with(".tres"):
							ResourceSaver.save(mat, path)
							print("[asset_processor] Fixed + saved: ", path)
						else:
							print("[asset_processor] Fixed in-memory (no .tres path yet): surface ", i)

	# Recurse into all children
	for child in node.get_children():
		_fix_all_materials(child)
