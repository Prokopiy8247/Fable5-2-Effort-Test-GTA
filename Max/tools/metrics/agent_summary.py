"""Summarise subagent transcripts (usage metadata + last progress note). Reads only
metadata and short trailing text, never dumps conversations."""
import json, os, sys, glob, collections
base = os.path.join(os.path.expanduser("~"), ".claude", "projects", "G--YouTube-Fable-5-2-Effort-Test-GTA-Max", "7ffba212-fbb2-4c22-ae3c-4c496a3b0a08", "subagents")
names = {"aa629bdd96a5d11c5": "buildings", "a11075f8c8325c0e9": "props", "ad975344013bb7075": "landmarks",
         "a9161b6647745e947": "cars", "a2ba73a4f34c0b6f7": "veh_other", "acf6583679e1a8339": "characters",
         "adc769cd137dd3117": "weapons", "a176932ae27ae18df": "audio"}
tot = collections.Counter()
for aid, nm in names.items():
    p = os.path.join(base, "agent-" + aid + ".jsonl")
    if not os.path.exists(p):
        print(nm, "NO FILE"); continue
    seen = {}
    last_text = ""
    first_ts = last_ts = None
    tools = collections.Counter()
    model = set()
    with open(p, encoding="utf-8", errors="replace") as f:
        for line in f:
            try: d = json.loads(line)
            except Exception: continue
            ts = d.get("timestamp")
            if ts:
                first_ts = first_ts or ts; last_ts = ts
            m = d.get("message") or {}
            if not isinstance(m, dict): continue
            if d.get("type") == "assistant":
                u = m.get("usage") or {}
                mid = m.get("id")
                if mid and u:
                    seen[mid] = u          # last snapshot per message id
                if m.get("model"): model.add(m["model"])
                for c in m.get("content") or []:
                    if isinstance(c, dict):
                        if c.get("type") == "text" and c.get("text", "").strip():
                            last_text = c["text"].strip()
                        if c.get("type") == "tool_use":
                            tools[c.get("name", "?").split("__")[-1]] += 1
    inp = sum(u.get("input_tokens", 0) or 0 for u in seen.values())
    cr = sum(u.get("cache_read_input_tokens", 0) or 0 for u in seen.values())
    cw = sum(u.get("cache_creation_input_tokens", 0) or 0 for u in seen.values())
    out = sum(u.get("output_tokens", 0) or 0 for u in seen.values())
    lastu = list(seen.values())[-1] if seen else {}
    ctx = (lastu.get("input_tokens", 0) or 0) + (lastu.get("cache_read_input_tokens", 0) or 0) + (lastu.get("cache_creation_input_tokens", 0) or 0)
    tot.update({"in": inp, "cr": cr, "cw": cw, "out": out})
    print("%-10s req=%3d ctx_now=%7d in=%6d cache_read=%9d cache_write=%8d out=%7d models=%s %s..%s" % (
        nm, len(seen), ctx, inp, cr, cw, out, sorted(model), (first_ts or "")[11:19], (last_ts or "")[11:19]))
    print("           tools:", dict(tools))
    print("           last note:", last_text[:260].replace("\n", " "))
print("TOTAL agents:", dict(tot))
