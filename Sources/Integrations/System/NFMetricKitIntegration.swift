import Foundation

#if canImport(MetricKit)
import MetricKit

/// First-party performance/crash diagnostics only. Payload contents stay with
/// Apple's MetricKit pipeline; NeuroForge retains only aggregate in-memory
/// receipt counts and never forwards a payload to analytics or a custom server.
final class NFMetricKitSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = NFMetricKitSubscriber()

    struct Snapshot: Equatable, Sendable {
        let metricPayloadCount: Int
        let diagnosticPayloadCount: Int
        let isRegistered: Bool
    }

    private let lock = NSLock()
    private var metricPayloadCount = 0
    private var diagnosticPayloadCount = 0
    private var isRegistered = false

    private override init() {
        super.init()
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !isRegistered else { return }
        MXMetricManager.shared.add(self)
        isRegistered = true
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isRegistered else { return }
        MXMetricManager.shared.remove(self)
        isRegistered = false
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        lock.lock()
        metricPayloadCount += payloads.count
        lock.unlock()
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        lock.lock()
        diagnosticPayloadCount += payloads.count
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            metricPayloadCount: metricPayloadCount,
            diagnosticPayloadCount: diagnosticPayloadCount,
            isRegistered: isRegistered
        )
    }
}
#else
final class NFMetricKitSubscriber: @unchecked Sendable {
    static let shared = NFMetricKitSubscriber()

    struct Snapshot: Equatable, Sendable {
        let metricPayloadCount: Int
        let diagnosticPayloadCount: Int
        let isRegistered: Bool
    }

    private init() {}
    func start() {}
    func stop() {}
    func snapshot() -> Snapshot {
        Snapshot(metricPayloadCount: 0, diagnosticPayloadCount: 0, isRegistered: false)
    }
}
#endif
