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
	if path(point) > threshold:
		return true
	for offset in [Vector3(margin, 0, 0), Vector3(-margin, 0, 0), Vector3(0, 0, margin), Vector3(0, 0, -margin)]:
		if path(point + offset) > threshold:
			return true
	return false


## Forgets the loaded splatmap (after it has been repainted).
static func reload() -> void:
	_image = null
