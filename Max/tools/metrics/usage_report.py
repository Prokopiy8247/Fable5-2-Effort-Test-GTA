"""Token accounting for this project (spec section 58).

Reads ONLY usage metadata (message ids, models, usage counters, timestamps) from the Claude Code
session log of this project and the transcripts of the agents it delegated to. No message content
is read or written. Deduplicates by message id (the log repeats a message's usage once per content
block), keeps the mutually exclusive categories of the Anthropic Messages API:
    input_tokens (uncached) | cache_creation_input_tokens (5m / 1h split) | cache_read_input_tokens | output_tokens
and prices them with the rates passed on the command line (USD per million tokens).

usage:  python tools/metrics/usage_report.py <session_jsonl> <subagent_dir> [--json out.json]
"""
import glob
import json
import os
import sys

# Claude Fable 5.2 Standard API rates, USD per MTok, verified 2026-11-10 at
# https://platform.claude.com/docs/en/about-claude/pricing
RATES = {"input": 8.0, "cache_write_5m": 10.0, "cache_write_1h": 16.0, "cache_read": 0.20, "output": 40.0}


def scan(path):
    """Per message id: the last usage record seen (records of one message carry the same usage)."""
    per_id = {}
    first_ts, last_ts = None, None
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("type") != "assistant":
                continue
            m = d.get("message") or {}
            model = m.get("model")
            u = m.get("usage")
            mid = m.get("id") or d.get("requestId") or d.get("uuid")
            if not u or not model or model == "<synthetic>":
                continue
            ts = d.get("timestamp")
            if ts:
                first_ts = ts if first_ts is None or ts < first_ts else first_ts
                last_ts = ts if last_ts is None or ts > last_ts else last_ts
            cc = u.get("cache_creation") or {}
            rec = {
                "model": model,
                "input": int(u.get("input_tokens") or 0),
                "cache_read": int(u.get("cache_read_input_tokens") or 0),
                "cache_write": int(u.get("cache_creation_input_tokens") or 0),
                "cache_write_5m": int(cc.get("ephemeral_5m_input_tokens") or 0),
                "cache_write_1h": int(cc.get("ephemeral_1h_input_tokens") or 0),
                "output": int(u.get("output_tokens") or 0),
                "split_known": bool(cc),
            }
            old = per_id.get(mid)
            # keep the most complete record (streaming snapshots only ever grow)
            if old is None or rec["output"] >= old["output"]:
                per_id[mid] = rec
    return per_id, first_ts, last_ts


def total(records):
    t = {"messages": 0, "input": 0, "cache_read": 0, "cache_write": 0, "cache_write_5m": 0, "cache_write_1h": 0,
         "cache_write_unsplit": 0, "output": 0}
    for r in records:
        t["messages"] += 1
        for k in ("input", "cache_read", "cache_write", "cache_write_5m", "cache_write_1h", "output"):
            t[k] += r[k]
        if not r["split_known"]:
            t["cache_write_unsplit"] += r["cache_write"]
    return t


def cost(t):
    # writes without a 5m / 1h split are priced at the 1-hour rate (this host uses a 1-hour TTL)
    w1h = t["cache_write_1h"] + t["cache_write_unsplit"]
    return (t["input"] * RATES["input"] + t["cache_write_5m"] * RATES["cache_write_5m"] + w1h * RATES["cache_write_1h"]
            + t["cache_read"] * RATES["cache_read"] + t["output"] * RATES["output"]) / 1_000_000.0


def main():
    session, sub_dir = sys.argv[1], sys.argv[2]
    out_json = sys.argv[sys.argv.index("--json") + 1] if "--json" in sys.argv else None
    sources = [("lead session", session)] + [("agent " + os.path.basename(p)[6:-6], p)
                                             for p in sorted(glob.glob(os.path.join(sub_dir, "agent-*.jsonl")))]
    all_recs, rows = [], []
    for label, path in sources:
        per_id, a, b = scan(path)
        recs = list(per_id.values())
        all_recs += recs
        t = total(recs)
        models = sorted({r["model"] for r in recs})
        rows.append((label, models, t, a, b))
    grand = total(all_recs)
    grand_total_tokens = grand["input"] + grand["cache_read"] + grand["cache_write"] + grand["output"]
    print("%-28s %6s %12s %14s %12s %11s  %s" % ("source", "msgs", "input", "cache_read", "cache_write", "output", "models"))
    for label, models, t, a, b in rows:
        print("%-28s %6d %12d %14d %12d %11d  %s" % (label, t["messages"], t["input"], t["cache_read"], t["cache_write"], t["output"], ",".join(models)))
    print("-" * 100)
    print("TOTAL messages %d" % grand["messages"])
    for k in ("input", "cache_read", "cache_write", "cache_write_5m", "cache_write_1h", "cache_write_unsplit", "output"):
        print("  %-20s %15d" % (k, grand[k]))
    print("  %-20s %15d" % ("total tokens", grand_total_tokens))
    print("API-equivalent USD at Claude Fable 5.2 Standard rates: %.2f" % cost(grand))
    if out_json:
        with open(out_json, "w", encoding="utf-8") as f:
            json.dump({"rates_usd_per_mtok": RATES, "total": grand, "total_tokens": grand_total_tokens,
                       "usd_at_fable_rates": round(cost(grand), 2),
                       "sources": [{"label": l, "models": m, "usage": t, "first": a, "last": b} for l, m, t, a, b in rows]},
                      f, indent=1)


if __name__ == "__main__":
    main()
