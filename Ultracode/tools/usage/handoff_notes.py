"""Build hand-off notes for agents that were cut off (usage limit) in a workflow run.

For every agent transcript in the workflow folder that has no "result" line in journal.jsonl
this writes qa/handoff/<label>.md containing: the files it wrote/edited, its last assistant
messages (plain text only, truncated), and its last tool calls. The successor agent reads the
note to continue the work instead of starting over.

Usage: python tools/usage/handoff_notes.py <workflow_transcript_dir> [--out qa/handoff]
"""
import json
import os
import re
import sys


def main():
    wf_dir = sys.argv[1]
    out_dir = "qa/handoff"
    if "--out" in sys.argv:
        out_dir = sys.argv[sys.argv.index("--out") + 1]
    os.makedirs(out_dir, exist_ok=True)

    done = set()
    with open(os.path.join(wf_dir, "journal.jsonl"), "r", encoding="utf-8") as f:
        for line in f:
            try:
                o = json.loads(line)
            except Exception:
                continue
            if o.get("type") == "result":
                done.add(o.get("agentId"))

    for name in sorted(os.listdir(wf_dir)):
        if not name.endswith(".meta.json"):
            continue
        agent_id = name[len("agent-"):-len(".meta.json")]
        with open(os.path.join(wf_dir, name), "r", encoding="utf-8") as f:
            meta = json.load(f)
        label = meta.get("description", agent_id)
        if agent_id in done:
            continue
        path = os.path.join(wf_dir, "agent-%s.jsonl" % agent_id)
        if not os.path.exists(path):
            continue
        files = []
        texts = []
        tools = []
        first_ts = last_ts = None
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                ts = rec.get("timestamp")
                if ts:
                    first_ts = first_ts or ts
                    last_ts = ts
                msg = rec.get("message")
                if not isinstance(msg, dict) or msg.get("role") != "assistant":
                    continue
                content = msg.get("content")
                if not isinstance(content, list):
                    continue
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "text":
                        t = (block.get("text") or "").strip()
                        if t:
                            texts.append(t)
                    elif block.get("type") == "tool_use":
                        inp = block.get("input") or {}
                        tname = block.get("name", "")
                        fp = inp.get("file_path")
                        if tname in ("Write", "Edit") and fp and fp not in files:
                            files.append(fp)
                        desc = inp.get("description") or inp.get("command") or inp.get("file_path") or inp.get("pattern") or ""
                        if not desc and "code" in inp:
                            desc = inp["code"][:160].replace("\n", " | ")
                        tools.append("%s: %s" % (tname.split("__")[-1], str(desc)[:200].replace("\n", " ")))
        safe = re.sub(r"[^A-Za-z0-9_\-]", "_", label)
        out = os.path.join(out_dir, safe + ".md")
        with open(out, "w", encoding="utf-8") as f:
            f.write("# Hand-off note for `%s`\n\n" % label)
            f.write("The previous agent on this brief was cut off by an account usage limit (not by a bug) ")
            f.write("at %s after starting at %s. Everything it saved is on disk; the last tool call may be half-done.\n\n" % (last_ts, first_ts))
            f.write("## Files it created or edited (%d)\n\n" % len(files))
            for fp in files:
                f.write("- %s\n" % fp)
            f.write("\n## Its last tool calls (most recent last)\n\n")
            for t in tools[-25:]:
                f.write("- %s\n" % t)
            f.write("\n## Its last messages (most recent last)\n\n")
            for t in texts[-8:]:
                t = t if len(t) <= 1800 else t[:1800] + " ...[truncated]"
                f.write("> " + t.replace("\n", "\n> ") + "\n\n")
        print("HANDOFF", label, "files=%d texts=%d tools=%d ->" % (len(files), len(texts), len(tools)), out)


if __name__ == "__main__":
    main()
