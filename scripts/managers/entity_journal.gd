class_name EntityJournal
extends RefCounted
## What the player character has learned about the Entity, written into the
## notebook's "The Entity" chapter (NotebookUI.add_entity_entry) the moment
## he learns it: only what he saw or heard for himself. The first entry
## comes with a thought ("I should write this down."). An entry can be
## rewritten as he learns more (the beam, the second time).
##
##   EntityJournal.learn(self, "beam")

## The entries, in his words, by key.
const ENTRIES := {
	"daylight": "It's gone when the sun is up. It only comes out after dark.",
	"peeker": "Something at the window, watching me. When I looked straight at it, it ducked away.",
	"beam": "It backed off when I held the light on it. Not at once: I had to keep the beam on it.",
	"beam_harder": "It backed off when I held the light on it. The second time it took longer. It's getting used to the light.",
	"lit_room": "It won't stay in a lit room. The lights are worth the fuel.",
	"sound": "It hears me. Running, doors, things I drop. It came straight for the sound.",
	"windows": "It tries the windows. The planks hold it for a while, then they give.",
	"climb": "It climbs. The upstairs windows aren't safe either.",
	"ambush": "It waits in the dark, where I'm going. A breath first, close. Then it comes.",
	"mimicry": "Footsteps when I was alone. Sounds I didn't make. It copies them, like the dormice at Gamma, and they come back slightly wrong.",
}
## Keys that rewrite another entry instead of adding one.
const REWRITES := {"beam_harder": "beam"}


## Writes what was learned (`key` in ENTRIES), if it's new. `from`: any node
## in the tree. True if the notebook changed.
static func learn(from: Node, key: String) -> bool:
	if from == null or not from.is_inside_tree() or not ENTRIES.has(key):
		return false
	var notebook := from.get_tree().get_first_node_in_group("notebook_ui")
	if notebook == null or not notebook.has_method("add_entity_entry"):
		return false
	var slot: String = REWRITES.get(key, key)
	var first: bool = notebook.entity_entry_count() == 0
	if not notebook.add_entity_entry(slot, ENTRIES[key]):
		return false
	print("[EntityJournal] Learned: %s" % key)
	if first:
		var monologue := from.get_node_or_null("/root/Monologue")
		if monologue and monologue.has_method("think_when_free"):
			monologue.think_when_free("I should write this down.", 3.5, "entity_journal_first", 1.2)
	return true


## Whether the player is looking at the Entity right now (in view, in sight).
static func player_sees(entity: Node) -> bool:
	return entity != null and entity.get("perception") != null and entity.perception.in_player_view
