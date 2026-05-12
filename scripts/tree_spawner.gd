extends Node3D

@export var tree_scenes: Array[PackedScene] # Use an Array so you can have different tree types!
@export var tree_count: int = 100
@export var ring_distance: float = 50.0
@export var position_jitter: float = 15.0

# Road Gap Settings
@export var road_angle: float = 0.0 # Direction of the road (0 is East)
@export var road_gap_width: float = 0.8 # Width of the "no tree" zone

func _ready() -> void:
	_spawn_trees()

func _spawn_trees() -> void:
	for i in range(tree_count):
		var angle = randf_range(0, TAU)
		
		# ROAD GAP LOGIC
		# Checks if the random angle is inside the road's "slice"
		var angle_diff = abs(wrapf(angle - road_angle, -PI, PI))
		if angle_diff < road_gap_width:
			continue
			
		var x = cos(angle) * (ring_distance + randf_range(-position_jitter, position_jitter))
		var z = sin(angle) * (ring_distance + randf_range(-position_jitter, position_jitter))
		
		# Pick a random tree from your array
		var tree_resource = tree_scenes.pick_random()
		var tree = tree_resource.instantiate()
		add_child(tree)
		
		tree.global_position = Vector3(x, -3, z) # Set Y to 0 or your ground height
		tree.rotation.y = randf_range(0, TAU)
		
		# AUTOMATIC COLLIDER (If the model doesn't have one)
		_ensure_collider(tree)

func _ensure_collider(tree_node: Node3D):
	# This checks if the tree already has a StaticBody3D. 
	# If not, it adds a simple Cylinder collider.
	if not tree_node.find_child("*StaticBody3D*", true):
		var static_body = StaticBody3D.new()
		var collision_shape = CollisionShape3D.new()
		var cylinder = CylinderShape3D.new()
		
		cylinder.height = 10.0 # Adjust to your tree height
		cylinder.radius = 0.5  # Adjust to your trunk width
		
		collision_shape.shape = cylinder
		static_body.add_child(collision_shape)
		tree_node.add_child(static_body)
		# Move the collider slightly up so it's not halfway in the ground
		collision_shape.position.y = 5.0
