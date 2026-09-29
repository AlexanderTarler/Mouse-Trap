class_name EntitySwing
extends RefCounted

## Repeating attack swing (windows, fuse box, portable lamp): plays
## AttackWindow and reports the impact frame, `impact_delay` seconds into
## each swing, one swing every `interval` seconds.

const ANIM_TIME := 1.2

var interval: float
var impact_delay: float
var _cooldown := 0.3
var _impact := -1.0
var _anim := 0.0


func _init(swing_interval: float, swing_impact_delay: float) -> void:
	interval = swing_interval
	impact_delay = swing_impact_delay


## Advances the swing. Returns true on the frame the blow lands.
func update(delta: float, entity: Entity) -> bool:
	var landed := false
	if _impact >= 0.0:
		_impact -= delta
		if _impact < 0.0:
			landed = true
	else:
		_cooldown -= delta
		if _cooldown <= 0.0:
			_cooldown = interval
			_impact = impact_delay
			_anim = ANIM_TIME
	if _anim > 0.0:
		_anim -= delta
		entity.play_anim(&"AttackWindow")
	return landed
