"""Adds static types to `for x in [literal, ...]` loops (GDScript infers Variant otherwise,
which breaks `:=` inference further down). Run after writing new scripts."""
import re, sys, pathlib
root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "gta/code")
pat = re.compile(r"^(\s*)for (\w+) in \[(.*)\]:\s*$")
num = re.compile(r"^-?\d+(\.\d+)?$")
changed = 0
for p in root.rglob("*.gd"):
    lines = p.read_text(encoding="utf-8").split("\n")
    out = []
    dirty = False
    for line in lines:
        m = pat.match(line)
        if m:
            items = [s.strip() for s in m.group(3).split(",") if s.strip()]
            t = None
            if items and all(num.match(i) for i in items):
                t = "float" if any("." in i for i in items) else "int"
            elif items and all(i.startswith('"') and i.endswith('"') for i in items):
                t = "String"
            if t:
                line = "%sfor %s: %s in [%s]:" % (m.group(1), m.group(2), t, m.group(3))
                dirty = True
                changed += 1
        out.append(line)
    if dirty:
        p.write_text("\n".join(out), encoding="utf-8", newline="\n")
print("typed loops:", changed)
