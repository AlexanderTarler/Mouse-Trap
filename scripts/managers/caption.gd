class_name Caption
extends RefCounted
## Calls the Captions autoload (looked up by path, so scripts using this
## compile without the autoloads, as the tests need). Nothing happens when
## captions are off.
##
##   Caption.at(self, "glass breaking", global_position)


static func at(from: Node, text: String, where: Vector3) -> void:
	var captions := _captions(from)
	if captions:
		captions.show_at(text, where)


static func text(from: Node, words: String) -> void:
	var captions := _captions(from)
	if captions:
		captions.show_text(words)


static func _captions(from: Node) -> Node:
	if from == null or not from.is_inside_tree():
		return null
	return from.get_node_or_null("/root/Captions")
