import Foundation

#if os(iOS) && canImport(BackgroundTasks)
@preconcurrency import BackgroundTasks
#endif

enum NFBackgroundTaskKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case prepareDailyPlan
    case indexSourceChunks
    case cleanGeneratedCache
    case assistPrivateSync

    var id: String { rawValue }

    var identifier: String {
        switch self {
        case .prepareDailyPlan:
            "com.zacrotech.NeuroForge.refresh.daily-plan"
        case .indexSourceChunks:
            "com.zacrotech.NeuroForge.processing.source-index"
        case .cleanGeneratedCache:
            "com.zacrotech.NeuroForge.processing.cache-cleanup"
        case .assistPrivateSync:
            "com.zacrotech.NeuroForge.processing.sync-assist"
        }
    }
}

enum NFBackgroundRequestClass: String, Codable, Equatable, Sendable {
    case appRefresh
    case processing
}

struct NFBackgroundTaskRequestDescriptor: Codable, Equatable, Identifiable, Sendable {
    let kind: NFBackgroundTaskKind
    let requestClass: NFBackgroundRequestClass
    let earliestBeginDate: Date
    let requiresNetworkConnectivity: Bool
    let requiresExternalPower: Bool

    var id: String { kind.identifier }
}

struct NFBackgroundWorkSnapshot: Codable, Equatable, Sendable {
    var shouldPrepareNextPlan: Bool
    var pendingSourceChunkCount: Int
    var expiredGeneratedCacheCount: Int
    var generatedCacheBytes: Int64
    var privateSyncAssistanceRequested: Bool
    var privateSyncIsConfigured: Bool

    init(
        shouldPrepareNextPlan: Bool = false,
        pendingSourceChunkCount: Int = 0,
        expiredGeneratedCacheCount: Int = 0,
        generatedCacheBytes: Int64 = 0,
        privateSyncAssistanceRequested: Bool = false,
        privateSyncIsConfigured: Bool = false
    ) {
        self.shouldPrepareNextPlan = shouldPrepareNextPlan
        self.pendingSourceChunkCount = max(0, pendingSourceChunkCount)
        self.expiredGeneratedCacheCount = max(0, expiredGeneratedCacheCount)
        self.generatedCacheBytes = max(0, generatedCacheBytes)
        self.privateSyncAssistanceRequested = privateSyncAssistanceRequested
        self.privateSyncIsConfigured = privateSyncIsConfigured
    }
}

enum NFBackgroundTaskPlanner {
    /// Background launches are only optimizations. Callers must be able to perform
    /// every requested operation after the next foreground launch.
    static func makeRequests(
        snapshot: NFBackgroundWorkSnapshot,
        now: Date
    ) -> [NFBackgroundTaskRequestDescriptor] {
        var requests: [NFBackgroundTaskRequestDescriptor] = []

        if snapshot.shouldPrepareNextPlan {
            requests.append(
                descriptor(
                    kind: .prepareDailyPlan,
                    requestClass: .appRefresh,
                    delay: 15 * 60,
                    now: now
                )
            )
        }

        if snapshot.pendingSourceChunkCount > 0 {
            requests.append(
                descriptor(
                    kind: .indexSourceChunks,
                    requestClass: .processing,
                    delay: 5 * 60,
                    now: now,
                    requiresExternalPower: snapshot.pendingSourceChunkCount >= 500
                )
            )
        }

        let shouldCleanCache = snapshot.expiredGeneratedCacheCount > 0
            || snapshot.generatedCacheBytes >= 128 * 1_024 * 1_024
        if shouldCleanCache {
            requests.append(
                descriptor(
                    kind: .cleanGeneratedCache,
                    requestClass: .processing,
                    delay: 60 * 60,
                    now: now,
                    requiresExternalPower: snapshot.generatedCacheBytes >= 512 * 1_024 * 1_024
                )
            )
        }

        if snapshot.privateSyncAssistanceRequested && snapshot.privateSyncIsConfigured {
            requests.append(
                descriptor(
                    kind: .assistPrivateSync,
                    requestClass: .processing,
                    delay: 15 * 60,
                    now: now,
                    requiresNetworkConnectivity: true
                )
            )
        }

        return requests.sorted { lhs, rhs in
            if lhs.earliestBeginDate == rhs.earliestBeginDate {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return lhs.earliestBeginDate < rhs.earliestBeginDate
        }
    }

    private static func descriptor(
        kind: NFBackgroundTaskKind,
        requestClass: NFBackgroundRequestClass,
        delay: TimeInterval,
        now: Date,
        requiresNetworkConnectivity: Bool = false,
        requiresExternalPower: Bool = false
    ) -> NFBackgroundTaskRequestDescriptor {
        NFBackgroundTaskRequestDescriptor(
            kind: kind,
            requestClass: requestClass,
            earliestBeginDate: now.addingTimeInterval(delay),
            requiresNetworkConnectivity: requiresNetworkConnectivity,
            requiresExternalPower: requiresExternalPower
        )
    }
}

enum NFBackgroundSchedulingStatus: Equatable, Sendable {
    case submitted
    case platformUnavailable
}

typealias NFBackgroundTaskHandler = @Sendable (NFBackgroundTaskKind) async -> Bool

@MainActor
protocol NFBackgroundTaskScheduling: AnyObject {
    func registerAll(handler: @escaping NFBackgroundTaskHandler) -> [NFBackgroundTaskKind: Bool]
    func submit(_ descriptor: NFBackgroundTaskRequestDescriptor) throws -> NFBackgroundSchedulingStatus
    func cancel(_ kind: NFBackgroundTaskKind)
}

@MainActor
final class NFBGTaskSchedulerAdapter: NFBackgroundTaskScheduling {
    #if os(iOS) && canImport(BackgroundTasks)
    private let scheduler: BGTaskScheduler

    init(scheduler: BGTaskScheduler = .shared) {
        self.scheduler = scheduler
    }
    #else
    init() {}
    #endif

    func registerAll(handler: @escaping NFBackgroundTaskHandler) -> [NFBackgroundTaskKind: Bool] {
        #if os(iOS) && canImport(BackgroundTasks)
        var results: [NFBackgroundTaskKind: Bool] = [:]
        for kind in NFBackgroundTaskKind.allCases {
            let registered = scheduler.register(
                forTaskWithIdentifier: kind.identifier,
                using: nil
            ) { task in
                let lifetime = NFBGTaskLifetime(task: task)
                let operation = Task.detached(priority: .utility) {
                    let completed = await handler(kind)
                    lifetime.complete(success: completed && !Task.isCancelled)
                }
                lifetime.installExpirationHandler {
                    operation.cancel()
                    lifetime.complete(success: false)
                }
            }
            results[kind] = registered
        }
        return results
        #else
        _ = handler
        return Dictionary(uniqueKeysWithValues: NFBackgroundTaskKind.allCases.map { ($0, false) })
        #endif
    }

    func submit(_ descriptor: NFBackgroundTaskRequestDescriptor) throws -> NFBackgroundSchedulingStatus {
        #if os(iOS) && canImport(BackgroundTasks)
        let request: BGTaskRequest
        switch descriptor.requestClass {
        case .appRefresh:
            request = BGAppRefreshTaskRequest(identifier: descriptor.id)
        case .processing:
            let processingRequest = BGProcessingTaskRequest(identifier: descriptor.id)
            processingRequest.requiresNetworkConnectivity = descriptor.requiresNetworkConnectivity
            processingRequest.requiresExternalPower = descriptor.requiresExternalPower
            request = processingRequest
        }
        request.earliestBeginDate = descriptor.earliestBeginDate
        try scheduler.submit(request)
        return .submitted
        #else
        _ = descriptor
        return .platformUnavailable
        #endif
    }

    func cancel(_ kind: NFBackgroundTaskKind) {
        #if os(iOS) && canImport(BackgroundTasks)
        scheduler.cancel(taskRequestWithIdentifier: kind.identifier)
        #else
        _ = kind
        #endif
    }
}

#if os(iOS) && canImport(BackgroundTasks)
private final class NFBGTaskLifetime: @unchecked Sendable {
    private let task: BGTask
    private let lock = NSLock()
    private var didComplete = false

    init(task: BGTask) {
        self.task = task
    }

    func installExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
        task.expirationHandler = handler
    }

    func complete(success: Bool) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        lock.unlock()
        task.setTaskCompleted(success: success)
    }
}
#endif
