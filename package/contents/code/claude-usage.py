#!/usr/bin/env python3
"""Fetch Claude usage (5h session + weekly limits) from the OAuth usage
endpoint — the same source as Claude Code's /usage. Emits compact JSON for
the Plasma widget, with reset times pre-converted to epoch milliseconds."""
import json
import os
import datetime
import urllib.request
import urllib.error

CRED = os.path.expanduser("~/.claude/.credentials.json")
URL = "https://api.anthropic.com/api/oauth/usage"


def emit(obj):
    print(json.dumps(obj))
    raise SystemExit(0)


try:
    with open(CRED) as f:
        token = json.load(f)["claudeAiOauth"]["accessToken"]
except Exception:
    emit({"error": "no-token"})

req = urllib.request.Request(
    URL,
    headers={
        "Authorization": "Bearer " + token,
        "anthropic-beta": "oauth-2025-04-20",
        "Content-Type": "application/json",
    },
)
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.load(r)
except urllib.error.HTTPError as e:
    emit({"error": "http-%d" % e.code})  # 401 => token expired, run claude
except Exception:
    emit({"error": "net"})


def conv(d):
    if not d:
        return None
    ms = None
    r = d.get("resets_at")
    if r:
        try:
            ms = int(datetime.datetime.fromisoformat(r).timestamp() * 1000)
        except Exception:
            ms = None
    return {"util": d.get("utilization"), "resets_ms": ms}


emit({
    "ok": True,
    "five_hour": conv(data.get("five_hour")),
    "seven_day": conv(data.get("seven_day")),
    "seven_day_opus": conv(data.get("seven_day_opus")),
    "seven_day_sonnet": conv(data.get("seven_day_sonnet")),
})
