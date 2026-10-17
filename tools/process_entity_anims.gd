extends SceneTree
## Makes Mixamo animations usable on the Entity (MonsterModel's GeneralSkeleton)
## and saves them to res://assets/animations/entity/<name>.anim, which the
## Entity's animation library (scenes/monster_entity.tscn) uses.
##
## The FBX files are imported retargeted to the humanoid skeleton (their
## .import has the same bone map as the older animations), but their hips
## position track comes through in Mixamo's units (standing is about 5.6),
## while playback expects it normalized (standing = 1.0, which the skeleton's
## motion_scale turns into the Entity's own hips height), so the body
## floated metres up. The
## older animations get away with that track switched off (they never leave
## their stance); these crouch, fall, crawl and die, so the track is kept and
## scaled down to the Entity instead. Looping ones are also kept in place
## (whatever distance one loop travels is taken out, or it would jump back
## each time round).
##
## Run after adding or reimporting one of them:
##   godot --headless --path . --script res://tools/process_entity_anims.gd

const SRC := "res://assets/animations/"
const OUT := "res://assets/animations/entity/"
## Mixamo's standing hips height in these files; played back, a hips
## position is multiplied by the skeleton's motion_scale, so standing is 1.0.
const SOURCE_STANDING_HIPS := 5.6
const NORMALIZED_STANDING_HIPS := 1.0

## FBX name -> [saved name, loops, in place (travel taken out; loops are)]
const ANIMS := {
	"Crouching Idle": ["crouching_idle", true],
	"Looking Around": ["looking_around", true],
	"Low Crawl": ["low_crawl", true],
	"Zombie Punching": ["zombie_punching", true],
	"Mutant Roaring": ["mutant_roaring", false],
	"Zombie Reaction Hit": ["zombie_reaction_hit", false],
	"Zombie Neck Bite": ["zombie_neck_bite", false],
	"Zombie Dying": ["zombie_dying", false],
	"Falling To Landing": ["falling_to_landing", false],
	# Through a window (EntityStateEnter / Entity._traverse): moved by the
	# game, so their forward travel is taken out as a loop's is.
	"entity/Entity Climbing Inside Upper Floor": ["climb_in_upper", false, true],
	"entity/Entity Dive Through Bottom Floor Windows": ["dive_in_lower", false, true],
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var failed := false
	for source in ANIMS:
		var out_name: String = ANIMS[source][0]
		var loops: bool = ANIMS[source][1]
		var in_place: bool = loops or (ANIMS[source].size() > 2 and ANIMS[source][2])
		var scene: Node = load(SRC + source + ".fbx").instantiate()
		var player := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var anim := player.get_animation(player.get_animation_list()[0]).duplicate(true) as Animation
		scene.free()
		var hips := -1
		for i in anim.get_track_count():
			if str(anim.track_get_path(i)).ends_with(":Hips") and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
				hips = i
		if hips >= 0:
			var k := NORMALIZED_STANDING_HIPS / SOURCE_STANDING_HIPS
			var count := anim.track_get_key_count(hips)
			var first: Vector3 = anim.track_get_key_value(hips, 0)
			var drift: Vector3 = anim.track_get_key_value(hips, count - 1) - first
			drift.y = 0.0
			for key in count:
				var value: Vector3 = anim.track_get_key_value(hips, key)
				if in_place and anim.length > 0.0:
					value -= drift * (anim.track_get_key_time(hips, key) / anim.length)
				anim.track_set_key_value(hips, key, value * k)
		anim.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
		anim.resource_name = out_name
		var err := ResourceSaver.save(anim, OUT + out_name + ".anim")
		print("[ANIMS] %-22s -> %s%s.anim  %.2f s%s  (%s)" % [source, OUT, out_name, anim.length,
			", loops" if loops else "", error_string(err)])
		failed = failed or err != OK or hips < 0
	print("[ANIMS] %s" % ("FAILED" if failed else "DONE"))
	quit(1 if failed else 0)
