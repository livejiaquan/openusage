import CoreServices
import Foundation

/// Watches log roots with FSEvents (file-level events, 1 s latency) and calls `onChange` when anything
/// under them is written. Started only while the panel is visible; `stop()` tears the stream down so a
/// closed panel holds no watcher. `start`/`stop` are called from the main actor; the callback runs on a
/// private queue.
final class LogDirectoryWatcher: @unchecked Sendable {
    private let paths: [String]
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.livejiaquan.tokamak.log-watcher", qos: .utility)
    private var stream: FSEventStreamRef?

    init(paths: [URL], onChange: @escaping @Sendable () -> Void) {
        self.paths = paths.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        self.onChange = onChange
    }

    var isRunning: Bool { stream != nil }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<LogDirectoryWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
        AppLog.debug(.lifecycle, "live log watcher started (\(paths.count) roots)")
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        AppLog.debug(.lifecycle, "live log watcher stopped")
    }

    deinit { stop() }
}
