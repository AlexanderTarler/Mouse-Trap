class_name KnockableProp
extends RigidBody3D

## A small loose thing (a book, an ashtray, a bottle) that can be knocked
## over: by the Entity passing it unseen (EntityWorld.loose_prop_near), or
## picked up and moved with the grab. `model` is any scene; a box collider
## is sized to it when the prop loads. It starts asleep, so it stays exactly
## where it was placed until something touches it.

@export var model: PackedScene
@export var prop_mass: float = 0.6


func _ready() -> void:
	mass = prop_mass
	add_to_group("knockable")
	if model and get_node_or_null("Model") == null:
		var instance := model.instantiate()
		instance.name = "Model"
		add_child(instance)
	var box := _bounds()
	if box.size != Vector3.ZERO:
		var shape := BoxShape3D.new()
		shape.size = box.size.max(Vector3.ONE * 0.03)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = box.get_center()
		add_child(collider)
	sleeping = true


## The model's meshes, in this body's space.
func _bounds() -> AABB:
	var box := AABB()
	var first := true
	var to_local := global_transform.affine_inverse()
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var b := (to_local * mesh.global_transform) * mesh.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
