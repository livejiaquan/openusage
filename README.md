# Tokamak

Track your AI coding subscriptions from the macOS menu bar — including the usage on your other computers.

> **Tokamak is an unofficial fork of [OpenUsage](https://github.com/robinebers/openusage) by Robin Ebers.**
> It is not the official OpenUsage app and is not endorsed by its maintainers. Report problems with
> Tokamak [here](https://github.com/livejiaquan/openusage/issues), not to the OpenUsage project.

Tokamak shows how much of your AI coding plans you've used: session and weekly limits, credits, and spend, all in one popover. Pin your most important metrics straight into the menu bar.

## What Tokamak Adds

- **[Remote Devices](docs/remote-devices.md).** Pull Claude Code and Codex history from your Linux servers, other Macs, Windows PCs, and WSL over the SSH keys you already use. The dashboard's **Usage From** menu switches between all devices, this Mac, and each machine. Only daily summaries are stored on this Mac; prompts and replies never leave the remote machine.
- **[Extra local log folders](docs/local-log-roots.md).** Include copied session archives in this Mac's history.

Everything else comes from OpenUsage, which Tokamak tracks closely.

## How It Differs From OpenUsage

- **Different app, side by side.** Tokamak has its own bundle ID (`com.livejiaquan.tokamak`), settings, logs (`~/Library/Logs/Tokamak`), local API port (`6740`), and CLI command (`tokamak`), so it can be installed next to the official app without either touching the other.
- **No analytics.** Tokamak ships without an analytics key, so it sends no usage statistics or crash reports anywhere.
- **No iCloud Sync.** Syncing history across Macs needs the fork's own iCloud container, so it is turned off. Remote Devices covers the same need over SSH.
- **Updates come from this repository**, not from OpenUsage's update feed.

## Installation

Signed releases aren't published yet. Until then, build it yourself (see [Building](#building)) or download the app bundle from the latest successful **Build Tokamak app** run under [Actions](https://github.com/livejiaquan/openusage/actions). Those builds are ad-hoc signed, so macOS asks you to confirm the first launch. Requires macOS 15 (Sequoia) or later.

## Supported Providers

- **[Antigravity](docs/providers/antigravity.md)** — shared Gemini and Claude pool quotas, 5-hour and weekly windows
- **[Claude](docs/providers/claude.md)** — session, weekly, model-specific limits, extra usage, local daily spend
- **[Codex](docs/providers/codex.md)** — session, weekly, credits, local daily spend
- **[Copilot](docs/providers/copilot.md)** — AI credits, extra usage, organization billing, chat and completions
- **[Cursor](docs/providers/cursor.md)** — credits, total usage, Grok Bot, Cursor Models, Other Models, requests, on-demand, per-day spend
- **[Devin](docs/providers/devin.md)** — weekly and daily quota, extra usage balance
- **[Grok](docs/providers/grok.md)** — weekly shared pool, pay-as-you-go, local daily spend
- **[Ollama](docs/providers/ollama.md)** — Ollama Cloud session and weekly limits, recent activity spend
- **[OpenCode](docs/providers/opencode.md)** — Go session/weekly/monthly caps, Zen spend, local daily spend
- **[OpenRouter](docs/providers/openrouter.md)** — credit balance, daily/weekly/monthly spend (API key)
- **[Z.ai](docs/providers/zai.md)** — session, weekly, web-search quotas (GLM Coding Plan, API key)

Most providers read the credentials already on your machine (keychain, auth files, app state) — no extra login. OpenRouter and Z.ai are the exceptions: they have no local credential to reuse, so you supply an API key (see [OpenRouter setup](docs/providers/openrouter.md) or [Z.ai setup](docs/providers/zai.md)). Credentials are used only for the corresponding provider requests. See [Privacy & usage data](docs/privacy.md).

## Features

- **Menu bar pins.** Pin metrics to the menu bar (up to 2 per provider); render as compact text or mini bars. The strip hides metrics with no data instead of showing placeholders.
- **Dashboard popover.** Provider-grouped meters with live reset countdowns and pace indicators. Click usage or reset values to flip their display everywhere; right-click a row to hide or star it, refresh its provider, or open Customize.
- **Global shortcut.** Toggle the popover from anywhere — record any combo in Settings.
- **Customize.** Turn providers and metrics on or off, choose which rows stay Always Visible or On Demand, and drag-reorder both.
- **Stale-while-revalidate.** Cached values display instantly at launch; refresh runs every 5 minutes.
- **[One-shot CLI](docs/cli.md).** Agents can read stable limit JSON through the same five-minute cache with `tokamak`, or bypass freshness with `tokamak --force`; the menu-bar app does not need to be running.
- **[Local HTTP API](docs/local-http-api.md).** Other apps can read machine-friendly limits from `127.0.0.1:6740/v1/limits`. It is loopback-only and never serves credentials; note that browser pages can read it too — see the [privacy note](docs/local-http-api.md#cors-and-privacy).
- **[Proxy support](docs/proxy.md).** Route provider requests through SOCKS5 or HTTP(S) via `~/.openusage/config.json`.
- **Native settings.** Launch at login, global shortcut, icon style, theme, density, 12/24-hour time — see [Settings](docs/settings.md).

## Documentation

Behavior docs live in [docs/](docs/README.md). Most pages describe behavior shared with OpenUsage and still use its name. Developer docs: [architecture](docs/architecture.md), [adding a provider](docs/adding-a-provider.md), and [debugging & capturing logs](docs/debugging.md).

## Building

```sh
swift build                 # debug build
swift test                  # run the test suite
./script/build_and_run.sh   # build and launch dist/Tokamak.app (no install)
```

Internal module and type names keep OpenUsage's spelling on purpose, so changes from upstream merge cleanly. Everything a user sees reads from `Sources/OpenUsage/Support/AppBrand.swift`. The app icon is generated by `assets/TokamakIcon/render.swift`.

## Releasing

Pushing a `v*` tag runs [.github/workflows/release.yml](.github/workflows/release.yml), which builds, signs, notarizes, and publishes a DMG and an appcast on this repository's GitHub Pages. It needs these repository secrets (Settings → Secrets and variables → Actions):

| Secret                       | What it is                                                        |
| ---------------------------- | ----------------------------------------------------------------- |
| `APPLE_CERTIFICATE`          | base64 of your Developer ID Application `.p12`                    |
| `APPLE_CERTIFICATE_PASSWORD` | the password set when exporting that `.p12`                       |
| `APPLE_ID`                   | the Apple ID email used for notarization                          |
| `APPLE_PASSWORD`             | an app-specific password for that Apple ID                        |
| `APPLE_TEAM_ID`              | your Apple Developer team ID                                      |
| `SPARKLE_PUBLIC_KEY`         | base64 EdDSA public key, baked into the build as `SUPublicEDKey`  |
| `SPARKLE_PRIVATE_KEY`        | base64 EdDSA private key used to sign the DMG                     |

Generate the Sparkle key pair once with Sparkle's `generate_keys` tool; the public and private values must match or signing is silently skipped. The repository must be public, and Settings → Pages must point at the `gh-pages` branch after the first release.

## Credits, License, and Trademark

Tokamak is built on [OpenUsage](https://github.com/robinebers/openusage), created by Robin Ebers and maintained with Mert and David. The code is under the [MIT license](LICENSE), which keeps the original copyright notice.

"OpenUsage" and its logo are trademarks of Robin Ebers (see [TRADEMARK.md](TRADEMARK.md)). Per that policy, this fork uses its own name and icon and doesn't claim to be the official project.
