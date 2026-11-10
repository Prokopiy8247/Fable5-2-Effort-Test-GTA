"""Token accounting for the Claude Fable 5.2 Godot GTA benchmark session (spec section 58).

Reads ONLY usage metadata (model id, token counters, ids, timestamps) from the local transcript
logs of THIS session: the main session JSONL plus every sub-agent / workflow-agent JSONL that
belongs to it. No message text, prompts or credentials are read into the output.

Normalisation (Anthropic Messages API semantics, see the prompt-caching documentation):
  input_tokens                  = uncached input tokens (exclusive of cache read/creation)
  cache_read_input_tokens       = tokens read from cache
  cache_creation_input_tokens   = tokens written to cache (ephemeral_5m + ephemeral_1h sum to it)
  output_tokens                 = output incl. thinking tokens (not reported separately)
The four categories are mutually exclusive, so total = their sum.

Streaming transcripts repeat the same API response on several lines (one per content block)
with identical message.id / requestId and cumulative usage, so records are de-duplicated by
(message.id, requestId) keeping the entry with the largest output_tokens.

Usage:
  python tools/usage/collect_usage.py [--since ISO8601] [--json out.json] [--probe]
"""
import argparse
import glob
import json
import os
import sys
from collections import defaultdict

PROJECT_LOG_DIR = os.path.join(os.path.expanduser("~"), ".claude", "projects", "G--YouTube-Fable-5-2-Effort-Test-GTA-Ultracode")
SESSION_ID = "f0ccccf9-8795-4dac-a29e-5a331b39db1d"


def session_files():
    files = []
    main = os.path.join(PROJECT_LOG_DIR, SESSION_ID + ".jsonl")
    if os.path.exists(main):
        files.append(("main", main))
    sub_root = os.path.join(PROJECT_LOG_DIR, SESSION_ID)
    for p in glob.glob(os.path.join(sub_root, "**", "*.jsonl"), recursive=True):
        if os.path.basename(p) == "journal.jsonl":
            continue
        files.append(("sub", p))
    return files


def iter_usage(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if '"usage"' not in line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            msg = rec.get("message")
            if not isinstance(msg, dict):
                continue
            usage = msg.get("usage")
            if not isinstance(usage, dict):
                continue
            if msg.get("role") != "assistant":
                continue
            yield {
                "id": msg.get("id"),
                "request_id": rec.get("requestId"),
                "model": msg.get("model"),
                "timestamp": rec.get("timestamp"),
                "session": rec.get("sessionId"),
                "sidechain": rec.get("isSidechain"),
                "agent": rec.get("agentId"),
                "usage": usage,
            }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="")
    ap.add_argument("--json", default="")
    ap.add_argument("--probe", action="store_true", help="print the usage key structure of a few records")
    args = ap.parse_args()

    files = session_files()
    best = {}
    raw_lines = 0
    probe_shown = 0
    for kind, path in files:
        for u in iter_usage(path):
            raw_lines += 1
            if args.since and u["timestamp"] and u["timestamp"] < args.since:
                continue
            if args.probe and probe_shown < 3:
                probe_shown += 1
                print("PROBE", kind, {k: (v if not isinstance(v, dict) else sorted(v.keys())) for k, v in u.items() if k != "usage"})
                print("PROBE usage:", json.dumps(u["usage"])[:900])
            key = (u["id"], u["request_id"])
            if u["id"] is None:
                key = (path, raw_lines)
            prev = best.get(key)
            if prev is None or (u["usage"].get("output_tokens") or 0) >= (prev["usage"].get("output_tokens") or 0):
                u["file_kind"] = kind
                best[key] = u

    per_model = defaultdict(lambda: defaultdict(int))
    first_ts, last_ts = None, None
    for u in best.values():
        us = u["usage"]
        model = u["model"] or "unknown"
        if model == "<synthetic>":
            continue
        m = per_model[(model, u["file_kind"])]
        m["requests"] += 1
        m["input"] += us.get("input_tokens") or 0
        m["cache_read"] += us.get("cache_read_input_tokens") or 0
        m["cache_write"] += us.get("cache_creation_input_tokens") or 0
        cc = us.get("cache_creation") or {}
        m["cache_write_5m"] += cc.get("ephemeral_5m_input_tokens") or 0
        m["cache_write_1h"] += cc.get("ephemeral_1h_input_tokens") or 0
        m["output"] += us.get("output_tokens") or 0
        m["thinking_included_in_output"] += (us.get("output_tokens_details") or {}).get("thinking_tokens") or 0
        tier = us.get("service_tier") or "unknown"
        m["tier_" + str(tier)] += 1
        stu = us.get("server_tool_use") or {}
        m["web_search_requests"] += stu.get("web_search_requests") or 0
        m["web_fetch_requests"] += stu.get("web_fetch_requests") or 0
        ts = u["timestamp"]
        if ts:
            first_ts = ts if first_ts is None or ts < first_ts else first_ts
            last_ts = ts if last_ts is None or ts > last_ts else last_ts

    result = {"session": SESSION_ID, "files": len(files), "raw_usage_lines": raw_lines,
              "deduplicated_requests": sum(v["requests"] for v in per_model.values()),
              "first_request": first_ts, "last_request": last_ts, "models": {}}
    grand = defaultdict(int)
    for (model, kind), m in sorted(per_model.items()):
        total = m["input"] + m["cache_read"] + m["cache_write"] + m["output"]
        d = dict(m)
        d["total"] = total
        result["models"]["%s | %s" % (model, kind)] = d
        for k, v in d.items():
            grand[k] += v
        pm = result.setdefault("per_model", {}).setdefault(model, defaultdict(int))
        for k, v in d.items():
            pm[k] += v
    result["grand_total"] = dict(grand)
    print(json.dumps(result, indent=2))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2)


if __name__ == "__main__":
    sys.exit(main())
