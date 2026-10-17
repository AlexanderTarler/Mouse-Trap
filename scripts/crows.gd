class_name Crows
extends Node3D
## A flock of crows, by day: perched (on stakes, a roof ridge, the ground),
## pecking and hopping. They go up cawing when the player comes close, or
## when the Entity does (a warning, if the player is watching), and don't
## come back until the player is far away. None at night: the clearing is
## silent then.
##
## The flock at the willow is the default; WorldDetails adds others with
## setup(): the cabin's roof ridge on Day 1 (up when the player is ~20 m
## away, gone for the day), the barn roof, the wreck yard, the clear-cut.
##
## Built in code (the kit has no birds): a low-poly body with two flapping
## wings, and a synthesized caw.

const FLY_TIME := 7.0

enum Perch {
	WILLOW,   ## the stakes around the willow, then the ground under it
	HIGH,     ## the highest points in `extent` around the centre (a roof ridge)
	GROUND,   ## the ground around the centre
}

## Where the flock is, how many, where they sit.
var centre := Vector3(103.0, 0.4, 85.3)
var count := 7
var perch := Perch.WILLOW
## HIGH: the half size (x, z) of the area searched for the highest points.
var extent := Vector2(8.0, 8.0)
## The player this close: they take off.
var flee_player := 12.0
## The Entity this close: they take off too.
var flee_entity := 22.0
## They settle again only once the player is this far away (and it's day).
var return_distance := 45.0
## Only on Day 1 (the first day), and once they're up they don't come back.
var day_one_only := false


## A flock other than the willow's (before it enters the tree).
func setup(at: Vector3, birds: int, sits: Perch, flee: float, area: Vector2 = Vector2(8.0, 8.0), first_day_only: bool = false) -> Crows:
	centre = at
	count = birds
	perch = sits
	flee_player = flee
	extent = area
	day_one_only = first_day_only
	return_distance = maxf(flee * 3.0, 45.0)
	return self


enum State { PERCHED, FLYING, GONE }

var _crows: Array[Dictionary] = []
var _mesh_body: ArrayMesh
var _mesh_wing: ArrayMesh
var _material: StandardMaterial3D
var _caws: Array[AudioStreamWAV] = []
var _rng := RandomNumberGenerator.new()
var _check := 0.0
## A spot that sends them up too when the player passes it (the roof flock:
## the stones by the old note on the way in), and how close counts (m).
var scare_spot := Vector3.INF
var scare_radius := 8.0
const CAWING := "res://assets/audio/objects/Birds_Cawing.ogg"


func _ready() -> void:
	add_to_group("crows")
	if Engine.is_editor_hint():
		return
	_rng.seed = 7 + int(centre.x * 13.0 + centre.z * 7.0)
	_build_meshes()
	for i in 3:
		_caws.append(_make_caw(_rng.randf_range(0.9, 1.15), 2 if i == 0 else 1))
	await get_tree().physics_frame
	for i in count:
		_crows.append(_make_crow())
	if _may_settle():
		_settle_all()
	else:
		for crow in _crows:
			crow.state = State.GONE
			crow.node.visible = false


func _process(delta: float) -> void:
	if _crows.is_empty():
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var entity := get_tree().get_first_node_in_group("entity") as Node3D
	var night := _is_night()
	_check -= delta
	# Not until the game is set up: at first the player stands where the
	# scene has them (in the cabin, under the roof flock) for a moment.
	var nm := get_node_or_null("/root/NightManager")
	if nm and "_spawn_setup_done" in nm and not nm._spawn_setup_done:
		_check = 0.25
	if _check <= 0.0:
		_check = 0.25
		var all_gone := true
		for crow in _crows:
			if crow.state != State.GONE:
				all_gone = false
		# Come back when nobody is around (by day).
		if all_gone and not night and not day_one_only and player and _flat(player.global_position, centre) > return_distance:
			_settle_all()
		# Something coming: up they go.
		var scare := ""
		if player and _flat(player.global_position, centre) < flee_player + 6.0:
			for crow in _crows:
				if crow.state == State.PERCHED and _flat(player.global_position, crow.node.global_position) < flee_player:
					scare = "player"
		if player and scare_spot != Vector3.INF and _flat(player.global_position, scare_spot) < scare_radius:
			for crow in _crows:
				if crow.state == State.PERCHED:
					scare = "player"
		if entity and entity.visible and entity.has_method("is_active") and entity.is_active() \
				and _flat(entity.global_position, centre) < flee_entity:
			scare = "entity"
		if night or (day_one_only and not _is_day_one()):
			scare = "night"
		if scare != "":
			_take_off(player, entity, scare)
	for crow in _crows:
		_animate(crow, delta)


## By day (and on Day 1, for a Day 1 flock).
func _may_settle() -> bool:
	return not _is_night() and (not day_one_only or _is_day_one())


func _is_day_one() -> bool:
	var nm := get_node_or_null("/root/NightManager")
	return nm == null or nm.current_night <= 0


func _is_night() -> bool:
	var gt := get_node_or_null("/root/GameTime")
	return gt != null and not gt.is_day


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ─── Behaviour ───────────────────────────────────────────────────────────

func _settle_all() -> void:
	var perches := _perches()
	for i in _crows.size():
		var crow: Dictionary = _crows[i]
		var spot: Vector3 = perches[i % perches.size()]
		crow.node.global_position = spot
		crow.node.rotation = Vector3(0.0, _rng.randf() * TAU, 0.0)
		crow.node.visible = true
		crow.state = State.PERCHED
		crow.timer = _rng.randf_range(0.5, 3.0)
		crow.flap = 0.0
		_fold(crow)


## Where they sit: the tops of the stakes, then the ground under the tree
## (WILLOW); the highest points around (HIGH); the ground around (GROUND).
func _perches() -> Array[Vector3]:
	if perch == Perch.HIGH:
		return _high_perches()
	var spots: Array[Vector3] = []
	var scene := get_tree().current_scene
	var sites := scene.get_node_or_null("Sites") if scene and perch == Perch.WILLOW else null
	if sites:
		for prop in sites.get_children():
			if prop is Node3D and String(prop.name).begins_with("SM_EC_WoodenPole_Large_00") \
					and _flat((prop as Node3D).global_position, centre) < 10.0:
				spots.append(_top_of(prop as Node3D))
	var space := get_world_3d().direct_space_state
	var tries := 0
	while spots.size() < count and tries < 60:
		tries += 1
		var angle := _rng.randf() * TAU
		var at := centre + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(2.5, 6.5)
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.8, at + Vector3.DOWN * 4.0)
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and (hit.position as Vector3).y < centre.y + 0.6:
			spots.append(hit.position)
	if spots.is_empty():
		spots.append(centre + Vector3(3, 0, 0))
	spots.shuffle()
	return spots


## The highest points (a roof's ridge) in the area around the centre, at
## least 0.7 m apart, looked down on from above.
func _high_perches() -> Array[Vector3]:
	var space := get_world_3d().direct_space_state
	var hits: Array[Vector3] = []
	var step := 0.5
	var x := -extent.x
	while x <= extent.x:
		var z := -extent.y
		while z <= extent.y:
			var top := centre + Vector3(x, 30.0, z)
			var query := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 40.0)
			var hit := space.intersect_ray(query)
			# (Not a tree trunk's collider: it stands higher than the roof,
			# and there's nothing up there to sit on.)
			if not hit.is_empty() and not ForestDresser.near_trunk(hit.position, 0.7):
				hits.append(hit.position)
			z += step
		x += step
	hits.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)
	var spots: Array[Vector3] = []
	for hit in hits:
		if spots.size() >= count:
			break
		if hit.y < hits[0].y - 0.6:
			break
		if spots.all(func(s: Vector3) -> bool: return s.distance_to(hit) > 0.7):
			spots.append(hit)
	if spots.is_empty():
		spots.append(centre)
	spots.shuffle()
	return spots


func _top_of(node: Node3D) -> Vector3:
	var box := AABB(node.global_position, Vector3.ZERO)
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return Vector3(box.get_center().x, box.end.y, box.get_center().z)


func _take_off(player: Node3D, entity: Node3D, why: String) -> void:
	var cawed := 0
	for crow in _crows:
		if crow.state != State.PERCHED:
			continue
		var away: Vector3 = crow.node.global_position - centre
		var threat: Node3D = entity if why == "entity" else player
		if threat:
			away = crow.node.global_position - threat.global_position
		away.y = 0.0
		if away.length() < 0.1:
			away = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
		away = away.normalized().rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
		crow.velocity = away * _rng.randf_range(4.0, 6.0) + Vector3.UP * _rng.randf_range(3.5, 5.0)
		crow.state = State.FLYING
		crow.timer = FLY_TIME + _rng.randf_range(0.0, 1.5)
		crow.delay = _rng.randf_range(0.0, 0.5)
		if cawed == 0:
			cawed += 1
			_caw(crow.node, 0)
			if why != "night":
				Caption.at(self, "crows taking off", crow.node.global_position)


func _animate(crow: Dictionary, delta: float) -> void:
	var node: Node3D = crow.node
	match crow.state:
		State.PERCHED:
			crow.timer -= delta
			if crow.timer <= 0.0:
				crow.timer = _rng.randf_range(1.0, 4.0)
				var roll := _rng.randf()
				if roll < 0.4:
					# Peck.
					crow.peck = 0.35
				elif roll < 0.75:
					node.rotate_y(_rng.randf_range(-1.2, 1.2))
				else:
					# A hop.
					crow.hop = 0.3
			crow.peck = maxf(crow.peck - delta, 0.0)
			crow.hop = maxf(crow.hop - delta, 0.0)
			crow.body.rotation.x = sin(crow.peck / 0.35 * PI) * 0.7
			crow.body.position.y = 0.12 + sin(crow.hop / 0.3 * PI) * 0.12
		State.FLYING:
			if crow.delay > 0.0:
				crow.delay -= delta
				return
			crow.timer -= delta
			crow.velocity.y = minf(crow.velocity.y + 1.2 * delta, 6.0)
			node.global_position += crow.velocity * delta
			var flat := Vector3(crow.velocity.x, 0.0, crow.velocity.z)
			if flat.length() > 0.1:
				node.look_at(node.global_position + flat, Vector3.UP)
				node.rotate_object_local(Vector3.UP, PI)
			crow.flap += delta * 16.0
			var beat := sin(crow.flap) * 1.0
			crow.left.rotation.z = beat
			crow.right.rotation.z = -beat
			crow.body.rotation.x = -0.25
			if crow.timer <= 0.0:
				crow.state = State.GONE
				node.visible = false
		State.GONE:
			pass


func _fold(crow: Dictionary) -> void:
	crow.left.rotation = Vector3(0, 0, -1.25)
	crow.right.rotation = Vector3(0, 0, 1.25)
	crow.body.rotation = Vector3.ZERO
	crow.body.position.y = 0.12
	crow.peck = 0.0
	crow.hop = 0.0


## The flock's cawing as it goes up, from where the birds are.
func _caw(at: Node3D, which: int) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = load(CAWING) if ResourceLoader.exists(CAWING) else _caws[which % _caws.size()]
	player.unit_size = 8.0
	player.max_distance = 60.0
	player.volume_db = -2.0
	player.pitch_scale = _rng.randf_range(0.92, 1.08)
	player.bus = &"SFX"
	add_child(player)
	player.global_position = at.global_position
	player.play()
	player.finished.connect(player.queue_free)


# ─── The bird ────────────────────────────────────────────────────────────

func _make_crow() -> Dictionary:
	var root := Node3D.new()
	root.name = "Crow"
	add_child(root)
	var body := MeshInstance3D.new()
	body.mesh = _mesh_body
	body.material_override = _material
	body.position.y = 0.12
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(body)
	var left := Node3D.new()
	left.position = Vector3(0.04, 0.05, -0.02)
	body.add_child(left)
	var lw := MeshInstance3D.new()
	lw.mesh = _mesh_wing
	lw.material_override = _material
	left.add_child(lw)
	var right := Node3D.new()
	right.position = Vector3(-0.04, 0.05, -0.02)
	right.scale = Vector3(-1, 1, 1)
	body.add_child(right)
	var rw := MeshInstance3D.new()
	rw.mesh = _mesh_wing
	rw.material_override = _material
	right.add_child(rw)
	var crow := {"node": root, "body": body, "left": left, "right": right, "state": State.GONE,
		"timer": 0.0, "delay": 0.0, "velocity": Vector3.ZERO, "flap": 0.0, "peck": 0.0, "hop": 0.0}
	_fold(crow)
	root.visible = false
	return crow


## The body (beak forward, along -z... flipped: facing +z), head, tail; and
## a wing that hinges at its root (x = 0) and spreads along +x.
func _build_meshes() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.035, 0.035, 0.045)
	_material.roughness = 0.45
	_material.metallic_specular = 0.6
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Body: a stretched octahedron.
	var nose := Vector3(0, 0.05, 0.16)
	var tail := Vector3(0, 0.04, -0.14)
	var top := Vector3(0, 0.12, 0.0)
	var bottom := Vector3(0, -0.03, 0.0)
	var l := Vector3(0.07, 0.04, 0.0)
	var r := Vector3(-0.07, 0.04, 0.0)
	for tri in [[nose, top, l], [nose, r, top], [nose, l, bottom], [nose, bottom, r],
			[tail, l, top], [tail, top, r], [tail, bottom, l], [tail, r, bottom]]:
		_tri(st, tri[0], tri[1], tri[2])
	# Head and beak.
	var h := Vector3(0, 0.12, 0.17)
	var beak := Vector3(0, 0.1, 0.28)
	var hl := Vector3(0.035, 0.1, 0.15)
	var hr := Vector3(-0.035, 0.1, 0.15)
	var hb := Vector3(0, 0.07, 0.15)
	for tri in [[beak, h, hl], [beak, hr, h], [beak, hl, hb], [beak, hb, hr], [h, hr, hl]]:
		_tri(st, tri[0], tri[1], tri[2])
	# Tail fan.
	_tri(st, Vector3(0, 0.05, -0.1), Vector3(0.06, 0.06, -0.3), Vector3(-0.06, 0.06, -0.3))
	# Legs.
	_tri(st, Vector3(0.02, -0.01, 0.0), Vector3(0.03, -0.12, 0.02), Vector3(0.025, -0.01, -0.02))
	_tri(st, Vector3(-0.02, -0.01, 0.0), Vector3(-0.03, -0.12, 0.02), Vector3(-0.025, -0.01, -0.02))
	st.generate_normals()
	_mesh_body = st.commit()
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w0 := Vector3(0, 0, 0.07)
	var w1 := Vector3(0, 0, -0.07)
	var w2 := Vector3(0.2, 0.01, 0.05)
	var w3 := Vector3(0.36, 0.0, -0.04)
	var w4 := Vector3(0.18, 0.0, -0.12)
	_tri(st, w0, w2, w1)
	_tri(st, w2, w4, w1)
	_tri(st, w2, w3, w4)
	st.generate_normals()
	_mesh_wing = st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## A crow's caw: a harsh, nasal tone that sags in pitch, roughened with
## noise, `count` times.
func _make_caw(pitch: float, count: int) -> AudioStreamWAV:
	var rate := 22050
	var one := int(rate * 0.32)
	var gap := int(rate * 0.12)
	var total := one * count + gap * (count - 1)
	var data := PackedByteArray()
	data.resize(total * 2)
	var phase := 0.0
	var rough := 0.0
	for n in count:
		var start := n * (one + gap)
		for i in one:
			var t := float(i) / one
			var freq := (560.0 - 170.0 * t) * pitch
			phase = fmod(phase + freq / rate, 1.0)
			# A buzzy pulse wave with its overtones, plus rasp.
			var tone := (1.0 if phase < 0.28 else -0.4) + 0.3 * sin(phase * TAU * 3.0)
			rough = rough * 0.6 + (randf() * 2.0 - 1.0) * 0.4
			var envelope := minf(t / 0.04, 1.0) * pow(1.0 - t, 1.4)
			var sample := (tone * 0.55 + rough * 0.45 * (0.6 + 0.4 * sin(t * 90.0))) * envelope * 0.55
			data.encode_s16((start + i) * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
