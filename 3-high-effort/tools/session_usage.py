"""Sum token usage for one Claude Code session from its local JSONL log.

Reads only the per-message `usage` and `model` fields (no message content is copied).
Deduplicates by message id (streamed assistant messages are logged once per content block).
Usage: python tools/session_usage.py <session.jsonl> [<subagent.jsonl> ...]
"""
import json
import sys
from collections import defaultdict

PRICES = {  # USD per million tokens, platform.claude.com pricing page (fetched 2026-10-23)
    "opus-5-5": {"in": 4.0, "w5": 5.0, "w1h": 8.0, "read": 0.20, "out": 20.0},
    "sonnet-5-5": {"in": 2.0, "w5": 2.5, "w1h": 4.0, "read": 0.10, "out": 10.0},
}


def price_key(model):
    m = (model or "").lower()
    for k in PRICES:
        if k in m:
            return k
    return None


def scan(path):
    seen = {}
    first = last = None
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                rec = json.loads(line)
            except Exception:
                continue
            ts = rec.get("timestamp")
            msg = rec.get("message") if isinstance(rec.get("message"), dict) else None
            if not msg or msg.get("role") != "assistant" or "usage" not in msg:
                continue
            mid = msg.get("id") or rec.get("requestId") or rec.get("uuid")
            u = msg["usage"]
            seen[mid] = (msg.get("model"), u, ts)
            first = first or ts
            last = ts
    return seen, first, last


def main():
    grand = defaultdict(float)
    for path in sys.argv[1:]:
        seen, first, last = scan(path)
        per_model = defaultdict(lambda: defaultdict(float))
        for model, u, ts in seen.values():
            pm = per_model[model]
            pm["requests"] += 1
            pm["input"] += u.get("input_tokens", 0) or 0
            pm["output"] += u.get("output_tokens", 0) or 0
            pm["cache_read"] += u.get("cache_read_input_tokens", 0) or 0
            cc = u.get("cache_creation") or {}
            w5 = cc.get("ephemeral_5m_input_tokens")
            w1 = cc.get("ephemeral_1h_input_tokens")
            total_w = u.get("cache_creation_input_tokens", 0) or 0
            if w5 is None and w1 is None:
                w5, w1 = total_w, 0
            pm["cache_write_5m"] += w5 or 0
            pm["cache_write_1h"] += w1 or 0
        print(f"== {path}\n   first={first} last={last}")
        for model, pm in per_model.items():
            k = price_key(model)
            cost = None
            if k:
                p = PRICES[k]
                cost = (pm["input"] * p["in"] + pm["cache_write_5m"] * p["w5"] + pm["cache_write_1h"] * p["w1h"]
                        + pm["cache_read"] * p["read"] + pm["output"] * p["out"]) / 1e6
                grand["cost"] += cost
            tot = pm["input"] + pm["output"] + pm["cache_read"] + pm["cache_write_5m"] + pm["cache_write_1h"]
            for key in ("input", "output", "cache_read", "cache_write_5m", "cache_write_1h"):
                grand[key] += pm[key]
            grand["total"] += tot
            print(f"   model={model} requests={int(pm['requests'])} input={int(pm['input'])} cache_read={int(pm['cache_read'])} "
                  f"cache_write_5m={int(pm['cache_write_5m'])} cache_write_1h={int(pm['cache_write_1h'])} output={int(pm['output'])} "
                  f"total={int(tot)} cost_usd={cost if cost is None else round(cost, 2)}")
    print("== GRAND", {k: (round(v, 2) if k == "cost" else int(v)) for k, v in grand.items()})


if __name__ == "__main__":
    main()
