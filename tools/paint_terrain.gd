extends SceneTree
## Paints the terrain's ground textures (TerraBrush splatmap, see TerrainMask):
##   green - the walking paths: kept exactly as painted;
##   alpha - worn grass: a verge fading out from every path, and trampled
##           ground around the cabin;
##   blue  - forest floor under the trees, by how dense they are;
##   red   - grass everywhere else.
## All of it broken up with noise. Rerun after moving tree groups or
## repainting the paths.
##
## Run: godot --headless --path . --script res://tools/paint_terrain.gd

## Verges reach this far from a path (m).
const VERGE_WIDTH := 3.5
## Trampled ground around the cabin: centre and radius (m).
const YARD_CENTRE := Vector2(9.0, 14.0)
const YARD_RADIUS := 15.0


func _initialize() -> void:
	_run()


func _run() -> void:
	var splat: Image = load(TerrainMask.SPLATMAP_PATH)
	var scene: Node = load("res://scenes/cottage_horror.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	# Tree trunks: the tree groups' colliders.
	var trees: Array[Vector2] = []
	for n in scene.find_children("*", "CollisionShape3D", true, false):
		var body: Node = n.get_parent()
		if body is StaticBody3D and body.get_parent() and String(body.get_parent().name).begins_with("Group of Trees"):
			var g: Vector3 = (n as Node3D).global_position
			trees.append(Vector2(g.x, g.z))
	print("Trees: ", trees.size())

	var size := splat.get_width()
	var half := TerrainMask.HALF
	# Tree density: trees within 5 m of each pixel centre.
	var density := PackedFloat32Array()
	density.resize(size * size)
	for t in trees:
		var cx := int(round(t.x + half))
		var cy := int(round(t.y + half))
		for dy in range(-6, 7):
			for dx in range(-6, 7):
				var x := cx + dx
				var y := cy + dy
				if x < 0 or y < 0 or x >= size or y >= size:
					continue
				var d := Vector2(x - half, y - half).distance_to(t)
				if d < 5.0:
					density[y * size + x] += 1.0 - d / 5.0
	# Path proximity: how close the nearest path paint is (1 on it, 0 at VERGE_WIDTH).
	var paths := PackedFloat32Array()
	paths.resize(size * size)
	for y in size:
		for x in size:
			paths[y * size + x] = splat.get_pixel(x, y).g
	var reach := int(ceil(VERGE_WIDTH))
	var verge := PackedFloat32Array()
	verge.resize(size * size)
	for y in size:
		for x in size:
			var best := 0.0
			for dy in range(-reach, reach + 1):
				for dx in range(-reach, reach + 1):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= size or ny >= size:
						continue
					var p := paths[ny * size + nx]
					if p <= 0.05:
						continue
					var falloff := 1.0 - Vector2(dx, dy).length() / VERGE_WIDTH
					best = maxf(best, p * falloff)
			verge[y * size + x] = best

	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.08
	var fine := FastNoiseLite.new()
	fine.seed = 11
	fine.frequency = 0.3
	var counts := [0, 0, 0, 0]
	for y in size:
		for x in size:
			var i := y * size + x
			var path_weight := paths[i]
			var rest := 1.0 - path_weight
			var yard := 1.0 - clampf(Vector2(x - half, y - half).distance_to(YARD_CENTRE) / YARD_RADIUS, 0.0, 1.0)
			var worn := clampf(verge[i] * 0.9 + yard * 0.55 + fine.get_noise_2d(x, y) * 0.25, 0.0, 0.9) * rest
			var forest := smoothstep(2.0, 5.0, density[i] + noise.get_noise_2d(x, y) * 1.2) * 0.85 * (rest - worn)
			var grass := maxf(rest - worn - forest, 0.0)
			splat.set_pixel(x, y, Color(grass, path_weight, forest, worn))
			for c in 4:
				if [grass, path_weight, forest, worn][c] > 0.3:
					counts[c] += 1
	var err := ResourceSaver.save(splat, TerrainMask.SPLATMAP_PATH)
	print("Pixels over 30%%: grass %d, paths %d, forest floor %d, worn grass %d (of %d); saved: %s" % [counts[0], counts[1], counts[2], counts[3], size * size, error_string(err)])
	quit()
