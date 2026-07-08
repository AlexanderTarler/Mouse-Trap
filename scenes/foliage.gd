extends MultiMeshInstance3D

@export_subgroup("Scatter Bounds")
@export var min_bounds: Vector2 = Vector2(-50.0, -50.0) # Top-left X and Z limits
@export var max_bounds: Vector2 = Vector2(50.0, 50.0)   # Bottom-right X and Z limits

@export_subgroup("Grass Variation")
@export var min_scale: float = 0.75
@export var max_scale: float = 1.35

func _ready() -> void:
	# Fallback check to prevent engine exceptions if the resource isn't set up
	if not multimesh:
		push_error("MultiMesh resource is missing from this node!")
		return
	
	# Duplicate the MultiMesh resource so runtime changes don't serialize back to the .tscn
	multimesh = multimesh.duplicate()
		
	# Randomize the seed generation
	randomize()
	
	# Loop through every pre-allocated instance index 
	for i in range(multimesh.instance_count):
		var xf := Transform3D()
		
		# 1. Calculate a random position across the X and Z ground planes
		var random_x: float = randf_range(min_bounds.x, max_bounds.x)
		var random_z: float = randf_range(min_bounds.y, max_bounds.y)
		
		# Optional Raycast: If your ground is uneven or bumpy, you'll want to 
		# snap the Y coordinate to the height of the terrain. For now, we assume flat 0.0 ground:
		var target_position := Vector3(random_x, 0.0, random_z)
		
		# 2. Add structural variety: Give each instance a random rotation around the Y axis
		# This avoids a repetitive grid-like appearance
		var random_rotation: float = randf_range(0.0, TAU) # TAU is 360 degrees in radians
		xf = xf.rotated(Vector3.UP, random_rotation)
		
		# 3. Add biological variety: Slightly scale each individual patch up or down
		var random_scale: float = randf_range(min_scale, max_scale)
		xf = xf.scaled(Vector3(random_scale, random_scale, random_scale))
		
		# 4. Inject the calculated position coordinates into our temporary matrix
		xf.origin = target_position
		
		# 5. Commit this individual matrix setup directly to the GPU's instance buffer
		multimesh.set_instance_transform(i, xf)
