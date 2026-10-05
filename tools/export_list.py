"""Writes the export exclusions into export_presets.cfg, so builds leave out
the asset folders the game doesn't use (the project holds whole asset packs;
most of it isn't in the game).

Everything is exported except asset folders that nothing refers to. What the
game uses is found by following references, starting from its scenes,
resources, scripts and shaders: every res:// path in them, and in the files
those point to (scenes, materials, model import settings), and the assets the
scripts load by name at runtime (ForestDresser's "fern_1", the sound kit's
"SFX/...ogg" joined onto a folder constant). A folder holding anything used is
kept, except the files in it that nothing uses (models name their textures
inside them, and those are found too); folder trees with nothing used in
them are left out.

Run after adding assets (or before exporting):
    python tools/export_list.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRESETS = ROOT / "export_presets.cfg"
GAME_DIRS = ["scenes", "resources", "scripts", "shaders", "navigation", "addons"]
TEXT_EXT = {".tscn", ".tres", ".gd", ".gdshader", ".import", ".cfg", ".gdextension", ".godot"}
ASSET_EXT = {".ogg", ".wav", ".mp3", ".glb", ".gltf", ".fbx", ".tscn", ".tres", ".png", ".jpg", ".res", ".obj", ".dae"}
ALWAYS_EXCLUDED = ["tests/*", "tools/*", "planning/*", "build/*", "addons/godot_mcp/cache/*"]


def rel(p: Path) -> str:
    return p.relative_to(ROOT).as_posix()


def main():
    assets = ROOT / "assets"
    all_assets = {rel(p): p for p in assets.rglob("*") if p.is_file() and p.suffix in ASSET_EXT}
    uid_to_path = {}  # uid -> [paths] (copied files share IDs)
    for uid_file in ROOT.rglob("*.uid"):
        if ".godot" in uid_file.parts:
            continue
        uid = uid_file.read_text(encoding="utf-8", errors="ignore").strip()
        uid_to_path.setdefault(uid, []).append(rel(uid_file)[: -len(".uid")])
    # Scenes and resources carry their own ID in their first line.
    for res_file in list(ROOT.rglob("*.tres")) + list(ROOT.rglob("*.tscn")):
        if ".godot" in res_file.parts:
            continue
        with open(res_file, encoding="utf-8", errors="ignore") as f:
            m = re.search(r'uid="(uid://[^"]+)"', f.readline())
        if m:
            uid_to_path.setdefault(m.group(1), []).append(rel(res_file))
    for imp in assets.rglob("*.import"):
        m = re.search(r'^uid="(uid://[^"]+)"', imp.read_text(encoding="utf-8", errors="ignore"), re.M)
        if m:
            uid_to_path.setdefault(m.group(1), []).append(rel(imp)[: -len(".import")])

    # Start from the game's own files and the project settings.
    todo = [ROOT / "project.godot"]
    for d in GAME_DIRS:
        todo += [p for p in (ROOT / d).rglob("*") if p.is_file() and p.suffix in TEXT_EXT]
    # Folders the scripts join names onto, and the strings they join.
    strings = set()
    for script in (ROOT / "scripts").rglob("*.gd"):
        strings.update(re.findall(r'"([^"\n]{2,200})"', script.read_text(encoding="utf-8", errors="ignore")))
    bases = sorted({s[len("res://"):] for s in strings if s.startswith("res://assets/") and s.endswith("/")})
    used = set()
    for s in strings:
        s = s[len("res://"):] if s.startswith("res://") else s
        if Path(s).suffix in ASSET_EXT:
            for base in [""] + bases:
                if base + s in all_assets:
                    used.add(base + s)
        elif re.fullmatch(r"[A-Za-z0-9_ ]+", s):
            # A bare model name, and its numbered variants (ForestDresser
            # turns "pine_tree_n_2" into "pine_tree_n_2_3").
            for base in bases:
                for ext in (".glb", ".tscn", ".fbx"):
                    if base + s + ext in all_assets:
                        used.add(base + s + ext)
                        for a_rel in all_assets:
                            if a_rel.startswith(base + s + "_") and a_rel.endswith(ext)                                     and re.fullmatch(r"[0-9_]+", a_rel[len(base + s + "_"):-len(ext)]):
                                used.add(a_rel)
    # Names built from pieces at runtime:
    #   - counter formats ("stair_step_%02d.wav", "Monster Growl (%d).mp3"),
    #     on their own or after a folder constant;
    #   - a folder constant + a sub-folder piece ("Ambient Wind/") + a name
    #     prefix ("Ambient Wind") + a counter, joined in code: every file in
    #     those folders starting with a prefix named in the code.
    dirs = set(bases) | {b + s for b in bases for s in strings if s.endswith("/") and not s.startswith("res://")}
    for s in strings:
        q = s[len("res://"):] if s.startswith("res://") else s
        if re.search(r"%0?\d*[ds]", q) and Path(q.replace("%", "")).suffix.lower() in ASSET_EXT:
            regex = re.escape(q)
            regex = re.sub(r"%0(\d+)d", lambda m: r"\d{%s}" % m.group(1), regex.replace("\\%", "%"))
            regex = regex.replace("%d", r"\d+").replace("%s", ".*")
            for base in [""] + sorted(dirs):
                pattern = re.compile(re.escape(base) + regex + "$")
                for a_rel in all_assets:
                    if pattern.match(a_rel):
                        used.add(a_rel)
    prefixes = {s for s in strings if len(s) >= 4 and "/" not in s and not s.startswith(("res://", "uid://"))}
    for d in dirs:
        folder = ROOT / d
        if not folder.is_dir():
            continue
        for f in folder.iterdir():
            if f.is_file() and f.suffix.lower() in ASSET_EXT and any(f.name.startswith(p) for p in prefixes):
                used.add(rel(f))
    todo += [all_assets[u] for u in used]

    # Follow references.
    seen = set()
    while todo:
        p = todo.pop()
        key = rel(p)
        if key in seen or not p.exists():
            continue
        seen.add(key)
        if key.startswith("assets/"):
            used.add(key)
        # Models name their textures inside the binary file: found by name
        # within the same asset pack.
        if p.suffix in (".glb", ".gltf", ".fbx", ".dae", ".obj") and key.startswith("assets/"):
            pack = "/".join(key.split("/")[:2]) + "/"
            names = {n.decode("latin-1").lower() for n in re.findall(rb'([A-Za-z0-9_\- .()]{2,80}\.(?:png|jpg|jpeg|tga|PNG|JPG))', p.read_bytes())}
            for name in names:
                base = Path(name).name
                for a_rel, a_path in all_assets.items():
                    if a_rel.startswith(pack) and a_path.name.lower() == base:
                        todo.append(a_path)
        # Godot pulls a model's textures out next to it, named
        # "<model>_<material>.png", and (with materials/extract) its materials
        # as .tres files beside it; the import refers to them only from
        # inside the compressed imported file.
        if p.suffix in (".glb", ".gltf", ".fbx", ".dae", ".obj") and key.startswith("assets/"):
            imp_text = p.with_name(p.name + ".import")
            extracts = imp_text.exists() and "materials/extract=1" in imp_text.read_text(encoding="utf-8", errors="ignore")
            for sibling in p.parent.iterdir():
                if not sibling.is_file():
                    continue
                if sibling.name.startswith(p.stem + "_") and sibling.suffix.lower() in (".png", ".jpg", ".jpeg"):
                    todo.append(sibling)
                elif extracts and sibling.suffix == ".tres":
                    todo.append(sibling)
        # Binary resources (meshes saved as .res) name their textures inside;
        # a compressed one can't be read, so its folder's images are kept.
        if p.suffix in (".res", ".scn", ".mesh") and key.startswith("assets/"):
            data = p.read_bytes()
            if data[:4] == b"RSCC":
                for sibling in p.parent.iterdir():
                    if sibling.is_file() and sibling.suffix.lower() in (".png", ".jpg", ".jpeg"):
                        todo.append(sibling)
            else:
                for ref in re.findall(rb"res://([^\x00\"\n]{3,200}?\.[A-Za-z0-9]{2,6})", data):
                    target = ROOT / ref.decode("utf-8", "ignore")
                    if target.exists():
                        todo.append(target)
                for uid in re.findall(rb"uid://[a-z0-9]+", data):
                    u = uid.decode()
                    for path in uid_to_path.get(u, []):
                        todo.append(ROOT / path)
        # What Godot imported it as (binary scenes and meshes) names the
        # textures it pulled out of the model.
        imp_file = p.with_name(p.name + ".import")
        if imp_file.exists():
            for dest in re.findall(r'"res://(\.godot/imported/[^"]+)"', imp_file.read_text(encoding="utf-8", errors="ignore")):
                dest_path = ROOT / dest
                if dest_path.exists() and dest_path.suffix in (".scn", ".res", ".mesh"):
                    for ref in re.findall(rb'res://([^\x00"\n]{3,200}?\.(?:png|jpg|jpeg|tga|tres|res|glb|fbx))', dest_path.read_bytes()):
                        target = ROOT / ref.decode("utf-8", "ignore")
                        if target.exists():
                            todo.append(target)
        texts = [p] if p.suffix in TEXT_EXT else []
        imp = p.with_name(p.name + ".import")
        if imp.exists():
            texts.append(imp)
        for t in texts:
            content = t.read_text(encoding="utf-8", errors="ignore")
            refs = set(re.findall(r'res://([^"\n]+?)(?="|::|$)', content, re.M))
            for u in re.findall(r'(uid://[a-z0-9]+)', content):
                refs |= set(uid_to_path.get(u, []))
            for r in refs:
                r = r.split("::")[0]
                target = ROOT / r
                if r.startswith(".godot/") or not target.exists() or target.is_dir():
                    continue
                todo.append(target)

    used_dirs = {str(Path(u).parent.as_posix()) for u in used}
    # Asset folders with nothing used in their tree: left out (the highest).
    excluded = []
    for d in sorted({rel(p.parent) for p in all_assets.values()}, key=len):
        if any(u == d or u.startswith(d + "/") for u in used_dirs):
            continue
        if any(d.startswith(e + "/") for e in excluded):
            continue
        excluded.append(d)
    # In the folders that are kept, whatever nothing uses goes too.
    unused_files = []
    for a_rel, a_path in all_assets.items():
        if a_rel in used or any(a_rel.startswith(e + "/") for e in excluded):
            continue
        unused_files.append(a_rel)
    patterns = ALWAYS_EXCLUDED + [e + "/*" for e in excluded] + unused_files

    text = PRESETS.read_text(encoding="utf-8")
    text = re.sub(r'export_filter="[^"]*"', 'export_filter="all_resources"', text)
    text = re.sub(r'\nexport_files=PackedStringArray\([^\n]*\)', "", text)
    text = re.sub(r'exclude_filter="[^"]*"', 'exclude_filter="%s"' % ", ".join(patterns).replace('"', '\\"'), text)
    PRESETS.write_text(text, encoding="utf-8", newline="\n")
    kept = sum(1 for a in all_assets if not any(a.startswith(e + "/") for e in excluded))
    print("%d asset files used; %d asset folders and %d unused files left out; %d of %d asset files kept."
          % (len(used), len(excluded), len(unused_files), kept - len(unused_files), len(all_assets)))


if __name__ == "__main__":
    main()
