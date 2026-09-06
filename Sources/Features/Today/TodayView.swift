import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(NFNavigationState.self) private var navigation
    @Environment(NFTodaySessionSequence.self) private var todaySessionSequence
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedBlock: PlanBlock?
    @State private var selectedCompletedBlock: PlanBlock?
    @State private var showsCompletedPlanReview = false
    @State private var showsAdaptivePlanHistory = false
    @State private var pendingSessionBlock: PlanBlock?
    @State private var pendingReplacementAcknowledgement: NFTodayReplacementAcknowledgement?
    @State private var readinessImpact: NFTodayReadinessImpact?
    @State private var readinessPreview: NFTodayReadinessPreview?
    @State private var showSessionIntro = false
    @State private var showBaseline = false
    @State private var pendingBaselineStart: NFBaselineStart?

    private var executablePlan: DailyPlan {
        store.reviewExecutionPlan(store.todayPlan, at: Date(), calendar: .current)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return NFAppLocalization.localized("Good morning", locale: NFAppLocalization.preferredLocale, comment: "Time-of-day greeting on the Today screen.")
        case 12..<18:
            return NFAppLocalization.localized("Good afternoon", locale: NFAppLocalization.preferredLocale, comment: "Time-of-day greeting on the Today screen.")
        default:
            return NFAppLocalization.localized("Good evening", locale: NFAppLocalization.preferredLocale, comment: "Time-of-day greeting on the Today screen.")
        }
    }

    private func readinessBinding(for plan: DailyPlan) -> Binding<Readiness> {
        Binding(
            get: { store.readiness },
            set: { proposed in
                guard proposed != store.readiness else { return }
                let hasStarted = store.attempts.contains { $0.planID == plan.id }
                    || store.sessionCheckpoints.contains { $0.planID == plan.id }
                    || store.activeSessionRequest?.planID == plan.id
                readinessPreview = NFTodayReadinessPreview(plan: plan,
                    completedBlockIDs: store.completedPlanBlockIDs(planID: plan.id),
                    currentReadiness: store.readiness, proposedReadiness: proposed,
                    preservesRemainingPlan: hasStarted || plan.policyVersion != NFDailyScheduler.policyVersion)
            }
        )
    }

    var body: some View {
        NavigationStack(path: Binding(get: { navigation.today }, set: { navigation.today = $0 })) {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        greetingAndDate
                        // Keep the sheet presenter alive when ending the last
                        // saved run removes its card. The learner still needs
                        // to read and dismiss that run's committed summary.
                        ZStack(alignment: .topLeading) {
                            NFContinueSessionsCard()
                            if store.resumableSessions.isEmpty && store.generatedPracticeDrafts.isEmpty {
                                prescriptionHero
                            }
                        }
                        reviewShortcut
                        planSection
                        quickPractice
                        DisclosureGroup("More for today") {
                            VStack(alignment: .leading, spacing: 24) {
                                baselineCard
                                abilityCores
                                weeklyMission
                                forgeMilestones
                                sideQuests
                            }.padding(.top, 12)
                        }
                    }
                    .frame(maxWidth: 980, alignment: .leading)
                    .padding(.horizontal, horizontalSizeClass == .compact ? 16 : 20)
                    .containerRelativeFrame(.horizontal) { availableWidth, _ in
                        min(availableWidth, 1_020)
                    }
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle("Today")
            .sheet(item: $readinessPreview) { preview in
                NFTodayReadinessPreviewView(preview: preview,
                    onCancel: { readinessPreview = nil },
                    onApply: {
                        readinessPreview = nil
                        applyReadiness(preview.proposedReadiness)
                    })
            }
            .sheet(item: $selectedBlock) { block in
                let persistedReason = persistedReplacementReason(for: block.id)
                let acknowledgement = pendingReplacementAcknowledgement.flatMap {
                    $0.replacementBlockID == block.id ? $0 : nil
                }
                PlanBlockDetailView(
                    block: block,
                    canReplace: store.canReplaceTodayPlanBlock(block.id),
                    persistedReplacementReason: persistedReason,
                    replacementAcknowledgement: acknowledgement,
                    onStart: {
                        pendingSessionBlock = block
                        selectedBlock = nil
                    },
                    onPreviewReplacement: { reason in
                        try store.previewTodayPlanBlockReplacement(block.id, reason: reason)
                    },
                    onReplace: { preview in
                        guard let reason = preview.proposedPlan.replacement?.reason else { return }
                        if let replacement = store.replaceTodayPlanBlock(block.id, reason: reason, preview: preview) {
                            pendingReplacementAcknowledgement = makeReplacementAcknowledgement(
                                originalBlock: block,
                                replacementBlock: replacement
                            )
                            // The replacement is acknowledged in this sheet before
                            // any daily-plan launch, so do not race a root alert over
                            // the newly persisted replacement details.
                            store.notice = nil
                            selectedBlock = replacement
                        }
                    },
                    onAcknowledgeReplacement: {
                        pendingReplacementAcknowledgement = nil
                    }
                )
            }
            .sheet(item: $selectedCompletedBlock) { block in
                NFCompletedTodayReviewView(
                    plan: store.todayPlan,
                    completedBlockIDs: store.completedPlanBlockIDs(planID: store.todayPlan.id),
                    attempts: store.attempts,
                    checkpoints: store.sessionCheckpoints,
                    focusedBlockID: block.id
                )
            }
            .sheet(isPresented: $showsCompletedPlanReview) {
                NFCompletedTodayReviewView(
                    plan: store.todayPlan,
                    completedBlockIDs: store.completedPlanBlockIDs(planID: store.todayPlan.id),
                    attempts: store.attempts,
                    checkpoints: store.sessionCheckpoints
                )
            }
            .sheet(isPresented: $showsAdaptivePlanHistory) {
                NFAdaptivePlanHistoryView()
                    .environment(store)
            }
            .sheet(isPresented: $showSessionIntro) {
                TodaySessionIntroView(
                    plan: executablePlan,
                    completedBlockIDs: store.completedPlanBlockIDs(planID: store.todayPlan.id)
                ) { selectedBlockIDs in
                    showSessionIntro = false
                    Task { @MainActor in
                        await Task.yield()
                        _ = todaySessionSequence.start(
                            plan: store.todayPlan,
                            blockIDs: selectedBlockIDs,
                            store: store
                        )
                    }
                }
            }
            .sheet(isPresented: $showBaseline) {
                BaselineOverviewView { start in
                    pendingBaselineStart = start
                    showBaseline = false
                }
                .environment(store)
            }
            .onAppear {
                _ = store.refreshReassessmentSchedule()
                presentRequestedPlanIfNeeded()
                presentRequestedCompletedReviewIfNeeded()
                if store.shouldOpenBaseline {
                    store.consumeBaselineRequest()
                    showBaseline = true
                }
            }
            .onChange(of: store.shouldOpenTodayPlan) { _, _ in
                presentRequestedPlanIfNeeded()
            }
            .onChange(of: store.shouldOpenCompletedTodayReview) { _, _ in
                presentRequestedCompletedReviewIfNeeded()
            }
            .onChange(of: store.readiness) { _, readiness in
                if readinessImpact?.newReadiness != readiness {
                    readinessImpact = nil
                }
            }
            .onChange(of: selectedBlock) { _, block in
                guard block == nil, let pendingSessionBlock else { return }
                self.pendingSessionBlock = nil
                Task { @MainActor in
                    await Task.yield()
                    _ = todaySessionSequence.start(
                        plan: store.todayPlan,
                        blockIDs: [pendingSessionBlock.id],
                        store: store
                    )
                }
            }
            .onChange(of: showBaseline) { _, isShowing in
                guard !isShowing, let start = pendingBaselineStart else { return }
                pendingBaselineStart = nil
                Task { @MainActor in
                    await Task.yield()
                    let definition = NFAssessmentCatalog.definition(for: start.block)
                    store.beginSession(
                        lab: definition.coveredLabs.first ?? .mentalMath,
                        source: .baseline,
                        requestedMinutes: Int(ceil(Double(definition.maximumDurationSeconds) / 60)),
                        evidenceClass: .assessmentHoldout,
                        targetDifficulty: 0.5,
                        requestedItemCount: definition.minimumScorableItems,
                        startingIndex: start.completedCount,
                        assessmentBlock: start.block,
                        seedOverride: AdaptiveEngine.fnv1a64("baseline|v1|\(store.profileSnapshot.id.uuidString)")
                    )
                }
            }
        }
    }

    private var reviewShortcut: some View {
        let due = store.readyReviewEntries(at: Date(), calendar: .current).count
        return Button {
            NFAppPreferenceScope.defaults.set("Review", forKey: "nf.progress.section")
            store.selectedDestination = .progress
        } label: {
            HStack {
                Label(due > 0 ? "Ready to review" : "You're up to date.", systemImage: "clock.arrow.circlepath")
                Spacer()
                if due > 0 { Text(NFAppLocalization.formattedQuestionCount(due)) }
                Image(systemName: "chevron.right")
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private var baselineCard: some View {
        let completedBlocks = eligibleBaselineDefinitions.filter { definition in
            store.baselineBlockIsEstablished(definition.kind)
        }.count
        let requiredBlocks = eligibleBaselineDefinitions.count
        return Group {
            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        baselineIcon
                        baselineTitle
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    baselineDescription
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        baselineProgress(completedBlocks: completedBlocks, requiredBlocks: requiredBlocks)
                        Spacer(minLength: 12)
                        baselineButton
                    }
                }
            } else {
                HStack(spacing: 16) {
                    baselineIcon
                    baselineCopy
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 7) {
                        baselineProgress(completedBlocks: completedBlocks, requiredBlocks: requiredBlocks)
                        baselineButton
                    }
                }
            }
        }
        .nfCard(cornerRadius: 20, padding: 16)
    }

    private var eligibleBaselineDefinitions: [NFAssessmentBlockDefinition] {
        NFAssessmentCatalog.baselineBlocks.filter {
            !($0.kind == .spatialRepresentation && store.profile?.excludeVisualSpatial == true)
        }
    }

    private var baselineIsComplete: Bool {
        !eligibleBaselineDefinitions.isEmpty
            && eligibleBaselineDefinitions.allSatisfy {
                store.baselineBlockIsEstablished($0.kind)
            }
    }

    private var baselineIcon: some View {
        NFIconTile(
            symbol: "dial.medium.fill",
            color: NFTheme.cyan,
            size: 54
        )
    }

    private var baselineCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            baselineTitle
            baselineDescription
        }
    }

    private var baselineTitle: some View {
        Text("Starting skill check")
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var baselineDescription: some View {
        Text("Choose any short block to give recommendations a better starting point. You can finish the rest later.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func baselineProgress(completedBlocks: Int, requiredBlocks: Int) -> some View {
        Text("\(completedBlocks) / \(requiredBlocks) blocks")
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private var baselineButton: some View {
        Button("Choose a block") { showBaseline = true }
            .buttonStyle(.bordered)
            .tint(NFTheme.cyanForeground)
    }

    @ViewBuilder
    private var reassessmentCard: some View {
        if let status = store.reassessmentStatus() {
            let definition = status.block.map { NFAssessmentCatalog.definition(for: $0) }
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    NFIconTile(
                        symbol: status.isDue ? "arrow.triangle.2.circlepath.circle.fill" : "calendar.badge.clock",
                        color: status.isDue ? NFTheme.amber : NFTheme.indigo,
                        size: 50
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(status.isDue ? "Reassessment due" : status.isDeferred ? "Reassessment deferred" : "Next reassessment")
                            .font(.headline)
                        Text(reassessmentTimingText(status))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    NFStatusPill(
                        text: status.isDue
                            ? NFAppLocalization.formattedMinuteRange(4, 6, style: .compact)
                            : NFAppLocalization.localized("\(status.activeDaysCompleted) / \(status.activeDaysRequired) days",
                                locale: NFAppLocalization.preferredLocale,
                                comment: "Weekly-assessment readiness progress; placeholders are completed and required active days."
                            ),
                        symbol: status.isDue ? "timer" : "calendar",
                        color: status.isDue ? NFTheme.amber : NFTheme.indigo
                    )
                }

                if let definition {
                    Text("Cycle \(status.cycle) assesses \(definition.title.lowercased()) only; other skill estimates are left unchanged. The prompt is optional and never blocks today’s plan.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if status.isDue {
                    ViewThatFits(in: .horizontal) {
                        HStack { reassessmentActions(status) }
                        VStack(alignment: .leading, spacing: 10) { reassessmentActions(status) }
                    }
                }
            }
            .nfCard(cornerRadius: 20, padding: 16)
        }
    }

    @ViewBuilder
    private func reassessmentActions(_ status: NFReassessmentStatus) -> some View {
        Button("Start reassessment") {
            store.beginDueReassessment()
        }
        .buttonStyle(.borderedProminent)
        .tint(NFTheme.controlTint(for: "orange"))
        .foregroundStyle(NFTheme.controlForeground(for: "orange"))
        if status.canDefer {
            Button("Defer seven days") {
                store.deferDueReassessment()
            }
            .buttonStyle(.bordered)
        }
    }

    private func reassessmentTimingText(_ status: NFReassessmentStatus) -> String {
        if status.isDeferred, let deferredUntil = status.deferredUntil {
            return NFAppLocalization.localized("Deferred until \(localizedLongDate(deferredUntil)). Progress and consistency are unchanged.", locale: NFAppLocalization.preferredLocale, comment: "Reassessment timing status; the placeholder is a locale-formatted date.")
        }
        if let dueAt = status.dueAt {
            return NFAppLocalization.localized("Due since \(localizedLongDate(dueAt)) after 28 active days.", locale: NFAppLocalization.preferredLocale, comment: "Reassessment due status; the placeholder is a locale-formatted date.")
        }
        return NFAppLocalization.localized(
            "Active-day cycle began \(localizedLongDate(status.activeDayAnchor)). Remaining: \(NFAppLocalization.formattedActiveDayCount(status.activeDaysRemaining)).",
            locale: NFAppLocalization.preferredLocale,
            comment: "Reassessment-cycle status with a locale-formatted date and localized remaining active-day count."
        )
    }

    private func localizedLongDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .year()
                .month(.wide)
                .day()
                .locale(NFAppLocalization.preferredLocale)
        )
    }

    private var header: some View {
        let progress = store.forgeProgress
        return VStack(alignment: .leading, spacing: 14) {
            Group {
                if usesStackedAccessibilityLayout {
                    VStack(alignment: .leading, spacing: 12) {
                        greetingAndDate
                        forgeStatus(progress, stacked: true)
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .bottom, spacing: 18) {
                            greetingAndDate
                            Spacer(minLength: 16)
                            forgeStatus(progress, stacked: false)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            greetingAndDate
                            forgeStatus(progress, stacked: false)
                        }
                    }
                }
            }

            Group {
                if usesStackedAccessibilityLayout {
                    VStack(alignment: .leading, spacing: 8) {
                        forgeRankLabel(level: progress.level)
                        NFForgeProgressBar(
                            progress: progress.levelProgress,
                            accent: NFTheme.gold,
                            secondary: NFTheme.rose,
                            height: 7
                        )
                        forgeXPLabel(progress.xpToNextLevel)
                    }
                } else {
                    HStack(spacing: 10) {
                        forgeRankLabel(level: progress.level)
                        NFForgeProgressBar(
                            progress: progress.levelProgress,
                            accent: NFTheme.gold,
                            secondary: NFTheme.rose,
                            height: 7
                        )
                        forgeXPLabel(progress.xpToNextLevel)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Level \(progress.level), \(progress.xpToNextLevel) XP to the next level")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var usesStackedAccessibilityLayout: Bool {
        horizontalSizeClass == .compact && dynamicTypeSize.isAccessibilitySize
    }

    private func forgeRankLabel(level: Int) -> some View {
        let rank = forgeRankTitle(level: level)
        return Text(
            usesStackedAccessibilityLayout
                ? rank.replacingOccurrences(of: " ", with: "\n")
                : rank
        )
            .font(.caption.weight(.bold))
            .foregroundStyle(NFTheme.violetForeground)
            .textCase(.uppercase)
            .lineLimit(usesStackedAccessibilityLayout ? 2 : 1)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func forgeXPLabel(_ xp: Int) -> some View {
        Text("\(xp) XP")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }

    private var greetingAndDate: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(
                usesStackedAccessibilityLayout
                    ? greeting.replacingOccurrences(of: " ", with: "\n")
                    : greeting
            )
                .font(.system(
                    usesStackedAccessibilityLayout ? .title : .largeTitle,
                    design: .rounded,
                    weight: .bold
                ))
                .lineLimit(usesStackedAccessibilityLayout ? 2 : 1)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(
                usesStackedAccessibilityLayout
                    ? Date.now.formatted(
                        .dateTime
                            .weekday(.abbreviated)
                            .month(.abbreviated)
                            .day()
                            .locale(NFAppLocalization.preferredLocale)
                    )
                    : Date.now.formatted(
                        .dateTime
                            .weekday(.wide)
                            .month(.wide)
                            .day()
                            .locale(NFAppLocalization.preferredLocale)
                    )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(usesStackedAccessibilityLayout ? 2 : 1)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func forgeStatus(_ progress: NFForgeProgressSnapshot, stacked: Bool) -> some View {
        if stacked {
            VStack(alignment: .leading, spacing: 8) {
                forgeLevelPill(progress)
                forgeStreakPill(progress)
            }
        } else {
            HStack(spacing: 8) {
                forgeLevelPill(progress)
                forgeStreakPill(progress)
            }
        }
    }

    private func forgeLevelPill(_ progress: NFForgeProgressSnapshot) -> some View {
            NFStatusPill(
                text: "Level \(progress.level)",
                symbol: "sparkles",
                color: NFTheme.gold
            )
    }

    private func forgeStreakPill(_ progress: NFForgeProgressSnapshot) -> some View {
            NFStatusPill(
                text: NFAppLocalization.localized(
                    "\(progress.momentum.currentActiveDayStreak) active-day streak",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Today status badge with a complete, contextual active-day streak value."
                ),
                symbol: "flame.fill",
                color: NFTheme.rose
            )
    }

    private func forgeRankTitle(level: Int) -> String {
        switch level {
        case 1...2: NFAppLocalization.localized("Curious Spark", locale: NFAppLocalization.preferredLocale, comment: "Cosmetic Forge activity rank.")
        case 3...4: NFAppLocalization.localized("Pattern Scout", locale: NFAppLocalization.preferredLocale, comment: "Cosmetic Forge activity rank.")
        case 5...7: NFAppLocalization.localized("Circuit Builder", locale: NFAppLocalization.preferredLocale, comment: "Cosmetic Forge activity rank.")
        case 8...11: NFAppLocalization.localized("Systems Solver", locale: NFAppLocalization.preferredLocale, comment: "Cosmetic Forge activity rank.")
        case 12...15: NFAppLocalization.localized("STEM Pathfinder", locale: NFAppLocalization.preferredLocale, comment: "Cosmetic Forge activity rank.")
        default: NFAppLocalization.localized("Polymath", locale: NFAppLocalization.preferredLocale, comment: "Cosmetic Forge activity rank.")
        }
    }

    private func readinessPicker(plan: DailyPlan) -> some View {
        let readiness = readinessBinding(for: plan)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("Energy", systemImage: store.readiness.symbol)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Energy today", selection: readiness) {
                    ForEach(Readiness.allCases) { level in
                        Label(level.title, systemImage: level.symbol).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("today-readiness-picker")
                .accessibilityValue(store.readiness.title)
            }

            Text(currentReadinessSnapshot.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let readinessImpact, readinessImpact.newReadiness == store.readiness {
                Divider()
                Label("Why this changed", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NFTheme.cyanForeground)
                Text(readinessImpact.changeSummary)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Text(readinessImpact.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 430)
        .nfCard(cornerRadius: 14, padding: 10)
        .accessibilityElement(children: .contain)
        .accessibilityHint("Preview the effect before applying an energy change")
    }

    private var prescriptionHero: some View {
        let plan = executablePlan
        let completedIDs = store.completedPlanBlockIDs(planID: plan.id)
        let completedMinutes = plan.blocks
            .filter { completedIDs.contains($0.id) }
            .reduce(0) { $0 + $1.minutes }
        let remainingMinutes = max(0, plan.minutes - completedMinutes)
        let remainingBlocks = plan.blocks.filter { !completedIDs.contains($0.id) }
        let planIsComplete = !plan.blocks.isEmpty && remainingBlocks.isEmpty
        let completion = plan.minutes == 0 ? 0 : min(1, Double(completedMinutes) / Double(plan.minutes))

        return Group {
            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: 16) {
                    if usesStackedAccessibilityLayout {
                        VStack(alignment: .leading, spacing: 14) {
                            prescriptionRing(minutes: remainingMinutes, completion: completion, size: 88, lineWidth: 9)
                            compactPrescriptionCopy(
                                planIsComplete: planIsComplete,
                                completedIDsAreEmpty: completedIDs.isEmpty,
                                remainingBlockCount: remainingBlocks.count
                            )
                        }
                    } else {
                        HStack(spacing: 16) {
                            prescriptionRing(minutes: remainingMinutes, completion: completion, size: 88, lineWidth: 9)
                            compactPrescriptionCopy(
                                planIsComplete: planIsComplete,
                                completedIDsAreEmpty: completedIDs.isEmpty,
                                remainingBlockCount: remainingBlocks.count
                            )
                        }
                    }

                    startSessionButton
                        .frame(maxWidth: .infinity)
                    heroControls(plan: plan, planIsComplete: planIsComplete, remainingBlockCount: remainingBlocks.count)
                }
            } else {
                HStack(spacing: 22) {
                    prescriptionRing(minutes: remainingMinutes, completion: completion, size: 116, lineWidth: 11)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("DAILY CIRCUIT")
                            .font(.caption.weight(.heavy))
                            .tracking(1.8)
                            .foregroundStyle(NFTheme.cyanForeground)
                        Text(planIsComplete
                             ? "Circuit complete. Nice work."
                             : completedIDs.isEmpty ? "Your all-round workout is ready." : "Keep your circuit moving.")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text(planIsComplete
                             ? "Every chapter is saved. Free practice is still open."
                             : "\(NFAppLocalization.formattedChapterCount(remainingBlocks.count)) · \(NFAppLocalization.formattedMinutes(remainingMinutes, style: .compact)) · +\(remainingBlocks.count * NFForgeProgressEngine.xpPerEligibleCompletedSession) completion XP")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        startSessionButton
                            .frame(maxWidth: 310)
                        heroControls(plan: plan, planIsComplete: planIsComplete, remainingBlockCount: remainingBlocks.count)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .nfGameCard(accent: NFTheme.violet, secondary: NFTheme.cyan, cornerRadius: 30, padding: 22)
    }

    private func compactPrescriptionCopy(
        planIsComplete: Bool,
        completedIDsAreEmpty: Bool,
        remainingBlockCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DAILY CIRCUIT")
                .font(.caption2.weight(.heavy))
                .tracking(1.5)
                .foregroundStyle(NFTheme.cyanForeground)
            Text(planIsComplete
                 ? "Circuit complete. Nice work."
                 : completedIDsAreEmpty ? "Your all-round workout is ready." : "Keep your circuit moving.")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(planIsComplete
                 ? "Every chapter is saved. Free practice is still open."
                 : "\(NFAppLocalization.formattedChapterCount(remainingBlockCount)) · +\(remainingBlockCount * NFForgeProgressEngine.xpPerEligibleCompletedSession) completion XP")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startSessionButton: some View {
        let plan = executablePlan
        let completed = store.completedPlanBlockIDs(planID: plan.id)
        let planIsComplete = !plan.blocks.isEmpty && plan.blocks.allSatisfy { completed.contains($0.id) }
        let remaining = plan.blocks.filter { !completed.contains($0.id) }
        let replacementToAcknowledge = pendingReplacementBlock(in: plan)
        return Button {
            if let replacementToAcknowledge {
                selectedBlock = replacementToAcknowledge
            } else if planIsComplete {
                store.selectedDestination = .train
            } else {
                _ = todaySessionSequence.start(
                    plan: plan,
                    blockIDs: remaining.map(\.id),
                    store: store
                )
            }
        } label: {
            Label(
                replacementToAcknowledge != nil
                    ? "Review saved replacement"
                    : planIsComplete
                    ? "Choose free practice"
                    : completed.isEmpty ? "Start daily circuit" : "Continue daily circuit",
                systemImage: replacementToAcknowledge != nil
                    ? "checkmark.message.fill"
                    : planIsComplete ? "square.grid.2x2.fill" : "play.fill"
            )
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(NFTheme.controlTint(for: "indigo"))
        .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
    }

    @ViewBuilder
    private func heroControls(plan: DailyPlan, planIsComplete: Bool, remainingBlockCount: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                if !planIsComplete {
                    readinessPicker(plan: plan)
                    if pendingReplacementBlock(in: store.todayPlan) != nil {
                        Button("Review replacement") {
                            selectedBlock = pendingReplacementBlock(in: store.todayPlan)
                        }
                        .buttonStyle(.bordered)
                    } else if remainingBlockCount > 1 {
                        Button("Adjust circuit") { showSessionIntro = true }
                            .buttonStyle(.bordered)
                    }
                }
                Button("Plan history") { showsAdaptivePlanHistory = true }
                    .buttonStyle(.bordered)
            }
            VStack(alignment: .leading, spacing: 10) {
                if !planIsComplete {
                    readinessPicker(plan: plan)
                    if pendingReplacementBlock(in: store.todayPlan) != nil {
                        Button("Review replacement") {
                            selectedBlock = pendingReplacementBlock(in: store.todayPlan)
                        }
                        .buttonStyle(.bordered)
                    } else if remainingBlockCount > 1 {
                        Button("Adjust circuit") { showSessionIntro = true }
                            .buttonStyle(.bordered)
                    }
                }
                Button("Plan history") { showsAdaptivePlanHistory = true }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func prescriptionRing(minutes: Int, completion: Double, size: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(NFTheme.indigo.opacity(0.13), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: completion)
                .stroke(
                    AngularGradient(colors: [NFTheme.indigo, NFTheme.cyan], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(minutes)")
                    .font((size < 100 ? Font.title2 : Font.title).bold().monospacedDigit())
                Text(completion >= 1 ? "DONE" : "MIN LEFT")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Daily circuit, \(NFAppLocalization.formattedMinutes(minutes)) remaining, \(Int(completion * 100)) percent complete"
        )
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NFSectionHeader(
                "Circuit chapters",
                subtitle: "Recall, build, cross over, and reflect. Start the whole circuit above or choose one chapter."
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                ForEach(Array(executablePlan.blocks.enumerated()), id: \.element.id) { index, block in
                    let completed = store.completedPlanBlockIDs(planID: store.todayPlan.id).contains(block.id)
                    Button {
                        if completed {
                            selectedCompletedBlock = block
                        } else if let replacement = pendingReplacementBlock(in: store.todayPlan) {
                            selectedBlock = replacement
                        } else {
                            selectedBlock = block
                        }
                    } label: {
                        PlanBlockCard(number: index + 1, block: block, isComplete: completed)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today-plan-block-\(index + 1)")
                    .accessibilityHint(completed
                                       ? "Opens the immutable saved-answer review for this completed chapter."
                                       : "Opens details and a start action for this chapter.")
                }
            }
        }
    }

    private var foundationalLabs: [TrainingLab] {
        TrainingLab.allCases.filter { lab in
            lab != .transfer && !(lab == .spatial && store.profile?.excludeVisualSpatial == true)
        }
    }

    private var abilityCores: some View {
        let progress = store.forgeProgress
        let covered = progress.currentWeekCoveredLabs
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                NFSectionHeader(
                    "Skills",
                    subtitle: "Keep the full STEM toolkit in rotation. Your goals add emphasis without removing broad practice."
                )
                Spacer(minLength: 12)
                Text("\(covered.count) / \(progress.accessibleLabs.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(covered == progress.accessibleLabs ? NFTheme.mintForeground : .secondary)
            }

            NFForgeProgressBar(
                progress: progress.currentWeekCoverage,
                accent: NFTheme.cyan,
                secondary: NFTheme.mint,
                height: 8
            )
            .accessibilityLabel("\(covered.count) of \(progress.accessibleLabs.count) foundational abilities practiced this week")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 12)], spacing: 12) {
                ForEach(foundationalLabs) { lab in
                    Button {
                        store.beginSession(
                            lab: lab,
                            source: .focused,
                            requestedMinutes: 5,
                            requestedItemCount: 5,
                            isTimed: false
                        )
                    } label: {
                        AbilityCoreTile(lab: lab, isCovered: covered.contains(lab))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var forgeMilestones: some View {
        let unlocked = Set(store.forgeProgress.milestones.map(\.code))
        return VStack(alignment: .leading, spacing: 14) {
            NFSectionHeader(
                "Milestones",
                subtitle: "Earned by showing up, completing circuits, and exploring broadly. They never change skill scores."
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForgeMilestoneSeal(
                    title: "First Spark",
                    symbol: "sparkles",
                    color: NFTheme.gold,
                    isUnlocked: unlocked.contains(.firstAttempt)
                )
                ForgeMilestoneSeal(
                    title: "Circuit Complete",
                    symbol: "checkmark.seal.fill",
                    color: NFTheme.mint,
                    isUnlocked: unlocked.contains(.firstCompletedSession)
                )
                ForgeMilestoneSeal(
                    title: "First Crossover",
                    symbol: "arrow.triangle.swap",
                    color: NFTheme.rose,
                    isUnlocked: unlocked.contains(.firstTransferAttempt)
                )
                ForgeMilestoneSeal(
                    title: "All-Round Explorer",
                    symbol: "hexagon.fill",
                    color: NFTheme.violet,
                    isUnlocked: unlocked.contains(.accessibleLabCircuit)
                )
            }
        }
    }

    @ViewBuilder
    private var sideQuests: some View {
        if !baselineIsComplete || store.reassessmentStatus() != nil {
            VStack(alignment: .leading, spacing: 14) {
                NFSectionHeader(
                    "Side quests",
                    subtitle: "Optional skill checks sharpen recommendations without blocking your daily circuit."
                )
                if !baselineIsComplete { baselineCard }
                reassessmentCard
            }
        }
    }

    private var quickPractice: some View {
        VStack(alignment: .leading, spacing: 14) {
            NFSectionHeader("Quick practice", subtitle: "Choose a short activity outside today’s plan.")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { quickPracticeActions }
                VStack(spacing: 12) { quickPracticeActions }
            }
        }
    }

    @ViewBuilder
    private var quickPracticeActions: some View {
        QuickPracticeButton(title: "Mental math", detail: NFAppLocalization.formattedMinutes(5), symbol: "function", color: NFTheme.indigo, accessibilityIdentifier: "quick-practice-mental-math") {
            store.beginSession(
                lab: .mentalMath,
                source: .focused,
                requestedMinutes: 5,
                requestedItemCount: 5,
                isTimed: false
            )
        }
        QuickPracticeButton(title: "Source reviews", detail: quickSourceCountLabel, symbol: "clock.arrow.circlepath", color: NFTheme.cyan, accessibilityIdentifier: "quick-practice-source-reviews") {
            if store.documents.isEmpty {
                store.requestSourceReviewDocumentImport()
            } else {
                store.requestSourceReviews()
            }
        }
    }

    private var weeklyMission: some View {
        Group {
            if let mission = store.weeklyTransferMission {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        NFIconTile(symbol: "scope", color: NFTheme.rose, size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Weekly transfer mission")
                                .font(.headline)
                            Text(weeklyMissionTitle(mission))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        NFStatusPill(
                            text: NFAppLocalization.formattedMinutes(mission.estimatedMinutes, style: .compact),
                            symbol: "timer",
                            color: NFTheme.rose
                        )
                    }
                    Text(
                        NFAppLocalization.localized("Combines \(mission.labs.map(\.shortTitle).joined(separator: " + ")) while changing \(NFTransferDimensionLocalization.list(mission.requiredTransferDimensions)).",
                            locale: NFAppLocalization.preferredLocale,
                            comment: "Weekly transfer-mission summary; placeholders are the localized lab list and transfer-dimension list."
                        )
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack { weeklyMissionActions(mission) }
                        VStack(alignment: .leading, spacing: 10) { weeklyMissionActions(mission) }
                    }
                }
                .nfCard()
            } else if weeklyMissionCompletedThisWeek {
                HStack(spacing: 14) {
                    NFIconTile(symbol: "checkmark.seal.fill", color: NFTheme.mint, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weekly mission complete")
                            .font(.headline)
                        Text("Your result is saved in Progress.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .nfCard()
            }
        }
    }

    @ViewBuilder
    private func weeklyMissionActions(_ mission: NFWeeklyTransferMission) -> some View {
        Button("Start mission") {
            store.beginSession(
                lab: .transfer,
                source: .weeklyMission,
                requestedMinutes: mission.estimatedMinutes,
                evidenceClass: mission.evidenceClass,
                field: store.profileSnapshot.fields.sorted(by: { $0.rawValue < $1.rawValue }).first,
                topic: weeklyMissionTopic(mission),
                targetDifficulty: 0.7,
                requestedItemCount: max(4, mission.estimatedMinutes / 2),
                seedOverride: mission.seed,
                planID: mission.id,
                planBlockID: mission.id,
                isTimed: false,
                mechanicID: "weekly.\(mission.kind.rawValue)",
                transferBrief: mission.exerciseTransferBrief
            )
        }
        .buttonStyle(.borderedProminent)
        .tint(NFTheme.roseControlTint)
        .foregroundStyle(NFTheme.roseControlForeground)
        Button("Defer one day") {
            store.deferWeeklyTransferMission(mission)
        }
        .buttonStyle(.bordered)
        Button("Inspect skills") {
            store.selectedDestination = .progress
        }
        .buttonStyle(.bordered)
    }

    private var quickSourceCountLabel: String {
        let count = store.documents.count
        switch count {
        case 0:
            return NFAppLocalization.localized("No sources yet", locale: NFAppLocalization.preferredLocale, comment: "Quick-practice source-review status when no sources are imported.")
        case 1:
            return NFAppLocalization.localized("\(count) source", locale: NFAppLocalization.preferredLocale, comment: "Quick-practice source-review count when exactly one source is imported; the placeholder is the source count.")
        default:
            return NFAppLocalization.localized("\(count) sources", locale: NFAppLocalization.preferredLocale, comment: "Quick-practice source-review count when multiple sources are imported; the placeholder is the source count.")
        }
    }

    private var weeklyMissionCompletedThisWeek: Bool {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return false }
        return store.sessionCheckpoints.contains {
            $0.isComplete
                && $0.sourceRaw == SessionSource.weeklyMission.rawValue
                && interval.contains($0.updatedAt)
        }
    }

    private func weeklyMissionTitle(_ mission: NFWeeklyTransferMission) -> String {
        mission.kind.title
    }

    private func weeklyMissionTopic(_ mission: NFWeeklyTransferMission) -> String {
        let locale = NFAppLocalization.preferredLocale
        let abilityTitles = NFTodaySkillPresentation.localizedTitles(
            skillIDs: mission.skillIDs,
            fallbackLabs: mission.labs,
            locale: locale
        )
        return NFAppLocalization.localized(
            "\(weeklyMissionTitle(mission)); abilities: \(NFTodaySkillPresentation.localizedList(abilityTitles, locale: locale)); transfer dimensions: \(NFTransferDimensionLocalization.list(mission.requiredTransferDimensions))",
            locale: locale,
            comment: "Weekly transfer-mission learner summary; placeholders are the mission title, localized ability list, and localized transfer-dimension list. Persisted skill identifiers are never exposed."
        )
    }

    private var activeDayCount: Int {
        Set(store.standardizedAttempts.map { Calendar.current.startOfDay(for: $0.submittedAt) }).count
    }

    private var currentReadinessSnapshot: NFTodayReadinessPlanSnapshot {
        let plan = store.todayPlan
        return NFTodayReadinessPlanSnapshot(
            plan: plan,
            completedBlockIDs: store.completedPlanBlockIDs(planID: plan.id),
            readiness: store.readiness
        )
    }

    private func applyReadiness(_ newReadiness: Readiness) {
        let previousReadiness = store.readiness
        guard previousReadiness != newReadiness else { return }

        let previousPlan = store.todayPlan
        let previousSnapshot = NFTodayReadinessPlanSnapshot(
            plan: previousPlan,
            completedBlockIDs: store.completedPlanBlockIDs(planID: previousPlan.id),
            readiness: previousReadiness
        )
        let planWasAlreadyInProgress = store.attempts.contains { $0.planID == previousPlan.id }
            || store.sessionCheckpoints.contains { $0.planID == previousPlan.id }
            || store.activeSessionRequest?.planID == previousPlan.id
        let existingHistoryIDs = Set(store.adaptivePlanHistory.map(\.id))

        store.updateReadiness(newReadiness)
        guard store.readiness == newReadiness else { return }

        let updatedPlan = store.todayPlan
        let updatedSnapshot = NFTodayReadinessPlanSnapshot(
            plan: updatedPlan,
            completedBlockIDs: store.completedPlanBlockIDs(planID: updatedPlan.id),
            readiness: store.readiness
        )
        let persistedReason = store.adaptivePlanHistory.first {
            $0.kind == .readinessChanged && !existingHistoryIDs.contains($0.id)
        }?.reason ?? NFAppLocalization.localized(
            "Your energy setting changed the plan policy used for today’s remaining work.",
            locale: NFAppLocalization.preferredLocale,
            comment: "Fallback explanation when an adaptive readiness-history record is unavailable."
        )

        readinessImpact = NFTodayReadinessImpact(
            previousReadiness: previousReadiness,
            newReadiness: store.readiness,
            previous: previousSnapshot,
            new: updatedSnapshot,
            planWasAlreadyInProgress: planWasAlreadyInProgress,
            reason: persistedReason
        )

        if let acknowledgement = pendingReplacementAcknowledgement,
           !updatedPlan.blocks.contains(where: { $0.id == acknowledgement.replacementBlockID }) {
            pendingReplacementAcknowledgement = nil
        }
    }

    private func persistedReplacementReason(for blockID: String) -> NFPlanReplacementReason? {
        let plan = store.todayPlan
        guard let canonical = store.dailyPlans.first(where: { $0.id == plan.id })?.snapshot,
              let replacement = canonical.replacement,
              replacement.replacementBlockID == blockID else {
            return nil
        }
        return replacement.reason
    }

    private func makeReplacementAcknowledgement(
        originalBlock: PlanBlock,
        replacementBlock: PlanBlock
    ) -> NFTodayReplacementAcknowledgement {
        let plan = store.todayPlan
        let canonicalReplacement = store.dailyPlans
            .first(where: { $0.id == plan.id })?
            .snapshot?
            .replacement
        let persistedReason = canonicalReplacement?.reason ?? .needVariety
        let historyRecord = store.adaptivePlanHistory.first { record in
            guard record.kind == .planReplaced,
                  let payload = record.undoPayload,
                  case let .dailyPlan(historyPlanID, _, _) = payload else {
                return false
            }
            return historyPlanID == plan.id
        }
        let explanation = historyRecord?.reason ?? NFAppLocalization.localized(
            "You chose \(persistedReason.title). The saved replacement keeps today’s scheduled duration unchanged.",
            locale: NFAppLocalization.preferredLocale,
            comment: "Fallback acknowledgement after a persisted daily-plan block replacement; the placeholder is the learner-selected reason."
        )
        return NFTodayReplacementAcknowledgement(
            id: historyRecord?.id ?? UUID(),
            planID: plan.id,
            replacementBlockID: canonicalReplacement?.replacementBlockID ?? replacementBlock.id,
            previousTitle: historyRecord?.previousState ?? originalBlock.title,
            replacementTitle: historyRecord?.newState ?? replacementBlock.title,
            reason: persistedReason,
            explanation: explanation
        )
    }

    private func pendingReplacementBlock(in plan: DailyPlan) -> PlanBlock? {
        guard let pendingReplacementAcknowledgement else { return nil }
        return plan.blocks.first { $0.id == pendingReplacementAcknowledgement.replacementBlockID }
    }

    private func presentRequestedPlanIfNeeded() {
        guard store.shouldOpenTodayPlan else { return }
        store.consumeTodayPlanRequest()
        let plan = executablePlan
        let completed = store.completedPlanBlockIDs(planID: plan.id)
        if let replacement = pendingReplacementBlock(in: plan) {
            selectedBlock = replacement
        } else if let remaining = plan.blocks.first(where: { !completed.contains($0.id) }) {
            selectedBlock = remaining
        } else {
            showsCompletedPlanReview = true
        }
    }

    private func presentRequestedCompletedReviewIfNeeded() {
        guard store.shouldOpenCompletedTodayReview else { return }
        store.shouldOpenCompletedTodayReview = false
        selectedBlock = nil
        selectedCompletedBlock = nil
        showsCompletedPlanReview = true
    }
}

struct NFTodayReadinessPreview: Identifiable {
    let id = UUID()
    let planID: String
    let currentReadiness: Readiness
    let proposedReadiness: Readiness
    let completedBlocks: [PlanBlock]
    let remainingBlocks: [PlanBlock]
    let preservesRemainingPlan: Bool

    init(plan: DailyPlan, completedBlockIDs: Set<String>, currentReadiness: Readiness,
         proposedReadiness: Readiness, preservesRemainingPlan: Bool) {
        planID = plan.id
        self.currentReadiness = currentReadiness
        self.proposedReadiness = proposedReadiness
        completedBlocks = plan.blocks.filter { completedBlockIDs.contains($0.id) }
        remainingBlocks = plan.blocks.filter { !completedBlockIDs.contains($0.id) }
        self.preservesRemainingPlan = preservesRemainingPlan
    }

    var currentRemainingMinutes: Int { remainingBlocks.reduce(0) { $0 + $1.minutes } }

    var pacingEffect: String {
        switch proposedReadiness {
        case .low:
            NFAppLocalization.localized("New daily sessions will be untimed. You can choose a shorter remaining session; saved questions keep their original settings.", comment: "Low-energy preview describes real timing/shortening policy without inventing a replacement plan.")
        case .normal, .high:
            NFAppLocalization.localized("New daily sessions follow your usual pacing and timing preferences. Timed fluency still requires suitable practice evidence; saved questions keep their original settings.", comment: "Normal/high-energy preview does not promise a higher skill estimate or bypass fluency readiness.")
        }
    }

    var planEffect: String {
        preservesRemainingPlan
            ? NFAppLocalization.localized("Your saved chapter list stays fixed. This choice changes the pacing available for new daily sessions.", comment: "Readiness preview for started or earlier-version immutable plans.")
            : NFAppLocalization.localized("Applying may update the unstarted sections. Nothing changes until you apply.", comment: "Readiness preview for an unstarted current-policy plan; no prospective plan is generated.")
    }
}

private struct NFTodayReadinessPreviewView: View {
    let preview: NFTodayReadinessPreview
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("\(preview.currentReadiness.title) → \(preview.proposedReadiness.title)")
                        .font(.title2.bold()).accessibilityHeading(.h2)
                    Text(preview.pacingEffect).accessibilityIdentifier("readiness-preview-effect")
                    Text(preview.planEffect).font(.subheadline)
                    Label("Saved answers, completed sections and earned rewards stay unchanged.", systemImage: "lock.fill")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if !preview.completedBlocks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Completed sections — fixed").font(.headline)
                            ForEach(preview.completedBlocks) { block in
                                Label(block.title, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(NFTheme.mintForeground)
                            }
                        }.nfCard(cornerRadius: 14)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Current remaining plan").font(.headline)
                        Text(NFAppLocalization.formattedMinutes(preview.currentRemainingMinutes))
                            .foregroundStyle(.secondary)
                        ForEach(preview.remainingBlocks) { block in
                            LabeledContent(block.title, value: NFAppLocalization.formattedMinutes(block.minutes))
                        }
                    }.nfCard(cornerRadius: 14)
                }.padding(20)
            }
            .navigationTitle("Energy preview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel).accessibilityIdentifier("readiness-preview-cancel")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Apply energy change", action: onApply)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.borderedProminent)
                    .tint(NFTheme.controlTint(for: "indigo")).foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                    .padding(16).background(.regularMaterial)
                    .accessibilityIdentifier("readiness-preview-apply")
            }
        }
        .nfDesktopPresentationFrame(minWidth: 400, idealWidth: 600, minHeight: 520, idealHeight: 740)
    }
}

struct NFTodayReadinessPlanSnapshot: Equatable {
    let remainingMinutes: Int
    let timedMinutes: Int
    let nextChapterTitle: String?
    let nextChapterMinutes: Int?

    init(
        remainingMinutes: Int,
        timedMinutes: Int,
        nextChapterTitle: String?,
        nextChapterMinutes: Int?
    ) {
        self.remainingMinutes = max(0, remainingMinutes)
        self.timedMinutes = max(0, timedMinutes)
        self.nextChapterTitle = nextChapterTitle
        self.nextChapterMinutes = nextChapterMinutes.map { max(0, $0) }
    }

    init(plan: DailyPlan, completedBlockIDs: Set<String>, readiness: Readiness) {
        let remaining = plan.blocks.filter { !completedBlockIDs.contains($0.id) }
        self.init(
            remainingMinutes: remaining.reduce(0) { $0 + $1.minutes },
            timedMinutes: readiness == .low
                ? 0
                : remaining.filter(\.timed).reduce(0) { $0 + $1.minutes },
            nextChapterTitle: remaining.first?.title,
            nextChapterMinutes: remaining.first?.minutes
        )
    }

    var summary: String {
        let timing = timedMinutes == 0
            ? NFAppLocalization.localized(
                "untimed",
                locale: NFAppLocalization.preferredLocale,
                comment: "Current readiness impact when no remaining daily-plan minutes are timed."
            )
            : NFAppLocalization.localized(
                "\(NFAppLocalization.formattedMinutes(timedMinutes)) timed",
                locale: NFAppLocalization.preferredLocale,
                comment: "Current readiness impact; the placeholder is the localized remaining timed duration."
            )
        if let nextChapterTitle, let nextChapterMinutes {
            return NFAppLocalization.localized(
                "Current effect: \(NFAppLocalization.formattedMinutes(remainingMinutes)) remaining, \(timing). Next: \(nextChapterTitle), \(NFAppLocalization.formattedMinutes(nextChapterMinutes)).",
                locale: NFAppLocalization.preferredLocale,
                comment: "Exact current readiness consequence; placeholders are remaining duration, timing summary, next chapter title, and next chapter duration."
            )
        }
        return NFAppLocalization.localized(
            "Current effect: \(NFAppLocalization.formattedMinutes(remainingMinutes)) remaining, \(timing). No chapter remains.",
            locale: NFAppLocalization.preferredLocale,
            comment: "Exact current readiness consequence after every daily-plan chapter is complete."
        )
    }
}

struct NFTodayReadinessImpact: Equatable {
    let previousReadiness: Readiness
    let newReadiness: Readiness
    let previous: NFTodayReadinessPlanSnapshot
    let new: NFTodayReadinessPlanSnapshot
    let planWasAlreadyInProgress: Bool
    let reason: String

    var changeSummary: String {
        let lengthChange = previous.remainingMinutes == new.remainingMinutes
            ? NFAppLocalization.localized(
                "Remaining length stays \(NFAppLocalization.formattedMinutes(new.remainingMinutes)).",
                locale: NFAppLocalization.preferredLocale,
                comment: "Readiness consequence when the remaining daily-plan length is unchanged."
            )
            : NFAppLocalization.localized(
                "Remaining length: \(NFAppLocalization.formattedMinutes(previous.remainingMinutes)) to \(NFAppLocalization.formattedMinutes(new.remainingMinutes)).",
                locale: NFAppLocalization.preferredLocale,
                comment: "Readiness consequence; placeholders are previous and new remaining minute counts."
            )
        let timingChange = previous.timedMinutes == new.timedMinutes
            ? NFAppLocalization.localized(
                "Timed work stays \(NFAppLocalization.formattedMinutes(new.timedMinutes)).",
                locale: NFAppLocalization.preferredLocale,
                comment: "Readiness consequence when the remaining timed-work length is unchanged."
            )
            : NFAppLocalization.localized(
                "Timed work: \(NFAppLocalization.formattedMinutes(previous.timedMinutes)) to \(NFAppLocalization.formattedMinutes(new.timedMinutes)).",
                locale: NFAppLocalization.preferredLocale,
                comment: "Readiness consequence; placeholders are previous and new timed minute counts."
            )
        let chapterChange: String
        switch (previous.nextChapterTitle, previous.nextChapterMinutes, new.nextChapterTitle, new.nextChapterMinutes) {
        case let (.some(oldTitle), .some(oldMinutes), .some(newTitle), .some(newMinutes))
            where oldTitle != newTitle || oldMinutes != newMinutes:
            chapterChange = NFAppLocalization.localized(
                "Next chapter: \(oldTitle), \(NFAppLocalization.formattedMinutes(oldMinutes)) to \(newTitle), \(NFAppLocalization.formattedMinutes(newMinutes)).",
                locale: NFAppLocalization.preferredLocale,
                comment: "Readiness consequence; placeholders name the previous and new next chapters and their durations."
            )
        case let (_, _, .some(title), .some(minutes)):
            chapterChange = NFAppLocalization.localized(
                "Next chapter stays \(title), \(NFAppLocalization.formattedMinutes(minutes)).",
                locale: NFAppLocalization.preferredLocale,
                comment: "Readiness consequence when the next chapter and its duration are unchanged."
            )
        default:
            chapterChange = NFAppLocalization.localized(
                "No chapter remains.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Readiness consequence when the daily plan has no remaining chapter."
            )
        }
        let progressNote = planWasAlreadyInProgress
            ? NFAppLocalization.localized(
                "The chapter list is fixed because today’s work already started.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Readiness consequence after a daily plan has begun."
            )
            : NFAppLocalization.localized(
                "The unstarted circuit was safely recalculated.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Readiness consequence before a daily plan has begun."
            )
        return "\(previousReadiness.title) → \(newReadiness.title). \(lengthChange) \(timingChange) \(chapterChange) \(progressNote)"
    }
}

struct NFTodayReplacementAcknowledgement: Equatable, Identifiable {
    let id: UUID
    let planID: String
    let replacementBlockID: String
    let previousTitle: String
    let replacementTitle: String
    let reason: NFPlanReplacementReason
    let explanation: String
}

enum NFTodaySkillPresentation {
    static func localizedTitles(
        skillIDs: [String],
        fallbackLabs: [TrainingLab],
        locale: Locale = NFAppLocalization.preferredLocale
    ) -> [String] {
        if skillIDs.isEmpty {
            return fallbackLabs.map { $0.localizedShortTitle(locale: locale) }
        }
        return skillIDs.enumerated().map { index, skillID in
            localizedTitle(
                for: skillID,
                fallbackLab: fallbackLabs.indices.contains(index) ? fallbackLabs[index] : nil,
                locale: locale
            )
        }
    }

    static func localizedTitle(
        for skillID: String,
        fallbackLab: TrainingLab? = nil,
        locale: Locale = NFAppLocalization.preferredLocale
    ) -> String {
        if let lab = TrainingLab.allCases.first(where: { $0.skillID == skillID }) {
            return lab.localizedShortTitle(locale: locale)
        }
        if let dimension = NFAssessmentDimension.from(skillID: skillID) {
            return localizedAssessmentTitle(dimension, locale: locale)
        }
        if let fallbackLab {
            return fallbackLab.localizedShortTitle(locale: locale)
        }
        return NFAppLocalization.localized(
            "Adaptive skill focus",
            locale: locale,
            comment: "Privacy-safe learner-facing fallback for an unknown persisted skill identifier."
        )
    }

    static func localizedList(_ values: [String], locale: Locale) -> String {
        guard !values.isEmpty else {
            return NFAppLocalization.localized(
                "Adaptive skill focus",
                locale: locale,
                comment: "Privacy-safe learner-facing fallback when a weekly mission has no named ability."
            )
        }
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: values) ?? values.joined(separator: ", ")
    }

    private static func localizedAssessmentTitle(
        _ dimension: NFAssessmentDimension,
        locale: Locale
    ) -> String {
        switch dimension {
        case .mentalArithmetic:
            NFAppLocalization.localized("Mental math", locale: locale, comment: "Learner-facing assessment skill name.")
        case .quantitativeEstimation:
            NFAppLocalization.localized("Estimation", locale: locale, comment: "Learner-facing assessment skill name.")
        case .probability:
            NFAppLocalization.localized("Probability", locale: locale, comment: "Learner-facing assessment skill name.")
        case .spatialTransformations:
            NFAppLocalization.localized("Spatial transformation", locale: locale, comment: "Learner-facing assessment skill name.")
        case .dataInterpretation:
            NFAppLocalization.localized("Data interpretation", locale: locale, comment: "Learner-facing assessment skill name.")
        case .experimentalReasoning:
            NFAppLocalization.localized("Experimental design", locale: locale, comment: "Learner-facing assessment skill name.")
        case .logic:
            NFAppLocalization.localized("Logic", locale: locale, comment: "Learner-facing assessment skill name.")
        case .confidenceCalibration:
            NFAppLocalization.localized("Confidence calibration", locale: locale, comment: "Learner-facing assessment skill name.")
        }
    }
}

enum NFAdaptiveHistoryPresentation {
    static func safeText(_ value: String) -> String {
        guard NFUserFacingContentLinter.lint(value) == nil else {
            return NFAppLocalization.localized(
                "Internal implementation detail hidden",
                locale: NFAppLocalization.preferredLocale,
                comment: "Adaptive-plan history replacement for a legacy value that contains a raw internal identifier."
            )
        }
        return value
    }
}

private struct NFAdaptivePlanHistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pendingUndo: NFAdaptivePlanChangeRecord?
    @State private var showsUndoConfirmation = false

    private var records: [NFAdaptivePlanChangeRecord] {
        store.adaptivePlanHistory
            .filter { $0.profileID == store.profileSnapshot.id }
            .sorted {
                if $0.occurredAt == $1.occurredAt {
                    return $0.id.uuidString > $1.id.uuidString
                }
                return $0.occurredAt > $1.occurredAt
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    NFSectionHeader(
                        "Plan history",
                        eyebrow: "ADAPTIVE CHANGES",
                        subtitle: "A local audit trail of plan, readiness, mission, and preference decisions. Safe changes can be undone until later work depends on them."
                    )

                    if records.isEmpty {
                        ContentUnavailableView(
                            "No adaptive changes yet",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("Plan changes and their reasons will appear here.")
                        )
                    } else {
                        ForEach(records) { record in
                            historyCard(record)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Plan history")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Undo this adaptive change?",
                isPresented: $showsUndoConfirmation,
                titleVisibility: .visible,
                presenting: pendingUndo
            ) { change in
                Button("Restore previous safe state") {
                    _ = store.undoAdaptivePlanChange(change.id)
                    pendingUndo = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingUndo = nil
                }
            } message: { change in
                Text("Undo is available only while the current plan still exactly matches “\(NFAdaptiveHistoryPresentation.safeText(change.newState))” and no later answer or checkpoint depends on it.")
            }
        }
        .nfDesktopPresentationFrame(minWidth: 440, idealWidth: 780, minHeight: 620, idealHeight: 860)
    }

    private func historyCard(_ record: NFAdaptivePlanChangeRecord) -> some View {
        let wasUndone = store.reversedAdaptivePlanChangeIDs.contains(record.id)
        let canUndo = store.canUndoAdaptivePlanChange(record)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                NFIconTile(
                    symbol: historySymbol(record.kind),
                    color: historyColor(record.kind),
                    size: 44
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: NFAdaptiveHistoryPresentation.safeText(record.title))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        record.occurredAt.formatted(
                            .dateTime
                                .year()
                                .month(.wide)
                                .day()
                                .hour()
                                .minute()
                                .locale(NFAppLocalization.preferredLocale)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if wasUndone {
                    NFStatusPill(text: "Undone", symbol: "arrow.uturn.backward.circle.fill", color: NFTheme.mint)
                }
            }

            LabeledContent {
                Text(verbatim: record.previousState.map(NFAdaptiveHistoryPresentation.safeText) ?? NFAppLocalization.localized(
                    "No prior persisted state",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Adaptive-plan history value when a record created a state rather than changing one."
                ))
            } label: {
                Text("Previous")
            }
            LabeledContent {
                Text(verbatim: NFAdaptiveHistoryPresentation.safeText(record.newState))
            } label: {
                Text("New")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Reason")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: NFAdaptiveHistoryPresentation.safeText(record.reason))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if record.canUndo && !wasUndone {
                Button("Undo change") {
                    pendingUndo = record
                    showsUndoConfirmation = true
                }
                .buttonStyle(.bordered)
                .disabled(!canUndo)
                .accessibilityHint(canUndo
                                   ? "Restores the previous persisted state."
                                   : "Unavailable because this change was used, superseded, or no longer matches the current state.")
                if !canUndo {
                    Text("Undo is no longer safe because later work used or superseded this state.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .nfCard(cornerRadius: 18, padding: 16)
    }

    private func historySymbol(_ kind: NFAdaptivePlanChangeKind) -> String {
        switch kind {
        case .planMaterialized: "list.bullet.clipboard.fill"
        case .planReplaced: "arrow.triangle.2.circlepath"
        case .readinessChanged: "battery.75percent"
        case .weeklyMissionPinned: "scope"
        case .preferencesApplied: "slider.horizontal.3"
        case .undo: "arrow.uturn.backward.circle.fill"
        }
    }

    private func historyColor(_ kind: NFAdaptivePlanChangeKind) -> Color {
        switch kind {
        case .planMaterialized: NFTheme.indigo
        case .planReplaced: NFTheme.cyan
        case .readinessChanged: NFTheme.amber
        case .weeklyMissionPinned: NFTheme.rose
        case .preferencesApplied: NFTheme.violet
        case .undo: NFTheme.mint
        }
    }
}

private struct AbilityCoreTile: View {
    let lab: TrainingLab
    let isCovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                NFIconTile(
                    symbol: lab.symbol,
                    color: NFTheme.color(for: lab.colorToken),
                    size: 42
                )
                Spacer(minLength: 8)
                Image(systemName: isCovered ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isCovered ? NFTheme.mintForeground : NFTheme.foregroundColor(for: lab.colorToken))
                    .accessibilityHidden(true)
            }
            Text(lab.shortTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Text(isCovered ? "Active this week" : "Quick 5")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isCovered ? NFTheme.mintForeground : .secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .nfGameCard(
            accent: NFTheme.color(for: lab.colorToken),
            secondary: isCovered ? NFTheme.mint : NFTheme.cyan,
            cornerRadius: 18,
            padding: 14
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(lab.title), \(isCovered ? "active this week" : "start a five-minute practice")")
    }
}

private struct ForgeMilestoneSeal: View {
    let title: String
    let symbol: String
    let color: Color
    let isUnlocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isUnlocked ? color.opacity(0.18) : Color.primary.opacity(0.05))
                Image(systemName: isUnlocked ? symbol : "lock.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isUnlocked ? color : Color.primary.opacity(0.28))
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isUnlocked ? .primary : .secondary)
                Text(isUnlocked ? "Unlocked" : "Keep training")
                    .font(.caption)
                    .foregroundStyle(isUnlocked ? color : Color.primary.opacity(0.32))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .nfCard(cornerRadius: 18, padding: 12)
        .accessibilityElement(children: .combine)
    }
}

enum NFTodayXPSource: String, Equatable {
    case completedChapter = "completed_chapter"
    case completedAnswer = "completed_answer"
    case activityFallback = "activity"

    static func resolved(from persistedIdentifier: String?) -> NFTodayXPSource {
        persistedIdentifier.flatMap(NFTodayXPSource.init(rawValue:)) ?? .activityFallback
    }

    func localizedLabel(amount: Int) -> String {
        let safeAmount = max(0, amount)
        return switch self {
        case .completedChapter:
            NFAppLocalization.localized(
                "+\(safeAmount) completion XP",
                locale: NFAppLocalization.preferredLocale,
                comment: "Forge XP awarded for completing a circuit chapter."
            )
        case .completedAnswer:
            NFAppLocalization.localized(
                "+\(safeAmount) answer XP",
                locale: NFAppLocalization.preferredLocale,
                comment: "Forge XP awarded for a completed answer; independent of correctness."
            )
        case .activityFallback:
            NFAppLocalization.localized(
                "+\(safeAmount) activity XP",
                locale: NFAppLocalization.preferredLocale,
                comment: "Safe fallback Forge XP label when a saved award-source identifier is unavailable."
            )
        }
    }
}

private struct PlanBlockCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let number: Int
    let block: PlanBlock
    let isComplete: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                NFIconTile(symbol: block.lab.symbol, color: NFTheme.color(for: block.lab.colorToken))
                VStack(alignment: .leading, spacing: 3) {
                    Text("CHAPTER \(number)")
                        .font(.caption2.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(NFTheme.foregroundColor(for: block.lab.colorToken))
                    Text(block.lab == .transfer ? "Try a new context" : block.lab.shortTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isComplete ? "checkmark.seal.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isComplete ? NFTheme.mintForeground : Color.primary.opacity(0.28))
                    .accessibilityLabel(isComplete ? "Completed" : "Not completed")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(block.title)
                    .font(.headline)
                Text(block.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
            Spacer(minLength: 0)
            HStack {
                Label(NFAppLocalization.formattedMinutes(block.minutes, style: .compact), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(NFTodayXPSource.completedChapter.localizedLabel(
                    amount: NFForgeProgressEngine.xpPerEligibleCompletedSession
                ))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(isComplete ? NFTheme.mintForeground : NFTheme.goldForeground)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
        .nfGameCard(
            accent: NFTheme.color(for: block.lab.colorToken),
            secondary: isComplete ? NFTheme.mint : NFTheme.cyan,
            cornerRadius: 20,
            padding: 16
        )
        .contentShape(Rectangle())
    }
}

private struct QuickPracticeButton: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                NFIconTile(symbol: symbol, color: color, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold))
                    Text(LocalizedStringKey(detail)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .nfCard(cornerRadius: 18, padding: 14)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct TodaySessionIntroView: View {
    @Environment(\.dismiss) private var dismiss
    let plan: DailyPlan
    let completedBlockIDs: Set<String>
    let onStart: ([String]) -> Void

    private var remainingBlocks: [PlanBlock] {
        plan.blocks.filter { !completedBlockIDs.contains($0.id) }
    }

    private var timedMinutes: Int {
        remainingBlocks.filter(\.timed).reduce(0) { $0 + $1.minutes }
    }

    private var totalMinutes: Int {
        remainingBlocks.reduce(0) { $0 + $1.minutes }
    }

    private var optionCounts: [Int] {
        Array(Set([remainingBlocks.count, min(2, remainingBlocks.count), min(1, remainingBlocks.count)]))
            .filter { $0 > 0 }
            .sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    NFSectionHeader(
                        "Adjust circuit",
                        eyebrow: "DAILY CIRCUIT",
                        subtitle: "Choose how much to complete now. You can stop after any block and return to the rest later."
                    )

                    HStack(spacing: 10) {
                        NFStatusPill(
                            text: NFAppLocalization.localized(
                                "\(NFAppLocalization.formattedMinutes(totalMinutes, style: .compact)) remaining",
                                locale: NFAppLocalization.preferredLocale,
                                comment: "Remaining session duration; the placeholder is a localized compact duration."
                            ),
                            symbol: "timer",
                            color: NFTheme.indigo
                        )
                        NFStatusPill(
                            text: timedMinutes == 0
                                ? NFAppLocalization.localized("Untimed", locale: NFAppLocalization.preferredLocale, comment: "Session timing badge when no timed blocks remain.")
                                : NFAppLocalization.localized("\(NFAppLocalization.formattedMinutes(timedMinutes, style: .compact)) timed",
                                    locale: NFAppLocalization.preferredLocale,
                                    comment: "Timed session duration; the placeholder is a localized compact duration."
                                ),
                            symbol: timedMinutes == 0 ? "infinity" : "stopwatch",
                            color: NFTheme.cyan
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Circuit chapters").font(.title2.bold())
                        ForEach(Array(remainingBlocks.enumerated()), id: \.element.id) { index, block in
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.caption.bold().monospacedDigit())
                                    .frame(width: 28, height: 28)
                                    .background(NFTheme.indigo.opacity(0.12), in: Circle())
                                NFIconTile(
                                    symbol: block.lab.symbol,
                                    color: NFTheme.color(for: block.lab.colorToken),
                                    size: 38
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(block.title).font(.headline)
                                    Text("\(NFAppLocalization.formattedMinutes(block.minutes, style: .compact)) · \(block.timed ? "timed when eligible" : "untimed")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }

                    if remainingBlocks.isEmpty {
                        ContentUnavailableView(
                            "Today’s plan is complete",
                            systemImage: "checkmark.seal.fill",
                            description: Text("Your completed work is saved. Focused practice is still available from Practice.")
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Start with").font(.headline)
                            ForEach(optionCounts, id: \.self) { count in
                                let selected = Array(remainingBlocks.prefix(count))
                                Button {
                                    onStart(selected.map(\.id))
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(optionTitle(count: count))
                                                .font(.headline)
                                            Text("\(NFAppLocalization.formattedMinutes(selected.reduce(0) { $0 + $1.minutes })) · stop safely after any block")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "play.fill")
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.bordered)
                                .tint(NFTheme.indigoForeground)
                                .controlSize(.large)
                            }
                        }
                        .nfCard()
                    }
                }
                .padding(24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Adjust circuit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .nfDesktopPresentationFrame(minWidth: 420, idealWidth: 760, minHeight: 620, idealHeight: 820)
    }

    private func optionTitle(count: Int) -> String {
        if count == remainingBlocks.count {
            return NFAppLocalization.localized("All remaining blocks", locale: NFAppLocalization.preferredLocale, comment: "Session-intro option to complete every remaining daily-plan block.")
        }
        if count == 1 {
            return NFAppLocalization.localized("Next block only", locale: NFAppLocalization.preferredLocale, comment: "Shortened-session option to complete only the next daily-plan block.")
        }
        return NFAppLocalization.localized("Next \(count) blocks", locale: NFAppLocalization.preferredLocale, comment: "Shortened-session option; the placeholder is the number of daily-plan blocks.")
    }
}

private struct PlanBlockDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let block: PlanBlock
    let canReplace: Bool
    let persistedReplacementReason: NFPlanReplacementReason?
    let replacementAcknowledgement: NFTodayReplacementAcknowledgement?
    let onStart: () -> Void
    let onPreviewReplacement: (NFPlanReplacementReason) throws -> NFPlanReplacementPreview
    let onReplace: (NFPlanReplacementPreview) -> Void
    let onAcknowledgeReplacement: () -> Void
    @State private var replacementReason = NFPlanReplacementReason.wantVariety
    @State private var replacementPreview: NFPlanReplacementPreview?
    @State private var replacementPreviewError: String?
    @State private var didAcknowledgeReplacement = false

    private var requiresReplacementAcknowledgement: Bool {
        replacementAcknowledgement != nil && !didAcknowledgeReplacement
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 16) {
                        NFIconTile(symbol: block.lab.symbol, color: NFTheme.color(for: block.lab.colorToken), size: 62)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(block.title).font(.title2.bold()).accessibilityIdentifier("plan-block-title")
                            Text(block.detail).foregroundStyle(.secondary)
                        }
                    }

                    if let replacementAcknowledgement, !didAcknowledgeReplacement {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Replacement saved", systemImage: "checkmark.seal.fill")
                                .font(.headline)
                                .foregroundStyle(NFTheme.mintForeground)
                            Text("Review and acknowledge this committed change before starting today’s circuit.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            LabeledContent("Before", value: replacementAcknowledgement.previousTitle)
                            LabeledContent("Now", value: replacementAcknowledgement.replacementTitle)
                            LabeledContent("Your reason", value: replacementAcknowledgement.reason.title)
                            Text(replacementAcknowledgement.explanation)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button {
                                didAcknowledgeReplacement = true
                                onAcknowledgeReplacement()
                            } label: {
                                Label("Acknowledge replacement", systemImage: "checkmark")
                                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(NFTheme.controlTint(for: "green"))
                            .foregroundStyle(NFTheme.controlForeground(for: "green"))
                        }
                        .nfCard()
                        .accessibilityElement(children: .contain)
                    }

                    LabeledContent("Target duration", value: NFAppLocalization.formattedMinutes(block.minutes))
                    LabeledContent("Practice type", value: evidenceTitle)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Why this is next").font(.headline)
                        if let persistedReplacementReason {
                            Label(
                                "Your saved replacement reason: \(persistedReplacementReason.title)",
                                systemImage: "person.crop.circle.badge.checkmark"
                            )
                            .foregroundStyle(.secondary)
                        }
                        ForEach(displayedReasons, id: \.rawValue) { reason in
                            Label(reason.title, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .nfCard()

                    if persistedReplacementReason == nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("One-block adjustment").font(.headline)
                            Text("Replacing a block keeps today’s total time. Choose the closest reason.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Menu {
                                ForEach(NFPlanReplacementReason.currentChoices) { reason in
                                    Button { replacementReason = reason } label: {
                                        if reason == replacementReason { Label(reason.title, systemImage: "checkmark") }
                                        else { Text(reason.title) }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("Reason")
                                    Spacer()
                                    Text(replacementReason.title)
                                    Image(systemName: "chevron.up.chevron.down")
                                }.frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("plan-replacement-reason")
                            Button {
                                do {
                                    replacementPreview = try onPreviewReplacement(replacementReason)
                                    replacementPreviewError = nil
                                } catch {
                                    replacementPreview = nil
                                    replacementPreviewError = error.localizedDescription
                                }
                            } label: {
                                Text("Preview replacement").frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.bordered).disabled(!canReplace)
                            .accessibilityIdentifier("plan-replacement-preview")
                            if let replacementPreviewError {
                                Text(verbatim: replacementPreviewError).foregroundStyle(.secondary)
                            }
                            if let preview = replacementPreview {
                                replacementPreviewCard(preview)
                            }
                            if !canReplace {
                                Text("Replacement is unavailable after this block starts or after today’s one replacement is used.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .nfCard()
                    }

                    Button {
                        onStart()
                    } label: {
                        Label("Start this block", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NFTheme.controlTint(for: "indigo"))
                    .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                    .controlSize(.large)
                    .disabled(requiresReplacementAcknowledgement)
                    .accessibilityHint(requiresReplacementAcknowledgement
                                       ? "Acknowledge the saved replacement above before starting."
                                       : "Starts this persisted daily-plan chapter.")
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Block details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: replacementReason) { _, _ in
                replacementPreview = nil
                replacementPreviewError = nil
            }
        }
    }

    private func replacementPreviewCard(_ preview: NFPlanReplacementPreview) -> some View {
        let original = preview.originalPlan.domainPlan.blocks.first { $0.id == preview.originalBlock.id }
        let proposed = preview.proposedPlan.domainPlan.blocks.first { $0.id == preview.replacementBlock.id }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Replacement preview").font(.headline)
                .accessibilityIdentifier("plan-replacement-preview-heading")
            LabeledContent("Before", value: original?.title ?? preview.originalBlock.title)
            LabeledContent {
                Text(proposed?.title ?? preview.replacementBlock.title)
                    .accessibilityIdentifier("plan-replacement-proposed-title")
            } label: { Text("Proposed") }
            LabeledContent("Target duration", value: NFAppLocalization.formattedMinutes(preview.replacementBlock.minutes))
            LabeledContent("Your reason", value: replacementReason.title)
            LabeledContent("Practice type", value: evidenceTitle(for: preview.replacementBlock.evidenceClass))
            Text("Completed sections stay fixed. This replacement keeps the scheduled time and practice type. Earlier results stay unchanged.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Your reason changes today’s activity choice. It does not change your measured skill or assign a reviewed challenge band.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button {
                    replacementPreview = nil
                    replacementPreviewError = nil
                } label: {
                    Text("Cancel").frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.bordered).accessibilityIdentifier("plan-replacement-cancel")
                Button {
                    onReplace(preview)
                } label: {
                    Text("Apply replacement").frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent).disabled(!canReplace)
                .accessibilityIdentifier("plan-replacement-apply")
            }
        }.nfCard()
    }

    private var evidenceTitle: String { evidenceTitle(for: block.evidenceClass) }

    private func evidenceTitle(for evidence: EvidenceClass) -> String {
        switch evidence {
        case .practice: NFAppLocalization.localized("Training performance", locale: NFAppLocalization.preferredLocale, comment: "Evidence-channel title for ordinary practice.")
        case .nearTransfer: NFAppLocalization.localized("Near transfer", locale: NFAppLocalization.preferredLocale, comment: "Evidence-channel title for related but unfamiliar forms.")
        case .appliedTransfer: NFAppLocalization.localized("Applied transfer", locale: NFAppLocalization.preferredLocale, comment: "Evidence-channel title for applying a skill in another context.")
        case .retention: NFAppLocalization.localized("Delayed retention", locale: NFAppLocalization.preferredLocale, comment: "Evidence-channel title for recall after a delay.")
        case .assessmentHoldout: NFAppLocalization.localized("Assessment holdout", locale: NFAppLocalization.preferredLocale, comment: "Evidence-channel title for protected, previously unexposed assessment forms.")
        case .documentPractice: NFAppLocalization.localized("Personal document practice", locale: NFAppLocalization.preferredLocale, comment: "Evidence-channel title for practice from personal source material; excluded from standardized estimates.")
        }
    }

    private var displayedReasons: [PrescriptionReason] {
        guard persistedReplacementReason != nil else { return block.reasons }
        return block.reasons.filter { $0 != .userOverride }
    }
}
