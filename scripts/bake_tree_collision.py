#!/usr/bin/env python3
"""
Bake CylinderShape3D collision bodies into trees.tscn.
Parses the TSCN text and appends StaticBody3D + CylinderShape3D nodes
for every pine_tree_* child node.
"""
import re
import os

# Paths
script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
tscn_path = os.path.join(script_dir, "scenes", "trees.tscn")

with open(tscn_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Find lines that define pine_tree nodes at root level
pine_nodes = []
for i, line in enumerate(lines):
    # Match: [node name="pine_tree_..." parent="." instance=...]
    m = re.match(
        r'^\[node name="(pine_tree_[^"]+)" parent="\." instance=', line)
    if m:
        name = m.group(1)
        # Read the next line(s) to get the transform
        transform_line = ""
        for j in range(i+1, min(i+3, len(lines))):
            if lines[j].startswith("transform = "):
                transform_line = lines[j].strip()
                break
        coll_name = name + "_collision"
        pine_nodes.append((name, coll_name, transform_line, i))

print(f"Found {len(pine_nodes)} pine tree instances")

# Build collision body blocks to inject
collision_blocks = {}
for name, coll_name, transform_line, idx in pine_nodes:
    # Check if this tree doesn't already have a collision body
    coll_exists = False
    for line in lines:
        if f'name="{coll_name}" type="StaticBody3D"' in line:
            coll_exists = True
            break
    if coll_exists:
        continue

    # Extract position from transform
    pos_match = re.search(
        r'Transform3D\([^,]+,[^,]+,[^,]+,[^,]+,[^,]+,[^,]+,[^,]+,[^,]+,[^,]+,\s*(-?[\d.e+-]+),\s*(-?[\d.e+-]+),\s*(-?[\d.e+-]+)\)', transform_line)
    if pos_match:
        tx, ty, tz = pos_match.group(1), pos_match.group(2), pos_match.group(3)
        transform_str = f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {tx}, {ty}, {tz})"
    else:
        # Use identity transform if no explicit transform found
        transform_str = transform_line if transform_line else "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)"

    block = f"""
[node name="{coll_name}" type="StaticBody3D" parent="."]
{transform_str}

[node name="CollisionShape3D" type="CollisionShape3D" parent="{coll_name}"]
shape = SubResource("CylinderShape3D_{name}")
position = Vector3(0, 4, 0)

"""
    collision_blocks[idx] = block

if not collision_blocks:
    print("All trees already have collision bodies!")
    exit(0)

# Inject blocks after each pine tree's transform line
new_lines = []
injected_at = set()
for i, line in enumerate(lines):
    new_lines.append(line)
    if i in collision_blocks and i not in injected_at:
        new_lines.append(collision_blocks[i])
        injected_at.add(i)

# Add CylinderShape3D sub-resources at the top (before first [node)
# Find position to insert sub-resources (after ext_resources, before [node)
sub_resource_idx = None
for i, line in enumerate(new_lines):
    if line.startswith("[node ") and sub_resource_idx is None:
        sub_resource_idx = i
        break

# Generate sub-resource entries
sub_resources = []
for name, coll_name, _, _ in pine_nodes:
    # Check if this tree doesn't already have collision
    coll_block_key = None
    for k, v in collision_blocks.items():
        if coll_name in v:
            coll_block_key = k
            break
    if coll_block_key is None:
        continue
    sub_resources.append(
        f"[sub_resource type=\"CylinderShape3D\" id=\"CylinderShape3D_{name}\"]\nradius = 0.5\nheight = 8.0\n\n")

if sub_resources:
    # Insert before first [node line
    for sr in reversed(sub_resources):
        new_lines.insert(sub_resource_idx, sr)

with open(tscn_path, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print(
    f"Injected {len(collision_blocks)} collision bodies and {len(sub_resources)} sub-resources")
print("Done!")
