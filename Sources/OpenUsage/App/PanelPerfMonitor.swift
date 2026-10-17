import AppKit
import QuartzCore

/// Measures how smooth the panel feels while it is open, so "it feels laggy" can be traced to a cause.
/// A display link on the panel's screen notes every frame that arrives late (the main thread was busy),
/// and logs: how long the panel took to appear, each stall of 100 ms or more (with its time since
/// opening, to line up with other log lines), and a one-line summary on close. Runs only while the panel
/// is open; the display link callback itself is a few arithmetic operations.
@MainActor
final class PanelPerfMonitor: NSObject {
    private var link: CADisplayLink?
    private var openedAt: CFTimeInterval = 0
    private var requestedAt: CFTimeInterval = 0
    private var lastTick: CFTimeInterval = 0
    private var frames = 0
    private var stalls: [CFTimeInterval] = []
    private var firstFrameLogged = false

    /// Call when an open is requested (before layout), then `start` once the panel is ordered front.
    func markOpenRequested() {
        requestedAt = CACurrentMediaTime()
    }

    func start(window: NSWindow) {
        stop(log: false)
        openedAt = CACurrentMediaTime()
        AppLog.info(.statusItem, "perf: panel ordered front \(Self.ms(openedAt - requestedAt)) ms after the request")
        lastTick = 0
        frames = 0
        stalls = []
        firstFrameLogged = false
        let link = window.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop(log: Bool = true) {
        guard let link else { return }
        link.invalidate()
        self.link = nil
        guard log else { return }
        let open = CACurrentMediaTime() - openedAt
        let worst = stalls.max().map { "\(Self.ms($0)) ms" } ?? "none"
        AppLog.info(.statusItem, "perf: panel was open \(String(format: "%.1f", open)) s, \(frames) frames, "
            + "\(stalls.count) stalls >= 50 ms, worst \(worst)")
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        frames += 1
        if !firstFrameLogged {
            firstFrameLogged = true
            AppLog.info(.statusItem, "perf: first frame \(Self.ms(now - requestedAt)) ms after the request")
        }
        defer { lastTick = now }
        guard lastTick > 0 else { return }
        let gap = now - lastTick
        let frame = max(link.targetTimestamp - link.timestamp, 1.0 / 120)
        guard gap >= max(0.05, frame * 3) else { return }
        stalls.append(gap)
        if gap >= 0.1 {
            AppLog.info(.statusItem, "perf: \(Self.ms(gap)) ms stall at \(String(format: "%.1f", now - openedAt)) s")
        }
    }

    private static func ms(_ seconds: CFTimeInterval) -> Int { Int((seconds * 1000).rounded()) }
}
