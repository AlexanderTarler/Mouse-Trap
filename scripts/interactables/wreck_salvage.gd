extends StaticBody3D

## The car part item this wreck contains.
## Assign an ItemData .tres resource (e.g., car_part_battery.tres) in the Inspector.
@export var item_resource: ItemData

## An inner-monologue message shown when the player interacts BEFORE Day 3.
## Each wreck should have a unique sarcastic message about the abandoned car.
## When Day 3 arrives, the player can salvage the part instead.
@export_multiline var inner_monologue: String = ""

## Tracks whether the player has already looted this specific car.
var is_looted: bool = false

## Tracks whether the inner monologue has been shown (so it doesn't repeat).
var _monologue_shown: bool = false



func _ready() -> void:
	# Add to x-ray highlight group for the car part finding objective.
	add_to_group("xray_car_wreck")
	# Specific wreck group for individual targeting. Uses node name to determine
	# which wreck this is (car_wreck_1, car_wreck_2, car_wreck_3).
	match name.to_lower():
		"car_wreck_1", "carwreck1", "wreck_1":
			add_to_group("xray_wreck_1")
		"car_wreck_2", "carwreck2", "wreck_2":
			add_to_group("xray_wreck_2")
		"car_wreck_3", "carwreck3", "wreck_3":	add_to_group("xray_wreck_3")


## Triggered when the player looks at the car and presses the interact key.
	# BUG 1 FIX: Ensure Layer 2 ("Interactable") is active — must run AFTER any
	# bare 'collision_layer = N' assignment in _ready so it cannot be overwritten.
	set_collision_layer_value(1, true)
	set_collision_layer_value(2, true)

func interact(player: Node3D = null) -> void:
	print("[Wreck] interact() CALLED — is_looted=", is_looted, " | item_resource=", item_resource)
	
	# ─── TASK 2.1: EXHAUSTED GATE ────────────────────────────────
	# When the player is exhausted (Day 3+), they are too tired to salvage
	# car wrecks. The interaction is blocked with a greyed-out message.
	# Standard doors/locks remain interactable — only resource-gathering
	# interactions are disabled while exhausted.
	var player_ref = player if player else get_tree().get_first_node_in_group("player")
	if player_ref and "is_exhausted" in player_ref and player_ref.is_exhausted:
		_show_hud_message("I am too tired to do this...")
		print("[Wreck] BLOCKED: Player is exhausted.")
		return
	
	# ─── ALREADY LOOTED ─────────────────────────────────────────
	if is_looted:
		_show_hud_message("It's completely stripped. Nothing useful left.")
		print("[Wreck] BLOCKED: Already looted.")
		return
	
	# ─── BEFORE DAY 3: Inner monologue only, NO item given ──────
	# The player notices the wrecks and makes sarcastic observations,
	# but can only actually scavenge them once desperation sets in.
	if _is_before_day_3():
		if inner_monologue.length() > 0 and not _monologue_shown:
			_show_hud_message(inner_monologue)
			_monologue_shown = true
			print("[Wreck] Inner monologue shown (before Day 3). Item NOT given.")
		elif _monologue_shown:
			print("[Wreck] Monologue already shown previously, skipping.")
		else:
			print("[Wreck] No inner_monologue set, but before Day 3. No action.")
		return
	
	# ─── DAY 3: only once the van has been looked at again ───────
	# ("Investigate the car again."): until then there's no telling which
	# parts it needs.
	if not _van_checked():
		_show_hud_message("I should take a proper look at the van first.")
		return

	# ─── DAY 3+: Salvage the car part ───────────────────────────
	if not item_resource:
		print("[Wreck] ERROR: item_resource is NULL!")
		_show_hud_message("Nothing useful here.")
		return
	
	var inventory: Node = _get_inventory()
	if not inventory:
		print("[Wreck] ERROR: Could not find Inventory autoload!")
		_show_hud_message("I can't take this right now.")
		return
	
	var added: bool = inventory.add_item(item_resource)
	if not added:
		_show_hud_message("I can't carry any more.")
		return
	
	# Mark as looted and clear x-ray highlight
	is_looted = true
	var item_name := _get_item_name()
	_show_hud_message("This %s should work in the van." % item_name.to_lower())
	
	# ─── AUDIO FEEDBACK ──────────────────────────────────────────────
	var hsm := get_node_or_null("/root/HorrorSoundManager")
	if hsm and hsm.has_method("play_sound"):
		hsm.play_sound("scrap_salvage", global_position)
	
	# ─── VISUAL FEEDBACK: Brief spark particle burst ────────────────
	_spawn_salvage_spark_particles()
	
	print("[Wreck] SUCCESS: Player salvaged '", item_name, "'. is_looted now true.")
	
	# Clear x-ray highlight for this specific wreck
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("clear_highlight"):
		var group_name = _get_xray_group_name()
		if not group_name.is_empty():
			rm.clear_highlight(group_name)


## Returns the x-ray group name for this specific wreck based on node name.
func _get_xray_group_name() -> String:
	var name_lower = name.to_lower()
	match name_lower:
		"car_wreck_1", "carwreck1", "wreck_1":
			return "xray_wreck_1"
		"car_wreck_2", "carwreck2", "wreck_2":
			return "xray_wreck_2"
		"car_wreck_3", "carwreck3", "wreck_3":
			return "xray_wreck_3"
	return ""


## Returns true if the game hasn't reached Day 3 yet.
func _is_before_day_3() -> bool:
	var nm = get_node_or_null("/root/NightManager")
	if nm and "current_night" in nm:
		return nm.current_night < 3
	return false


func _get_inventory():
	var inv = get_node_or_null("/root/Inventory")
	if inv:
		return inv
	var candidates = get_tree().get_nodes_in_group("inventory")
	if candidates.size() > 0:
		return candidates[0]
	return null


func _get_item_name() -> String:
	if item_resource and "item_name" in item_resource:
		return str(item_resource.item_name)
	if item_resource and "resource_path" in item_resource:
		var path := str(item_resource.resource_path)
		return path.get_file().get_basename()
	return "Unknown Part"


func _spawn_salvage_spark_particles() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "SalvageSparkParticles"
	particles.one_shot = true
	particles.emitting = false
	particles.amount = 20
	particles.lifetime = 0.8
	particles.explosiveness = 0.9
	particles.randomness = 0.5
	particles.position = Vector3.UP * 1.0   # (a child: placed by its parent)
	
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 180.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 3.0
	mat.gravity = Vector3(0.0, -3.0, 0.0)
	mat.color = Color(1.0, 0.7, 0.1, 1)  # Orange sparks
	mat.scale_min = 0.05
	mat.scale_max = 0.15
	particles.process_material = mat
	
	add_child(particles)
	particles.emitting = true
	
	# Auto-remove after lifetime
	get_tree().create_timer(1.5).timeout.connect(particles.queue_free)


## Whether the van has been investigated on Day 3 (RoutineManager.van_inspected).
func _van_checked() -> bool:
	var rm := get_node_or_null("/root/RoutineManager")
	return rm == null or bool(rm.get("van_inspected"))


func get_interact_text() -> String:
	if is_looted:
		return ""
	# ─── TASK 2.1: EXHAUSTED INTERACTION PROMPT ──────────────────
	# When exhausted, grey out the interaction prompt instead of
	# showing the normal "Press E" text. The player is too tired.
	var player_ref = get_tree().get_first_node_in_group("player")
	if player_ref and "is_exhausted" in player_ref and player_ref.is_exhausted:
		return "Too tired to do this"
	var item_name := _get_item_name()
	if _is_before_day_3() or not _van_checked():
		var nm = get_node_or_null("/root/NightManager")
		if nm and "current_night" in nm and nm.current_night == 0:
			return ""
		return "[E] Examine the wreck"
	return "[E] Salvage " + item_name


func _show_hud_message(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(msg, self)
	else:
		print("[Wreck HUD Missing] ", msg)
