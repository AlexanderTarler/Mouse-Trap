class_name EntityTraces
extends Node3D

## Signs the Entity was here, for the player to find:
##   - muddy claw prints wherever it walks inside the cabin or close to it
##   - gouges in the wall under windows it peeked into or broke
## Traces persist through the day and are cleared when the next night starts.
## Textures are small pixel-art images generated at startup (PSX style, no
## asset files needed).

const MAX_FOOTPRINTS := 60
const MAX_SCRATCHES := 16
const STRIDE := 0.75                ## Meters between prints.
const FOOT_SPREAD := 0.14           ## Sideways offset of left/right prints.
## Prints are left outdoors only this close to a cabin entry (the muddy yard
## and porch), so the forest floor doesn't fill up with them.
const OUTDOOR_TRACK_RADIUS := 7.0
const MUD := Color(0.16, 0.11, 0.07)
const GOUGE := Color(0.1, 0.08, 0.06)

var entity: Entity
var _footprint_texture: ImageTexture
var _scratch_texture: ImageTexture
var _footprints: Array[Decal] = []
var _scratches: Array[Decal] = []
var _scratch_count: Dictionary = {}   ## CabinEntryLink -> scratches left there
var _distance_since_print := 0.0
var _left_foot := true
var _last_position := Vector3.INF


func setup(owner_entity: Entity) -> void:
	entity = owner_entity
	top_level = true
	global_transform = Transform3D.IDENTITY
	_footprint_texture = ImageTexture.create_from_image(_draw_footprint())
	_scratch_texture = ImageTexture.create_from_image(_draw_scratches())


func footprint_count() -> int:
	return _footprints.size()


func scratch_count() -> int:
	return _scratches.size()


func clear_all() -> void:
	for decal in _footprints + _scratches:
		decal.queue_free()
	_footprints.clear()
	_scratches.clear()
	_scratch_count.clear()
	_last_position = Vector3.INF


## Called by the Entity every physics frame while it's active.
func update_tracks(on_floor: bool) -> void:
	var pos := entity.global_position
	if _last_position == Vector3.INF or not on_floor or entity.is_traversing():
		_last_position = pos
		return
	_distance_since_print += Entity._flat_distance(pos, _last_position)
	_last_position = pos
	if _distance_since_print < STRIDE:
		return
	_distance_since_print = 0.0
	if entity.perception.entity_inside or _near_cabin(pos):
		_leave_footprint(pos)


## Gouges under a window (at most three per window).
func scratch_window(link: CabinEntryLink) -> void:
	if not link or link.kind != CabinEntryLink.Kind.WINDOW:
		return
	var count: int = _scratch_count.get(link, 0)
	if count >= 3:
		return
	_scratch_count[link] = count + 1
	var inward := link.end_position - link.start_position
	inward.y = 0.0
	inward = inward.normalized()
	var window: Node3D = link.entry
	var side := Vector3(-inward.z, 0.0, inward.x)
	var pos := window.global_position + Vector3.DOWN * randf_range(0.7, 1.1) \
		+ side * randf_range(-0.45, 0.45) - inward * 0.05
	# Decals project along their local -Y: point it into the wall, with the
	# texture's vertical (local Z) running down the wall.
	var y_axis := -inward
	var z_axis := Vector3.DOWN
	var x_axis := y_axis.cross(z_axis).normalized()
	var decal := _make_decal(_scratch_texture, GOUGE, Vector3(0.8, 0.6, 0.8))
	decal.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), pos) \
		.rotated_local(Vector3.UP, randf_range(-0.25, 0.25))
	_push(_scratches, decal, MAX_SCRATCHES)


func _leave_footprint(pos: Vector3) -> void:
	var heading := entity.global_transform.basis.z
	heading.y = 0.0
	heading = heading.normalized()
	var side := Vector3(-heading.z, 0.0, heading.x) * (FOOT_SPREAD if _left_foot else -FOOT_SPREAD)
	_left_foot = not _left_foot
	var decal := _make_decal(_footprint_texture, MUD, Vector3(0.3, 0.6, 0.42))
	var basis := Basis(Vector3.UP, atan2(heading.x, heading.z) + randf_range(-0.15, 0.15))
	decal.global_transform = Transform3D(basis, pos + side + Vector3.UP * 0.2)
	_push(_footprints, decal, MAX_FOOTPRINTS)


func _make_decal(texture: Texture2D, color: Color, size: Vector3) -> Decal:
	var decal := Decal.new()
	decal.texture_albedo = texture
	decal.modulate = color
	decal.size = size
	decal.upper_fade = 0.1
	decal.lower_fade = 0.1
	decal.cull_mask = 1
	add_child(decal)
	return decal


func _push(list: Array[Decal], decal: Decal, limit: int) -> void:
	list.append(decal)
	if list.size() > limit:
		list.pop_front().queue_free()


func _near_cabin(pos: Vector3) -> bool:
	for link in entity.world.entries():
		if Entity._flat_distance(pos, link.start_position) < OUTDOOR_TRACK_RADIUS:
			return true
	return false


# ─── Procedural textures ─────────────────────────────────────────────────────

## A three-toed clawed print, 16x24 px. Texture "up" (v = 0) is the toe end.
static func _draw_footprint() -> Image:
	var img := Image.create(16, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := Color(1, 1, 1, 1)
	# Heel pad.
	for y in range(13, 22):
		for x in range(4, 12):
			var dx := (x - 7.5) / 4.0
			var dy := (y - 17.0) / 4.5
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, ink)
	# Three long toes ending in claws.
	for toe in [[3, -1], [8, 0], [12, 1]]:
		var x: int = toe[0]
		var lean: int = toe[1]
		for y in range(3, 13):
			var tx := clampi(x + int(lean * (12 - y) / 5.0), 0, 15)
			img.set_pixel(tx, y, ink)
			if y > 6:
				img.set_pixel(clampi(tx + 1, 0, 15), y, ink)
		img.set_pixel(clampi(x + lean * 2, 0, 15), 1, ink)
		img.set_pixel(clampi(x + lean * 2, 0, 15), 2, ink)
	return img


## Four ragged parallel gouges, 32x32 px.
static func _draw_scratches() -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for line in 4:
		var x := 7.0 + line * 5.0
		for y in range(2 + line, 29 - line):
			x += rng.randf_range(-0.5, 0.6)
			var alpha := 1.0 if y > 4 and y < 26 else 0.5
			img.set_pixel(clampi(int(x), 0, 31), y, Color(1, 1, 1, alpha))
			if rng.randf() < 0.6:
				img.set_pixel(clampi(int(x) + 1, 0, 31), y, Color(1, 1, 1, alpha * 0.7))
	return img
