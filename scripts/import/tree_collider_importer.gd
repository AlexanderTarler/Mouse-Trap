@tool
extends EditorScenePostImport

func _post_import(scene: Node) -> Object:
	if scene and scene is Node3D:
		var static_body := StaticBody3D.new()
		static_body.name = "StaticBody3D"
		
		var collision_shape := CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		
		var cylinder := CylinderShape3D.new()
		cylinder.height = 8.0   # Average height of retro trees
		cylinder.radius = 0.3   # Slender trunk radius
		
		collision_shape.shape = cylinder
		collision_shape.position.y = 4.0 # Lift up so it sits on the ground
		
		static_body.add_child(collision_shape)
		scene.add_child(static_body)
		
		# Set proper editor ownership so it builds into the scene resource cleanly
		static_body.owner = scene
		collision_shape.owner = scene
		
	return scene
