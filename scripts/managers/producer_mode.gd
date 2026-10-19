class_name ProducerMode
extends Node3D
## Producer mode (development): watch the Entity work. The game starts at
## Night 3 (DevStart, behind black); then you are a floating ghost that
## passes through everything, and a replica of the player stands in the
## cabin for the Entity to hunt instead of you.
##
## Start it from the main menu's "Producer Mode" (debug builds), with
## "-- --producer" on the command line, or by ticking Player.producer_mode
## and running the level.
##
## The replica is the real Player node: still in the "player" group, so the
## Entity, its senses and the night go on as for the player; its controls are
## off, it can't die (K lets the Entity kill), and it has a body to see.
## Keys (also on screen; H hides them):
##   mouse, W A S D        look, fly          Space / Ctrl   up / down
##   Shift                 fast               F              flashlight on / off
##   V                     follow the Entity until V again (the mouse
##                         turns round it)
##   G                     to the replica     R              the replica to where you look
##   [ / ]                 slower / faster time    K          Entity may kill
##   F3                    the Entity's debug overlay (its state, its senses)

## Asked for (main menu, command line, Player.producer_mode): the level
## starts in producer mode.
static var requested := false

const FLY_SPEED := 6.0
const FAST := 4.0
const LOOK := 0.0022
const TIME_SCALES := [0.1, 0.25, 0.5, 1.0, 2.0, 3.0]
## Following the Entity: this far from it (m), from behind and a little
## above to start with; the mouse turns round it.
const FOLLOW_DISTANCE := 5.2
const FOLLOW_PITCH := 0.52

var camera: Camera3D
var replica: Node3D
var following := false
var flashlight: SpotLight3D
var _orbit_yaw := 0.0
var _orbit_pitch := FOLLOW_PITCH
var _listener: AudioListener3D
var _help: Label
var _yaw := 0.0
var _pitch := -0.2
var _time_index := 3


## Whether this run is a producer run (and so the Night 3 dev start).
static func wanted(player: Node) -> bool:
	return requested or (player != null and bool(player.get("producer_mode")))


func _ready() -> void:
	name = "ProducerMode"
	process_mode = Node.PROCESS_MODE_ALWAYS
	replica = get_tree().get_first_node_in_group("player") as Node3D
	_make_replica()
	camera = Camera3D.new()
	camera.name = "GhostCamera"
	camera.fov = 75.0
	camera.far = 800.0
	add_child(camera)
	_listener = AudioListener3D.new()
	camera.add_child(_listener)
	# The producer's own flashlight (F), off to start with.
	flashlight = SpotLight3D.new()
	flashlight.name = "GhostFlashlight"
	flashlight.spot_range = 35.0
	flashlight.spot_angle = 28.0
	flashlight.light_energy = 3.0
	flashlight.light_color = Color(1.0, 0.95, 0.85)
	flashlight.shadow_enabled = true
	flashlight.visible = false
	camera.add_child(flashlight)
	# Start above the cabin, looking at it.
	var at := replica.global_position if replica else Vector3.ZERO
	global_position = at + Vector3(-10.0, 6.0, -10.0)
	_yaw = atan2(-(at.x - global_position.x), -(at.z - global_position.z))
	_pitch = -0.35
	camera.current = true
	_listener.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_make_help()
	var entity := get_tree().get_first_node_in_group("entity")
	if entity:
		entity.can_kill = false
	print("[ProducerMode] On: you're the ghost; the replica stands at %s." % at)


func _exit_tree() -> void:
	requested = false
	Engine.time_scale = 1.0


## The player, as a stand-in: controls off, a body to see, on the floor.
func _make_replica() -> void:
	if not replica:
		return
	for setter in ["set_process", "set_physics_process", "set_process_input", "set_process_unhandled_input"]:
		replica.call(setter, false)
	if "velocity" in replica:
		replica.velocity = Vector3.ZERO
	# A body the size of its collider, where its collider is.
	var span := _body_span()
	var body := MeshInstance3D.new()
	body.name = "ReplicaBody"
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = maxf(span.y - span.x, 0.8)
	body.mesh = mesh
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.25, 0.55, 0.95)
	paint.emission_enabled = true
	paint.emission = Color(0.1, 0.25, 0.5)
	body.material_override = paint
	replica.add_child(body)
	body.position = Vector3.UP * (span.x + span.y) * 0.5
	# In the cabin (where the dev start left it may be anywhere).
	var spawn := get_tree().current_scene.get_node_or_null("PlayerSpawnpoints/PlayerSpawnDev") as Node3D
	_place_replica(spawn.global_position if spawn else replica.global_position)


## The player's collider, bottom to top (local y).
func _body_span() -> Vector2:
	for child in replica.get_children():
		var shape_node := child as CollisionShape3D
		if not shape_node or not shape_node.shape:
			continue
		var box := shape_node.shape.get_debug_mesh().get_aabb()
		return Vector2(shape_node.position.y + box.position.y, shape_node.position.y + box.end.y)
	return Vector2(0.0, 1.8)


## The replica to stand on the floor under (or at) `spot`.
func _place_replica(spot: Vector3) -> void:
	var space := replica.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 1.0, spot + Vector3.DOWN * 6.0, 1, [(replica as CollisionObject3D).get_rid()])
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		replica.global_position = spot
		return
	# Its feet (the bottom of its collider) on the floor.
	replica.global_position = (hit.position as Vector3) - Vector3.UP * _body_span().x


func _make_help() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_help = Label.new()
	_help.position = Vector2(16, 120)
	_help.add_theme_font_size_override("font_size", 14)
	_help.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	_help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_help.add_theme_constant_override("outline_size", 4)
	layer.add_child(_help)


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if following:
			# Round the Entity (following goes on until V).
			_orbit_yaw -= event.relative.x * LOOK
			_orbit_pitch = clampf(_orbit_pitch + event.relative.y * LOOK, -0.2, 1.4)
		else:
			_yaw -= event.relative.x * LOOK
			_pitch = clampf(_pitch - event.relative.y * LOOK, -1.5, 1.5)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F:
				flashlight.visible = not flashlight.visible
			KEY_V:
				following = not following
				_orbit_yaw = 0.0
				_orbit_pitch = FOLLOW_PITCH
			KEY_G:
				if replica:
					global_position = replica.global_position + Vector3(0, 1.6, 0) - _forward() * 3.0
					following = false
			KEY_R:
				_replica_to_aim()
			KEY_BRACKETLEFT:
				_time_index = maxi(_time_index - 1, 0)
				Engine.time_scale = TIME_SCALES[_time_index]
			KEY_BRACKETRIGHT:
				_time_index = mini(_time_index + 1, TIME_SCALES.size() - 1)
				Engine.time_scale = TIME_SCALES[_time_index]
			KEY_K:
				var entity := get_tree().get_first_node_in_group("entity")
				if entity:
					entity.can_kill = not entity.can_kill
			KEY_H:
				_help.visible = not _help.visible
			_:
				return
		get_viewport().set_input_as_handled()


func _forward() -> Vector3:
	return -Basis(Vector3.UP, _yaw).z


## The replica moved to the floor where the ghost is looking.
func _replica_to_aim() -> void:
	if not replica:
		return
	var from := camera.global_position
	var to := from - camera.global_basis.z * 60.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1, [(replica as CollisionObject3D).get_rid()]))
	if not hit.is_empty():
		_place_replica(hit.position)
		print("[ProducerMode] The replica moved to %s." % replica.global_position)


func _process(delta: float) -> void:
	# (Real time: the ghost flies the same whatever the game's speed.)
	var real := delta / maxf(Engine.time_scale, 0.01)
	var entity := get_tree().get_first_node_in_group("entity") as Node3D
	if following and entity:
		var angle := entity.global_rotation.y + _orbit_yaw
		var offset := Vector3(sin(angle) * cos(_orbit_pitch), sin(_orbit_pitch), cos(angle) * cos(_orbit_pitch)) * FOLLOW_DISTANCE
		global_position = global_position.lerp(entity.global_position + offset, clampf(real * 3.0, 0.0, 1.0))
		var look := entity.global_position + Vector3.UP * 1.2 - camera.global_position
		_yaw = atan2(-look.x, -look.z)
		_pitch = atan2(look.y, Vector2(look.x, look.z).length())
	elif not get_tree().paused:
		var move := Vector3.ZERO
		var basis := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
		if Input.is_action_pressed("move_forward"): move -= basis.z
		if Input.is_action_pressed("move_back"): move += basis.z
		if Input.is_action_pressed("move_left"): move -= basis.x
		if Input.is_action_pressed("move_right"): move += basis.x
		if Input.is_action_pressed("jump"): move += Vector3.UP
		if Input.is_action_pressed("ui_crouch"): move += Vector3.DOWN
		var speed := FLY_SPEED * (FAST if Input.is_action_pressed("ui_shift") else 1.0)
		global_position += move.normalized() * speed * real
	camera.global_basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	if not camera.current:
		camera.current = true
		_listener.make_current()
	if _help.visible:
		_help.text = _help_text(entity)


func _help_text(entity: Node) -> String:
	var gt := get_node_or_null("/root/GameTime")
	var nm := get_node_or_null("/root/NightManager")
	var state: String = entity.get_state_name() if entity and entity.has_method("get_state_name") else ""
	var distance := (entity as Node3D).global_position.distance_to(replica.global_position) if entity and replica else -1.0
	return "PRODUCER MODE   Night %d  %s   time x%s\nEntity: %s, %.1f m from the replica   kills: %s%s\n\nmouse, W A S D: look, fly   Space / Ctrl: up / down   Shift: fast\nF: flashlight   V: follow the Entity (mouse: round it; V again to stop)   G: to the replica   R: replica to where you look\n[ / ]: slower / faster   K: Entity may kill   F3: Entity debug   H: hide this" % [
		nm.current_night if nm else 0, Wristwatch.clock_text(gt.cycle_progress) if gt else "",
		str(TIME_SCALES[_time_index]), state, distance, "on" if entity and entity.can_kill else "off",
		"   (following)" if following else ""]
