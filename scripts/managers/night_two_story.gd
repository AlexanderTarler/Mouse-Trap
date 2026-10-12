extends Node
## NightTwoStory (autoload): the beats of Night 2.2 (the car alarm and the
## chase) that belong to no one object:
##   - reaching the cabin with the Entity on their heels:
##     "What the FUCK was that?!"

const CHECK_INTERVAL := 0.25
const INSIDE_THOUGHT_DELAY := 1.0

var _check_left := 0.0
var _inside_pending := false


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_INTERVAL
	if not _inside_pending and not Monologue.has_thought("n22_inside") and _chased_inside():
		_inside_pending = true
		get_tree().create_timer(INSIDE_THOUGHT_DELAY).timeout.connect(_think_inside)


func _think_inside() -> void:
	_inside_pending = false
	Monologue.think("What the FUCK was that?!", null, 4.0, "n22_inside")


## The van chase is on and the player has made it inside the cabin.
func _chased_inside() -> bool:
	var entity := get_tree().get_first_node_in_group("entity")
	if entity == null or not entity.get("van_chase_active"):
		return false
	var player := get_tree().get_first_node_in_group("player")
	return player != null and player.has_method("get_player_room") and player.get_player_room() != "Outside"
