extends Node

## One-time batch tool to add CylinderShape3D collision bodies to trees.tscn.
## Run this script ONCE from the editor (Scene > Run Script) to permanently
## bake collision into the scene file.
## After running, delete this script — the collision is permanent.

func _run() -> void:
	var scene_path := "res://scenes/trees.tscn"
	var scene := load(scene_path) as PackedScene
	if not scene:
		push_error("Could not load ", scene_path)
		return
	
	var root := scene.instantiate() as Node3D
	if not root:
		push_error("Could not instantiate scene")
		return
	
	print("[BATCH_COLL] Loaded trees.tscn with ", root.get_child_count(), " children")
	
	var added := 0
	for child in root.get_children():
		if child is Node3D and child.name.begins_with("pine_tree"):
			# Skip if collision body already exists
			var collision_name := child.name + "_coll"
			if root.has_node(collision_name):
				print("[BATCH_COLL] Skipping ", child.name, " — collision already exists")
				continue
			
			# Create StaticBody3D
			var body := StaticBody3D.new()
			body.name = collision_name
			body.transform = child.transform
			
			# Create CylinderShape3D
			var shape := CylinderShape3D.new()
			shape.radius = 0.5
			shape.height = 8.0
			
			# Create CollisionShape3D
			var col := CollisionShape3D.new()
			col.name = "CollisionShape3D"
			col.shape = shape
			col.position = Vector3(0, 4.0, 0)
			
			body.add_child(col)
			col.owner = body
			
			root.add_child(body)
			body.owner = root
			added += 1
	
	print("[BATCH_COLL] Added ", added, " collision bodies")
	
	# Save back to scene
	var result := PackedScene.new()
	result.pack(root)
	ResourceSaver.save(result, scene_path)
	print("[BATCH_COLL] Saved to ", scene_path)
	print("[BATCH_COLL] DONE — collision bodies are now baked into the scene file permanently.")
	get_tree().quit()