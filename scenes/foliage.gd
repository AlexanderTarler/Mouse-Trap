extends MultiMeshInstance3D

## ─── PERFORMANCE: Visibility Range Culling ───────────────────────────────────
## The Godot 4 visibility_range system automatically culls meshes from rendering
## when they are beyond this distance from the camera. Without this, every blade
## of grass in the entire forest is rendered every frame.
## 
## For a PSX-style dense forest, grass culling at 40m is imperceptible because
## the grass blends into the ground texture at that distance anyway.
##
## NOTE: visibility_range_end and visibility_range_fade_mode are inherited from
## GeometryInstance3D, so we do NOT redeclare them as @export. They are set
## directly in _ready().

func _ready() -> void:
	# Apply visibility range culling at runtime.
	# Grass beyond 40m from the camera is not rendered.
	# Fade mode = SELF (smooth alpha fade-out) to avoid pop-in.
	self.visibility_range_end = 40.0
	self.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF