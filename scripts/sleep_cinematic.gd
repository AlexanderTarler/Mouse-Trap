class_name SleepCinematic
extends Node
## Going to sleep and waking up, in first person (the bed, bed_interactable.gd).
##
##   await cinematic.fall_asleep(player)       # ends on black (the HUD's fade)
##   ... the night or day changes behind the black ...
##   await cinematic.wake_up(player, sudden)   # from black to standing by the bed
##
## Going to sleep: a camera of its own eases from the player's eyes to
## sitting on the bed, then lying back with the head on the pillow, looking
## up at the ceiling; breathing slows and the eyelids close, with a heavy
## blink or two, to black.
## Waking up: lying there in the dark, the eyelids open slowly (a blink,
## half-shut again, open), then the player sits up, gets up, and stands
## beside the bed facing the room, where control comes back.
## Sudden (Night 2.2, woken by the car alarm): eyes snap open with a jolt,
## up and out of bed in about a second.
##
## Dozing off where the player is (the Day 2 data upload, computer_ui.gd):
## only the eyelids and the breathing, no bed, no camera of its own.
##   await cinematic.doze_off()      # heavy blinks, to shut
##   await cinematic.open_eyes()     # and open again; then free it
##
## The bed's head end is its pillow (a child named "pillow*"); the rest is
## measured from the bed's meshes, so it works for any bed.

const LIDS_LAYER := 140
## The soft edge of each eyelid (px).
const LID_EDGE := 90.0
const BREATHING := "res://assets/audio/objects/Player Breathing.ogg"

## Going to sleep: to sitting on the bed, then lying back (s).
const TO_SIT_TIME := 1.4
const LIE_BACK_TIME := 1.2
## Waking: sitting up, then standing (s).
const SIT_UP_TIME := 1.0
const STAND_TIME := 0.9
const SUDDEN_SIT_UP_TIME := 0.45
const SUDDEN_STAND_TIME := 0.5

## The eyelids: [closed amount (0 open, 1 shut), seconds to get there].
const FALL_ASLEEP_LIDS := [[0.55, 0.9], [0.25, 0.35], [0.8, 0.8], [0.55, 0.3], [1.0, 0.7]]
const WAKE_LIDS := [[0.65, 0.8], [1.0, 0.25], [0.35, 0.7], [0.75, 0.15], [0.0, 0.55]]

var _bed: Node3D = null
var _camera: Camera3D = null
var _layer: CanvasLayer = null
var _top_lid: Control = null
var _bottom_lid: Control = null
var _lids := 0.0
var _breathing: AudioStreamPlayer = null
var _hidden_crosshairs: Array[Node] = []
var _shake := 0.0


## `bed`: the bed model (its meshes and its pillow).
func setup(bed: Node3D) -> SleepCinematic:
	_bed = bed
	return self


func fall_asleep(player: Node3D) -> void:
	_begin(player)
	var start := _player_camera(player).global_transform
	_camera.global_transform = start
	_set_lids(0.0)
	_breathe(true)
	await _move_camera(start, sit_transform(), TO_SIT_TIME)
	var lids := _lid_tween(FALL_ASLEEP_LIDS)
	await _move_camera(sit_transform(), lie_transform(true), LIE_BACK_TIME)
	if lids.is_running():
		await lids.finished
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("fade_to_black"):
		await hud.fade_to_black(0.05)
	_breathe(false)
	_end(player, false)


## From black: awake, up, and standing by the bed. `sudden`: the alarm.
func wake_up(player: Node3D, sudden: bool = false) -> void:
	_place_player(player)
	var stand := _player_camera(player).global_transform
	_begin(player)
	_camera.global_transform = lie_transform(false)
	_set_lids(1.0)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("fade_from_black"):
		await hud.fade_from_black(0.05)
	if sudden:
		var snap := create_tween()
		snap.tween_method(_set_lids, 1.0, 0.0, 0.15)
		_shake = 0.06
		create_tween().tween_property(self, "_shake", 0.0, 0.6)
		await snap.finished
		await _move_camera(lie_transform(false), sit_transform(), SUDDEN_SIT_UP_TIME, Tween.EASE_OUT)
		await _move_camera(sit_transform(), stand, SUDDEN_STAND_TIME)
	else:
		await _lid_tween(WAKE_LIDS).finished
		await _move_camera(lie_transform(false), sit_transform(), SIT_UP_TIME)
		await _move_camera(sit_transform(), stand, STAND_TIME)
	_end(player, true)


# ─── Where ──────────────────────────────────────────────────────────────────

## The bed's bounds (its meshes, not the pillow).
func bed_box() -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in _bed.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or _is_pillow(mesh):
			continue
		var bounds := mesh.global_transform * mesh.mesh.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	return box


func _is_pillow(node: Node) -> bool:
	var at := node
	while at and at != _bed:
		if str(at.name).to_lower().begins_with("pillow"):
			return true
		at = at.get_parent()
	return false


## The top of the pillow (or the bed's head end).
func pillow_top() -> Vector3:
	for mesh: MeshInstance3D in _bed.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh and _is_pillow(mesh):
			var bounds := mesh.global_transform * mesh.mesh.get_aabb()
			return Vector3(bounds.get_center().x, bounds.end.y, bounds.get_center().z)
	var box := bed_box()
	return box.get_center() + Vector3.UP * box.size.y * 0.5


## From the pillow towards the foot of the bed (flat).
func feet_direction() -> Vector3:
	var toward := bed_box().get_center() - pillow_top()
	toward.y = 0.0
	return toward.normalized() if toward.length_squared() > 0.001 else Vector3.LEFT


## Lying on the back, head on the pillow, looking up (the top of the view
## towards the headboard). `rolled`: the head tipped a little to one side.
func lie_transform(rolled: bool) -> Transform3D:
	var head := pillow_top() + Vector3.UP * 0.18 + feet_direction() * 0.08
	var basis := Basis.looking_at(Vector3.UP, -feet_direction())
	if rolled:
		basis = Basis(feet_direction(), deg_to_rad(9.0)) * basis
	return Transform3D(basis, head)


## Sitting up on the bed, looking towards its foot.
func sit_transform() -> Transform3D:
	var at := pillow_top() + feet_direction() * 0.55 + Vector3.UP * 0.55
	return Transform3D(Basis.looking_at(feet_direction() + Vector3.DOWN * 0.15, Vector3.UP), at)


## Where the player stands after waking: off the foot of the bed, facing
## the room, on the bed's floor.
func stand_position() -> Vector3:
	var box := bed_box()
	var feet := feet_direction()
	var half := absf(feet.x) * box.size.x * 0.5 + absf(feet.z) * box.size.z * 0.5
	var spot := box.get_center() + feet * (half + 0.7)
	spot.y = box.position.y + 0.05
	return spot


# ─── How ────────────────────────────────────────────────────────────────────

func _place_player(player: Node3D) -> void:
	player.global_position = stand_position()
	if player.has_method("reset_camera"):
		player.reset_camera()
	# Facing the way the feet point (into the room): the body faces -Z.
	var feet := feet_direction()
	player.rotation.y = atan2(-feet.x, -feet.z)
	if "velocity" in player:
		player.velocity = Vector3.ZERO


func _player_camera(player: Node3D) -> Camera3D:
	var camera := player.get_node_or_null("CameraHolder/Camera3D") as Camera3D
	return camera if camera else get_viewport().get_camera_3d()


func _begin(player: Node3D) -> void:
	if player.has_method("set_physics_process"):
		player.set_physics_process(false)
		player.set_process_input(false)
	var own := _player_camera(player)
	_camera = Camera3D.new()
	_camera.name = "SleepCamera"
	if own:
		_camera.fov = own.fov
		_camera.near = minf(own.near, 0.05)
		_camera.environment = own.environment
		_camera.attributes = own.attributes
	get_tree().current_scene.add_child(_camera)
	_camera.current = true
	_make_lids()
	_hidden_crosshairs.clear()
	for crosshair in get_tree().get_nodes_in_group("crosshair"):
		if crosshair is CanvasItem and crosshair.visible:
			crosshair.visible = false
			_hidden_crosshairs.append(crosshair)


## Back to the player's own camera. `awake`: control returns.
func _end(player: Node3D, awake: bool) -> void:
	var own := _player_camera(player)
	if own:
		own.current = true
	if is_instance_valid(_camera):
		_camera.queue_free()
	_camera = null
	if is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	for crosshair in _hidden_crosshairs:
		if is_instance_valid(crosshair):
			crosshair.visible = true
	_hidden_crosshairs.clear()
	if awake and player.has_method("set_physics_process"):
		player.set_physics_process(true)
		player.set_process_input(true)


func _move_camera(from: Transform3D, to: Transform3D, seconds: float, easing: Tween.EaseType = Tween.EASE_IN_OUT) -> void:
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(easing)
	tween.tween_method(func(t: float) -> void:
		if is_instance_valid(_camera):
			var xform := from.interpolate_with(to, t)
			if _shake > 0.0:
				xform.origin += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake
			_camera.global_transform = xform, 0.0, 1.0, seconds)
	await tween.finished


## The eyelids through `steps` ([amount, seconds] each); await its finished.
func _lid_tween(steps: Array) -> Tween:
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var from := _lids
	for step in steps:
		tween.tween_method(_set_lids, from, step[0], step[1])
		from = step[0]
	return tween


func _make_lids() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "Eyelids"
	_layer.layer = LIDS_LAYER
	add_child(_layer)
	_top_lid = _lid(true)
	_bottom_lid = _lid(false)
	_set_lids(_lids)


## A black lid with a soft edge (towards the middle of the screen).
func _lid(top: bool) -> Control:
	var lid := Control.new()
	lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(lid)
	var solid := ColorRect.new()
	solid.color = Color.BLACK
	solid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	solid.name = "Solid"
	lid.add_child(solid)
	var gradient := Gradient.new()
	gradient.set_color(0, Color.BLACK)
	gradient.set_color(1, Color(0, 0, 0, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0) if top else Vector2(0.5, 1.0)
	texture.fill_to = Vector2(0.5, 1.0) if top else Vector2(0.5, 0.0)
	var edge := TextureRect.new()
	edge.texture = texture
	edge.stretch_mode = TextureRect.STRETCH_SCALE
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.name = "Edge"
	lid.add_child(edge)
	lid.set_meta("top", top)
	return lid


## 0 = eyes open, 1 = shut.
func _set_lids(amount: float) -> void:
	_lids = amount
	if not is_instance_valid(_layer):
		return
	var screen := get_viewport().get_visible_rect().size
	# Fully shut, the soft edges overlap past the middle.
	var reach := amount * (screen.y * 0.5 + LID_EDGE)
	for lid in [_top_lid, _bottom_lid]:
		var top: bool = lid.get_meta("top")
		var solid := lid.get_node("Solid") as ColorRect
		var edge := lid.get_node("Edge") as TextureRect
		var solid_height := maxf(reach - LID_EDGE, 0.0)
		var edge_height := minf(reach, LID_EDGE)
		solid.size = Vector2(screen.x, solid_height)
		edge.size = Vector2(screen.x, edge_height)
		if top:
			solid.position = Vector2.ZERO
			edge.position = Vector2(0.0, solid_height)
		else:
			solid.position = Vector2(0.0, screen.y - solid_height)
			edge.position = Vector2(0.0, screen.y - solid_height - edge_height)


func _breathe(on: bool) -> void:
	if on:
		if not ResourceLoader.exists(BREATHING):
			return
		_breathing = AudioStreamPlayer.new()
		_breathing.stream = load(BREATHING)
		_breathing.bus = "SFX"
		_breathing.volume_db = -17.1
		_breathing.pitch_scale = 0.85
		add_child(_breathing)
		_breathing.play()
	elif is_instance_valid(_breathing):
		var player := _breathing
		_breathing = null
		var tween := create_tween()
		tween.tween_property(player, "volume_db", -60.0, 0.8)
		tween.tween_callback(player.queue_free)


func lids_amount() -> float:
	return _lids


## Eyelids only (see the top): heavy blinks, then shut.
func doze_off() -> void:
	if not is_instance_valid(_layer):
		_make_lids()
	_set_lids(0.0)
	_breathe(true)
	await _lid_tween(FALL_ASLEEP_LIDS).finished


## Eyelids only: open again (slowly, a blink), and gone.
func open_eyes() -> void:
	if not is_instance_valid(_layer):
		_make_lids()
		_set_lids(1.0)
	_breathe(false)
	await _lid_tween(WAKE_LIDS).finished
	if is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null


func is_running() -> bool:
	return _camera != null
