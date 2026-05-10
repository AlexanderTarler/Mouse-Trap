extends ColorRect

## "Feeling watched" visual effect overlay.
## Shows a pulsing vignette and subtle distortion when the entity is near.
## The more intense the watching, the stronger the effect.

@export var min_opacity: float = 0.0
@export var max_opacity: float = 0.4
@export var pulse_speed: float = 2.0

var _watch_intensity: float = 0.0
var _pulse_phase: float = 0.0

func _ready() -> void:
	# Make this cover the full screen
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0, 0, 0, 0)
	
	# Connect to entity manager
	var em = get_node_or_null("/root/EntityManager")
	if em:
		em.player_watched.connect(_on_player_watched)

func _on_player_watched(intensity: float) -> void:
	_watch_intensity = intensity

func _process(delta: float) -> void:
	if _watch_intensity <= 0.01:
		color = Color(0, 0, 0, 0)
		return
	
	_pulse_phase += delta * pulse_speed
	
	# Pulse the vignette based on watch intensity
	var pulse = 0.5 + sin(_pulse_phase) * 0.5
	var alpha = lerp(min_opacity, max_opacity, _watch_intensity) * pulse
	
	# Tint shifts toward purple/red at high intensity
	var tint = Color(
		0.1 * _watch_intensity,
		0.0,
		0.05 * _watch_intensity,
		alpha
	)
	color = tint
