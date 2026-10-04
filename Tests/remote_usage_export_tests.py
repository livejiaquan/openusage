import contextlib
import datetime as dt
import importlib.util
import io
import json
import os
import pathlib
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "Sources/OpenUsage/Resources/remote_usage_export.py"
SPEC = importlib.util.spec_from_file_location("remote_usage_export", SCRIPT)
exporter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(exporter)


class RemoteUsageExportTests(unittest.TestCase):
    def test_child_replay_and_claude_usage_export_without_conversation(self):
        with tempfile.TemporaryDirectory() as temporary:
            old_home = os.environ.get("HOME")
            old_codex = os.environ.pop("CODEX_HOME", None)
            old_claude = os.environ.pop("CLAUDE_CONFIG_DIR", None)
            os.environ["HOME"] = temporary
            try:
                home = pathlib.Path(temporary)
                codex = home / ".codex/sessions/2026/10/04/rollout.jsonl"
                claude = home / ".claude/projects/example/session.jsonl"
                codex.parent.mkdir(parents=True)
                claude.parent.mkdir(parents=True)
                now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
                when = now.isoformat().replace("+00:00", "Z")
                started = int(now.timestamp())
                lines = [
                    {"timestamp": when, "type": "session_meta", "payload": {"parent_thread_id": "parent"}},
                    {"timestamp": when, "type": "turn_context", "payload": {"model": "gpt-5.2"}},
                    {"timestamp": when, "type": "event_msg", "payload": {"type": "token_count", "info": {
                        "total_token_usage": {"input_tokens": 100, "output_tokens": 20},
                        "last_token_usage": {"input_tokens": 100, "output_tokens": 20}}}},
                    {"timestamp": when, "type": "event_msg", "payload": {"type": "task_started", "started_at": started}},
                    {"timestamp": when, "type": "event_msg", "payload": {"type": "token_count", "info": {
                        "total_token_usage": {"input_tokens": 130, "output_tokens": 25},
                        "last_token_usage": {"input_tokens": 30, "output_tokens": 5}}}},
                ]
                codex.write_text("\n".join(json.dumps(item) for item in lines) + "\n")
                archived = home / ".codex/archived_sessions/2026/10/04/rollout.jsonl"
                archived.parent.mkdir(parents=True)
                archived.write_text(json.dumps({
                    "timestamp": when, "type": "event_msg", "payload": {"type": "token_count", "info": {
                        "last_token_usage": {"input_tokens": 999, "output_tokens": 999}}}
                }) + "\n")
                claude.write_text(json.dumps({
                    "timestamp": when, "sessionId": "session", "requestId": "request",
                    "version": "2.1.0", "prompt": "SECRET_CONVERSATION_TEXT",
                    "message": {"id": "message", "model": "claude-sonnet-4-5", "usage": {
                        "input_tokens": 10, "output_tokens": 3,
                        "cache_creation_input_tokens": 2, "cache_read_input_tokens": 4}}
                }) + "\n")

                first = self.run_export()
                second = self.run_export()  # Exercises the incremental parsed-event cache.
                self.assertEqual(first, second)
                self.assertEqual(len(first["codex"]), 1)
                self.assertEqual(first["codex"][0]["total"], 35)
                self.assertEqual(len(first["claude"]), 1)
                self.assertEqual(first["claude"][0]["tokens"]["cacheRead"], 4)
                self.assertNotIn("SECRET_CONVERSATION_TEXT", json.dumps(first))
                self.assertNotIn("SECRET_CONVERSATION_TEXT", (home / ".cache/openusage-remote/events-v1.json").read_text())
            finally:
                if old_home is None:
                    os.environ.pop("HOME", None)
                else:
                    os.environ["HOME"] = old_home
                if old_codex is not None:
                    os.environ["CODEX_HOME"] = old_codex
                if old_claude is not None:
                    os.environ["CLAUDE_CONFIG_DIR"] = old_claude

    @staticmethod
    def run_export():
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            exporter.main()
        return json.loads(output.getvalue())


if __name__ == "__main__":
    unittest.main()
