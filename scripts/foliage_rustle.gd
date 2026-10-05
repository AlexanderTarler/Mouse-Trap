class_name FoliageRustle
extends Node3D
## Walking into a bush, a fern, tall grass or a thistle rustles. Every plant
## of those kinds in the level is found once the forest has been batched
## (the batches, WorldDetails' scatter, and the plants left as their own
## meshes), kept in a grid by where it stands and how wide it is, and when
## the player moves into one a rustle plays there: leafy for shrubs and
## bushes, crackly for the bare twigs and dry thistles, a soft swish for
## grass, wheat and weeds. Sprinting is louder, crouching quieter; standing
## still in a bush is silent.
##
## Plants are also cover: crouched inside one at least COVER_HEIGHT tall,
## the Entity only sees the player from close by (EntityConfig
## bush_cover_range; EntityPerception asks in_cover()). The price: pushing
## through them makes a noise it can hear ("rustle", "rustle_crouch" in
## EntityConfig.noise_radius).
##
## The sound is a recording of brushing against bushes (BRUSH_SOUND), pitched
## per kind: lower for dry twigs, higher for grass. Without it, synthesized
## rustles stand in.

const BRUSH_SOUND := "res://assets/audio/objects/Brushing Against Bushes.ogg"
const KIND_PITCH := {"leafy": 1.0, "twiggy": 0.88, "grassy": 1.2}

## Mesh name (prefix) -> [kind, footprint scale]. The footprint is the
## mesh's width times this (a bush's leaves reach further than you'd brush).
const PLANTS := {
	"fern_1": ["leafy", 0.42],             # green shrub
	"fern_2": ["leafy", 0.42],             # flowering shrub
	"fern_3": ["twiggy", 0.36],            # bare twigs
	"tree_1": ["leafy", 0.25],             # sapling
	"SM_EC_Plant_Bush": ["leafy", 0.4],
	"SM_EC_Plant_Card_Cross": ["grassy", 0.9],
	"grass_2": ["grassy", 0.45],
	"grass_3": ["grassy", 0.45],
	"grass_4": ["grassy", 0.45],
	"wheat_1": ["grassy", 0.45],
	"SM_EC_Crop_0": ["grassy", 0.5],
}
## Meadow plants (all named Plane_*): by the model they come from.
const MEADOW_MODELS := {
	"Bush.fbx": ["leafy", 0.42],
	"Rasberry Bush.fbx": ["leafy", 0.42],
	"Blueberry Bush.fbx": ["leafy", 0.42],
	"Fern.fbx": ["leafy", 0.38],
	"Flowery Fern.fbx": ["leafy", 0.38],
	"Flowery_fern_asset": ["leafy", 0.38],
	"Thistles.fbx": ["twiggy", 0.45],
	"Wild Lavinder.fbx": ["leafy", 0.4],
}
const CELL := 4.0
## The player's body radius (m), added to each footprint.
const BODY := 0.3
## Moving slower than this (m/s) makes no sound.
const MIN_SPEED := 0.8
## While still moving inside the same plant, it rustles again this often (s).
const REPEAT := 0.55
const VOLUME_DB := {"leafy": -8.0, "twiggy": -9.0, "grassy": -15.0}
## Plants this tall (m) or taller hide a crouching player.
const COVER_HEIGHT := 0.7

## Vector2i cell -> Array of [Vector3 position, float radius, String kind, float height]
var _grid := {}
var count := 0
var counts := {}
var ready_to_play := false
var _sounds := {}
var _inside: Array = []
var _repeat := 0.0
var _rng := RandomNumberGenerator.new()
var _pool: Array[AudioStreamPlayer3D] = []
## (tests) the last rustle: [kind, position].
var last_rustle: Array = []


func _ready() -> void:
	add_to_group("foliage_rustle")
	if Engine.is_editor_hint():
		return
	_rng.seed = 11
	var brushing: AudioStream = load(BRUSH_SOUND) if ResourceLoader.exists(BRUSH_SOUND) else null
	for kind in VOLUME_DB:
		_sounds[kind] = []
		if brushing:
			_sounds[kind].append(brushing)
		else:
			for i in 4:
				_sounds[kind].append(_make_sound(kind))
	for i in 4:
		var player := AudioStreamPlayer3D.new()
		player.bus = &"SFX"
		player.unit_size = 4.0
		player.max_distance = 30.0
		add_child(player)
		_pool.append(player)
	# Wait for the forest's and WorldDetails' batches (WorldDetails is the
	# parent; it says when it's done).
	await get_tree().physics_frame
	var details := get_parent()
	if details and "is_scattered" in details and not details.is_scattered:
		await details.scattered
	while FoliageBatcher.is_build_scheduled():
		await get_tree().process_frame
	collect()


## Finds every plant that rustles.
func collect() -> void:
	_grid.clear()
	count = 0
	counts.clear()
	var scene := get_tree().current_scene
	if not scene:
		return
	for node in scene.find_children("*", "MultiMeshInstance3D", true, false):
		var batch := node as MultiMeshInstance3D
		var multimesh := batch.multimesh
		if not multimesh or not multimesh.mesh:
			continue
		var plant := _classify(multimesh.mesh, "")
		if plant.is_empty():
			continue
		var width := _width(multimesh.mesh)
		for i in multimesh.instance_count:
			var xform := batch.global_transform * multimesh.get_instance_transform(i)
			var scale := xform.basis.get_scale()
			_add(xform.origin, width * scale.x * plant[1], plant[0], multimesh.mesh.get_aabb().size.y * scale.y)
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if not mesh_instance.mesh or not mesh_instance.is_visible_in_tree():
			continue
		var plant := _classify(mesh_instance.mesh, _source_file(mesh_instance, scene))
		if plant.is_empty():
			continue
		var scale := mesh_instance.global_basis.get_scale()
		_add(mesh_instance.global_position, _width(mesh_instance.mesh) * maxf(scale.x, scale.z) * plant[1], plant[0],
			_height(mesh_instance.mesh, mesh_instance.global_basis))
	ready_to_play = true
	print("[FoliageRustle] %d plants rustle: %s" % [count, counts])


func _classify(mesh: Mesh, source: String) -> Array:
	var name := mesh.resource_name
	for prefix in PLANTS:
		if name.begins_with(prefix):
			return PLANTS[prefix]
	var path := mesh.resource_path
	for model in MEADOW_MODELS:
		if model in path or (source != "" and source == model):
			return MEADOW_MODELS[model]
	# Batched meadow plants lose their file path: the big Plane_* meshes are
	# the bushes (the small ones are flowers and ground grass, left out).
	if name.begins_with("Plane") and path == "" and source == "":
		var size := mesh.get_aabb().size
		if size.y >= 0.8 and maxf(size.x, size.z) >= 0.8 and maxf(size.x, size.z) < 3.0:
			return ["twiggy" if size.y > 1.4 else "leafy", 0.42]
	return []


## A mesh's height in the world (the meadow models are z-up: whichever
## world axis is up).
func _height(mesh: Mesh, basis: Basis) -> float:
	var box := mesh.get_aabb()
	var up := Vector3.ZERO
	for corner in 8:
		up.y = maxf(up.y, absf((basis * box.get_endpoint(corner)).y))
	var low := INF
	var high := -INF
	for corner in 8:
		var y := (basis * box.get_endpoint(corner)).y
		low = minf(low, y)
		high = maxf(high, y)
	return high - low


func _width(mesh: Mesh) -> float:
	var size := mesh.get_aabb().size
	return maxf(size.x, size.z)


## The scene file the mesh came from (a model placed by hand).
func _source_file(node: Node, scene: Node) -> String:
	var current := node
	while current and current != scene:
		if current.scene_file_path != "":
			return current.scene_file_path.get_file()
		current = current.get_parent()
	return ""


func _add(at: Vector3, radius: float, kind: String, height: float) -> void:
	radius = clampf(radius, 0.25, 1.4)
	var cell := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	if not _grid.has(cell):
		_grid[cell] = []
	_grid[cell].append([at, radius, kind, height])
	count += 1
	counts[kind] = counts.get(kind, 0) + 1


## The plants the point is inside of (flat).
func plants_at(point: Vector3) -> Array:
	var found := []
	var cell := Vector2i(floori(point.x / CELL), floori(point.z / CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for plant in _grid.get(cell + Vector2i(dx, dz), []):
				var p: Vector3 = plant[0]
				if absf(p.y - point.y) > 2.5:
					continue
				if Vector2(p.x - point.x, p.z - point.z).length() < plant[1] + BODY:
					found.append(plant)
	return found


func _physics_process(delta: float) -> void:
	if not ready_to_play:
		return
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	# Not while the player is frozen (the computer, a cutscene).
	if not player or not player.is_physics_processing():
		_inside.clear()
		return
	var crouching: bool = player.has_method("is_crouching") and player.is_crouching()
	step(player.global_position, Vector2(player.velocity.x, player.velocity.z).length(), crouching, delta)


## True if a crouching player at `point` is hidden by a plant: inside one
## tall enough (its middle, not just brushing its edge).
func in_cover(point: Vector3) -> bool:
	if not ready_to_play:
		return false
	for plant in plants_at(point):
		var p: Vector3 = plant[0]
		if plant[3] >= COVER_HEIGHT and Vector2(p.x - point.x, p.z - point.z).length() < plant[1]:
			return true
	return false


## The player at `at`, moving at `speed` (m/s): rustles what they walk into.
func step(at: Vector3, speed: float, crouching: bool, delta: float) -> void:
	var now := plants_at(at)
	_repeat -= delta
	if speed < MIN_SPEED:
		_inside = now
		return
	var entered := false
	for plant in now:
		if not _inside.has(plant):
			entered = true
			_rustle(plant, at, speed, crouching)
			break
	if not entered and not now.is_empty() and _repeat <= 0.0:
		_rustle(now[0], at, speed, crouching)
	_inside = now


func _rustle(plant: Array, player_at: Vector3, speed: float, crouching: bool) -> void:
	_repeat = REPEAT
	var kind: String = plant[2]
	var sound := _free_player()
	sound.stream = _sounds[kind][_rng.randi() % _sounds[kind].size()]
	var loud: float = VOLUME_DB[kind]
	if crouching:
		loud -= 7.0
	elif speed > 5.5:
		loud += 4.0
	sound.volume_db = loud
	sound.pitch_scale = _rng.randf_range(0.88, 1.12) * KIND_PITCH[kind] * (0.9 if crouching else 1.0)
	var at: Vector3 = plant[0]
	sound.global_position = Vector3(at.x, player_at.y - 0.6, at.z)
	sound.play()
	last_rustle = [kind, at]
	# The Entity can hear it.
	var player := get_tree().get_first_node_in_group("player")
	if player:
		NoiseEvent.emit(player, Vector3(at.x, player_at.y, at.z), &"rustle_crouch" if crouching else &"rustle")


func _free_player() -> AudioStreamPlayer3D:
	for player in _pool:
		if not player.playing:
			return player
	return _pool[_rng.randi() % _pool.size()]


## A rustle: shaped noise. Leafy: a soft swell of mid-high hiss with leaf
## flutter; twiggy: drier, with sharp twig ticks; grassy: short and airy.
func _make_sound(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var length: float = float({"leafy": 0.55, "twiggy": 0.5, "grassy": 0.35}[kind]) * _rng.randf_range(0.85, 1.2)
	var frames := int(rate * length)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var low := 0.0
	var band := 0.0
	var tick := 0.0
	var flutter_rate := _rng.randf_range(18.0, 30.0)
	for i in frames:
		var t := float(i) / frames
		var white := _rng.randf() * 2.0 - 1.0
		low = low * 0.75 + white * 0.25
		band = white - low  # the high part: leaves, not wind
		var envelope := pow(sin(t * PI), 0.8) * (1.0 - t * 0.3)
		var sample := 0.0
		match kind:
			"leafy":
				var flutter := 0.55 + 0.45 * absf(sin(t * flutter_rate * TAU * 0.5 + sin(t * 7.0)))
				sample = (band * 0.7 + low * 0.5) * flutter * envelope
			"twiggy":
				sample = band * 0.45 * envelope
				if _rng.randf() < 0.004:
					tick = _rng.randf_range(0.6, 1.0)
				sample += (white * tick) * 0.9
				tick *= 0.86
			"grassy":
				sample = band * 0.55 * envelope * (0.7 + 0.3 * sin(t * 40.0))
		data.encode_s16(i * 2, int(clampf(sample * 0.6, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
