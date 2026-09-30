extends SceneTree
## Bakes both navigation meshes of the level and saves them to their resource
## files, so the navmesh can be rebuilt without opening the editor:
##   - NavigationRegion3D (exterior)                 -> res://navigation/exterior_navmesh.res
##   - NavigationRegion3D/Cabin/NavigationRegion3D   -> res://navigation/cabin_interior_navmesh.res
## The scene only references these files, so it is not modified. Baking in
## the editor still works the same way and writes to the same files.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tools/bake_navmesh.gd
## If the editor has the level open, reopen the scene afterwards so it picks up
## the new files.

const SCENE := "res://scenes/cottage_horror.tscn"
const REGIONS := ["NavigationRegion3D", "NavigationRegion3D/Cabin/NavigationRegion3D"]


func _initialize() -> void:
	_run()


func _run() -> void:
	var scene: Node = load(SCENE).instantiate()
	# Bake the normal game state, whatever the level's dev-mode toggle says.
	scene.get_node("Player").start_in_dev_mode = false
	root.add_child(scene)
	for i in 3:
		await physics_frame
	var failed := false
	for path in REGIONS:
		var region: NavigationRegion3D = scene.get_node(path)
		var mesh := region.navigation_mesh
		if mesh == null or mesh.resource_path.is_empty() or mesh.resource_path.contains("::"):
			push_error("[BAKE] %s has no navigation mesh file to write to" % path)
			failed = true
			continue
		var start := Time.get_ticks_msec()
		region.bake_navigation_mesh(false)
		var err := ResourceSaver.save(mesh, mesh.resource_path)
		print("[BAKE] %-45s %5d polygons in %4d ms -> %s (%s)" % [path, mesh.get_polygon_count(),
			Time.get_ticks_msec() - start, mesh.resource_path, error_string(err)])
		failed = failed or err != OK or mesh.get_polygon_count() == 0
	print("[BAKE] %s" % ("FAILED" if failed else "DONE"))
	quit(1 if failed else 0)
