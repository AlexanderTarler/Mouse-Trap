extends Node
## Weather (autoload): a rainstorm. It breaks after the player documents Nest
## Gamma (hasselmus_nest.gd), so the long walk back to the cabin happens in
## a downpour: rain streaking down around them, the hiss of it (muffled
## indoors by the Ambient bus), a grey, darker sky,
## and now and then lightning and a roll of thunder. It eases off once they
## are back inside the cabin, or after STORM_DURATION.
##
## The kit has no rain recording: the rain is synthesized (filtered noise
## with droplet ticks); the thunder is the kit's distant explosions, pitched
## down.

const THUNDER_PATHS: Array[String] = [
	"res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Explosions/explosion_distant_1.ogg",
	"res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Explosions/explosion_distant_2.ogg",
	"res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Explosions/explosion_distant_3.ogg",
	"res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Explosions/explosion_distant_4.ogg",
]
## Seconds the storm lasts at most.
const STORM_DURATION := 300.0
## Seconds to build up and to die away.
const FADE_IN := 12.0
const FADE_OUT := 20.0
## Back inside for this long and the storm starts easing off.
const INSIDE_ENDS_AFTER := 8.0
## Seconds between lightning strikes.
const THUNDER_INTERVAL := Vector2(14.0, 32.0)
const RAIN_DB := -6.0
const MIX_RATE := 22050.0

## 0 = clear, 1 = full storm.
var level := 0.0
var _target := 0.0
var _storm_left := 0.0
var _inside_time := 0.0
var _thunder_left := 0.0
var _rain_particles: GPUParticles3D = null
var _rain_player: AudioStreamPlayer = null
var _rain_playback: AudioStreamGeneratorPlayback = null
var _thunder_player: AudioStreamPlayer = null
var _thunder_streams: Array[AudioStream] = []
var _flash: DirectionalLight3D = null
var _noise_state := 0.0
var _noise_slow := 0.0


func _ready() -> void:
	for path in THUNDER_PATHS:
		if ResourceLoader.exists(path):
			_thunder_streams.append(load(path))


func is_raining() -> bool:
	return level > 0.01


## The storm breaks (building up over FADE_IN seconds).
func start_storm(duration: float = STORM_DURATION) -> void:
	if _target > 0.0:
		return
	_target = 1.0
	_storm_left = duration
	_inside_time = 0.0
	_thunder_left = randf_range(4.0, 9.0)
	print("[Weather] A storm breaks.")


## Clear skies at once (a checkpoint from before the storm was restored).
func clear_now() -> void:
	_target = 0.0
	level = 0.0
	_tear_down()


## The storm eases off (over FADE_OUT seconds).
func stop_storm() -> void:
	_target = 0.0


func _process(delta: float) -> void:
	if _target <= 0.0 and level <= 0.0:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if _target > 0.0:
		_storm_left -= delta
		var inside: bool = player != null and player.has_method("get_player_room") and player.get_player_room() != "Outside"
		_inside_time = _inside_time + delta if inside else 0.0
		if _storm_left <= 0.0 or _inside_time > INSIDE_ENDS_AFTER:
			stop_storm()
	var rate := 1.0 / FADE_IN if _target > level else 1.0 / FADE_OUT
	level = move_toward(level, _target, rate * delta)
	_apply(player, delta)
	if level <= 0.0 and _target <= 0.0:
		_tear_down()


func _apply(player: Node3D, delta: float) -> void:
	var environment := get_tree().get_first_node_in_group("environment_controller")
	if environment and "weather" in environment and not is_equal_approx(environment.weather, level):
		environment.weather = level
	_ensure_rain()
	if _rain_particles and player:
		_rain_particles.global_position = player.global_position + Vector3.UP * 14.0
		# It rains around the player wherever they are: the drops stop on the
		# roof (the height-field collision), so from inside the cabin the
		# rain is seen through the windows, not falling indoors.
		_rain_particles.emitting = level > 0.05
		_rain_particles.amount_ratio = level
	if _rain_player:
		_rain_player.volume_db = linear_to_db(maxf(level, 0.0001)) + RAIN_DB
		_fill_rain()
	_thunder_left -= delta
	if _thunder_left <= 0.0 and level > 0.5 and _target > 0.0:
		_thunder_left = randf_range(THUNDER_INTERVAL.x, THUNDER_INTERVAL.y)
		_strike()


## Lightning, then (sound being slower than light) the thunder.
func _strike() -> void:
	var scene := get_tree().current_scene
	if not scene:
		return
	if not _flash:
		_flash = DirectionalLight3D.new()
		_flash.name = "LightningFlash"
		_flash.light_color = Color(0.8, 0.85, 1.0)
		_flash.rotation_degrees = Vector3(-60.0, randf() * 360.0, 0.0)
		_flash.light_energy = 0.0
		scene.add_child(_flash)
	var flicker := create_tween()
	for burst in [1.4, 0.0, 2.2, 0.3, 0.0]:
		flicker.tween_property(_flash, "light_energy", burst * level, 0.06)
	var distance := randf_range(0.6, 3.5)
	get_tree().create_timer(distance).timeout.connect(_thunder.bind(distance))


func _thunder(distance: float) -> void:
	if _thunder_streams.is_empty() or level <= 0.0:
		return
	if not _thunder_player:
		_thunder_player = AudioStreamPlayer.new()
		_thunder_player.bus = &"Ambient"
		add_child(_thunder_player)
	_thunder_player.stream = _thunder_streams.pick_random()
	# Closer strikes are louder and sharper.
	_thunder_player.pitch_scale = randf_range(0.42, 0.6)
	_thunder_player.volume_db = lerpf(4.0, -6.0, distance / 3.5)
	_thunder_player.play()


func _ensure_rain() -> void:
	var scene := get_tree().current_scene
	if not scene:
		return
	if not is_instance_valid(_rain_particles):
		_rain_particles = _make_rain()
		scene.add_child(_rain_particles)
	if not _rain_player:
		_rain_player = AudioStreamPlayer.new()
		_rain_player.bus = &"Ambient"
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = MIX_RATE
		generator.buffer_length = 0.25
		_rain_player.stream = generator
		add_child(_rain_player)
		_rain_player.play()
		_rain_playback = _rain_player.get_stream_playback()


func _make_rain() -> GPUParticles3D:
	var rain := GPUParticles3D.new()
	rain.name = "Rain"
	rain.top_level = true
	rain.amount = 8000
	rain.lifetime = 1.1
	rain.preprocess = 1.0
	rain.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 30, 40))
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(16.0, 0.5, 16.0)
	process.direction = Vector3(0.08, -1.0, 0.05)
	process.spread = 3.0
	process.initial_velocity_min = 16.0
	process.initial_velocity_max = 20.0
	process.gravity = Vector3(0, -9.8, 0)
	process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	rain.process_material = process
	var streak := QuadMesh.new()
	streak.size = Vector2(0.018, 0.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.75, 0.8, 0.9, 0.45)
	streak.material = material
	rain.draw_pass_1 = streak
	# Drops stop at the ground and on roofs (the cabin's included).
	var floor_collider := GPUParticlesCollisionHeightField3D.new()
	floor_collider.size = Vector3(40, 30, 40)
	floor_collider.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	floor_collider.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	floor_collider.follow_camera_enabled = true
	rain.add_child(floor_collider)
	return rain


## Rain: brownish noise (the hiss) with sparse sharper ticks (drops close by).
func _fill_rain() -> void:
	if not _rain_playback:
		return
	var frames := _rain_playback.get_frames_available()
	for i in frames:
		var white := randf() * 2.0 - 1.0
		_noise_state = _noise_state * 0.82 + white * 0.18
		_noise_slow = _noise_slow * 0.995 + white * 0.005
		var sample := _noise_state * 0.6 + _noise_slow * 2.0
		if randf() < 0.0025:
			sample += (randf() * 2.0 - 1.0) * 0.5
		_rain_playback.push_frame(Vector2(sample, sample) * 0.5)


func _tear_down() -> void:
	if is_instance_valid(_rain_particles):
		_rain_particles.queue_free()
	_rain_particles = null
	if _rain_player:
		_rain_player.queue_free()
		_rain_player = null
		_rain_playback = null
	if is_instance_valid(_flash):
		_flash.queue_free()
	_flash = null
	var environment := get_tree().get_first_node_in_group("environment_controller")
	if environment and "weather" in environment:
		environment.weather = 0.0
	print("[Weather] The storm has passed.")
