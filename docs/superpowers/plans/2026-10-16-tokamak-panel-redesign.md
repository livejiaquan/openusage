# Tokamak Panel Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved Tokamak panel. It adds frosted glass, a live Activity card, provider speed chips, calm meter motion, a run-out alert, restyled On Demand rows, and a "Live Activity" settings section, on top of OpenUsage's single-page dashboard.

**Architecture:**
- A new `Sources/OpenUsage/Live/` module owns live speed:
  - per-family log tails that read only appended bytes;
  - 30-second buckets;
  - a visibility-gated `@MainActor` store;
  - remote samples built at SSH import.
- UI lives in new view files.
- Upstream files only get small, additive call-site changes, to keep merges with OpenUsage cheap.
- Existing data is reused for everything except live speed: pace engine, daily history, per-model usage, and reset expiries.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI plus AppKit, XCTest, CoreServices FSEvents, SwiftPM.

**Spec:** `docs/superpowers/specs/2026-10-16-tokamak-panel-redesign-design.md`. Mockups are in `docs/superpowers/specs/2026-10-16-tokamak-panel-redesign/`.

## Global Constraints

- **Type scale and spacing.** Use `DensitySetting` values only.
  - Default: label 13, supporting 12, header 14, badge 11, meter 5 pt.
  - Compact: one step down.
- **Panel width** is 320 pt.
- **Hit targets.** Every interactive element is at least 24 pt tall and has a VoiceOver label.
- **Continuous motion** goes through `VisibilityGatedTimeline` or another `\.popoverIsVisible` plus `\.reduceAnimations` gate. When the panel is hidden, nothing new may tick, watch, or poll.
- **Copy.** User-facing names come from `AppBrand`. Run-out copy reuses OpenUsage's pace wording ("Limit in …", "~N% spare"). Hard-coded titles use Title Case (AGENTS.md).
- **Files.** Keep each file under about 500 LOC. Add no new dependencies.
- **Upstream files** (anything not under `Live/` or a new view file) get additive edits only. Don't reformat or reorder.
- **Testing a task.**
  - With Xcode installed: `swift test --filter <TestClass>`.
  - Without Xcode (the current state of this Mac): push `feat/ssh-rebrand` to `fork` and read the `Build SSH remote usage app` run.
  - **The owner must approve the first push of `feat/ssh-rebrand`**, because it publishes the Tokamak rebrand.
- **Starting point for views.** The throwaway spike `feat/ssh-design-spike:Sources/OpenUsage/Views/ActivitySpike.swift` may be copied for view pieces: `StackedActivityChart`, `QuietSegmentedControl`, `LiveDot`, `CalmMeterSweep`. Do not copy its `LiveActivityPreview` fake data.

## Review Focus

1. **A session file is rewritten or truncated**, so its size is smaller than the stored offset. The tail must re-read from 0 without double counting or crashing. Test: `LiveLogTailTests.testTruncatedFileRestartsWithoutDoubleCounting`.
2. **A partial last line.** The CLI writes a JSONL line in two chunks. The tail must not parse half a line or skip it. Test: `LiveLogTailTests.testPartialLineIsReadOnceComplete`.
3. **The clock moves backwards or there is a long sleep gap** (laptop wakes after hours). Buckets must roll forward cleanly with no negative or stale rates. Test: `LiveRateBucketsTests.testLongGapClearsBuckets`.
4. **Usage From is set to a device that was just removed.** The view model falls back to "all" (matching `WidgetDataStore`'s existing reset) instead of showing an empty card. Test: `LiveActivityComposerTests.testUnknownScopeFallsBackToAll`.
5. **A huge headline number.** Values like "$12,345.67" or "12.3B" in the collapsed 17 pt row must not truncate; the sparkline shrinks first. Covered by the Task 6 screenshot checklist (Compact plus collapsed plus a long value), with a debug override value.

---

### Task 1: Frosted Glass by Default

**Files:**
- Modify: `Sources/OpenUsage/Stores/PopoverTransparencyStore.swift:54` (`init` default)
- Modify: `Sources/OpenUsage/Support/Theme.swift` (`CardSurfaceModifier`, `.translucent` branch)
- Test: `Tests/OpenUsageTests/PopoverTransparencyStoreTests.swift:27`

**Interfaces:**
- Produces: `PopoverTransparencyStore.increaseTransparency` defaults to `true` when the key is absent.

- [ ] **Step 1:** Change the test at line 27 to `XCTAssertTrue(store.increaseTransparency)` for a fresh defaults suite. Keep the persistence round-trip assertions.
- [ ] **Step 2:** Run the test. Expected: FAIL (the default is still false).
- [ ] **Step 3:** In `init`, use `defaults.object(forKey: Self.key) as? Bool ?? true`. `resetToDefaults` (line 96) must set `true`, which keeps the "reset equals fresh install" rule.
- [ ] **Step 4:** In the `.translucent` card branch, replace `Theme.traySurface.opacity(0.55)` with a lighter fill.
  - Dark mode: `Color.white.opacity(0.07)`.
  - Light mode: `Color.white.opacity(0.55)`.
  - Choose with `@Environment(\.colorScheme)`.
  - Keep the `Theme.cardFill` overlay.
  - If system Reduce Transparency is on, the store already forces opaque. Don't add a second check.
- [ ] **Step 5:** Run `PopoverTransparencyStoreTests`. Expected: PASS.
- [ ] **Step 6:** Commit: `feat: default Tokamak to the frosted translucent panel`.

### Task 2: Live Rate Buckets

**Files:**
- Create: `Sources/OpenUsage/Live/LiveRateBuckets.swift`
- Test: `Tests/OpenUsageTests/LiveRateBucketsTests.swift`

**Interfaces:**
- Produces:
```swift
struct LiveRateBuckets: Equatable, Sendable {
    static let bucketDuration: TimeInterval = 30
    static let bucketCount = 60                 // 30 minutes
    static let trailingWindow: TimeInterval = 300
    init(now: Date)
    mutating func add(tokens: Int, at timestamp: Date, now: Date)  // drops events outside [now-30min, now+60s]
    mutating func advance(to now: Date)          // rolls the window; a gap >= 30 min clears everything
    func ratePerMinute(now: Date) -> Double      // tokens in the trailing 300 s / 5
    func history(now: Date) -> [Double]          // 60 values, tokens/min per bucket, oldest first
    static func merged(_ parts: [LiveRateBuckets], now: Date) -> LiveRateBuckets
}
```

- [ ] **Step 1: Write the failing tests.**
  - `testRateCountsOnlyTrailingFiveMinutes`: add 1,000 tokens at now-60 s and 9,000 at now-10 min. Expect `ratePerMinute == 200`.
  - `testHistoryHasSixtyBucketsInTokensPerMinute`: add 300 tokens at now-15 s. Expect `history.count == 60` and `history.last == 600`.
  - `testLongGapClearsBuckets`: add tokens, then `advance(to: now + 2h)`. Expect all zeros and rate 0.
  - `testEventsBeyondWindowAreIgnored`: tokens at now-31 min and now+5 min don't change anything.
  - `testMergedSumsBucketwise`.
- [ ] **Step 2:** Run `swift test --filter LiveRateBucketsTests`. Expected: FAIL (the type is missing).
- [ ] **Step 3:** Implement it as a ring of 60 `Int`, aligned to 30 s boundaries (`floor(t / 30)`).
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(live): add 30-minute token rate buckets`.

### Task 3: Live Log Tails (This Mac)

**Files:**
- Create: `Sources/OpenUsage/Live/LiveLogTail.swift`
- Modify: `Sources/OpenUsage/Providers/Claude/ClaudeLogUsageScanner.swift` (add a method)
- Modify: `Sources/OpenUsage/Providers/Codex/CodexLogUsageScanner.swift` (add a method)
- Test: `Tests/OpenUsageTests/LiveLogTailTests.swift`

**Interfaces:**
- Consumes: `LiveRateBuckets` (Task 2); `ClaudeLogUsageScanner.parseLine(_:)`; `CodexLogFileParser` (stateful, `mutating parse(_ data: Data)`).
- Produces:
```swift
enum LiveFamily: String, Sendable, CaseIterable { case claude, codex }
actor LiveLogTail {
    init(family: LiveFamily, candidateFiles: @escaping @Sendable (_ modifiedSince: Date) -> [URL])
    func poll(now: Date) -> LiveRateBuckets
    func reset()
}
// Scanner additions (non-private, reuse the scanners' existing root and file discovery):
extension ClaudeLogUsageScanner { func liveCandidateFiles(modifiedSince: Date) -> [URL] }
extension CodexLogUsageScanner { func liveCandidateFiles(modifiedSince: Date) -> [URL] }
```

- [ ] **Step 1: Write the failing tests**, using temp directories with real JSONL lines. Build them with `CodexLogFixture` and the existing Claude fixtures in `ClaudeLogUsageScannerTests`.
  - `testAppendedClaudeLinesRaiseRate`
  - `testDuplicateClaudeMessageCountsOnce`: same `message.id` and `requestId` in two files counts once.
  - `testCodexTokenCountsUseParserDeltas`: two cumulative `token_count` lines add only the delta, matching `CodexLogUsageScanner.parseFile`.
  - `testPartialLineIsReadOnceComplete`
  - `testTruncatedFileRestartsWithoutDoubleCounting`
  - `testFilesOlderThanThirtyMinutesAreNotRead`: the candidate closure gets `now - 30min`.
- [ ] **Step 2:** Run `swift test --filter LiveLogTailTests`. Expected: FAIL.
- [ ] **Step 3: Implement the tail.**
  - Keep a per-file cursor: `offset` plus, for Codex, a retained `CodexLogFileParser`.
  - On first sight, parse the whole file and keep events with `timestamp >= now - 30 min`.
  - After that, read only bytes after `offset`, up to the last `\n`.
  - If `size < offset`, drop the cursor and re-read the file.
  - Count tokens the same way the daily aggregators do. Claude: `tokens.promptTokens + tokens.output`. Codex: `event.total`. Confirm against `ClaudeLogUsageScanner.aggregate` and `CodexLogUsageScanner.aggregate`; if they differ, follow them.
  - Claude dedup: a `[String: Date]` keyed by `"messageID|requestID"`, pruned past the 30-minute window. Entries with `messageID == nil` always count.
  - The scanner methods filter their existing discovered files by `mtime >= modifiedSince`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(live): tail recent Claude and Codex session logs`.

### Task 4: Remote Live Samples

**Files:**
- Create: `Sources/OpenUsage/Live/RemoteLiveSample.swift`
- Modify: `Sources/OpenUsage/Services/SSHRemoteUsageClient.swift` (`fetch` return type)
- Modify: `Sources/OpenUsage/Stores/RemoteUsageDeviceStore.swift` (keep samples and failures)
- Test: `Tests/OpenUsageTests/RemoteLiveSampleTests.swift`; update `RemoteUsageDeviceTests.testHungRemoteFetchFailsWithTimeoutInsteadOfBlocking` for the new return type.

**Interfaces:**
- Consumes: `LiveRateBuckets`; `RemoteUsageEvents` (already decoded in `fetch`).
- Produces:
```swift
struct RemoteLiveSample: Equatable, Sendable {
    static let staleAfter: TimeInterval = 15 * 60
    let deviceID: String
    let importedAt: Date
    let buckets: LiveRateBuckets          // anchored at importedAt
    var lastFailureAt: Date?
    func isAvailable(now: Date) -> Bool    // false if now - importedAt > staleAfter or a failure is newer than importedAt
    static func from(events: RemoteUsageEvents, deviceID: String, importedAt: Date) -> RemoteLiveSample
}
struct RemoteFetchResult: Sendable { let document: UsageHistoryDocument; let liveSample: RemoteLiveSample }
// SSHRemoteUsageClient.fetch(_:) -> RemoteFetchResult
// RemoteUsageDeviceStore: private(set) var liveSamples: [String: RemoteLiveSample]  (memory only)
```

- [ ] **Step 1: Write the failing tests.**
  - `testSampleBucketsRecentEvents`: events at importedAt-2 min give a rate above 0. Events at importedAt-40 min are ignored.
  - `testSampleGoesStaleAfterFifteenMinutes`
  - `testFailureAfterImportMakesSampleUnavailable`
  - `testSamplesAreNotPersisted`: a new `RemoteUsageDeviceStore` on the same defaults has empty `liveSamples`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement it.
  - `fetch` builds the sample from the decoded events before pricing.
  - The store saves it on success, and sets `lastFailureAt` on the catch path.
  - Removing a device removes its sample.
- [ ] **Step 4:** Run `RemoteLiveSampleTests` and `RemoteUsageDeviceTests`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(live): keep per-device live samples from SSH imports`.

### Task 5: Live Activity Store and Composer

**Files:**
- Create: `Sources/OpenUsage/Live/LogDirectoryWatcher.swift`
- Create: `Sources/OpenUsage/Live/LiveActivityStore.swift`
- Create: `Sources/OpenUsage/Live/LiveActivityComposer.swift`
- Modify: `Sources/OpenUsage/App/AppContainer.swift` (create the store)
- Modify: `Sources/OpenUsage/App/StatusItemController.swift:317` and `:351` (visibility hooks)
- Test: `Tests/OpenUsageTests/LiveActivityComposerTests.swift`

**Interfaces:**
- Consumes: `LiveLogTail`, `RemoteLiveSample`, `RemoteUsageDeviceStore.devices` and `liveSamples`, `WidgetDataStore.historyScopeID`.
- Produces:
```swift
final class LogDirectoryWatcher: @unchecked Sendable {   // FSEvents, latency 1 s, file-level events
    init(paths: [URL], onChange: @escaping @Sendable () -> Void)
    func start(); func stop()
}
@MainActor @Observable final class LiveActivityStore {
    init(tails: [LiveFamily: LiveLogTail], watchedRoots: [URL], remoteDevices: RemoteUsageDeviceStore, now: @escaping () -> Date = Date.init)
    private(set) var local: [LiveFamily: LiveRateBuckets]
    func setVisible(_ visible: Bool)   // true: start watcher + 2 s poll Task; false: cancel both
    func view(scope: String) -> LiveActivityView
}
struct LiveSeries: Equatable, Identifiable { let id: String; let name: String; let note: String?; let history: [Double]?; let rate: Double? }
struct LiveActivityView: Equatable {
    var totalRate: Double?                 // nil when nothing in scope is available
    var providerRates: [LiveFamily: Double]
    var providerSeries: [LiveSeries]       // Claude, Codex
    var deviceSeries: [LiveSeries]         // This Mac first, then remote devices in device order
    var showsDeviceBreakdown: Bool         // scope == "all" && at least one remote device
}
enum LiveActivityComposer {
    static func compose(scope: String, local: [LiveFamily: LiveRateBuckets], remote: [RemoteLiveSample],
                        devices: [RemoteUsageDevice], now: Date) -> LiveActivityView
    static func chipFamily(forProviderID id: String, providerIDs: [String]) -> LiveFamily?
}
```
- `chipFamily`: the provider's family if it is `claude`/`codex` and either the ID equals the bare family, or no bare-family ID exists and this is the first ID of that family in `providerIDs`. Otherwise nil.

- [ ] **Step 1: Write the failing tests** for the pure composer.
  - `testAllScopeSumsLocalAndAvailableRemote`
  - `testThisMacScopeIgnoresRemote`
  - `testSingleDeviceScopeUsesOnlyThatDevice`: `providerRates` are empty and `showsDeviceBreakdown == false`.
  - `testUnavailableRemoteShowsDashNotZero`: the series `rate == nil` and the note says "last import Xm ago".
  - `testUnknownScopeFallsBackToAll`
  - `testChipFamilyPrefersBareID`
  - `testChipFamilyFallsBackToFirstAccountCard`
- [ ] **Step 2:** Run `swift test --filter LiveActivityComposerTests`. Expected: FAIL.
- [ ] **Step 3:** Implement the composer, then the store and the watcher.
  - The store polls every 2 s only while visible.
  - A watcher event triggers an immediate poll.
  - `setVisible(false)` cancels the Task and stops FSEvents.
  - In `AppContainer`, build the tails from scanner instances' `liveCandidateFiles`.
  - In `StatusItemController`, call `container.liveActivity.setVisible(true/false)` next to the existing `setPopoverShown` calls.
- [ ] **Step 4:** Run the composer tests plus the full suite. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(live): visibility-gated live activity store`.

### Task 6: Activity Card

**Files:**
- Create: `Sources/OpenUsage/Views/ActivityCard.swift`
- Create: `Sources/OpenUsage/Views/ActivityChartViews.swift` (`StackedActivityChart`, `QuietSegmentedControl`, `LiveDot`)
- Create: `Sources/OpenUsage/Stores/LiveActivitySettings.swift`
- Modify: `Sources/OpenUsage/Views/DashboardContentView.swift` (insert the card above Total Spend)

**Interfaces:**
- Consumes: `LiveActivityStore.view(scope:)`, `WidgetDataStore.historyScopeID`, `WidgetDataStore.snapshots` (today's totals).
- Produces:
```swift
enum LiveActivitySettings {                // @AppStorage keys and defaults
    static let cardKey = "tokamak.live.card"            // default true
    static let headerSpeedKey = "tokamak.live.headerSpeed" // default true
    static let animatedMetersKey = "tokamak.live.animatedMeters" // default true
    static let edgeGlowKey = "tokamak.live.edgeGlow"    // default false
    static let deviceBreakdownKey = "tokamak.live.deviceBreakdown" // default true
    static let collapsedKey = "tokamak.activity.collapsed"   // default false
    static let headlineKey = "tokamak.activity.headline"     // ActivityHeadline.rawValue, default "speed"
}
enum ActivityHeadline: String, CaseIterable { case speed, spentToday, tokensToday }  // titles "Speed"/"Spent Today"/"Tokens Today"; units "tokens/min"/"spent today"/"tokens today"
```

- [ ] **Step 1:** Build the view to the spec's section 3 (`mockup-panel-v7.html`).
  - Headline: 24 / 20 pt, `.monospacedDigit()`, and `.contentTransition(.numericText())`.
  - Unit menu: `.menuStyle(.button)` and `.buttonStyle(.plain)`, so the chevron comes after the text.
  - Chart: 44 pt tall.
  - Caption row: "Last 30 min", with `QuietSegmentedControl` shown when `view.showsDeviceBreakdown` and the deviceBreakdown setting is on.
  - Legend from `providerSeries` or `deviceSeries`.
  - Caret: same look as the provider caret, 24 pt.
  - Collapsed: 17 / 15 pt number with a 110 × 22 sparkline that yields width first (`layoutPriority` on the number).
  - Today's totals sum `snapshot.usageHistory?.series.daily` entries where `date == DailyUsageAccumulator.dayKey(from: now)`.
  - Hidden entirely when `cardKey` is false.
- [ ] **Step 2: Verify.** Build in CI, install the artifact, and screenshot:
  - expanded and collapsed;
  - Compact;
  - Light;
  - Devices mode;
  - a long value. Add a `#if DEBUG` launch argument `-TokamakDebugHeadline 12345.67` that overrides the spent value.

  Check that nothing truncates or overlaps and that every hit target is at least 24 pt. Fix what you find before showing the owner.
- [ ] **Step 3:** Commit: `feat: live Activity card`.

### Task 7: Header Speed Chips and Calm Meter Sweep

**Files:**
- Create: `Sources/OpenUsage/Views/CalmMeterSweep.swift`
- Modify: `Sources/OpenUsage/Views/ProviderSectionHeader.swift` (optional `liveRate: Double?`; hidden while the copy button is revealed)
- Modify: `Sources/OpenUsage/Views/WidgetGroupedListView.swift:50` (pass the rate from `chipFamily`)
- Modify: `Sources/OpenUsage/Views/WidgetRowView.swift` (meter fill overlay)
- Test: `Tests/OpenUsageTests/CalmMeterSweepTests.swift`

**Interfaces:**
- Consumes: `LiveActivityComposer.chipFamily`, `LiveActivityView.providerRates`, `LiveActivitySettings.headerSpeedKey`, `animatedMetersKey`, `edgeGlowKey`.
- Produces:
```swift
struct CalmMeterSweep: View {
    static let peakRate: Double = 1_500_000   // tokens/min mapped to the fastest cycle
    static func period(forRate rate: Double) -> TimeInterval?   // nil when rate <= 0; else 16 - 8 * min(rate / peakRate, 1)
    init(period: TimeInterval, showsEdgeGlow: Bool)
}
```
- Sweep visuals:
  - Highlight width is 45% of the fill (minimum 24 pt). Peak opacity is 0.16 in dark mode and 0.5 in light mode.
  - Travel takes the first 62% of the cycle with cosine easing, then it rests.
  - It applies only to meters whose `data.title` starts with "Session" in the Claude and Codex families.
  - The edge glow uses a 4.5 s cycle with opacity 0.15–0.45.

- No change is needed for the spec's "status copy right-aligned on the label line". `WidgetRowView.boundedLabelRow` already does that; keep its wording.

- [ ] **Step 1: Write the failing tests:** `testNoSweepWithoutActivity` (rate 0 gives nil), `testPeriodClampsBetweenEightAndSixteen` (inputs 1, 750k, 1.5M, 9M map to about 16, 12, 8, 8).
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement the sweep, the chip ("● 982K/min", supporting size, medium weight, secondary color, monospaced digits, VoiceOver "Claude, 982 thousand tokens per minute"), and the wiring.
- [ ] **Step 4:** Run the tests. Expected: PASS. In the CI screenshots, the chip must not collide with the copy button on hover.
- [ ] **Step 5:** Commit: `feat: provider speed chips and calm session sweep`.

### Task 8: Run-Out Alert

**Files:**
- Modify: `Sources/OpenUsage/Models/WidgetData.swift` (add a method next to `meterState`; it needs the private `paceContext`)
- Create: `Sources/OpenUsage/Live/RunOutAlert.swift`
- Modify: `Sources/OpenUsage/Stores/WidgetDataStore.swift` (add `runOutAlert(now:)`)
- Modify: `Sources/OpenUsage/Views/ActivityCard.swift` (alert line)
- Test: `Tests/OpenUsageTests/RunOutAlertTests.swift`

**Interfaces:**
- Produces:
```swift
extension WidgetData {
    /// Seconds between the projected run-out and the reset; nil unless meterState(now:) is .runningOut with an ETA.
    func runOutLeadTime(now: Date) -> TimeInterval?
    func secondsToRunOut(now: Date) -> TimeInterval?
}
struct RunOutAlert: Equatable {
    let providerName: String; let metricTitle: String; let leadTime: TimeInterval
    static func soonest(_ candidates: [(providerName: String, data: WidgetData)], now: Date) -> RunOutAlert?  // smallest secondsToRunOut wins
    var message: String   // "<metricTitle> runs out about <lead> before it resets at this pace." with `lead` from the app's existing duration formatter (e.g. "22m", "1h 5m")
}
// WidgetDataStore.runOutAlert(now: Date = Date()) -> RunOutAlert?
//   candidates = orderedDescriptors() filtered by isProviderEnabled, bounded data only (same filter as evaluateNotifications),
//   including On Demand rows; providerName = registry display name.
```

- [ ] **Step 1: Write the failing tests.**
  - `testHealthyMeterHasNoAlert`
  - `testRunningOutMeterReportsLeadTime`: limit 100, used 60, period 5 h, 1 h elapsed. Expect the lead equals `resetsAt - (now + secondsToRunOut)`, within 1 s.
  - `testSoonestRunOutWins`
  - `testDisabledProviderNeverAlerts`
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement it. The card shows the line ("⚠" plus the message, the provider name in semibold, the alert colors from the mockup) only when `runOutAlert` is non-nil and the card is expanded.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: run-out alert in the Activity card`.

### Task 9: Rate Limit Resets List Rows

**Files:**
- Create: `Sources/OpenUsage/Views/ResetListRows.swift`
- Modify: `Sources/OpenUsage/Views/WidgetRowView.swift` (route `showsResetExpiries` rows and Claude's rate-limit-resets row to the new view in the dashboard)
- Test: `Tests/OpenUsageTests/ResetListLayoutTests.swift`

**Interfaces:**
- Consumes: `WidgetData.expiriesAt`, `\.codexResetClaims` (environment), the existing claim/confirm flow in `RateLimitResetsDetail.swift`.
- Produces:
```swift
enum ResetListLayout {
    static let collapsedLimit = 2
    static let soonThreshold: TimeInterval = 3 * 86_400
    static func visible(total: Int, expanded: Bool) -> (shown: Int, hidden: Int)
    static func isSoon(_ expiry: Date, now: Date) -> Bool
}
```
- A row is: a numbered 18 pt circle, "Expires Oct 19" (`MMM d`), a countdown ("in 3d"), and **Use**.
- **Use** appears only when `codexResetClaims[providerID] != nil`, and it opens the existing confirm flow.
- The overflow row reads "Show N More" / "Show Less" with a chevron.
- With zero resets, keep the existing empty state.

- [ ] **Step 1: Write the failing tests:** `testTwoOrFewerShowAll`, `testFiveCollapsedShowsTwoHidesThree`, `testExpandedShowsAll`, `testSoonIsWithinThreeDays`.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement the view and the routing.
- [ ] **Step 4:** Run the tests plus the CI screenshots (one, two, and five resets; Claude without Use).
- [ ] **Step 5:** Commit: `feat: list-style Rate Limit Resets with overflow`.

### Task 10: Usage Row, Last 14 Days, Top Models Today

**Files:**
- Create: `Sources/OpenUsage/Views/UsageStatRow.swift`
- Create: `Sources/OpenUsage/Views/TopModelsRow.swift`
- Create: `Sources/OpenUsage/Models/UsageStatGrouping.swift`
- Create: `Sources/OpenUsage/Models/TopModels.swift`
- Modify: `Sources/OpenUsage/Views/WidgetGroupedListView.swift` (render grouped rows)
- Modify: `Sources/OpenUsage/Views/UsageSparkline.swift` (14 daily bars style)
- Modify: `Sources/OpenUsage/Models/WidgetDescriptor+Factories.swift` (add `topModelsToday(provider:)`)
- Modify: the Antigravity, Claude, Codex, Cursor, Grok, and OpenCode provider descriptor lists, placing the new descriptor after `.usageTrend`
- Modify: `Sources/OpenUsage/Stores/DefaultLayout.swift` (metric IDs, expanded IDs, never pinned)
- Test: `Tests/OpenUsageTests/UsageStatGroupingTests.swift`, `Tests/OpenUsageTests/TopModelsTests.swift`

**Interfaces:**
- Produces:
```swift
enum UsageStatGrouping {
    enum Item: Equatable { case single(String); case usageStats([String]) }   // descriptor IDs
    static func group(_ orderedIDs: [String]) -> [Item]   // merges runs of ≥2 adjacent IDs ending in .today/.yesterday/.last30
}
struct TopModelEntry: Equatable { let model: String; let cost: Double; let share: Double }
enum TopModels {
    static func today(from history: ProviderUsageHistory, dayKey: String, limit: Int = 3) -> [TopModelEntry]  // [] when fewer than 2 models
}
// WidgetDescriptor.topModelsToday(provider:) — id "\(provider.id).topModels", title "Top Models Today", not pinnable
```
- Defaults (confirmed by the owner): enabled, On Demand, not pinnable, ordered right after `.trend`.
- Last 14 Days reuses the `.trend` descriptor. Show the last 14 daily entries as bars, today in the provider color, and "avg $X/day" on the label line.

- [ ] **Step 1: Write the failing tests.**
  - `testThreeAdjacentStatsMerge`
  - `testSingleStatStaysSingle`
  - `testNonAdjacentStatsDoNotMerge`
  - `testTopThreeByCostWithShares`
  - `testOneModelHidesRow`
  - `testTopModelsIsNotPinnableAndOnDemandByDefault`, which checks `DefaultLayout.expandedMetricIDs` contains it and `pinnedMetricIDs` doesn't.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement it. Customize keeps listing today, yesterday, and last30 separately. Grouping is dashboard-only.
- [ ] **Step 4:** Run the tests and the full suite (existing layout and Customize tests must stay green). Then take CI screenshots of a provider's On Demand open.
- [ ] **Step 5:** Commit: `feat: grouped Usage row, 14-day bars, Top Models Today`.

### Task 11: Live Activity Settings Section and Docs

**Files:**
- Create: `Sources/OpenUsage/Views/LiveActivitySettingsSection.swift`
- Modify: `Sources/OpenUsage/Views/SettingsScreen.swift` (insert the section after Remote Devices)
- Modify: `Sources/OpenUsage/App/AppContainer.swift` (the reset-all key list must include the `LiveActivitySettings` keys)
- Modify: `docs/settings.md`, `docs/dashboard.md`, `docs/remote-devices.md`, `docs/privacy.md` (live tail reads only local logs; nothing leaves the Mac)
- Test: `Tests/OpenUsageTests/LiveActivitySettingsTests.swift`

**Interfaces:**
- Consumes: `LiveActivitySettings` keys (Task 6).
- The toggles:

  | Row title | Key | Default | Note |
  |---|---|---|---|
  | Activity Card | `cardKey` | true | |
  | Speed on Provider Headers | `headerSpeedKey` | true | |
  | Animated Meters | `animatedMetersKey` | true | |
  | Edge Glow | `edgeGlowKey` | false | Indented, disabled when Animated Meters is off |
  | Device Breakdown | `deviceBreakdownKey` | true | |

- [ ] **Step 1: Write the failing test.** `testResetAllRestoresLiveDefaults`: set every key to its opposite, call the existing reset path, and assert the defaults.
- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3:** Implement the section in the existing settings row style (`settingsSwitchStyle`). Update the docs: plain, short, no visual design details (AGENTS.md).
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: Live Activity settings`.

### Task 12: Whole-Panel Verification

**Files:** none (verification only; fixes go back to the owning task's files)

- [ ] **Step 1:** Run the full suite (`swift test` or CI) and `python3 -m unittest discover -s Tests -p remote_usage_export_tests.py`. Expected: all green.
- [ ] **Step 2: Screenshot matrix.** Install the CI build and capture:
  - Default and Compact × Dark and Light;
  - Activity expanded and collapsed;
  - the alert state (use a debug override or a real near-limit session);
  - Devices mode;
  - On Demand open with five resets;
  - all Live Activity toggles off.

  The all-off state should match OpenUsage's look except for glass and On Demand rows.
- [ ] **Step 3: Performance check.** Close the panel for 2 minutes. Activity Monitor's "Idle Wake Ups" for Tokamak must not rise above the baseline build from before Task 2. No FSEvents stream should remain open: confirm with a `#if DEBUG` log line on stop.
- [ ] **Step 4:** Commit any fixes and record the matrix results in the PR description (AGENTS.md structure, with screenshots).
