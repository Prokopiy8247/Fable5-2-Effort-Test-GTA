"""Reads a Godot log and relaxes `var x := expr` to `var x = expr` on lines where the
GDScript analyzer could not infer a type (Variant-typed expressions). Prints other errors."""
import re, sys, pathlib
log = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").split("\n")
fixed = 0; other = []
i = 0
while i < len(log):
    line = log[i]
    m = re.search(r'Cannot infer the type of "(\w+)" variable', line)
    loc = None
    for j in range(i + 1, min(i + 4, len(log))):
        lm = re.search(r"\((res://[^:]+):(\d+)\)", log[j])
        if lm:
            loc = (lm.group(1), int(lm.group(2))); break
    if m and loc:
        path = pathlib.Path(loc[0].replace("res://", ""))
        src = path.read_text(encoding="utf-8").split("\n")
        ln = src[loc[1] - 1]
        new = re.sub(r"\b(var|const)\s+%s\s*:=" % re.escape(m.group(1)), r"\1 %s =" % m.group(1), ln, count=1)
        if new != ln:
            src[loc[1] - 1] = new
            path.write_text("\n".join(src), encoding="utf-8", newline="\n")
            fixed += 1
    elif ("SCRIPT ERROR" in line or line.startswith("ERROR")) and "Cannot infer" not in line:
        other.append(line.strip()[:200] + ("   @ %s:%d" % loc if loc else ""))
    i += 1
print("relaxed inferences:", fixed)
seen = set()
for o in other:
    if o not in seen:
        seen.add(o); print(o)
