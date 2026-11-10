# Converts inferred local declarations (`var x := expr`) to dynamic ones to avoid GDScript Variant-inference parse errors.
import re, sys, pathlib
n = 0
for p in pathlib.Path('gta/code').rglob('*.gd'):
    s = p.read_text(encoding='utf-8')
    s2 = re.sub(r'^(\t+var \w+) := ', r'\1 = ', s, flags=re.M)
    if s2 != s:
        n += s.count(':= ') - s2.count(':= ')
        p.write_bytes(s2.encode('utf-8'))
print('replaced', n)
