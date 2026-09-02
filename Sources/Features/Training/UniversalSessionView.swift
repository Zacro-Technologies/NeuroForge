import Observation
import SwiftUI

#if os(macOS)
import AppKit
#endif

enum NFSessionStage: Equatable {
    case item
    case confidence
    case selfCheckComparison
    case reflection
    case feedback
    case summary
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
    let sessionID: UUID
    let request: SessionRequest
    let itemCount: Int
    private let assessmentSession: NFAssessmentBlockSession?
    private(set) var exercise: NFExercise
    private(set) var assessmentDescriptor: NFAssessmentItemDescriptor?
    private(set) var assessmentState: NFAdaptiveAssessmentState
    private(set) var assessmentStopReason: NFAssessmentStopReason?
    private(set) var stage: NFSessionStage = .item
    private(set) var index: Int
    private(set) var results: [NFExerciseScoringResult] = []
    private(set) var correctness: [Bool]
    private(set) var credits: [Double]
    private(set) var assessmentDescriptorIDs: [String]
    private(set) var assessmentEvents: [String]
    private(set) var lastResult: NFExerciseScoringResult?
    private(set) var reflectionTrigger: NFAttemptReflectionTrigger?
    private(set) var shownAt = Date()
    private(set) var isPaused = false
    private(set) var isCommitInFlight = false
    private(set) var hintCount = 0
    private(set) var interruptionCount = 0
    private(set) var revisionCount = 0
    private(set) var inputModality: NFInputModality = .unknown
    private var pauseStartedAt: Date?
    private var accumulatedPausedDuration: TimeInterval = 0
    private var cumulativeActiveDuration: TimeInterval
    private var assessmentPracticeActiveDuration: TimeInterval
    private var pendingAttemptID: UUID?
    private var pendingSelfCheckConfidence: ConfidenceLevel?
    private var committedAttemptID: UUID?
    private var responseLockedActiveDuration: TimeInterval?
    private var pointerIsOverResponseControl = false
    private var seenQuestionFingerprints: Set<String> = []

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
    var violatedRuleID: String?
    var scratchpad = ""
    var showScratchpad = false
    var showHint = false
    var showReport = false
    var timerIsVisible = true
    var saveError: String?
    private(set) var suggestedReflectionCode: NFErrorReflectionCode?
    var selectedReflectionCode: NFErrorReflectionCode?
    var reflectionNote = ""

    init(request: SessionRequest, sessionID: UUID = UUID()) {
        self.request = request
        self.sessionID = request.resumeSessionID ?? sessionID
        correctness = request.resumedResults
        credits = request.resumedCredits
        assessmentDescriptorIDs = request.resumedAssessmentDescriptorIDs
        let restoredAssessmentEvents = request.resumedAssessmentEvents.isEmpty
            ? request.resumedAssessmentDescriptorIDs.map { "answered:\($0)" }
            : request.resumedAssessmentEvents
        assessmentEvents = restoredAssessmentEvents
        let restoredActiveDuration = max(0, request.resumedActiveDurationSeconds)
        cumulativeActiveDuration = restoredActiveDuration
        assessmentPracticeActiveDuration = request.resumedAssessmentPracticeDurationSeconds
        let restoredAssessmentElapsed = max(
            0,
            restoredActiveDuration - request.resumedAssessmentPracticeDurationSeconds
        )
        let restoredDescriptorIDs = Set(restoredAssessmentEvents.compactMap { event -> String? in
            guard let separator = event.firstIndex(of: ":") else { return nil }
            return String(event[event.index(after: separator)...])
        })
        let session = request.assessmentBlock.map { block in
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
                    activeElapsedSeconds: Int(restoredAssessmentElapsed.rounded(.up))
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
            let resolvedItemCount = request.requestedItemCount
                ?? request.requestedMinutes.map { max(3, min(12, $0 / 2)) }
                ?? 5
            let resumeAtSummary = request.resumeCurrentItemWasCommitted
                && request.startingIndex >= resolvedItemCount
            let initialIndex = min(max(0, request.startingIndex), max(0, resolvedItemCount - 1))
            assessmentState = NFAdaptiveAssessmentState()
            assessmentDescriptor = nil
            assessmentStopReason = nil
            itemCount = resolvedItemCount
            index = initialIndex
            exercise = Self.makeExercise(request: request, index: initialIndex, assessmentDescriptor: nil)
            if resumeAtSummary { stage = .summary }
        }
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
                ?? suggestedReflectionCode
            reflectionNote = request.resumedReflectionNote
            stage = .reflection
        }
    }

    var progress: Double {
        if stage == .summary { return 1 }
        if let assessmentSession {
            let itemProgress = Double(assessmentState.completedScorableItems)
                / Double(max(1, assessmentSession.minimumScorableItems))
            let informationProgress = assessmentState.accumulatedInformation
                / max(0.001, assessmentSession.targetInformation)
            return min(1, max(0, min(itemProgress, informationProgress)))
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
                activeElapsedSeconds: Int(assessmentActiveElapsed.rounded(.up))
            )
            return step.shouldStop
                ? NFAppLocalization.localized("View summary", locale: NFAppLocalization.preferredLocale, comment: "Session button shown after the final item.")
                : NFAppLocalization.localized("Next challenge", locale: NFAppLocalization.preferredLocale, comment: "Session button shown between exercises.")
        }
        return index + 1 == itemCount
            ? NFAppLocalization.localized("View summary", locale: NFAppLocalization.preferredLocale, comment: "Session button shown after the final item.")
            : NFAppLocalization.localized("Next challenge", locale: NFAppLocalization.preferredLocale, comment: "Session button shown between exercises.")
    }

    var usesTimedMode: Bool {
        !hidesAssessmentTimer && request.isTimed == true && exercise.timingEligible
    }

    var hidesAssessmentTimer: Bool { assessmentSession != nil || exercise.assessmentProtected }

    var isAssessmentPractice: Bool { assessmentDescriptor?.role == .practice }

    var displayedHint: String? {
        exercise.feedback.hintLadder.first
    }

    var calculationChainDiagnostic: NFCalculationChainDiagnostic? {
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

    var canSkip: Bool { stage == .item && !isAssessmentPractice }

    var canSaveReflection: Bool {
        guard let reflectionTrigger else { return false }
        guard reflectionNote.count <= AttemptReflectionRecord.maximumNoteCharacters else { return false }
        if reflectionTrigger == .weeklyTransfer {
            return !reflectionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return selectedReflectionCode != nil
    }

    var hasSufficientAssessmentEvidence: Bool {
        guard let assessmentSession else { return !correctness.isEmpty }
        return assessmentSession.hasSufficientEvidence(in: assessmentState)
    }

    var correctCount: Int { correctness.filter { $0 }.count }
    var incorrectCount: Int { correctness.count - correctCount }
    var skippedCount: Int { assessmentEvents.filter { $0.hasPrefix("skipped:") }.count }
    var presentedCount: Int { correctness.count + skippedCount }

    private var assessmentActiveElapsed: TimeInterval {
        max(0, cumulativeActiveDuration - assessmentPracticeActiveDuration)
    }

    func activeElapsed(at date: Date = Date()) -> TimeInterval {
        let inProgress = stage == .item
            || stage == .confidence
            || stage == .selfCheckComparison
            ? (responseLockedActiveDuration ?? currentItemActiveDuration(at: date))
            : 0
        return max(0, cumulativeActiveDuration + inProgress)
    }

    func timerLabel(at date: Date = Date()) -> String {
        guard usesTimedMode else {
            return NFAppLocalization.localized("Untimed", locale: NFAppLocalization.preferredLocale, comment: "Session timer status when timing is disabled.")
        }
        guard let requestedMinutes = request.requestedMinutes else {
            return formatClock(activeElapsed(at: date))
        }
        let remaining = max(0, TimeInterval(requestedMinutes * 60) - activeElapsed(at: date))
        return remaining > 0
            ? formatClock(remaining)
            : NFAppLocalization.localized("Time target reached", locale: NFAppLocalization.preferredLocale, comment: "Session timer status after the target duration elapses.")
    }

    func toggleTimerVisibility() {
        timerIsVisible.toggle()
    }

    var canSubmit: Bool {
        if case .selfCheck = exercise.interaction {
            if stage == .selfCheckComparison {
                return selfCheckReferenceRevealed
                    && selfCheckRating != nil
                    && !selfCheckReflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return !selfCheckReflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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

    func submitResponse() {
        guard stage == .item, canSubmit else { return }
        if pendingAttemptID == nil { pendingAttemptID = UUID() }
        responseLockedActiveDuration = currentItemActiveDuration()
        stage = .confidence
    }

    func noteTextResponseInput() {
        inputModality = .keyboard
    }

    func noteDiscreteResponseInput() {
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
              !isCommitInFlight else { return }
        revisionCount += 1
        responseLockedActiveDuration = nil
        pendingSelfCheckConfidence = nil
        selfCheckReferenceRevealed = false
        selfCheckRating = nil
        stage = .item
    }

    func requestHint() {
        guard !showHint else { return }
        showHint = true
        hintCount += 1
    }

    func commit(confidence: ConfidenceLevel, store: AppStore) {
        guard stage == .confidence, !isCommitInFlight else { return }
        if case .selfCheck = exercise.interaction {
            pendingSelfCheckConfidence = confidence
            // Save the learner's pre-reference recall before revealing the key.
            // A restored draft deliberately returns to this unrevealed state.
            guard checkpointDraft(store: store) else { return }
            selfCheckReferenceRevealed = true
            stage = .selfCheckComparison
            return
        }
        persistAttempt(confidence: confidence, store: store)
    }

    func saveSelfCheck(store: AppStore) {
        guard stage == .selfCheckComparison,
              canSubmit,
              let confidence = pendingSelfCheckConfidence else { return }
        persistAttempt(confidence: confidence, store: store)
    }

    private func persistAttempt(confidence: ConfidenceLevel, store: AppStore) {
        guard !isCommitInFlight else { return }
        isCommitInFlight = true
        defer { isCommitInFlight = false }
        let response = makeResponse()
        let score = NFExerciseScoringEngine.score(response, for: exercise)
        let activeDuration = responseLockedActiveDuration ?? currentItemActiveDuration()
        let attemptID = pendingAttemptID ?? UUID()
        pendingAttemptID = attemptID
        do {
            try store.saveExerciseAttempt(
                attemptID: attemptID,
                sessionID: sessionID,
                exercise: exercise,
                response: response,
                result: score,
                confidence: confidence,
                shownAt: shownAt,
                activeDuration: activeDuration,
                source: request.source,
                assessmentBlock: request.assessmentBlock,
                assessmentDescriptorID: assessmentDescriptor?.id,
                assessmentDescriptor: assessmentDescriptor,
                assessmentCycle: request.reassessmentCycle,
                planID: request.planID,
                planBlockID: request.planBlockID,
                hintCount: hintCount,
                inputMode: inputModality.rawValue,
                interruptionCount: interruptionCount,
                revisionCount: revisionCount,
                accommodationFlags: accommodationFlags(store: store),
                // Persist the mode that actually ran. Protected assessment and
                // timing-ineligible items never become speed evidence merely
                // because their parent request asked for timing.
                wasTimed: usesTimedMode
            )
            cumulativeActiveDuration += activeDuration
            if isAssessmentPractice, let descriptorID = assessmentDescriptor?.id {
                assessmentPracticeActiveDuration += activeDuration
                let event = "practice:\(descriptorID)"
                if !assessmentEvents.contains(event) { assessmentEvents.append(event) }
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
            saveError = nil
            reflectionTrigger = store.reflectionTrigger(
                for: score,
                confidence: confidence,
                exercise: exercise,
                source: request.source
            )
            if reflectionTrigger != nil {
                suggestedReflectionCode = score.isCorrect
                    ? nil
                    : NFErrorReflectionCode.candidate(for: score.errorCode, lab: exercise.lab)
                selectedReflectionCode = suggestedReflectionCode
                reflectionNote = ""
                stage = .reflection
            } else {
                stage = .feedback
            }
            _ = persistCheckpoint(
                store: store,
                response: encoded(response),
                hasCommittedCurrentItem: true
            )
        } catch {
            saveError = "The response could not be saved. It remains on this screen so you can retry."
        }
    }

    func saveReflection(store: AppStore) {
        guard canSaveReflection,
              let committedAttemptID,
              let reflectionTrigger,
              let result = lastResult else { return }
        do {
            try store.saveAttemptReflection(
                attemptID: committedAttemptID,
                deterministicErrorCode: result.errorCode,
                selectedErrorCode: selectedReflectionCode,
                trigger: reflectionTrigger,
                note: reflectionNote
            )
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
        if let assessmentSession {
            if isAssessmentPractice {
                let step = NFAssessmentEngine.nextStep(
                    in: assessmentSession,
                    state: assessmentState,
                    activeElapsedSeconds: Int(assessmentActiveElapsed.rounded(.up))
                )
                if let stopReason = step.stopReason {
                    stopAssessment(stopReason, store: store)
                    return
                }
                guard let descriptor = step.item else { return }
                assessmentDescriptor = descriptor
                exercise = Self.makeExercise(
                    request: request,
                    index: index,
                    assessmentDescriptor: descriptor
                )
                prepareNextItem()
                _ = checkpointDraft(store: store)
                return
            }
            let step = NFAssessmentEngine.nextStep(
                in: assessmentSession,
                state: assessmentState,
                activeElapsedSeconds: Int(assessmentActiveElapsed.rounded(.up))
            )
            if let stopReason = step.stopReason {
                stopAssessment(stopReason, store: store)
                return
            }
            guard let descriptor = step.item else { return }
            index = assessmentState.completedScorableItems
            assessmentDescriptor = descriptor
            exercise = Self.makeExercise(
                request: request,
                index: index,
                assessmentDescriptor: descriptor
            )
            prepareNextItem()
            return
        }

        if index + 1 >= itemCount {
            enterSummary()
            _ = checkpointDraft(store: store)
            return
        }
        index += 1
        exercise = Self.makeExercise(
            request: request,
            index: index,
            assessmentDescriptor: nil,
            excludingContentFingerprints: seenQuestionFingerprints
        )
        seenQuestionFingerprints.insert(NFQuestionFingerprint.fingerprint(for: exercise))
        prepareNextItem()
        _ = checkpointDraft(store: store)
    }

    func skip(store: AppStore) {
        guard canSkip, !isCommitInFlight else { return }
        isCommitInFlight = true
        defer { isCommitInFlight = false }
        if pendingAttemptID == nil { pendingAttemptID = UUID() }
        let activeDuration = currentItemActiveDuration()
        do {
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
                wasTimed: usesTimedMode
            )
            cumulativeActiveDuration += activeDuration
            let skippedID = assessmentDescriptor?.id ?? exercise.id
            let skippedEvent = "skipped:\(skippedID)"
            if !assessmentEvents.contains(skippedEvent) {
                assessmentEvents.append(skippedEvent)
            }
            saveError = nil
        } catch {
            saveError = "The skip could not be saved. The item remains on screen so no evidence is lost."
            return
        }

        if let assessmentSession, let assessmentDescriptor {
            assessmentState = assessmentState.appending(assessmentDescriptor)
            let step = NFAssessmentEngine.nextStep(
                in: assessmentSession,
                state: assessmentState,
                activeElapsedSeconds: Int(assessmentActiveElapsed.rounded(.up))
            )
            if let stopReason = step.stopReason {
                stopAssessment(stopReason, store: store)
                return
            }
            guard let descriptor = step.item else { return }
            index = assessmentState.completedScorableItems
            self.assessmentDescriptor = descriptor
            exercise = Self.makeExercise(
                request: request,
                index: index,
                assessmentDescriptor: descriptor
            )
            prepareNextItem()
            _ = checkpointDraft(store: store)
            return
        }

        if index + 1 >= itemCount {
            enterSummary()
            _ = checkpointDraft(store: store)
            return
        }
        index += 1
        exercise = Self.makeExercise(
            request: request,
            index: index,
            assessmentDescriptor: nil,
            excludingContentFingerprints: seenQuestionFingerprints
        )
        seenQuestionFingerprints.insert(NFQuestionFingerprint.fingerprint(for: exercise))
        prepareNextItem()
        _ = checkpointDraft(store: store)
    }

    private func prepareNextItem() {
        stage = .item
        lastResult = nil
        reflectionTrigger = nil
        suggestedReflectionCode = nil
        selectedReflectionCode = nil
        reflectionNote = ""
        committedAttemptID = nil
        shownAt = Date()
        accumulatedPausedDuration = 0
        pauseStartedAt = nil
        isPaused = false
        // Scratchpad content belongs to the whole chapter/session so the
        // completed review can preserve work spanning more than one item.
        showHint = false
        hintCount = 0
        revisionCount = 0
        inputModality = .unknown
        pointerIsOverResponseControl = false
        pendingAttemptID = nil
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
        guard stage != .summary, !isPaused else { return }
        pauseStartedAt = date
        isPaused = true
        interruptionCount += 1
    }

    func resume(at date: Date = Date()) {
        guard isPaused else { return }
        if let pauseStartedAt { accumulatedPausedDuration += max(0, date.timeIntervalSince(pauseStartedAt)) }
        pauseStartedAt = nil
        isPaused = false
    }

    func togglePause() { isPaused ? resume() : pause() }

    func advance(store: AppStore) {
        guard !isPaused else { return }
        switch stage {
        case .item:
            submitResponse()
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
        let inFlightDuration: TimeInterval = switch stage {
        case .item, .confidence, .selfCheckComparison:
            responseLockedActiveDuration ?? currentItemActiveDuration()
        case .reflection, .feedback, .summary:
            0
        }
        let activeDuration = cumulativeActiveDuration + inFlightDuration
        let hasCommittedCurrentItem = stage == .reflection || stage == .feedback || stage == .summary
        let pendingReflectionAttemptID = stage == .reflection ? committedAttemptID : nil
        let pendingReflectionTrigger = stage == .reflection ? reflectionTrigger : nil
        let pendingSelectedReflectionCode = stage == .reflection ? selectedReflectionCode : nil
        let pendingReflectionNote = stage == .reflection ? reflectionNote : nil
        return checkpointDraft(using: {
            try store.upsertCheckpoint(
                sessionID: sessionID,
                request: request,
                currentIndex: index,
                itemCount: itemCount,
                response: encoded(makeResponse()),
                scratchpad: scratchpad,
                results: correctness,
                credits: credits,
                assessmentDescriptorIDs: assessmentDescriptorIDs,
                assessmentEvents: assessmentEvents,
                activeDurationSeconds: activeDuration,
                assessmentStopReason: assessmentStopReason,
                pendingReflectionAttemptID: pendingReflectionAttemptID,
                reflectionTrigger: pendingReflectionTrigger,
                selectedReflectionCode: pendingSelectedReflectionCode,
                reflectionNote: pendingReflectionNote,
                hasCommittedCurrentItem: hasCommittedCurrentItem,
                isComplete: stage == .summary && hasSufficientAssessmentEvidence
            )
        })
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

    @discardableResult
    func finish(store: AppStore) -> Bool {
        checkpointDraft(store: store)
    }

    private func stopAssessment(_ reason: NFAssessmentStopReason, store: AppStore) {
        assessmentStopReason = reason
        enterSummary()
        _ = checkpointDraft(store: store)
    }

    @discardableResult
    private func persistCheckpoint(
        store: AppStore,
        response: String,
        hasCommittedCurrentItem: Bool,
        isComplete: Bool = false
    ) -> Bool {
        let pendingReflectionAttemptID = stage == .reflection ? committedAttemptID : nil
        let pendingReflectionTrigger = stage == .reflection ? reflectionTrigger : nil
        let pendingSelectedReflectionCode = stage == .reflection ? selectedReflectionCode : nil
        let pendingReflectionNote = stage == .reflection ? reflectionNote : nil
        return checkpointDraft(using: {
            try store.upsertCheckpoint(
                sessionID: sessionID,
                request: request,
                currentIndex: index,
                itemCount: itemCount,
                response: response,
                scratchpad: scratchpad,
                results: correctness,
                credits: credits,
                assessmentDescriptorIDs: assessmentDescriptorIDs,
                assessmentEvents: assessmentEvents,
                activeDurationSeconds: cumulativeActiveDuration,
                assessmentStopReason: assessmentStopReason,
                pendingReflectionAttemptID: pendingReflectionAttemptID,
                reflectionTrigger: pendingReflectionTrigger,
                selectedReflectionCode: pendingSelectedReflectionCode,
                reflectionNote: pendingReflectionNote,
                hasCommittedCurrentItem: hasCommittedCurrentItem,
                isComplete: isComplete
            )
        })
    }

    private func enterSummary() {
        stage = .summary
        pauseStartedAt = nil
        isPaused = false
        showScratchpad = false
    }

    private func currentItemActiveDuration(at date: Date = Date()) -> TimeInterval {
        let ongoingPause = pauseStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return max(
            0,
            date.timeIntervalSince(shownAt) - accumulatedPausedDuration - ongoingPause
        )
    }

    private func formatClock(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func prepareInteraction() {
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
        switch exercise.interaction {
        case let .orderedSteps(schema): orderedStepIDs = schema.steps.map(\.id)
        case let .claimEvidence(schema):
            claimSelections = Dictionary(uniqueKeysWithValues: schema.claims.map { ($0.id, Set<String>()) })
        case let .logicState(schema):
            logicState = Dictionary(uniqueKeysWithValues: schema.expectedFinalState.keys.map { ($0, "") })
        default: orderedStepIDs = []
        }
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
            .claimEvidence(NFClaimEvidenceSubmission(pairs: claimSelections.map {
                NFClaimEvidencePair(claimID: $0.key, evidenceIDs: $0.value.sorted())
            }))
        case .logicState:
            .logicState(NFLogicStateSubmission(finalState: logicState, violatedRuleID: violatedRuleID))
        }
    }

    private func accommodationFlags(store: AppStore) -> [String] {
        var flags: [String] = []
        if store.profile?.hideTimers == true { flags.append("timersHidden") }
        if store.profile?.reducedMotion == true { flags.append("reducedMotion") }
        if store.profile?.excludeVisualSpatial == true { flags.append("visualSpatialExcluded") }
        return flags
    }

    private func encoded(_ response: NFExerciseResponse) -> String {
        guard let data = try? JSONEncoder().encode(response) else { return "" }
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
            claimSelections = Dictionary(uniqueKeysWithValues: submission.pairs.map { ($0.claimID, Set($0.evidenceIDs)) })
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
            excludingContentFingerprints: excludingContentFingerprints
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
    @State private var saveAndClosePending = false
    @State private var showsAllReflectionReasons = false
    @FocusState private var responseFocus: ResponseFocus?

    init(request: SessionRequest) {
        _runtime = State(initialValue: NFUniversalSessionRuntime(request: request))
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                if runtime.stage != .summary {
                    header
                    Divider().opacity(0.5)
                }
                Group {
                    switch runtime.stage {
                    case .item, .selfCheckComparison: itemView
                    case .confidence: confidenceView
                    case .reflection: reflectionView
                    case .feedback: feedbackView
                    case .summary: summaryView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityHidden(runtime.isPaused)
            if runtime.isPaused {
                pauseOverlay
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
            }
        }
        .accessibilityIdentifier("universal-session")
        .nfDesktopPresentationFrame(
            minWidth: dynamicTypeSize.isAccessibilitySize ? 560 : 620,
            idealWidth: 860,
            minHeight: 600,
            idealHeight: 800
        )
        .interactiveDismissDisabled(runtime.stage != .summary || runtime.saveError != nil)
        .sheet(isPresented: $runtime.showScratchpad) { ScratchpadView(text: $runtime.scratchpad) }
        .sheet(isPresented: $runtime.showReport) {
            ReportExerciseView(
                exercise: runtime.exercise,
                assessmentDescriptorID: runtime.assessmentDescriptor?.id
            )
        }
        .alert("Save interrupted", isPresented: Binding(
            get: { runtime.saveError != nil },
            set: {
                if !$0 {
                    runtime.saveError = nil
                    saveAndClosePending = false
                }
            }
        )) {
            if saveAndClosePending {
                Button("Retry") { attemptSaveAndClose() }
                Button("Discard unsaved changes", role: .destructive) { discardAndClose() }
                Button("Keep session open", role: .cancel) { saveAndClosePending = false }
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { Text(LocalizedStringKey(runtime.saveError ?? "")) }
        .task {
            sessionCommands.activate(
                requestID: runtime.request.id,
                capabilities: runtime.commandCapabilities
            )
            _ = runtime.checkpointDraft(store: store)
            focusFirstResponseFieldIfNeeded()
        }
        .onDisappear {
            sessionCommands.deactivate(requestID: runtime.request.id)
        }
        .onChange(of: runtime.commandCapabilities) { _, capabilities in
            sessionCommands.update(
                requestID: runtime.request.id,
                capabilities: capabilities
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                runtime.pause()
                _ = runtime.checkpointDraft(store: store)
            }
        }
        .onChange(of: runtime.stage) { _, stage in
            if stage == .summary {
                runtime.showScratchpad = false
                responseFocus = nil
            } else if stage == .reflection {
                showsAllReflectionReasons = false
            } else if stage == .item {
                focusFirstResponseFieldIfNeeded()
            }
        }
        .modifier(NFSessionReinforcementModifier(
            stage: runtime.stage,
            isCorrect: runtime.lastResult?.isCorrect,
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
            runtime.advance(store: store)
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
                } else if runtime.usesTimedMode {
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
                    .accessibilityLabel(runtime.timerIsVisible ? "Hide countdown" : "Show countdown")
                } else {
                    Text("Untimed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Untimed session")
                }
            }
        }
    }

    private var sessionUtilityControls: some View {
        HStack(spacing: 4) {
            Button { runtime.showScratchpad = true } label: {
                Image(systemName: "square.and.pencil")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open scratchpad")

            if runtime.stage != .summary {
                Menu {
                    if runtime.canSkip {
                        Button { runtime.skip(store: store) } label: {
                            Label("Skip — no score", systemImage: "forward.end")
                        }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FlowLayout(spacing: 8) {
                    NFStatusPill(text: runtime.exercise.lab.shortTitle, symbol: runtime.exercise.lab.symbol, color: NFTheme.color(for: runtime.exercise.lab.colorToken))
                }
                if let context = runtime.exercise.contextText, !context.isEmpty {
                    NFFormattedLearningText(context, font: .subheadline)
                        .foregroundStyle(.secondary)
                }
                if !runtime.exercise.instructions.isEmpty {
                    Label(runtime.exercise.instructions, systemImage: "list.bullet.clipboard")
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
                representationView
                responseView
                if runtime.showHint, !runtime.exercise.assessmentProtected,
                   let hint = runtime.displayedHint {
                    Label(hint, systemImage: "lightbulb.fill")
                        .font(.subheadline).foregroundStyle(NFTheme.amberForeground).nfCard(cornerRadius: 16, padding: 14)
                }
                HStack {
                    if !runtime.exercise.assessmentProtected, runtime.displayedHint != nil {
                        Button(runtime.showHint ? "Hint shown" : "Use a hint") { runtime.requestHint() }
                            .buttonStyle(.bordered).disabled(runtime.showHint)
                    }
                    if runtime.canSkip {
                        Button("Skip — no score") { runtime.skip(store: store) }
                            .buttonStyle(.bordered)
                            .disabled(runtime.isCommitInFlight)
                    }
                    Spacer()
                    Button(runtime.stage == .selfCheckComparison ? "Save self-check" : "Submit response") {
                        submitCurrentResponse()
                    }
                        .buttonStyle(.borderedProminent)
                        .tint(NFTheme.controlTint(for: runtime.exercise.lab.colorToken))
                        .foregroundStyle(NFTheme.controlForeground(for: runtime.exercise.lab.colorToken))
                        .controlSize(.large).disabled(!runtime.canSubmit)
                        .keyboardShortcut(.defaultAction)
                }
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
    }

    private var selfCheckPreReferenceFooter: String {
        if case .selfCheck = runtime.exercise.interaction {
            return "You’ll rate your confidence before seeing the reference."
        }
        return "You’ll rate your confidence before seeing feedback."
    }

    @ViewBuilder
    private var responseView: some View {
        switch runtime.exercise.interaction {
        case let .numeric(schema):
            HStack(spacing: 12) {
                TextField(schema.placeholder, text: $runtime.numericValue)
                    .textFieldStyle(.roundedBorder).font(.title2.monospacedDigit()).numericKeyboard()
                    .focused($responseFocus, equals: .numericValue)
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
                    .frame(maxWidth: 150)
                    .focused($responseFocus, equals: .numericUnit)
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Arrange the steps").font(.headline)
                ForEach(Array(runtime.orderedStepIDs.enumerated()), id: \.element) { index, id in
                    if let step = schema.steps.first(where: { $0.id == id }) {
                        HStack {
                            Text("\(index + 1)").font(.caption.bold().monospacedDigit()).frame(width: 26, height: 26).background(.secondary.opacity(0.12), in: Circle())
                            Text(step.text)
                            Spacer()
                            Button {
                                runtime.noteDiscreteResponseInput()
                                runtime.moveStep(from: index, offset: -1)
                            } label: {
                                Image(systemName: "arrow.up")
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: self.orderedStepMoveAccessibilityLabel(
                                step: step.text,
                                position: index + 1,
                                movesUp: true
                            )))
                            .disabled(index == 0)
                            .onHover(perform: runtime.setPointerOverResponseControl)
                            Button {
                                runtime.noteDiscreteResponseInput()
                                runtime.moveStep(from: index, offset: 1)
                            } label: {
                                Image(systemName: "arrow.down")
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: self.orderedStepMoveAccessibilityLabel(
                                step: step.text,
                                position: index + 1,
                                movesUp: false
                            )))
                            .disabled(index == runtime.orderedStepIDs.count - 1)
                            .onHover(perform: runtime.setPointerOverResponseControl)
                        }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        case let .shortText(schema):
            VStack(alignment: .trailing, spacing: 6) {
                TextEditor(text: $runtime.shortText)
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
                        : "Answer from memory. You will choose confidence before seeing the reference."
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $runtime.selfCheckReflection)
                .focused($responseFocus, equals: .selfCheck)
                .frame(minHeight: 110)
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .disabled(runtime.selfCheckReferenceRevealed)
                .onChange(of: runtime.selfCheckReflection) { oldValue, newValue in
                    if oldValue != newValue { runtime.noteTextResponseInput() }
                }
                if runtime.selfCheckReferenceRevealed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reference answer")
                            .font(.caption.weight(.semibold))
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
                        }
                        .buttonStyle(.bordered)
                        .tint(selected ? NFTheme.indigo : .secondary)
                        .nfSelectionAccessibility(selected)
                        .onHover(perform: runtime.setPointerOverResponseControl)
                    }
                }
            }
        case let .claimEvidence(schema):
            VStack(alignment: .leading, spacing: 14) {
                ForEach(schema.claims) { claim in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(claim.text).font(.headline)
                        ForEach(schema.evidence) { evidence in
                            let selected = runtime.claimSelections[claim.id, default: []].contains(evidence.id)
                            Button {
                                runtime.noteDiscreteResponseInput()
                                if selected { runtime.claimSelections[claim.id, default: []].remove(evidence.id) }
                                else { runtime.claimSelections[claim.id, default: []].insert(evidence.id) }
                            } label: {
                                HStack(alignment: .top) { Image(systemName: selected ? "checkmark.square.fill" : "square"); Text(evidence.text); Spacer() }
                            }
                            .buttonStyle(.plain)
                            .frame(minHeight: 44)
                            .padding(8)
                            .background(selected ? NFTheme.indigo.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel(Text(verbatim: "\(claim.text): \(evidence.text)"))
                            .nfSelectionAccessibility(selected)
                            .onHover(perform: runtime.setPointerOverResponseControl)
                        }
                    }.nfCard(cornerRadius: 16, padding: 14)
                }
            }
        case let .logicState(schema):
            VStack(alignment: .leading, spacing: 14) {
                ForEach(NFEstimateExactContract.orderedResponseKeys(for: schema), id: \.self) { key in
                    TextField("Response for \(NFEstimateExactContract.localizedResponseLabel(for: key))", text: Binding(
                        get: { runtime.logicState[key, default: ""] },
                        set: {
                            runtime.logicState[key] = $0
                            runtime.noteTextResponseInput()
                        }
                    ))
                        .textFieldStyle(.roundedBorder)
                        .focused($responseFocus, equals: .logic(key))
                        .submitLabel(.next)
                        .onSubmit { focusNextLogicField(after: key, schema: schema) }
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
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
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
        ForEach(Array(runtime.exercise.representations.enumerated()), id: \.offset) { _, representation in
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
                NFFormattedLearningText("```\(language)\n\(source)\n```")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: summary))
            case let .spatial(metadata):
                NFSpatialDiagramView(
                    metadata: metadata,
                    prefersReducedMotion: store.profile?.reducedMotion == true
                )
            case let .logicState(metadata):
                VStack(alignment: .leading, spacing: 6) { ForEach(metadata.transitions) { transition in Text("\(transition.condition) → \(transition.mutation)").font(.body.monospaced()) } }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            case .prose: EmptyView()
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
                    Button { runtime.commit(confidence: level, store: store) } label: {
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
                NFIconTile(symbol: "text.bubble.fill", color: NFTheme.amber, size: 66)
                Text(runtime.reflectionTrigger?.title ?? NFAppLocalization.localized("Brief reflection", locale: NFAppLocalization.preferredLocale, comment: "Fallback title for an item-level reflection."))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .accessibilityHeading(.h1)
                if runtime.reflectionTrigger == .weeklyTransfer {
                    Text("Before the explanation, name what structure carried over—or what made the unfamiliar context difficult.")
                        .foregroundStyle(.secondary)
                    TextField("What did you transfer?", text: $runtime.reflectionNote, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                } else {
                    Text("Your answer did not match. Choose what may have happened before viewing the explanation.")
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
                Button("Save and view explanation") {
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

    private var feedbackView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                            Text(feedbackCreditLabel(for: result))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(result.feedback.explanation).font(.title3)
                    if let trigger = runtime.reflectionTrigger {
                        Label(
                            NFAppLocalization.localized("Your \(trigger.title.lowercased()) was saved separately from the immutable score.", locale: NFAppLocalization.preferredLocale, comment: "Confirmation that an item reflection was saved without changing the score; the placeholder is the localized reflection trigger title."),
                            systemImage: "checkmark.message.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(NFTheme.mintForeground)
                    }
                    if let decisive = result.feedback.decisiveStep { Label(decisive, systemImage: "scope").nfCard(cornerRadius: 16, padding: 14) }
                    if let expected = result.expectedAnswerSummary { LabeledContent("Expected", value: expected).nfCard(cornerRadius: 16, padding: 14) }
                    if let diagnostic = runtime.calculationChainDiagnostic {
                        DisclosureGroup("Replay the calculation chain") {
                            VStack(alignment: .leading, spacing: 9) {
                                Text("This diagnostic is score-preserving: it reconstructs the seeded steps but never changes the submitted attempt.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                    if !runtime.exercise.citations.isEmpty {
                        VStack(alignment: .leading, spacing: 8) { Text("Sources").font(.headline); ForEach(runtime.exercise.citations) { citation in Label(citation.title, systemImage: "quote.opening") } }.nfCard(cornerRadius: 16, padding: 14)
                    }
                    Button { runtime.showReport = true } label: {
                        Label("Report item", systemImage: "exclamationmark.bubble")
                    }
                    .buttonStyle(.bordered)
                }
                Button(runtime.nextActionTitle) { runtime.next(store: store) }
                    .buttonStyle(.borderedProminent)
                    .tint(NFTheme.controlTint(for: "indigo"))
                    .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
    }

    private var summaryView: some View {
        ScrollView {
            VStack(spacing: 20) {
                let assessmentComplete = runtime.hasSufficientAssessmentEvidence
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
                Text(assessmentComplete ? "Session complete" : "More answers needed")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .accessibilityHeading(.h1)
                Grid(horizontalSpacing: 22, verticalSpacing: 8) {
                    GridRow {
                        summaryCount(value: runtime.correctCount, label: "Correct")
                        summaryCount(value: runtime.incorrectCount, label: "Incorrect")
                    }
                    GridRow {
                        summaryCount(value: runtime.skippedCount, label: "Skipped")
                        summaryCount(value: runtime.presentedCount, label: "Presented")
                    }
                }
                .accessibilityElement(children: .combine)
                Text(!assessmentComplete
                     ? runtime.request.source == .reassessment
                        ? "This skill check ended before enough scored answers were completed. Skipped questions do not count; retry to get a fresh set."
                        : runtime.request.source == .baseline
                            ? "This starting skill check ended before enough scored answers were completed. Skipped questions do not count; retry to get a fresh set."
                            : "Answer at least one challenge to complete this session. Skipped questions stay out of progress and rewards."
                     : runtime.request.evidenceClass == .documentPractice
                        ? "Source practice does not change your skill scores."
                     : "Your answers were saved and now update this lab’s progress.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                if assessmentComplete, !runtime.correctness.isEmpty {
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
                            Text("+\(earnedXP) Forge XP")
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
                                Text("Your shortened session is complete; the remaining chapters stay available in Forge.")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    .nfCard(cornerRadius: 16, padding: 14)
                }
                Button(!assessmentComplete ? "Close and retry later" : nextTodayBlock == nil ? "Done" : "Continue to next block") {
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
                    Button("Resume") { runtime.resume() }
                        .buttonStyle(.borderedProminent)
                        .tint(NFTheme.controlTint(for: "indigo"))
                        .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                        .controlSize(.large)
                    if runtime.stage == .reflection {
                        Label("Complete the required reflection before closing this item.", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Save & close") {
                            attemptSaveAndClose()
                        }
                        .buttonStyle(.bordered)
                    }
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
        if runtime.stage == .selfCheckComparison {
            runtime.saveSelfCheck(store: store)
        } else {
            runtime.noteSubmissionControlInputIfNeeded(.keyboard)
            runtime.submitResponse()
        }
    }

    private func attemptSaveAndClose() {
        saveAndClosePending = true
        guard runtime.checkpointDraft(store: store) else { return }
        saveAndClosePending = false
        todaySessionSequence.clear()
        store.activeSessionRequest = nil
        dismiss()
    }

    private func discardAndClose() {
        saveAndClosePending = false
        runtime.saveError = nil
        todaySessionSequence.clear()
        store.activeSessionRequest = nil
        dismiss()
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
                responseFocus = NFEstimateExactContract.orderedResponseKeys(for: schema).first.map(ResponseFocus.logic)
            default: responseFocus = nil
            }
        }
        #endif
    }

    private func focusNextLogicField(after key: String, schema: NFLogicStateResponseSchema) {
        let keys = NFEstimateExactContract.orderedResponseKeys(for: schema)
        guard let index = keys.firstIndex(of: key), keys.indices.contains(index + 1) else {
            if runtime.canSubmit { submitCurrentResponse() }
            return
        }
        responseFocus = .logic(keys[index + 1])
    }

    private func orderedStepMoveAccessibilityLabel(
        step: String,
        position: Int,
        movesUp: Bool
    ) -> String {
        if movesUp {
            return NFAppLocalization.localized(
                "Move step \(position) up: \(step)",
                locale: NFAppLocalization.preferredLocale,
                comment: "Accessibility label for moving an ordered response step up."
            )
        }
        return NFAppLocalization.localized(
            "Move step \(position) down: \(step)",
            locale: NFAppLocalization.preferredLocale,
            comment: "Accessibility label for moving an ordered response step down."
        )
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

private struct ReportExerciseView: View {
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
