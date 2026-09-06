import Observation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum NFSessionStage: String, Codable, Equatable, Sendable {
    case item
    case confidence
    case selfCheckComparison
    case reflection
    case feedback
    case summary
}

/// A save result alone is insufficient: the local journal can acknowledge the
/// exact state before a secondary store fails. Only that exact acknowledgement
/// permits closing; a prepared in-memory intent is not evidence of a saved one.
enum NFSessionExitDisposition: Equatable {
    case saved, pendingCommit, unacknowledged
    var permitsClose: Bool { self != .unacknowledged }
    static func resolve(saveSucceeded: Bool, exactAcknowledgement: Bool, pendingCommit: Bool) -> Self {
        guard saveSucceeded || exactAcknowledgement else { return .unacknowledged }
        return pendingCommit ? .pendingCommit : .saved
    }
}

enum NFSessionRecoveryText {
    static func make(response: NFExerciseResponse, exercise: NFExercise?, scratchpad: String = "", reflection: String = "") -> String {
        // Only learner-authored material is exported here. A protected exercise
        // cannot contribute option labels, references, feedback or a key.
        let context = exercise?.assessmentProtected == false ? exercise : nil
        var sections = [NFResponsePresentation.text(response, exercise: context)]
        if !scratchpad.isEmpty {
            if let payload = NFScratchpadInspection.inspect(scratchpad).payload {
                if !payload.notes.isEmpty { sections.append(payload.notes) }
                // Preserve drawing bytes in the recovery copy without invoking
                // the drawing renderer. Notes remain directly readable.
                if payload.hasDrawing { sections.append(payload.storedValue) }
            } else { sections.append(scratchpad) }
        }
        if !reflection.isEmpty { sections.append(reflection) }
        return sections.joined(separator: "\n\n")
    }
}

/// Minimal device-local commit input. No normalization, diagnosis, solution,
/// explanation or reusable scoring key can be represented by this type.
struct NFProtectedCommitReceipt: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let attemptID: UUID
    let exerciseID: String
    let descriptorID: String
    let exerciseDigest: String
    let scorerVersion: Int
    let outcome: NFScoringOutcome
    let isCorrect: Bool
    let credit: Double

    init?(attemptID: UUID, exercise: NFExercise, descriptor: NFAssessmentItemDescriptor?, score: NFExerciseScoringResult) {
        guard exercise.assessmentProtected, let descriptor, descriptor.isProtectedAssessment,
              score.exerciseID == exercise.id, score.scoringVersion == NFExerciseScoringEngine.scoringVersion,
              [.correct, .partial, .incorrect].contains(score.outcome), score.credit.isFinite,
              (0...1).contains(score.credit), score.isCorrect == (score.outcome == .correct),
              score.outcome == .correct ? score.credit == 1 : score.outcome == .incorrect ? score.credit == 0 : score.credit > 0 && score.credit < 1,
              let digest = try? NFLocalItemCheckpoint.digest(exercise) else { return nil }
        self.attemptID = attemptID; exerciseID = exercise.id; descriptorID = descriptor.id
        exerciseDigest = digest; scorerVersion = score.scoringVersion
        outcome = score.outcome; isCorrect = score.isCorrect; credit = score.credit
    }

    func verifiedScore(for saved: NFLocalItemCheckpoint, exercise: NFExercise) -> NFExerciseScoringResult? {
        guard schemaVersion == 1, attemptID == saved.attemptID, exerciseID == exercise.id,
              exercise.assessmentProtected, let descriptor = saved.descriptor,
              descriptor.isProtectedAssessment, descriptorID == descriptor.id,
              let catalog = saved.assessmentCatalogSnapshot,
              (catalog.items + catalog.candidatePool).contains(descriptor),
              descriptor.block == catalog.definition.kind,
              exerciseDigest == saved.exerciseDigest,
              (try? NFLocalItemCheckpoint.digest(exercise)) == exerciseDigest,
              scorerVersion == saved.scorerVersion, scorerVersion == NFExerciseScoringEngine.scoringVersion,
              [.correct, .partial, .incorrect].contains(outcome), credit.isFinite, (0...1).contains(credit),
              isCorrect == (outcome == .correct),
              outcome == .correct ? credit == 1 : outcome == .incorrect ? credit == 0 : credit > 0 && credit < 1 else { return nil }
        return Self.policySafeScore(exerciseID: exerciseID, scorerVersion: scorerVersion,
            outcome: outcome, isCorrect: isCorrect, credit: credit)
    }

    static func policySafeScore(_ score: NFExerciseScoringResult) -> NFExerciseScoringResult {
        policySafeScore(exerciseID: score.exerciseID, scorerVersion: score.scoringVersion,
            outcome: score.outcome, isCorrect: score.isCorrect, credit: score.credit)
    }

    private static func policySafeScore(exerciseID: String, scorerVersion: Int, outcome: NFScoringOutcome,
                                        isCorrect: Bool, credit: Double) -> NFExerciseScoringResult {
        .init(exerciseID: exerciseID, scoringVersion: scorerVersion, isCorrect: isCorrect, credit: credit,
            normalizedResponse: nil, errorCode: nil, expectedAnswerSummary: nil,
            feedback: .init(title: "Answer saved",
                explanation: "Skill guidance is available when this assessment block is complete.",
                decisiveStep: nil, strategy: nil, errorCode: nil, isDelayed: true), outcome: outcome)
    }
}

@MainActor
@Observable
final class NFSessionCloseRegistry {
    static let shared = NFSessionCloseRegistry()
    private struct Registration {
        let prepare: () -> Bool
        let close: () -> Void
        let saveGate: NFSessionDraftSaveGate?
    }
    private var registrations: [UUID: Registration] = [:]
    private var afterClosing: ((Bool) -> Void)?
    private var closingTokens: Set<UUID> = []

    var hasPresentations: Bool { !registrations.isEmpty }
    func register(_ id: UUID, check: @escaping () -> Bool, close: @escaping () -> Void = {},
                  saveGate: NFSessionDraftSaveGate? = nil) {
        registrations[id] = Registration(prepare: check, close: close, saveGate: saveGate)
        #if os(macOS)
        NFNativeSessionExitDiagnostics.record("registry.register.count=\(registrations.count)")
        #endif
        if let completion = afterClosing, !closingTokens.contains(id) {
            afterClosing = nil
            closingTokens = []
            #if os(macOS)
            NFNativeSessionExitDiagnostics.record("registry.close-cancelled-new-registration")
            #endif
            completion(false)
        }
    }
    func remove(_ id: UUID) {
        registrations.removeValue(forKey: id)
        #if os(macOS)
        NFNativeSessionExitDiagnostics.record("registry.remove.count=\(registrations.count).pending=\(afterClosing != nil)")
        #endif
        if registrations.isEmpty, let completion = afterClosing {
            afterClosing = nil
            closingTokens = []
            #if os(macOS)
            NFNativeSessionExitDiagnostics.record("registry.closed-completion")
            #endif
            completion(true)
        }
    }

    /// The close callback synchronously releases the writer and requests its
    /// owned presentation's dismissal. SwiftUI disappearance is only a fallback:
    /// it is not a reliable acknowledgement for a native Quit command.
    func closePresentation(_ id: UUID, close: () -> Void,
                           removeWindowRegistration: () -> Void = {}) {
        close()
        removeWindowRegistration()
        remove(id)
    }
    var hasPendingDraftSaves: Bool { registrations.values.contains { $0.saveGate?.isSaving == true } }
    var currentRegistrationIDs: Set<UUID> { Set(registrations.keys) }
    func awaitDraftSaves(expectedRegistrations tokens: Set<UUID>) async -> Bool {
        guard tokens == Set(registrations.keys) else { return false }
        let gates = registrations.values.compactMap(\.saveGate)
        // This only waits for already reserved writes. Afterward native routing
        // rechecks all current registrations and each actual current draft.
        for registration in registrations.values where registration.saveGate?.isSaving == true { _ = registration.prepare() }
        for gate in gates { await gate.waitUntilIdle() }
        return tokens == Set(registrations.keys)
    }

    func prepareToClose() -> Bool {
        guard !hasPendingDraftSaves else { return false }
        // Every presentation gets a save attempt; a cancelled quit grants no
        // cached permission to discard a subsequent edit.
        return registrations.values.map { $0.prepare() }.allSatisfy { $0 }
    }
    func closeAcknowledgedPresentations(completion: @escaping (Bool) -> Void) {
        let current = Array(registrations.values)
        #if os(macOS)
        NFNativeSessionExitDiagnostics.record("registry.close-acknowledged.count=\(current.count)")
        #endif
        guard !current.isEmpty else { completion(true); return }
        closingTokens = Set(registrations.keys)
        afterClosing = completion
        current.forEach { $0.close() }
    }
}

#if os(macOS)
final class NFSessionWindowCloseProxy: NSObject, NSWindowDelegate {
    struct Registration {
        let prepare: () -> Bool
        let close: () -> Void
        weak var presentationWindow: NSWindow?
        let saveGate: NFSessionDraftSaveGate?
    }
    private var awaitingDraftSaves = false
    weak var window: NSWindow?
    weak var previous: (any NSWindowDelegate)?
    var registrations: [UUID: Registration] = [:]
    var requestedClose = false

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NFNativeSessionExitDiagnostics.record("window.request")
        let gates = registrations.values.compactMap(\.saveGate).filter(\.isSaving)
        if !gates.isEmpty {
            guard !awaitingDraftSaves else { return false }
            awaitingDraftSaves = true
            let tokens = Set(registrations.keys)
            for registration in registrations.values where registration.saveGate?.isSaving == true { _ = registration.prepare() }
            Task { @MainActor [weak self, weak sender] in
                for gate in gates { await gate.waitUntilIdle() }
                guard let self, let sender else { return }
                self.awaitingDraftSaves = false
                guard Set(self.registrations.keys) == tokens else { return }
                // Re-enter the original route after storage acknowledgement;
                // registrations/delegate/child-sheet authority may have changed.
                guard self.registrations.values.allSatisfy({ $0.presentationWindow?.attachedSheet == nil }) else { return }
                if sender.delegate === self { _ = self.windowShouldClose(sender) }
                else { sender.performClose(nil) }
            }
            return false
        }
        guard registrations.values.map({ $0.prepare() }).allSatisfy({ $0 }) else {
            NFNativeSessionExitDiagnostics.record("window.blocked")
            return false
        }
        guard !registrations.isEmpty else { return previous?.windowShouldClose?(sender) ?? true }
        requestedClose = true
        NFNativeSessionExitDiagnostics.record("window.dismiss-owned-presentations")
        Array(registrations.values).forEach { $0.close() }
        return false
    }
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || previous?.responds(to: selector) == true
    }
    override func forwardingTarget(for selector: Selector!) -> Any? {
        previous?.responds(to: selector) == true ? previous : super.forwardingTarget(for: selector)
    }
}

/// A window has one proxy throughout overlapping SwiftUI view lifetimes.
/// Individual views remove only their own registration, never another writer.
@MainActor
final class NFSessionWindowCloseRegistry {
    static let shared = NFSessionWindowCloseRegistry(monitorsKeyboard: true)
    private var proxies: [ObjectIdentifier: NFSessionWindowCloseProxy] = [:]
    private let monitorsKeyboard: Bool
    private var closeKeyMonitor: Any?
    init(monitorsKeyboard: Bool = false) { self.monitorsKeyboard = monitorsKeyboard }
    var registeredWindows: [NSWindow] { proxies.values.compactMap(\.window) }

    /// SwiftUI's modal responder may consume the standard Close equivalent
    /// before the enabled Training command. Intercept only this app's exact
    /// active session presentation; child sheets keep their native key path.
    @discardableResult
    func routeCloseKey(_ event: NSEvent, keyWindow: NSWindow?) -> Bool {
        guard event.type == .keyDown, !event.isARepeat,
              event.charactersIgnoringModifiers?.lowercased() == "w",
              event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad]) == .command else { return false }
        proxies = proxies.filter { $0.value.window != nil }
        updateCloseKeyMonitor()
        guard let keyWindow else { return false }
        guard proxies.values.contains(where: { proxy in
            proxy.registrations.values.contains { $0.presentationWindow === keyWindow }
        }) else {
            NFNativeSessionExitDiagnostics.record("window.close-key.unregistered")
            return false
        }
        guard keyWindow.attachedSheet == nil else {
            NFNativeSessionExitDiagnostics.record("window.close-key.child-sheet")
            return false
        }
        NFNativeSessionExitDiagnostics.record("window.close-key.captured")
        NFSessionNativeCloseActions.shared.closeWindow(keyWindow, registry: self)
        return true
    }

    private func updateCloseKeyMonitor() {
        guard monitorsKeyboard else { return }
        if proxies.isEmpty {
            if let closeKeyMonitor { NSEvent.removeMonitor(closeKeyMonitor) }
            closeKeyMonitor = nil
        } else if closeKeyMonitor == nil {
            closeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    self?.routeCloseKey(event, keyWindow: NSApp.keyWindow) == true
                }
                return handled ? nil : event
            }
        }
    }
    @discardableResult
    func requestClose(_ candidate: NSWindow) -> Bool {
        let window = candidate.sheetParent ?? candidate
        guard let proxy = proxies[ObjectIdentifier(window)], proxy.window === window else { return false }
        _ = proxy.windowShouldClose(window)
        return true
    }


    func register(_ token: UUID, window candidate: NSWindow,
                  presentationWindow: NSWindow? = nil,
                  prepare: @escaping () -> Bool, close: @escaping () -> Void,
                  saveGate: NFSessionDraftSaveGate? = nil) {
        proxies = proxies.filter { $0.value.window != nil }
        let window = candidate.sheetParent ?? candidate
        let key = ObjectIdentifier(window)
        let proxy: NFSessionWindowCloseProxy
        if let existing = proxies[key], existing.window === window {
            proxy = existing
        } else {
            proxy = NFSessionWindowCloseProxy()
            proxy.window = window
            proxy.previous = window.delegate
            proxies[key] = proxy
        }
        proxy.registrations[token] = .init(prepare: prepare, close: close,
            presentationWindow: presentationWindow ?? candidate, saveGate: saveGate)
        updateCloseKeyMonitor()
        if window.delegate !== proxy {
            proxy.previous = window.delegate
            window.delegate = proxy
        }
    }

    func remove(_ token: UUID, window: NSWindow) {
        let target = window.sheetParent ?? window
        let key = ObjectIdentifier(target)
        guard let proxy = proxies[key], proxy.window === target else { return }
        proxy.registrations.removeValue(forKey: token)
        NFNativeSessionExitDiagnostics.record("window.registry-remove.count=\(proxy.registrations.count).requested=\(proxy.requestedClose)")
        guard proxy.registrations.isEmpty else { return }
        if target.delegate === proxy { target.delegate = proxy.previous }
        proxies.removeValue(forKey: key)
        updateCloseKeyMonitor()
        if proxy.requestedClose { NFNativeWindowCloseContinuation.schedule(target) }
    }

    func remove(_ token: UUID) {
        let windows = proxies.values.filter { $0.registrations[token] != nil }.compactMap(\.window)
        for window in windows { remove(token, window: window) }
    }
}

/// A one-shot continuation waits for owned sheets to finish tearing down.
/// It never polls and never bypasses the final native delegate decision.
@MainActor
final class NFNativeWindowCloseContinuation: NSObject {
    private static var pending: [UUID: NFNativeWindowCloseContinuation] = [:]
    private let id = UUID()
    private var windows: [NSWindow]
    private let completion: () -> Void
    private init(windows: [NSWindow], completion: @escaping () -> Void) {
        self.windows = windows; self.completion = completion
    }
    static func schedule(_ window: NSWindow) {
        afterSheetsClose(in: [window]) { [weak window] in
            NFNativeSessionExitDiagnostics.record("window.retry-original-delegate")
            window?.performClose(nil)
        }
    }
    static func afterSheetsClose(in windows: [NSWindow], completion: @escaping () -> Void) {
        NFNativeSessionExitDiagnostics.record("continuation.start.windows=\(windows.count)")
        let continuation = NFNativeWindowCloseContinuation(windows: windows, completion: completion)
        pending[continuation.id] = continuation
        Task { @MainActor in
            await Task.yield()
            continuation.afterPresentationRemoval()
        }
    }
    private func afterPresentationRemoval() {
        windows.removeAll { $0.attachedSheet == nil }
        NFNativeSessionExitDiagnostics.record("continuation.inspect.attached=\(windows.count)")
        guard !windows.isEmpty else { finish(); return }
        for window in windows {
            NotificationCenter.default.addObserver(self, selector: #selector(sheetEnded(_:)),
                name: NSWindow.didEndSheetNotification, object: window)
        }
    }
    @objc private func sheetEnded(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === window }
        NFNativeSessionExitDiagnostics.record("continuation.sheet-ended.remaining=\(windows.count)")
        if windows.isEmpty { finish() }
    }
    private func finish() {
        NFNativeSessionExitDiagnostics.record("continuation.finish")
        NotificationCenter.default.removeObserver(self)
        Self.pending.removeValue(forKey: id)
        completion()
    }
}

@MainActor
final class NFSessionNativeCloseActions {
    static let shared = NFSessionNativeCloseActions()
    private var quitPending = false
    func closeWindow(_ window: NSWindow?, registry: NFSessionWindowCloseRegistry = .shared) {
        NFNativeSessionExitDiagnostics.record("window.command")
        guard let window else { return }
        if !registry.requestClose(window) { window.performClose(nil) }
    }
    func quit(registry: NFSessionCloseRegistry = .shared,
              windows: [NSWindow], terminate: @escaping () -> Void) {
        NFNativeSessionExitDiagnostics.record("quit.command")
        guard !quitPending else {
            NFNativeSessionExitDiagnostics.record("quit.already-pending")
            return
        }
        if registry.hasPendingDraftSaves {
            quitPending = true
            let tokens = registry.currentRegistrationIDs
            Task { @MainActor [weak self] in
                let unchanged = await registry.awaitDraftSaves(expectedRegistrations: tokens)
                guard let self else { return }
                self.quitPending = false
                guard unchanged else {
                    NFNativeSessionExitDiagnostics.record("quit.cancelled-new-registration")
                    return
                }
                self.quit(registry: registry, windows: windows, terminate: terminate)
            }
            return
        }
        guard registry.prepareToClose() else {
            NFNativeSessionExitDiagnostics.record("quit.blocked")
            return
        }
        guard registry.hasPresentations else {
            NFNativeSessionExitDiagnostics.record("quit.no-presentations")
            terminate()
            return
        }
        quitPending = true
        NFNativeSessionExitDiagnostics.record("quit.dismiss-owned-presentations")
        registry.closeAcknowledgedPresentations { [weak self] allPresentationsClosed in
            guard allPresentationsClosed else {
                self?.quitPending = false
                NFNativeSessionExitDiagnostics.record("quit.cancelled-new-registration")
                return
            }
            NFNativeWindowCloseContinuation.afterSheetsClose(in: windows) {
                self?.quitPending = false
                NFNativeSessionExitDiagnostics.record("quit.forward-native")
                terminate()
            }
        }
    }
}

private struct NFSessionWindowCloseGuard: NSViewRepresentable {
    let token: UUID
    let saveGate: NFSessionDraftSaveGate?
    let prepare: () -> Bool
    let close: () -> Void
    final class Probe: NSView {
        var moved: (@MainActor (NSWindow?) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); moved?(window) }
    }
    @MainActor final class Coordinator {
        let token: UUID
        weak var window: NSWindow?
        var prepare: () -> Bool = { true }
        var close: () -> Void = {}
        var saveGate: NFSessionDraftSaveGate?
        init(token: UUID) { self.token = token }
        func attach(_ candidate: NSWindow?) {
            let target = candidate?.sheetParent ?? candidate
            if window !== target { detach(); window = target }
            if let target {
                NFSessionWindowCloseRegistry.shared.register(token, window: target,
                    presentationWindow: candidate, prepare: prepare, close: close, saveGate: saveGate)
            }
        }
        func detach() {
            if let window { NFSessionWindowCloseRegistry.shared.remove(token, window: window) }
            window = nil
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(token: token) }
    func makeNSView(context: Context) -> Probe {
        let view = Probe(); view.moved = { [weak coordinator = context.coordinator] in coordinator?.attach($0) }
        return view
    }
    func updateNSView(_ view: Probe, context: Context) {
        context.coordinator.prepare = prepare
        context.coordinator.close = close
        context.coordinator.saveGate = saveGate
        context.coordinator.attach(view.window)
    }
    static func dismantleNSView(_ view: Probe, coordinator: Coordinator) { coordinator.detach() }
}
#endif

private struct NFSessionCloseGuardModifier: ViewModifier {
    let saveGate: NFSessionDraftSaveGate?
    let prepare: () -> Bool
    let close: () -> Void
    @State private var registrationID = UUID()
    func body(content: Content) -> some View {
        let token = registrationID
        let closePresentation = {
            NFSessionCloseRegistry.shared.closePresentation(token, close: close) {
                #if os(macOS)
                NFSessionWindowCloseRegistry.shared.remove(token)
                #endif
            }
        }
        return content
            .onAppear { NFSessionCloseRegistry.shared.register(token, check: prepare, close: closePresentation, saveGate: saveGate) }
            .onDisappear {
                #if os(macOS)
                NFSessionWindowCloseRegistry.shared.remove(token)
                #endif
                NFSessionCloseRegistry.shared.remove(token)
            }
            #if os(macOS)
            .background(NFSessionWindowCloseGuard(token: token, saveGate: saveGate, prepare: prepare, close: closePresentation).frame(width: 0, height: 0))
            #endif
    }
}
extension View {
    func nfSessionCloseGuard(id: UUID, saveGate: NFSessionDraftSaveGate? = nil,
                             prepare: @escaping () -> Bool, close: @escaping () -> Void) -> some View {
        modifier(NFSessionCloseGuardModifier(saveGate: saveGate, prepare: prepare, close: close))
    }
}

struct NFSessionSaveRecoveryView: View {
    let message: String
    let disposition: NFSessionExitDisposition
    let recoveryText: String
    let retry: () -> Void
    let close: () -> Void
    let discard: () -> Void
    let keepOpen: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Save interrupted").font(.title2.bold()).accessibilityHeading(.h1)
                    Text(verbatim: message)
                    Text(LocalizedStringKey(disposition == .pendingCommit
                        ? "Your answer is saved locally. This session is waiting to finish saving its last step. Continue the saved session to retry."
                        : disposition == .saved
                            ? "Your exact work is saved locally. It is safe to close this session."
                            : "These changes have not been acknowledged by local storage. Discarding leaves the last saved version unchanged."))
                    VStack(alignment: .leading, spacing: 12) {
                        ShareLink("Export recovery copy", item: recoveryText)
                        Button("Copy recovery text") {
                            #if os(macOS)
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(recoveryText, forType: .string)
                            #else
                            UIPasteboard.general.string = recoveryText
                            #endif
                        }
                    }.buttonStyle(.bordered).controlSize(.large)
                    Button("Retry save", action: retry).buttonStyle(.borderedProminent)
                    if disposition.permitsClose {
                        Button("Close saved work", action: close).buttonStyle(.bordered)
                    } else {
                        Button("Discard unsaved changes", role: .destructive, action: discard).buttonStyle(.bordered)
                    }
                    Button("Keep session open", action: keepOpen).buttonStyle(.bordered)
                    Text(verbatim: recoveryText).font(.body).textSelection(.enabled)
                }.controlSize(.large).padding(24).frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
            }
        }.interactiveDismissDisabled()
        #if os(macOS)
        .onExitCommand { keepOpen() }
        #endif
        .nfDesktopPresentationFrame(minWidth: 480, idealWidth: 640, minHeight: 500, idealHeight: 700)
    }
}

/// The command boundary shared by ordinary and private authored sessions. Storage
/// adapters supply individual durable operations; phase, frozen intent, retry
/// reconciliation and publication order live here rather than in either view.
@MainActor
@Observable
final class NFSessionLifecycleCoordinator {
    struct CommitIntent {
        let attemptID: UUID
        let response: NFExerciseResponse
        let score: NFExerciseScoringResult
        let confidence: ConfidenceLevel?
    }
    enum Receipt { case absent, matching, conflicting }
    enum AdvanceCommand { case next, completedSkip, endSession, continueSitting }
    enum Advance<Snapshot> {
        case item(Snapshot)
        case summary(Snapshot)
        case unavailable(String)
    }

    var phase: NFSessionStage = .item
    private(set) var isBusy = false
    private(set) var preparedIntent: CommitIntent?

    func resetForItem() { preparedIntent = nil; phase = .item }

    @discardableResult
    func revealReference(canMutate: () -> Bool, expose: (Bool) -> Void, persist: () -> Bool) -> Bool {
        guard !isBusy, canMutate(), phase == .item || phase == .confidence else { return false }
        let previous = phase
        phase = .selfCheckComparison
        expose(true)
        guard persist(), canMutate() else {
            expose(false)
            phase = previous
            return false
        }
        return true
    }

    func commit(exercise: NFExercise, response: NFExerciseResponse, attemptID: UUID?,
                confidence: ConfidenceLevel?, recoveredIntent: CommitIntent?,
                canMutate: () -> Bool, receipt: (CommitIntent) -> Receipt,
                allowsNewCommit: () -> Bool, publishPrepared: (CommitIntent) -> Void,
                persistPrepared: () -> Bool, saveAttempt: (CommitIntent) throws -> Void,
                acknowledge: (CommitIntent) -> Void, persistFeedback: () -> Bool,
                nonScorable: (NFExerciseScoringResult) -> Void, conflictingReceipt: (CommitIntent?) -> Void,
                failedSave: () -> Void) {
        guard !isBusy, canMutate(), phase == .item || phase == .confidence || phase == .selfCheckComparison else { return }
        isBusy = true
        defer { isBusy = false }
        let intent: CommitIntent
        if let frozen = preparedIntent ?? recoveredIntent {
            guard frozen.score.exerciseID == exercise.id,
                  frozen.score.scoringVersion == NFExerciseScoringEngine.scoringVersion,
                  [.correct, .partial, .incorrect, .selfReported].contains(frozen.score.outcome),
                  NFGeneratedPracticeCompatibility.responseIsStructurallyCompatible(frozen.response, with: exercise.interaction) else {
                conflictingReceipt(nil)
                return
            }
            intent = frozen
        } else {
            let evaluated = NFExerciseScoringEngine.score(response, for: exercise)
            let score = exercise.assessmentProtected && [.correct, .partial, .incorrect].contains(evaluated.outcome)
                ? NFProtectedCommitReceipt.policySafeScore(evaluated) : evaluated
            guard score.outcome != .needsClarification && score.outcome != .invalidItem else {
                if score.outcome == .needsClarification { phase = .item }
                nonScorable(score)
                return
            }
            intent = CommitIntent(attemptID: attemptID ?? UUID(), response: response, score: score, confidence: confidence)
        }
        // Receipt reconciliation precedes quarantine checks and fresh writes.
        // A matching immutable receipt is sufficient to recover feedback.
        let savedReceipt = receipt(intent)
        guard canMutate() else { return }
        switch savedReceipt {
        case .conflicting:
            preparedIntent = intent
            phase = .confidence
            publishPrepared(intent)
            conflictingReceipt(intent)
            return
        case .matching:
            preparedIntent = intent
            phase = .feedback
            acknowledge(intent)
            _ = persistFeedback()
            return
        case .absent:
            guard allowsNewCommit() else { return }
        }
        preparedIntent = intent
        phase = .confidence
        publishPrepared(intent)
        guard persistPrepared(), canMutate() else { return }
        do {
            try saveAttempt(intent)
            guard canMutate() else { return }
            phase = .feedback
            acknowledge(intent)
            _ = persistFeedback()
        } catch { failedSave() }
    }

    /// The async adapter supplies an accepted-checkpoint publication closure;
    /// this coordinator never publishes feedback merely because a write began.
    func commitAsync(exercise: NFExercise, response: NFExerciseResponse, attemptID: UUID?,
        confidence: ConfidenceLevel?, recoveredIntent: CommitIntent?,
        canMutate: () -> Bool, receipt: (CommitIntent) -> Receipt,
        allowsNewCommit: () -> Bool, publishPrepared: (CommitIntent) -> Void,
        persistPrepared: () async throws -> Void, saveAttempt: (CommitIntent) async throws -> Void,
        persistAndPublishFeedback: (CommitIntent) async throws -> Void,
        nonScorable: (NFExerciseScoringResult) -> Void, conflictingReceipt: (CommitIntent?) -> Void,
        failedSave: (Error) -> Void) async {
        guard !isBusy, canMutate(), phase == .item || phase == .confidence || phase == .selfCheckComparison else { return }
        isBusy = true
        defer { isBusy = false }
        let intent: CommitIntent
        if let frozen = preparedIntent ?? recoveredIntent {
            guard frozen.score.exerciseID == exercise.id,
                  frozen.score.scoringVersion == NFExerciseScoringEngine.scoringVersion,
                  [.correct, .partial, .incorrect, .selfReported].contains(frozen.score.outcome),
                  NFGeneratedPracticeCompatibility.responseIsStructurallyCompatible(frozen.response, with: exercise.interaction) else {
                conflictingReceipt(nil)
                return
            }
            intent = frozen
        } else {
            let evaluated = NFExerciseScoringEngine.score(response, for: exercise)
            let score = exercise.assessmentProtected && [.correct, .partial, .incorrect].contains(evaluated.outcome)
                ? NFProtectedCommitReceipt.policySafeScore(evaluated) : evaluated
            guard score.outcome != .needsClarification && score.outcome != .invalidItem else {
                if score.outcome == .needsClarification { phase = .item }
                nonScorable(score)
                return
            }
            intent = CommitIntent(attemptID: attemptID ?? UUID(), response: response, score: score, confidence: confidence)
        }
        let savedReceipt = receipt(intent)
        guard canMutate() else { return }
        switch savedReceipt {
        case .conflicting:
            preparedIntent = intent; phase = .confidence; publishPrepared(intent)
            conflictingReceipt(intent); return
        case .matching:
            preparedIntent = intent
            do {
                try Task.checkCancellation()
                try await persistAndPublishFeedback(intent)
            } catch { failedSave(error) }
            return
        case .absent: guard allowsNewCommit() else { return }
        }
        preparedIntent = intent; phase = .confidence; publishPrepared(intent)
        do {
            try await persistPrepared()
            try Task.checkCancellation()
            guard canMutate() else { return }
            try await saveAttempt(intent)
            try Task.checkCancellation()
            guard canMutate() else { return }
            try await persistAndPublishFeedback(intent)
        } catch { failedSave(error) }
    }

    /// A skipped or disclosed item is an immutable activity receipt, never a
    /// fabricated deterministic score. Reconciliation precedes any fresh write.
    /// Unscored outcomes use the same receipt-first reconciliation as scored
    /// commits, with no fabricated scoring result or pre-acknowledged disclosure.
    func commitUnscoredAsync(canMutate: () -> Bool, receipt: () -> Receipt,
        prepare: () -> Void, persistPrepared: () async throws -> Void,
        save: () async throws -> Void, persistAndPublishFeedback: () async throws -> Void,
        conflictingReceipt: () async throws -> Void, failed: (Error) -> Void) async {
        guard !isBusy, canMutate(), phase == .item || phase == .confidence || phase == .feedback else { return }
        isBusy = true
        defer { isBusy = false }
        let savedReceipt = receipt()
        guard canMutate() else { return }
        do {
            try Task.checkCancellation()
            switch savedReceipt {
            case .matching:
                prepare(); phase = .confidence
                try await persistAndPublishFeedback()
                return
            case .conflicting:
                prepare(); phase = .confidence
                try await persistPrepared()
                try Task.checkCancellation()
                guard canMutate() else { return }
                try await conflictingReceipt()
                return
            case .absent: break
            }
            prepare(); phase = .confidence
            try await persistPrepared()
            try Task.checkCancellation()
            guard canMutate() else { return }
            try await save()
            try Task.checkCancellation()
            guard canMutate() else { return }
            try await persistAndPublishFeedback()
        } catch { failed(error) }
    }

    func commitUnscored(canMutate: () -> Bool, receipt: () -> Receipt,
                        prepare: () -> Void, persistPrepared: () -> Bool,
                        save: () throws -> Void, acknowledge: () -> Void,
                        persistFeedback: () -> Bool, failed: () -> Void) {
        guard !isBusy, canMutate(), phase == .item || phase == .confidence || phase == .feedback else { return }
        isBusy = true
        defer { isBusy = false }
        let savedReceipt = receipt()
        guard canMutate() else { return }
        switch savedReceipt {
        case .conflicting: failed(); return
        case .matching:
            phase = .feedback
            acknowledge()
            _ = persistFeedback()
            return
        case .absent: break
        }
        prepare()
        phase = .confidence
        guard persistPrepared(), canMutate() else { return }
        do {
            try save()
            guard canMutate() else { return }
            phase = .feedback
            acknowledge()
            _ = persistFeedback()
        } catch { failed() }
    }

    /// Async counterpart of the shared advance boundary. Cancellation may
    /// prevent persistence, but cannot retract an accepted storage receipt.
    func advanceAsync<Snapshot>(command: AdvanceCommand = .next,
        allowsUnpreparedEnding: Bool = false, canMutate: () -> Bool,
        prepare: () throws -> Advance<Snapshot>, persist: (Snapshot) async throws -> Snapshot,
        publish: (Snapshot) -> Void, unavailable: (String) -> Void,
        failed: (Error) -> Void) async {
        guard !isBusy, canMutate(), allowsAdvance(command, allowsUnpreparedEnding: allowsUnpreparedEnding) else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try Task.checkCancellation()
            let proposal = try prepare()
            switch proposal {
            case let .unavailable(reason): unavailable(reason)
            case let .item(snapshot):
                let accepted = try await persist(snapshot)
                guard canMutate() else { return }
                // An acknowledged rename is published even if the waiting
                // task was cancelled after the filesystem commit boundary.
                preparedIntent = nil
                phase = .item
                publish(accepted)
            case let .summary(snapshot):
                let accepted = try await persist(snapshot)
                guard canMutate() else { return }
                phase = .summary
                publish(accepted)
            }
        } catch { failed(error) }
    }

    private func allowsAdvance(_ command: AdvanceCommand, allowsUnpreparedEnding: Bool) -> Bool {
        switch command {
        case .next: phase == .feedback
        case .completedSkip: phase == .item || phase == .confidence
        case .endSession: phase != .confidence || (allowsUnpreparedEnding && preparedIntent == nil)
        case .continueSitting: phase == .summary
        }
    }

    /// No next-item state is published until its complete snapshot is durable.
    /// Unavailability and failed writes retain the current feedback and intent.
    func advance<Snapshot>(command: AdvanceCommand = .next, allowsUnpreparedEnding: Bool = false, canMutate: () -> Bool, persistCurrent: () -> Bool,
                           prepare: () throws -> Advance<Snapshot>, persist: (Snapshot) -> Bool,
                           publish: (Snapshot) -> Void, unavailable: (String) -> Void,
                           failedPreparation: () -> Void) {
        guard !isBusy, canMutate() else { return }
        guard allowsAdvance(command, allowsUnpreparedEnding: allowsUnpreparedEnding) else { return }
        isBusy = true
        defer { isBusy = false }
        guard persistCurrent(), canMutate() else { return }
        do {
            let proposal = try prepare()
            switch proposal {
            case let .unavailable(reason): unavailable(reason)
            case let .item(snapshot):
                guard persist(snapshot), canMutate() else { return }
                preparedIntent = nil
                phase = .item
                publish(snapshot)
            case let .summary(snapshot):
                guard persist(snapshot), canMutate() else { return }
                phase = .summary
                publish(snapshot)
            }
        } catch { failedPreparation() }
    }
}

extension NFExerciseResponse {
    /// Shared empty draft for atomic launch preparation and the visible editor.
    static func initialDraft(for exercise: NFExercise) -> NFExerciseResponse {
        switch exercise.interaction {
        case .numeric: .numeric(.init(value: "", unit: nil))
        case .singleChoice: .singleChoice(optionID: "")
        case .multipleChoice: .multipleChoice(optionIDs: [])
        case let .orderedSteps(schema): .orderedSteps(stepIDs: schema.steps.map(\.id))
        case .shortText: .shortText("")
        case .selfCheck: .selfCheck(.init(rating: .notYet, reflection: ""))
        case let .claimEvidence(schema): .claimEvidence(.init(pairs: schema.claims.map { .init(claimID: $0.id, evidenceIDs: []) }.sorted { $0.claimID < $1.claimID }))
        case let .logicState(schema): .logicState(.init(finalState: Dictionary(uniqueKeysWithValues: schema.expectedFinalState.keys.map { ($0, "") }), violatedRuleID: nil))
        }
    }
}

extension NFLocalItemCheckpoint {
    static func initial(request: SessionRequest, exercise: NFExercise, slotID: UUID,
                        attemptID: UUID, at date: Date, reviewedDemand: NFEditorialDemandRecord? = nil,
                        timingConditionOverride: NFSessionTimingCondition? = nil) throws -> NFLocalItemCheckpoint {
        let effectiveTiming = timingConditionOverride ?? request.timingCondition
        guard timingConditionOverride.map({ $0.isSupported && $0.mode != .timedFluency }) ?? true,
              request.hasValidTimingDurations, effectiveTiming?.accepts(exercise, reviewedDemand: reviewedDemand) != false else {
            throw NFLocalSessionRepository.RepositoryError.unsupportedVersion
        }
        var value = NFLocalItemCheckpoint(slotID: slotID, attemptID: attemptID, index: 0,
            itemCount: request.requestedItemCount ?? 5, phase: .item, exercise: exercise,
            exerciseDigest: try digest(exercise), descriptor: nil, response: .initialDraft(for: exercise),
            confidence: nil, scratchpad: "", hintCount: 0, solutionRevealed: false, referenceRevealed: false,
            selfCheckRating: nil, result: nil, committedAttemptID: nil, correctness: [], credits: [],
            assessmentDescriptorIDs: [], assessmentEvents: [], cumulativeActiveDuration: 0,
            itemActiveDuration: 0, assessmentPracticeDuration: 0, interruptionCount: 0, revisionCount: 0,
            inputModality: .unknown, reflectionTrigger: nil, suggestedReflectionCode: nil,
            selectedReflectionCode: nil, reflectionNote: "",
            semanticExclusions: [NFQuestionFingerprint.fingerprint(for: exercise)], shownAt: date)
        value.timingConditionOverride = timingConditionOverride
        value.sittingActiveDuration = 0; value.sittingOrdinal = 0
        value.answerDurationComplete = true; value.assistanceEvents = []; value.mathWork = .initial(for: exercise); value.dataInspection = .initial(for: exercise); value.scienceStudy = .initial(for: exercise); value.transferRelationship = .initial(for: exercise)
        return value
    }
}

struct NFExerciseTableAccessibilityModel: Equatable, Sendable {
    let headers: [String]
    let rows: [[String]]
    let authoredSummary: String

    var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    var summary: String {
        let dimensions = NFAppLocalization.localized(
            "Table with \(NFAppLocalization.formattedColumnCount(columnCount)) and \(NFAppLocalization.formattedDataRowCount(rows.count)).",
            locale: NFAppLocalization.preferredLocale,
            comment: "Accessible exercise-table dimensions with localized column and data-row counts."
        )
        return authoredSummary.isEmpty ? dimensions : "\(authoredSummary) \(dimensions)"
    }

    func headerLabel(columnIndex: Int) -> String {
        let header = headers.indices.contains(columnIndex) && !headers[columnIndex].isEmpty
            ? headers[columnIndex]
            : NFAppLocalization.localized(
                "Unlabeled column",
                locale: NFAppLocalization.preferredLocale,
                comment: "Fallback accessible exercise-table column name."
            )
        return NFAppLocalization.localized(
            "Column \(columnIndex + 1) of \(columnCount), header: \(header)",
            locale: NFAppLocalization.preferredLocale,
            comment: "Accessible exercise-table header with column position and header text."
        )
    }

    func rowLabel(rowIndex: Int) -> String {
        NFAppLocalization.localized(
            "Row \(rowIndex + 1) of \(rows.count)",
            locale: NFAppLocalization.preferredLocale,
            comment: "Accessible exercise-table row position; placeholders are current and total row counts."
        )
    }

    func cellLabel(rowIndex: Int, columnIndex: Int) -> String {
        let header = headers.indices.contains(columnIndex) && !headers[columnIndex].isEmpty
            ? headers[columnIndex]
            : NFAppLocalization.localized(
                "Unlabeled column",
                locale: NFAppLocalization.preferredLocale,
                comment: "Fallback accessible exercise-table column name."
            )
        let value: String
        if rows.indices.contains(rowIndex),
           rows[rowIndex].indices.contains(columnIndex),
           !rows[rowIndex][columnIndex].isEmpty {
            value = rows[rowIndex][columnIndex]
        } else {
            value = NFAppLocalization.localized(
                "Empty",
                locale: NFAppLocalization.preferredLocale,
                comment: "Accessible exercise-table empty-cell value."
            )
        }
        return NFAppLocalization.localized(
            "Row \(rowIndex + 1) of \(rows.count), column \(columnIndex + 1) of \(columnCount). \(header): \(value)",
            locale: NFAppLocalization.preferredLocale,
            comment: "Accessible exercise-table cell with row/column position, header, and value."
        )
    }
}

@MainActor
@Observable
final class NFUniversalSessionRuntime {
    let draftSaveGate = NFSessionDraftSaveGate()
    let sessionID: UUID
    let request: SessionRequest
    private(set) var itemCount: Int
    private let assessmentSession: NFAssessmentBlockSession?
    private(set) var exercise: NFExercise
    private(set) var assessmentDescriptor: NFAssessmentItemDescriptor?
    private(set) var assessmentState: NFAdaptiveAssessmentState
    private(set) var assessmentStopReason: NFAssessmentStopReason?
    private let lifecycle = NFSessionLifecycleCoordinator()
    private(set) var stage: NFSessionStage {
        get { lifecycle.phase }
        set { lifecycle.phase = newValue }
    }
    private(set) var index: Int
    private(set) var results: [NFExerciseScoringResult] = []
    private(set) var correctness: [Bool]
    private(set) var credits: [Double]
    private(set) var assessmentDescriptorIDs: [String]
    private(set) var assessmentEvents: [String]
    private(set) var lastResult: NFExerciseScoringResult?
    private var savedClarificationMessage: String?
    private var clarificationResponseIdentity: String?
    private(set) var reflectionTrigger: NFAttemptReflectionTrigger?
    private(set) var shownAt = Date()
    private(set) var isPaused = false
    private(set) var isCommitInFlight = false
    private var pendingSubmissionVerification: NFPendingSubmissionVerification?
    private(set) var nextUnavailableReason: String?
    private(set) var hintCount = 0
    private(set) var assistanceEvents: [NFLocalAssistanceEvent] = []
    private(set) var traceInspection: NFTraceInspectionDraft?
    private(set) var interruptionCount = 0
    private(set) var revisionCount = 0
    private(set) var inputModality: NFInputModality = .unknown
    private var pauseStartedAt: Date?
    private var accumulatedPausedDuration: TimeInterval = 0
    private var cumulativeActiveDuration: TimeInterval
    private var assessmentPracticeActiveDuration: TimeInterval
    private var pendingAttemptID: UUID?
    private var pendingSkip = false
    private(set) var hasPreparedCommit = false
    private(set) var endedEarly = false
    private var pendingSelfCheckConfidence: ConfidenceLevel?
    private var committedAttemptID: UUID?
    var hasCommittedFeedback: Bool { stage == .feedback && committedAttemptID != nil }
    private var responseLockedActiveDuration: TimeInterval?
    private var pointerIsOverResponseControl = false
    private var seenQuestionFingerprints: Set<String> = []
    private var slotID = UUID()
    private let writerID = UUID()
    private let countAlternativeCommandID = UUID()
    #if DEBUG
    var receiptWriteAcknowledged: (() -> Void)?
    #endif
    private var writerRepository: NFLocalSessionRepository?
    private var timingAuthorityProfileID: UUID?
    private var retainedWriterAuthority: NFLocalWriterAuthority?
    private var activeCommandAuthority: NFLocalWriterAuthority?
    private var checkpointRevision = 0
    private var acknowledgedEnvelopeRevision: Int?
    private var ordinaryReservationDecisionID: String?
    private let monotonicNow: () -> TimeInterval
    private var activeSegmentStart: TimeInterval
    private var savedItemActiveDuration: TimeInterval = 0
    private var savedSittingActiveDuration: TimeInterval = 0
    private var sittingSegmentStart: TimeInterval?
    private var itemPresentationAcknowledged = false
    private var confidenceInteractionActive = false
    private(set) var sittingOrdinal = 0
    private(set) var awaitingNextSitting = false
    private(set) var answerDurationComplete = true
    private(set) var timeBudgetUsed = false
    private(set) var durationChoiceRequired = false
    private(set) var isDurablyPrepared = false
    private(set) var unavailableReason: String?
    private(set) var solutionRevealed = false
    var selectedConfidence: ConfidenceLevel?
    private var confidenceResponseIdentity: String?


    var numericValue = ""
    var numericUnit = ""
    var singleChoiceID: String?
    var multipleChoiceIDs: Set<String> = []
    var orderedStepIDs: [String] = []
    var shortText = ""
    var selfCheckRating: NFSelfCheckRating?
    var selfCheckReflection = ""
    var selfCheckReferenceRevealed = false
    var claimSelections: [String: Set<String>] = [:]
    var logicState: [String: String] = [:]
    private(set) var mathWork: NFMathWorkDraft?
    private(set) var dataInspection: NFDataInspectionDraft?
    private(set) var scienceStudy: NFScienceStudyDraft?
    private(set) var transferRelationship: NFTransferRelationshipDraft?
    var violatedRuleID: String?
    var scratchpad = ""
    var showScratchpad = false
    var showHint = false
    var showReport = false
    var timerIsVisible = true
    private(set) var timingConditionOverride: NFSessionTimingCondition?
    var saveError: String?
    private(set) var suggestedReflectionCode: NFErrorReflectionCode?
    var selectedReflectionCode: NFErrorReflectionCode?
    var reflectionNote = ""

    init(request: SessionRequest, sessionID: UUID = UUID(), monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.monotonicNow = monotonicNow
        self.activeSegmentStart = monotonicNow()
        self.request = request
        self.sessionID = request.localSessionID ?? request.resumeSessionID ?? sessionID
        correctness = request.resumedResults
        credits = request.resumedCredits
        assessmentDescriptorIDs = request.resumedAssessmentDescriptorIDs
        let restoredAssessmentEvents = request.resumedAssessmentEvents.isEmpty
            ? request.resumedAssessmentDescriptorIDs.map { "answered:\($0)" }
            : request.resumedAssessmentEvents
        assessmentEvents = restoredAssessmentEvents
        let restoredTimingIsValid = request.hasValidTimingDurations && request.localCheckpoint?.hasValidTimingDurations != false
        let restoredActiveDuration = restoredTimingIsValid ? request.resumedActiveDurationSeconds : 0
        cumulativeActiveDuration = restoredActiveDuration
        assessmentPracticeActiveDuration = restoredTimingIsValid ? request.resumedAssessmentPracticeDurationSeconds : 0
        let restoredAssessmentElapsed = max(
            0,
            restoredActiveDuration - request.resumedAssessmentPracticeDurationSeconds
        )
        let restoredDescriptorIDs = Set(restoredAssessmentEvents.compactMap { event -> String? in
            guard let separator = event.firstIndex(of: ":") else { return nil }
            return String(event[event.index(after: separator)...])
        })
        let session = request.localCheckpoint?.assessmentCatalogSnapshot ?? request.assessmentBlock.map { block in
            NFAssessmentEngine.makeBlockSession(
                block: block,
                phase: request.reassessmentCycle.map { .reassessment(cycle: $0) }
                    ?? .initialBaseline,
                profileSeed: request.seed,
                selfReportedDifficulty: request.targetDifficulty ?? 0.5,
                excludedDescriptorIDs: request.quarantinedAssessmentDescriptorIDs
                    .subtracting(restoredDescriptorIDs)
            )
        }
        assessmentSession = session

        if let session {
            let restoredState = Self.replayAssessmentEvents(
                restoredAssessmentEvents,
                credits: request.resumedCredits,
                in: session,
                selfReportedDifficulty: request.targetDifficulty ?? 0.5
            )
            let restoredIndex = restoredState.completedScorableItems
            itemCount = session.itemCap
            assessmentState = restoredState
            index = restoredIndex
            if request.reassessmentCycle == nil,
               !restoredAssessmentEvents.contains(where: { $0.hasPrefix("practice:") }),
               let practiceDescriptor = Self.makeAssessmentPracticeDescriptor(
                    request: request,
                    block: session.definition.kind
               ) {
                assessmentDescriptor = practiceDescriptor
                assessmentStopReason = nil
                exercise = Self.makeExercise(
                    request: request,
                    index: restoredIndex,
                    assessmentDescriptor: practiceDescriptor
                )
            } else {
                let step = NFAssessmentEngine.nextStep(
                    in: session,
                    state: restoredState,
                    activeElapsedSeconds: NFSessionDurationPolicy.wholeSeconds(restoredAssessmentElapsed) ?? 0,
                    sittingBudgetSeconds: max(1, request.requestedMinutes ?? 5) * 60
                )
                assessmentDescriptor = step.item
                assessmentStopReason = step.stopReason
                exercise = Self.makeExercise(
                    request: request,
                    index: restoredIndex,
                    assessmentDescriptor: step.item
                )
                if step.shouldStop { stage = .summary }
            }
        } else {
            let resolvedItemCount = max(1, request.requestedItemCount ?? 5)
            let resumeAtSummary = request.resumeCurrentItemWasCommitted
                && request.startingIndex >= resolvedItemCount
            let initialIndex = min(max(0, request.startingIndex), max(0, resolvedItemCount - 1))
            assessmentState = NFAdaptiveAssessmentState()
            assessmentDescriptor = nil
            assessmentStopReason = nil
            itemCount = resolvedItemCount
            index = initialIndex
            exercise = request.localCheckpoint?.exercise ?? Self.makeExercise(request: request, index: initialIndex, assessmentDescriptor: nil)
            if resumeAtSummary { stage = .summary }
        }
        unavailableReason = exercise.availabilityReason
        scratchpad = request.resumedScratchpad
        seenQuestionFingerprints.insert(NFQuestionFingerprint.fingerprint(for: exercise))
        prepareInteraction()
        let resumedResponse: NFExerciseResponse? = request.resumedResponsePayload
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(NFExerciseResponse.self, from: $0) }
        if (!request.resumeCurrentItemWasCommitted || request.resumedPendingReflectionAttemptID != nil),
           let response = resumedResponse {
            restore(response)
        }
        if assessmentSession == nil,
           let attemptID = request.resumedPendingReflectionAttemptID,
           let trigger = request.resumedReflectionTrigger,
           resumedResponse != nil {
            let restoredResult = NFExerciseScoringEngine.score(makeResponse(), for: exercise)
            lastResult = restoredResult
            committedAttemptID = attemptID
            pendingAttemptID = attemptID
            reflectionTrigger = trigger
            suggestedReflectionCode = restoredResult.isCorrect
                ? nil
                : NFErrorReflectionCode.candidate(
                    for: restoredResult.errorCode,
                    lab: exercise.lab
                )
            selectedReflectionCode = request.resumedSelectedReflectionCode
            reflectionNote = request.resumedReflectionNote
            stage = .reflection
        }
        if let checkpoint = request.localCheckpoint {
            restoreExactCheckpoint(checkpoint)
        } else if request.resumedResponsePayload != nil {
            unavailableReason = "This older session can’t be resumed exactly. Your saved answer and notes are retained. Start new practice to continue."
        }
        if !restoredTimingIsValid {
            unavailableReason = "The saved timing data is unavailable. Your original question and answer are retained for recovery."
        }
        // An external admission is checked only after attaching the exact local
        // repository. isDurablyPrepared stays false; no editor or clock is published.
        if request.timingCondition?.isSupported == false || timingConditionOverride?.isSupported == false {
            unavailableReason = "This timing setting needs a compatible version of NeuroForge. Your saved work is unchanged."
        }
        if assessmentSession == nil, request.requestedItemCount == nil, request.requestedMinutes != nil,
           request.localCheckpoint == nil {
            configureTimedWorkload()
        }
    }

    private func restoreExactCheckpoint(_ saved: NFLocalItemCheckpoint, freshlyAccepted: Bool = false) {
        cancelReviewedChoice()
        separateReviewedCommand = nil
        let isFreshAcceptance = freshlyAccepted || request.freshlyAcceptedLaunch == true
        guard saved.hasValidTimingDurations, request.hasValidTimingDurations else {
            unavailableReason = "The saved timing data is unavailable. Your original question and answer are retained for recovery."
            return
        }
        guard request.permitsSpatialAssembly(exercise:saved.exercise),request.permitsCoordinateReasoning(exercise:saved.exercise),request.permitsNetFolding(exercise:saved.exercise),request.permitsSolidSection(exercise:saved.exercise),request.permitsCoordinateTransform(exercise: saved.exercise),request.permitsSpatialStructure(exercise: saved.exercise), request.permitsRetrievalAsset(exercise: saved.exercise), request.permitsRetrievalAuthority(exercise: saved.exercise), request.hasSupportedScienceStudyPolicy, saved.hasSupportedScienceStudy, request.hasSupportedGraphConstructionPolicy, saved.hasSupportedGraphConstruction, request.permitsGraphConstruction(exercise: saved.exercise), request.supportsTransferRecipe(in: saved), saved.hasSupportedTransferRelationship else {
            unavailableReason = NFGeneratedPracticeCompatibility.unavailableMessage
            return
        }
        guard saved.hasSupportedDataInspection else {
            unavailableReason = "Saved data inspection is unavailable in this version. Your original answer remains saved."
            return
        }
        guard saved.hasSupportedTimingCondition, saved.hasSupportedMathWork, request.timingCondition?.isSupported != false else {
            unavailableReason = "This timing setting needs a compatible version of NeuroForge. Your saved work is unchanged."
            return
        }
        timingConditionOverride = saved.timingConditionOverride
        guard saved.schemaVersion == 1,
              saved.committedAttemptID != nil || saved.scorerVersion == NFExerciseScoringEngine.scoringVersion else {
            unavailableReason = "This saved work needs a newer version of NeuroForge."
            return
        }
        let exactExercise = saved.exercise ?? Self.makeExercise(request: request, index: saved.index, assessmentDescriptor: saved.descriptor)
        guard NFExerciseSchemaValidator.supportsExerciseSchemaVersion(exactExercise.schemaVersion) else {
            unavailableReason = "This saved work needs a compatible version of NeuroForge. Your original answers remain saved."
            return
        }
        guard (try? NFLocalItemCheckpoint.digest(exactExercise)) == saved.exerciseDigest else {
            unavailableReason = "This saved question could not be verified. Your original answer is retained."
            return
        }
        guard NFGeneratedPracticeCompatibility.responseIsStructurallyCompatible(saved.response, with: exactExercise.interaction) else {
            unavailableReason = "This saved work needs a compatible version of NeuroForge. Your original answers remain saved."
            return
        }
        if saved.committedAttemptID == nil, saved.phase == .item || saved.phase == .selfCheckComparison {
            do { try NFExerciseSchemaValidator.validateInteraction(exactExercise.interaction) }
            catch {
                unavailableReason = "This saved work needs a compatible version of NeuroForge. Your original answers remain saved."
                return
            }
        }
        guard exactExercise.hasSupportedTraceContract,
              saved.traceInspection.map({ $0.isValid(for: exactExercise) }) ?? true else {
            unavailableReason = "This saved work needs a compatible version of NeuroForge. Your original answers remain saved."
            return
        }
        if exactExercise.assessmentProtected, saved.pendingOutcome == "answer" || saved.committedAttemptID != nil || saved.protectedCommitReceipt != nil {
            guard saved.result == nil, saved.protectedCommitReceipt?.verifiedScore(for: saved, exercise: exactExercise) != nil else {
                unavailableReason = "This saved question could not be verified. Your original answer is retained."
                return
            }
        }
        lifecycle.resetForItem()
        confidenceInteractionActive = false
        exercise = exactExercise
        index = saved.index
        itemCount = saved.itemCount
        slotID = saved.slotID
        ordinaryReservationDecisionID = saved.ordinaryReservationDecisionID
        pendingAttemptID = saved.attemptID
        pendingSkip = saved.pendingOutcome == "skip" || saved.pendingOutcome == "reveal"
        hasPreparedCommit = saved.pendingOutcome == "answer"
        assessmentDescriptor = saved.descriptor
        stage = saved.phase
        endedEarly = saved.endedEarly == true
        prepareInteraction()
        restore(saved.response)
        savedClarificationMessage = saved.clarificationMessage
        clarificationResponseIdentity = saved.clarificationMessage == nil ? nil : semanticResponseIdentity
        selectedConfidence = saved.confidence
        confidenceResponseIdentity = saved.confidence == nil ? nil : semanticResponseIdentity
        scratchpad = saved.scratchpad
        hintCount = saved.hintCount
        assistanceEvents = saved.assistanceEvents ?? []
        traceInspection = saved.traceInspection
        showHint = saved.hintCount > 0
        solutionRevealed = saved.solutionRevealed
        selfCheckReferenceRevealed = saved.referenceRevealed
        selfCheckRating = saved.selfCheckRating
        pendingSelfCheckConfidence = saved.confidence
        lastResult = exercise.assessmentProtected
            ? saved.protectedCommitReceipt?.verifiedScore(for: saved, exercise: exercise)
            : saved.result
        committedAttemptID = saved.committedAttemptID
        correctness = saved.correctness
        credits = saved.credits
        assessmentDescriptorIDs = saved.assessmentDescriptorIDs
        assessmentEvents = saved.assessmentEvents
        cumulativeActiveDuration = saved.cumulativeActiveDuration
        savedItemActiveDuration = saved.itemActiveDuration
        assessmentPracticeActiveDuration = saved.assessmentPracticeDuration
        interruptionCount = saved.interruptionCount + (isFreshAcceptance ? 0 : 1)
        revisionCount = saved.revisionCount
        inputModality = saved.inputModality
        mathWork = saved.mathWork
        dataInspection = saved.dataInspection
        scienceStudy = saved.scienceStudy
        transferRelationship = saved.transferRelationship
        reflectionTrigger = saved.reflectionTrigger
        suggestedReflectionCode = saved.suggestedReflectionCode
        selectedReflectionCode = saved.selectedReflectionCode
        reflectionNote = saved.reflectionNote
        seenQuestionFingerprints = saved.semanticExclusions
        shownAt = saved.shownAt
        responseLockedActiveDuration = stage == .item ? nil : saved.itemActiveDuration
        savedSittingActiveDuration = max(0, saved.sittingActiveDuration ?? 0)
        sittingSegmentStart = nil
        itemPresentationAcknowledged = false
        sittingOrdinal = max(0, saved.sittingOrdinal ?? 0)
        awaitingNextSitting = saved.awaitingNextSitting == true
        assessmentStopReason = saved.assessmentStopReason
        timeBudgetUsed = saved.timeBudgetUsed == true
        // A fresh accepted launch has no unknown gap before presentation. A
        // resumed draft still cannot prove its last unsaved time fragment.
        answerDurationComplete = isFreshAcceptance && saved.answerDurationComplete == true
        isPaused = !isFreshAcceptance && stage != .summary
        NFSessionPauseDiagnostics.record(isPaused ? "restore.paused" : "restore.running")
        if let session = assessmentSession {
            let replayed = Self.replayAssessmentEvents(assessmentEvents, credits: credits, in: session, selfReportedDifficulty: request.targetDifficulty ?? 0.5)
            guard session.definition.kind == request.assessmentBlock,
                  saved.assessmentState == nil || saved.assessmentState == replayed else {
                unavailableReason = "This saved skill-check path could not be verified. Your original answers are retained."
                return
            }
            assessmentState = replayed
        }
    }

    var progress: Double {
        if stage == .summary { return 1 }
        if let assessmentSession {
            let itemProgress = Double(assessmentState.completedScorableItems)
                / Double(max(1, assessmentSession.minimumScorableItems))
            return min(1, max(0, itemProgress))
        }
        return Double(index) / Double(max(1, itemCount))
    }

    var positionLabel: String {
        if isAssessmentPractice {
            return NFAppLocalization.localized("Practice · no standardized score", locale: NFAppLocalization.preferredLocale, comment: "Position label for a checked preview whose task credit does not affect the protected skill score.")
        }
        return assessmentSession == nil
            ? NFAppLocalization.localized("\(index + 1) / \(itemCount)", locale: NFAppLocalization.preferredLocale, comment: "Exercise position followed by total exercise count.")
            : NFAppLocalization.localized("Question \(index + 1)", locale: NFAppLocalization.preferredLocale, comment: "Question number inside a skill-check block whose final length adapts to the learner.")
    }

    var nextActionTitle: String {
        if isAssessmentPractice {
            return NFAppLocalization.localized("Start skill check", locale: NFAppLocalization.preferredLocale, comment: "Button shown after a non-scored assessment preview.")
        }
        if let assessmentSession {
            let step = NFAssessmentEngine.nextStep(
                in: assessmentSession,
                state: assessmentState,
                activeElapsedSeconds: NFSessionDurationPolicy.wholeSeconds(assessmentActiveElapsed) ?? 0,
                    sittingBudgetSeconds: NFSessionDurationPolicy.wholeSeconds(sittingBudgetSeconds) ?? 0
            )
            return step.shouldStop
                ? NFAppLocalization.localized("View summary", locale: NFAppLocalization.preferredLocale, comment: "Session button shown after the final item.")
                : NFAppLocalization.localized("Next challenge", locale: NFAppLocalization.preferredLocale, comment: "Session button shown between exercises.")
        }
        return index + 1 == itemCount
            ? NFAppLocalization.localized("View summary", locale: NFAppLocalization.preferredLocale, comment: "Session button shown after the final item.")
            : NFAppLocalization.localized("Next challenge", locale: NFAppLocalization.preferredLocale, comment: "Session button shown between exercises.")
    }

    var currentTimingCondition: NFSessionTimingCondition? { timingConditionOverride ?? request.timingCondition }
    private var admittedTimingDemand: NFEditorialDemandRecord? {
        writerRepository?.admittedTimingDemand(request: request, exercise: exercise, slotID: slotID,
            decisionID: ordinaryReservationDecisionID, profileID: timingAuthorityProfileID)
    }
    private var hasTimingAuthority: Bool {
        guard request.timingCondition?.mode == .timedFluency else {
            return currentTimingCondition?.isSupported != false
        }
        // A display-only override can remove the timing target, but it cannot
        // bypass the accepted slot, profile, scorer or manifest authority.
        guard let demand = admittedTimingDemand else { return false }
        return currentTimingCondition?.accepts(exercise, reviewedDemand: demand) == true
    }
    var usesTimedMode: Bool {
        guard !hidesAssessmentTimer else { return false }
        if let condition = currentTimingCondition {
            return condition.mode == .timedFluency && isDurablyPrepared
                && condition.accepts(exercise, reviewedDemand: admittedTimingDemand)
        }
        return request.isTimed == true && exercise.timingEligible
    }
    var isTimingPresentationReady: Bool {
        request.timingCondition?.mode != .timedFluency || (isDurablyPrepared && hasTimingAuthority)
    }
    var showsTimer: Bool {
        guard !hidesAssessmentTimer, isTimingPresentationReady else { return false }
        if let condition = currentTimingCondition { return condition.isSupported && condition.mode != .untimed }
        return usesTimedMode
    }
    var usesElapsedOnly: Bool { currentTimingCondition?.mode == .elapsedOnly }

    /// Display-only changes preserve the committed question/configuration. The
    /// current condition lives with its draft, rather than rewriting its receipt.
    func setDisplayTiming(_ mode: NFEditorialTimingMode, store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.setDisplayTiming(mode, store: store)
        }) { return }
        guard mode != .timedFluency, !hidesAssessmentTimer, !hasPreparedCommit,
              !pendingSkip, ownsWriter, stage == .item else { return }
        let previous = timingConditionOverride
        timingConditionOverride = .init(mode)
        guard checkpointDraft(store: store) else { timingConditionOverride = previous; return }
    }

    var hidesAssessmentTimer: Bool { assessmentSession != nil || exercise.assessmentProtected }

    var isAssessmentPractice: Bool { assessmentDescriptor?.role == .practice }

    var displayedHint: String? {
        let hints = activeHintLadder
        guard !hints.isEmpty else { return nil }
        return hints[min(max(0, hintCount - 1), hints.count - 1)]
    }

    var requiresConfidence: Bool { exercise.assessmentProtected && !usesTimedMode }
    var isSelfCheck: Bool { if case .selfCheck = exercise.interaction { return true }; return false }
    var confidenceInvitation: Bool {
        !usesTimedMode && !isSelfCheck && EditorialBandEvidenceV1.confidenceInvited(
            sessionID: sessionID.uuidString.lowercased(), ordinaryPresentationOrdinal: index)
    }
    var responseDraftIdentity: String { encoded(makeResponse()) + scratchpad + reflectionNote + encoded(mathWork) + encoded(dataInspection) + encoded(scienceStudy) + encoded(transferRelationship) }
    var hintActionTitle: String {
        hintCount == 0 ? "Use a hint" : hintCount < activeHintLadder.count ? "Next hint" : "See worked solution"
    }
    var visibleHints: [String] { Array(activeHintLadder.prefix(hintCount)) }

    var responseEditorSlotID: UUID { slotID }
    var presentationIdentity: String { "\(slotID.uuidString)|\(stage.rawValue)|\(isDurablyPrepared)|\(isPaused)" }
    var sittingBudgetSeconds: TimeInterval {
        Double(max(1, request.requestedMinutes ?? 5)) * 60
    }
    var isTimeBudgetedPractice: Bool { assessmentSession == nil && request.requestedItemCount == nil && request.requestedMinutes != nil }
    var workloadMode: NFEditorialWorkMode {
        if exercise.assessmentProtected { return .protectedCheck }
        if isSelfCheck || exercise.evidenceClass == .documentPractice { return .personalStudy }
        if usesTimedMode { return .timedFluency }
        if request.evidenceClass == .retention { return .retention }
        if request.repairOriginAttemptID != nil { return .repair }
        return .practice
    }

    /// Called by the visible, fully prepared content surface. Construction,
    /// generation, disk writes and a hidden/background window are not work time.
    func acknowledgePresented() {
        if deferUntilDraftSaveCompletes({ [weak self] in self?.acknowledgePresented() }) { return }
        guard isDurablyPrepared, hasTimingAuthority, ownsWriter, !isPaused, stage != .summary,
              unavailableReason == nil, !durationChoiceRequired else { return }
        do {
            let command = try sessionWriterCommand()
            try writerRepository?.acknowledgeSessionPresentation(sessionID: sessionID, slotID: slotID, at: Date(), command: command)
        } catch {
            saveError = NFAppLocalization.localizedCatalogValue(
                "This session could not be saved. It remains open so you can retry or explicitly discard the unsaved changes.",
                locale: NFAppLocalization.preferredLocale)
            isDurablyPrepared = false
            return
        }
        if !itemPresentationAcknowledged {
            itemPresentationAcknowledged = true
            activeSegmentStart = monotonicNow()
        }
        if sittingSegmentStart == nil { sittingSegmentStart = monotonicNow() }
    }

    func sittingActiveElapsed() -> TimeInterval {
        let delta = sittingSegmentStart.map { monotonicNow() - $0 } ?? 0
        return savedSittingActiveDuration + (delta.isFinite ? max(0, delta) : 0)
    }

    private func freezeSittingClock() {
        savedSittingActiveDuration = sittingActiveElapsed()
        sittingSegmentStart = nil
    }

    func beginConfidenceInteraction() {
        guard stage == .item, !confidenceInteractionActive else { return }
        savedItemActiveDuration = currentItemActiveDuration()
        confidenceInteractionActive = true
    }

    func endConfidenceInteraction() {
        guard confidenceInteractionActive else { return }
        confidenceInteractionActive = false
        activeSegmentStart = monotonicNow()
    }

    private func configureTimedWorkload() {
        guard let first = NFEditorialWorkloadPolicy.runtimeEstimate(reviewedDemand: exercise.contractMetadata?.editorialDemand,
            legacyExpectedResponseSeconds: nil, mode: workloadMode) else {
            durationChoiceRequired = true
            return
        }
        var estimates = [first]
        var seconds = first.totalSeconds
        var exclusions = Set([NFQuestionFingerprint.fingerprint(for: exercise)])
        var ordinal = 1
        while seconds < sittingBudgetSeconds, ordinal < 1_000 {
            let candidate = Self.makeExercise(request: request, index: ordinal, assessmentDescriptor: nil, excludingContentFingerprints: exclusions)
            guard candidate.availabilityReason == nil,
                  let estimate = NFEditorialWorkloadPolicy.runtimeEstimate(reviewedDemand: candidate.contractMetadata?.editorialDemand,
                    legacyExpectedResponseSeconds: nil, mode: workloadMode) else { break }
            estimates.append(estimate); seconds += estimate.totalSeconds; ordinal += 1
            exclusions.insert(NFQuestionFingerprint.fingerprint(for: candidate))
        }
        itemCount = NFEditorialWorkloadPolicy.plannedItemCount(estimates: estimates, budgetSeconds: sittingBudgetSeconds, mode: workloadMode)
        if itemCount == 0 { timeBudgetUsed = true; enterSummary() }
    }

    func startCountBasedAlternative(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.startCountBasedAlternative(store: store)
        }) { return }
        guard durationChoiceRequired,
              store.activeSessionRequest == nil || store.activeSessionRequest?.id == request.id else { return }
        let previousRequest = store.activeSessionRequest
        store.activeSessionRequest = nil
        // Re-enter the canonical launch boundary so the accepted five-question
        // request receives its own exact reservation and keeps its provenance.
        let accepted = store.beginSession(lab: request.lab, source: request.source,
            preferredMentalMathKind: request.preferredMentalMathKind, evidenceClass: request.evidenceClass,
            field: request.field, topic: request.topic, recommendationRationale: request.recommendationRationale,
            targetDifficulty: request.targetDifficulty, requestedItemCount: 5,
            assessmentBlock: request.assessmentBlock, reassessmentCycle: request.reassessmentCycle,
            seedOverride: request.seed, planID: request.planID, planBlockID: request.planBlockID,
            isTimed: request.isTimed, timingCondition: request.timingCondition, mechanicID: request.mechanicID,
            retentionItemIDs: request.retentionItemIDs, retentionTargets: request.retentionTargets,
            transferBrief: request.transferBrief, launchLocaleIdentifier: request.localeIdentifier,
            additionalQuarantinedItemIDs: request.quarantinedItemIDs,
            additionalQuarantinedAssessmentDescriptorIDs: request.quarantinedAssessmentDescriptorIDs,
            launchCommandID: countAlternativeCommandID, repairOriginAttemptID: request.repairOriginAttemptID,
            repairSemanticExclusions: request.repairSemanticExclusions,
            reservationStrategy: request.ordinaryDelivery?.strategy ?? .fixedBlock,
            tracePolicyVersion: request.tracePolicyVersion, scienceStudyPolicyVersion: request.scienceStudyPolicyVersion,
            scienceStudyExcludedContextID: request.scienceStudyExcludedContextID, transferPolicyVersion: request.transferPolicyVersion, transferExcludedContextID: request.transferExcludedContextID,
            graphConstructionPolicyVersion: request.graphConstructionPolicyVersion,
            retrievalAuthorityPolicyVersion: request.retrievalAuthorityPolicyVersion,
            retrievalAssetPolicyVersion: request.retrievalAssetPolicyVersion,
            spatialStructurePolicyVersion: request.spatialStructurePolicyVersion,
            coordinateTransformPolicyVersion: request.coordinateTransformPolicyVersion,solidSectionPolicyVersion:request.solidSectionPolicyVersion,netFoldingPolicyVersion:request.netFoldingPolicyVersion,coordinateReasoningPolicyVersion:request.coordinateReasoningPolicyVersion,spatialAssemblyPolicyVersion:request.spatialAssemblyPolicyVersion)
        guard accepted else {
            store.activeSessionRequest = previousRequest ?? request
            saveError = store.lastErrorMessage
            return
        }
        releaseWriter()
    }

    func continueProtectedSitting(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.continueProtectedSitting(store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard awaitingNextSitting, assessmentSession != nil, ownsWriter, !hasExited,
              stage == .summary, !isCommitInFlight else { return }
        advanceProtectedItem(store: store, newSitting: true)
    }

    private var semanticResponseIdentity: String {
        NFConfidenceResponseIdentity.value(makeResponse(), exercise: exercise)
    }

    func chooseConfidence(_ confidence: ConfidenceLevel) {
        endConfidenceInteraction()
        selectedConfidence = confidence
        confidenceResponseIdentity = semanticResponseIdentity
    }

    func invalidateConfidenceAfterEdit() {
        if confidenceResponseIdentity != semanticResponseIdentity {
            selectedConfidence = nil
            confidenceResponseIdentity = nil
        }
    }

    var ownsWriter: Bool {
        writerRepository?.isWriter(activeCommandAuthority ?? retainedWriterAuthority, sessionID: sessionID) ?? true
    }

    func sessionWriterCommand() throws -> NFSessionWriterCommand {
        guard let writerRepository else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
        return try writerRepository.sessionCommand(authority: activeCommandAuthority ?? retainedWriterAuthority,
            sessionID: sessionID)
    }

    func releaseWriter() { freezeSittingClock(); writerRepository?.releaseWriter(writerID) }

    func takeOver(store: AppStore) {
        let repository = store.localSessions
        guard repository.takeOver(writerID, sessionID: sessionID, checkpoint: { [weak self, weak store] in
            guard let self, let store else { return true }
            return self.checkpointDraft(store: store)
        }) else {
            saveError = "The other window could not save its work. Keep it open and retry."
            return
        }
        writerRepository = repository
        retainedWriterAuthority = repository.writerAuthority(for: writerID, sessionID: sessionID)
        if let latest = repository.archive.sessions.first(where: { $0.id == sessionID }) {
            acknowledgedEnvelopeRevision = latest.revision
            restoreExactCheckpoint(latest.checkpoint)
        }
    }

    /// Disclosure begins only after the controller has acknowledged its
    /// immutable receipt. The source resolver checks protection again when the
    /// sheet opens, so a later imported restriction cannot leave stale content.
    func committedCitationContext(store: AppStore) -> NFCommittedFeedbackCitations? {
        guard stage == .feedback, !exercise.assessmentProtected,
              lastResult?.feedback.isDelayed == false,
              let attemptID = committedAttemptID,
              let record = store.attempts.first(where: { $0.id == attemptID }),
              record.sessionID == sessionID, record.itemID == exercise.id,
              store.historyPresentation(for: .init(attempt: record)).source != .protectedAssessment,
              let saved = store.exerciseSnapshot(for: attemptID), saved == exercise,
              !saved.citations.isEmpty,
              Set(saved.citations.map(\.id)).count == saved.citations.count,
              let digest = try? NFLocalItemCheckpoint.digest(saved) else { return nil }
        return .init(attemptID: attemptID, sessionID: sessionID, exerciseDigest: digest, citations: saved.citations)
    }

    var readableAnswer: String { NFResponsePresentation.text(makeResponse(), exercise: exercise) }

    func reconcilePendingSkip(store: AppStore) {
        if pendingSkip { skip(store: store) }
    }

    func retrySaving(store: AppStore) {
        if store.localSessions.archiveWriteVerificationNeeded, !draftSaveGate.isSaving {
            Task { @MainActor [weak self, weak store] in
                guard let self, let store else { return }
                if await self.checkpointDraftAsync(store: store) { self.retrySaving(store: store) }
            }
            return
        }
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.retrySaving(store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        if pendingSkip {
            reconcilePendingSkip(store: store)
        } else if committedAttemptID == nil && stage == .confidence {
            commit(confidence: selectedConfidence, store: store)
        } else { _ = checkpointDraft(store: store) }
    }

    func endSession(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.endSession(store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard ownsWriter, pendingSubmissionVerification == nil, !isCommitInFlight, !hasExited, stage != .summary else { return }
        if pendingSkip {
            skip(store: store, endingAfterAcknowledgement: true)
            return
        }
        if hasPreparedCommit {
            retrySaving(store: store)
            guard !hasPreparedCommit else { return }
        }
        endAtSavedBoundary(store: store)
    }

    private var pendingEditorialRepairCommandID: UUID?
    private var pendingEditorialRepairOriginID: UUID?
    var reviewedSlotLabel: String? {
        guard let decision = writerRepository?.archive.adaptiveItemReceipts?[ordinaryReservationDecisionID ?? ""]?.editorialDecision,
              decision.isSupported, let assignment = decision.reviewAssignment,
              assignment.isSupported else { return nil }
        if assignment.role != .probe, currentTimingCondition?.mode?.rawValue != assignment.group.pacingConditionID {
            return "Practice · review conditions changed"
        }
        switch assignment.role {
        case .probe: return "Reviewed practice"
        case .repair: return "Immediate repair · a fresh related question"
        case .delayedCheck: return "Delayed check · a fresh related question"
        }
    }
    func retrySimilar(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.retrySimilar(store: store)
        }) { return }
        guard stage == .feedback, !exercise.assessmentProtected,
              exercise.evidenceClass != .documentPractice, let committedAttemptID else { return }
        guard checkpointDraft(store: store) else { return }
        if lastResult?.isCorrect == false, request.ordinaryDelivery?.editorialPolicy?.usesDeclaredReviewSlots == true,
           writerRepository?.archive.adaptiveItemReceipts?[ordinaryReservationDecisionID ?? ""]?.editorialDecision?.admission.demand.reviewContract != nil {
            do {
                let command = try sessionWriterCommand()
                let id = pendingEditorialRepairOriginID == committedAttemptID ? (pendingEditorialRepairCommandID ?? UUID()) : UUID()
                pendingEditorialRepairCommandID = id; pendingEditorialRepairOriginID = committedAttemptID
                if store.beginEditorialRepair(from: request, commandID: id, command: command) {
                    pendingEditorialRepairCommandID = nil; pendingEditorialRepairOriginID = nil; releaseWriter()
                }
            } catch { saveError = error.localizedDescription }
            return
        }
        let previousRequest = store.activeSessionRequest
        let repairMechanicID: String?
        if (mathWork != nil || scienceStudy != nil || transferRelationship != nil), let familyID = exercise.contractMetadata?.familyID,
           let activity = NFDefaultContentCatalog.activity(id: familyID), activity.lab == exercise.lab,
           exercise.templateID.hasSuffix("." + activity.templateSlug) {
            // Family IDs identify catalog entries; only the explicit mechanic
            // token pins the generator variant for this new repair run.
            repairMechanicID = activity.mechanicID
        } else { repairMechanicID = request.mechanicID }
        store.activeSessionRequest = nil
        guard store.beginSession(lab: request.lab, source: .focused,
            preferredMentalMathKind: request.preferredMentalMathKind,
            field: request.field, topic: request.topic,
            requestedItemCount: 1,
            seedOverride: exercise.seed ^ NFStableDeterminism.hash64("repair|\(committedAttemptID.uuidString)"),
            isTimed: false, mechanicID: repairMechanicID,
            repairOriginAttemptID: committedAttemptID, repairSemanticExclusions: seenQuestionFingerprints,
            scienceStudyExcludedContextID: NFScienceStudyContract.make(exercise: exercise)?.contextID,
            transferExcludedContextID: NFTransferRelationshipContract.make(exercise: exercise)?.contextID,
            graphConstructionPolicyVersion: request.graphConstructionPolicyVersion,
            retrievalAuthorityPolicyVersion: request.retrievalAuthorityPolicyVersion,
            retrievalAssetPolicyVersion: request.retrievalAssetPolicyVersion,
            spatialStructurePolicyVersion: request.spatialStructurePolicyVersion,
            coordinateTransformPolicyVersion: request.coordinateTransformPolicyVersion,solidSectionPolicyVersion:request.solidSectionPolicyVersion,netFoldingPolicyVersion:request.netFoldingPolicyVersion,coordinateReasoningPolicyVersion:request.coordinateReasoningPolicyVersion,spatialAssemblyPolicyVersion:request.spatialAssemblyPolicyVersion) else {
            store.activeSessionRequest = previousRequest
            return
        }
    }

    func reflect() {
        guard stage == .feedback, ownsWriter, !exercise.assessmentProtected, reflectionTrigger != nil else { return }
        stage = .reflection
    }

    func dismissReflection() { if stage == .reflection { stage = .feedback } }


    var calculationChainDiagnostic: NFCalculationChainDiagnostic? {
        if let score = lastResult, !exercise.assessmentProtected,
           let value = NFMathWorkPolicy.diagnosis(exercise: exercise, draft: mathWork, submittedFinalValue: numericValue) {
            return .init(originalScoreIsCorrect: score.isCorrect, originalCredit: score.credit,
                expectedFinalValue: value.expectedFinalValue, submittedFinalValue: value.submittedFinalValue,
                checkpoints: value.checkpoints, firstMismatchedCheckpoint: value.firstMismatchedCheckpoint)
        }
        guard lastResult?.isCorrect == false,
              exercise.tags.contains("calculation-chain") else { return nil }
        let contract = exercise.representations.lazy.compactMap { representation -> NFCalculationChainContract? in
            guard case let .logicState(metadata) = representation else { return nil }
            return NFCalculationChainContract(representation: metadata)
        }.first
        guard let contract else { return nil }
        return NFCalculationChainEngine.diagnose(
            contract: contract,
            submittedFinalValue: numericValue
        )
    }

    var hasSavedSkipAwaitingAdvance: Bool {
        let event = "\(solutionRevealed ? "revealed" : "skipped"):\(assessmentDescriptor?.id ?? exercise.id)"
        return pendingSkip && assessmentEvents.contains(event)
    }

    var canSkip: Bool { stage == .item && !pendingSkip && !isAssessmentPractice && ownsWriter && unavailableReason == nil && isDurablyPrepared }

    var canEditDraft: Bool {
        if draftSaveGate.hasQueuedAction || isCommitInFlight || pendingSubmissionVerification != nil { return false }
        return stage == .item && committedAttemptID == nil && !isPaused
            && ownsWriter && isDurablyPrepared && !hasPreparedCommit && !pendingSkip && !solutionRevealed
    }

    var canRateSelfCheck: Bool {
        if draftSaveGate.hasQueuedAction || isCommitInFlight || pendingSubmissionVerification != nil { return false }
        return stage == .selfCheckComparison && isSelfCheck && selfCheckReferenceRevealed
            && committedAttemptID == nil && !isPaused && ownsWriter && isDurablyPrepared
            && !hasPreparedCommit && !pendingSkip && !solutionRevealed
    }

    var canSaveReflection: Bool {
        stage == .reflection && ownsWriter && reflectionTrigger != nil
            && reflectionNote.count <= AttemptReflectionRecord.maximumNoteCharacters
    }

    var hasSufficientAssessmentEvidence: Bool {
        guard !endedEarly else { return false }
        guard let assessmentSession else { return !correctness.isEmpty || assessmentEvents.contains { $0.hasPrefix("selfReported:") } }
        return assessmentSession.hasSufficientEvidence(in: assessmentState)
    }

    var hasCompletedRun: Bool {
        guard !endedEarly, stage == .summary else { return false }
        if assessmentSession != nil { return hasSufficientAssessmentEvidence }
        return index + 1 >= itemCount || timeBudgetUsed
    }

    var correctCount: Int { correctness.filter { $0 }.count }
    var incorrectCount: Int { correctness.count - correctCount }
    var skippedCount: Int { assessmentEvents.filter { $0.hasPrefix("skipped:") }.count }
    var revealedCount: Int { assessmentEvents.filter { $0.hasPrefix("revealed:") }.count }
    var presentedCount: Int { correctness.count + skippedCount + revealedCount + assessmentEvents.filter { $0.hasPrefix("selfReported:") }.count }

    private var assessmentActiveElapsed: TimeInterval {
        sittingActiveElapsed()
    }

    func activeElapsed(at date: Date = Date()) -> TimeInterval {
        let inProgress = stage == .item
            || stage == .confidence
            || stage == .selfCheckComparison
            ? (currentActivityIsAcknowledged ? 0 : (responseLockedActiveDuration ?? currentItemActiveDuration(at: date)))
            : 0
        return max(0, cumulativeActiveDuration + inProgress)
    }

    func timerLabel(at date: Date = Date()) -> String {
        guard showsTimer else {
            return NFAppLocalization.localized("Untimed", locale: NFAppLocalization.preferredLocale, comment: "Session timer status when timing is disabled.")
        }
        guard !usesElapsedOnly, let requestedMinutes = request.requestedMinutes else {
            return formatClock(sittingActiveElapsed())
        }
        let remaining = max(0, Double(requestedMinutes) * 60 - sittingActiveElapsed())
        return remaining > 0
            ? formatClock(remaining)
            : NFAppLocalization.localized("Time target reached", locale: NFAppLocalization.preferredLocale, comment: "Session timer status after the target duration elapses.")
    }

    func toggleTimerVisibility() {
        timerIsVisible.toggle()
    }

    var canSubmit: Bool {
        guard !draftSaveGate.hasQueuedAction, !isCommitInFlight, pendingSubmissionVerification == nil else { return false }
        guard hasTimingAuthority, request.timingCondition?.mode != .timedFluency || isDurablyPrepared else { return false }
        guard traceInspection.map({ $0.isValid(for: exercise) }) ?? true else { return false }
        guard ownsWriter, !pendingSkip, !isPaused else { return false }
        guard unavailableReason == nil, !solutionRevealed else { return false }
        if case .selfCheck = exercise.interaction {
            if stage == .selfCheckComparison {
                return selfCheckReferenceRevealed
                    && selfCheckRating != nil
                    && !selfCheckReflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return !selfCheckReflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let transferRelationship, !transferRelationship.isCompatible(with: exercise, response: makeResponse()) { return false }
        if awaitsTransferRelationship { return canLockTransferRelationship }
        if awaitsScienceEvidence { return scienceEvidenceValidation?.isValid == true }
        if awaitsEstimateLock { return NFStateValueAuthority.exactNumber(logicState[NFEstimateExactContract.estimateKey] ?? "") != nil }
        return responseValidation.isValid
    }

    var commandCapabilities: NFSessionCommandCapabilities {
        NFSessionCommandCapabilities.resolve(
            stage: stage,
            isPaused: isPaused,
            canSubmit: canSubmit
        )
    }

    var responseValidation: NFExerciseResponseValidation {
        NFExerciseResponseValidator.validate(
            makeResponse(),
            for: exercise.interaction,
            localeIdentifier: exercise.localeIdentifier
        )
    }

    var responseValidationMessage: String? {
        if let transferRelationship, !transferRelationship.isCompatible(with: exercise, response: makeResponse()) { return NFAppLocalization.localizedCatalogValue("This target response is too large to save. Your original text is retained; shorten it or export it before closing.", locale: NFAppLocalization.preferredLocale) }
        if awaitsTransferRelationship { return nil }
        if awaitsScienceEvidence { return scienceEvidenceValidation?.issue?.guidance }
        if awaitsEstimateLock {
            return canSubmit ? nil : NFAppLocalization.localized("Enter a numerical estimate before continuing.", locale: NFAppLocalization.preferredLocale, comment: "First-stage estimate input guidance.")
        }
        if case .selfCheck = exercise.interaction {
            if stage == .selfCheckComparison, selfCheckRating == nil {
                return NFAppLocalization.localized("Choose how closely your answer matched the reference.", locale: NFAppLocalization.preferredLocale, comment: "Self-check validation guidance before the learner chooses a match rating.")
            }
            if selfCheckReflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return NFAppLocalization.localized("Enter your answer before continuing.", locale: NFAppLocalization.preferredLocale, comment: "Self-check validation guidance for an empty pre-reference response.")
            }
            return nil
        }
        return responseValidation.issue?.guidance
    }

    var clarificationMessage: String? {
        guard stage == .item, clarificationResponseIdentity == semanticResponseIdentity else { return nil }
        return savedClarificationMessage
    }

    func submitResponse() {
        guard stage == .item, canSubmit, !awaitsEstimateLock, !awaitsScienceEvidence, !awaitsTransferRelationship else { return }
        if pendingAttemptID == nil { pendingAttemptID = UUID() }
        responseLockedActiveDuration = currentItemActiveDuration()
        endConfidenceInteraction()
        stage = .confidence
    }

    func noteTextResponseInput() {
        endConfidenceInteraction()
        inputModality = .keyboard
    }

    func noteDiscreteResponseInput() {
        endConfidenceInteraction()
        #if os(macOS)
        let eventType = NSApp.currentEvent?.type
        inputModality = eventType == .keyDown || eventType == .keyUp
            ? .keyboard
            : .pointer
        #else
        inputModality = pointerIsOverResponseControl ? .pointer : .touch
        #endif
    }

    func noteSubmissionControlInputIfNeeded(_ modality: NFInputModality? = nil) {
        guard inputModality == .unknown else { return }
        if let modality {
            inputModality = modality
        } else {
            noteDiscreteResponseInput()
        }
    }

    func setPointerOverResponseControl(_ isInside: Bool) {
        pointerIsOverResponseControl = isInside
    }

    func editResponse() {
        guard exercise.responseEditPolicy == .editableBeforeCommit,
              stage == .confidence,
              !isCommitInFlight, !hasPreparedCommit, !pendingSkip else { return }
        revisionCount += 1
        savedItemActiveDuration = responseLockedActiveDuration ?? currentItemActiveDuration()
        activeSegmentStart = monotonicNow()
        confidenceInteractionActive = false
        responseLockedActiveDuration = nil
        pendingSelfCheckConfidence = nil
        selfCheckReferenceRevealed = false
        selfCheckRating = nil
        stage = .item
    }


    var codeTraceProjection: NFCodeTraceProjection? { NFCodeTraceProjection.make(exercise: exercise) }
    var capturedSupportCount: Int { hintCount + (traceInspection == nil ? 0 : 1) + (dataInspection?.supportCount ?? 0) }
    func inspectCode(_ action: NFCodeTraceAction, store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.inspectCode(action, store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canEditDraft, let projection = codeTraceProjection else { return }
        let previous = traceInspection, previousEvents = assistanceEvents
        do {
            if var draft = traceInspection {
                switch action {
                case .next: draft.next(in: projection)
                case .previous: draft.previous()
                case .reset: draft.reset()
                case let .selectLine(line): draft.select(line: line, in: projection)
                case let .predict(name, value): draft.predict(variable: name, value: value, in: projection)
                }
                guard draft.isValid(for: exercise) else {
                    if case .predict = action {
                        // Keep the complete current edit for correction/export;
                        // incompatible text must not replace the durable draft.
                        traceInspection = draft
                        saveError = NFTraceInspectionDraft.oversizedPredictionMessage
                    }
                    return
                }
                traceInspection = draft
            } else {
                guard case .next = action, canSubmit else { return }
                traceInspection = try NFTraceInspectionDraft.begin(exercise: exercise, prediction: makeResponse())
            }
            guard traceInspection != previous else { return }
            if (traceInspection?.revealedStepCount ?? 0) > (previous?.revealedStepCount ?? 0) {
                assistanceEvents.append(.init(id: UUID(), kind: .codeTrace,
                    stage: traceInspection?.revealedStepCount ?? 0, activeOffset: currentItemActiveDuration(),
                    generatorVersion: exercise.generatorVersion))
            }
            checkpointDraftRetainingAcknowledgedStage(store: store) {
                if case .predict = action { return } // Keep new typed input visible for Retry/export.
                traceInspection = previous; assistanceEvents = previousEvents
            }
        } catch { saveError = "This saved work needs a compatible version of NeuroForge. Your original answers remain saved." }
    }

    func requestHint() {
        guard stage == .item, ownsWriter, !pendingSkip, !hasPreparedCommit, !exercise.assessmentProtected,
              hintCount < activeHintLadder.count else { return }
        showHint = true
        hintCount += 1
        assistanceEvents.append(.init(id: UUID(), kind: .hint, stage: hintCount,
            activeOffset: currentItemActiveDuration(), generatorVersion: exercise.generatorVersion))
    }

    func requestHint(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.requestHint(store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard !awaitsTransferRelationship else { return }
        let oldCount = hintCount
        let oldVisibility = showHint
        let oldEvents = assistanceEvents
        requestHint()
        guard hintCount != oldCount else { return }
        checkpointDraftRetainingAcknowledgedStage(store: store) {
            hintCount = oldCount
            showHint = oldVisibility
            assistanceEvents = oldEvents
        }
    }

    func revealSolution(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.revealSolution(store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard !awaitsTransferRelationship else { return }
        guard stage == .item, ownsWriter, !pendingSkip, !hasPreparedCommit, !solutionRevealed, !exercise.assessmentProtected else { return }
        let previousDuration = responseLockedActiveDuration
        solutionRevealed = true
        responseLockedActiveDuration = currentItemActiveDuration()
        assistanceEvents.append(.init(id: UUID(), kind: .workedSolution, stage: hintCount + 1,
            activeOffset: responseLockedActiveDuration ?? 0, generatorVersion: exercise.generatorVersion))
        checkpointDraftRetainingAcknowledgedStage(store: store) {
            solutionRevealed = false
            responseLockedActiveDuration = previousDuration
            assistanceEvents.removeLast()
        }
    }

    func submitInline(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.submitInline(store: store)
        }) { return }
        if awaitsTransferRelationship { _ = lockTransferRelationship(store: store); return }
        if awaitsScienceEvidence { _ = lockScienceEvidence(store: store); return }
        if awaitsEstimateLock { _ = lockEstimate(store: store); return }
        guard canSubmit, !requiresConfidence || selectedConfidence != nil else { return }
        invalidateConfidenceAfterEdit()
        guard !requiresConfidence || selectedConfidence != nil else { return }
        submitResponse()
        commit(confidence: selectedConfidence, store: store)
    }

    func commit(confidence: ConfidenceLevel?, store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.commit(confidence: confidence, store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard stage == .confidence, !pendingSkip, !isCommitInFlight, ownsWriter else { return }
        if case .selfCheck = exercise.interaction, !hasPreparedCommit {
            pendingSelfCheckConfidence = confidence
            lifecycle.revealReference(canMutate: { self.ownsWriter },
                expose: { self.selfCheckReferenceRevealed = $0 },
                persist: { self.checkpointDraft(store: store) })
            return
        }
        persistAttempt(confidence: hasPreparedCommit ? selectedConfidence : confidence, store: store)
    }

    func saveSelfCheck(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.saveSelfCheck(store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard stage == .selfCheckComparison,
              canSubmit else { return }
        persistAttempt(confidence: pendingSelfCheckConfidence, store: store)
    }

    private func persistAttempt(confidence: ConfidenceLevel?, store: AppStore) {
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard !isCommitInFlight, ownsWriter else { return }
        isCommitInFlight = true
        defer { isCommitInFlight = false }
        let response = makeResponse()
        let activeDuration = responseLockedActiveDuration ?? currentItemActiveDuration()
        let recovered: NFSessionLifecycleCoordinator.CommitIntent? = {
            guard hasPreparedCommit, let pendingAttemptID, let lastResult else { return nil }
            return .init(attemptID: pendingAttemptID, response: response, score: lastResult, confidence: selectedConfidence)
        }()
        lifecycle.commit(exercise: exercise, response: response, attemptID: pendingAttemptID,
            confidence: confidence, recoveredIntent: recovered,
            canMutate: { self.ownsWriter },
            // The ordinary repository validates the complete immutable receipt
            // on an idempotent save; it never replaces a conflicting attempt.
            receipt: { intent in
                guard self.exercise.assessmentProtected,
                      let record = store.attempts.first(where: { $0.id == intent.attemptID }) else { return .absent }
                return self.matchesOriginalReceipt(record, exercise: self.exercise, response: intent.response,
                    confidence: intent.confidence, descriptor: self.assessmentDescriptor)
                    && record.isCorrect == intent.score.isCorrect && record.deterministicCredit == intent.score.credit
                    ? .matching : .conflicting
            }, allowsNewCommit: {
                // A prepared checkpoint may lag an already-committed receipt.
                // AppStore performs its complete immutable comparison before
                // accepting that retry; later contract quarantine cannot force
                // a fresh evaluation of a saved receipt.
                if let id = self.pendingAttemptID, store.attempts.contains(where: { $0.id == id }) { return true }
                do { try NFExerciseSchemaValidator.validateInteraction(self.exercise.interaction); return true }
                catch {
                    self.unavailableReason = "This saved work needs a compatible version of NeuroForge. Your original answers remain saved."
                    return false
                }
            },
            publishPrepared: { intent in
                self.pendingAttemptID = intent.attemptID
                let referenceWasRevealed = self.selfCheckReferenceRevealed
                self.restore(intent.response)
                if case let .selfCheck(submission) = intent.response {
                    self.selfCheckReferenceRevealed = referenceWasRevealed
                    self.selfCheckRating = submission.rating
                }
                self.selectedConfidence = intent.confidence
                self.lastResult = intent.score
                self.hasPreparedCommit = true
            },
            persistPrepared: { self.checkpointDraft(store: store) },
            saveAttempt: { intent in
                try store.withSessionCommand(try self.sessionWriterCommand(), sessionID: self.sessionID) {
                    try store.saveExerciseAttempt(
                        attemptID: intent.attemptID, sessionID: self.sessionID,
                        exercise: self.exercise, response: intent.response, result: intent.score,
                        confidence: intent.confidence, shownAt: self.shownAt, activeDuration: activeDuration,
                        source: self.request.source, assessmentBlock: self.request.assessmentBlock,
                        assessmentDescriptorID: self.assessmentDescriptor?.id, assessmentDescriptor: self.assessmentDescriptor,
                        assessmentCycle: self.request.reassessmentCycle, planID: self.request.planID,
                        planBlockID: self.request.planBlockID, hintCount: self.capturedSupportCount,
                        inputMode: self.inputModality.rawValue, interruptionCount: self.interruptionCount,
                        revisionCount: self.revisionCount, accommodationFlags: self.accommodationFlags(store: store),
                        wasTimed: self.usesTimedMode, mathWork: self.mathWork, traceInspection: self.traceInspection, dataInspection: self.dataInspection, scienceStudy: self.scienceStudy, transferRelationship: self.transferRelationship)
                    #if DEBUG
                    self.receiptWriteAcknowledged?()
                    #endif
                }
            },
            acknowledge: { intent in
                self.acknowledgeCommittedAttempt(intent, activeDuration: activeDuration, store: store)
            },
            persistFeedback: { self.checkpointDraft(store: store) },
            nonScorable: { score in
                if score.outcome == .invalidItem { self.unavailableReason = score.feedback.explanation }
                else {
                    self.savedItemActiveDuration = activeDuration
                    self.activeSegmentStart = self.monotonicNow()
                    self.responseLockedActiveDuration = nil
                    self.savedClarificationMessage = score.feedback.explanation
                    self.clarificationResponseIdentity = self.semanticResponseIdentity
                    self.lastResult = nil
                    self.hasPreparedCommit = false
                    self.saveError = nil
                    _ = self.checkpointDraft(store: store)
                }
            }, conflictingReceipt: { _ in
                self.unavailableReason = "This saved work needs a compatible version of NeuroForge. Your original answers remain saved."
            }, failedSave: {
                self.saveError = "The response could not be saved. It remains on this screen so you can retry."
            })
    }

    private func matchesOriginalReceipt(_ record: AttemptRecord, exercise: NFExercise,
                                         response: NFExerciseResponse, confidence: ConfidenceLevel?,
                                         descriptor: NFAssessmentItemDescriptor?) -> Bool {
        guard !exercise.assessmentProtected || record.errorCode != "protected_evaluator_unavailable",
              let originalResponse = try? JSONDecoder().decode(NFExerciseResponse.self, from: Data(record.response.utf8)) else { return false }
        return record.sessionID == sessionID && record.itemID == exercise.id
            && record.templateID == exercise.templateID && record.seed == exercise.seed
            && record.gameID == exercise.lab.rawValue && record.prompt == exercise.prompt
            && record.scoringVersion == NFExerciseScoringEngine.scoringVersion
            && originalResponse == response && record.confidenceRaw == confidence?.rawValue
            && record.evidenceClassRaw == exercise.evidenceClass.rawValue
            && record.sessionSourceRaw == request.source.rawValue && !record.wasSkipped
            && record.generationID == nil && record.responseFormatRaw == response.responseFormatRaw
            && record.assessmentDescriptorID == descriptor?.id && record.assessmentBlockRaw == request.assessmentBlock?.rawValue
            && record.planID == request.planID && record.planBlockID == request.planBlockID
            && record.sourceDocumentIDsRaw == exercise.provenance.sourceDocumentIDs.joined(separator: ",")
            && record.sourceChunkIDsRaw == exercise.provenance.sourceChunkIDs.joined(separator: ",")
            && record.deterministicCredit.isFinite && (0...1).contains(record.deterministicCredit)
    }

    /// Older journals may lag an authenticated attempt. Reconcile only the
    /// original persisted receipt; never ask today's evaluator to regrade it.
    func reconcileProtectedReceipt(store: AppStore) {
        guard var saved = request.localCheckpoint, saved.exercise == nil,
              saved.protectedCommitReceipt == nil,
              saved.pendingOutcome == "answer" || saved.committedAttemptID != nil,
              let record = store.attempts.first(where: { $0.id == (saved.committedAttemptID ?? saved.attemptID) }),
              record.id == saved.attemptID, let descriptor = saved.descriptor,
              let catalog = saved.assessmentCatalogSnapshot,
              catalog.definition.kind == request.assessmentBlock,
              (catalog.items + catalog.candidatePool).contains(descriptor),
              saved.scorerVersion == NFExerciseScoringEngine.scoringVersion else { return }
        let exact = Self.makeExercise(request: request, index: saved.index, assessmentDescriptor: descriptor)
        guard NFExerciseSchemaValidator.supportsExerciseSchemaVersion(exact.schemaVersion),
              (try? NFLocalItemCheckpoint.digest(exact)) == saved.exerciseDigest,
              matchesOriginalReceipt(record, exercise: exact, response: saved.response,
                  confidence: saved.confidence, descriptor: descriptor) else { return }
        let score = NFExerciseScoringResult(exerciseID: exact.id, scoringVersion: record.scoringVersion,
            isCorrect: record.isCorrect, credit: record.deterministicCredit, normalizedResponse: nil,
            errorCode: nil, expectedAnswerSummary: nil,
            feedback: .init(title: "Answer saved", explanation: "Skill guidance is available when this assessment block is complete.",
                decisiveStep: nil, strategy: nil, errorCode: nil, isDelayed: true))
        saved.result = nil
        saved.protectedCommitReceipt = NFProtectedCommitReceipt(attemptID: saved.attemptID,
            exercise: exact, descriptor: descriptor, score: score)
        guard saved.protectedCommitReceipt?.verifiedScore(for: saved, exercise: exact) != nil else { return }
        unavailableReason = nil
        restoreExactCheckpoint(saved)
    }

    private func acknowledgeCommittedAttempt(_ intent: NFSessionLifecycleCoordinator.CommitIntent,
                                         activeDuration: TimeInterval, store: AppStore) {
        let score = intent.score
        let attemptID = intent.attemptID
        let confidence = intent.confidence
        cumulativeActiveDuration += activeDuration
        if isAssessmentPractice, let descriptorID = assessmentDescriptor?.id {
            assessmentPracticeActiveDuration += activeDuration
            let event = "practice:\(descriptorID)"
            if !assessmentEvents.contains(event) { assessmentEvents.append(event) }
        } else if score.outcome == .selfReported {
            assessmentEvents.append("selfReported:\(attemptID.uuidString)")
        } else {
            results.append(score)
            correctness.append(score.isCorrect)
            credits.append(score.credit)
            if let descriptorID = assessmentDescriptor?.id,
               !assessmentDescriptorIDs.contains(descriptorID) {
                assessmentDescriptorIDs.append(descriptorID)
                assessmentEvents.append("answered:\(descriptorID)")
            }
        }
        if let assessmentDescriptor, !isAssessmentPractice {
            assessmentState = assessmentState
                .appending(assessmentDescriptor)
                .recordingResponse(to: assessmentDescriptor, credit: score.credit)
        }
        lastResult = score
        committedAttemptID = attemptID
        hasPreparedCommit = false
        saveError = nil
        reflectionTrigger = store.reflectionTrigger(
            for: score,
            confidence: confidence ?? .uncertain,
            exercise: exercise,
            source: request.source
        )
        if reflectionTrigger != nil {
            suggestedReflectionCode = score.isCorrect
                ? nil
                : NFErrorReflectionCode.candidate(for: score.errorCode, lab: exercise.lab)
            selectedReflectionCode = nil
            reflectionNote = ""
            // The shared coordinator has acknowledged feedback.
        }
    }

    func saveReflection(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.saveReflection(store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canSaveReflection,
              let committedAttemptID,
              let reflectionTrigger,
              let result = lastResult else { return }
        guard checkpointDraft(store: store) else { return }
        do {
            try store.withSessionCommand(try self.sessionWriterCommand(), sessionID: self.sessionID) {
                try store.saveAttemptReflection(
                    attemptID: committedAttemptID,
                    deterministicErrorCode: result.errorCode,
                    selectedErrorCode: selectedReflectionCode,
                    trigger: reflectionTrigger,
                    note: reflectionNote
                )
            }
            saveError = nil
            stage = .feedback
            _ = persistCheckpoint(
                store: store,
                response: encoded(makeResponse()),
                hasCommittedCurrentItem: true
            )
        } catch {
            saveError = NFAppLocalization.localized("The reflection could not be saved. Your scored attempt is safe; retry to continue.", locale: NFAppLocalization.preferredLocale, comment: "Session error shown when a required item reflection could not be saved.")
        }
    }

    func next(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.next(store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard stage == .feedback, !isCommitInFlight, ownsWriter, !hasExited, !isPaused,
              nextUnavailableReason == nil else { return }
        if assessmentSession != nil { advanceProtectedItem(store: store) }
        else { advanceOrdinaryItem(store: store) }
    }

    func skip(store: AppStore, endingAfterAcknowledgement: Bool = false) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.skip(store: store, endingAfterAcknowledgement: endingAfterAcknowledgement)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard (canSkip || pendingSkip), ownsWriter, !isCommitInFlight, !hasExited else { return }
        isCommitInFlight = true
        defer { isCommitInFlight = false }
        if pendingAttemptID == nil { pendingAttemptID = UUID() }
        pendingSkip = true
        responseLockedActiveDuration = responseLockedActiveDuration ?? currentItemActiveDuration()
        guard checkpointDraft(store: store) else { return }
        let activeDuration = currentItemActiveDuration()
        do {
            try store.withSessionCommand(try self.sessionWriterCommand(), sessionID: self.sessionID) {
                try store.saveSkippedExercise(
                    attemptID: pendingAttemptID ?? UUID(),
                    sessionID: sessionID,
                    exercise: exercise,
                    shownAt: shownAt,
                    activeDuration: activeDuration,
                    source: request.source,
                    assessmentBlock: request.assessmentBlock,
                    assessmentDescriptor: assessmentDescriptor,
                    assessmentCycle: request.reassessmentCycle,
                    planID: request.planID,
                    planBlockID: request.planBlockID,
                    interruptionCount: interruptionCount,
                    accommodationFlags: accommodationFlags(store: store),
                    wasTimed: usesTimedMode,
                    revealedSolution: solutionRevealed,
                    draftResponse: solutionRevealed ? encoded(makeResponse()) : "",
                    hintCount: capturedSupportCount,
                    traceInspection: traceInspection, dataInspection: dataInspection, scienceStudy: scienceStudy, transferRelationship: transferRelationship
                )
                #if DEBUG
                self.receiptWriteAcknowledged?()
                #endif
            }
            let skippedID = assessmentDescriptor?.id ?? exercise.id
            let skippedEvent = "\(solutionRevealed ? "revealed" : "skipped"):\(skippedID)"
            if !assessmentEvents.contains(skippedEvent) {
                cumulativeActiveDuration += activeDuration
                assessmentEvents.append(skippedEvent)
            }
            if let descriptor = assessmentDescriptor, assessmentSession != nil {
                assessmentState = assessmentState.appending(descriptor)
            }
            // The acknowledged skip remains a durable pending transition until
            // a next/summary snapshot accepts it. Repeated receipt verification
            // never adds its duration or event a second time.
            saveError = nil
        } catch {
            saveError = "The skip could not be saved. The item remains on screen so no evidence is lost."
            return
        }

        if endingAfterAcknowledgement { endAtSavedBoundary(store: store); return }
        if assessmentSession != nil { advanceProtectedItem(store: store, afterSkip: true); return }

        advanceOrdinaryItem(store: store, afterSkip: true)
    }

    private func advanceOrdinaryItem(store: AppStore, afterSkip: Bool = false) {
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        freezeSittingClock()
        var shortageReason: String?
        var adaptivePreparation: NFLocalAdaptiveItemPreparation?
        var acceptedAdaptiveCheckpoint: NFLocalItemCheckpoint?
        lifecycle.advance(command: afterSkip ? .completedSkip : .next, canMutate: { self.ownsWriter },
            persistCurrent: { self.checkpointDraft(store: store) },
            prepare: { () -> NFSessionLifecycleCoordinator.Advance<NFLocalItemCheckpoint> in
                guard var current = store.localSessions.archive.sessions.first(where: { $0.id == self.sessionID })?.checkpoint else {
                    throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
                }
                if self.index + 1 >= self.itemCount {
                    current.phase = .summary
                    current.pendingOutcome = nil
                    return .summary(current)
                }
                let candidate: NFExercise
                if self.request.ordinaryDelivery?.strategy == .adaptiveItem {
                    do {
                        let preparation = try store.prepareAdaptiveItem(request: self.request, predecessor: current, at: Date(), command: try self.sessionWriterCommand())
                        adaptivePreparation = preparation
                        guard let exact = preparation.checkpoint.exercise else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
                        candidate = exact
                    } catch NFLocalSessionRepository.RepositoryError.unavailableLaunch {
                        let reason = NFLocalSessionRepository.RepositoryError.unavailableLaunch.localizedDescription
                        guard afterSkip else { return .unavailable(reason) }
                        shortageReason = reason
                        current.phase = .summary; current.pendingOutcome = nil; current.endedEarly = true
                        return .summary(current)
                    }
                } else {
                    candidate = Self.makeExercise(request: self.request, index: self.index + 1,
                        assessmentDescriptor: nil, excludingContentFingerprints: self.seenQuestionFingerprints)
                }
                if let reason = candidate.availabilityReason {
                    guard afterSkip else { return .unavailable(reason) }
                    // A skipped item has no answer feedback to retain. Close an
                    // exhausted finite pool with its real acknowledged count.
                    shortageReason = reason
                    current.phase = .summary
                    current.pendingOutcome = nil
                    current.endedEarly = true
                    return .summary(current)
                }
                if self.isTimeBudgetedPractice {
                    let estimate = NFEditorialWorkloadPolicy.runtimeEstimate(reviewedDemand: candidate.contractMetadata?.editorialDemand,
                        legacyExpectedResponseSeconds: nil, mode: self.workloadMode)
                    guard NFEditorialWorkloadPolicy.admission(estimate: estimate,
                        remainingSeconds: self.sittingBudgetSeconds - self.sittingActiveElapsed(), protected: false) == .fits else {
                        current.phase = .summary
                        current.pendingOutcome = nil
                        current.timeBudgetUsed = true
                        return .summary(current)
                    }
                }
                var next = try adaptivePreparation?.checkpoint ?? NFLocalItemCheckpoint.initial(request: self.request, exercise: candidate,
                    slotID: UUID(), attemptID: UUID(), at: Date())
                next.timingConditionOverride = self.timingConditionOverride
                next.index = self.index + 1
                next.itemCount = self.itemCount
                next.scratchpad = self.scratchpad
                next.correctness = self.correctness
                next.credits = self.credits
                next.assessmentDescriptorIDs = self.assessmentDescriptorIDs
                next.assessmentEvents = self.assessmentEvents
                next.cumulativeActiveDuration = self.cumulativeActiveDuration
                next.assessmentPracticeDuration = self.assessmentPracticeActiveDuration
                next.semanticExclusions.formUnion(self.seenQuestionFingerprints)
                next.sittingActiveDuration = self.sittingActiveElapsed()
                next.sittingOrdinal = self.sittingOrdinal
                return .item(next)
            }, persist: { checkpoint in
                self.checkpointDraft(using: {
                    if checkpoint.phase == .item, let preparation = adaptivePreparation {
                        let accepted = try store.acceptAdaptiveItem(preparation, checkpoint: checkpoint)
                        acceptedAdaptiveCheckpoint = accepted.checkpoint
                        self.acknowledgedEnvelopeRevision = accepted.revision
                        self.checkpointRevision += 1
                    } else { try self.persistLocalCheckpointValue(checkpoint, store: store) }
                })
            }, publish: { proposed in
                let checkpoint = acceptedAdaptiveCheckpoint ?? proposed
                if checkpoint.phase == .summary {
                    self.pendingSkip = false
                    self.endedEarly = checkpoint.endedEarly == true
                    self.nextUnavailableReason = shortageReason
                    self.timeBudgetUsed = checkpoint.timeBudgetUsed ?? false
                    self.enterSummary()
                } else if let exactExercise = checkpoint.exercise {
                    self.index = checkpoint.index
                    self.exercise = exactExercise
                    self.seenQuestionFingerprints = checkpoint.semanticExclusions
                    self.prepareNextItem()
                    self.slotID = checkpoint.slotID
                    self.ordinaryReservationDecisionID = checkpoint.ordinaryReservationDecisionID
                    self.pendingAttemptID = checkpoint.attemptID
                    self.shownAt = checkpoint.shownAt
                    self.isDurablyPrepared = true
                }
                // The exact local journal is already durable. The existing
                // SwiftData checkpoint remains a compatibility projection.
                _ = self.checkpointDraft(store: store)
            }, unavailable: { reason in
                self.nextUnavailableReason = reason
                self.saveError = nil
            }, failedPreparation: {
                self.saveError = NFAppLocalization.localizedCatalogValue("We couldn't save this yet. Your answer is still here.", locale: NFAppLocalization.preferredLocale)
            })
    }

    private(set) var reviewedChoice: NFReviewedChallengeChoice?
    private(set) var reviewedChallengeError: String?
    private(set) var reviewedAvailableBands: [NFEditorialBand] = []
    private var separateReviewedCommand: (id: UUID, slotID: UUID, band: NFEditorialBand, writerAuthority: NFLocalWriterAuthority)?
    private(set) var replacementUnavailableReason: String?
    var canReplaceCurrentItem: Bool {
        request.ordinaryDelivery?.strategy == .adaptiveItem && assessmentSession == nil
            && !exercise.assessmentProtected && exercise.evidenceClass == .practice
            && stage == .item && !pendingSkip && !hasPreparedCommit && committedAttemptID == nil
            && ownsWriter && !isPaused && isDurablyPrepared && unavailableReason == nil
    }

    func replaceCurrentItem(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.replaceCurrentItem(store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canReplaceCurrentItem else { return }
        guard checkpointDraft(store: store),
              let saved = store.localSessions.archive.sessions.first(where: { $0.id == sessionID }),
              saved.checkpoint.slotID == slotID else { return }
        do {
            let preparation = try store.prepareAdaptiveReplacement(request: request, predecessor: saved.checkpoint, at: Date(), command: try sessionWriterCommand())
            let accepted = try store.acceptAdaptiveItem(preparation, checkpoint: preparation.checkpoint)
            acknowledgedEnvelopeRevision = accepted.revision
            checkpointRevision += 1
            restoreExactCheckpoint(accepted.checkpoint, freshlyAccepted: true)
            isDurablyPrepared = true
            replacementUnavailableReason = nil
            nextUnavailableReason = nil
            saveError = nil
        } catch NFLocalSessionRepository.RepositoryError.unavailableLaunch {
            replacementUnavailableReason = NFLocalSessionRepository.RepositoryError.unavailableLaunch.localizedDescription
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func prepareNextItem() {
        cancelReviewedChoice()
        separateReviewedCommand = nil
        replacementUnavailableReason = nil
        freezeSittingClock()
        unavailableReason = exercise.availabilityReason
        nextUnavailableReason = nil
        lifecycle.resetForItem()
        isDurablyPrepared = false
        itemPresentationAcknowledged = false
        confidenceInteractionActive = false
        lastResult = nil
        reflectionTrigger = nil
        suggestedReflectionCode = nil
        selectedReflectionCode = nil
        reflectionNote = ""
        committedAttemptID = nil
        shownAt = Date()
        slotID = UUID()
        selectedConfidence = nil
        confidenceResponseIdentity = nil
        solutionRevealed = false
        savedItemActiveDuration = 0
        activeSegmentStart = monotonicNow()
        accumulatedPausedDuration = 0
        pauseStartedAt = nil
        isPaused = false
        // Scratchpad content belongs to the whole chapter/session so the
        // completed review can preserve work spanning more than one item.
        showHint = false
        hintCount = 0
        assistanceEvents = []
        traceInspection = nil
        revisionCount = 0
        inputModality = .unknown
        pointerIsOverResponseControl = false
        pendingAttemptID = nil
        pendingSkip = false
        interruptionCount = 0
        answerDurationComplete = true
        hasPreparedCommit = false
        pendingSelfCheckConfidence = nil
        responseLockedActiveDuration = nil
        prepareInteraction()
    }

    func moveStep(from index: Int, offset: Int) {
        let target = index + offset
        guard orderedStepIDs.indices.contains(index), orderedStepIDs.indices.contains(target) else { return }
        orderedStepIDs.swapAt(index, target)
    }

    func pause(at date: Date = Date()) {
        NFSessionPauseDiagnostics.record(isPaused ? "pause.already-paused" : "pause.request")
        guard stage != .summary, !isPaused else { return }
        savedItemActiveDuration = currentItemActiveDuration()
        freezeSittingClock()
        pauseStartedAt = date
        isPaused = true
        interruptionCount += 1
        NFSessionPauseDiagnostics.record("pause.accepted")
    }

    func resume(at date: Date = Date()) {
        NFSessionPauseDiagnostics.record(isPaused ? "resume.request" : "resume.already-running")
        guard isPaused else { return }
        if let pauseStartedAt { accumulatedPausedDuration += max(0, date.timeIntervalSince(pauseStartedAt)) }
        pauseStartedAt = nil
        activeSegmentStart = monotonicNow()
        isPaused = false
        acknowledgePresented()
        NFSessionPauseDiagnostics.record("resume.accepted")
    }

    func togglePause() { isPaused ? resume() : pause() }

    func advance(store: AppStore) {
        guard !isPaused else { return }
        switch stage {
        case .item:
            submitInline(store: store)
        case .selfCheckComparison:
            saveSelfCheck(store: store)
        case .feedback:
            next(store: store)
        case .confidence, .reflection, .summary:
            break
        }
    }

    @discardableResult
    func checkpointDraft(store: AppStore) -> Bool {
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; _ = self.checkpointDraft(store: store)
        }) { return false }
        guard !hasExited, !durationChoiceRequired else { return false }
        let committed = currentActivityIsAcknowledged
        let complete = hasCompletedRun
        return checkpointDraft(using: {
            let checkpoint = try persistLocalCheckpoint(store: store)
            try mirrorLocalCheckpoint(checkpoint, committed: committed, complete: complete,
                store: store, command: sessionWriterCommand())
        })
    }

    #if DEBUG
    /// Fault boundary after the authoritative local snapshot is saved and
    /// before the legacy session projection. Never used by production flows.
    var legacyCheckpointWriteFailure: (() throws -> Void)?
    var localCheckpointWriteFailure: ((NFLocalItemCheckpoint) throws -> Void)?
    #endif

    @discardableResult
    func checkpointDraftRetainingAcknowledgedStage(store: AppStore, rollback: () -> Void) -> Bool {
        let priorRevision = checkpointRevision
        let saved = checkpointDraft(store: store)
        if !saved {
            if checkpointRevision == priorRevision { rollback() }
            else {
                // The exact local response/help stage already owns this write.
                // Reverting it here would let a later autosave erase a saved
                // prediction or assistance reveal after a projection failure.
                saveError = NFAppLocalization.localizedCatalogValue(
                    "Your work is saved on this device. Its session summary could not be updated; you can retry the save.",
                    locale: NFAppLocalization.preferredLocale)
            }
        }
        return saved
    }

    @discardableResult
    func checkpointDraft(using persist: () throws -> Void) -> Bool {
        guard stage == .item || stage == .confidence || stage == .selfCheckComparison
                || stage == .reflection || stage == .feedback || stage == .summary else {
            return false
        }
        do {
            try persist()
            saveError = nil
            return true
        } catch {
            saveError = NFAppLocalization.localized(
                "This session could not be saved. It remains open so you can retry or explicitly discard the unsaved changes.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Session checkpoint failure that keeps the session open and explains the recovery choices."
            )
            return false
        }
    }

    private(set) var hasExited = false

    var recoveryText: String {
        let response = NFSessionRecoveryText.make(response: request.localCheckpoint.flatMap { unavailableReason == nil ? nil : $0.response } ?? makeResponse(),
            exercise: unavailableReason == nil ? exercise : nil,
            scratchpad: unavailableReason == nil ? scratchpad : request.localCheckpoint?.scratchpad ?? scratchpad,
            reflection: unavailableReason == nil ? reflectionNote : request.localCheckpoint?.reflectionNote ?? reflectionNote)
        let working = unavailableReason == nil ? NFMathWorkPolicy.recoveryText(mathWork, exercise: exercise) : nil
        let trace = traceInspection.map { $0.recoveryText(exercise: exercise) }
        let prediction = unavailableReason == nil ? dataInspection?.recoveryText(exercise: exercise) : nil
        let evidence = unavailableReason == nil ? scienceStudy?.recoveryText(exercise: exercise) : nil
        let relationship = transferRelationship?.recoveryText(exercise: exercise)
        return [response, working, trace, prediction, evidence, relationship].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    func exitDisposition(store: AppStore, saveSucceeded: Bool = false) -> NFSessionExitDisposition {
        if draftSaveGate.isSaving || pendingSubmissionVerification != nil || store.localSessions.archiveWriteVerificationNeeded { return .unacknowledged }
        if unavailableReason != nil || durationChoiceRequired { return .saved }
        let desired = try? currentLocalCheckpoint()
        let acknowledged = store.localSessions.archive.sessions.first { $0.id == sessionID && $0.ownerDeviceID == store.localSessions.ownerDeviceID }
        if let desired, let saved = acknowledged?.checkpoint,
           hasReplayablePreparedFeedback(desired: desired, saved: saved, store: store) { return .pendingCommit }
        return .resolve(saveSucceeded: saveSucceeded,
            exactAcknowledgement: desired != nil && desired == acknowledged?.checkpoint,
            pendingCommit: desired?.pendingOutcome != nil)
    }

    private func hasReplayablePreparedFeedback(desired: NFLocalItemCheckpoint, saved: NFLocalItemCheckpoint,
                                               store: AppStore) -> Bool {
        guard desired.phase == .feedback, saved.phase == .confidence, saved.pendingOutcome == "answer",
              desired.committedAttemptID == saved.attemptID, desired.attemptID == saved.attemptID,
              desired.slotID == saved.slotID, desired.index == saved.index, desired.itemCount == saved.itemCount,
              desired.exercise == saved.exercise, desired.exerciseDigest == saved.exerciseDigest,
              desired.descriptor == saved.descriptor, desired.scorerVersion == saved.scorerVersion,
              desired.response == saved.response, desired.confidence == saved.confidence,
              desired.scratchpad == saved.scratchpad, desired.reflectionNote == saved.reflectionNote,
              desired.selectedReflectionCode == saved.selectedReflectionCode,
              desired.hintCount == saved.hintCount, desired.assistanceEvents == saved.assistanceEvents,
              desired.traceInspection == saved.traceInspection,
              desired.solutionRevealed == saved.solutionRevealed,
              desired.referenceRevealed == saved.referenceRevealed, desired.selfCheckRating == saved.selfCheckRating,
              desired.result == saved.result, desired.protectedCommitReceipt == saved.protectedCommitReceipt,
              desired.timingConditionOverride == saved.timingConditionOverride,
              desired.semanticExclusions == saved.semanticExclusions, desired.mathWork == saved.mathWork, desired.dataInspection == saved.dataInspection, desired.scienceStudy == saved.scienceStudy, desired.transferRelationship == saved.transferRelationship,
              let record = store.attempts.first(where: { $0.id == saved.attemptID }),
              let score = lastResult,
              matchesOriginalReceipt(record, exercise: exercise, response: saved.response,
                  confidence: isSelfCheck ? nil : saved.confidence, descriptor: saved.descriptor),
              record.isCorrect == score.isCorrect, record.deterministicCredit == score.credit,
              record.hintCount == desired.capturedSupportCount else { return false }
        if exercise.assessmentProtected {
            return saved.protectedCommitReceipt?.verifiedScore(for: saved, exercise: exercise) != nil
        }
        let expected = isSelfCheck && exercise.evidenceClass == .documentPractice
            && !exercise.provenance.sourceDocumentIDs.isEmpty ? "" : score.expectedAnswerSummary ?? ""
        return store.exerciseSnapshot(for: record.id) == exercise
            && store.localSessions.archive.snapshots.first(where: { $0.attemptID == record.id })?.traceInspection == desired.traceInspection
            && store.localSessions.archive.snapshots.first(where: { $0.attemptID == record.id })?.dataInspection == desired.dataInspection
            && store.localSessions.archive.snapshots.first(where: { $0.attemptID == record.id })?.scienceStudy == desired.scienceStudy
            && store.localSessions.archive.snapshots.first(where: { $0.attemptID == record.id })?.transferRelationship == desired.transferRelationship
            && record.correctAnswerText == expected && record.errorCode == score.errorCode
    }

    @discardableResult
    func prepareToClose(store: AppStore) -> NFSessionExitDisposition {
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        pause()
        let saved = checkpointDraft(store: store)
        return exitDisposition(store: store, saveSucceeded: saved)
    }

    func finishClosing() {
        pendingSubmissionVerification = nil
        hasExited = true
        saveError = nil
        releaseWriter()
    }

    @discardableResult
    func finish(store: AppStore) -> Bool {
        checkpointDraft(store: store)
    }

    @discardableResult
    private func persistCheckpoint(
        store: AppStore, response: String, hasCommittedCurrentItem: Bool, isComplete: Bool = false
    ) -> Bool { checkpointDraft(store: store) }

    private func persistLocalCheckpoint(store: AppStore) throws -> NFLocalItemCheckpoint {
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard unavailableReason == nil else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
        if writerRepository == nil {
            writerRepository = store.localSessions
            guard store.localSessions.claimWriter(writerID, sessionID: sessionID, checkpoint: { [weak self, weak store] in
                guard let self, let store else { return true }
                return self.checkpointDraft(store: store)
            }) else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
            retainedWriterAuthority = store.localSessions.writerAuthority(for: writerID, sessionID: sessionID)
            activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
            if let saved = store.localSessions.archive.sessions.first(where: { $0.id == sessionID }) {
                guard request.localCheckpoint == saved.checkpoint else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
                acknowledgedEnvelopeRevision = saved.revision
            }
        }
        guard ownsWriter else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
        if pendingAttemptID == nil { pendingAttemptID = UUID() }
        let checkpoint = try currentLocalCheckpoint()
        try persistLocalCheckpointValue(checkpoint, store: store)
        return checkpoint
    }

    private func currentLocalCheckpoint() throws -> NFLocalItemCheckpoint {
        guard pendingSubmissionVerification == nil, !hasUnexpectedPreparedResponseEdit else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
        guard let pendingAttemptID else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
        var checkpoint = NFLocalItemCheckpoint(
            slotID: slotID, attemptID: pendingAttemptID, index: index, itemCount: itemCount,
            phase: stage, exercise: exercise.assessmentProtected ? nil : exercise,
            exerciseDigest: try NFLocalItemCheckpoint.digest(exercise), descriptor: assessmentDescriptor,
            response: makeResponse(), confidence: selectedConfidence, scratchpad: scratchpad,
            hintCount: hintCount, solutionRevealed: solutionRevealed,
            referenceRevealed: selfCheckReferenceRevealed, selfCheckRating: selfCheckRating,
            result: exercise.assessmentProtected ? nil : lastResult, committedAttemptID: committedAttemptID,
            correctness: correctness, credits: credits, assessmentDescriptorIDs: assessmentDescriptorIDs,
            assessmentEvents: assessmentEvents, cumulativeActiveDuration: cumulativeActiveDuration,
            itemActiveDuration: responseLockedActiveDuration ?? currentItemActiveDuration(),
            assessmentPracticeDuration: assessmentPracticeActiveDuration,
            interruptionCount: interruptionCount, revisionCount: revisionCount, inputModality: inputModality,
            reflectionTrigger: reflectionTrigger, suggestedReflectionCode: suggestedReflectionCode,
            selectedReflectionCode: selectedReflectionCode, reflectionNote: reflectionNote,
            semanticExclusions: seenQuestionFingerprints, shownAt: shownAt
        )
        checkpoint.endedEarly = endedEarly
        checkpoint.pendingOutcome = pendingSkip ? (solutionRevealed ? "reveal" : "skip") : (stage == .confidence && lastResult != nil ? "answer" : nil)
        checkpoint.assistanceEvents = assistanceEvents
        checkpoint.mathWork = mathWork
        checkpoint.dataInspection = dataInspection
        checkpoint.scienceStudy = scienceStudy
        checkpoint.transferRelationship = transferRelationship
        checkpoint.traceInspection = traceInspection
        checkpoint.clarificationMessage = clarificationMessage
        checkpoint.timingConditionOverride = timingConditionOverride
        checkpoint.ordinaryReservationDecisionID = ordinaryReservationDecisionID
        checkpoint.sittingActiveDuration = sittingActiveElapsed()
        checkpoint.sittingOrdinal = sittingOrdinal
        checkpoint.awaitingNextSitting = awaitingNextSitting
        checkpoint.assessmentStopReason = assessmentStopReason
        checkpoint.assessmentState = assessmentSession == nil ? nil : assessmentState
        checkpoint.assessmentCatalogSnapshot = assessmentSession
        checkpoint.answerDurationComplete = answerDurationComplete
        checkpoint.timeBudgetUsed = timeBudgetUsed
        if exercise.assessmentProtected, let lastResult {
            checkpoint.protectedCommitReceipt = NFProtectedCommitReceipt(attemptID: pendingAttemptID,
                exercise: exercise, descriptor: assessmentDescriptor, score: lastResult)
            guard checkpoint.protectedCommitReceipt?.verifiedScore(for: checkpoint, exercise: exercise) != nil else {
                throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
            }
        }
        return checkpoint
    }

    private func persistLocalCheckpointValue(_ checkpoint: NFLocalItemCheckpoint, store: AppStore) throws {
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        let command = try sessionWriterCommand()
        if request.timingCondition?.mode == .timedFluency {
            guard let exercise = checkpoint.exercise,
                  let demand = store.localSessions.admittedTimingDemand(request: request, exercise: exercise,
                    slotID: checkpoint.slotID, decisionID: checkpoint.ordinaryReservationDecisionID, profileID: store.profile?.id),
                  (checkpoint.timingConditionOverride ?? request.timingCondition)?.accepts(exercise, reviewedDemand: demand) == true else {
                isDurablyPrepared = false
                throw NFLocalSessionRepository.RepositoryError.unsupportedVersion
            }
            timingAuthorityProfileID = store.profile?.id
        }
        let envelope = try localEnvelope(checkpoint, store: store)
        #if DEBUG
        try localCheckpointWriteFailure?(checkpoint)
        #endif
        try store.localSessions.saveSession(envelope, command: command, expectedRevision: acknowledgedEnvelopeRevision)
        acknowledgeLocalWrite(envelope, store: store)
    }

    private func acknowledgeLocalWrite(_ envelope: NFLocalSessionEnvelope, store: AppStore) {
        acknowledgedEnvelopeRevision = envelope.revision
        checkpointRevision += 1
        store.localSessionRevision += 1
        isDurablyPrepared = true
    }

    private func localEnvelope(_ checkpoint: NFLocalItemCheckpoint, store: AppStore) throws -> NFLocalSessionEnvelope {
        guard request.permitsSpatialAssembly(exercise:checkpoint.exercise),request.permitsCoordinateReasoning(exercise:checkpoint.exercise),request.permitsNetFolding(exercise:checkpoint.exercise),request.permitsSolidSection(exercise:checkpoint.exercise),request.permitsCoordinateTransform(exercise: checkpoint.exercise),request.permitsSpatialStructure(exercise: checkpoint.exercise), request.permitsRetrievalAsset(exercise: checkpoint.exercise), request.permitsRetrievalAuthority(exercise: checkpoint.exercise), checkpoint.hasValidTimingDurations, checkpoint.hasSupportedMathWork, checkpoint.hasSupportedDataInspection, checkpoint.hasSupportedTraceInspection, checkpoint.hasSupportedScienceStudy, request.hasSupportedScienceStudyPolicy, checkpoint.hasSupportedGraphConstruction, request.hasSupportedGraphConstructionPolicy, request.permitsGraphConstruction(exercise: checkpoint.exercise), checkpoint.hasSupportedTransferRelationship, request.supportsTransferRecipe(in: checkpoint), request.hasValidTimingDurations else {
            throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
        }
        var launch = request.launchOnly()
        launch.localCheckpoint = nil
        launch.localSessionID = sessionID
        let complete = checkpoint.phase == .summary && checkpoint.endedEarly != true
            && (assessmentSession == nil
                ? checkpoint.index + 1 >= checkpoint.itemCount || checkpoint.timeBudgetUsed == true
                : checkpoint.assessmentState.map { assessmentSession?.hasSufficientEvidence(in: $0) == true } == true)
        return NFLocalSessionEnvelope(id: sessionID, ownerDeviceID: store.localSessions.ownerDeviceID,
            revision: try NFSessionWriterRevision.next(after: acknowledgedEnvelopeRevision),
            request: launch, checkpoint: checkpoint,
            status: checkpoint.awaitingNextSitting == true ? .suspended
                : checkpoint.endedEarly == true || (checkpoint.phase == .summary && !complete) ? .endedEarly
                : checkpoint.phase == .summary ? .completed : .suspended,
            updatedAt: Date())
    }

    private func enterSummary() {
        freezeSittingClock()
        stage = .summary
        pauseStartedAt = nil
        isPaused = false
        showScratchpad = false
    }

    private func currentItemActiveDuration(at date: Date = Date()) -> TimeInterval {
        if let responseLockedActiveDuration { return responseLockedActiveDuration }
        let delta = isPaused || stage != .item || !itemPresentationAcknowledged || confidenceInteractionActive || draftSaveGate.hasQueuedAction ? 0 : monotonicNow() - activeSegmentStart
        return savedItemActiveDuration + (delta.isFinite ? max(0, delta) : 0)
    }

    private func formatClock(_ interval: TimeInterval) -> String {
        guard NFSessionDurationPolicy.isValid(interval) else {
            return NFAppLocalization.localizedCatalogValue("Timing unavailable", locale: NFAppLocalization.preferredLocale)
        }
        let seconds = Int(interval.rounded(.down))
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    private func prepareInteraction() {
        savedClarificationMessage = nil
        clarificationResponseIdentity = nil
        mathWork = .initial(for: exercise)
        dataInspection = .initial(for: exercise)
        scienceStudy = .initial(for: exercise)
        transferRelationship = .initial(for: exercise)
        numericValue = ""
        numericUnit = ""
        singleChoiceID = nil
        multipleChoiceIDs = []
        shortText = ""
        selfCheckRating = nil
        selfCheckReflection = ""
        selfCheckReferenceRevealed = false
        pendingSelfCheckConfidence = nil
        claimSelections = [:]
        logicState = [:]
        violatedRuleID = nil
        orderedStepIDs = []
        restore(.initialDraft(for: exercise))
    }

    private func makeResponse() -> NFExerciseResponse {
        switch exercise.interaction {
        case .numeric:
            .numeric(NFNumericSubmission(value: numericValue, unit: numericUnit.isEmpty ? nil : numericUnit))
        case .singleChoice:
            .singleChoice(optionID: singleChoiceID ?? "")
        case .multipleChoice:
            .multipleChoice(optionIDs: multipleChoiceIDs.sorted())
        case .orderedSteps:
            .orderedSteps(stepIDs: orderedStepIDs)
        case .shortText:
            .shortText(shortText)
        case .selfCheck:
            .selfCheck(NFSelfCheckSubmission(rating: selfCheckRating ?? .notYet, reflection: selfCheckReflection))
        case .claimEvidence:
            .claimEvidence(NFClaimEvidenceSubmission(pairs: claimSelections.keys.sorted().map {
                NFClaimEvidencePair(claimID: $0, evidenceIDs: claimSelections[$0, default: []].sorted())
            }))
        case .logicState:
            .logicState(NFLogicStateSubmission(finalState: NFMathWorkPolicy.finalState(logicState, draft: mathWork), violatedRuleID: violatedRuleID))
        }
    }

    private func accommodationFlags(store: AppStore) -> [String] {
        var flags: [String] = []
        if store.profile?.hideTimers == true { flags.append("timersHidden") }
        if store.profile?.reducedMotion == true { flags.append("reducedMotion") }
        if store.profile?.excludeVisualSpatial == true { flags.append("visualSpatialExcluded") }
        return flags
    }

    private func encoded<Value: Encodable>(_ response: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(response) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func restore(_ response: NFExerciseResponse) {
        switch response {
        case let .numeric(submission): numericValue = submission.value; numericUnit = submission.unit ?? ""
        case let .singleChoice(optionID): singleChoiceID = optionID
        case let .multipleChoice(optionIDs): multipleChoiceIDs = Set(optionIDs)
        case let .orderedSteps(stepIDs): orderedStepIDs = stepIDs
        case let .shortText(text): shortText = text
        case let .selfCheck(submission):
            selfCheckReflection = submission.reflection ?? ""
            // Draft restoration must never reveal a reference or reuse a rating
            // recorded only after the learner saw that reference.
            selfCheckRating = nil
            selfCheckReferenceRevealed = false
        case let .claimEvidence(submission):
            claimSelections = submission.pairs.reduce(into: [:]) { $0[$1.claimID] = Set($1.evidenceIDs) }
        case let .logicState(submission): logicState = submission.finalState; violatedRuleID = submission.violatedRuleID
        }
    }

    private static func makeExercise(
        request: SessionRequest,
        index: Int,
        assessmentDescriptor: NFAssessmentItemDescriptor?,
        excludingContentFingerprints: Set<String> = []
    ) -> NFExercise {
        NFDeterministicSessionExerciseFactory.makeExercise(
            request: request,
            index: index,
            assessmentDescriptor: assessmentDescriptor,
            excludingContentFingerprints: excludingContentFingerprints.union(request.repairSemanticExclusions ?? [])
        )
    }

    private static func replayAssessmentEvents(
        _ events: [String],
        credits: [Double],
        in session: NFAssessmentBlockSession,
        selfReportedDifficulty: Double
    ) -> NFAdaptiveAssessmentState {
        let candidates = Dictionary(uniqueKeysWithValues: session.candidatePool.map { ($0.id, $0) })
        var state = NFAssessmentEngine.initialAdaptiveState(
            selfReportedDifficulty: selfReportedDifficulty
        )
        var creditIndex = 0
        for event in events {
            guard let separator = event.firstIndex(of: ":") else { continue }
            let kind = String(event[..<separator])
            let descriptorID = String(event[event.index(after: separator)...])
            guard let descriptor = candidates[descriptorID],
                  descriptor.block == session.definition.kind,
                  descriptor.role == session.phase.role else { continue }
            switch kind {
            case "answered":
                guard credits.indices.contains(creditIndex) else { continue }
                state = state
                    .appending(descriptor)
                    .recordingResponse(to: descriptor, credit: credits[creditIndex])
                creditIndex += 1
            case "skipped":
                state = state.appending(descriptor)
            default:
                continue
            }
        }
        return state
    }

    private static func makeAssessmentPracticeDescriptor(
        request: SessionRequest,
        block: NFAssessmentBlockKind
    ) -> NFAssessmentItemDescriptor? {
        NFPracticeItemSelector.select(
            from: NFAssessmentEngine.makePracticeCandidates(block: block, seed: request.seed),
            seed: request.seed,
            excluding: request.quarantinedAssessmentDescriptorIDs
        )
    }
}

struct UniversalSessionView: View {
    private enum AccessibleFocus: Hashable { case prompt, feedback, reference, clarification }

    private enum ResponseFocus: Hashable {
        case numericValue
        case numericUnit
        case shortText
        case selfCheck
        case logic(String)
    }

    @Environment(AppStore.self) private var store
    @Environment(NFTodaySessionSequence.self) private var todaySessionSequence
    @Environment(NFSessionCommandBridge.self) private var sessionCommands
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var runtime: NFUniversalSessionRuntime
    @FocusState private var confidenceHasFocus: Bool
    @State private var saveAndClosePending = false
    @State private var showsAllReflectionReasons = false
    @State private var selectedFeedbackCitation: NFCommittedCitationRoute?
    @FocusState private var responseFocus: ResponseFocus?
    @State private var dataPredictionFocusReset = UUID()
    @AccessibilityFocusState private var accessibleFocus: AccessibleFocus?
    @State private var lastAccessiblePresentation: String?

    init(request: SessionRequest) {
        _runtime = State(initialValue: NFUniversalSessionRuntime(request: request))
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                if runtime.stage != .summary && runtime.isTimingPresentationReady {
                    header
                    Divider().opacity(0.5)
                }
                Group {
                    if !runtime.ownsWriter {
                        ContentUnavailableView {
                            Label("This session is open in another window.", systemImage: "macwindow.on.rectangle")
                        } description: {
                            Text("Take over to continue from that window’s last saved answer.")
                        } actions: { Button("Take over") { runtime.takeOver(store: store) } }
                    } else if runtime.durationChoiceRequired {
                        ContentUnavailableView {
                            Label("Choose a question count", systemImage: "clock.badge.questionmark")
                        } description: {
                            Text("These questions don’t yet have reviewed time estimates. You can choose five questions and work at your own pace.")
                        } actions: {
                            Button("Start 5 questions") { runtime.startCountBasedAlternative(store: store) }
                                .buttonStyle(.borderedProminent)
                            Button("Close") { store.activeSessionRequest = nil; dismiss() }
                        }
                    } else if let reason = runtime.unavailableReason {
                        ContentUnavailableView {
                            Label("Saved work unavailable", systemImage: "doc.badge.ellipsis")
                        } description: {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(verbatim: NFAppLocalization.localizedCatalogValue(reason, locale: NFAppLocalization.preferredLocale))
                                Text(verbatim: runtime.recoveryText).textSelection(.enabled)
                                ShareLink("Export recovery copy", item: runtime.recoveryText)
                            }
                        } actions: {
                            Button("Close") { closeSavedSession() }
                        }
                    } else if !runtime.isDurablyPrepared {
                        VStack(spacing: 16) {
                            ProgressView("Preparing saved question…")
                            if runtime.saveError != nil {
                                Button("Retry preparation") { Task { await runtime.retrySavingAsync(store: store) } }
                            }
                        }
                    } else {
                    Group {
                    switch runtime.stage {
                    case .item, .selfCheckComparison, .feedback: itemView
                    case .confidence: confidenceView
                    case .reflection: reflectionView
                    case .summary: summaryView
                    }
                    }
                    .task(id: runtime.presentationIdentity) {
                        runtime.acknowledgePresented()
                        await focusAcknowledgedPresentation()
                    }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityHidden(runtime.isPaused)
            .disabled(runtime.isPaused)
            if runtime.isPaused {
                pauseOverlay
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("universal-session")
        .nfDesktopPresentationFrame(
            minWidth: dynamicTypeSize.isAccessibilitySize ? 560 : 620,
            idealWidth: 860,
            minHeight: 600,
            idealHeight: 800
        )
        .interactiveDismissDisabled(runtime.stage != .summary || runtime.saveError != nil)
        .sheet(isPresented: $runtime.showScratchpad) { ScratchpadView(text: $runtime.scratchpad, exercise: runtime.exercise) }
        .sheet(item: $selectedFeedbackCitation) { route in
            NFHistoryCitationView(route: route)
        }
        .sheet(isPresented: $runtime.showReport) {
            ReportExerciseView(
                exercise: runtime.exercise,
                assessmentDescriptorID: runtime.assessmentDescriptor?.id
            )
        }
        .sheet(isPresented: Binding(get: { runtime.saveError != nil }, set: { if !$0 { runtime.saveError = nil } })) {
            NFSessionSaveRecoveryView(message: NFAppLocalization.localizedCatalogValue(runtime.saveError ?? "", locale: NFAppLocalization.preferredLocale),
                disposition: runtime.exitDisposition(store: store), recoveryText: runtime.recoveryText,
                retry: {
                    Task {
                        await runtime.retrySavingAsync(store: store)
                        if saveAndClosePending { attemptSaveAndClose() }
                    }
                }, close: { closeSavedSession() }, discard: { discardAndClose() },
                keepOpen: { runtime.saveError = nil; saveAndClosePending = false })
        }
        #if os(macOS)
        .onExitCommand {
            guard !runtime.showScratchpad, !runtime.showReport, selectedFeedbackCitation == nil, runtime.saveError == nil else { return }
            attemptSaveAndClose()
        }
        #endif
        .nfPendingSessionSave(runtime.draftSaveGate)
        .nfSessionCloseGuard(id: runtime.sessionID, saveGate: runtime.draftSaveGate, prepare: {
            runtime.prepareToClose(store: store).permitsClose
        }, close: { closeSavedSession() })
        .task {
            sessionCommands.activate(
                requestID: runtime.request.id,
                capabilities: runtime.commandCapabilities
            )
            runtime.reconcileProtectedReceipt(store: store)
            _ = runtime.checkpointDraft(store: store)
            runtime.reconcilePendingSkip(store: store)
            if runtime.stage == .confidence, !runtime.requiresConfidence || runtime.selectedConfidence != nil {
                await runtime.commitAsync(confidence: runtime.selectedConfidence, store: store)
            }
            focusFirstResponseFieldIfNeeded()
        }
        .onChange(of: runtime.awaitsEstimateLock) { wasWaiting, isWaiting in
            if wasWaiting, !isWaiting, !runtime.isPaused {
                responseFocus = .logic(NFEstimateExactContract.exactKey)
            }
        }
        .task(id: runtime.responseDraftIdentity) {
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard !Task.isCancelled else { return }
            guard runtime.ownsWriter else { return }
            runtime.invalidateConfidenceAfterEdit()
            _ = await runtime.checkpointDraftAsync(store: store)
        }
        .onDisappear {
            runtime.releaseWriter()
            sessionCommands.deactivate(requestID: runtime.request.id)
        }
        .onChange(of: runtime.commandCapabilities) { _, capabilities in
            sessionCommands.update(
                requestID: runtime.request.id,
                capabilities: capabilities
            )
        }
        .onChange(of: scenePhase) { _, phase in
            NFSessionPauseDiagnostics.record(phase == .active ? "scene.active" : phase == .inactive ? "scene.inactive" : "scene.background")
            if phase != .active {
                runtime.pause()
                _ = runtime.checkpointDraft(store: store)
            }
        }
        .onChange(of: confidenceHasFocus) { _, focused in
            if focused { runtime.beginConfidenceInteraction() }
            else { runtime.endConfidenceInteraction() }
        }
        .onChange(of: runtime.stage) { _, stage in
            if stage == .feedback {
                responseFocus = nil
            } else if stage == .summary {
                runtime.showScratchpad = false
                responseFocus = nil
            } else if stage == .reflection {
                showsAllReflectionReasons = false
            } else if stage == .item {
                focusFirstResponseFieldIfNeeded()
            }
        }
        .onChange(of: runtime.clarificationMessage) { _, message in
            if message != nil {
                responseFocus = nil
                Task { @MainActor in
                    await Task.yield()
                    guard runtime.clarificationMessage == message, !runtime.isPaused else { return }
                    accessibleFocus = .clarification
                }
            }
        }
        .modifier(NFSessionReinforcementModifier(
            stage: runtime.stage,
            isCorrect: runtime.exercise.assessmentProtected || runtime.isSelfCheck ? nil : runtime.lastResult?.isCorrect,
            hapticsEnabled: store.profile?.reinforcementHapticsEnabled == true,
            soundEnabled: store.profile?.reinforcementSoundEnabled == true
        ))
        .onReceive(NotificationCenter.default.publisher(for: .neuroForgeTogglePause)) { notification in
            guard notification.object as? UUID == runtime.request.id,
                  runtime.commandCapabilities.canTogglePause else { return }
            runtime.togglePause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .neuroForgeAdvanceUniversalSession)) { notification in
            guard notification.object as? UUID == runtime.request.id,
                  runtime.commandCapabilities.canAdvance else { return }
            if runtime.stage == .item {
                runtime.noteSubmissionControlInputIfNeeded(.keyboard)
            }
            Task { await runtime.advanceAsync(store: store) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .neuroForgeShowScratchpad)) { notification in
            guard notification.object as? UUID == runtime.request.id,
                  runtime.commandCapabilities.canShowScratchpad else { return }
            runtime.showScratchpad = true
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            if usesCompactSessionHeader {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        pauseControl
                        sessionIdentity
                        Spacer(minLength: 0)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            sessionStatus
                            Spacer(minLength: 0)
                            sessionUtilityControls
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            sessionStatus
                            HStack {
                                Spacer(minLength: 0)
                                sessionUtilityControls
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    pauseControl
                    sessionIdentity
                    Spacer(minLength: 0)
                    sessionStatus
                    sessionUtilityControls
                }
            }
            ProgressView(value: runtime.progress)
                .tint(NFTheme.foregroundColor(for: runtime.exercise.lab.colorToken))
                .accessibilityLabel("Session progress")
                .accessibilityValue(Text(verbatim: runtime.positionLabel))
                .accessibilityIdentifier("session-position")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var usesCompactSessionHeader: Bool {
        horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    private var pauseControl: some View {
        Button { runtime.pause() } label: {
            Image(systemName: "pause.fill")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Pause session")
    }

    private var sessionIdentity: some View {
        HStack(spacing: 10) {
            NFIconTile(
                symbol: runtime.exercise.lab.symbol,
                color: NFTheme.color(for: runtime.exercise.lab.colorToken),
                size: 38
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(sessionPurposeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(runtime.exercise.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sessionPurposeTitle: String {
        if runtime.isAssessmentPractice {
            return NFAppLocalization.localized("Practice question · task checked, no skill score", locale: NFAppLocalization.preferredLocale, comment: "Session header distinguishing deterministic practice-task checking from protected skill scoring.")
        }
        if runtime.request.source == .baseline {
            return NFAppLocalization.localized("Starting skill check", locale: NFAppLocalization.preferredLocale, comment: "Session header for the initial skill check.")
        }
        if runtime.request.source == .reassessment {
            return NFAppLocalization.localized("Skill check · round \(runtime.request.reassessmentCycle ?? 1)", locale: NFAppLocalization.preferredLocale, comment: "Session header for a reassessment; the placeholder is the reassessment round.")
        }
        return runtime.exercise.purpose.title
    }

    @ViewBuilder
    private var sessionStatus: some View {
        if runtime.stage != .summary {
            HStack(spacing: 8) {
                Text(runtime.positionLabel)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if runtime.hidesAssessmentTimer {
                    Label("Timer not shown", systemImage: "eye.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Assessment timer is not shown")
                } else if runtime.showsTimer {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if store.profile?.hideTimers == true || !runtime.timerIsVisible {
                            Label("Timer hidden", systemImage: "eye.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(runtime.timerLabel(at: context.date))
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(runtime.timerLabel(at: context.date) == "Time target reached" ? NFTheme.amberForeground : .secondary)
                        }
                    }
                    Button { runtime.toggleTimerVisibility() } label: {
                        Image(systemName: runtime.timerIsVisible ? "eye" : "eye.slash")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.profile?.hideTimers == true)
                    .accessibilityLabel(runtime.timerIsVisible ? "Hide timer" : "Show timer")
                } else {
                    Text("Untimed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Untimed session")
                }
                if !runtime.hidesAssessmentTimer && runtime.stage == .item {
                    Menu("Timing") {
                        Button("Untimed") { runtime.setDisplayTiming(.untimed, store: store) }
                        Button("Elapsed only") { runtime.setDisplayTiming(.elapsedOnly, store: store) }
                    }
                    .font(.caption)
                    .disabled(runtime.hasPreparedCommit)
                }
            }
        }
    }

    private var sessionUtilityControls: some View {
        HStack(spacing: 4) {
            Button { attemptSaveAndClose() } label: {
                Image(systemName: "square.and.arrow.down")
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Save and close session")
            .accessibilityIdentifier("session-header-save-close")
            Button { runtime.showScratchpad = true } label: {
                Image(systemName: "square.and.pencil")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open scratchpad")

            if runtime.stage != .summary {
                Menu {
                    Button("End session") { Task { await runtime.endSessionAsync(store: store) } }
                    if runtime.canReplaceCurrentItem {
                        Button("Replace with another question") { runtime.replaceCurrentItem(store: store) }
                    }
                    if runtime.canSkip {
                        Button { runtime.skip(store: store) } label: {
                            Label("Skip — no score", systemImage: "forward.end")
                        }
                    }
                    if !runtime.exercise.assessmentProtected, runtime.exercise.evidenceClass != .documentPractice {
                        Button("Try a similar question · extra practice") { runtime.retrySimilar(store: store) }
                            .buttonStyle(.bordered)
                    }
                    Button { runtime.showReport = true } label: {
                        Label("Report item", systemImage: "exclamationmark.bubble")
                    }
                    Button { runtime.showScratchpad = true } label: {
                        Label("Scratchpad", systemImage: "square.and.pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Session controls")
            }
        }
    }

    private var itemView: some View {
        ScrollViewReader { scroll in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FlowLayout(spacing: 8) {
                    NFStatusPill(text: runtime.exercise.lab.shortTitle, symbol: runtime.exercise.lab.symbol, color: NFTheme.color(for: runtime.exercise.lab.colorToken))
                }
                NFReviewedChallengeControls(runtime: runtime)
                if let notice = contentLanguageNotice {
                    Label { Text(verbatim: notice) } icon: { Image(systemName: "globe") }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("session-content-language-notice")
                }
                if let context = NFMathWorkPolicy.presentationContext(exercise: runtime.exercise, draft: runtime.mathWork), !context.isEmpty {
                    NFFormattedLearningText(context, font: .subheadline)
                        .foregroundStyle(.secondary)
                }
                if let label = runtime.reviewedSlotLabel {
                    Text(LocalizedStringKey(label)).font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("session-reviewed-role")
                }
                if !runtime.exercise.instructions.isEmpty {
                    Label(runtime.mathWork?.kind == .estimateFirst ? NFAppLocalization.localized("Save an estimate first, then enter the exact result and judge whether it fits your estimate.", locale: NFAppLocalization.preferredLocale, comment: "Two-stage mental calculation instructions.") : runtime.exercise.instructions, systemImage: "list.bullet.clipboard")
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NFTheme.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                NFFormattedLearningText(
                    runtime.exercise.prompt,
                    font: .system(.title2, design: .rounded, weight: .bold)
                )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: runtime.exercise.accessibility.promptAccessibilityLabel))
                    .accessibilityHeading(.h1)
                    .accessibilityIdentifier("session-prompt")
                    .id("session-prompt-anchor")
                    .accessibilityFocused($accessibleFocus, equals: .prompt)
                representationView
                if runtime.stage == .feedback { Text("Your answer").font(.headline) }
                responseView.disabled(!(runtime.canEditDraft || runtime.canRateSelfCheck))
                if let reason = runtime.replacementUnavailableReason {
                    Text(verbatim: NFAppLocalization.localizedCatalogValue(reason, locale: NFAppLocalization.preferredLocale))
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("session-replacement-unavailable")
                }
                if let message = runtime.clarificationMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Review answer format", systemImage: "info.circle").font(.headline)
                        Text(verbatim: message).textSelection(.enabled)
                    }
                    .foregroundStyle(NFTheme.amberForeground)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("session-answer-clarification")
                    .accessibilityFocused($accessibleFocus, equals: .clarification)
                }
                if runtime.stage == .item && !runtime.usesTimedMode && !runtime.isSelfCheck && !runtime.awaitsEstimateLock && !runtime.awaitsScienceEvidence && !runtime.awaitsTransferRelationship {
                    inlineConfidenceView.disabled(!runtime.canEditDraft)
                }
                if !runtime.exercise.assessmentProtected {
                    ForEach(Array(runtime.visibleHints.enumerated()), id: \.offset) { _, hint in
                        Label(hint, systemImage: "lightbulb.fill")
                            .font(.subheadline).foregroundStyle(NFTheme.amberForeground)
                    }
                    if runtime.solutionRevealed && runtime.stage != .feedback {
                        Text("Worked solution · learning only").font(.headline)
                        Text(runtime.exercise.feedback.correctExplanation)
                        Text("This revealed question is not independently scored.").font(.footnote)
                        Button("Continue practice") { runtime.skip(store: store) }
                    }
                }
                if runtime.stage != .feedback {
                if runtime.hasOptionalMathWorking {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(runtime.mathWork?.workingExpanded == true ? "Hide optional working" : "Show optional working") {
                            runtime.toggleMathWorking(store: store)
                        }.buttonStyle(.bordered).disabled(!runtime.canEditDraft)
                        if runtime.mathWork?.workingExpanded == true, let contract = runtime.mathWorkingContract {
                            NFMathWorkingFields(contract: contract, values: runtime.mathWork?.workingValues ?? [],
                                isEditable: runtime.canEditDraft, update: { runtime.setMathWorkingValue($1, at: $0) })
                        }
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack { answerActions }
                    VStack(alignment: .leading, spacing: 12) { answerActions }
                }
                .disabled(runtime.hasSavedSkipAwaitingAdvance)
                if let message = runtime.responseValidationMessage, !runtime.canSubmit {
                    Label {
                        Text(verbatim: message)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("session-response-requirement")
                }
                Text(
                    runtime.stage == .selfCheckComparison
                        ? "Compare your answer with the reference, then rate the match."
                        : selfCheckPreReferenceFooter
                )
                    .font(.footnote).foregroundStyle(.tertiary)
                }
                if runtime.stage == .feedback {
                    feedbackContent.id("session-feedback-anchor")
                }
                if runtime.isAssessmentPractice {
                    Label(
                        "Practice item — this does not affect your starting level.",
                        systemImage: "checkmark.shield"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if runtime.stage == .feedback {
                feedbackFooter
            } else if runtime.hasSavedSkipAwaitingAdvance {
                VStack(alignment: .leading, spacing: 12) {
                    Text(runtime.solutionRevealed
                        ? "Solution viewing saved. Continue when saving is available."
                        : "Skip saved. Continue when saving is available.")
                        .font(.subheadline)
                        .accessibilityIdentifier("session-saved-skip-awaiting-advance")
                    HStack {
                        Button("Retry advance") { runtime.skip(store: store) }
                            .accessibilityIdentifier("session-retry-skip-advance")
                        Button("End session") { Task { await runtime.endSessionAsync(store: store) } }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(.bar)
            } else if !runtime.solutionRevealed {
                submitAnswerButton
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(.bar)
            }
        }
        .task(id: runtime.presentationIdentity) {
            guard runtime.isDurablyPrepared, !runtime.isPaused else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            if runtime.stage == .feedback { scroll.scrollTo("session-feedback-anchor", anchor: .top) }
            else if runtime.stage == .item { scroll.scrollTo("session-prompt-anchor", anchor: .top) }
        }
        }
    }

    @ViewBuilder
    private var answerActions: some View {
        if !runtime.awaitsTransferRelationship, !runtime.exercise.assessmentProtected, runtime.displayedHint != nil, !runtime.solutionRevealed {
            Button {
                if runtime.hintCount < runtime.activeHintLadder.count {
                    runtime.requestHint(store: store)
                } else { runtime.revealSolution(store: store) }
            } label: {
                Text(LocalizedStringKey(runtime.hintActionTitle))
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.bordered)
        }
        if runtime.canSkip {
            Button { runtime.skip(store: store) } label: {
                Text(runtime.solutionRevealed ? "Continue after solution" : "Skip — no score")
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.bordered)
        }
    }

    private var submitAnswerButton: some View {
            Button(LocalizedStringKey(runtime.awaitsTransferRelationship ? "Save relationship and continue" : runtime.awaitsScienceEvidence ? "Save evidence and continue" : runtime.awaitsEstimateLock ? "Save estimate and continue" : runtime.stage == .selfCheckComparison ? "Save self-check" : "Submit response")) { submitCurrentResponse() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!runtime.canSubmit || !runtime.isDurablyPrepared || (runtime.requiresConfidence && runtime.selectedConfidence == nil))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("session-submit")
    }

    @ViewBuilder
    private var inlineConfidenceView: some View {
        if runtime.requiresConfidence || runtime.confidenceInvitation {
            confidenceChoices
        } else {
            DisclosureGroup { confidenceChoices } label: {
                Text("Confidence (optional)").frame(minHeight: 44).contentShape(Rectangle())
            }
        }
    }

    private var confidenceChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(runtime.requiresConfidence ? "How confident are you? Choose one." : "How confident are you? (optional)")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                ForEach(ConfidenceLevel.allCases) { confidence in
                    Button {
                        runtime.beginConfidenceInteraction()
                        runtime.chooseConfidence(confidence)
                        confidenceHasFocus = false
                    } label: {
                        HStack {
                            Image(systemName: runtime.selectedConfidence == confidence ? "checkmark.circle.fill" : "circle")
                            Text(confidence.title)
                        }.frame(minHeight: 44)
                    }.buttonStyle(.bordered).nfSelectionAccessibility(runtime.selectedConfidence == confidence)
                        .focused($confidenceHasFocus)
                }
            }
        }
    }

    private var selfCheckPreReferenceFooter: String {
        if case .selfCheck = runtime.exercise.interaction {
            return "Write what you recall, then compare it with the reference."
        }
        return runtime.requiresConfidence ? "Choose confidence, then submit your answer." : "Confidence is optional. Your answer determines the result."
    }

    @ViewBuilder
    private var responseView: some View {
        switch runtime.exercise.interaction {
        case let .numeric(schema):
            HStack(spacing: 12) {
                TextField(schema.placeholder, text: $runtime.numericValue)
                    .accessibilityIdentifier("session-numeric-answer")
                    .textFieldStyle(.roundedBorder).font(.title2.monospacedDigit()).numericKeyboard()
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .focused($responseFocus, equals: .numericValue)
                    .simultaneousGesture(TapGesture().onEnded { responseFocus = .numericValue })
                    .submitLabel(schema.answer.unitRequired ? .next : .done)
                    .onSubmit {
                        if schema.answer.unitRequired,
                           runtime.numericUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            responseFocus = .numericUnit
                        } else {
                            submitCurrentResponse()
                        }
                    }
                    .onChange(of: runtime.numericValue) { oldValue, newValue in
                        if oldValue != newValue { runtime.noteTextResponseInput() }
                    }
                if schema.answer.canonicalUnit != nil {
                    TextField("Unit", text: $runtime.numericUnit)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 150, minHeight: 44)
                    .contentShape(Rectangle())
                    .focused($responseFocus, equals: .numericUnit)
                    .simultaneousGesture(TapGesture().onEnded { responseFocus = .numericUnit })
                    .submitLabel(.done)
                    .onSubmit { submitCurrentResponse() }
                    .onChange(of: runtime.numericUnit) { oldValue, newValue in
                        if oldValue != newValue { runtime.noteTextResponseInput() }
                    }
                }
            }
        case let .singleChoice(schema):
            choiceGrid(schema.options, multiple: false)
        case let .multipleChoice(schema):
            VStack(alignment: .leading, spacing: 10) {
                Text("Select all that apply").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                choiceGrid(schema.options, multiple: true)
            }
        case let .orderedSteps(schema):
            NFOrderedResponseEditor(schema: schema, order: $runtime.orderedStepIDs,
                isEditable: runtime.canEditDraft, permitsEditing: { runtime.canEditDraft },
                onInput: { runtime.noteDiscreteResponseInput() },
                onHover: { runtime.setPointerOverResponseControl($0) })
                .id("ordered-\(runtime.sessionID)-\(runtime.responseEditorSlotID)")
        case let .shortText(schema):
            VStack(alignment: .trailing, spacing: 6) {
                TextEditor(text: $runtime.shortText)
                    .accessibilityLabel("Your answer")
                    .focused($responseFocus, equals: .shortText)
                    .frame(minHeight: 130)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .onChange(of: runtime.shortText) { oldValue, newValue in
                        if oldValue != newValue { runtime.noteTextResponseInput() }
                    }
                Text("\(runtime.shortText.count) / \(schema.maximumCharacters)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(runtime.shortText.count > schema.maximumCharacters ? NFTheme.roseForeground : .secondary)
                    .accessibilityLabel(NFAppLocalization.localized(
                        "\(NFAppLocalization.formattedCharacterCount(runtime.shortText.count)) of \(NFAppLocalization.formattedCharacterCount(schema.maximumCharacters))",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Short-text character usage with localized current and maximum character counts."
                    ))
            }
        case let .selfCheck(schema):
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    runtime.selfCheckReferenceRevealed
                        ? "Compare your answer with the reference, then rate the match."
                        : "Answer from memory before seeing the reference. Confidence is optional."
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $runtime.selfCheckReflection)
                .accessibilityLabel("Your answer from memory")
                .focused($responseFocus, equals: .selfCheck)
                .frame(minHeight: 110)
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .disabled(!runtime.canEditDraft)
                .onChange(of: runtime.selfCheckReflection) { oldValue, newValue in
                    if oldValue != newValue { runtime.noteTextResponseInput() }
                }
                if runtime.selfCheckReferenceRevealed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reference answer")
                            .font(.caption.weight(.semibold))
                            .accessibilityFocused($accessibleFocus, equals: .reference)
                        NFFormattedLearningText(schema.referenceAnswer, font: .body)
                            .textSelection(.enabled)
                        Text("Check your recall against:")
                            .font(.caption.weight(.semibold))
                        ForEach(schema.criteria, id: \.self) { criterion in
                            Label(criterion, systemImage: "checkmark")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)

                    ForEach(NFSelfCheckRating.allCases, id: \.rawValue) { rating in
                        let selected = runtime.selfCheckRating == rating
                        Button {
                            runtime.noteDiscreteResponseInput()
                            runtime.selfCheckRating = rating
                        } label: {
                            HStack { Image(systemName: selected ? "checkmark.circle.fill" : "circle"); Text(ratingTitle(rating)); Spacer() }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .tint(selected ? NFTheme.indigo : .secondary)
                        .disabled(!runtime.canRateSelfCheck)
                        .nfSelectionAccessibility(selected)
                        .onHover(perform: runtime.setPointerOverResponseControl)
                    }
                }
            }
        case let .claimEvidence(schema):
            if let draft = runtime.scienceStudy {
                NFScienceStudyEditor(exercise: runtime.exercise, draft: draft, selection: runtime.claimSelections,
                    canEdit: runtime.canEditDraft, updateSelection: { runtime.setScienceSelection($0) },
                    onInput: { runtime.noteDiscreteResponseInput() })
            } else {
                NFClaimEvidenceEditor(schema: schema, selection: $runtime.claimSelections, onInput: runtime.noteDiscreteResponseInput)
            }
        case let .logicState(schema):
            if let graph = runtime.graphConstruction, let inputIdentity = runtime.graphInputIdentity {
                NFGraphConstructionEditor(graph: graph, response: runtime.graphResponse,
                    canEdit: runtime.canEditDraft, revealsExpected: runtime.stage == .feedback && runtime.hasCommittedFeedback,
                    updateResponse: { runtime.setGraphResponse($0, expectedInputIdentity: inputIdentity) })
                    .id(inputIdentity)
            } else {
            if let draft = runtime.transferRelationship {
                NFTransferRelationshipEditor(exercise: runtime.exercise, draft: draft, response: runtime.transferResponse,
                    canEdit: runtime.canEditDraft, choose: { runtime.setTransferRelationship($0) }, enterTotal: { runtime.setTransferTotal($0) },
                    onInput: { runtime.noteDiscreteResponseInput() }, onSubmit: { submitCurrentResponse() })
            } else {
            VStack(alignment: .leading, spacing: 14) {
                if let estimate = runtime.mathWork?.lockedEstimate {
                    LabeledContent("Estimate saved before exact work", value: estimate)
                        .accessibilityIdentifier("math-locked-estimate")
                } else if runtime.awaitsEstimateLock {
                    Text("First save your estimate. The exact-result fields open afterward.").font(.subheadline)
                }
                ForEach(runtime.visibleLogicKeys(schema), id: \.self) { key in
                    let responseLabel = runtime.exercise.contractMetadata?.coordinateReasoning.flatMap { _ in
                        NFCoordinateReasoningContract.make(exercise: runtime.exercise).map { $0.responseLabel(key) }
                    } ?? NFCoordinateTransformContract.make(exercise: runtime.exercise).map {
                        $0.text("\(key) (grid units)", "\(key)（格子単位）")
                    } ?? NFMathWorkPolicy.responseLabel(for: key, draft: runtime.mathWork)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Response for \(responseLabel)").font(.subheadline.bold())
                        TextField("Response for \(responseLabel)", text: Binding(
                            get: { runtime.logicState[key, default: ""] },
                            set: {
                                runtime.logicState[key] = $0
                                runtime.noteTextResponseInput()
                            }
                        ))
                            .textFieldStyle(.roundedBorder)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                            .focused($responseFocus, equals: .logic(key))
                            .simultaneousGesture(TapGesture().onEnded { responseFocus = .logic(key) })
                            .submitLabel(.next)
                            .onSubmit { focusNextLogicField(after: key, schema: schema) }
                        .accessibilityLabel("Response for \(responseLabel)")
                    }
                }
                if !schema.ruleOptions.isEmpty {
                    Text("Violated invariant").font(.headline)
                    ForEach(schema.ruleOptions) { option in
                        let selected = runtime.violatedRuleID == option.id
                        Button {
                            runtime.noteDiscreteResponseInput()
                            runtime.violatedRuleID = option.id
                        } label: {
                            HStack { Image(systemName: selected ? "checkmark.circle.fill" : "circle"); Text(option.text); Spacer() }
                        }
                        .buttonStyle(.bordered)
                        .nfSelectionAccessibility(selected)
                        .onHover(perform: runtime.setPointerOverResponseControl)
                    }
                }
            }
            }
            }
        }
    }

    @ViewBuilder
    private func choiceGrid(_ options: [NFChoiceOption], multiple: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
            ForEach(options) { option in
                let selected = multiple ? runtime.multipleChoiceIDs.contains(option.id) : runtime.singleChoiceID == option.id
                Button {
                    runtime.noteDiscreteResponseInput()
                    if multiple {
                        if selected { runtime.multipleChoiceIDs.remove(option.id) } else { runtime.multipleChoiceIDs.insert(option.id) }
                    } else { runtime.singleChoiceID = option.id }
                } label: {
                    HStack(alignment: .top) {
                        Image(systemName: multiple ? (selected ? "checkmark.square.fill" : "square") : (selected ? "largecircle.fill.circle" : "circle"))
                        NFFormattedLearningText(option.text)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }.padding(14).frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                        .background(selected ? NFTheme.indigo.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.accessibilityLabel ?? option.text)
                .nfSelectionAccessibility(selected)
                .onHover(perform: runtime.setPointerOverResponseControl)
            }
        }
    }

    @ViewBuilder
    private var representationView: some View {
        if let asset = NFRetrievalAssetContract.make(exercise: runtime.exercise) { NFRetrievalAssetStimulusView(asset: asset) }
        ForEach(Array((runtime.graphConstruction == nil && runtime.exercise.contractMetadata?.retrievalAsset == nil ? runtime.exercise.independentRepresentations : []).enumerated()), id: \.offset) { _, representation in
            if let data = NFInspectableDataProjection.make(exercise: runtime.exercise, representation: representation) {
                VStack(alignment: .leading, spacing: 12) {
                    NFDataInspectionView(data: data, controlledPointID: runtime.dataInspection?.selectedPointID,
                        onSelect: runtime.dataInspection == nil || !runtime.canEditDraft ? nil : { runtime.selectDataPoint($0, store: store) },
                        highlightPointID: runtime.dataInspection?.overlayExpanded == true ? data.points.first?.id : nil,
                        onBeginInspection: { responseFocus = nil; dataPredictionFocusReset = UUID() })
                    if let draft = runtime.dataInspection {
                        NFDataPredictionView(draft: draft, exercise: runtime.exercise, canEdit: runtime.canEditDraft,
                            setPrediction: { runtime.setDataPrediction($0) },
                            reveal: { _ = runtime.revealDataExplanation(store: store) },
                            toggleOverlay: { runtime.toggleDataExplanation(store: store) }, focusResetToken: dataPredictionFocusReset)
                    }
                }
            } else {
            switch representation {
            case let .table(headers, rows, summary):
                let accessibilityModel = NFExerciseTableAccessibilityModel(
                    headers: headers,
                    rows: rows,
                    authoredSummary: summary
                )
                VStack(spacing: 0) {
                    HStack {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                            Text(header)
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                    .background(.secondary.opacity(0.1))
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack { ForEach(Array(row.enumerated()), id: \.offset) { _, cell in Text(cell).frame(maxWidth: .infinity, alignment: .leading) } }.padding(10)
                        Divider()
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityRepresentation {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: accessibilityModel.summary)
                            .accessibilityHeading(.h2)
                        ForEach(0..<accessibilityModel.columnCount, id: \.self) { columnIndex in
                            Text(verbatim: accessibilityModel.headerLabel(columnIndex: columnIndex))
                                .accessibilityHeading(.h3)
                        }
                        ForEach(rows.indices, id: \.self) { rowIndex in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: accessibilityModel.rowLabel(rowIndex: rowIndex))
                                    .accessibilityHeading(.h3)
                                ForEach(0..<accessibilityModel.columnCount, id: \.self) { columnIndex in
                                    Text(verbatim: accessibilityModel.cellLabel(
                                        rowIndex: rowIndex,
                                        columnIndex: columnIndex
                                    ))
                                }
                            }
                            .accessibilityElement(children: .contain)
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            case let .equation(latex, spoken):
                NFFormattedLearningText("$$\n\(latex)\n$$", font: .title3.monospaced())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: spoken))
            case let .code(language, source, summary):
                if let trace = runtime.codeTraceProjection, trace.contract.source == source {
                    NFCodeTraceView(projection: trace, draft: runtime.traceInspection,
                        canInspect: runtime.canEditDraft, predictionIsReady: runtime.canSubmit,
                        perform: { action in
                            if case .predict = action { } else { responseFocus = nil }
                            runtime.inspectCode(action, store: store)
                        })
                } else {
                NFFormattedLearningText("```\(language)\n\(source)\n```")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: summary))
                }
            case let .spatial(metadata):
                NFSpatialDiagramView(
                    metadata: metadata,
                    localeIdentifier: runtime.exercise.localeIdentifier,
                    prefersReducedMotion: store.profile?.reducedMotion == true,
                    exercise: runtime.exercise,
                    learningPhase: runtime.hasCommittedFeedback
                        ? .committedFeedback : runtime.solutionRevealed ? .savedWorkedSolution : .independent
                )
            case let .logicState(metadata):
                VStack(alignment: .leading, spacing: 6) { ForEach(metadata.transitions) { transition in Text("\(transition.condition) → \(transition.mutation)").font(.body.monospaced()) } }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            case .prose: EmptyView()
            }
            }
        }
    }

    private var confidenceView: some View {
        ScrollView {
            VStack(spacing: 20) {
                NFIconTile(symbol: "gauge.with.dots.needle.50percent", color: NFTheme.cyan, size: 66)
                Text("How confident are you?")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .accessibilityHeading(.h1)
                Text("How confident are you in this answer?").foregroundStyle(.secondary)
                ForEach(ConfidenceLevel.allCases) { level in
                    Button { Task { await runtime.commitAsync(confidence: level, store: store) } } label: {
                        HStack { ConfidenceGlyph(level: level); Text(level.title).font(.headline); Spacer(); Image(systemName: "chevron.right") }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(runtime.isCommitInFlight)
                }
                if runtime.exercise.responseEditPolicy == .editableBeforeCommit {
                    Button("Edit response") { runtime.editResponse() }
                        .buttonStyle(.bordered)
                        .disabled(runtime.isCommitInFlight)
                } else {
                    Label("Response locked after submit", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
    }

    private var reflectionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NFFormattedLearningText(runtime.exercise.prompt, font: .title2)
                Text(verbatim: runtime.readableAnswer).textSelection(.enabled)
                NFIconTile(symbol: "text.bubble.fill", color: NFTheme.amber, size: 66)
                Text(runtime.reflectionTrigger?.title ?? NFAppLocalization.localized("Brief reflection", locale: NFAppLocalization.preferredLocale, comment: "Fallback title for an item-level reflection."))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .accessibilityHeading(.h1)
                if runtime.reflectionTrigger == .weeklyTransfer {
                    Text("Which structure carried over, or what made the unfamiliar context difficult?")
                        .foregroundStyle(.secondary)
                    TextField("What did you transfer?", text: $runtime.reflectionNote, axis: .vertical)
                        .accessibilityLabel("Reflection note")
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                } else {
                    Text("Think about the correction. You can choose a reason, write a note, or leave this for later.")
                        .foregroundStyle(.secondary)
                    if let candidate = runtime.suggestedReflectionCode {
                        LabeledContent("Suggested reason", value: candidate.title)
                            .nfCard(cornerRadius: 16, padding: 14)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Likely reasons")
                            .font(.headline)
                            .accessibilityHeading(.h2)
                        ForEach(primaryReflectionReasons) { code in
                            reflectionReasonButton(code)
                        }
                    }
                    .nfCard(cornerRadius: 16, padding: 14)

                    DisclosureGroup("More reasons", isExpanded: $showsAllReflectionReasons) {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(NFErrorReflectionGroup.allCases) { group in
                                let choices = group.choices.filter { !primaryReflectionReasons.contains($0) }
                                if !choices.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(group.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        ForEach(choices) { code in
                                            reflectionReasonButton(code)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 12)
                    }
                    .nfCard(cornerRadius: 16, padding: 14)
                    TextField("Optional: what will you check next time?", text: $runtime.reflectionNote, axis: .vertical)
                        .accessibilityLabel("Reflection note")
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                }
                Text(reflectionCharacterCountMessage)
                    .font(.caption)
                    .foregroundStyle(
                        runtime.reflectionNote.count > AttemptReflectionRecord.maximumNoteCharacters
                            ? NFTheme.roseForeground
                            : .secondary
                    )
                Text("This note helps tailor review; it does not change your score.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                Button("Not sure yet") { runtime.dismissReflection(); _ = runtime.checkpointDraft(store: store) }
                    .buttonStyle(.bordered)
                Button("Save reflection") {
                    runtime.saveReflection(store: store)
                }
                .buttonStyle(.borderedProminent)
                .tint(NFTheme.controlTint(for: "indigo"))
                .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!runtime.canSaveReflection)
            }
            .padding(24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }

    private var reflectionCharacterCountMessage: String {
        let remaining = AttemptReflectionRecord.maximumNoteCharacters - runtime.reflectionNote.count
        return remaining >= 0
            ? NFAppLocalization.formattedCharactersRemaining(remaining)
            : NFAppLocalization.formattedCharactersOverLimit(-remaining)
    }

    private var primaryReflectionReasons: [NFErrorReflectionCode] {
        NFErrorReflectionCode.conciseChoices(
            candidate: runtime.suggestedReflectionCode,
            lab: runtime.exercise.lab
        )
    }

    private func reflectionReasonButton(_ code: NFErrorReflectionCode) -> some View {
        let isSelected = runtime.selectedReflectionCode == code
        return Button {
            runtime.selectedReflectionCode = code
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? NFTheme.indigoForeground : .secondary)
                Text(code.title)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .nfSelectionAccessibility(isSelected)
    }

    @ViewBuilder
    private var feedbackContent: some View {
                if let result = runtime.lastResult {
                    HStack(spacing: 14) {
                        NFIconTile(
                            symbol: result.feedback.isDelayed ? "lock.fill" : (result.isCorrect ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"),
                            color: result.feedback.isDelayed ? NFTheme.indigo : (result.isCorrect ? NFTheme.mint : NFTheme.amber),
                            size: 62
                        )
                        VStack(alignment: .leading) {
                            Text(result.feedback.title)
                                .font(.title.bold())
                                .accessibilityHeading(.h1)
                                .accessibilityIdentifier("session-feedback-title")
                                .accessibilityFocused($accessibleFocus, equals: .feedback)
                            Text(feedbackCreditLabel(for: result))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(result.feedback.explanation).font(.title3)
                    if let trigger = runtime.reflectionTrigger {
                        Button("Reflect on this answer (optional)") { runtime.reflect() }
                        Label(
                            NFAppLocalization.localized("Optional \(trigger.title.lowercased()) helps you plan your next attempt.", locale: NFAppLocalization.preferredLocale, comment: "Confirmation that an item reflection was saved without changing the score; the placeholder is the localized reflection trigger title."),
                            systemImage: "checkmark.message.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(NFTheme.mintForeground)
                    }
                    if let decisive = result.feedback.decisiveStep { Label(decisive, systemImage: "scope").nfCard(cornerRadius: 16, padding: 14) }
                    if let expected = result.expectedAnswerSummary { LabeledContent("Expected", value: expected).nfCard(cornerRadius: 16, padding: 14) }
                    if !result.feedback.isDelayed, let explanation = NFObservedProportionExplanation.make(exercise: runtime.exercise) {
                        VStack(alignment: .leading, spacing: 12) {
                            if let prediction = runtime.dataInspection?.firstPrediction {
                                LabeledContent("Prediction saved before explanation (%)", value: prediction.value)
                            }
                            NFDataDenominatorExplanationView(explanation: explanation)
                        }.nfCard().accessibilityIdentifier("session-data-feedback-explanation")
                    }
                    if let draft = runtime.transferRelationship, !result.feedback.isDelayed {
                        NFTransferSavedRelationshipView(exercise: runtime.exercise, draft: draft)
                        NFTransferRelationshipDebriefView(exercise: runtime.exercise)
                    }
                    if runtime.hasCommittedFeedback, !result.feedback.isDelayed,
                       let graph = NFGraphConstructionHistoryProjection.make(exercise: runtime.exercise, response: runtime.graphResponse, isProtected: runtime.exercise.assessmentProtected) {
                        NFGraphConstructionFeedbackView(projection: graph)
                    }
                    if runtime.scienceStudy != nil, !result.feedback.isDelayed {
                        NFScienceStudyFeedbackView(exercise: runtime.exercise, response: runtime.scienceResponse)
                    }
                    if let diagnostic = runtime.calculationChainDiagnostic {
                        DisclosureGroup("Replay the saved calculation steps") {
                            VStack(alignment: .leading, spacing: 9) {
                                Text("This diagnostic is score-preserving: it reconstructs the seeded steps but never changes the submitted attempt.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let index = diagnostic.firstMismatchedCheckpoint {
                                    Text("Recheck your entered value after step \(index + 1).").font(.subheadline.bold())
                                }
                                ForEach(diagnostic.checkpoints) { checkpoint in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text("\(checkpoint.index + 1)")
                                            .font(.caption.bold().monospacedDigit())
                                            .frame(width: 24, height: 24)
                                            .background(NFTheme.indigo.opacity(0.12), in: Circle())
                                        Text(checkpoint.operation.instruction)
                                        Spacer()
                                        Text("\(checkpoint.input.canonicalString) → \(checkpoint.output.canonicalString)")
                                            .font(.body.monospaced())
                                    }
                                }
                            }
                            .padding(.top, 10)
                        }
                        .nfCard(cornerRadius: 16, padding: 14)
                    }
                    if let context = runtime.committedCitationContext(store: store) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sources").font(.headline)
                            ForEach(context.citations) { citation in
                                Button { selectedFeedbackCitation = context.route(for: citation.id) } label: {
                                    Label(citation.title, systemImage: "doc.text.magnifyingglass")
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("session-feedback-citation-" + citation.id)
                            }
                        }.nfCard(cornerRadius: 16, padding: 14)
                    }
                    Button { runtime.showReport = true } label: {
                        Label("Report item", systemImage: "exclamationmark.bubble")
                    }
                    .buttonStyle(.bordered)
                }
    }

    private var feedbackFooter: some View {
            VStack(alignment: .leading, spacing: 12) {
                if let reason = runtime.nextUnavailableReason {
                    Text(verbatim: NFAppLocalization.localizedCatalogValue(reason, locale: NFAppLocalization.preferredLocale))
                        .font(.subheadline)
                        .accessibilityIdentifier("session-next-unavailable")
                }
                HStack {
                    Button(runtime.nextActionTitle) { runtime.next(store: store) }
                        .accessibilityIdentifier("session-next")
                        .foregroundStyle(runtime.nextUnavailableReason == nil
                            ? NFTheme.controlForeground(for: "indigo") : Color.secondary)
                        .disabled(runtime.nextUnavailableReason != nil)
                    if runtime.nextUnavailableReason != nil {
                        Button("End session") { Task { await runtime.endSessionAsync(store: store) } }
                            .accessibilityIdentifier("session-end-unavailable")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(NFTheme.controlTint(for: "indigo"))
                .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(.bar)
    }

    private var summaryView: some View {
        ScrollView {
            VStack(spacing: 20) {
                let assessmentComplete = runtime.hasCompletedRun
                let nextTodayBlock = todaySessionSequence.nextBlock(
                    after: runtime.request.planBlockID,
                    planID: runtime.request.planID,
                    store: store
                )
                NFIconTile(
                    symbol: assessmentComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                    color: assessmentComplete ? NFTheme.mint : NFTheme.amber,
                    size: 78
                )
                Text(runtime.awaitingNextSitting ? "Saved for your next sitting" : runtime.timeBudgetUsed ? "Time target reached" : runtime.endedEarly ? "Ended after \(runtime.presentedCount) of \(runtime.itemCount) questions" : assessmentComplete ? "Session complete" : "More answers needed")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .accessibilityHeading(.h1)
                if !runtime.isSelfCheck && !runtime.exercise.assessmentProtected {
                Grid(horizontalSpacing: 22, verticalSpacing: 8) {
                    GridRow {
                        summaryCount(value: runtime.correctCount, label: "Correct")
                        summaryCount(value: runtime.incorrectCount, label: "Incorrect")
                    }
                    GridRow {
                        summaryCount(value: runtime.skippedCount, label: "Skipped")
                        if runtime.revealedCount > 0 { summaryCount(value: runtime.revealedCount, label: "Solution viewed") }
                        summaryCount(value: runtime.presentedCount, label: "Presented")
                    }
                }
                .accessibilityElement(children: .combine)
                } else {
                    Text(runtime.isSelfCheck ? "Personal study saved · self-reported match" : "Skill-check answers saved. Review your overall skill guidance in Progress.")
                        .foregroundStyle(.secondary)
                }
                Text(runtime.awaitingNextSitting ? "Your answers and remaining coverage are saved. Continue this same skill check in another sitting; your questions won’t be rerolled. The time estimate is advisory." : runtime.timeBudgetUsed ? "Your submitted answers are saved. There isn’t enough estimated time to start another question." : runtime.endedEarly ? "Your submitted answers are saved. The remaining questions were not scored." : !assessmentComplete
                     ? runtime.request.source == .reassessment
                        ? "This skill check ended before enough scored answers were completed. Skipped questions do not count; retry to get a fresh set."
                        : runtime.request.source == .baseline
                            ? "This starting skill check ended before enough scored answers were completed. Skipped questions do not count; retry to get a fresh set."
                            : "Answer at least one challenge to complete this session. Skipped questions stay out of progress and rewards."
                     : runtime.request.evidenceClass == .documentPractice
                        ? "Source practice does not change your skill scores."
                     : runtime.correctness.isEmpty
                        ? "Your study activity was saved. Skipped and solution-viewed questions do not change skill scores."
                     : "Your answers were saved and now update this lab’s progress.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                if assessmentComplete, !runtime.correctness.isEmpty, !runtime.exercise.assessmentProtected {
                    let earnedXP = runtime.correctness.count * NFForgeProgressEngine.xpPerEligibleAttempt
                        + NFForgeProgressEngine.xpPerEligibleCompletedSession
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(NFTheme.gold.opacity(0.22))
                            Image(systemName: "sparkles")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(NFTheme.goldForeground)
                        }
                        .frame(width: 54, height: 54)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("+\(earnedXP) Practice XP")
                                .font(.title3.bold().monospacedDigit())
                            Text("Rewarded for answered challenges and a completed session—not for speed or correctness.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: 520)
                    .nfGameCard(
                        accent: NFTheme.gold,
                        secondary: NFTheme.rose,
                        cornerRadius: 20,
                        padding: 16
                    )
                    .accessibilityElement(children: .combine)
                }
                if runtime.request.source == .today,
                   let planID = runtime.request.planID,
                   store.todayPlan.id == planID {
                    let completed = store.completedPlanBlockIDs(planID: planID).count
                    VStack(spacing: 7) {
                        Text("\(completed) of \(store.todayPlan.blocks.count) daily-plan blocks complete")
                            .font(.headline.monospacedDigit())
                        Group {
                            if let nextTodayBlock {
                                Text(NFAppLocalization.formattedNextBlock(
                                    title: nextTodayBlock.title,
                                    minutes: nextTodayBlock.minutes
                                ))
                            } else if completed == store.todayPlan.blocks.count {
                                Text("Today’s plan is complete.")
                            } else {
                                Text("Your shortened session is complete; the remaining chapters stay available in Today.")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    .nfCard(cornerRadius: 16, padding: 14)
                }
                if runtime.awaitingNextSitting {
                    Button("Begin next sitting") { runtime.continueProtectedSitting(store: store) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("session-next-sitting")
                }
                Button(runtime.awaitingNextSitting ? "Save and continue later" : runtime.endedEarly ? "Done" : !assessmentComplete ? "Close and retry later" : nextTodayBlock == nil ? "Done" : "Continue to next block") {
                    guard runtime.finish(store: store) else { return }
                    let didContinue = assessmentComplete
                        && runtime.request.source == .today
                        && todaySessionSequence.advance(
                            after: runtime.request.planBlockID,
                            planID: runtime.request.planID,
                            store: store
                        )
                    if !didContinue {
                        todaySessionSequence.clear()
                        store.activeSessionRequest = nil
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(NFTheme.controlTint(for: "indigo"))
                .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                .controlSize(.large)
            }
            .padding(30)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }

    private var pauseOverlay: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    NFIconTile(symbol: "pause.fill", color: NFTheme.indigo, size: 74)
                    Text("Session paused")
                        .font(.title.bold())
                        .accessibilityHeading(.h1)
                    Text("Time away is excluded from active duration.").foregroundStyle(.secondary)
                    Button {
                        NFSessionPauseDiagnostics.record("resume.button")
                        runtime.resume()
                    } label: {
                        Text("Resume").frame(minWidth: 96, minHeight: 44).contentShape(Rectangle())
                    }
                        .accessibilityIdentifier("session-resume")
                        .buttonStyle(.borderedProminent)
                        .tint(NFTheme.controlTint(for: "indigo"))
                        .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                        .controlSize(.large)
                    Button { attemptSaveAndClose() } label: {
                        Text("Save & close").frame(minWidth: 96, minHeight: 44).contentShape(Rectangle())
                    }
                        .accessibilityIdentifier("session-save-close")
                        .buttonStyle(.bordered)

                }
                .padding(32)
                .nfCard(cornerRadius: 26)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
        }
    }

    private func summaryCount(value: Int, label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .number)
                .font(.title2.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 110)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func feedbackCreditLabel(for result: NFExerciseScoringResult) -> String {
        if runtime.isSelfCheck { return "Self-reported match · personal study" }
        if result.feedback.isDelayed {
            return NFAppLocalization.localized("Scoring is protected until assessment review", locale: NFAppLocalization.preferredLocale, comment: "Protected-assessment feedback status before delayed scoring is revealed.")
        }
        let credit = result.credit.formatted(.percent.precision(.fractionLength(0)))
        if runtime.isAssessmentPractice {
            return NFAppLocalization.localized("\(credit) task credit · not added to the skill score", locale: NFAppLocalization.preferredLocale, comment: "Practice-item feedback distinguishing deterministic task credit from standardized skill scoring.")
        }
        if runtime.exercise.evidenceClass == .documentPractice {
            return NFAppLocalization.localized("\(credit) task credit · personal practice only", locale: NFAppLocalization.preferredLocale, comment: "Personal source-practice feedback distinguishing task credit from standardized evidence.")
        }
        return NFAppLocalization.localized("\(credit) task credit", locale: NFAppLocalization.preferredLocale, comment: "Post-answer deterministic task-credit summary.")
    }

    private func submitCurrentResponse() {
        guard runtime.canSubmit else { return }
        Task {
            if runtime.stage == .selfCheckComparison {
                await runtime.saveSelfCheckAsync(store: store)
            } else {
                runtime.noteSubmissionControlInputIfNeeded(.keyboard)
                let wasEstimate = runtime.awaitsEstimateLock
                await runtime.submitInlineAsync(store: store)
                if wasEstimate && !runtime.awaitsEstimateLock {
                    responseFocus = .logic(NFEstimateExactContract.exactKey)
                }
            }
        }
    }

    private func attemptSaveAndClose() {
        saveAndClosePending = true
        if runtime.draftSaveGate.isSaving {
            _ = runtime.prepareToClose(store: store)
            Task { @MainActor in
                await runtime.draftSaveGate.waitUntilIdle()
                guard saveAndClosePending else { return }
                attemptSaveAndClose()
            }
            return
        }
        guard runtime.prepareToClose(store: store).permitsClose else { return }
        closeSavedSession()
    }

    private func closeSavedSession() {
        runtime.finishClosing()
        saveAndClosePending = false
        todaySessionSequence.clear()
        store.activeSessionRequest = nil
        dismiss()
    }

    private func discardAndClose() {
        // Only unacknowledged in-memory changes are discarded. The repository
        // and any prepared or committed receipt remain untouched.
        guard runtime.exitDisposition(store: store) == .unacknowledged else { closeSavedSession(); return }
        closeSavedSession()
    }

    /// Focusing the actual heading lets VoiceOver announce only policy-safe
    /// visible content. It does not move the keyboard's response focus.
    private func focusAcknowledgedPresentation() async {
        let identity = runtime.presentationIdentity
        guard runtime.isDurablyPrepared, !runtime.isPaused, runtime.saveError == nil,
              scenePhase == .active, lastAccessiblePresentation != identity else { return }
        let destination: AccessibleFocus
        switch runtime.stage {
        case .item: destination = .prompt
        case .feedback: destination = .feedback
        case .selfCheckComparison: destination = .reference
        default: return
        }
        await Task.yield()
        guard !Task.isCancelled, runtime.presentationIdentity == identity,
              runtime.isDurablyPrepared, !runtime.isPaused, runtime.saveError == nil,
              scenePhase == .active else { return }
        lastAccessiblePresentation = identity
        accessibleFocus = destination
    }

    private func focusFirstResponseFieldIfNeeded() {
        #if os(macOS)
        guard runtime.stage == .item else { return }
        Task { @MainActor in
            await Task.yield()
            switch runtime.exercise.interaction {
            case .numeric: responseFocus = .numericValue
            case .shortText: responseFocus = .shortText
            case .selfCheck: responseFocus = .selfCheck
            case let .logicState(schema):
                responseFocus = runtime.visibleLogicKeys(schema).first.map(ResponseFocus.logic)
            default: responseFocus = nil
            }
        }
        #endif
    }

    private var contentLanguageNotice: String? {
        let chromeLocale = NFAppLocalization.preferredLocale
        let contentLocale = Locale(identifier: runtime.exercise.localeIdentifier)
        guard contentLocale.language.languageCode != chromeLocale.language.languageCode else { return nil }
        let contentName = chromeLocale.localizedString(forLanguageCode: contentLocale.language.languageCode?.identifier ?? runtime.exercise.localeIdentifier)
            ?? runtime.exercise.localeIdentifier
        return NFAppLocalization.localized(
            "This saved question stays in \(contentName) until you finish it. Your app language applies to the controls.",
            locale: chromeLocale,
            comment: "Explains why a saved question keeps its original language after changing app language."
        )
    }

    private func focusNextLogicField(after key: String, schema: NFLogicStateResponseSchema) {
        let keys = runtime.visibleLogicKeys(schema)
        guard let index = keys.firstIndex(of: key), keys.indices.contains(index + 1) else {
            if runtime.canSubmit { submitCurrentResponse() }
            return
        }
        responseFocus = .logic(keys[index + 1])
    }

    private func ratingTitle(_ rating: NFSelfCheckRating) -> String {
        switch rating {
        case .matched: NFAppLocalization.localized("Matched", locale: NFAppLocalization.preferredLocale, comment: "Recall self-check rating.")
        case .partiallyMatched: NFAppLocalization.localized("Partly matched", locale: NFAppLocalization.preferredLocale, comment: "Recall self-check rating.")
        case .notYet: NFAppLocalization.localized("Not yet", locale: NFAppLocalization.preferredLocale, comment: "Recall self-check rating.")
        }
    }
}

private struct NFSessionReinforcementModifier: ViewModifier {
    let stage: NFSessionStage
    let isCorrect: Bool?
    let hapticsEnabled: Bool
    let soundEnabled: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: stage) { _, newStage in
                guard newStage == .feedback, soundEnabled, let isCorrect else { return }
                NFReinforcementFeedback.playSound(success: isCorrect)
            }
            .sensoryFeedback(.success, trigger: stage) { _, newStage in
                hapticsEnabled && newStage == .feedback && isCorrect == true
            }
            .sensoryFeedback(.warning, trigger: stage) { _, newStage in
                hapticsEnabled && newStage == .feedback && isCorrect == false
            }
    }
}

struct ReportExerciseView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exercise: NFExercise
    let assessmentDescriptorID: String?
    @State private var reason = "Answer or explanation seems incorrect"
    @State private var note = ""
    @State private var saved = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    Text(exercise.prompt)
                }
                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        Text("Answer or explanation seems incorrect").tag("Answer or explanation seems incorrect")
                        Text("Prompt is ambiguous").tag("Prompt is ambiguous")
                        if !exercise.citations.isEmpty {
                            Text("Source excerpt is insufficient").tag("Source excerpt is insufficient")
                        }
                        Text("Accessibility issue").tag("Accessibility issue")
                        Text("Inappropriate content").tag("Inappropriate content")
                    }
                    TextField("Optional note", text: $note, axis: .vertical)
                }
                Section {
                    Text("Saved reports are excluded from future practice sets.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(saved ? "Report saved" : "Report item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save report") { save() }
                        .disabled(saved)
                }
            }
        }
        .nfDesktopPresentationFrame(minWidth: 360, minHeight: 460)
        .alert("Report could not be saved", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(saveError ?? "The report stays on screen so you can retry."))
        }
    }

    private func save() {
        do {
            try store.saveItemReport(
                exercise: exercise,
                assessmentDescriptorID: assessmentDescriptorID,
                reason: reason,
                note: note
            )
            saved = true
        } catch {
            saveError = "The report stays on screen so you can retry."
        }
    }
}


extension NFUniversalSessionRuntime {
    var awaitsEstimateLock: Bool { mathWork?.awaitsEstimate == true }
    var activeHintLadder: [String] { mathWork?.hintLadder ?? exercise.feedback.hintLadder }
    func visibleLogicKeys(_ schema: NFLogicStateResponseSchema) -> [String] {
        NFMathWorkPolicy.responseKeys(schema: schema, draft: mathWork)
    }
    var hasOptionalMathWorking: Bool { mathWork?.workingValues.isEmpty == false }
    var mathWorkingContract: NFCalculationChainContract? { NFMathWorkPolicy.workingContract(for: exercise) }

    @discardableResult
    func lockEstimate(store: AppStore) -> Bool {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; _ = self.lockEstimate(store: store)
        }) { return false }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canEditDraft, unavailableReason == nil, let previous = mathWork,
              previous.isCompatible(with: exercise, response: makeResponse()),
              let next = previous.lockingEstimate(logicState[NFEstimateExactContract.estimateKey] ?? "",
                  activeSeconds: currentItemActiveDuration()) else { return false }
        let previousConfidence = selectedConfidence
        mathWork = next; selectedConfidence = nil
        return checkpointDraftRetainingAcknowledgedStage(store: store) {
            mathWork = previous; selectedConfidence = previousConfidence
        }
    }

    func toggleMathWorking(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.toggleMathWorking(store: store)
        }) { return }
        guard canEditDraft, unavailableReason == nil, var next = mathWork, !next.workingValues.isEmpty else { return }
        let previous = mathWork, previousCount = hintCount, previousEvents = assistanceEvents, previousHint = showHint
        next.workingExpanded.toggle(); mathWork = next
        // The compensation worksheet exposes a strategy, unlike blank chain
        // checkpoints whose operations are already essential givens. Save that
        // assistance before revealing the worksheet; final-answer credit is unchanged.
        if next.workingExpanded, next.kind == .compensation {
            while hintCount < min(2, activeHintLadder.count) { requestHint() }
        }
        checkpointDraftRetainingAcknowledgedStage(store: store) {
            mathWork = previous; hintCount = previousCount; assistanceEvents = previousEvents; showHint = previousHint
        }
    }
    func setMathWorkingValue(_ value: String, at index: Int) {
        guard canEditDraft, unavailableReason == nil, mathWork?.workingExpanded == true, mathWork?.workingValues.indices.contains(index) == true, value.count <= 500 else { return }
        noteTextResponseInput()
        mathWork?.workingValues[index] = value
    }
}


/// The same exact ordered operations have native text fields; no drawing or
/// pointer gesture is required to preserve optional learner checkpoints.
private struct NFMathWorkingFields: View {
    let contract: NFCalculationChainContract
    let values: [String]
    let isEditable: Bool
    let update: (Int, String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Optional working does not change final-answer credit.")
                .font(.footnote).foregroundStyle(.secondary)
            ForEach(Array(contract.operations.enumerated()), id: \.offset) { index, operation in
                VStack(alignment: .leading, spacing: 5) {
                    Text("Step \(index + 1): \(operation.instruction)").font(.subheadline)
                    TextField("Your value after step \(index + 1)", text: Binding(
                        get: { values.indices.contains(index) ? values[index] : "" },
                        set: { update(index, $0) }))
                        .textFieldStyle(.roundedBorder).frame(minHeight: 44)
                        .accessibilityIdentifier("math-working-\(index)")
                }
            }
        }.disabled(!isEditable)
    }
}


extension NFUniversalSessionRuntime {
    func setDataPrediction(_ text: String) {
        guard canEditDraft, unavailableReason == nil, text.count <= 500,
              dataInspection?.overlayRevealed == false else { return }
        dataInspection?.predictionText = text
    }
    func selectDataPoint(_ id: Int, store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.selectDataPoint(id, store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canEditDraft, unavailableReason == nil, let previous = dataInspection,
              let next = previous.selecting(pointID: id, exercise: exercise) else { return }
        dataInspection = next
        checkpointDraftRetainingAcknowledgedStage(store: store) { dataInspection = previous }
    }
    @discardableResult
    func revealDataExplanation(store: AppStore) -> Bool {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; _ = self.revealDataExplanation(store: store)
        }) { return false }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canEditDraft, unavailableReason == nil, let previous = dataInspection,
              let next = previous.revealing(exercise: exercise, activeSeconds: currentItemActiveDuration()) else { return false }
        let oldConfidence = selectedConfidence
        dataInspection = next; selectedConfidence = nil
        return checkpointDraftRetainingAcknowledgedStage(store: store) {
            dataInspection = previous; selectedConfidence = oldConfidence
        }
    }
    func toggleDataExplanation(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.toggleDataExplanation(store: store)
        }) { return }
        guard canEditDraft, unavailableReason == nil, let previous = dataInspection, previous.overlayRevealed else { return }
        dataInspection?.overlayExpanded.toggle()
        checkpointDraftRetainingAcknowledgedStage(store: store) { dataInspection = previous }
    }
}


extension NFUniversalSessionRuntime {
    var scienceResponse: NFExerciseResponse { makeResponse() }
    var awaitsScienceEvidence: Bool { scienceStudy?.awaitsEvidence == true }
    var scienceEvidenceValidation: NFExerciseResponseValidation? {
        scienceStudy?.evidenceValidation(makeResponse(), exercise: exercise)
    }
    func setScienceSelection(_ value: [String: Set<String>]) {
        guard canEditDraft, let draft = scienceStudy else { return }
        let response = NFExerciseResponse.claimEvidence(.init(pairs: value.keys.sorted().map {
            .init(claimID: $0, evidenceIDs: value[$0, default: []].sorted())
        }))
        guard draft.isCompatible(with: exercise, response: response) else { return }
        claimSelections = value
    }
    @discardableResult
    func lockScienceEvidence(store: AppStore) -> Bool {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; _ = self.lockScienceEvidence(store: store)
        }) { return false }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canEditDraft, let previous = scienceStudy,
              let next = previous.locking(response: makeResponse(), exercise: exercise,
                  activeSeconds: currentItemActiveDuration()) else { return false }
        let previousConfidence = selectedConfidence
        scienceStudy = next; selectedConfidence = nil
        return checkpointDraftRetainingAcknowledgedStage(store: store) {
            scienceStudy = previous; selectedConfidence = previousConfidence
        }
    }
}


extension NFUniversalSessionRuntime {
    var transferResponse: NFExerciseResponse { makeResponse() }
    var awaitsTransferRelationship: Bool { transferRelationship?.awaitsRelationship == true }
    var canLockTransferRelationship: Bool {
        guard canEditDraft, let draft = transferRelationship else { return false }
        return draft.locking(response: makeResponse(), exercise: exercise, activeSeconds: currentItemActiveDuration()) != nil
    }
    func setTransferRelationship(_ id: String?) {
        guard canEditDraft, let draft = transferRelationship, draft.awaitsRelationship else { return }
        let response = NFExerciseResponse.logicState(.init(finalState: logicState, violatedRuleID: id))
        guard draft.isCompatible(with: exercise, response: response) else { return }
        violatedRuleID = id
    }
    func setTransferTotal(_ value: String) {
        guard canEditDraft, transferRelationship?.awaitsRelationship == false else { return }
        logicState[NFTransferRelationshipContract.totalKey] = value
    }
    @discardableResult
    func lockTransferRelationship(store: AppStore) -> Bool {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; _ = self.lockTransferRelationship(store: store)
        }) { return false }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canEditDraft, let previous = transferRelationship,
              let next = previous.locking(response: makeResponse(), exercise: exercise,
                  activeSeconds: currentItemActiveDuration()) else { return false }
        let previousConfidence = selectedConfidence
        transferRelationship = next; selectedConfidence = nil
        return checkpointDraftRetainingAcknowledgedStage(store: store) {
            transferRelationship = previous; selectedConfidence = previousConfidence
        }
    }
}


extension NFUniversalSessionRuntime {
    var graphConstruction: NFGraphConstructionContract? { NFGraphConstructionContract.make(exercise: exercise) }
    var graphResponse: NFExerciseResponse { makeResponse() }
    var graphExerciseDigest: String? { try? NFLocalItemCheckpoint.digest(exercise) }
    var graphInputIdentity: String? { graphExerciseDigest.map { "\(sessionID.uuidString)|\(responseEditorSlotID.uuidString)|\($0)" } }
    @discardableResult func setGraphPoint(_ point: NFGraphConstructionContract.Point, expectedInputIdentity: String) -> Bool {
        guard let graph = graphConstruction, graph.contains(point) else { return false }
        return setGraphResponse(point.response, expectedInputIdentity: expectedInputIdentity)
    }
    @discardableResult func setGraphResponse(_ response: NFExerciseResponse, expectedInputIdentity: String) -> Bool {
        guard ownsWriter, canEditDraft, unavailableReason == nil,
              graphInputIdentity == expectedInputIdentity, let graph = graphConstruction,
              response == NFExerciseResponse.initialDraft(for: exercise) || graph.point(from: response) != nil,
              case let .logicState(value) = response else { return false }
        noteDiscreteResponseInput(); logicState = value.finalState; violatedRuleID = nil
        invalidateConfidenceAfterEdit()
        return true
    }
}

struct NFReviewedChallengeChoice: Identifiable, Equatable {
    let id: UUID
    let slotID: UUID
    let action: NFEditorialOverrideAction
    let writerAuthority: NFLocalWriterAuthority
    var boundary: NFEditorialOverrideBoundary?
}

extension NFUniversalSessionRuntime {
    var reviewedSlotID: UUID { slotID }
    var editorialWriterAuthority: NFLocalWriterAuthority? { ownsWriter ? (activeCommandAuthority ?? retainedWriterAuthority) : nil }

    var canChooseReviewedChallenge: Bool {
        guard ownsWriter, !hasExited, !isPaused, isDurablyPrepared, unavailableReason == nil,
              assessmentSession == nil, !exercise.assessmentProtected, exercise.evidenceClass == .practice,
              !pendingSkip, itemPresentationAcknowledged else { return false }
        if stage == .item { return committedAttemptID == nil && !hasPreparedCommit }
        return stage == .feedback && committedAttemptID == pendingAttemptID && lastResult != nil
    }

    func reviewedChallengePresentation(store: AppStore) -> NFEditorialChallengePresentation? {
        _ = store.localSessionRevision
        guard !hasExited, assessmentSession == nil, !exercise.assessmentProtected else { return nil }
        return store.localSessions.editorialChallengePresentation(sessionID: sessionID)
    }

    var canApplyReviewedNext: Bool { canChooseReviewedChallenge && index + 1 < itemCount }

    func chooseReviewedChallenge(_ action: NFEditorialOverrideAction, store: AppStore, expectedSlotID: UUID? = nil) {
        guard expectedSlotID == nil || expectedSlotID == slotID else { return }
        guard canChooseReviewedChallenge, reviewedChallengePresentation(store: store) != nil,
              let authority = editorialWriterAuthority else { return }
        if reviewedChoice?.slotID != slotID || reviewedChoice?.action != action || reviewedChoice?.writerAuthority != authority {
            reviewedChoice = .init(id: UUID(), slotID: slotID, action: action, writerAuthority: authority)
        }
        reviewedChallengeError = nil
        reviewedAvailableBands = []
    }

    func cancelReviewedChoice() {
        reviewedChoice = nil
        reviewedChallengeError = nil
        reviewedAvailableBands = []
    }

    @discardableResult
    func applyReviewedChoice(_ boundary: NFEditorialOverrideBoundary, store: AppStore) -> Bool {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; _ = self.applyReviewedChoice(boundary, store: store)
        }) { return false }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canChooseReviewedChallenge, var choice = reviewedChoice, choice.slotID == slotID,
              reviewedChallengePresentation(store: store) != nil else { return false }
        guard choice.writerAuthority == editorialWriterAuthority else {
            reviewedChallengeError = NFEditorialOverrideError.staleOwner.localizedDescription
            reviewedAvailableBands = []
            saveError = nil
            return false
        }
        guard boundary == .nextQuestion ? canApplyReviewedNext : canReplaceCurrentItem else { return false }
        // A different boundary is a new explicit command. Retrying the same
        // boundary retains its ID even if the previous file write failed.
        if let prior = choice.boundary, prior != boundary {
            choice = .init(id: UUID(), slotID: slotID, action: choice.action, writerAuthority: choice.writerAuthority, boundary: boundary)
        } else { choice.boundary = boundary }
        reviewedChoice = choice
        guard checkpointDraft(store: store), ownsWriter,
              let saved = store.localSessions.archive.sessions.first(where: { $0.id == sessionID }),
              saved.checkpoint.slotID == choice.slotID, saved.checkpoint.attemptID == pendingAttemptID else { return false }
        let intent = NFEditorialOverrideIntent(id: choice.id, action: choice.action, writerAuthority: choice.writerAuthority)
        do {
            switch boundary {
            case .nextQuestion:
                _ = try store.setEditorialNextQuestion(intent, request: request, predecessor: saved.checkpoint)
            case .replaceCurrent:
                let preparation = try store.prepareAdaptiveReplacement(request: request,
                    predecessor: saved.checkpoint, overrideIntent: intent, command: try sessionWriterCommand())
                let accepted = try store.acceptAdaptiveItem(preparation, checkpoint: preparation.checkpoint)
                acknowledgedEnvelopeRevision = accepted.revision
                checkpointRevision += 1
                restoreExactCheckpoint(accepted.checkpoint, freshlyAccepted: true)
                isDurablyPrepared = true
                replacementUnavailableReason = nil
                nextUnavailableReason = nil
            }
            cancelReviewedChoice()
            saveError = nil
            return true
        } catch let error as NFEditorialOverrideError {
            reviewedChallengeError = error.localizedDescription
            reviewedAvailableBands = error.availableBands
            saveError = nil
        } catch NFLocalSessionRepository.RepositoryError.unavailableLaunch {
            reviewedChallengeError = NFLocalSessionRepository.RepositoryError.unavailableLaunch.localizedDescription
            reviewedAvailableBands = []
            saveError = nil
        } catch { saveError = error.localizedDescription }
        return false
    }

    func separateReviewedBands(store: AppStore) -> [NFEditorialBand] {
        _ = store.localSessionRevision
        guard canChooseReviewedChallenge, request.ordinaryDelivery?.strategy == .fixedBlock else { return [] }
        return store.localSessions.reviewedStartingBands(sessionID: sessionID)
    }

    @discardableResult
    func startSeparateReviewedActivity(_ band: NFEditorialBand, store: AppStore, expectedSlotID: UUID? = nil) -> Bool {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; _ = self.startSeparateReviewedActivity(band, store: store, expectedSlotID: expectedSlotID)
        }) { return false }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard expectedSlotID == nil || expectedSlotID == slotID else { return false }
        guard canChooseReviewedChallenge, separateReviewedBands(store: store).contains(band) else { return false }
        if separateReviewedCommand?.slotID != slotID || separateReviewedCommand?.band != band || separateReviewedCommand?.writerAuthority != editorialWriterAuthority {
            guard let authority = editorialWriterAuthority else { return false }
            separateReviewedCommand = (UUID(), slotID, band, authority)
        }
        guard let command = separateReviewedCommand else { return false }
        pause()
        guard checkpointDraft(store: store) else { return false }
        guard ownsWriter else { return false }
        if store.beginSeparateReviewedActivity(from: request, band: band, commandID: command.id, writerAuthority: command.writerAuthority) {
            // The root presentation is keyed by the new request ID. Releasing
            // only this writer lets it replace the old sheet without clearing
            // or dismissing the newly accepted request.
            finishClosing()
            return true
        }
        reviewedChallengeError = store.lastErrorMessage ?? NFEditorialOverrideError.unsupported.localizedDescription
        resume()
        return false
    }
}

private struct NFReviewedChallengeControls: View {
    @Bindable var runtime: NFUniversalSessionRuntime
    @Environment(AppStore.self) private var store

    var body: some View {
        let slotID = runtime.reviewedSlotID
        if let shown = runtime.reviewedChallengePresentation(store: store) {
            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizedStringKey(shown.titleKey)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(verbatim: band(shown.deliveredBand) + " · " + mode(shown.mode)).font(.subheadline.weight(.semibold))
                Text(NFAppLocalization.localized("Reasoning steps: \(shown.reasoningSteps)", locale: NFAppLocalization.preferredLocale, comment: "Actual reviewed demand count for the current question."))
                    .font(.caption).foregroundStyle(.secondary)
                if let familyTitle = shown.mixedFamilyTitle {
                    Text(verbatim: familyTitle).font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("session-reviewed-family")
                    Text("This activity mixes reviewed families. Each family keeps its own challenge.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let count = shown.mixedFeasibleFamilyCount, count < 4 {
                        Text("Fewer than four reviewed families are currently available for this activity. The saved questions use only compatible families.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("session-reviewed-reduced-scope")
                    }
                }
                Text(verbatim: localized(shown.explanationKey)).font(.footnote)
                if let pending = shown.pendingBand {
                    LabeledContent("Next question", value: band(pending) + " · " + mode(shown.pendingChallengeMode ?? .adaptive))
                        .font(.footnote).accessibilityIdentifier("session-pending-challenge")
                }
                if runtime.canChooseReviewedChallenge {
                    Menu {
                        choice("Easier", action: .easier, slotID: slotID)
                        choice("Harder", action: .harder, slotID: slotID)
                        choice("Keep this level", action: .keepThisLevel, slotID: slotID)
                        choice("Return to Adaptive", action: .adaptive, slotID: slotID)
                        Menu("Reviewed bands") {
                            ForEach(shown.reviewedCatalogBands, id: \.self) { value in
                                choice(NFEditorialChallengePresentation.bandNameKey(value), action: .fixedBand(value), slotID: slotID)
                            }
                        }
                    } label: {
                        Label("Change challenge", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.bordered).accessibilityIdentifier("session-change-challenge")
                }
                if let choice = runtime.reviewedChoice, choice.slotID == slotID {
                    choiceActions(choice)
                }
                if let reason = runtime.reviewedChallengeError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Challenge choice unavailable").font(.footnote.weight(.semibold))
                        Text(verbatim: localized(reason)).font(.footnote)
                        ForEach(runtime.reviewedAvailableBands, id: \.self) { value in
                            Button {
                                runtime.chooseReviewedChallenge(.fixedBand(value), store: store, expectedSlotID: slotID)
                            } label: {
                                Text(verbatim: band(value)).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.bordered).disabled(!runtime.canChooseReviewedChallenge)
                        }
                    }.accessibilityIdentifier("session-challenge-unavailable")
                }
                DisclosureGroup("Technical details") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: shown.policyVersion)
                        Text(verbatim: shown.objectiveID)
                        Text(verbatim: shown.familyID)
                        Text(verbatim: shown.decisionID)
                    }.font(.caption.monospaced()).textSelection(.enabled)
                }.font(.caption)
            }
            .padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain).accessibilityIdentifier("session-reviewed-challenge")
        } else {
            let bands = runtime.separateReviewedBands(store: store)
            if !bands.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This fixed question set stays saved. Start a separate reviewed activity for the remaining questions.").font(.footnote)
                    Menu {
                        ForEach(bands, id: \.self) { value in
                            Button { _ = runtime.startSeparateReviewedActivity(value, store: store, expectedSlotID: slotID) } label: {
                                Text(verbatim: band(value))
                            }
                        }
                    } label: {
                        Text("Start a separate reviewed activity").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.bordered).accessibilityIdentifier("session-start-separate-reviewed")
                    if let reason = runtime.reviewedChallengeError { Text(verbatim: localized(reason)).font(.footnote) }
                }
            }
        }
    }

    @ViewBuilder private func choice(_ title: String, action: NFEditorialOverrideAction, slotID: UUID) -> some View {
        Button { runtime.chooseReviewedChallenge(action, store: store, expectedSlotID: slotID) } label: {
            Text(verbatim: localized(title))
        }
    }

    private func choiceActions(_ choice: NFReviewedChallengeChoice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: actionTitle(choice.action)).font(.subheadline.weight(.semibold))
            Text("Timing stays unchanged.").font(.footnote).foregroundStyle(.secondary)
            Button { _ = runtime.applyReviewedChoice(.nextQuestion, store: store) } label: {
                Text("Apply to next question").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.borderedProminent).disabled(!runtime.canApplyReviewedNext)
                .accessibilityIdentifier("session-challenge-apply-next")
            if runtime.canReplaceCurrentItem {
                Button { _ = runtime.applyReviewedChoice(.replaceCurrent, store: store) } label: {
                    Text("Replace this question").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.bordered).accessibilityIdentifier("session-challenge-replace")
            }
            if !runtime.canApplyReviewedNext && !runtime.canReplaceCurrentItem {
                Text("This is the last question. Choose a new activity to change the challenge.").font(.footnote)
            }
            Button("Cancel") { runtime.cancelReviewedChoice() }.frame(minHeight: 44)
        }
    }
    private func localized(_ key: String) -> String { NFAppLocalization.localizedCatalogValue(key, locale: NFAppLocalization.preferredLocale) }
    private func band(_ value: NFEditorialBand) -> String { localized(NFEditorialChallengePresentation.bandNameKey(value)) }
    private func mode(_ value: NFEditorialChallengeMode) -> String {
        switch value { case .adaptive: return localized("Adaptive"); case .fixedBand: return localized("Fixed challenge") }
    }
    private func actionTitle(_ value: NFEditorialOverrideAction) -> String {
        switch value {
        case .easier: return localized("Easier")
        case .harder: return localized("Harder")
        case .keepThisLevel: return localized("Keep this level")
        case .adaptive: return localized("Return to Adaptive")
        case let .fixedBand(value): return band(value)
        }
    }
}

extension NFUniversalSessionRuntime {
    /// Receipt acknowledgement may change the derived evidence state, but a
    /// new question/sitting/summary is published only from an accepted snapshot.
    private func advanceProtectedItem(store: AppStore, afterSkip: Bool = false, newSitting: Bool = false) {
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard let session = assessmentSession else { return }
        freezeSittingClock()
        defer {
            if itemPresentationAcknowledged, !isPaused, stage != .summary, sittingSegmentStart == nil {
                sittingSegmentStart = monotonicNow()
            }
        }
        lifecycle.advance(command: newSitting ? .continueSitting : afterSkip ? .completedSkip : .next,
            canMutate: { self.ownsWriter && !self.hasExited && self.unavailableReason == nil },
            persistCurrent: { self.checkpointDraft(store: store) },
            prepare: { () -> NFSessionLifecycleCoordinator.Advance<NFLocalItemCheckpoint> in
                guard var current = store.localSessions.archive.sessions.first(where: { $0.id == self.sessionID })?.checkpoint,
                      current.slotID == self.slotID, current.attemptID == self.pendingAttemptID,
                      current.assessmentCatalogSnapshot == session,
                      let state = current.assessmentState else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
                if newSitting {
                    guard current.phase == .summary, current.awaitingNextSitting == true else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
                    current.sittingActiveDuration = 0
                    current.sittingOrdinal = (current.sittingOrdinal ?? 0) + 1
                    current.awaitingNextSitting = false
                    current.assessmentStopReason = nil
                }
                let step = NFAssessmentEngine.nextStep(in: session, state: state,
                    activeElapsedSeconds: NFSessionDurationPolicy.wholeSeconds(current.sittingActiveDuration ?? 0) ?? 0,
                    sittingBudgetSeconds: NFSessionDurationPolicy.wholeSeconds(self.sittingBudgetSeconds) ?? 0)
                if let reason = step.stopReason {
                    current.phase = .summary
                    current.pendingOutcome = nil
                    current.assessmentStopReason = reason
                    current.awaitingNextSitting = reason == .maximumActiveDurationReached && !session.hasSufficientEvidence(in: state)
                    return .summary(current)
                }
                guard let descriptor = step.item,
                      descriptor.block == session.definition.kind,
                      (session.items + session.candidatePool).contains(descriptor),
                      !state.selectedItemIDs.contains(descriptor.id) else {
                    throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
                }
                let index = state.completedScorableItems
                let candidate = Self.makeExercise(request: self.request, index: index, assessmentDescriptor: descriptor)
                guard candidate.availabilityReason == nil,
                      NFExerciseSchemaValidator.supportsExerciseSchemaVersion(candidate.schemaVersion) else {
                    throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
                }
                var next = try NFLocalItemCheckpoint.initial(request: self.request, exercise: candidate,
                    slotID: UUID(), attemptID: UUID(), at: Date())
                next.index = index
                next.itemCount = current.itemCount
                next.exercise = candidate.assessmentProtected ? nil : candidate
                next.descriptor = descriptor
                next.scratchpad = current.scratchpad
                next.correctness = current.correctness
                next.credits = current.credits
                next.assessmentDescriptorIDs = current.assessmentDescriptorIDs
                next.assessmentEvents = current.assessmentEvents
                next.cumulativeActiveDuration = current.cumulativeActiveDuration
                next.assessmentPracticeDuration = current.assessmentPracticeDuration
                next.semanticExclusions.formUnion(current.semanticExclusions)
                next.sittingActiveDuration = current.sittingActiveDuration
                next.sittingOrdinal = current.sittingOrdinal
                next.assessmentState = state
                next.assessmentCatalogSnapshot = session
                next.timingConditionOverride = current.timingConditionOverride
                return .item(next)
            }, persist: { checkpoint in
                self.checkpointDraft(using: { try self.persistLocalCheckpointValue(checkpoint, store: store) })
            }, publish: { checkpoint in
                self.restoreExactCheckpoint(checkpoint, freshlyAccepted: true)
                self.isDurablyPrepared = true
                if checkpoint.phase == .summary { self.enterSummary() }
                self.saveError = nil
                // Publish follows the authoritative local save; this second
                // adapter may fail without retracting the accepted question.
                _ = self.checkpointDraft(store: store)
            }, unavailable: { self.nextUnavailableReason = $0 }, failedPreparation: {
                self.saveError = NFAppLocalization.localizedCatalogValue("This saved question could not be verified. Your original answer is retained.", locale: NFAppLocalization.preferredLocale)
            })
    }

    private func endAtSavedBoundary(store: AppStore) {
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        if stage == .item { savedItemActiveDuration = currentItemActiveDuration(); activeSegmentStart = monotonicNow() }
        defer { if stage == .item { activeSegmentStart = monotonicNow() } }
        freezeSittingClock()
        defer {
            if itemPresentationAcknowledged, !isPaused, stage != .summary, sittingSegmentStart == nil {
                sittingSegmentStart = monotonicNow()
            }
        }
        lifecycle.advance(command: .endSession,
            allowsUnpreparedEnding: stage == .confidence && !hasPreparedCommit && lastResult == nil,
            canMutate: { self.ownsWriter && !self.hasExited && !self.hasPreparedCommit && self.unavailableReason == nil },
            persistCurrent: { self.checkpointDraft(store: store) },
            prepare: { () -> NFSessionLifecycleCoordinator.Advance<NFLocalItemCheckpoint> in
                guard var terminal = store.localSessions.archive.sessions.first(where: { $0.id == self.sessionID })?.checkpoint,
                      terminal.slotID == self.slotID, terminal.attemptID == self.pendingAttemptID,
                      terminal.pendingOutcome != "answer" else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
                terminal.phase = .summary
                terminal.endedEarly = true
                terminal.pendingOutcome = nil
                terminal.awaitingNextSitting = false
                return .summary(terminal)
            }, persist: { checkpoint in
                self.checkpointDraft(using: { try self.persistLocalCheckpointValue(checkpoint, store: store) })
            }, publish: { checkpoint in
                self.restoreExactCheckpoint(checkpoint, freshlyAccepted: true)
                self.isDurablyPrepared = true
                self.enterSummary()
                self.saveError = nil
                _ = self.checkpointDraft(store: store)
            }, unavailable: { self.nextUnavailableReason = $0 }, failedPreparation: {
                self.saveError = NFAppLocalization.localizedCatalogValue("This saved question could not be verified. Your original answer is retained.", locale: NFAppLocalization.preferredLocale)
            })
    }

    /// Used by time/legacy projections while a skip is saved but its next
    /// snapshot is not. The already accumulated duration is not added twice.
    private var currentActivityIsAcknowledged: Bool {
        if committedAttemptID != nil { return true }
        let id = assessmentDescriptor?.id ?? exercise.id
        return assessmentEvents.contains("skipped:\(id)") || assessmentEvents.contains("revealed:\(id)")
    }
}

/// The editor may keep receiving ordinary edits during an autosave. An explicit
/// action captures its boundary, locks further editing, and runs once after the
/// accepted (or failed) save has finished. It never executes on the file actor.
@MainActor @Observable
final class NFSessionDraftSaveGate {
    private(set) var isSaving = false
    private(set) var hasQueuedAction = false
    private(set) var showsProgress = false
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var queuedAction: (() -> Void)?
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    func begin() -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        progressTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard let self, self.isSaving else { return }
            self.showsProgress = true
        }
        return true
    }

    @discardableResult func enqueue(_ action: @escaping () -> Void) -> Bool {
        guard isSaving else { return false }
        if queuedAction == nil { queuedAction = action; hasQueuedAction = true }
        return true
    }

    func waitUntilIdle() async {
        guard isSaving else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    func finish() {
        let action = queuedAction
        queuedAction = nil
        hasQueuedAction = false
        isSaving = false
        progressTask?.cancel(); progressTask = nil
        showsProgress = false
        action?()
        let waiters = idleWaiters
        idleWaiters = []
        waiters.forEach { $0.resume() }
    }
}

private struct NFPendingSessionSaveModifier: ViewModifier {
    let gate: NFSessionDraftSaveGate
    func body(content: Content) -> some View {
        content.disabled(gate.hasQueuedAction)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if gate.showsProgress { ProgressView("Saving your work…").padding(8) }
            }
    }
}

extension View {
    func nfPendingSessionSave(_ gate: NFSessionDraftSaveGate) -> some View {
        modifier(NFPendingSessionSaveModifier(gate: gate))
    }
}

extension NFUniversalSessionRuntime {
    /// Debounce tasks save the latest immutable draft here. Explicit Submit has
    /// its own awaited prepared/receipt/feedback protocol; other lifecycle
    /// commands queue behind this earlier transaction before their own boundary.
    @discardableResult
    func checkpointDraftAsync(store: AppStore) async -> Bool {
        await draftSaveGate.waitUntilIdle()
        guard !Task.isCancelled, !hasExited, !durationChoiceRequired, unavailableReason == nil,
              ownsWriter, isDurablyPrepared else { return false }
        guard draftSaveGate.begin() else { return false }
        defer { draftSaveGate.finish() }
        do {
            let command = try sessionWriterCommand()
            let checkpoint = try currentLocalCheckpoint()
            let envelope = try localEnvelope(checkpoint, store: store)
            let committed = currentActivityIsAcknowledged
            let complete = hasCompletedRun
            #if DEBUG
            try localCheckpointWriteFailure?(checkpoint)
            #endif
            let acknowledgement = try await store.localSessions.saveSessionAsync(envelope,
                command: command, expectedRevision: acknowledgedEnvelopeRevision)
            // The repository already adopted the exact committed bytes even if
            // this task was cancelled during rename. Do not start another phase.
            try store.localSessions.validateSessionCommand(command, sessionID: sessionID)
            acknowledgeLocalWrite(envelope, store: store)
            guard !acknowledgement.verificationNeeded else {
                saveError = NFAppLocalization.localizedCatalogValue(
                    "Your latest work was written, but storage verification did not finish. Keep this session open and retry saving.",
                    locale: NFAppLocalization.preferredLocale)
                return false
            }
            try mirrorLocalCheckpoint(checkpoint, committed: committed, complete: complete,
                store: store, command: command)
            saveError = nil
            return true
        } catch is CancellationError {
            // An edit superseded disposable preparation. Its new debounce task
            // will save the latest response after this ticket is finalized.
            return false
        } catch {
            if !hasExited {
                saveError = NFAppLocalization.localizedCatalogValue(
                    "This session could not be saved. It remains open so you can retry or explicitly discard the unsaved changes.",
                    locale: NFAppLocalization.preferredLocale)
            }
            return false
        }
    }

    private func deferUntilDraftSaveCompletes(_ action: @escaping () -> Void) -> Bool {
        guard draftSaveGate.isSaving else { return false }
        if draftSaveGate.hasQueuedAction { return true }
        let hadSittingClock = sittingSegmentStart != nil
        savedItemActiveDuration = currentItemActiveDuration()
        activeSegmentStart = monotonicNow()
        freezeSittingClock()
        let identity = responseDraftIdentity
        let command = try? sessionWriterCommand()
        return draftSaveGate.enqueue { [weak self] in
            guard let self, !self.hasExited else { return }
            self.activeSegmentStart = self.monotonicNow()
            if hadSittingClock, !self.isPaused, self.stage != .summary { self.sittingSegmentStart = self.monotonicNow() }
            guard let command, (try? self.sessionWriterCommand()) == command,
                  self.responseDraftIdentity == identity else {
                self.saveError = NFAppLocalization.localizedCatalogValue(
                    "Your answer changed while saving. Review it and try the action again.", locale: NFAppLocalization.preferredLocale)
                return
            }
            action()
        }
    }

    private func mirrorLocalCheckpoint(_ checkpoint: NFLocalItemCheckpoint, committed: Bool, complete: Bool,
                                      store: AppStore, command: NFSessionWriterCommand) throws {
        guard exercise.evidenceClass != .documentPractice,
              exercise.provenance.sourceDocumentIDs.isEmpty else { return }
        let inFlight: TimeInterval = switch checkpoint.phase {
        case .item, .confidence, .selfCheckComparison: committed ? 0 : checkpoint.itemActiveDuration
        case .reflection, .feedback, .summary: 0
        }
        #if DEBUG
        try legacyCheckpointWriteFailure?()
        #endif
        try store.withSessionCommand(command, sessionID: sessionID) {
            try store.upsertCheckpoint(sessionID: sessionID, request: request,
                currentIndex: checkpoint.index, itemCount: checkpoint.itemCount,
                response: encoded(checkpoint.response), scratchpad: checkpoint.scratchpad,
                results: checkpoint.correctness, credits: checkpoint.credits,
                assessmentDescriptorIDs: checkpoint.assessmentDescriptorIDs, assessmentEvents: checkpoint.assessmentEvents,
                activeDurationSeconds: checkpoint.cumulativeActiveDuration + inFlight,
                assessmentStopReason: checkpoint.assessmentStopReason,
                pendingReflectionAttemptID: checkpoint.phase == .reflection ? checkpoint.committedAttemptID : nil,
                reflectionTrigger: checkpoint.phase == .reflection ? checkpoint.reflectionTrigger : nil,
                selectedReflectionCode: checkpoint.phase == .reflection ? checkpoint.selectedReflectionCode : nil,
                reflectionNote: checkpoint.phase == .reflection ? checkpoint.reflectionNote : nil,
                hasCommittedCurrentItem: committed, isComplete: complete)
        }
    }
}

private enum NFSubmissionPublication {
    case none
    case reference(confidence: ConfidenceLevel?)
    case feedback(intent: NFSessionLifecycleCoordinator.CommitIntent, activeDuration: TimeInterval)
}

/// The archive may have been replaced even when its directory cannot be verified.
/// Retain that exact accepted state; the older visible phase must never overwrite it.
private struct NFPendingSubmissionVerification {
    let checkpoint: NFLocalItemCheckpoint
    let publication: NFSubmissionPublication
    let command: NFSessionWriterCommand
}

extension NFUniversalSessionRuntime {
    /// Real view/keyboard entry point. Intermediate teaching locks retain their
    /// existing command implementation; scored Submit uses the awaited protocol.
    func submitInlineAsync(store: AppStore) async {
        guard await waitForSubmissionBoundary(), canSubmit else { return }
        if awaitsTransferRelationship { _ = lockTransferRelationship(store: store); return }
        if awaitsScienceEvidence { _ = lockScienceEvidence(store: store); return }
        if awaitsEstimateLock { _ = lockEstimate(store: store); return }
        guard !requiresConfidence || selectedConfidence != nil else { return }
        invalidateConfidenceAfterEdit()
        guard !requiresConfidence || selectedConfidence != nil else { return }
        submitResponse()
        await commitAsync(confidence: selectedConfidence, store: store)
    }

    func commitAsync(confidence: ConfidenceLevel?, store: AppStore) async {
        guard await waitForSubmissionBoundary(), stage == .confidence, !pendingSkip,
              !isCommitInFlight, ownsWriter, isDurablyPrepared else { return }
        do {
            let command = try sessionWriterCommand()
            guard draftSaveGate.begin() else { return }
            isCommitInFlight = true
            freezeSittingClock()
            defer { isCommitInFlight = false; draftSaveGate.finish() }
            if case .selfCheck = exercise.interaction, !hasPreparedCommit {
                var checkpoint = try currentLocalCheckpoint()
                checkpoint.phase = .selfCheckComparison
                checkpoint.referenceRevealed = true
                try await persistSubmissionCheckpoint(checkpoint, store: store, command: command,
                    publication: .reference(confidence: confidence))
            } else {
                await persistAttemptAsync(confidence: hasPreparedCommit ? selectedConfidence : confidence,
                    store: store, command: command)
            }
        } catch { submissionFailed(error) }
    }

    func saveSelfCheckAsync(store: AppStore) async {
        guard await waitForSubmissionBoundary(), stage == .selfCheckComparison, canSubmit,
              !isCommitInFlight, ownsWriter else { return }
        do {
            let command = try sessionWriterCommand()
            guard draftSaveGate.begin() else { return }
            isCommitInFlight = true
            freezeSittingClock()
            defer { isCommitInFlight = false; draftSaveGate.finish() }
            await persistAttemptAsync(confidence: pendingSelfCheckConfidence, store: store, command: command)
        } catch { submissionFailed(error) }
    }

    func retrySavingAsync(store: AppStore) async {
        guard !hasUnexpectedPreparedResponseEdit else {
            submissionFailed(NFLocalSessionRepository.RepositoryError.staleRevision)
            return
        }
        guard await waitForSubmissionBoundary() else { return }
        if let pending = pendingSubmissionVerification {
            guard await repairSubmissionVerification(pending, store: store) else { return }
            // A verified comparison/feedback already completed this command.
            if case .none = pending.publication {} else { return }
        } else if store.localSessions.archiveWriteVerificationNeeded {
            guard await checkpointDraftAsync(store: store) else { return }
        }
        if pendingSkip { reconcilePendingSkip(store: store) }
        else if committedAttemptID == nil && stage == .confidence {
            await commitAsync(confidence: selectedConfidence, store: store)
        } else { _ = await checkpointDraftAsync(store: store) }
    }

    func endSessionAsync(store: AppStore) async {
        guard await waitForSubmissionBoundary(allowActiveSubmission: true) else { return }
        if hasPreparedCommit || pendingSubmissionVerification != nil {
            await retrySavingAsync(store: store)
            guard !hasPreparedCommit, pendingSubmissionVerification == nil, !isCommitInFlight else { return }
        }
        endSession(store: store)
    }

    func advanceAsync(store: AppStore) async {
        guard !isPaused else { return }
        switch stage {
        case .item: await submitInlineAsync(store: store)
        case .selfCheckComparison: await saveSelfCheckAsync(store: store)
        case .feedback: next(store: store)
        case .confidence, .reflection, .summary: break
        }
    }

    /// One explicit action may wait for an earlier immutable autosave. Capture
    /// authority/response before waiting and exclude the wait from solving time.
    private func waitForSubmissionBoundary(allowActiveSubmission: Bool = false) async -> Bool {
        guard !hasExited, (allowActiveSubmission || !isCommitInFlight), ownsWriter, !Task.isCancelled,
              let command = try? sessionWriterCommand() else { return false }
        let identity = responseDraftIdentity
        if draftSaveGate.isSaving {
            guard !draftSaveGate.hasQueuedAction else { return false }
            _ = deferUntilDraftSaveCompletes({})
            await draftSaveGate.waitUntilIdle()
        }
        guard !Task.isCancelled, !hasExited, !isCommitInFlight,
              command == (try? sessionWriterCommand()), responseDraftIdentity == identity else { return false }
        return true
    }

    private func repairSubmissionVerification(_ pending: NFPendingSubmissionVerification, store: AppStore) async -> Bool {
        guard pending.command == (try? sessionWriterCommand()), draftSaveGate.begin() else { return false }
        isCommitInFlight = true
        freezeSittingClock()
        defer { isCommitInFlight = false; draftSaveGate.finish() }
        do {
            try await persistSubmissionCheckpoint(pending.checkpoint, store: store,
                command: pending.command, publication: pending.publication)
            saveError = nil
            return true
        } catch { submissionFailed(error); return false }
    }

    private func persistSubmissionCheckpoint(_ checkpoint: NFLocalItemCheckpoint, store: AppStore,
        command: NFSessionWriterCommand, publication: NFSubmissionPublication = .none) async throws {
        try store.localSessions.validateSessionCommand(command, sessionID: sessionID)
        let envelope = try localEnvelope(checkpoint, store: store)
        #if DEBUG
        try localCheckpointWriteFailure?(checkpoint)
        #endif
        let acknowledgement = try await store.localSessions.saveSessionAsync(envelope,
            command: command, expectedRevision: acknowledgedEnvelopeRevision)
        // Rename is accepted even on cancellation. Adopt its revision but keep
        // the old visible phase until storage verification succeeds. A retry
        // rewrites exactly this immutable checkpoint, never the older UI state.
        try store.localSessions.validateSessionCommand(command, sessionID: sessionID)
        acknowledgeLocalWrite(envelope, store: store)
        pendingSubmissionVerification = .init(checkpoint: checkpoint, publication: publication, command: command)
        guard !hasUnexpectedPreparedResponseEdit else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
        guard !acknowledgement.verificationNeeded else {
            throw NFLocalSessionRepository.RepositoryError.busy
        }
        pendingSubmissionVerification = nil
        publishSubmission(publication, checkpoint: checkpoint, store: store)
        try mirrorLocalCheckpoint(checkpoint, committed: checkpoint.committedAttemptID != nil,
            complete: checkpoint.phase == .summary && checkpoint.endedEarly != true,
            store: store, command: command)
        saveError = nil
    }

    private func publishSubmission(_ publication: NFSubmissionPublication, checkpoint: NFLocalItemCheckpoint,
                                   store: AppStore) {
        switch publication {
        case .none: break
        case .reference(let confidence):
            pendingSelfCheckConfidence = confidence
            selfCheckReferenceRevealed = true
            stage = .selfCheckComparison
        case .feedback(let intent, let activeDuration):
            stage = .feedback
            acknowledgeCommittedAttempt(intent, activeDuration: activeDuration, store: store)
            // Display the exact invitation retained before suspension.
            reflectionTrigger = checkpoint.reflectionTrigger
            suggestedReflectionCode = checkpoint.suggestedReflectionCode
            selectedReflectionCode = checkpoint.selectedReflectionCode
            reflectionNote = checkpoint.reflectionNote
        }
    }

    private func feedbackCheckpoint(_ intent: NFSessionLifecycleCoordinator.CommitIntent,
        activeDuration: TimeInterval, store: AppStore) throws -> NFLocalItemCheckpoint {
        var checkpoint = try currentLocalCheckpoint()
        guard checkpoint.phase == .confidence, checkpoint.pendingOutcome == "answer",
              checkpoint.attemptID == intent.attemptID, checkpoint.committedAttemptID == nil,
              checkpoint.response == intent.response else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
        checkpoint.phase = .feedback
        checkpoint.committedAttemptID = intent.attemptID
        checkpoint.pendingOutcome = nil
        checkpoint.cumulativeActiveDuration += activeDuration
        if isAssessmentPractice, let descriptorID = assessmentDescriptor?.id {
            checkpoint.assessmentPracticeDuration += activeDuration
            let event = "practice:\(descriptorID)"
            if !checkpoint.assessmentEvents.contains(event) { checkpoint.assessmentEvents.append(event) }
        } else if intent.score.outcome == .selfReported {
            checkpoint.assessmentEvents.append("selfReported:\(intent.attemptID.uuidString)")
        } else {
            checkpoint.correctness.append(intent.score.isCorrect)
            checkpoint.credits.append(intent.score.credit)
            if let descriptorID = assessmentDescriptor?.id,
               !checkpoint.assessmentDescriptorIDs.contains(descriptorID) {
                checkpoint.assessmentDescriptorIDs.append(descriptorID)
                checkpoint.assessmentEvents.append("answered:\(descriptorID)")
            }
        }
        if let descriptor = assessmentDescriptor, !isAssessmentPractice {
            checkpoint.assessmentState = assessmentState.appending(descriptor)
                .recordingResponse(to: descriptor, credit: intent.score.credit)
        }
        checkpoint.reflectionTrigger = store.reflectionTrigger(for: intent.score,
            confidence: intent.confidence ?? .uncertain, exercise: exercise, source: request.source)
        if checkpoint.reflectionTrigger != nil {
            checkpoint.suggestedReflectionCode = intent.score.isCorrect ? nil
                : NFErrorReflectionCode.candidate(for: intent.score.errorCode, lab: exercise.lab)
            checkpoint.selectedReflectionCode = nil; checkpoint.reflectionNote = ""
        }
        return checkpoint
    }

    private func persistAndPublishFeedback(_ intent: NFSessionLifecycleCoordinator.CommitIntent,
        activeDuration: TimeInterval, store: AppStore, command: NFSessionWriterCommand) async throws {
        let checkpoint = try feedbackCheckpoint(intent, activeDuration: activeDuration, store: store)
        try await persistSubmissionCheckpoint(checkpoint, store: store, command: command,
            publication: .feedback(intent: intent, activeDuration: activeDuration))
    }

    /// A native callback delivered after the editor locked must not be silently
    /// overwritten by retry or attached to the frozen score. Keep its live text
    /// available for recovery export; the accepted prepared answer stays exact.
    private var hasUnexpectedPreparedResponseEdit: Bool {
        if let pendingSubmissionVerification,
           pendingSubmissionVerification.checkpoint.response != makeResponse() { return true }
        guard hasPreparedCommit else { return false }
        let frozen = lifecycle.preparedIntent?.response
            ?? request.localCheckpoint.flatMap { $0.pendingOutcome == "answer" ? $0.response : nil }
        return frozen.map { $0 != makeResponse() } ?? false
    }

    private func submissionFailed(_ error: Error) {
        guard !hasExited else { return }
        saveError = NFAppLocalization.localizedCatalogValue(
            "The response could not be saved. It remains on this screen so you can retry.",
            locale: NFAppLocalization.preferredLocale)
    }
}

extension NFUniversalSessionRuntime {
    private func persistAttemptAsync(confidence: ConfidenceLevel?, store: AppStore, command: NFSessionWriterCommand) async {
        let response = makeResponse()
        let activeDuration = responseLockedActiveDuration ?? currentItemActiveDuration()
        var needsClarificationSave = false
        let recovered: NFSessionLifecycleCoordinator.CommitIntent? = {
            guard hasPreparedCommit, let pendingAttemptID, let lastResult else { return nil }
            return .init(attemptID: pendingAttemptID, response: response, score: lastResult, confidence: selectedConfidence)
        }()
        await lifecycle.commitAsync(exercise: exercise, response: response, attemptID: pendingAttemptID,
            confidence: confidence, recoveredIntent: recovered,
            canMutate: { self.ownsWriter && (try? self.sessionWriterCommand()) == command },
            // The ordinary repository validates the complete immutable receipt
            // on an idempotent save; it never replaces a conflicting attempt.
            receipt: { intent in
                guard self.exercise.assessmentProtected,
                      let record = store.attempts.first(where: { $0.id == intent.attemptID }) else { return .absent }
                return self.matchesOriginalReceipt(record, exercise: self.exercise, response: intent.response,
                    confidence: intent.confidence, descriptor: self.assessmentDescriptor)
                    && record.isCorrect == intent.score.isCorrect && record.deterministicCredit == intent.score.credit
                    ? .matching : .conflicting
            }, allowsNewCommit: {
                // A prepared checkpoint may lag an already-committed receipt.
                // AppStore performs its complete immutable comparison before
                // accepting that retry; later contract quarantine cannot force
                // a fresh evaluation of a saved receipt.
                if let id = self.pendingAttemptID, store.attempts.contains(where: { $0.id == id }) { return true }
                do { try NFExerciseSchemaValidator.validateInteraction(self.exercise.interaction); return true }
                catch {
                    self.unavailableReason = "This saved work needs a compatible version of NeuroForge. Your original answers remain saved."
                    return false
                }
            },
            publishPrepared: { intent in
                self.pendingAttemptID = intent.attemptID
                let referenceWasRevealed = self.selfCheckReferenceRevealed
                self.restore(intent.response)
                if case let .selfCheck(submission) = intent.response {
                    self.selfCheckReferenceRevealed = referenceWasRevealed
                    self.selfCheckRating = submission.rating
                }
                self.selectedConfidence = intent.confidence
                self.lastResult = intent.score
                self.hasPreparedCommit = true
            },
            persistPrepared: { try await self.persistSubmissionCheckpoint(try self.currentLocalCheckpoint(), store: store, command: command) },
            saveAttempt: { intent in
                try await store.saveExerciseAttemptAsync(command: command,
                        attemptID: intent.attemptID, sessionID: self.sessionID,
                        exercise: self.exercise, response: intent.response, result: intent.score,
                        confidence: intent.confidence, shownAt: self.shownAt, activeDuration: activeDuration,
                        source: self.request.source, assessmentBlock: self.request.assessmentBlock,
                        assessmentDescriptorID: self.assessmentDescriptor?.id, assessmentDescriptor: self.assessmentDescriptor,
                        assessmentCycle: self.request.reassessmentCycle, planID: self.request.planID,
                        planBlockID: self.request.planBlockID, hintCount: self.capturedSupportCount,
                        inputMode: self.inputModality.rawValue, interruptionCount: self.interruptionCount,
                        revisionCount: self.revisionCount, accommodationFlags: self.accommodationFlags(store: store),
                        wasTimed: self.usesTimedMode, mathWork: self.mathWork, traceInspection: self.traceInspection, dataInspection: self.dataInspection, scienceStudy: self.scienceStudy, transferRelationship: self.transferRelationship)
                #if DEBUG
                self.receiptWriteAcknowledged?()
                #endif
            },
            persistAndPublishFeedback: { intent in
                try await self.persistAndPublishFeedback(intent, activeDuration: activeDuration, store: store, command: command)
            },
            nonScorable: { score in
                if score.outcome == .invalidItem { self.unavailableReason = score.feedback.explanation }
                else {
                    self.savedItemActiveDuration = activeDuration
                    self.activeSegmentStart = self.monotonicNow()
                    self.responseLockedActiveDuration = nil
                    self.savedClarificationMessage = score.feedback.explanation
                    self.clarificationResponseIdentity = self.semanticResponseIdentity
                    self.lastResult = nil
                    self.hasPreparedCommit = false
                    self.saveError = nil
                    needsClarificationSave = true
                }
            }, conflictingReceipt: { _ in
                self.unavailableReason = "This saved work needs a compatible version of NeuroForge. Your original answers remain saved."
            }, failedSave: { error in self.submissionFailed(error) })
        if needsClarificationSave {
            do { try await persistSubmissionCheckpoint(try currentLocalCheckpoint(), store: store, command: command) }
            catch { submissionFailed(error) }
            // Grading/storage is not independent response time.
            activeSegmentStart = monotonicNow()
            if !isPaused { sittingSegmentStart = monotonicNow() }
        }
        }
}

/// Test-fixture diagnostics contain event names and monotonic timestamps only.
/// They are absent from ordinary launches and never include question/answer data.
private enum NFSessionPauseDiagnostics {
    @MainActor static func record(_ event: String) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing"),
              let id = NFUITestLaunchConfiguration.persistentRunID else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: "NeuroForge-UITests-\(id.uuidString)")
        let url = root.appending(path: "SessionPauseEvents.log")
        let previous = (try? Data(contentsOf: url)) ?? Data()
        var next = Data(previous.suffix(16_384))
        next.append(Data("\(ProcessInfo.processInfo.systemUptime) \(event)\n".utf8))
        try? next.write(to: url, options: .atomic)
        #endif
    }
}
