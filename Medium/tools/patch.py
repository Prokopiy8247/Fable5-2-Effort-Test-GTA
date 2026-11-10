# tiny helper: python tools/patch.py <file> <<< "old\n===\nnew\n@@@\nold2\n===\nnew2"
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text(encoding='utf-8')
blocks = sys.stdin.read().split('\n@@@\n')
ok = True
for b in blocks:
    if '\n===\n' not in b: continue
    old, new = b.split('\n===\n', 1)
    old = old.strip('\n'); new = new.rstrip('\n')
    if new.startswith('\n'): new = new[1:]
    if old not in s:
        print('NOT FOUND:', old[:70].replace('\n', '\n')); ok = False; continue
    s = s.replace(old, new, 1)
p.write_bytes(s.encode('utf-8'))
print('patched' if ok else 'patched with misses', p)
