@tool
extends EditorScenePostImport

func _post_import(scene: Node) -> Object:
	_process_nodes(scene)
	return scene # Returns the modified asset back to the editor

func _process_nodes(node: Node) -> void:
	if node is MeshInstance3D:
		# Mathematically wraps the mesh in a clean, lightweight static collider
		node.create_convex_collision(true, true)
	
	# Recursively search through any nested sub-meshes inside the model
	for child in node.get_children():
		_process_nodes(child)
