#!/usr/bin/env python3
"""Fetch Claude usage (5h session + weekly limits) from the OAuth usage
endpoint — the same source as Claude Code's /usage. Emits compact JSON for
the Plasma widget, with reset times pre-converted to epoch milliseconds."""
import json
import os
import datetime
import urllib.request
import urllib.error

CRED = os.path.expanduser(
    os.environ.get("CLAUDE_CREDENTIALS", "~/.claude/.credentials.json"))
URL = "https://api.anthropic.com/api/oauth/usage"


def emit(obj):
    obj["fetched_ms"] = int(datetime.datetime.now().timestamp() * 1000)
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


def to_ms(iso):
    if not iso:
        return None
    try:
        return int(datetime.datetime.fromisoformat(iso).timestamp() * 1000)
    except Exception:
        return None


def conv(d):
    if not d:
        return None
    return {"util": d.get("utilization"), "resets_ms": to_ms(d.get("resets_at"))}


# The `limits` array is the current shape of the API: one entry per active
# limit, including per-model weekly caps that the legacy `seven_day_opus` /
# `seven_day_sonnet` fields no longer carry (they come back null).
KIND_LABELS = {
    "session": "Current session",
    "weekly_all": "All models",
    "weekly_opus": "Opus",
    "weekly_sonnet": "Sonnet",
    "weekly_scoped": "Scoped",
}


def label_for(lim):
    scope = lim.get("scope") or {}
    model = (scope.get("model") or {}).get("display_name")
    surface = (scope.get("surface") or {})
    surface_name = surface.get("display_name") if isinstance(surface, dict) else surface
    if model:
        return model
    if surface_name:
        return str(surface_name)
    kind = lim.get("kind") or ""
    return KIND_LABELS.get(kind, kind.replace("_", " ").title() or "Limit")


limits = []
for lim in (data.get("limits") or []):
    if not isinstance(lim, dict):
        continue
    limits.append({
        "kind": lim.get("kind"),
        "group": lim.get("group"),
        "label": label_for(lim),
        "util": lim.get("percent"),
        "resets_ms": to_ms(lim.get("resets_at")),
        "severity": lim.get("severity"),
        "is_active": bool(lim.get("is_active")),
    })

# Extra usage credits (pay-as-you-go beyond the plan), when enabled.
extra = data.get("extra_usage") or {}
spend = data.get("spend") or {}
used = spend.get("used") or {}
extra_out = None
if extra.get("is_enabled") or spend.get("enabled"):
    amount = used.get("amount_minor")
    exponent = used.get("exponent")
    extra_out = {
        "util": extra.get("utilization") if extra.get("utilization") is not None
                else spend.get("percent"),
        "used": (amount / (10 ** exponent)) if isinstance(amount, (int, float))
                and isinstance(exponent, int) else None,
        "currency": used.get("currency") or extra.get("currency"),
    }

emit({
    "ok": True,
    "five_hour": conv(data.get("five_hour")),
    "seven_day": conv(data.get("seven_day")),
    "seven_day_opus": conv(data.get("seven_day_opus")),
    "seven_day_sonnet": conv(data.get("seven_day_sonnet")),
    "limits": limits,
    "extra": extra_out,
})
