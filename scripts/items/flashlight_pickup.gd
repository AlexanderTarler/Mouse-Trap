extends RigidBody3D

## Flashlight pickup item in the world.
## When the player interacts (presses E), the player's built-in flashlight is enabled.
## The player cannot use their flashlight until they pick this up.

@export var item_data: ItemData


func _ready() -> void:
	add_to_group("xray_flashlight")
	
	# Ensure this RigidBody3D can be detected by the interaction manager's raycast
	# Layer 2 ("Interactable") added — the interaction ray only
	# raycasts against layer 2, so every pickup must opt in (1|2 = 3).
	collision_layer = 1 | 2
	
	# Make the item glow slightly so it's noticeable
	var mesh = get_node_or_null("MeshInstance3D")
	if mesh:
		var mat = mesh.get_surface_override_material(0)
		if not mat:
			mat = StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission = Color(1, 1, 0.5, 0.3)
		mat.emission_energy_multiplier = 0.5
		mesh.set_surface_override_material(0, mat)


func interact() -> void:
	
	# Find the player and enable their flashlight
	var player = get_tree().get_first_node_in_group("player")
	
	if player and player.has_method("enable_flashlight"):
		player.enable_flashlight()
		print("[FlashlightPickup] Flashlight enabled for player!")
		
		# ─── DAY 1 ONBOARDING: PHASE 2 — FLASHLIGHT PICKED UP ────
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_flashlight_picked_up"):
			rm.on_flashlight_picked_up()
		
		# ─── FLASHLIGHT TUTORIAL — NIGHT 1 + HAS FLASHLIGHT GATE ──
		# The "Press [F] to turn the flashlight on and off." hint fires the
		# first time Night 1 coincides with the player having the flashlight.
		# try_trigger_flashlight() no-ops unless it is Night 1, and the
		# one_shot guard prevents duplicate display. This handles the case
		# where the player picks up the flashlight AFTER Night 1 began
		# (TutorialManager._on_night_started ran before they had it).
		var tm = get_node_or_null("/root/TutorialManager")
		if tm and tm.has_method("try_trigger_flashlight"):
			tm.try_trigger_flashlight()
		
		queue_free()
	else:
		print("[FlashlightPickup] Could not find player or enable_flashlight method!")


func get_interact_text() -> String:
	return "[E] Pick up Flashlight"
