extends RigidBody3D

@export var item_name: String = "Item"
@export var item_description: String = "A mysterious object."
@export var item_icon: Texture2D = null

func _ready() -> void:
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

func pick_up() -> void:
	# Called by the interaction manager when the player picks this up
	hide()
	# We don't queue_free because the interaction manager keeps a reference
	# and will reposition it

func drop() -> void:
	show()

func interact() -> void:
	# Called when pressing E on this item (quick interact)
	print("Item: ", item_name, " - ", item_description)
