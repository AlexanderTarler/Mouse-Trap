"""Appends the details tools/bake_details.gd wrote out (CabinDetails.tscn,
ForestDetails.tscn) to the level's .tscn, as text, leaving everything else in
the file as it was; and makes the level's own loose props in the cabin that
were fixed (a coin, a bottle, the football) KnockableProps too, so
they can be picked up.

Usage: python tools/merge_details.py <folder bake_details.gd wrote to>
Close the level in the editor first; reopen it afterwards.
"""
import os
import re
import sys
from pathlib import Path

# (MERGE_LEVEL: another copy of the level, to try it on.)
LEVEL = Path(os.environ.get("MERGE_LEVEL") or Path(__file__).resolve().parent.parent / "scenes" / "cottage_horror.tscn")
GROUPS = ["CabinDetails", "ForestDetails"]
KNOCKABLE = "res://scripts/knockable_prop.gd"
# The level's own things in the cabin that become loose: instanced scenes...
LOOSE_INSTANCES = ["coin_mp_12", "glass_bottle_12"]
# ...and plain meshes (KnockableProp.mesh).
LOOSE_MESHES = ["PsxLowPolyHomeInteriorPropsPackFootBallLod0"]


def blocks(text):
    return [chunk.strip("\n") for chunk in re.split(r"\n(?=\[)", text.strip("\n"))]


def main():
    folder = Path(sys.argv[1])
    level_text = LEVEL.read_text(encoding="utf-8")
    newline = "\r\n" if "\r\n" in level_text else "\n"
    level_text = level_text.replace("\r\n", "\n")
    for group in GROUPS:
        if re.search(r'^\[node name="%s" ' % group, level_text, re.M):
            sys.exit("The level already has a %s node." % group)
    level = blocks(level_text)

    existing = {}
    for b in level:
        m = re.match(r'\[ext_resource type="[^"]+"[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"', b)
        if m:
            existing[m.group(1)] = m.group(2)
    new_ext, new_sub, new_nodes = [], [], []

    def ext_id(kind, path, suggested):
        if path not in existing:
            existing[path] = suggested
            new_ext.append('[ext_resource type="%s" path="%s" id="%s"]' % (kind, path, suggested))
        return existing[path]

    for group in GROUPS:
        part = blocks((folder / (group + ".tscn")).read_text(encoding="utf-8").replace("\r\n", "\n"))
        ext_map = {}
        for b in part:
            m = re.match(r'\[ext_resource type="([^"]+)"[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"\]', b)
            if m:
                kind, path, old = m.groups()
                ext_map[old] = ext_id(kind, path, "%s_%s" % (group.lower(), old))
        sub_map = {}
        for b in part:
            m = re.match(r'\[sub_resource type="([^"]+)" id="([^"]+)"\]', b)
            if m:
                sub_map[m.group(2)] = "%s_%s" % (group, m.group(2))

        def fix_refs(text):
            text = re.sub(r'ExtResource\("([^"]+)"\)', lambda m: 'ExtResource("%s")' % ext_map[m.group(1)], text)
            return re.sub(r'SubResource\("([^"]+)"\)', lambda m: 'SubResource("%s")' % sub_map[m.group(1)], text)

        for b in part:
            m = re.match(r'\[sub_resource type="([^"]+)" id="([^"]+)"\]', b)
            if m:
                new_sub.append(fix_refs(b.replace('id="%s"' % m.group(2), 'id="%s"' % sub_map[m.group(2)], 1)))
        for b in part:
            if not b.startswith("[node "):
                continue
            head, _, body = b.partition("\n")
            if ' parent="' not in head:
                head = head.replace('[node name="%s"' % group, '[node name="%s" parent="."' % group, 1)
            else:
                head = re.sub(r' parent="\."', ' parent="%s"' % group, head)
                head = re.sub(r' parent="(?!%s")([^"]+)"' % group, r' parent="%s/\1"' % group, head)
            new_nodes.append(fix_refs(head) + ("\n" + fix_refs(body) if body else ""))

    # The level's own loose things.
    knock = ext_id("Script", KNOCKABLE, "details_knockable")
    converted = 0
    for i, b in enumerate(level):
        head, _, body = b.partition("\n")
        m = re.match(r'\[node name="([^"]+)" parent="([^"]+)" unique_id=(\d+)( groups=\[[^\]]*\])? instance=ExtResource\("([^"]+)"\)\]$', head)
        if m and m.group(1) in LOOSE_INSTANCES:
            name, parent, uid, _, res = m.groups()
            level[i] = ('[node name="%s" type="RigidBody3D" parent="%s" unique_id=%s]\n%s\nscript = ExtResource("%s")\nmodel = ExtResource("%s")'
                        % (name, parent, uid, body, knock, res))
            converted += 1
            continue
        m = re.match(r'\[node name="([^"]+)" type="MeshInstance3D" parent="([^"]+)" unique_id=(\d+)\]$', head)
        if m and m.group(1) in LOOSE_MESHES:
            name, parent, uid = m.groups()
            # (The script before its properties: Godot drops a script's
            # property that's set before the script itself.)
            lines = body.split("\n")
            first = [l for l in lines if l.startswith("transform = ")]
            rest = [l for l in lines if not l.startswith("transform = ")]
            level[i] = ('[node name="%s" type="RigidBody3D" parent="%s" unique_id=%s]\n%s'
                        % (name, parent, uid, "\n".join(first + ['script = ExtResource("%s")' % knock] + rest)))
            converted += 1

    last_ext = max(i for i, b in enumerate(level) if b.startswith("[ext_resource"))
    level[last_ext + 1:last_ext + 1] = new_ext
    first_node = next(i for i, b in enumerate(level) if b.startswith("[node "))
    level[first_node:first_node] = new_sub
    first_editable = next((i for i, b in enumerate(level) if b.startswith("[editable ")), len(level))
    level[first_editable:first_editable] = new_nodes

    out = "\n\n".join(level) + "\n"
    out = re.sub(r'(\[editable path="[^"]+"\])\n\n(?=\[editable )', r"\1\n", out)
    LEVEL.write_text(out.replace("\n", newline), encoding="utf-8", newline="")
    print("Merged %d ext resources, %d sub resources, %d nodes; %d of the level's props made loose."
          % (len(new_ext), len(new_sub), len(new_nodes), converted))


if __name__ == "__main__":
    main()
