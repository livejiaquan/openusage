# Tokamak Panel Redesign — Design

Status: draft for owner review · 2026-10-16 · branch `feat/ssh-rebrand`

Reference mockups (open in a browser; numbers in them are simulated):

- `2026-10-16-tokamak-panel-redesign/mockup-panel-v7.html` — the agreed panel, with Default/Compact and Dark/Light switches.
- `2026-10-16-tokamak-panel-redesign/mockup-alert-states.html` — quiet vs. "runs out before reset" states, and collapse behavior.
- `2026-10-16-tokamak-panel-redesign/mockup-resets-options.html` — Rate Limit Resets options; **option A (list rows) was chosen**.

The mockups decide *what goes where and how big*. They imitate native materials and controls; the build uses the real macOS ones.

## Intent

Tokamak is a fork of OpenUsage that adds usage from other machines over SSH. The owner likes OpenUsage's simple single-page panel and wants to keep it, but make it feel more alive and more useful:

- See **how fast tokens are burning right now**, per provider and per device.
- Know **whether a limit will run out before it resets**, without doing arithmetic.
- Get **more detail on demand** (usage, trends, models, resets) without the information overload of apps like Syrtis.
- Look visibly **different from OpenUsage** (frosted glass, live motion), which the trademark policy also encourages.

## Goals

1. Keep the single-page panel: Claude and Codex are visible as soon as it opens, with no tabs.
2. Add a live **Activity card** at the top, a **speed chip** on each provider header, and **calm motion** on live meters.
3. Show a **run-out alert** only when a limit is projected to run out before its reset.
4. Enrich **On Demand** content with compact Usage, Last 14 Days, Top Models Today, and Rate Limit Resets layouts.
5. Use a **frosted-glass panel** look in the spirit of Syrtis.
6. Make everything new **switchable**, so turning it all off gives today's OpenUsage panel.

## Non-goals

- No tabs or multi-lens views like Syrtis (Models, Monthly, Hourly, and so on).
- No new providers, and no change to how quotas are fetched.
- No real-time speed for remote devices. They stay on the 5-minute SSH import, labeled with their age.
- No iCloud Sync work (it's off in Tokamak).

## Anti-goals (would make this a failure even if it "works")

- **Distracting motion.** If a user notices the sweep or the dot before the numbers, it's too strong. Motion must be slow and dim, and it stops when the panel is hidden.
- **Resource cost.** Anything that keeps a timer, file scanning, or animation running while the panel is closed is a failure. The app must stay a light menu-bar utility.
- **Clutter.** A row of copy that says the same thing twice is a failure. For example, "empty in 1h 9m" on the bar plus a sentence repeating it in the card.
- **Hard-to-use controls.** Every clickable element needs at least a 24 pt hit area and must look clickable.
- **Fake data presented as real.** Preview or estimated numbers must be labeled.

## Constraints

- **Type scale and spacing** come from `DensitySetting`, and both densities must look right:
  - Default: label 13, supporting 12, header 14, badge 11, meter 5 pt, bar row padding 10.
  - Compact: each one step down.
- **Panel width** stays 320 pt.
- **Swift 6 strict concurrency.** Keep files under about 500 LOC (AGENTS.md).
- **Keep merges with upstream OpenUsage small.**
  - Put new UI in new files.
  - In upstream files, prefer small, additive call-site changes over rewrites.
  - Internal type and module names keep upstream spelling. User-facing names come from `AppBrand`.
- **Respect both reduce-motion sources.** `\.reduceAnimations` covers the system "Reduce motion" and the app's own setting. Continuous motion must go through `VisibilityGatedTimeline` or an equivalent visibility gate.
- **Build environment.** The maintainer's Mac currently has no Xcode, so SwiftUI only compiles in GitHub Actions (`remote-usage-build.yml`, about 6–8 minutes). Each stage must be reviewable from CI artifacts.
- **Settings defaults.** AGENTS.md requires confirming metric defaults with the owner. The defaults below were agreed in the design sessions.

## The panel, top to bottom

### 1. Panel surface (frosted glass)

- **Translucent by default.** Tokamak defaults the panel to the translucent surface treatment: OpenUsage's existing behind-window vibrancy (`PopoverBackdropView`, `.translucent`).
- **The existing "Increase Transparency" toggle stays.** The test pinning its default to *off* moves to *on* for Tokamak.
- **Lighter cards.** Under translucency, cards must let noticeably more of the desktop through than OpenUsage's translucent cards do today. The design spike showed today's cards read as flat gray. Target the mockup's look, roughly a 7% white fill over the vibrancy in dark mode and a misty white in light mode, while keeping text contrast legible in both.
- **Fallback.** If system Reduce Transparency is on, the opaque look remains.

### 2. Usage From

Unchanged (existing scope menu). It shows only when there are remote devices or iCloud peers.

### 3. Activity card (new)

A card above the provider sections.

**Headline**
- The headline shows one of three values, picked from a menu attached to its unit label. The label looks like the "All Devices ⌄" scope control, with the text first and then the chevron.
  - **Speed** (default): tokens per minute across the shown providers, for example "1.30M tokens/min".
  - **Spent Today**: estimated cost today, for example "$458.33 spent today".
  - **Tokens Today**: tokens today, for example "2.2B tokens today".
- The choice persists.
- The headline number is 24 pt semibold with monospaced digits (Compact: 20 pt).
- A small green dot sits before the number. It breathes slowly (about 4.5 s per cycle, opacity about 0.45 to 1) and is static under reduce motion.

**Chart and breakdown**
- A 30-minute stacked-area chart, about 44 pt tall, sits under the headline, with the total drawn as a thin line.
- A caption row under the chart reads "Last 30 min", with a quiet two-option switch on the right: **Providers / Devices**.
  - The switch is a low-key gray pill, not the accent-blue native segmented control.
  - It only appears when at least one remote device exists.
- The legend lists each series with its color swatch, name, and rate.
  - **Providers mode**: Claude and Codex.
  - **Devices mode**:
    - This Mac (live) first.
    - Then each remote device, with its import age ("updated 2m ago") or "idle".
    - Devices with no recent activity show "—".

**Run-out alert**
- Eligible metrics: every **enabled** metric of an enabled provider in the current scope, **including ones behind a collapsed On Demand caret**. The point is to warn about limits you're not looking at. Disabled metrics and hidden providers never alert.
- Shown only when an eligible metric is projected to run out before its reset. In OpenUsage's terms, that is `MeterState.runningOut` with an ETA.
- It is one line inside the card, for example: "⚠ Claude Session runs out about 22m before it resets at this pace." The minutes come from `resetsAt − projected run-out time`.
- When several metrics qualify, show the one that runs out soonest.
- When none qualifies, show nothing.

**Collapse**
- A caret centered at the bottom of the card, using the same component and behavior as the provider cards' On Demand caret (chevron.down/up swap, no rotation).
- Collapsed, the card is one line: dot, headline number at 17 pt (Compact 15 pt), unit text without the chevron, and a sparkline about 110 × 22 pt on the right.
- The number must never truncate in either density. If space is short, the sparkline shrinks first.
- Collapsed state persists.

### 4. Provider headers

On the right of each Claude and Codex header: "● 982K/min" in supporting size, medium weight, secondary color, with monospaced digits.
- It hides while the header's hover-revealed copy button is showing, so the two never overlap.
- Other providers show nothing there.
- With multiple accounts per family, show the rate only on the account card that owns the default local logs. Others show nothing. This mirrors how local history is attributed today.

### 5. Metric rows (existing bounded rows)

**Pace copy and colors**
- Reuse OpenUsage's existing pace verdicts and copy: blue healthy, amber "~N% spare", red with flame and "Limit in …".
- Restyle only where the mockup differs: the status copy sits right-aligned on the label line.
- The run-out ETA copy stays OpenUsage's ("Limit in 1h 9m"); don't invent a second phrasing.

**Calm sweep**
- Applies only to the fill of meters whose window is "live". For v1, that means the **Session** meters of Claude and Codex.
- A soft highlight, about 45% of the fill width, peaks at about 16% white in dark mode and about 50% white in light mode.
- It eases across the fill, then rests: travel is about 62% of the cycle, the rest is a pause.
- Cycle length scales with the provider's current speed, clamped to 8–16 s (faster burn means a shorter cycle).
- It is invisible under reduce motion, when the panel is hidden, and when the provider's speed is zero.
- An optional faint breathing glow at the fill's leading edge uses the same visibility rules. It is off by default; see Settings.

### 6. On Demand content (behind the provider card's caret)

These are new or restyled metric rows. They live in the existing On Demand system: enable/disable, Always Visible vs. On Demand, and ordering in Customize, like any metric. Defaults are On Demand, enabled, in this order after the provider's existing On Demand limits (for example Opus Weekly).

1. **Rate Limit Resets** (restyle of the existing row; option A).
   - Header: "Rate Limit Resets" with "N available" right-aligned.
   - One row per reset, sorted by expiry: a numbered circle, "Expires Oct 19", a countdown ("in 3d", orange when within 3 days), and a **Use** button that starts the existing claim/confirm flow. **Use appears only where a claim service exists (Codex today).** Claude's resets are read-only, so its rows show no button.
   - Show at most 2 rows. The rest collapse into a "Show N More ⌄" row that expands inline; "Show Less ⌃" collapses it again.
   - With zero resets, keep the existing empty state.
2. **Usage**: a three-column row with Today, Yesterday, and 30 Days. Each column has a small caption, then the cost in label size and semibold, then the tokens in badge size. **This is a visual grouping, not a new metric.** The existing `today`, `yesterday`, and `last30` metrics keep their IDs, enablement, pins, and order. When two or more of them are enabled and adjacent in the same section, the dashboard renders them as one row with one column per enabled metric; otherwise each renders as it does today. No settings migration.
3. **Last 14 Days**: a restyle of the existing **Usage Trend** metric (same ID, same providers: Antigravity, Claude, Codex, Cursor, Grok, OpenCode). Daily bars, about 26 pt tall. Today is drawn in the provider color, other days in a neutral track color. "avg $X/day" is right-aligned on the label line. No second chart is added alongside it.
4. **Top Models Today**: a **new metric** for every provider that already records per-model daily usage. It lists the top 3 models by today's cost. Each shows the name, then "share% · $cost" right-aligned, then a thin 3 pt share bar in the provider color. Hidden when fewer than 2 models were used today. Defaults (confirmed by the owner on 2026-10-16): enabled, On Demand, not pinnable to the menu bar, ordered after Last 14 Days.

### 7. Settings → "Live Activity" (new section)

| Toggle | Default | Effect |
|---|---|---|
| Activity Card | On | Shows or hides the Activity card |
| Speed on Provider Headers | On | Shows or hides header chips |
| Animated Meters | On | Calm sweep on live meters (the edge glow is a sub-option, off) |
| Device Breakdown | On | Providers/Devices switch in the card (auto-hidden without remote devices) |

With all four off, the dashboard matches OpenUsage's (aside from glass and the restyled On Demand rows).

## Data

**Live speed (this Mac)**
- A new lightweight "live tail" source per provider family (Claude, Codex) produces tokens per minute and a 30-minute history of about 60 buckets.
- It uses the per-event timestamps and token counts the existing log parsers already produce.
- It must not rescan whole histories. It watches only recently modified session files, using file-system events on the log roots while the panel is visible, and parses only appended bytes.
- When the panel is hidden it stops: no watchers, no timers.
- On open, it seeds the 30-minute history from the last 30 minutes of events in recently modified files.
- Rate is tokens in the trailing window divided by window minutes. A 5-minute trailing window is the builder's call to tune.
- Dedup must match the history scanners: Claude by message/request ID, Codex by the replay rules. Live and daily numbers must not disagree in a visible way.

**Remote devices**
- The SSH exporter already returns per-event timestamps.
- At each import, compute and keep that device's last-30-minutes buckets and its trailing rate, labeled with the import time.
- These are in memory only. Persisted remote data stays daily summaries only, as today.

**Usage From scope applies to every live surface.**
- All Devices: the headline and header chips show this Mac's live rate plus remote imported rates; Devices mode lists each machine.
- This Mac: local live data only.
- A single remote device: the headline, chart, and header chips show that device's imported rate and buckets, labeled "updated Xm ago"; the Devices switch is hidden.
- No part of the panel describes a different set of machines than the scope says.

**Remote rates between imports**
- The last imported rate and buckets stay frozen, labeled with their import age.
- After 15 minutes without a successful import, or after an import fails, the device shows "—" with "last import Xm ago" instead of a number. The chart shows a gap, never a zero.
- After an app restart, remote rates are unavailable until each device's first import, because they aren't persisted.

**Everything else reuses existing data:**
- The pace engine (`WidgetData.meterState`, `Pace`) feeds the alert and the bar copy.
- Daily history feeds Usage and Last 14 Days.
- Per-model daily usage feeds Top Models Today.
- `expiriesAt` and the existing claim flow feed Rate Limit Resets.
- Headline "Spent/Tokens Today" sums today's entries across the shown providers in the current Usage From scope.

## Motion and update cadence

| Element | Cadence | Gate |
|---|---|---|
| Headline, chips, chart | Recompute every 2 s while visible | Panel visible |
| Calm sweep | Display-linked while visible | Visible and motion allowed |
| Breathing dot | 4.5 s cycle | Visible and motion allowed |
| Remote buckets | Each SSH import (5 min) | — |

Numbers animate with numeric-text content transitions. Collapsing uses the app's existing spring (`Motion.spring`).

## Accessibility

- Every interactive element has at least a 24 pt hit target and a VoiceOver label: headline menu, carets, breakdown switch, Use, and Show More.
- The breakdown switch exposes the selected state.
- The live chips combine into one element ("Claude, 982 thousand tokens per minute").
- All motion is off under reduce motion. Glass falls back to opaque under Reduce Transparency.

## Verification

- **Each stage ends with a CI build and real screenshots** of: dashboard expanded and collapsed, Compact, Light, the run-out alert state, On Demand open, and many resets. The builder checks hit targets, truncation, and overlaps before showing the owner.
- **Unit tests** for:
  - live-rate math and bucketing, including dedup parity with the daily scanners;
  - the "minutes before reset" calculation;
  - the resets overflow rule (2 visible plus "Show N More");
  - remote bucket computation from exporter events.
- **Performance check**: with the panel closed, the app shows no recurring wakeups from the new code. Verify with logs or Activity Monitor.

## Calls made during design (owner can override)

- The run-out wording reuses OpenUsage's "Limit in …" and pace copy instead of the mockup's "empty in ~1h 9m".
- The Usage row is a rendering of the existing three metrics, so there's no migration and pins keep working.
- Last 14 Days restyles the existing Usage Trend metric instead of adding a second chart.
- Rate Limit Resets shows **Use** only where a claim service exists (Codex).
- The run-out alert considers enabled metrics even when they sit behind a collapsed caret.
- The Usage From scope drives every live surface. Remote rates freeze with an age label and switch to "—" after 15 minutes without a successful import.
- The edge glow is optional and off by default. The sweep alone carries the "alive" feel.
- Multi-account families show the speed chip on only one card.

## Left to the builder

- The exact live-tail mechanism: FSEvents vs. DispatchSource, the bucket math, and the trailing window length.
- Material tuning to hit the mockup's translucency with legible text.
- File and type structure inside the constraints above.
- How the restyled rows plug into `WidgetRowView` / `WidgetDescriptor`, as long as Customize keeps working for them.
- Staging order. Suggested: glass and Activity card (with real speed) → header chips and sweep → alert → On Demand rows → Settings toggles.
