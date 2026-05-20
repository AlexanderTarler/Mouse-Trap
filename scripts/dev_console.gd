extends StaticBody3D

## Developer Console - Debug tool to force night mode.
## Place this inside the cabin scene. When the player interacts with it,
## it instantly forces the world to become night via GameTime.
##
## Interaction standard: The raycast in interaction_manager.gd hits the
## CollisionShape3D child of this StaticBody3D, then walks up the parent
## chain to find a node with interact(). PhysicalGrab calls interact()
## with no arguments (quick tap E).

func _ready():
	# Ensure the CollisionShape3D is set up for the raycast to detect.
	pass

func interact():
	## Called by physical_grab.gd when the player quick-taps E while looking
	## at this object. Forces the world to night via GameTime autoload.
	
	# Access the GameTime autoload directly (no Engine.has_singleton)
	var gt = get_node_or_null("/root/GameTime")
	if not gt:
		push_error("[DEV CONSOLE] Could not find GameTime autoload at /root/GameTime")
		return
	
	# Set progress to 0.51 (just past dusk, into night)
	gt.set_progress(0.51)
	
	# Unpause time so the cycle starts advancing from this point
	gt.unpause_time()
	
	print("[DEBUG] Developer Console used! Time forced to 0.51 (Night 2).")
