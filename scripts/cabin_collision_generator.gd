extends Node3D

## Cabin Collision Generator
##
## This script is disabled. The FBX cabins are single solid meshes
## with no door holes, so auto-generated collision blocks doorways.
##
## To add wall collision manually in the editor:
## 1. Right-click on this node -> Add Child Node -> StaticBody3D
## 2. Right-click on that -> Add Child Node -> CollisionShape3D
## 3. Set the shape to BoxShape3D
## 4. Position and scale to match cabin walls
## 5. Leave gaps for doorways
##
## For reference, here are the cabin dimensions:
##   Cabin One:   center=(0, 0, -0.86), size=(14.2, 8.5, 7.0)
##   Cabin Three: center=(0, 0, 14.88), size=(14.2, 14.2, 10.4)
##   Cabin Two:   center=(0, 0, -14.07), size=(14.2, 14.3, 7.3)

func _ready() -> void:
	# This script intentionally does nothing.
	# Wall colliders should be added manually in the editor.
	pass
