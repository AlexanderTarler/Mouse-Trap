class_name NoiseEvent

## Noises the Entity can hear. Any game system reports one with
##   NoiseEvent.emit(self, global_position, &"door")
## The kind picks how far it carries (EntityConfig.noise_radius, tunable in
## the Entity config's Hearing group); the Entity works out walls, openings
## and distance itself.
##
## Kinds: walk, sprint, crouch (footsteps), land, hammer, door, drop, click.


static func emit(source: Node, position: Vector3, kind: StringName) -> void:
	if not source or not source.is_inside_tree():
		return
	var entity := source.get_tree().get_first_node_in_group("entity")
	if entity and entity.has_method("hear_noise"):
		entity.hear_noise(position, kind)
