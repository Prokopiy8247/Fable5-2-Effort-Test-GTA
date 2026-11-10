# Writes end_time.txt and appends the session-metrics section to FABLE_5.2_FINAL_REPORT.md.
# Token counts come from this session's local Claude Code log, deduplicated by message id.
import json, glob, os, datetime, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUN = os.path.join(ROOT, '.fable-5.2-gta-runs', 'run-20261109-214834')
LOGS = os.path.expanduser('~/.claude/projects/G--YouTube-Fable-5-2-Effort-Test-GTA-Low/*.jsonl')
RATES = {'in': 8.0, 'w5': 10.0, 'w1': 16.0, 'read': 0.20, 'out': 40.0}  # USD per MTok, Claude Fable 5.2

tz = datetime.timezone(datetime.timedelta(hours=1))
now = datetime.datetime.now(tz)
open(os.path.join(RUN, 'end_time.txt'), 'w').write(now.isoformat(timespec='milliseconds') + ' Central European Standard Time\n')
start1 = datetime.datetime.fromisoformat('2026-11-09T21:48:34.352+01:00')
seg2 = datetime.datetime.fromisoformat(open(os.path.join(RUN, 'segment2_start.txt')).read().split()[0])
seg1_end = datetime.datetime.fromisoformat('2026-11-09T21:50:06+01:00')
active = (seg1_end - start1) + (now - seg2)
wall = now - start1


def hms(td):
    s = int(td.total_seconds())
    return '%02d:%02d:%02d' % (s // 3600, s % 3600 // 60, s % 60)


seen = {}
models = {}
sid = ''
for f in glob.glob(LOGS):
    sid = os.path.basename(f)[:-6]
    for line in open(f, encoding='utf-8', errors='ignore'):
        try:
            d = json.loads(line)
        except Exception:
            continue
        m = d.get('message') or {}
        if m.get('usage') and m.get('id') and m.get('model') != '<synthetic>':
            seen[m['id']] = m
t = {'in': 0, 'read': 0, 'w5': 0, 'w1': 0, 'out': 0}
for m in seen.values():
    u = m['usage']
    cc = u.get('cache_creation') or {}
    t['in'] += u.get('input_tokens', 0) or 0
    t['read'] += u.get('cache_read_input_tokens', 0) or 0
    t['w5'] += cc.get('ephemeral_5m_input_tokens', 0) or 0
    t['w1'] += cc.get('ephemeral_1h_input_tokens', 0) or 0
    t['out'] += u.get('output_tokens', 0) or 0
    models[m.get('model')] = models.get(m.get('model'), 0) + 1
cost = sum(t[k] * RATES[k] for k in t) / 1e6
total = sum(t.values())
sec = f'''
## Claude Fable 5.2 GTA Session Metrics

Project: Godot GTA sandbox
Run/session identifier: run-20261109-214834 / Claude Code session {sid}
Working-directory full path: G:\\YouTube\\Fable 5.2 Effort Test GTA\\Low
Start timestamp and timezone: 2026-11-09T21:48:34+01:00 (Central European Standard Time)
End timestamp and timezone: {now.isoformat(timespec='seconds')} (Central European Standard Time)
Elapsed wall-clock time (HH:MM:SS): {hms(wall)} (measured, includes the pauses below)
Elapsed minutes: {wall.total_seconds() / 60:.1f}
Elapsed hours: {wall.total_seconds() / 3600:.2f}
Known pauses / resumed segments: segment 1 ran 21:48:34-21:50:06 and stopped on the missing Blender MCP; segment 2 started {seg2.isoformat(timespec='seconds')}. Sum of the two segments: {hms(active)} ({active.total_seconds() / 60:.1f} min). Segment 2 also contains one interruption of unknown length before the user's "Try again" message.

Requested model: Claude Fable 5.2
Actual model identifier(s): {', '.join('%s (%d responses)' % kv for kv in models.items())}
Thinking/effort setting (if exposed): not exposed in the log (this benchmark folder is the "Low" effort variant)
Input tokens (state whether uncached or inclusive): {t['in']:,} (uncached only)
Cache-read tokens: {t['read']:,}
Cache-write tokens: {t['w5'] + t['w1']:,}
Cache-write duration breakdown (if exposed): 5-minute {t['w5']:,}; 1-hour {t['w1']:,}
Output tokens: {t['out']:,}
Thinking/reasoning tokens (included / separate / unavailable): included in output tokens; not reported separately
Deduplicated total tokens: {total:,}
Usage source and observation cutoff: local Claude Code session log (~/.claude/projects/G--YouTube-Fable-5-2-Effort-Test-GTA-Low/{sid}.jsonl), per-response usage deduplicated by message id, read at {now.isoformat(timespec='seconds')}
Unmeasured work / limitations: (1) the response that wrote this section and the final chat message are not in the count; (2) segment 1 ran in an earlier session whose log was not found, so its tokens are not counted; (3) this session's log also contains one short turn before the task prompt (a Blender connection check), which is counted; (4) one delegated web-fetch subagent (about 19k tokens, model not recorded) is not counted.

Token-only API-equivalent cost (USD): ${cost:.2f} (measured tokens x list rates; a lower bound given the limitations above)
Per-model subtotals (if applicable): single model
Official pricing source, verification date and comparison tier: https://platform.claude.com/docs/en/about-claude/pricing, read on 2026-11-09 through a web-fetch subagent (I did not read the page myself), Standard API tier
Rates and formula used: input $8, 5-minute cache write $10, 1-hour cache write $16, cache read $0.20, output $40 per million tokens; cost = sum(category tokens x rate) / 1,000,000
Cache/context/tier adjustments or explicit assumptions: no long-context, batch or fast-mode adjustment applied
External tool/API fees (known / excluded / unknown): none known; local Blender and Godot carry no fee; no asset libraries or 3D generators were used
Measured / estimated / unavailable, with reasons: time measured from OS timestamps; tokens measured from the session log with the listed gaps; cost computed from those tokens, so it is a measured lower bound, not a bill

Blender MCP server/tool namespace actually used: blender-gta-low (mcp__blender-gta-low__*)
Blender host: localhost
Blender port: 9877
Blender master file: GodotFable5.2GTALow.blend
Verified full path of master file: G:\\YouTube\\Fable 5.2 Effort Test GTA\\Low\\GodotFable5.2GTALow.blend
Approximate number of major Blender assets created: 140
'''
p = os.path.join(ROOT, 'FABLE_5.2_FINAL_REPORT.md')
s = open(p, encoding='utf-8').read()
i = s.find('\n## Claude Fable 5.2 GTA Session Metrics')
if i >= 0:
    s = s[:i]
open(p, 'w', encoding='utf-8', newline='\n').write(s.rstrip('\n') + '\n' + sec)
print(hms(wall), hms(active), total, '%.2f' % cost, t)
