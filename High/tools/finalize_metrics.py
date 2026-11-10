"""Fills the Session Metrics block of the final report from measured timestamps and the session usage log."""
import json, os, subprocess, sys
from datetime import datetime, timezone, timedelta
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUN = os.path.join(ROOT, ".fable-5.2-gta-runs", "run-20261109-215733")
LOG = os.path.expanduser("~/.claude/projects/G--YouTube-Fable-5-2-Effort-Test-GTA-High/a453750e-3bbc-4b05-85c1-f01dcace680a.jsonl")
SUB = os.path.expanduser("~/.claude/projects/G--YouTube-Fable-5-2-Effort-Test-GTA-High/a453750e-3bbc-4b05-85c1-f01dcace680a/subagents/agent-a198171dee26b6622.jsonl")
tz = timezone(timedelta(hours=1))
now = datetime.now(tz)
end_s = now.isoformat(timespec="milliseconds")
open(os.path.join(RUN, "end_time.txt"), "w", encoding="utf-8").write(end_s + " (Central European Standard Time)\n")
start_s = open(os.path.join(RUN, "start_time.txt"), encoding="utf-8-sig").read().split(" ")[0]
sec = int((now - datetime.fromisoformat(start_s)).total_seconds())
hms = "%02d:%02d:%02d" % (sec // 3600, sec % 3600 // 60, sec % 60)
PAUSE = 1056
act = sec - PAUSE
u = json.loads(subprocess.check_output([sys.executable, os.path.join(ROOT, "tools", "usage_report.py"), LOG]))
m = u["models"]["claude-fable-5-2"]
s = json.loads(subprocess.check_output([sys.executable, os.path.join(ROOT, "tools", "usage_report.py"), SUB]))["models"].get("claude-haiku-5-5", {})
R = {"in": 8.0, "cw1h": 16.0, "cw5": 10.0, "cr": 0.20, "out": 40.0}
cost = (m["in"] * R["in"] + m["cw1h"] * R["cw1h"] + m["cw5"] * R["cw5"] + m["cr"] * R["cr"] + m["out"] * R["out"]) / 1e6
total = m["in"] + m["cw"] + m["cr"] + m["out"]
block = f"""## Claude Fable 5.2 GTA Session Metrics

Project: Godot GTA sandbox
Run/session identifier: run-20261109-215733 (Claude session a453750e-3bbc-4b05-85c1-f01dcace680a)
Working-directory full path: G:\YouTube\Fable 5.2 Effort Test GTA\High
Start timestamp and timezone: {start_s} (Central European Standard Time)
End timestamp and timezone: {end_s} (Central European Standard Time)
Elapsed wall-clock time (HH:MM:SS): {hms} (measured from the two OS timestamps)
Elapsed minutes: {sec / 60:.1f}
Elapsed hours: {sec / 3600:.2f}
Known pauses / resumed segments: one idle gap of {PAUSE} s (17 min 36 s) from 23:27:53 to 23:45:29 local time, when the turn had stopped and the session waited for the user's "Try again"; identified from consecutive timestamps in the session log. Wall-clock minus that gap = {act // 3600:02d}:{act % 3600 // 60:02d}:{act % 60:02d} (derived, not separately tracked active time). Single segment otherwise.

Requested model: Claude Fable 5.2
Actual model identifier(s): claude-fable-5-2 (all {m['requests']} main-session requests); one delegated web-fetch subagent ran on claude-haiku-5-5 (2 requests)
Thinking/effort setting (if exposed): effort "high" as selected for this session; no separate thinking-token counter exposed
Input tokens (state whether uncached or inclusive): {m['in']:,} (uncached only; excludes cache reads and cache writes)
Cache-read tokens: {m['cr']:,}
Cache-write tokens: {m['cw']:,}
Cache-write duration breakdown (if exposed): 1-hour: {m['cw1h']:,}; 5-minute: {m['cw5']:,}
Output tokens: {m['out']:,}
Thinking/reasoning tokens (included / separate / unavailable): not reported separately; treated as included in output tokens (not independently confirmed)
Deduplicated total tokens: {total:,} (input + cache-read + cache-write + output, one record per message id)
Usage source and observation cutoff: local session log for this exact session (`usage` metadata per assistant message, deduplicated by message id, largest snapshot kept); cutoff = last logged request at {u['last']} UTC
Unmeasured work / limitations: the request that produced the final chat message (and this metrics step's own response) is after the cutoff. Delegated subagent (claude-haiku-5-5): input {s.get('in', 0):,}, cache-read {s.get('cr', 0):,}, cache-write {s.get('cw', 0):,} (5-minute), output {s.get('out', 0):,} — counted separately, not in the totals above.

Token-only API-equivalent cost (USD): ${cost:,.2f} (Fable 5.2 main session, measured usage x verified standard rates)
Per-model subtotals (if applicable): claude-fable-5-2 ${cost:,.2f}; claude-haiku-5-5 subagent not priced (its rates were not verified; ~39k tokens, negligible)
Official pricing source, verification date and comparison tier: https://platform.claude.com/docs/en/about-claude/pricing, fetched 2026-11-10, Standard Claude API tier (log reports service_tier "standard")
Rates and formula used: input $8.00, 1-hour cache write $16.00, 5-minute cache write $10.00, cache read $0.20, output $40.00 per million tokens; cost = sum(tokens x rate) / 1,000,000 = ({m['in']:,} x 8 + {m['cw1h']:,} x 16 + {m['cr']:,} x 0.20 + {m['out']:,} x 40) / 1e6
Cache/context/tier adjustments or explicit assumptions: no long-context premium applies to Fable 5.2 per the pricing page; cache-read rate is the page's Fable-specific $0.20; the three input categories are treated as mutually exclusive per the prompt-caching documentation
External tool/API fees (known / excluded / unknown): none known; Blender and Godot are local; web fetch fees unknown and excluded
Measured / estimated / unavailable, with reasons: time measured; tokens measured from the session log up to the cutoff; cost calculated from measured tokens and fetched official rates (a benchmark equivalent, not a bill)

Blender MCP server/tool namespace actually used: blender-gta-high (mcp__blender-gta-high__*)
Blender host: localhost
Blender port: 9879
Blender master file: GodotFable5.2GTAHigh.blend
Verified full path of master file: G:\YouTube\Fable 5.2 Effort Test GTA\High\GodotFable5.2GTAHigh.blend
Approximate number of major Blender assets created: 173 asset roots (166 exported GLBs + 7 kit modules), 661 objects
"""
p = os.path.join(ROOT, "FABLE_5.2_FINAL_REPORT.md")
t = open(p, encoding="utf-8").read()
if "{{METRICS}}" in t:
    t = t.replace("{{METRICS}}", block)
else:
    t = t[:t.index("## Claude Fable 5.2 GTA Session Metrics")] + block
open(p, "w", encoding="utf-8").write(t)
print(hms, f"{sec/60:.1f} min", "tokens", f"{total:,}", "cost", f"${cost:,.2f}", "in", m["in"], "cr", m["cr"], "cw", m["cw"], "out", m["out"])
