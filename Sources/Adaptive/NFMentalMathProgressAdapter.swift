import Foundation

/// The coordinator supplies the effective score and an authenticated retained
/// contract. Missing original content cannot be replaced by parsing display copy.
struct NFMentalMathProgressInput: Sendable {
    let attempt: AttemptDTO
    let response: NFExerciseResponse?
    let exercise: NFExercise?
    var isProtected = false
    var originalRecord: NFImmutableAttemptRecordSnapshot? = nil
}

enum NFMentalMathProgressAdapter {
    static func observations(from inputs: [NFMentalMathProgressInput], at date: Date) -> [NFMentalMathMetricObservation] {
        let eligible = NFProgressEvidenceProjection.eligible(inputs.map(\.attempt), at: date)
        let grouped = Dictionary(grouping: inputs, by: { $0.attempt.id })
        return eligible.compactMap { attempt in
            guard let copies = grouped[attempt.id], let first = copies.first,
                  copies.allSatisfy({ first.response == $0.response && first.exercise == $0.exercise
                    && first.isProtected == $0.isProtected && first.originalRecord == $0.originalRecord
                    && first.attempt.editorialObservation == $0.attempt.editorialObservation
                    && first.attempt.spatialDifficultyParameters == $0.attempt.spatialDifficultyParameters
                    && first.attempt.assessmentFormat == $0.attempt.assessmentFormat }) else { return nil }
            return observation(from: first, at: date)
        }
    }

    /// Compatibility for callers holding only a legacy record. It retains
    /// practice accuracy but grants no component or reviewed-condition evidence.
    static func observations(from attempts: [AttemptRecord], at date: Date = Date()) -> [NFMentalMathMetricObservation] {
        observations(from: attempts.map { .init(attempt: $0.dto, response: nil, exercise: nil,
            isProtected: NFReadOnlyAttemptSnapshot(attempt: $0).source == .protectedAssessment) }, at: date)
    }

    static func observation(from attempt: AttemptRecord, at date: Date = Date()) -> NFMentalMathMetricObservation? {
        observation(from: .init(attempt: attempt.dto, response: nil, exercise: nil,
            isProtected: NFReadOnlyAttemptSnapshot(attempt: attempt).source == .protectedAssessment), at: date)
    }

    static func observation(from input: NFMentalMathProgressInput, at date: Date) -> NFMentalMathMetricObservation? {
        let attempt = input.attempt
        let format = attempt.responseFormatRaw?.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !input.isProtected,
              ![EvidenceClass.assessmentHoldout, .nearTransfer].contains(attempt.evidenceClass),
              date.timeIntervalSinceReferenceDate.isFinite,
              attempt.submittedAt.timeIntervalSinceReferenceDate.isFinite, attempt.submittedAt <= date,
              attempt.lab == .mentalMath, attempt.credit.isFinite, (0...1).contains(attempt.credit),
              attempt.evidenceWeight.isFinite, attempt.evidenceWeight > 0, !attempt.wasSkipped,
              attempt.evidenceClass != .documentPractice,
              !["selfcheck", "sourceselfcheck", "selfreported", "revealed", "solutionrevealed"].contains(format ?? "") else { return nil }

        let exercise = input.exercise.flatMap { value -> NFExercise? in
            guard !input.isProtected, value.id == attempt.itemID, value.lab == attempt.lab, !value.assessmentProtected,
                  value.evidenceClass != .documentPractice, value.sourceContext.sourceDocumentIDs.isEmpty,
                  NFExerciseSchemaValidator.supportsExerciseSchemaVersion(value.schemaVersion),
                  (try? NFExerciseSchemaValidator.validateInteraction(value.interaction)) != nil else { return nil }
            return value
        }
        var estimate: NFExactNumber?
        var exactReference: NFExactNumber?
        var tags: Set<String> = []
        var unitRequired = false
        if let exercise {
            if case let .logicState(schema) = exercise.interaction,
               NFEstimateExactContract.isComposite(schema),
               case let .logicState(submission) = input.response {
                estimate = NFStateValueAuthority.exactNumber(submission.finalState[NFEstimateExactContract.estimateKey] ?? "")
                exactReference = NFStateValueAuthority.exactNumber(schema.expectedFinalState[NFEstimateExactContract.exactKey] ?? "")
                tags.insert("estimate-first")
            }
            if case let .numeric(schema) = exercise.interaction {
                unitRequired = schema.answer.unitRequired
            }
        }
        return NFMentalMathMetricObservation(
            submittedAt: attempt.submittedAt, credit: attempt.credit,
            // Legacy retention/transfer labels describe the activity route; they
            // do not prove a reviewed delay or unfamiliar transfer relationship.
            evidenceClass: .practice, evidenceWeight: attempt.evidenceWeight,
            wasSkipped: attempt.wasSkipped, hintCount: attempt.hintCount,
            interruptionCount: attempt.interruptionCount, wasTimed: false,
            activeDurationSeconds: nil, tags: tags,
            strategyID: nil, strategyWasValid: nil, estimate: estimate, exactReference: exactReference,
            unitRequired: unitRequired, unitWasCorrect: nil
        )
    }
}

@MainActor
extension AppStore {
    func mentalMathMetricObservations(from attempts: [AttemptRecord], at date: Date = Date()) -> [NFMentalMathMetricObservation] {
        NFMentalMathProgressAdapter.observations(from: mentalMathProgressInputs(from: attempts), at: date)
    }

    func mentalMathProgressInputs(from attempts: [AttemptRecord]) -> [NFMentalMathProgressInput] {
        let snapshots = localSessions.archive.snapshots.reduce(into: [UUID: NFExercise]()) { result, snapshot in
            result[snapshot.attemptID] = snapshot.exercise
        }
        return attempts.map { record in
            let protected = historyPresentation(for: .init(attempt: record)).source == .protectedAssessment
            let retained = snapshots[record.id].flatMap { exercise -> NFExercise? in
                guard !protected, exercise.id == record.itemID, exercise.prompt == record.prompt,
                      exercise.templateID == record.templateID, exercise.seed == record.seed else { return nil }
                return exercise
            }
            let response = record.response.data(using: .utf8).flatMap { try? JSONDecoder().decode(NFExerciseResponse.self, from: $0) }
            return NFMentalMathProgressInput(attempt: effectiveAttemptDTO(record), response: response, exercise: retained, isProtected: protected, originalRecord: .init(record))
        }
    }
}
