# Additional local log roots

OpenUsage can include read-only copies of Claude Code and Codex session logs in its local spend
history. This is useful when another computer syncs its session JSONL files to the Mac running
OpenUsage. Live subscription limits still come from the signed-in account.

Add `logSources` to `~/.openusage/config.json`:

```json
{
  "logSources": {
    "claudeProjectDirectories": ["~/Sync/AI-logs/claude-projects"],
    "codexSessionDirectories": ["~/Sync/AI-logs/codex-sessions"]
  }
}
```

Each Claude path points directly to a copied `projects/` tree. Each Codex path points directly to
a copied `sessions/` tree. OpenUsage searches each tree recursively for `.jsonl` files. It does not
change Claude Code's or Codex's own homes, write to the archive, or read credentials from it. Keep
any existing `proxy` entry in the same config file. Restart OpenUsage after changing the paths.

Session ownership rules still apply. Claude sessions with a conflicting or unrecognized account
are excluded from scoped account cards. Codex session rollouts do not identify the account that
paid for each turn, so local Codex history is excluded when multiple accounts are known. Copied
logs do not change that limitation. Only entries in the normal local-history date window appear.
