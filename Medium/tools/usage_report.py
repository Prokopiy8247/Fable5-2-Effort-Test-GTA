# Reads ONLY usage metadata (model id, token counters, timestamps) from this session's Claude Code log.
import json, sys, glob, os
base = os.path.expanduser(r'~/.claude/projects/G--YouTube-Fable-5-2-Effort-Test-GTA-Medium')
sid = '50b5d4e7-5c62-4517-bb45-65ed404d78c4'
files = [os.path.join(base, sid + '.jsonl')] + glob.glob(os.path.join(base, sid, '**', '*.jsonl'), recursive=True)
seen = {}
for f in files:
    for line in open(f, encoding='utf-8', errors='ignore'):
        try: d = json.loads(line)
        except Exception: continue
        m = d.get('message') or {}
        u = m.get('usage')
        if not u or m.get('role') != 'assistant': continue
        key = (m.get('id'), d.get('requestId'))
        seen[key] = (m.get('model'), u, d.get('timestamp'), os.path.basename(f))   # last streamed record per request wins
tot = {}
for model, u, ts, f in seen.values():
    t = tot.setdefault(model, dict(input=0, cache_read=0, cache_write=0, cw_5m=0, cw_1h=0, output=0, n=0, first=ts, last=ts))
    t['input'] += u.get('input_tokens', 0); t['cache_read'] += u.get('cache_read_input_tokens', 0)
    t['cache_write'] += u.get('cache_creation_input_tokens', 0); t['output'] += u.get('output_tokens', 0)
    cc = u.get('cache_creation') or {}
    t['cw_5m'] += cc.get('ephemeral_5m_input_tokens', 0); t['cw_1h'] += cc.get('ephemeral_1h_input_tokens', 0)
    t['n'] += 1; t['first'] = min(t['first'], ts); t['last'] = max(t['last'], ts)
print(json.dumps({'files': len(files), 'models': tot}, indent=1))
