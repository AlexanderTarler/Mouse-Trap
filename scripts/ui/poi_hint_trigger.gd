extends Area3D
class_name PoiHintTrigger

## Trigger a thought when player enters, with optional highlighting.
## One-shot: fires only once.

@export var hint_text: String = ""
@export var highlight_group: String = ""
@export var one_shot: bool = true

var _triggered: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _triggered and one_shot:
		return

	if not body.is_in_group("player"):
		return

	_triggered = true

	var rm := get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("_muse"):
		rm._muse(hint_text, hint_text.to_lower().replace(" ", "_"), 0.0)

	if highlight_group:
		var routine := get_node_or_null("/root/RoutineManager")
		if routine and routine.has_method("highlight_target"):
			routine.highlight_target(highlight_group)
