"""Count the Blender-authored assets (GLB exports and manifest entries) for the final report."""
import glob
import json
import os
from collections import Counter

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
man = {}
for f in sorted(glob.glob(os.path.join(ROOT, "gta/resources/data/manifests/*.json"))):
    d = json.load(open(f, encoding="utf-8"))
    a = d.get("assets", d.get("sounds", d))
    man[os.path.basename(f)] = len(a) if isinstance(a, (list, dict)) else 0
for k, v in man.items():
    print("%-24s %4d" % (k, v))
glbs = glob.glob(os.path.join(ROOT, "gta/generated/models/**/*.glb"), recursive=True)
cats = Counter(os.path.relpath(p, os.path.join(ROOT, "gta/generated/models")).replace(os.sep, "/").split("/")[0] for p in glbs)
print("GLB files:", len(glbs))
for k, v in sorted(cats.items()):
    print("  %-12s %4d" % (k, v))
wavs = glob.glob(os.path.join(ROOT, "gta/generated/audio/*.wav"))
print("WAV files:", len(wavs))
