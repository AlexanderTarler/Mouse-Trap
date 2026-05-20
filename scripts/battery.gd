extends Area3D

# This creates a "slot" in the Inspector for your data
@export var item_resource: ItemData 

func _ready():
	# Now this node "knows" what it is based on the resource
	if item_resource:
		print("I am a: ", item_resource.item_name)
