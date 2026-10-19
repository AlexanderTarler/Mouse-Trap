class_name ClockTick
extends AudioStreamPlayer3D
## The hall clock ticking (WorldDetails puts it on the clock in CabinDetails):
## barely there by day, plain at night, when the cabin is quiet and the
## player is counting the hours to dawn.

const STREAM := "res://assets/audio/house/Clock.wav"
## Where the hall clock hangs, if it's not in the level.
const FALLBACK := Vector3(5.8, 2.4, 8.2)
const DAY_DB := -30.0
const NIGHT_DB := -17.0


func _ready() -> void:
	bus = &"SFX"
	unit_size = 2.5
	max_distance = 16.0
	if ResourceLoader.exists(STREAM):
		stream = load(STREAM)
	volume_db = DAY_DB
	if stream and not Engine.is_editor_hint():
		play()


func _process(_delta: float) -> void:
	var gt := get_node_or_null("/root/GameTime")
	var night: bool = gt != null and not gt.is_day
	volume_db = move_toward(volume_db, NIGHT_DB if night else DAY_DB, 0.2)
