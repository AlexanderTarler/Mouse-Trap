class_name TerrainMask
extends RefCounted
## Reads what the terrain is painted with at a point (TerraBrush's splatmap,
## one pixel per metre, centred on the origin):
##   red   - grass (clearings, the yard)
##   green - walking paths
##   blue  - forest floor
##   alpha - worn grass (path verges, around the cabin)
## Used to keep the walking paths clear when the forest and the world details
## are placed (ForestDresser, WorldDetails), and by tools/paint_terrain.gd.

const SPLATMAP_PATH := "res://scenes/CottageHorror/Splatmap_0_0_0.res"
## World position of pixel (0, 0)'s centre is (-HALF, -HALF).
const HALF := 127.5

static var _image: Image = null
## The most path paint in each BLOCK x BLOCK block of pixels, so near_path()
## can answer "no" at once far from any path (the forest asks tens of
## thousands of times as the level loads).
const BLOCK := 8
static var _block_max := PackedFloat32Array()
static var _blocks_across := 0


static func image() -> Image:
	if _image == null and ResourceLoader.exists(SPLATMAP_PATH):
		_image = load(SPLATMAP_PATH)
	return _image


## The paint weights at a world point (bilinear), or grass outside the map.
static func sample(point: Vector3) -> Color:
	var img := image()
	if img == null:
		return Color(1, 0, 0, 0)
	var x := point.x + HALF
	var y := point.z + HALF
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var top := _pixel(img, x0, y0).lerp(_pixel(img, x0 + 1, y0), fx)
	var bottom := _pixel(img, x0, y0 + 1).lerp(_pixel(img, x0 + 1, y0 + 1), fx)
	return top.lerp(bottom, fy)


static func _pixel(img: Image, x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return Color(1, 0, 0, 0)
	return img.get_pixel(x, y)


## How much of a walking path there is at `point` (0-1).
static func path(point: Vector3) -> float:
	return sample(point).g


## True if anything placed at `point` would stand on (or within `margin` m of)
## a walking path.
static func near_path(point: Vector3, margin: float = 0.8, threshold: float = 0.1) -> bool:
	# Every pixel the samples below read has less paint than this: none of
	# them can be over it. (A hair under, so rounding never decides.)
	if _most_path_near(point, margin) < threshold - 0.0001:
		return false
	if path(point) > threshold:
		return true
	for offset in [Vector3(margin, 0, 0), Vector3(-margin, 0, 0), Vector3(0, 0, margin), Vector3(0, 0, -margin)]:
		if path(point + offset) > threshold:
			return true
	return false


## Forgets the loaded splatmap (after it has been repainted).
static func reload() -> void:
	_image = null
	_block_max = PackedFloat32Array()


## The most path paint among the pixels within `margin` m of `point` (and
## their neighbours, which the bilinear samples blend in).
static func _most_path_near(point: Vector3, margin: float) -> float:
	var img := image()
	if img == null:
		return 0.0
	if _block_max.is_empty():
		_blocks_across = ceili(img.get_width() / float(BLOCK))
		var blocks_down := ceili(img.get_height() / float(BLOCK))
		_block_max.resize(_blocks_across * blocks_down)
		for y in img.get_height():
			for x in img.get_width():
				var i := (y / BLOCK) * _blocks_across + x / BLOCK
				_block_max[i] = maxf(_block_max[i], img.get_pixel(x, y).g)
	var x0 := clampi(floori(point.x - margin + HALF), 0, img.get_width() - 1)
	var x1 := clampi(floori(point.x + margin + HALF) + 1, 0, img.get_width() - 1)
	var y0 := clampi(floori(point.z - margin + HALF), 0, img.get_height() - 1)
	var y1 := clampi(floori(point.z + margin + HALF) + 1, 0, img.get_height() - 1)
	var most := 0.0
	for by in range(y0 / BLOCK, y1 / BLOCK + 1):
		for bx in range(x0 / BLOCK, x1 / BLOCK + 1):
			most = maxf(most, _block_max[by * _blocks_across + bx])
	return most
