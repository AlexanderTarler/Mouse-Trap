extends Node3D

## PSX-style detail props generator.
## Creates low-poly decorative objects from the PSX Mega Pack Demo aesthetic.
## Since the actual model files are not available, this generates
## simple primitive-based props that match the PS1 horror style.

## Whether to generate props on ready
@export var generate_on_ready: bool = true

## Prop types to generate
@export var generate_candles: bool = true
@export var generate_barrels: bool = true
@export var generate_crates: bool = true
@export var generate_chairs: bool = true
@export var generate_tables: bool = true

## Number of each prop type
@export var candle_count: int = 4
@export var barrel_count: int = 2
@export var crate_count: int = 3
@export var chair_count: int = 2
@export var table_count: int = 1

func _ready() -> void:
	if generate_on_ready:
		_generate_props()

func _generate_props() -> void:
	if generate_candles:
		_generate_candles()
	if generate_barrels:
		_generate_barrels()
	if generate_crates:
		_generate_crates()
	if generate_chairs:
		_generate_chairs()
	if generate_tables:
		_generate_tables()

func _generate_candles() -> void:
	var positions = [
		Vector3(-1.5, 0, -2.5),
		Vector3(1.5, 0, -2.5),
		Vector3(-1.0, 0, -1.0),
		Vector3(1.0, 0, -1.0)
	]
	
	for i in range(min(candle_count, positions.size())):
		var pos = positions[i]
		var candle = _create_candle()
		candle.position = pos
		add_child(candle)

func _create_candle() -> Node3D:
	var root = Node3D.new()
	root.name = "Candle"
	
	# Candle body (cylinder)
	var body = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.04
	cylinder.bottom_radius = 0.05
	cylinder.height = 0.15
	cylinder.rings = 4
	cylinder.radial_segments = 6
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.85, 0.7, 1)
	mat.roughness = 0.8
	body.mesh = cylinder
	body.material_override = mat
	body.position = Vector3(0, 0.075, 0)
	root.add_child(body)
	
	# Flame
	var flame = MeshInstance3D.new()
	var flame_mesh = SphereMesh.new()
	flame_mesh.radius = 0.02
	flame_mesh.height = 0.06
	flame_mesh.rings = 4
	flame_mesh.radial_segments = 4
	
	var flame_mat = StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1, 0.6, 0.1, 1)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1, 0.6, 0.1, 1)
	flame_mat.emission_energy_multiplier = 2.0
	flame.mesh = flame_mesh
	flame.material_override = flame_mat
	flame.position = Vector3(0, 0.17, 0)
	flame.scale = Vector3(0.8, 1.2, 0.8)
	root.add_child(flame)
	
	# Small omni light for candle
	var light = OmniLight3D.new()
	light.light_color = Color(1, 0.6, 0.1, 1)
	light.light_energy = 0.5
	light.omni_range = 2.0
	light.position = Vector3(0, 0.2, 0)
	root.add_child(light)
	
	return root

func _generate_barrels() -> void:
	var positions = [
		Vector3(-2.0, 0, -3.5),
		Vector3(2.0, 0, -3.5)
	]
	
	for i in range(min(barrel_count, positions.size())):
		var pos = positions[i]
		var barrel = _create_barrel()
		barrel.position = pos
		add_child(barrel)

func _create_barrel() -> Node3D:
	var root = Node3D.new()
	root.name = "Barrel"
	
	var body = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.25
	cylinder.bottom_radius = 0.3
	cylinder.height = 0.5
	cylinder.rings = 4
	cylinder.radial_segments = 8
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.25, 0.15, 1)
	mat.roughness = 0.9
	body.mesh = cylinder
	body.material_override = mat
	body.position = Vector3(0, 0.25, 0)
	root.add_child(body)
	
	# Collision
	var col = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	var col_shape = CylinderShape3D.new()
	col_shape.radius = 0.3
	col_shape.height = 0.5
	shape.shape = col_shape
	shape.position = Vector3(0, 0.25, 0)
	col.add_child(shape)
	root.add_child(col)
	
	return root

func _generate_crates() -> void:
	var positions = [
		Vector3(-2.5, 0, -1.5),
		Vector3(2.5, 0, -1.5),
		Vector3(-2.0, 0, 0.5)
	]
	
	for i in range(min(crate_count, positions.size())):
		var pos = positions[i]
		var crate = _create_crate()
		crate.position = pos
		add_child(crate)

func _create_crate() -> Node3D:
	var root = Node3D.new()
	root.name = "Crate"
	
	var body = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.35, 0.2, 1)
	mat.roughness = 0.9
	body.mesh = box
	body.material_override = mat
	body.position = Vector3(0, 0.2, 0)
	root.add_child(body)
	
	# Collision
	var col = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	var col_shape = BoxShape3D.new()
	col_shape.size = Vector3(0.4, 0.4, 0.4)
	shape.shape = col_shape
	shape.position = Vector3(0, 0.2, 0)
	col.add_child(shape)
	root.add_child(col)
	
	return root

func _generate_chairs() -> void:
	var positions = [
		Vector3(-1.2, 0, -2.0),
		Vector3(1.2, 0, -2.0)
	]
	
	for i in range(min(chair_count, positions.size())):
		var pos = positions[i]
		var chair = _create_chair()
		chair.position = pos
		add_child(chair)

func _create_chair() -> Node3D:
	var root = Node3D.new()
	root.name = "Chair"
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.2, 0.1, 1)
	mat.roughness = 0.9
	
	# Seat
	var seat = MeshInstance3D.new()
	var seat_mesh = BoxMesh.new()
	seat_mesh.size = Vector3(0.3, 0.05, 0.3)
	seat.mesh = seat_mesh
	seat.material_override = mat
	seat.position = Vector3(0, 0.35, 0)
	root.add_child(seat)
	
	# Back
	var back = MeshInstance3D.new()
	var back_mesh = BoxMesh.new()
	back_mesh.size = Vector3(0.3, 0.3, 0.03)
	back.mesh = back_mesh
	back.material_override = mat
	back.position = Vector3(0, 0.5, -0.15)
	root.add_child(back)
	
	# Legs
	for x in [-0.12, 0.12]:
		for z in [-0.12, 0.12]:
			var leg = MeshInstance3D.new()
			var leg_mesh = BoxMesh.new()
			leg_mesh.size = Vector3(0.03, 0.3, 0.03)
			leg.mesh = leg_mesh
			leg.material_override = mat
			leg.position = Vector3(x, 0.15, z)
			root.add_child(leg)
	
	return root

func _generate_tables() -> void:
	var positions = [
		Vector3(0, 0, -2.0)
	]
	
	for i in range(min(table_count, positions.size())):
		var pos = positions[i]
		var table = _create_table()
		table.position = pos
		add_child(table)

func _create_table() -> Node3D:
	var root = Node3D.new()
	root.name = "Table"
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.25, 0.15, 1)
	mat.roughness = 0.9
	
	# Table top
	var top = MeshInstance3D.new()
	var top_mesh = BoxMesh.new()
	top_mesh.size = Vector3(0.8, 0.05, 0.5)
	top.mesh = top_mesh
	top.material_override = mat
	top.position = Vector3(0, 0.45, 0)
	root.add_child(top)
	
	# Legs
	for x in [-0.35, 0.35]:
		for z in [-0.2, 0.2]:
			var leg = MeshInstance3D.new()
			var leg_mesh = BoxMesh.new()
			leg_mesh.size = Vector3(0.04, 0.4, 0.04)
			leg.mesh = leg_mesh
			leg.material_override = mat
			leg.position = Vector3(x, 0.2, z)
			root.add_child(leg)
	
	# Collision
	var col = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	var col_shape = BoxShape3D.new()
	col_shape.size = Vector3(0.8, 0.5, 0.5)
	shape.shape = col_shape
	shape.position = Vector3(0, 0.25, 0)
	col.add_child(shape)
	root.add_child(col)
	
	return root
