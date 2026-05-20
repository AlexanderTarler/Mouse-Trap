extends Node3D

## Debug visualization for the cabin floor area.
## Enable by setting show_cabin_area = true in the inspector.
## The red sphere marks the center, the yellow ring marks the radius boundary.
## Use this to calibrate the cabin_center and cabin_radius values used by
## the player's footstep surface detection system.

@export var show_cabin_area: bool = false:
	set(value):
		show_cabin_area = value
		if show_cabin_area:
			_draw_area()
		else:
			_clear_area()

@export var cabin_center: Vector3 = Vector3(0.0, 0.0, 14.88)
@export var cabin_radius: float = 15.0

var _debug_node: Node3D = null


func _ready() -> void:
	if show_cabin_area:
		_draw_area()


func _draw_area() -> void:
	_clear_area()
	
	_debug_node = Node3D.new()
	_debug_node.name = "CabinAreaDebug"
	_debug_node.global_position = cabin_center
	add_child(_debug_node)
	
	# Center marker: red sphere
	var center_marker = MeshInstance3D.new()
	center_marker.mesh = SphereMesh.new()
	center_marker.mesh.radius = 0.3
	center_marker.mesh.height = 0.6
	var center_mat = StandardMaterial3D.new()
	center_mat.albedo_color = Color(1, 0, 0, 0.8)
	center_marker.material_override = center_mat
	_debug_node.add_child(center_marker)
	
	# Radius ring: yellow spheres around the perimeter
	var num_markers = 24
	for i in range(num_markers):
		var angle = TAU * i / num_markers
		var pos = Vector3(cos(angle) * cabin_radius, 0.1, sin(angle) * cabin_radius)
		var marker = MeshInstance3D.new()
		marker.mesh = SphereMesh.new()
		marker.mesh.radius = 0.15
		marker.mesh.height = 0.3
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1, 1, 0, 0.6)
		marker.material_override = mat
		marker.position = pos
		_debug_node.add_child(marker)
	
	print("[CabinDebug] Area visualization created at %s with radius %.1f" % [cabin_center, cabin_radius])


func _clear_area() -> void:
	if _debug_node:
		_debug_node.queue_free()
		_debug_node = null
