class_name FenceGate
extends AnimatableBody3D
## The barn yard's gate: E swings it open (into the yard) or shut. It turns
## on its hinge (this node's origin, at the post). The Entity doesn't wait
## for it: coming close to a shut gate, it shoves it open.
##
## The gate isn't part of the navmesh source (only the fence is), so the
## navmesh has a way through here whether it is open or shut.

## How far it swings open (degrees; negative swings it into the yard).
@export var open_angle: float = -95.0
@export var swing_time: float = 0.9
## The Entity this close (m) to a shut gate bursts it open.
@export var entity_push_distance: float = 3.5

const OPEN_SOUND := "res://assets/audio/horror_sfx_vol_1/Creaking Door/Creaking Door (3).mp3"
const SLAM_SOUND := "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Impacts/impact_3.ogg"
const LATCH_SOUND := "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Misc/hit_2.ogg"

var is_open := false
var _closed_y := 0.0
var _tween: Tween = null
var _audio: AudioStreamPlayer3D = null
var _entity: Node3D = null


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("fence_gate")
	_closed_y = rotation.y
	_audio = AudioStreamPlayer3D.new()
	_audio.bus = &"SFX"
	_audio.unit_size = 6.0
	_audio.max_distance = 35.0
	_audio.position = Vector3(1.8, -0.8, 0.0)
	add_child(_audio)


func get_interact_text() -> String:
	return "[E] Close Gate" if is_open else "[E] Open Gate"


func interact() -> void:
	set_open(not is_open)


func set_open(open: bool, forced: bool = false) -> void:
	if open == is_open:
		return
	is_open = open
	if _tween and _tween.is_valid():
		_tween.kill()
	var time := swing_time * (0.4 if forced else 1.0)
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if forced else Tween.EASE_IN_OUT)
	_tween.tween_property(self, "rotation:y", _closed_y + (deg_to_rad(open_angle) if open else 0.0), time)
	if not open:
		_tween.tween_callback(_play.bind(LATCH_SOUND, 0.9, -4.0))
	if forced:
		_play(SLAM_SOUND, 1.1, 0.0)
	elif open:
		_play(OPEN_SOUND, 1.15, -6.0)
	else:
		_play(OPEN_SOUND, 1.3, -9.0)


func _physics_process(_delta: float) -> void:
	if is_open:
		return
	if not is_instance_valid(_entity):
		_entity = get_tree().get_first_node_in_group("entity") as Node3D
		if not _entity:
			return
	if not _entity.is_visible_in_tree() or _entity.process_mode == Node.PROCESS_MODE_DISABLED:
		return
	var middle := global_transform * Vector3(1.8, 0.0, 0.0)
	if Vector2(_entity.global_position.x - middle.x, _entity.global_position.z - middle.z).length() < entity_push_distance:
		set_open(true, true)


func _play(path: String, pitch: float, volume_db: float) -> void:
	if not ResourceLoader.exists(path):
		return
	_audio.stream = load(path)
	_audio.pitch_scale = pitch
	_audio.volume_db = volume_db
	_audio.play()
