import AppKit
import SwiftUI

// Decorative live motion drawn by Core Animation in the render server. A `TimelineView(.animation)` made
// SwiftUI re-render the whole panel every display frame (~25% of the main thread with the panel open),
// which read as stutter; these layers animate with no per-frame SwiftUI work. Each one runs only while
// `animate` is true (panel shown, Reduce Animations off) and never takes clicks.

/// The live dot: a 6 pt circle whose opacity breathes over 4.5 s.
struct BreathingDotLayer: NSViewRepresentable {
    var active: Bool
    var animate: Bool

    func makeNSView(context: Context) -> BreathingDotView { BreathingDotView() }

    func updateNSView(_ view: BreathingDotView, context: Context) {
        view.update(active: active, animate: animate)
    }
}

final class BreathingDotView: NSView {
    private static let key = "breathe"
    private var active = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 6, height: 6) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColor()
    }

    func update(active: Bool, animate: Bool) {
        self.active = active
        applyColor()
        guard let layer else { return }
        if active && animate {
            guard layer.animation(forKey: Self.key) == nil else { return }
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = 1
            breathe.toValue = 0.45
            breathe.duration = 2.25
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(breathe, forKey: Self.key)
        } else {
            layer.removeAnimation(forKey: Self.key)
        }
    }

    private func applyColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (active ? NSColor.systemGreen : NSColor.secondaryLabelColor).cgColor
        }
    }
}

/// The calm sweep across a live meter's fill: a soft highlight travels left to right over the first 62%
/// of `period`, then rests. Clips itself to the capsule it overlays.
struct MeterSweepLayer: NSViewRepresentable {
    var period: TimeInterval
    var animate: Bool

    func makeNSView(context: Context) -> MeterSweepView { MeterSweepView() }

    func updateNSView(_ view: MeterSweepView, context: Context) {
        view.update(period: period, animate: animate)
    }
}

final class MeterSweepView: NSView {
    private static let key = "sweep"
    private let band = CAGradientLayer()
    private var period: TimeInterval = 12
    private var animate = false
    private var animatedWidth: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        band.isHidden = true
        layer?.addSublayer(band)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        if bounds.width != animatedWidth { restart() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    /// A new period restarts the cycle only when it moved by a second or more, so the 2-second speed
    /// updates don't keep resetting the sweep mid-travel.
    func update(period: TimeInterval, animate: Bool) {
        let periodChanged = abs(period - self.period) >= 1
        if periodChanged { self.period = period }
        guard animate != self.animate || periodChanged else { return }
        self.animate = animate
        restart()
    }

    private func applyColors() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let peak = dark ? 0.42 : 0.7
        band.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(peak).cgColor,
                       NSColor.white.withAlphaComponent(0).cgColor]
    }

    private func restart() {
        band.removeAnimation(forKey: Self.key)
        animatedWidth = bounds.width
        guard animate, bounds.width > 0 else {
            band.isHidden = true
            return
        }
        applyColors()
        let width = max(bounds.width * 0.45, 24)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        band.isHidden = false
        band.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        band.position = CGPoint(x: -width / 2, y: bounds.height / 2)
        CATransaction.commit()
        let travel = CAKeyframeAnimation(keyPath: "position.x")
        travel.values = [-width / 2, bounds.width + width / 2, bounds.width + width / 2]
        travel.keyTimes = [0, 0.62, 1]
        travel.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .linear)]
        travel.duration = period
        travel.repeatCount = .infinity
        band.add(travel, forKey: Self.key)
    }
}

/// The optional faint glow at a live meter's leading edge: a soft blue disc breathing over 4.5 s.
struct EdgeGlowLayer: NSViewRepresentable {
    var animate: Bool

    func makeNSView(context: Context) -> EdgeGlowView { EdgeGlowView() }

    func updateNSView(_ view: EdgeGlowView, context: Context) {
        view.update(animate: animate)
    }
}

final class EdgeGlowView: NSView {
    private static let key = "glow"
    private let disc = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        disc.type = .radial
        disc.startPoint = CGPoint(x: 0.5, y: 0.5)
        disc.endPoint = CGPoint(x: 1, y: 1)
        disc.colors = [NSColor(red: 0.55, green: 0.78, blue: 1, alpha: 0.9).cgColor, NSColor.clear.cgColor]
        disc.opacity = 0
        layer?.addSublayer(disc)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        disc.frame = bounds
    }

    func update(animate: Bool) {
        guard animate else {
            disc.removeAnimation(forKey: Self.key)
            disc.opacity = 0
            return
        }
        guard disc.animation(forKey: Self.key) == nil else { return }
        disc.opacity = 0.3
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 0.15
        breathe.toValue = 0.45
        breathe.duration = 2.25
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        disc.add(breathe, forKey: Self.key)
    }
}
