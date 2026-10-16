extends SceneTree
## Every page of the field notebook (the notes added, opened, laid out)
## measured against the page: prints any that overflow. Renders, so run
## WITHOUT --headless (headless runs never lay the notebook out).
##   godot --path . --resolution 1280x720 --script res://tools/journal_pages.gd
func _initialize():
	_go()
func _go():
	await process_frame
	var s = load("res://scenes/cottage_horror.tscn").instantiate()
	s.get_node("Player").start_in_dev_mode = false
	root.add_child(s)
	current_scene = s
	for i in 60:
		await process_frame
	var nb = get_first_node_in_group("notebook_ui")
	for r in ["arvid_note", "arvid_note_2", "field_journal_note", "porch_light_note", "research_map_note"]:
		var item = load("res://resources/%s.tres" % r)
		nb.add_note(item.note_text)
	nb._toggle()
	for i in 10:
		await process_frame
	var size: Vector2 = nb._page_size()
	print("[PAGES] page %s, %d pages, measured %s" % [size, nb._all_pages.size(), nb._paged_by_size])
	var over := 0
	nb.current_spread = 1
	nb._update_spread()
	await process_frame
	for i in nb._all_pages.size():
		nb._doc_label.text = nb._all_pages[i]
		await process_frame
		var h: float = nb._doc_label.get_content_height()
		if h > size.y + 1.0:
			over += 1
			print("[PAGES] page %d too tall: %.0f > %.0f: %s" % [i, h, size.y, nb._all_pages[i].substr(0, 60)])
	print("[PAGES] overflowing: %d" % over)
	quit()
