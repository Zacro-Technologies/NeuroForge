import SwiftUI

struct NFBaselineStart: Equatable, Sendable {
    let block: NFAssessmentBlockKind
    let completedCount: Int
}

struct BaselineOverviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onStart: (NFBaselineStart) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        NFSectionHeader(
                            "Starting skill check",
                            eyebrow: "Choose a block",
                            subtitle: "Complete one short scored block now, or return for the rest later. Results help choose what to practice next."
                        )

                        FlowLayout(spacing: 10) {
                            NFStatusPill(text: "4 blocks", symbol: "square.grid.2x2.fill", color: NFTheme.indigo)
                            NFStatusPill(text: NFAppLocalization.formattedMaximumMinutesEach(8), symbol: "timer", color: NFTheme.cyan)
                            NFStatusPill(text: "Pause between blocks", symbol: "pause.circle.fill", color: NFTheme.mint)
                        }

                        ForEach(NFAssessmentCatalog.baselineBlocks) { definition in
                            blockCard(definition)
                        }

                        if hasEstablishedBaselineEvidence {
                            baselineResultsCard
                        }

                        if allEligibleBaselineBlocksEstablished {
                            reassessmentScheduleCard
                        }

                        DisclosureGroup {
                            Text("Hints and answer feedback stay hidden until a block ends, so later answers are not influenced. Ordinary practice never changes these results.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        } label: {
                            Label("How skill checks stay fair", systemImage: "checkmark.shield.fill")
                                .font(.headline)
                        }
                        .nfCard()
                    }
                    .padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Skill check")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .nfDesktopPresentationFrame(
            minWidth: 420,
            idealWidth: 850,
            minHeight: 620,
            idealHeight: 850
        )
    }

    private var eligibleBaselineDefinitions: [NFAssessmentBlockDefinition] {
        NFAssessmentCatalog.baselineBlocks.filter {
            !($0.kind == .spatialRepresentation && store.profile?.excludeVisualSpatial == true)
        }
    }

    private var hasEstablishedBaselineEvidence: Bool {
        store.baselineDimensionSummaries.contains { $0.evidenceCount > 0 }
    }

    private var allEligibleBaselineBlocksEstablished: Bool {
        !eligibleBaselineDefinitions.isEmpty
            && eligibleBaselineDefinitions.allSatisfy { store.baselineBlockIsEstablished($0.kind) }
    }

    private var baselineResultsCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your starting levels")
                        .font(.title2.bold())
                    Text("Each area stays separate; there is no combined score or percentile.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                NFStatusPill(
                    text: allEligibleBaselineBlocksEstablished ? "Skill check complete" : "In progress",
                    symbol: allEligibleBaselineBlocksEstablished ? "checkmark.seal.fill" : "circle.dotted",
                    color: allEligibleBaselineBlocksEstablished ? NFTheme.mint : NFTheme.amber
                )
            }

            ForEach(NFAssessmentDimension.allCases) { dimension in
                let summary = store.protectedAssessmentDimensionSummaries.first(where: {
                    $0.id == dimension.skillID
                })
                HStack(spacing: 12) {
                    NFIconTile(
                        symbol: dimension.lab.symbol,
                        color: NFTheme.color(for: dimension.lab.colorToken),
                        size: 40
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dimension.title).font(.headline)
                        Text(summary?.status.title ?? NFAppLocalization.localized("Unassessed", locale: NFAppLocalization.preferredLocale, comment: "Baseline result status with no evidence."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if allEligibleBaselineBlocksEstablished {
                            Text(uncertaintyLabel(summary?.uncertainty))
                                .font(.caption.weight(.semibold))
                        }
                        Text(NFAppLocalization.formattedAnswerCount(summary?.evidenceCount ?? 0))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            }

            Divider()

            Label("What happens next", systemImage: "list.bullet.rectangle.fill")
                .font(.headline)
            Text("NeuroForge uses these results to suggest useful practice. Areas without enough answers stay unassessed instead of receiving a low rating.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if allEligibleBaselineBlocksEstablished,
               let uncertain = mostUncertainEstablishedDimension {
                Button {
                    dismiss()
                    Task { @MainActor in
                        await Task.yield()
                        store.beginSession(
                            lab: uncertain.lab,
                            source: .focused,
                            requestedMinutes: 5,
                            evidenceClass: .practice,
                            targetDifficulty: 0.45,
                            isTimed: false
                        )
                    }
                } label: {
                    Label("Review uncertain \(uncertain.title) items", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

        }
        .nfCard(cornerRadius: 20, padding: 16)
    }

    private var mostUncertainEstablishedDimension: NFAssessmentDimension? {
        let summaries = store.protectedAssessmentDimensionSummaries
        return NFAssessmentDimension.allCases.filter { dimension in
            summaries.first(where: { $0.id == dimension.skillID })?.status != .unassessed
        }.max { lhs, rhs in
            let left = summaries.first(where: { $0.id == lhs.skillID })?.uncertainty ?? 1
            let right = summaries.first(where: { $0.id == rhs.skillID })?.uncertainty ?? 1
            if left != right { return left < right }
            return lhs.rawValue > rhs.rawValue
        }
    }

    private func uncertaintyLabel(_ uncertainty: Double?) -> String {
        guard let uncertainty else {
            return NFAppLocalization.localized("Uncertainty unavailable", locale: NFAppLocalization.preferredLocale, comment: "Baseline uncertainty status without enough data.")
        }
        if uncertainty > 0.7 {
            return NFAppLocalization.localized("Wide uncertainty", locale: NFAppLocalization.preferredLocale, comment: "Baseline estimate with a broad uncertainty band.")
        }
        if uncertainty > 0.35 {
            return NFAppLocalization.localized("Moderate uncertainty", locale: NFAppLocalization.preferredLocale, comment: "Baseline estimate with a moderate uncertainty band.")
        }
        return NFAppLocalization.localized("Narrower uncertainty", locale: NFAppLocalization.preferredLocale, comment: "Baseline estimate with a relatively narrow uncertainty band.")
    }

    @ViewBuilder
    private var reassessmentScheduleCard: some View {
        if let status = store.reassessmentStatus() {
            VStack(alignment: .leading, spacing: 8) {
                Label("Reassessment schedule", systemImage: "calendar.badge.clock")
                    .font(.headline)
                if status.isDeferred, let deferredUntil = status.deferredUntil {
                    Text("Cycle \(status.cycle) is deferred until \(NFAppLocalization.formattedDate(deferredUntil, date: .long, time: .omitted)). Deferral does not change progress, active days, or consistency.")
                } else if let dueAt = status.dueAt {
                    Text("Cycle \(status.cycle) has been due since \(NFAppLocalization.formattedDate(dueAt, date: .long, time: .omitted)). It is an optional 4–6 minute protected form and can be opened from Today.")
                } else {
                    Text("The current 28-active-day cycle began \(NFAppLocalization.formattedDate(status.activeDayAnchor, date: .long, time: .omitted)). Recorded: \(NFAppLocalization.formattedActiveDayCount(status.activeDaysCompleted)). Remaining: \(NFAppLocalization.formattedActiveDayCount(status.activeDaysRemaining)).")
                }
                Text("A fresh check updates only the area you complete.")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .nfCard()
        }
    }

    private func blockCard(_ definition: NFAssessmentBlockDefinition) -> some View {
        let completed = completedCount(definition.kind)
        let excluded = definition.kind == .spatialRepresentation && store.profile?.excludeVisualSpatial == true
        let isComplete = store.baselineBlockIsEstablished(definition.kind)
        let needsRetry = store.baselineBlockNeedsRetry(definition.kind)
        let canResume = store.baselineBlockCanResume(definition.kind)
        let progress = min(1, Double(completed) / Double(definition.minimumScorableItems))
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 14) {
                NFIconTile(symbol: symbol(definition.kind), color: color(definition.kind), size: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text(definition.title).font(.title3.bold())
                    Text(NFAssessmentCatalog.dimensions(for: definition.kind).map(\.title).joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                NFStatusPill(
                    text: excluded
                        ? "Excluded"
                        : isComplete
                            ? "Complete"
                            : completedItemLabel(completed),
                    symbol: excluded ? "accessibility" : isComplete ? "checkmark.circle.fill" : "circle.dotted",
                    color: excluded || isComplete ? NFTheme.mint : color(definition.kind)
                )
            }
            if completed == 0 && !excluded {
                Capsule()
                    .fill(Color.secondary.opacity(0.13))
                    .frame(height: 4)
                    .accessibilityElement()
                    .accessibilityLabel("Not started")
                    .accessibilityValue(NFAppLocalization.formattedAnswerRequirement(
                        completed: 0,
                        required: definition.minimumScorableItems
                    ))
            } else {
                ProgressView(value: excluded ? 1 : progress)
                    .tint(excluded ? NFTheme.mint : color(definition.kind))
                    .accessibilityLabel(definition.title)
                    .accessibilityValue(excluded
                                        ? "Excluded"
                                        : NFAppLocalization.formattedAnswerRequirement(
                                            completed: completed,
                                            required: definition.minimumScorableItems
                                        ))
            }
            HStack {
                Text(
                    "\(NFAppLocalization.formattedMinuteRange(definition.targetDurationSeconds / 60, definition.maximumDurationSeconds / 60, style: .compact)) · \(NFAppLocalization.formattedQuestionRange(definition.minimumScorableItems, definition.itemCap))"
                )
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !excluded {
                    if isComplete {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NFTheme.mintForeground)
                            .accessibilityLabel("Completed assessment block")
                    } else {
                        Button(needsRetry ? "Retry" : canResume ? "Resume" : "Start") {
                            onStart(NFBaselineStart(block: definition.kind, completedCount: completed))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(color(definition.kind))
                    }
                }
            }
        }
        .nfCard(cornerRadius: 20, padding: 16)
    }

    private func completedCount(_ block: NFAssessmentBlockKind) -> Int {
        store.baselineScorableAttemptCount(for: block)
    }

    private func completedItemLabel(_ count: Int) -> String {
        switch max(0, count) {
        case 0:
            NFAppLocalization.localized("Not started", locale: NFAppLocalization.preferredLocale, comment: "Baseline block badge before any scored answers exist.")
        case 1:
            NFAppLocalization.formattedItemCount(1)
        default:
            NFAppLocalization.formattedItemCount(count)
        }
    }

    private func symbol(_ block: NFAssessmentBlockKind) -> String {
        switch block { case .numericalFluency: "function"; case .spatialRepresentation: "cube.transparent"; case .scientificDataReasoning: "flask.fill"; case .logicMetacognition: "point.3.connected.trianglepath.dotted" }
    }
    private func color(_ block: NFAssessmentBlockKind) -> Color {
        switch block { case .numericalFluency: NFTheme.indigo; case .spatialRepresentation: NFTheme.cyan; case .scientificDataReasoning: NFTheme.mint; case .logicMetacognition: NFTheme.rose }
    }
}
