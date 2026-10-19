class_name ShaderWarmup
extends Node
## The web build (the Compatibility renderer) compiles a material's shader the
## first time it's drawn under a given set of lights, and in a browser that
## takes long: walking up to the willow froze the game for seconds (its
## clearing, the crows and stones, and at night the ground under the totem's
## glow, all drawn for the first time). So at the start of a game, behind
## the black start screen, a camera of its own looks at the willow from a
## few distances, by day and with the totem up and glowing, a few frames
## each: the shaders are compiled then, not when the player gets there.
##
##   if ShaderWarmup.needed(): await ShaderWarmup.new().run(scene)
##
## NightManager does it before the opening, and on Continue (the start
## cover is up). With the totem up it also makes the purge's effects once
## (TotemAnchor.warm_effects): made for the first time at the willow, they
## froze the game there.

const WILLOW := Vector3(103.0, 0.0, 85.3)
## Where the camera looks from (offsets from the willow, m) and for how many
## frames.
const VIEWS := [Vector3(-24.0, 2.0, -12.0), Vector3(-12.0, 1.7, -6.0), Vector3(-4.0, 1.6, -2.5),
	Vector3(3.0, 1.6, -3.5), Vector3(0.0, 1.6, 4.5), Vector3(8.0, 2.0, 10.0)]
const FRAMES_PER_VIEW := 3


## Not headless (nothing is drawn). Every renderer: on Windows (Forward+)
## the purge's effects froze the game for seconds on a fresh install, as
## the willow did in the browser.
static func needed() -> bool:
	return DisplayServer.get_name() != "headless"


func run(scene: Node) -> void:
	var tree := scene.get_tree()
	var previous := scene.get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	camera.name = "ShaderWarmupCamera"
	camera.far = 200.0
	scene.add_child(camera)
	camera.current = true
	var started := Time.get_ticks_msec()
	# By day (as it is), then with the totem up and its glow on.
	var totem := tree.get_first_node_in_group("totem_anchor") as Node3D
	var totem_y := totem.global_position.y if totem else 0.0
	for raised in [false, true]:
		if totem and raised and "_original_y" in totem:
			totem.global_position.y = totem._original_y
		for offset: Vector3 in VIEWS:
			var ground := WILLOW + Vector3(offset.x, 0.0, offset.z)
			camera.global_position = ground + Vector3.UP * offset.y
			camera.look_at(WILLOW + Vector3.UP * 2.0)
			for i in FRAMES_PER_VIEW:
				await RenderingServer.frame_post_draw
	# The purge, with the totem up: the embers, the ash, the charred willow
	# (TotemAnchor.warm_effects), seen from close by for a moment.
	if totem and totem.has_method("warm_effects"):
		var effects: Array[Node] = totem.warm_effects()
		var close: Vector3 = VIEWS[2]
		camera.global_position = WILLOW + Vector3(close.x, close.y, close.z)
		camera.look_at(WILLOW + Vector3.UP * 2.5)
		for i in FRAMES_PER_VIEW * 3:
			await RenderingServer.frame_post_draw
		for node in effects:
			if is_instance_valid(node):
				node.queue_free()
	if totem:
		totem.global_position.y = totem_y
	camera.queue_free()
	if previous and is_instance_valid(previous):
		previous.current = true
	print("[ShaderWarmup] The willow's shaders compiled (%d ms)." % (Time.get_ticks_msec() - started))
