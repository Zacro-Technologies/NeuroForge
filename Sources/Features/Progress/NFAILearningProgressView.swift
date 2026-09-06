import SwiftUI

/// The parent owns navigation to the exact saved-answer list. This summary never
/// opens a tutor, requests a new grade or generates new practice by itself.
struct NFAILearningProgressView: View {
    let scopes: [NFAILearningProgress.Scope]
    let onOpenAnswers: (NFAILearningProgress.Scope) -> Void

    var body: some View {
        if !scopes.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Label("Your AI practice", systemImage: "sparkles").font(.title2.bold())
                Text("Credit describes these saved answers, including accepted grade reviews.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(scopes) { scope in
                    NFAILearningScopeCard(scope: scope) { onOpenAnswers(scope) }
                }
            }.accessibilityIdentifier("ai-learning-progress")
        }
    }
}

private struct NFAILearningScopeCard: View {
    let scope: NFAILearningProgress.Scope
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(scope.title).font(.headline)
            if let topic = scope.topic { Text(topic).font(.subheadline).foregroundStyle(.secondary) }
            LabeledContent("Evaluated answers", value: scope.attemptCount.formatted())
            LabeledContent("Earned credit", value: "\(scope.earnedCredit.formatted(.number.precision(.fractionLength(0...2)))) / \(scope.attemptCount.formatted())")
            if let focus = scope.latestCriterionNeedingWork {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A criterion to practise").font(.subheadline.bold())
                    Text(focus.criterion)
                    Text(focus.explanation).font(.callout)
                    if let nextStep = focus.nextStep { Text(nextStep).font(.callout) }
                    HStack {
                        Text("From a saved answer")
                        Text(focus.submittedAt, style: .date)
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
            if let latest = scope.answers.first {
                DisclosureGroup("Original feedback") {
                    Text(latest.originalFeedback).font(.callout)
                }
            }
            Button(action: open) {
                Label("View these saved answers", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.bordered).accessibilityIdentifier("ai-learning-scope-\(scope.id)")
        }.nfCard()
    }
}
