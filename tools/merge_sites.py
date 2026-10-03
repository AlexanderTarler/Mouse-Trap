"""Appends the props tools/bake_sites.gd wrote out to the level's .tscn, as
text, leaving everything else in the file as it was:

  - sites.tscn: a "Sites" node with the props (and their colliders), added
    to the level's root;
  - fixes.json: the barn's doors (moved onto its doorway, open, with
    colliders: the barn instance becomes editable for that) and colliders
    for drums and barriers already in the level.

Usage: python tools/merge_sites.py <folder bake_sites.gd wrote to>
"""
import json
import random
import re
import sys
from pathlib import Path

LEVEL = Path(__file__).resolve().parent.parent / "scenes" / "cottage_horror.tscn"
BARN = "SM_EC_Barn_02_Body"
# The doors' node ids inside the barn's own scene (an override names them).
DOOR_IDS = {"SM_EC_Barn_Door_04": 1859014387, "SM_EC_Barn_Door_05": 382844610}


def blocks(text):
    """The file as [header line + its body] blocks."""
    out = []
    for chunk in re.split(r"\n(?=\[)", text.strip("\n")):
        out.append(chunk.strip("\n"))
    return out


def fmt(n):
    s = repr(float(n))
    if s.endswith(".0"):
        s = s[:-2]
    return "0" if s == "-0" else s


def transform(values):
    return "Transform3D(%s)" % ", ".join(fmt(v) for v in values)


def uid():
    return random.randint(1, 2**31 - 1)


def main():
    folder = Path(sys.argv[1])
    level_text = LEVEL.read_text(encoding="utf-8")
    newline = "\r\n" if "\r\n" in level_text else "\n"
    level_text = level_text.replace("\r\n", "\n")
    if re.search(r'^\[node name="Sites" ', level_text, re.M):
        sys.exit("The level already has a Sites node.")
    level = blocks(level_text)
    sites = blocks((folder / "sites.tscn").read_text(encoding="utf-8").replace("\r\n", "\n"))
    fixes = json.loads((folder / "fixes.json").read_text(encoding="utf-8"))

    # Ext resources: reuse the level's for the same file, else add (new ids).
    existing = {}
    for b in level:
        m = re.match(r'\[ext_resource type="PackedScene"[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"', b)
        if m:
            existing[m.group(1)] = m.group(2)
    ext_map, new_ext = {}, []
    for b in sites:
        m = re.match(r'\[ext_resource type="([^"]+)" path="([^"]+)" id="([^"]+)"\]', b)
        if not m:
            continue
        kind, path, old = m.groups()
        if path in existing:
            ext_map[old] = existing[path]
        else:
            new_id = "site_" + old
            ext_map[old] = new_id
            new_ext.append('[ext_resource type="%s" path="%s" id="%s"]' % (kind, path, new_id))

    # Sub resources (the collider boxes): new ids.
    sub_map, new_sub = {}, []
    for b in sites:
        m = re.match(r'\[sub_resource type="([^"]+)" id="([^"]+)"\]', b)
        if m:
            new_id = m.group(2).replace("_", "_site_", 1)
            sub_map[m.group(2)] = new_id
            new_sub.append(b.replace('id="%s"' % m.group(2), 'id="%s"' % new_id, 1))

    # Nodes: the Sites root goes under the level's root, everything else
    # under Sites.
    new_nodes = []
    for b in sites:
        if not b.startswith("[node "):
            continue
        head, _, body = b.partition("\n")
        if ' parent="' not in head:
            head = head.replace('[node name="Sites" type="Node3D"', '[node name="Sites" type="Node3D" parent="."', 1)
        else:
            head = re.sub(r' parent="\."', ' parent="Sites"', head)
            head = re.sub(r' parent="(?!Sites")([^"]+)"', r' parent="Sites/\1"', head)
        head = re.sub(r'ExtResource\("([^"]+)"\)', lambda m: 'ExtResource("%s")' % ext_map[m.group(1)], head)
        body = re.sub(r'SubResource\("([^"]+)"\)', lambda m: 'SubResource("%s")' % sub_map[m.group(1)], body)
        new_nodes.append(head + ("\n" + body if body else ""))

    # The fixes.
    box_n = [0]

    def collider_nodes(parent, colliders):
        out = []
        for c in colliders:
            box_n[0] += 1
            box_id = "BoxShape3D_sitefix%d" % box_n[0]
            new_sub.append('[sub_resource type="BoxShape3D" id="%s"]\nsize = Vector3(%s)' % (box_id, ", ".join(fmt(v) for v in c["size"])))
            out.append('[node name="%s" type="StaticBody3D" parent="%s" unique_id=%d]' % (c["body"], parent, uid()))
            out.append('[node name="CollisionShape3D" type="CollisionShape3D" parent="%s/%s" unique_id=%d]\ntransform = %s\nshape = SubResource("%s")'
                       % (parent, c["body"], uid(), transform(c["transform"]), box_id))
        return out

    for door in fixes["doors"]:
        new_nodes.append('[node name="%s" parent="%s" unique_id=%d]\ntransform = %s'
                         % (door["name"], BARN, DOOR_IDS[door["name"]], transform(door["transform"])))
        new_nodes += collider_nodes("%s/%s" % (BARN, door["name"]), door["colliders"])
    for fix in fixes["colliders"]:
        new_nodes += collider_nodes(fix["path"], fix["colliders"])

    # Put it together: ext resources after the last ext resource, sub
    # resources before the first node, nodes before the editable-path list,
    # the barn's editable path last.
    last_ext = max(i for i, b in enumerate(level) if b.startswith("[ext_resource"))
    level[last_ext + 1:last_ext + 1] = new_ext
    first_node = next(i for i, b in enumerate(level) if b.startswith("[node "))
    level[first_node:first_node] = new_sub
    first_editable = next((i for i, b in enumerate(level) if b.startswith("[editable ")), len(level))
    level[first_editable:first_editable] = new_nodes
    if '[editable path="%s"]' % BARN not in level:
        level.append('[editable path="%s"]' % BARN)

    out = "\n\n".join(level) + "\n"
    # The editable paths sit one per line, without blank lines between.
    out = re.sub(r'(\[editable path="[^"]+"\])\n\n(?=\[editable )', r"\1\n", out)
    LEVEL.write_text(out.replace("\n", newline), encoding="utf-8", newline="")
    print("Merged %d ext resources, %d sub resources, %d nodes into %s." % (len(new_ext), len(new_sub), len(new_nodes), LEVEL.name))


if __name__ == "__main__":
    main()
