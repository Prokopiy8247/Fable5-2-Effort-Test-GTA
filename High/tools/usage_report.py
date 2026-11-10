"""Token accounting for this Claude session only. Reads usage metadata (no message text) from the session log.
Usage: python tools/usage_report.py <session.jsonl> [start_iso] """
import json, sys, collections
path = sys.argv[1]
by_id = {}
order = []
first_ts = last_ts = None
for line in open(path, encoding="utf-8", errors="ignore"):
    try:
        d = json.loads(line)
    except Exception:
        continue
    msg = d.get("message")
    if not isinstance(msg, dict) or d.get("type") != "assistant":
        continue
    u = msg.get("usage")
    if not isinstance(u, dict):
        continue
    mid = msg.get("id") or d.get("requestId") or d.get("uuid")
    ts = d.get("timestamp")
    if ts:
        first_ts = first_ts or ts
        last_ts = ts
    rec = {"model": msg.get("model", "?"), "in": u.get("input_tokens", 0) or 0, "out": u.get("output_tokens", 0) or 0,
           "cr": u.get("cache_read_input_tokens", 0) or 0, "cw": u.get("cache_creation_input_tokens", 0) or 0,
           "cw5": (u.get("cache_creation") or {}).get("ephemeral_5m_input_tokens", 0) or 0,
           "cw1h": (u.get("cache_creation") or {}).get("ephemeral_1h_input_tokens", 0) or 0,
           "side": bool(d.get("isSidechain")), "tier": u.get("service_tier")}
    if mid not in by_id:
        order.append(mid)
        by_id[mid] = rec
    else:  # streaming snapshots of one request: keep the largest counters
        old = by_id[mid]
        for k in ("in", "out", "cr", "cw", "cw5", "cw1h"):
            old[k] = max(old[k], rec[k])
tot = collections.defaultdict(lambda: collections.Counter())
for mid in order:
    r = by_id[mid]
    c = tot[r["model"]]
    for k in ("in", "out", "cr", "cw", "cw5", "cw1h"):
        c[k] += r[k]
    c["requests"] += 1
    c["sidechain_requests"] += int(r["side"])
print(json.dumps({"requests_total": len(order), "first": first_ts, "last": last_ts,
                  "tiers": sorted(set(str(by_id[m]["tier"]) for m in order)),
                  "models": {m: dict(c) for m, c in tot.items()}}, indent=1))
