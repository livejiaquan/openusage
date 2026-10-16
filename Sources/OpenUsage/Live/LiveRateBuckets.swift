import Foundation

/// Tokens spent over the last 30 minutes in 30-second buckets, aligned to wall-clock 30 s boundaries.
/// The live Activity card reads a trailing-five-minute rate and a 60-point history from it. A value
/// type, so the local tails, remote samples, and the composer can copy and merge it freely.
struct LiveRateBuckets: Equatable, Sendable {
    static let bucketDuration: TimeInterval = 30
    static let bucketCount = 60
    static let trailingWindow: TimeInterval = 300
    /// Events stamped this far in the future still count (clock skew between the CLI and this Mac).
    static let futureTolerance: TimeInterval = 60

    /// Tokens per bucket, oldest first; the last element is the bucket containing `newestSlot`.
    private(set) var buckets: [Int]
    private var newestSlot: Int

    init(now: Date) {
        buckets = Array(repeating: 0, count: Self.bucketCount)
        newestSlot = Self.slot(of: now)
    }

    mutating func add(tokens: Int, at timestamp: Date, now: Date) {
        advance(to: now)
        guard tokens > 0, let index = index(of: timestamp, now: now) else { return }
        buckets[index] += tokens
    }

    /// Takes back tokens counted earlier (a duplicate log entry replaced by a larger one). Never below zero.
    mutating func remove(tokens: Int, at timestamp: Date, now: Date) {
        advance(to: now)
        guard tokens > 0, let index = index(of: timestamp, now: now) else { return }
        buckets[index] = max(0, buckets[index] - tokens)
    }

    private func index(of timestamp: Date, now: Date) -> Int? {
        let age = now.timeIntervalSince(timestamp)
        guard age <= Self.bucketDuration * Double(Self.bucketCount), age >= -Self.futureTolerance else { return nil }
        let index = Self.bucketCount - 1 - (newestSlot - min(Self.slot(of: timestamp), newestSlot))
        return index >= 0 ? index : nil
    }

    /// Rolls the window forward. A gap of 30 minutes or more empties it; going backwards is a no-op.
    mutating func advance(to now: Date) {
        advance(toSlot: Self.slot(of: now))
    }

    private mutating func advance(toSlot target: Int) {
        guard target > newestSlot else { return }
        let shift = target - newestSlot
        if shift >= Self.bucketCount {
            buckets = Array(repeating: 0, count: Self.bucketCount)
        } else {
            buckets.removeFirst(shift)
            buckets.append(contentsOf: repeatElement(0, count: shift))
        }
        newestSlot = target
    }

    func ratePerMinute(now: Date) -> Double {
        var current = self
        current.advance(to: now)
        let trailingBuckets = Int(Self.trailingWindow / Self.bucketDuration)
        let tokens = current.buckets.suffix(trailingBuckets).reduce(0, +)
        return Double(tokens) / (Self.trailingWindow / 60)
    }

    /// 60 values in tokens per minute, oldest first.
    func history(now: Date) -> [Double] {
        var current = self
        current.advance(to: now)
        let perMinute = 60 / Self.bucketDuration
        return current.buckets.map { Double($0) * perMinute }
    }

    /// Sums parts bucket by bucket. After the clock steps backwards some parts are anchored ahead of
    /// `now`, so everything aligns to the newest anchor instead of dropping those parts.
    static func merged(_ parts: [LiveRateBuckets], now: Date) -> LiveRateBuckets {
        var result = LiveRateBuckets(now: now)
        result.newestSlot = max(result.newestSlot, parts.map(\.newestSlot).max() ?? result.newestSlot)
        for part in parts {
            var aligned = part
            aligned.advance(toSlot: result.newestSlot)
            for index in result.buckets.indices { result.buckets[index] += aligned.buckets[index] }
        }
        return result
    }

    private static func slot(of date: Date) -> Int {
        Int((date.timeIntervalSinceReferenceDate / bucketDuration).rounded(.down))
    }
}
