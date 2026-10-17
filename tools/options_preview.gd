extends SceneTree
## Renders the options menu, one PNG per tab (and the brightness screen).
## Run (windowed): godot --path . --rendering-method gl_compatibility --script res://tools/options_preview.gd -- <out_prefix>


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://options"
	await process_frame
	var back := ColorRect.new()
	back.color = Color(0.1, 0.12, 0.1)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(back)
	var menu: Node = load("res://scenes/ui/options_menu.tscn").instantiate()
	root.add_child(menu)
	menu.show_menu()
	for tab in 4:
		menu._tabs.current_tab = tab
		for i in 20:
			await process_frame
		root.get_texture().get_image().save_png("%s_%d.png" % [prefix, tab])
	var calibration := BrightnessCalibration.new()
	root.add_child(calibration)
	for i in 20:
		await process_frame
	root.get_texture().get_image().save_png("%s_cal.png" % prefix)
	print("[OPTIONS PREVIEW] saved")
	quit()
