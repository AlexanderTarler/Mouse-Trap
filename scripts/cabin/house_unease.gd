class_name HouseUnease
extends Node3D
## The cabin turning on the player, night by night: the house settling and
## groaning, a cabinet shutting, a door creaking, a handle tried. In a room
## away from the player, and never where the Entity really is (the house
## isn't there to tell lies about it, only to wear the nerves). Night 1 hardly
## anything, Night 2 now and then, Night 3 on, often. Only at night, with the
## player in or near the cabin, never in a cutscene. WorldDetails adds it.

const HOUSE := "res://assets/audio/house/"
## [file, dB, from which night].
const SOUNDS := [
	["Old House_creeky metal and wood_ambiance_7.wav", -10.0, 1],
	["res://assets/audio/objects/Floor Creak.ogg", -8.0, 1],
	["Cabinet_shut.wav", -12.0, 2],
	["Door_squeeky_2.wav", -13.0, 2],
	["Door_handle_jiggle_checking if locked.wav", -15.0, 3],
]
## Seconds between them, by night (Night 3 and later use the last).
const GAPS := [Vector2(150.0, 240.0), Vector2(60.0, 120.0), Vector2(30.0, 60.0)]
## Kept this far (m) from the player and from the Entity.
const AWAY_FROM_PLAYER := 6.0
const AWAY_FROM_ENTITY := 6.0
## Only with the player within this of the cabin.
const CABIN := Vector3(9.0, 0.0, 15.0)
const NEAR_CABIN := 30.0

var _left := 0.0
var _night := -1
var _player3d: AudioStreamPlayer3D
var _streams: Array = []
## How many it has played (for the tests).
var played := 0
var last_spot := Vector3.INF


func _ready() -> void:
	_player3d = AudioStreamPlayer3D.new()
	_player3d.name = "HouseSound"
	_player3d.bus = &"SFX"
	_player3d.unit_size = 5.0
	_player3d.max_distance = 30.0
	add_child(_player3d)
	for entry in SOUNDS:
		var path: String = entry[0] if String(entry[0]).begins_with("res://") else HOUSE + entry[0]
		_streams.append(load(path) if ResourceLoader.exists(path) else null)


func _process(delta: float) -> void:
	var nm := get_node_or_null("/root/NightManager")
	if nm == null or not nm.is_night_active or _in_cutscene():
		_night = -1
		return
	if nm.current_night != _night:
		_night = nm.current_night
		_left = _gap()
	_left -= delta
	if _left > 0.0:
		return
	_left = _gap()
	creak()


func _gap() -> float:
	var gap: Vector2 = GAPS[clampi(_night - 1, 0, GAPS.size() - 1)]
	return randf_range(gap.x, gap.y)


func _in_cutscene() -> bool:
	var em := get_node_or_null("/root/EndgameManager")
	return em != null and "is_sequence_playing" in em and em.is_sequence_playing


## One of tonight's sounds in a room away from the player and the Entity.
## False if there's nowhere (or the player's far from the cabin).
func creak() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var entity := get_tree().get_first_node_in_group("entity") as Node3D
	if player == null or Vector2(player.global_position.x - CABIN.x, player.global_position.z - CABIN.z).length() > NEAR_CABIN:
		return false
	var spot := _spot(player, entity)
	if spot == Vector3.INF:
		return false
	var choices: Array[int] = []
	for i in SOUNDS.size():
		if _streams[i] and maxi(_night, 1) >= int(SOUNDS[i][2]):
			choices.append(i)
	if choices.is_empty():
		return false
	var pick: int = choices.pick_random()
	_player3d.global_position = spot
	_player3d.stream = _streams[pick]
	_player3d.volume_db = SOUNDS[pick][1]
	_player3d.pitch_scale = randf_range(0.9, 1.05)
	_player3d.play()
	played += 1
	last_spot = spot
	Caption.at(self, "the house creaks", spot)
	return true


func _spot(player: Node3D, entity: Node3D) -> Vector3:
	var centres: Array = []
	if entity and entity.get("world") and entity.world.has_method("room_centers"):
		centres = entity.world.room_centers()
	var good: Array[Vector3] = []
	for centre: Vector3 in centres:
		if centre.distance_to(player.global_position) < AWAY_FROM_PLAYER:
			continue
		if entity and entity.visible and centre.distance_to(entity.global_position) < AWAY_FROM_ENTITY:
			continue
		good.append(centre)
	return good.pick_random() if not good.is_empty() else Vector3.INF
