"""Read local CLI logs and emit usage metadata only. Run through SSH on stdin.

The Mac prices and deduplicates these events with OpenUsage's existing Swift code.
No prompts, responses, credentials, or raw JSONL lines enter stdout or the cache.
"""

import datetime as dt
import json
import math
import os
import pathlib
import re
import sys
import tempfile

SCHEMA = "openusage.remote-events.v1"
CACHE_SCHEMA = 2
MAX_LINE = 8 * 1024 * 1024
UTC = dt.timezone.utc


def stamp(value):
    if not isinstance(value, str):
        return None
    try:
        return dt.datetime.fromisoformat(value.strip().replace("Z", "+00:00")).astimezone(UTC).timestamp()
    except ValueError:
        return None


def integer(value):
    return int(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else 0


def model_name(value):
    for candidate in (value.get("model"), value.get("model_name"),
                      (value.get("metadata") or {}).get("model") if isinstance(value.get("metadata"), dict) else None):
        if isinstance(candidate, str) and candidate.strip():
            return candidate.strip()
    return None


def codex_usage(value):
    def field(*names):
        for name in names:
            if name in value:
                return integer(value[name])
        return 0
    result = {
        "input": field("input_tokens", "prompt_tokens", "input"),
        "cached": field("cached_input_tokens", "cache_read_input_tokens", "cached_tokens"),
        "output": field("output_tokens", "completion_tokens", "output"),
        "reasoning": field("reasoning_output_tokens", "reasoning_tokens"),
    }
    reported = field("total_tokens")
    computed = result["input"] + result["output"] + result["reasoning"]
    result["total"] = reported if reported > 0 or computed == 0 else computed
    return result


def child_meta(value):
    def present(item):
        return item is not None and (not isinstance(item, str) or bool(item.strip()))
    source = value.get("source")
    return (present(value.get("forked_from_id")) or present(value.get("parent_thread_id"))
            or value.get("thread_source") == "subagent"
            or (isinstance(source, dict) and present(source.get("subagent"))))


def codex_fallback(model, iso_date):
    if model == "gpt-reserve":
        return "gpt-5.6-luna"
    if model != "codex-auto-review":
        return None
    for day, fallback in (("2026-07-09", "gpt-5.6-luna"), ("2026-04-23", "gpt-5.5"),
                          ("2026-03-05", "gpt-5.4"), ("2026-02-05", "gpt-5.3-codex"),
                          ("2025-12-11", "gpt-5.2-codex"), ("2025-11-13", "gpt-5.1-codex"),
                          ("2025-09-15", "gpt-5-codex"), ("2025-08-07", "gpt-5")):
        if iso_date >= day:
            return fallback
    return "gpt-5"


def parse_codex(path):
    events = []
    previous = None
    model = None
    fast = ultrafast = False
    saw_meta = False
    replay_gate = None
    with path.open("rb") as source:
        for line in source:
            if len(line) > MAX_LINE or not any(tag in line for tag in
                (b'"turn_context"', b'"session_meta"', b'"task_started"',
                 b'"thread_settings_applied"', b'"token_count"')):
                continue
            try:
                obj = json.loads(line)
            except (ValueError, UnicodeDecodeError):
                continue
            if not isinstance(obj, dict):
                continue
            payload = obj.get("payload")
            if not isinstance(payload, dict):
                continue
            kind = obj.get("type")
            if kind == "turn_context":
                model = model_name(payload) or model
                continue
            if kind == "session_meta" and not saw_meta:
                saw_meta = True
                if child_meta(payload):
                    created = stamp(obj.get("timestamp"))
                    replay_gate = int(created) if created is not None else "self"
                continue
            event_type = payload.get("type")
            if kind != "event_msg":
                continue
            if event_type == "thread_settings_applied":
                settings = payload.get("thread_settings")
                settings = settings if isinstance(settings, dict) else {}
                tier = settings.get("service_tier") or payload.get("service_tier")
                if isinstance(tier, str) and tier.strip():
                    fast = tier.strip() in ("fast", "priority")
                    ultrafast = tier.strip() == "ultrafast"
                continue
            if event_type == "task_started":
                started = payload.get("started_at")
                line_time = stamp(obj.get("timestamp"))
                gate = int(line_time) if replay_gate == "self" and line_time is not None else replay_gate
                if isinstance(started, (int, float)) and isinstance(gate, int) and started >= gate:
                    replay_gate = None
                continue
            if event_type != "token_count":
                continue
            when = stamp(obj.get("timestamp"))
            if when is None:
                continue
            info = payload.get("info")
            info = info if isinstance(info, dict) else {}
            totals = codex_usage(info["total_token_usage"]) if isinstance(info.get("total_token_usage"), dict) else None
            if replay_gate is not None:
                previous = totals or previous
                continue
            if totals is not None and totals == previous:
                continue
            last = info.get("last_token_usage")
            if isinstance(last, dict):
                usage = codex_usage(last)
            elif totals is not None:
                usage = {key: max(0, value - (previous or {}).get(key, 0)) for key, value in totals.items()}
            else:
                continue
            previous = totals or previous
            if not any(usage[key] > 0 for key in ("input", "cached", "output", "reasoning")):
                continue
            model = model_name(payload) or model_name(info) or model or "gpt-5"
            events.append({"timestamp": when - 978307200, "model": model,
                           "pricingModel": codex_fallback(model, str(obj.get("timestamp", ""))[:10]),
                           "input": usage["input"], "cached": min(usage["cached"], usage["input"]),
                           "output": usage["output"], "reasoning": usage["reasoning"],
                           "total": usage["total"], "isFast": fast, "isUltrafast": ultrafast})
    return events


def claude_tokens(usage):
    if not isinstance(usage.get("input_tokens"), (int, float)) or not isinstance(usage.get("output_tokens"), (int, float)):
        return None
    speed = usage.get("speed")
    if speed is not None and speed not in ("standard", "fast"):
        return None
    creation = usage.get("cache_creation")
    if isinstance(creation, dict):
        write5 = integer(creation.get("ephemeral_5m_input_tokens"))
        write1 = integer(creation.get("ephemeral_1h_input_tokens"))
    else:
        write5 = integer(usage.get("cache_creation_input_tokens"))
        write1 = 0
    return {"input": integer(usage["input_tokens"]), "cacheWrite5m": write5,
            "cacheWrite1h": write1, "cacheRead": integer(usage.get("cache_read_input_tokens")),
            "output": integer(usage["output_tokens"]), "isFast": speed == "fast"}


def parse_claude(path):
    entries = []
    with path.open("rb") as source:
        for line in source:
            if len(line) > MAX_LINE or b'"usage"' not in line:
                continue
            try:
                obj = json.loads(line)
            except (ValueError, UnicodeDecodeError):
                continue
            if not isinstance(obj, dict):
                continue
            when = stamp(obj.get("timestamp"))
            message = obj.get("message")
            if when is None or not isinstance(message, dict):
                continue
            usage = message.get("usage")
            if not isinstance(usage, dict):
                continue
            if any(obj.get(key) is None for key in ("timestamp",)) or any(
                key in part and part[key] is None for part, keys in
                ((obj, ("sessionId", "requestId")), (message, ("id", "model")),
                 (usage, ("speed", "cache_read_input_tokens", "cache_creation_input_tokens")))
                for key in keys):
                continue
            version = obj.get("version")
            if isinstance(version, str) and not re.match(r"^\d+\.\d+\.\d+", version):
                continue
            if any(isinstance(value, str) and not value for value in
                   (obj.get("sessionId"), obj.get("requestId"), message.get("id"), message.get("model"))):
                continue
            tokens = claude_tokens(usage)
            if tokens is None:
                continue
            model = message.get("model")
            model = model if isinstance(model, str) and model != "<synthetic>" else None
            cost = obj.get("costUSD")
            cost = cost if isinstance(cost, (int, float)) and math.isfinite(cost) and cost >= 0 else None
            message_id = message.get("id") if isinstance(message.get("id"), str) else None
            request_id = obj.get("requestId") if isinstance(obj.get("requestId"), str) else None
            base = {"timestamp": when - 978307200, "tokens": tokens,
                    "messageID": message_id, "requestID": request_id,
                    "isSidechain": obj.get("isSidechain") is True, "hasSpeed": "speed" in usage,
                    "costUSD": cost,
                    "model": model}
            entries.append(base)
            advisor_index = 0
            for iteration in usage.get("iterations", []) if isinstance(usage.get("iterations"), list) else []:
                if not isinstance(iteration, dict) or iteration.get("type") != "advisor_message":
                    continue
                advisor_model = iteration.get("model")
                advisor_tokens = claude_tokens(iteration)
                if not isinstance(advisor_model, str) or not advisor_model or advisor_tokens is None:
                    continue
                child = dict(base, tokens=advisor_tokens, model=advisor_model, costUSD=None,
                             messageID=f"{base['messageID']}:advisor:{advisor_index}" if base["messageID"] else None,
                             hasSpeed="speed" in iteration)
                entries.append(child)
                advisor_index += 1
    return entries


def roots(provider):
    home = pathlib.Path.home()
    if provider == "codex":
        raw = os.environ.get("CODEX_HOME", "")
        homes = [pathlib.Path(part.strip()).expanduser() for part in raw.split(",") if part.strip()] if raw.strip() else [home / ".codex"]
        result = []
        for codex_home in homes:
            dirs = [codex_home / "sessions", codex_home / "archived_sessions"]
            result.extend([folder for folder in dirs if folder.is_dir()] or [codex_home])
        return result
    raw = os.environ.get("CLAUDE_CONFIG_DIR", "")
    if raw.strip():
        configs = [pathlib.Path(part.strip()).expanduser() for part in raw.split(",") if part.strip()]
    else:
        configs = [pathlib.Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")) / "claude", home / ".claude"]
    return [config if config.name == "projects" else config / "projects" for config in configs]


def discover(provider):
    seen = set()
    result = []
    if provider == "codex":
        raw = os.environ.get("CODEX_HOME", "")
        homes = [pathlib.Path(part.strip()).expanduser() for part in raw.split(",") if part.strip()] if raw.strip() else [pathlib.Path.home() / ".codex"]
        for home in homes:
            relative_seen = set()
            directories = [folder for folder in (home / "sessions", home / "archived_sessions") if folder.is_dir()] or [home]
            for root in directories:
                for path in sorted(root.rglob("*.jsonl")):
                    if not path.is_file():
                        continue
                    relative = str(path.relative_to(root))
                    resolved = str(path.resolve())
                    if relative not in relative_seen and resolved not in seen:
                        relative_seen.add(relative)
                        seen.add(resolved)
                        result.append(path)
    else:
        for root in roots(provider):
            if not root.is_dir():
                continue
            for path in sorted(root.rglob("*.jsonl")):
                if not path.is_file():
                    continue
                resolved = str(path.resolve())
                if resolved not in seen:
                    seen.add(resolved)
                    result.append(path)
    return result


def main():
    cache_dir = pathlib.Path.home() / ".cache" / "openusage-remote"
    cache_file = cache_dir / "events-v1.json"
    try:
        cache = json.loads(cache_file.read_text())
        if cache.get("schema") != CACHE_SCHEMA:
            cache = {}
    except (OSError, ValueError):
        cache = {}
    old = cache.get("files", {})
    updated = {}
    result = {"schema": SCHEMA, "codex": [], "claude": []}
    cutoff = (dt.datetime.now().astimezone() - dt.timedelta(days=31)).timestamp() - 978307200
    for provider, parser in (("codex", parse_codex), ("claude", parse_claude)):
        for path in discover(provider):
            key = provider + ":" + str(path.resolve())
            try:
                stat = path.stat()
                cached = old.get(key)
                if isinstance(cached, dict) and cached.get("size") == stat.st_size and cached.get("mtime") == stat.st_mtime_ns:
                    events = cached["events"]
                else:
                    events = parser(path)
                updated[key] = {"size": stat.st_size, "mtime": stat.st_mtime_ns, "events": events}
                result[provider].extend(event for event in events if event["timestamp"] >= cutoff)
            except OSError as error:
                raise SystemExit(f"Could not read a {provider} session: {error}") from error
    # Cache contains only normalized usage metadata and is private to the remote user.
    try:
        cache_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", dir=cache_dir, prefix="events-", delete=False) as temp:
            os.chmod(temp.name, 0o600)
            json.dump({"schema": CACHE_SCHEMA, "files": updated}, temp, separators=(",", ":"))
            temp_name = temp.name
        os.replace(temp_name, cache_file)
    except OSError as error:
        print(f"Could not update remote usage cache: {error}", file=sys.stderr)
    json.dump(result, sys.stdout, separators=(",", ":"))


if __name__ == "__main__":
    main()
