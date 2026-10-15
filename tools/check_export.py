"""Checks the export keeps everything the game refers to by path.

The export leaves out what tools/export_list.py finds unused. This checks
that independently: every res:// path written in the game's scenes,
resources, scripts and shaders must exist, and must not be left out by the
presets' exclude_filter (a file the game loads by name would otherwise only
fail in the build, when it's needed). Paths built at runtime from a folder
constant (ECHOES + "SFX/...") are checked by their folder: it must not be
left out as a whole.

    python tools/check_export.py      (exit 1 and a list if something is wrong)
"""
import fnmatch
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAME_DIRS = ["scenes", "resources", "scripts", "shaders", "navigation"]
TEXT_EXT = {".tscn", ".tres", ".gd", ".gdshader"}
PATH_RE = re.compile(r'res://[^"\'\s)\]]+')


def exclude_patterns() -> list[str]:
    text = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    patterns = set()
    for match in re.finditer(r'^exclude_filter="([^"]*)"', text, re.M):
        patterns.update(p.strip() for p in match.group(1).split(",") if p.strip())
    return sorted(patterns)


def excluded(path: str, patterns: list[str]) -> str:
    for pattern in patterns:
        if fnmatch.fnmatchcase(path, pattern):
            return pattern
    return ""


def main() -> int:
    patterns = exclude_patterns()
    files = [ROOT / "project.godot"]
    for folder in GAME_DIRS:
        files += [p for p in (ROOT / folder).rglob("*") if p.suffix in TEXT_EXT]
    problems = []
    checked = 0
    for source in files:
        text = source.read_text(encoding="utf-8", errors="ignore")
        for raw in PATH_RE.findall(text):
            path = raw.removeprefix("res://").rstrip(".,;")
            where = source.relative_to(ROOT).as_posix()
            if "%" in path or "{" in path:
                continue   # a pattern filled in at runtime ("... (%d).mp3"): its folder is checked below
            if path.endswith("/") or "." not in Path(path).name:
                # A folder constant: something inside is loaded by name.
                folder = path.rstrip("/")
                if (ROOT / folder).is_dir():
                    probe = folder + "/x.ogg"
                    rule = excluded(probe, patterns)
                    if rule:
                        problems.append(f"{where}: folder res://{folder}/ is left out ({rule})")
                continue
            checked += 1
            if not (ROOT / path).exists():
                problems.append(f"{where}: res://{path} does not exist")
                continue
            rule = excluded(path, patterns)
            if rule:
                problems.append(f"{where}: res://{path} is left out of the export ({rule})")
    for problem in sorted(set(problems)):
        print("[EXPORT CHECK] PROBLEM  " + problem)
    print(f"[EXPORT CHECK] {checked} paths in {len(files)} files, {len(patterns)} exclusions: "
          + ("ALL KEPT" if not problems else f"{len(set(problems))} PROBLEMS"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
