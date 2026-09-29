class_name EntityStateDormant
extends EntityState

## Hidden and inactive. Nothing happens until something activates it.


func enter(_from: int, _data: Dictionary) -> void:
	perception.reset_memory()
	brain.target_entry = null


func update(_delta: float) -> void:
	entity.stop()


func reacts_to_flashlight() -> bool:
	return false


func reacts_to_lamp() -> bool:
	return false
