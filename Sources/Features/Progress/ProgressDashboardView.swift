import Charts
import SwiftUI

#if os(iOS)
import PencilKit
import UIKit
#endif

/// The dashboard consumes derived authority; immutable raw confidence remains
/// available only in the original answer detail.
struct NFHistoryCalibrationSummary: Equatable, Sendable {
    let eligibleCount: Int
    let matchingCount: Int
    var fraction: Double? { eligibleCount == 0 ? nil : Double(matchingCount) / Double(eligibleCount) }

    init(attempts: [AttemptDTO]) {
        let eligible = attempts.filter { $0.confidence != nil && !$0.wasSkipped && $0.evidenceWeight > 0 }
        eligibleCount = eligible.count
        matchingCount = eligible.filter { attempt in
            guard let confidence = attempt.confidence else { return false }
            return (confidence.probability >= 0.5) == attempt.correct
        }.count
    }
}

struct ProgressDashboardView: View {
    @Environment(AppStore.self) private var store
    @Environment(NFNavigationState.self) private var navigation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("nf.progress.section") private var selectedSection = "Overview"
    @State private var filters = NFProgressFilters()
    @State private var showsFilters = false
    @State private var showsProgressDetails = false
    @State private var showsMethodology = false
    @State private var correctionSaveError = false
    @State private var dashboardProjection = NFProgressDashboardProjection()
    @State private var dashboardClock = NFProgressDashboardClock(capturedAt: Date(), calendar: .current)
    @State private var publishedDashboardRequest: NFProgressDashboardRequest?
    @State private var inspectedWeek: Date?
    @State private var weeklyChartDataPage = 0

    private var hasAnyStandardizedHistory: Bool {
        !store.standardizedAttempts.isEmpty
    }

    private var hasMatchingStandardizedHistory: Bool {
        !filteredAttempts.isEmpty
    }

    private var filteredAttempts: [AttemptRecord] {
        store.standardizedAttempts.filter { filters.includes($0, at: dashboardClock.capturedAt, calendar: dashboardClock.calendar) }
    }

    private var filteredSummaries: [SkillSummary] {
        dashboardSnapshot?.summaries ?? []
    }

    private var assessedCount: Int {
        filteredSummaries.filter {
            $0.evidenceCount > 0 && eligibleAbilityLabs.contains($0.lab)
        }.count
    }

    private var eligibleAbilityLabs: Set<TrainingLab> {
        var labs = Set(TrainingLab.allCases.filter { $0 != .transfer })
        if store.profile?.excludeVisualSpatial == true { labs.remove(.spatial) }
        return labs
    }

    private var totalEvidence: Int {
        dashboardSnapshot?.totalEvidence ?? 0
    }

    private var personalPracticeCount: Int {
        store.attempts.filter {
            filters.includes($0, at: dashboardClock.capturedAt, calendar: dashboardClock.calendar)
                && !$0.wasSkipped
                && $0.evidenceClassRaw == EvidenceClass.documentPractice.rawValue
        }.count
    }

    private var isDashboardActive: Bool { scenePhase == .active && selectedSection == "Overview" }

    private var dashboardRequest: NFProgressDashboardRequest {
        store.progressDashboardRequest(filters: filters, clock: dashboardClock,
            section: selectedSection, isActive: isDashboardActive)
    }

    /// The body withholds an old result as soon as its inputs change, even before
    /// SwiftUI starts the replacement task. A late worker cannot reattach it.
    private var dashboardSnapshot: NFProgressDashboardSnapshot? {
        guard isDashboardActive, publishedDashboardRequest == dashboardRequest else { return nil }
        return dashboardProjection.snapshot
    }

    private func refreshDashboardClock() {
        dashboardClock = dashboardClock.refreshing(isActive: isDashboardActive, at: Date(), calendar: .current)
    }

    private var errorPatterns: [NFErrorPattern] {
        Dictionary(grouping: dashboardSnapshot?.patterns ?? [], by: \.code).map { code, patterns in
            NFErrorPattern(code: code, count: patterns.reduce(0) { $0 + $1.evidenceAttemptIDs.count },
                last: patterns.map(\.lastObservedAt).max())
        }.sorted { $0.count == $1.count ? $0.code < $1.code : $0.count > $1.count }
    }

    private var mentalMathMetrics: [NFMentalMathMetricKind: NFMentalMathMetricResult] {
        dashboardSnapshot?.mentalMathMetrics ?? [:]
    }

    var body: some View {
        NavigationStack(path: Binding(get: { navigation.progress }, set: { navigation.progress = $0 })) {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        NFSectionHeader(
                            "Your progress",
                            eyebrow: "Personal learning",
                            subtitle: "See what is improving and what is worth practicing next."
                        )
                        Picker("Progress section", selection: $selectedSection) {
                            Text("Overview").tag("Overview")
                            Text("Review").tag("Review")
                            Text("History").tag("History")
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("progress-section-picker")
                        if selectedSection == "Overview" {
                        correctionNotice
                        if dashboardSnapshot == nil {
                            ProgressView("Updating progress…").frame(maxWidth: .infinity, minHeight: 100)
                                .accessibilityIdentifier("progress-projection-loading")
                        } else {
                        overviewHero
                        historicalPracticeCard
                        if let progress = dashboardSnapshot?.forge { forgeJourneyCard(progress) }
                        prioritySection
                        weeklyTrendCard
                        if let consistency = dashboardSnapshot?.consistency { consistencyCard(consistency) }
                        }
                        DisclosureGroup(isExpanded: $showsFilters) {
                            progressFiltersCard
                                .padding(.top, 12)
                        } label: {
                            Label("Filter progress", systemImage: "line.3.horizontal.decrease.circle")
                                .font(.headline)
                        }
                        .nfCard(cornerRadius: 18, padding: 16)
                        if dashboardSnapshot != nil {
                        DisclosureGroup(isExpanded: $showsProgressDetails) {
                            VStack(alignment: .leading, spacing: 24) {
                                evidenceChannelsCard
                                mentalMathMetricsCard
                                skillMap
                                calibrationCard
                                errorPatternsCard
                                ProgressAnnotationsCard()
                            }
                            .padding(.top, 14)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Label("Explore details", systemImage: "chart.bar.xaxis")
                                    .font(.headline)
                                Text("Skill map, confidence, answer history, and common errors")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .nfCard(cornerRadius: 18, padding: 16)
                        }
                        DisclosureGroup(isExpanded: $showsMethodology) {
                            methodologyNote
                                .padding(.top, 10)
                        } label: {
                            Label("How progress is calculated", systemImage: "info.circle")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 4)
                        } else if selectedSection == "Review" {
                            NFReviewQueueView()
                        } else {
                            NavigationLink(value: NFProgressRoute.history(nil)) {
                                Label("Open answer history", systemImage: "clock.arrow.circlepath")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            ForEach(Array(store.attempts.prefix(12))) { attempt in
                                NavigationLink(value: NFProgressRoute.attempt(attempt.id)) {
                                    NFAttemptHistoryRow(attempt: NFReadOnlyAttemptSnapshot(attempt: attempt))
                                }
                                .buttonStyle(.plain)
                            }
                            if store.attempts.isEmpty {
                                Text("Your completed answers will appear here.").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
                }
            }
            .task(id: dashboardRequest) {
                let request = dashboardRequest
                publishedDashboardRequest = nil
                guard request.isActive else { dashboardProjection.cancel(); return }
                let input = store.progressDashboardInput(filters: request.filters, clock: request.clock)
                await dashboardProjection.update(input)
                guard !Task.isCancelled, request == dashboardRequest else { return }
                publishedDashboardRequest = request
            }
            .task(id: isDashboardActive) {
                guard isDashboardActive else { return }
                // Foreground entry is immediate. While visible, a bounded tick
                // also catches rolling cutoffs and clock changes without writes.
                while !Task.isCancelled {
                    refreshDashboardClock()
                    do { try await Task.sleep(for: .seconds(NFProgressDashboardClock.maximumRefreshInterval)) }
                    catch { return }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshDashboardClock() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refreshDashboardClock() }
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in refreshDashboardClock() }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refreshDashboardClock() }
            #endif
            .onDisappear { dashboardProjection.cancel(); publishedDashboardRequest = nil }
            .navigationTitle("Progress")
            .navigationDestination(for: NFProgressRoute.self) { route in
                NFProgressRouteView(route: route, filters: $filters)
            }
        }
    }

    @ViewBuilder private var correctionNotice: some View {
        if !store.unacknowledgedCorrections.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("A progress explanation was updated", systemImage: "info.circle").font(.headline)
                Text("Your original answers are unchanged. Review the affected answers to see why their contribution to progress changed.")
                DisclosureGroup("Affected answers") {
                    ForEach(store.unacknowledgedCorrections) { correction in
                        if let id = UUID(uuidString: correction.attemptID) {
                            NavigationLink(value: NFProgressRoute.attempt(id)) {
                                Text(LocalizedStringKey(correction.reason))
                            }.frame(minHeight: 44)
                        }
                    }
                }
                Button("Dismiss update") {
                    do { try store.acknowledgeCorrections(); correctionSaveError = false }
                    catch { correctionSaveError = true }
                }.buttonStyle(.bordered)
                if correctionSaveError { Text("We couldn't save this yet. Your answer is still here.").foregroundStyle(.secondary) }
            }.nfCard()
        }
    }

    @ViewBuilder private var historicalPracticeCard: some View {
        let history = store.historicalPracticeSummaries
            .filter { $0.legacyCount > 0 }
        if !history.isEmpty {
            DisclosureGroup("Historical practice") {
                Text("Earlier practice is preserved here. It is separate from reviewed challenge-band evidence.").font(.subheadline)
                ForEach(history, id: \.labID) { summary in
                    if let lab = TrainingLab(rawValue: summary.labID) {
                        NavigationLink(value: NFProgressRoute.history(lab)) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(lab.title).font(.headline)
                                Text(NFAppLocalization.formattedAnswerCount(summary.legacyCount))
                                if let mean = summary.legacyMeanCredit {
                                    LabeledContent("Historical mean credit", value: mean.formatted(.percent.precision(.fractionLength(0))))
                                }
                            }
                        }
                    }
                }
            }.nfCard()
        }
    }

    private var overviewHero: some View {
        let hasOnlyPersonalPractice = totalEvidence == 0 && personalPracticeCount > 0
        let isFilteredEmpty = hasAnyStandardizedHistory && !hasMatchingStandardizedHistory
        let hasMatchingUnscoredActivity = hasMatchingStandardizedHistory && totalEvidence == 0
        let layout = dynamicTypeSize.isAccessibilitySize || horizontalSizeClass == .compact
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(spacing: 24))
        return layout {
            ZStack {
                Circle()
                    .stroke(NFTheme.indigo.opacity(0.12), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: Double(assessedCount) / Double(max(1, eligibleAbilityLabs.count)))
                    .stroke(
                        AngularGradient(colors: [NFTheme.indigo, NFTheme.cyan, NFTheme.mint], center: .center),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(assessedCount)")
                        .font(.title.bold().monospacedDigit())
                    Text("OF \(eligibleAbilityLabs.count)")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(assessedCount) of \(eligibleAbilityLabs.count) foundational abilities have results")

            VStack(alignment: .leading, spacing: 9) {
                Text(isFilteredEmpty
                     ? "No results match these filters."
                     : hasMatchingUnscoredActivity
                        ? "Matching activity has no scored evidence."
                     : hasOnlyPersonalPractice
                        ? "Your practice history is growing."
                        : totalEvidence == 0 ? "Practice reveals your next steps." : "Your skill map is taking shape.")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(isFilteredEmpty
                     ? "Your saved history is still available. Change or clear the active filters to include it."
                     : hasMatchingUnscoredActivity
                        ? "The matching records are skips or non-scoring activity, so they do not change the skill map."
                     : hasOnlyPersonalPractice
                        ? "Saved personal-practice history: \(NFAppLocalization.formattedAnswerCount(personalPracticeCount)). Complete daily practice or a skill check to begin your skill map."
                        : totalEvidence == 0
                            ? "Complete a few questions to reveal your first priorities."
                            : "Your practice plan now uses \(NFAppLocalization.formattedScoredAnswerCount(totalEvidence)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if isFilteredEmpty {
                    Button("Clear filters") { clearProgressFilters() }
                        .buttonStyle(.bordered)
                        .tint(NFTheme.indigoForeground)
                } else {
                    NFStatusPill(
                        text: hasOnlyPersonalPractice
                            ? NFAppLocalization.formattedPersonalAnswerCount(personalPracticeCount)
                            : NFAppLocalization.formattedScoredAnswerCount(totalEvidence),
                        symbol: hasOnlyPersonalPractice ? "clock.arrow.circlepath" : "circle.hexagongrid.fill",
                        color: hasOnlyPersonalPractice ? NFTheme.amber : NFTheme.indigo
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .nfCard(cornerRadius: 26)
    }

    private func forgeJourneyCard(_ progress: NFForgeProgressSnapshot) -> some View {
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [NFTheme.gold.opacity(0.28), NFTheme.rose.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    VStack(spacing: 0) {
                        Text("\(progress.level)")
                            .font(.title.bold().monospacedDigit())
                        Text("LEVEL")
                            .font(.caption2.weight(.heavy))
                            .tracking(1)
                    }
                }
                .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Forge journey")
                        .font(.title3.bold())
                    HStack {
                        Text("\(progress.totalXP) XP earned")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                        Spacer()
                        Text("\(progress.xpToNextLevel) to next level")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    NFForgeProgressBar(
                        progress: progress.levelProgress,
                        accent: NFTheme.gold,
                        secondary: NFTheme.rose,
                        height: 8
                    )
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                DetailMetric(
                    value: NFAppLocalization.formattedActiveDayCount(progress.momentum.currentActiveDayStreak),
                    label: "Current momentum run"
                )
                DetailMetric(
                    value: "\(progress.currentWeekCoveredLabs.count) / \(progress.accessibleLabs.count)",
                    label: "Abilities this week"
                )
                DetailMetric(
                    value: "\(progress.milestones.count) / \(NFForgeMilestoneCode.allCases.count)",
                    label: "Milestones"
                )
            }

            Label(
                "Practice XP acknowledges completed practice and breadth. It is separate from accuracy, transfer, retention, and skill evidence.",
                systemImage: "checkmark.shield.fill"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .nfGameCard(accent: NFTheme.gold, secondary: NFTheme.violet, cornerRadius: 26)
    }

    private var progressFiltersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            NFSectionHeader(
                "Choose what to show",
                subtitle: "Applies to the overview, weekly trend, and detailed views."
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                Picker("Date range", selection: $filters.period) {
                    ForEach(NFProgressPeriod.allCases) { period in Text(period.title).tag(period) }
                }
                Picker("Module", selection: $filters.lab) {
                    Text("All modules").tag(nil as TrainingLab?)
                    ForEach(TrainingLab.allCases) { lab in Text(lab.shortTitle).tag(Optional(lab)) }
                }
                Picker("Input mode", selection: $filters.inputMode) {
                    Text("All inputs").tag(nil as String?)
                    ForEach(inputModeOptions, id: \.self) { mode in
                        Text(NFInputModality.title(forPersistedValue: mode)).tag(Optional(mode))
                    }
                }
                Picker("Timing", selection: $filters.timing) {
                    ForEach(NFProgressTimingFilter.allCases) { timing in Text(timing.title).tag(timing) }
                }
                Picker("Domain context", selection: $filters.domain) {
                    Text("All domains").tag(nil as STEMField?)
                    ForEach(domainOptions) { field in Text(field.title).tag(Optional(field)) }
                }
            }
            .pickerStyle(.menu)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(totalEvidence) results match · \(filters.summary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if filters.hasRestrictions {
                    Button("Clear filters") { clearProgressFilters() }
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .nfCard()
    }

    private var weeklyTrendCard: some View {
        let points = dashboardSnapshot?.weeklyPoints ?? []
        let inspected = NFWeeklyProgressPoint.inspect(at: inspectedWeek, in: points)
        return VStack(alignment: .leading, spacing: 12) {
            NFSectionHeader(
                "Weekly practice by activity",
                subtitle: "Scored answers in the selected filters."
            )
            if points.isEmpty {
                let hasMatchingActivity = !filteredAttempts.isEmpty
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        hasMatchingActivity
                            ? "No scored chart data"
                            : hasAnyStandardizedHistory ? "No matching activity" : "No activity yet",
                        systemImage: hasMatchingActivity
                            ? "chart.xyaxis.line"
                            : hasAnyStandardizedHistory ? "line.3.horizontal.decrease.circle" : "chart.xyaxis.line",
                        description: Text(hasMatchingActivity
                                          ? "Matching activity exists, but it contains no eligible scored answers for this chart."
                                          : hasAnyStandardizedHistory
                                            ? "Your history is intact, but the active filters exclude it."
                                            : "Complete a scored question to begin this chart.")
                    )
                    if !hasMatchingActivity && hasAnyStandardizedHistory && filters.hasRestrictions {
                        Button("Clear filters") { clearProgressFilters() }
                            .buttonStyle(.bordered)
                    }
                }
                .frame(minHeight: 180)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Week", point.week),
                        y: .value("Earned credit", point.credit)
                    )
                    .foregroundStyle(by: .value("Module", point.lab.shortTitle))
                    .symbol(by: .value("Module", point.lab.shortTitle))
                    PointMark(
                        x: .value("Week", point.week),
                        y: .value("Earned credit", point.credit)
                    )
                    .foregroundStyle(by: .value("Module", point.lab.shortTitle))
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.5, 1]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number, format: .percent.precision(.fractionLength(0)))
                            }
                        }
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear)) }
                .chartXSelection(value: $inspectedWeek)
                .frame(height: 260)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(NFWeeklyProgressPoint.accessibilitySummary(for: points))

                Text("Select a point to inspect the saved answers behind it.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(inspected) { point in
                    NFProgressPointInspection(date: point.week, activity: point.lab.shortTitle,
                        sampleCount: point.count, value: point.credit,
                        onShowHistory: { navigation.progress.append(.chartHistory(point.attemptIDs)) })
                }

                DisclosureGroup("View weekly chart data") {
                    let page = min(weeklyChartDataPage, max(0, (points.count - 1) / 50))
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(points.dropFirst(page * 50).prefix(50))) { point in
                            Button {
                                navigation.progress.append(.chartHistory(point.attemptIDs))
                            } label: {
                                NFProgressChartDataRow(date: point.week, activity: point.lab.shortTitle,
                                    sampleCount: point.count, value: point.credit)
                            }
                            .accessibilityHint("View matching history")
                        }
                        HStack {
                            Button("Previous page") { weeklyChartDataPage = max(0, page - 1) }
                                .disabled(page == 0)
                            Spacer()
                            Text("Page \(page + 1)").font(.caption)
                            Spacer()
                            Button("Next page") { weeklyChartDataPage = page + 1 }
                                .disabled((page + 1) * 50 >= points.count)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline)
            }
        }
        .nfCard()
    }

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NFSectionHeader("Practice next", subtitle: "The skills that can help you most right now.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                ForEach(Array(store.currentPriorityBreakdowns.prefix(3))) { priority in
                    let recommendation = practiceRecommendation(for: priority)
                    Button {
                        launch(recommendation)
                    } label: {
                        PriorityCard(
                            title: priority.lab.title,
                            reason: priority.reasons.first?.title
                                ?? NFAppLocalization.localized("Evidence priority", locale: NFAppLocalization.preferredLocale, comment: "Fallback reason label for a recommended practice priority."),
                            detail: recommendation.rationale,
                            configuration: recommendation.configurationSummary,
                            symbol: priority.lab.symbol,
                            accentColor: NFTheme.color(for: priority.lab.colorToken),
                            foregroundColor: NFTheme.foregroundColor(for: priority.lab.colorToken)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Starts this recommended activity with its displayed module, practice type, duration, and timing preference.")
                }
            }
        }
    }

    private func consistencyCard(_ snapshot: NFConsistencySnapshot) -> some View {
        return VStack(alignment: .leading, spacing: 14) {
            NFSectionHeader(
                "Consistency",
                subtitle: "Build a steady rhythm without losing past progress."
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                DetailMetric(value: "\(snapshot.currentActiveDayStreak)", label: "Current active-day run")
                DetailMetric(value: "\(snapshot.activeDaysInWindow)", label: "Active days · 28 days")
                DetailMetric(value: "\(snapshot.protectedPauseCount)", label: "Protected pauses · 28 days")
            }

            HStack(spacing: 6) {
                ForEach(snapshot.days.suffix(14)) { day in
                    ZStack {
                        Circle()
                            .fill(consistencyColor(day.status))
                        Image(systemName: consistencySymbol(day.status))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.primary)
                            .accessibilityHidden(true)
                    }
                        .frame(width: 20, height: 20)
                        .accessibilityLabel("\(NFAppLocalization.formattedDate(day.date, date: .abbreviated, time: .omitted)): \(consistencyLabel(day.status))")
                }
            }

            Text(snapshot.protectionAvailableThisWeek
                 ? "You can take one flex day this week without breaking your active-day run."
                 : "You have used this week’s flex day. Your earlier progress stays intact.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                NFStatusPill(text: "Active", symbol: "checkmark.circle.fill", color: NFTheme.mint)
                NFStatusPill(text: "Planned rest", symbol: "moon.zzz.fill", color: NFTheme.cyan)
                NFStatusPill(text: "Flex day", symbol: "shield.fill", color: NFTheme.indigo)
            }
        }
        .nfCard()
    }

    private func consistencyColor(_ status: NFConsistencyDayStatus) -> Color {
        switch status {
        case .active: NFTheme.mint
        case .plannedRest: NFTheme.cyan.opacity(0.55)
        case .protectedPause: NFTheme.indigo.opacity(0.65)
        case .missedPlanned: Color.secondary.opacity(0.25)
        case .availableToday: Color.secondary.opacity(0.12)
        }
    }

    private func consistencyLabel(_ status: NFConsistencyDayStatus) -> String {
        switch status {
        case .active: NFAppLocalization.localized("active", locale: NFAppLocalization.preferredLocale, comment: "Accessibility label for an active training day.")
        case .plannedRest: NFAppLocalization.localized("planned rest", locale: NFAppLocalization.preferredLocale, comment: "Accessibility label for a planned rest day.")
        case .protectedPause: NFAppLocalization.localized("flex day", locale: NFAppLocalization.preferredLocale, comment: "Accessibility label for the weekly flexible day.")
        case .missedPlanned: NFAppLocalization.localized("planned day without practice", locale: NFAppLocalization.preferredLocale, comment: "Neutral accessibility label for a planned day with no practice.")
        case .availableToday: NFAppLocalization.localized("available today", locale: NFAppLocalization.preferredLocale, comment: "Accessibility label for today's available plan.")
        }
    }

    private var evidenceChannelsCard: some View {
        let personalCount = personalPracticeCount
        let counts = dashboardSnapshot?.categories ?? [:]
        return VStack(alignment: .leading, spacing: 13) {
            NFSectionHeader("Kinds of practice", subtitle: "See where your completed questions came from.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                EvidenceChannelMetric(title: "Practice", count: counts[.practice, default: 0], symbol: "repeat", foregroundColor: NFTheme.indigoForeground)
                EvidenceChannelMetric(title: "Transfer", count: counts[.nearTransfer, default: 0] + counts[.appliedTransfer, default: 0], symbol: "arrow.triangle.swap", foregroundColor: NFTheme.roseForeground)
                EvidenceChannelMetric(title: "Retention", count: counts[.retention, default: 0], symbol: "clock.arrow.circlepath", foregroundColor: NFTheme.mintForeground)
                EvidenceChannelMetric(title: "Protected assessment", count: counts[.assessmentHoldout, default: 0], symbol: "lock.shield.fill", foregroundColor: NFTheme.cyanForeground)
                EvidenceChannelMetric(title: "Personal AI/source", count: personalCount, symbol: "apple.intelligence", foregroundColor: NFTheme.amberForeground)
            }
        }
    }

    private var mentalMathMetricsCard: some View {
        let metrics = mentalMathMetrics
        return VStack(alignment: .leading, spacing: 14) {
            NFSectionHeader(
                "Mental-math details",
                subtitle: "Practice details appear when the saved question provides enough context."
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                ForEach(NFMentalMathMetricKind.allCases, id: \.rawValue) { kind in
                    if let result = metrics[kind] {
                        VStack(alignment: .leading, spacing: 7) {
                            Label(mentalMathMetricTitle(kind), systemImage: mentalMathMetricSymbol(kind))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(mentalMathMetricForegroundColor(kind))
                            Text(mentalMathMetricValue(result))
                                .font(.title3.bold().monospacedDigit())
                            Text(result.isAvailable
                                 ? NFAppLocalization.formattedEligibleAnswerCount(result.sampleCount)
                                 : NFAppLocalization.formattedAnswerRequirement(
                                    completed: result.sampleCount,
                                    required: result.minimumSampleCount
                                 ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Text("Speed uses correct, uninterrupted Rapid Recall work. Skips and hints do not raise these results.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .nfCard()
    }

    private func mentalMathMetricTitle(_ kind: NFMentalMathMetricKind) -> String {
        switch kind {
        case .independentAccuracy: NFAppLocalization.localized("Practice accuracy", locale: NFAppLocalization.preferredLocale, comment: "Descriptive accuracy from eligible saved mental-math practice; reviewed independence is not inferred.")
        case .retrievalFluency: NFAppLocalization.localized("Retrieval fluency", locale: NFAppLocalization.preferredLocale, comment: "Independent mental-math progress metric for eligible accurate timed recall.")
        case .strategyFlexibility: NFAppLocalization.localized("Strategy flexibility", locale: NFAppLocalization.preferredLocale, comment: "Independent mental-math progress metric for valid strategy variety.")
        case .estimationError: NFAppLocalization.localized("Estimation error", locale: NFAppLocalization.preferredLocale, comment: "Independent mental-math progress metric; lower error is better.")
        case .unitHandling: NFAppLocalization.localized("Unit handling", locale: NFAppLocalization.preferredLocale, comment: "Independent mental-math progress metric for correct physical or scientific units.")
        case .retention: NFAppLocalization.localized("Delayed retention", locale: NFAppLocalization.preferredLocale, comment: "Independent mental-math progress metric for recall after a delay.")
        case .transfer: NFAppLocalization.localized("Unfamiliar transfer", locale: NFAppLocalization.preferredLocale, comment: "Independent mental-math progress metric for unfamiliar applications.")
        }
    }

    private func mentalMathMetricSymbol(_ kind: NFMentalMathMetricKind) -> String {
        switch kind {
        case .independentAccuracy: "checkmark.seal"
        case .retrievalFluency: "timer"
        case .strategyFlexibility: "arrow.triangle.branch"
        case .estimationError: "scope"
        case .unitHandling: "ruler"
        case .retention: "clock.arrow.circlepath"
        case .transfer: "arrow.triangle.swap"
        }
    }

    private func mentalMathMetricForegroundColor(_ kind: NFMentalMathMetricKind) -> Color {
        switch kind {
        case .independentAccuracy, .unitHandling: NFTheme.mintForeground
        case .retrievalFluency, .retention: NFTheme.cyanForeground
        case .strategyFlexibility: NFTheme.indigoForeground
        case .estimationError: NFTheme.amberForeground
        case .transfer: NFTheme.roseForeground
        }
    }

    private func consistencySymbol(_ status: NFConsistencyDayStatus) -> String {
        switch status {
        case .active: "checkmark"
        case .plannedRest: "moon.fill"
        case .protectedPause: "shield.fill"
        case .missedPlanned: "xmark"
        case .availableToday: "circle.fill"
        }
    }

    private func mentalMathMetricValue(_ result: NFMentalMathMetricResult) -> String {
        guard let value = result.value, result.isAvailable else {
            return NFAppLocalization.localized("More answers needed", locale: NFAppLocalization.preferredLocale, comment: "Progress metric status when more answers are needed for a value.")
        }
        switch result.unit {
        case .proportion, .relativeError:
            return value.formatted(.percent.precision(.fractionLength(0...1)))
        case .seconds:
            return NFAppLocalization.formattedSeconds(value, style: .compact)
        }
    }

    private var skillMap: some View {
        VStack(alignment: .leading, spacing: 14) {
            NFSectionHeader("Skill map", subtitle: "Choose a lab to see its history and next steps.")
            if hasAnyStandardizedHistory && !hasMatchingStandardizedHistory {
                VStack(spacing: 10) {
                    ContentUnavailableView(
                        "No abilities match",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("The active filters exclude your saved answers.")
                    )
                    Button("Clear filters") { clearProgressFilters() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredSummaries) { summary in
                        Button {
                            navigation.progress.append(.skill(summary.lab))
                        } label: {
                            SkillRow(summary: summary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var calibrationCard: some View {
        let calibration = dashboardSnapshot?.calibration ?? .init(attempts: [])
        let calibrated = calibration.matchingCount
        let fraction = calibration.fraction ?? 0

        return HStack(spacing: 20) {
            Gauge(value: fraction) {
                Text("Calibration")
            } currentValueLabel: {
                Text(calibration.eligibleCount == 0 ? "—" : fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.headline.monospacedDigit())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(Gradient(colors: [NFTheme.amber, NFTheme.cyan, NFTheme.mint]))
            .frame(width: 90)

            VStack(alignment: .leading, spacing: 5) {
                Text("Confidence calibration")
                    .font(.headline)
                Text(
                    calibration.eligibleCount == 0
                        ? "Answer a few questions to see how confidence matches accuracy."
                        : "Confidence matched accuracy for \(calibrated) of \(NFAppLocalization.formattedAnswerCount(calibration.eligibleCount))."
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .nfCard()
    }

    private var methodologyNote: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(NFTheme.indigoForeground)
            Text("NeuroForge reports performance on defined tasks. It is not an intelligence test, medical device, diagnostic service, or treatment. Results may not generalize to other activities.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var errorPatternsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            NFSectionHeader("Common error patterns", subtitle: "Use these patterns to decide what to revisit.")
            if dashboardProjection.isLoading {
                ProgressView().accessibilityLabel("Common error patterns")
            } else if errorPatterns.isEmpty {
                Text("No repeated mistakes yet.").foregroundStyle(.secondary).nfCard(cornerRadius: 16, padding: 14)
            } else {
                ForEach(Array(errorPatterns.prefix(5))) { pattern in
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(NFTheme.amberForeground)
                            .accessibilityHidden(true)
                        Text(localizedErrorTitle(pattern.code)).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(pattern.count) ×").font(.caption.bold().monospacedDigit())
                        Text(pattern.last.map { NFAppLocalization.formattedDate($0, date: .abbreviated, time: .omitted) } ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var calibrationDescription: String {
        let biases = filteredSummaries.compactMap(\.calibrationBias)
        guard !biases.isEmpty else {
            return NFAppLocalization.localized("Collect confidence before feedback.", locale: NFAppLocalization.preferredLocale, comment: "Confidence-calibration status when no evidence is available.")
        }
        let average = biases.reduce(0, +) / Double(biases.count)
        if average > 0.12 {
            return NFAppLocalization.localized("Recent responses lean overconfident.", locale: NFAppLocalization.preferredLocale, comment: "Confidence-calibration status.")
        }
        if average < -0.12 {
            return NFAppLocalization.localized("Recent responses lean underconfident.", locale: NFAppLocalization.preferredLocale, comment: "Confidence-calibration status.")
        }
        return NFAppLocalization.localized("Confidence is broadly aligned with accuracy.", locale: NFAppLocalization.preferredLocale, comment: "Confidence-calibration status.")
    }

    private func priorityDetail(_ priority: NFSchedulingScoreBreakdown) -> String {
        let factors: [(String, Double)] = [
            (NFAppLocalization.localized("A review is due soon.", locale: NFAppLocalization.preferredLocale, comment: "Learner-facing reason a skill is recommended next."), priority.reviewUrgency),
            (NFAppLocalization.localized("Matches the goals you selected.", locale: NFAppLocalization.preferredLocale, comment: "Learner-facing reason a skill is recommended next."), priority.normalizedGoalWeight),
            (NFAppLocalization.localized("Recent answers make this worth revisiting.", locale: NFAppLocalization.preferredLocale, comment: "Learner-facing reason a skill is recommended next."), priority.weaknessRelativeToGoal),
            (NFAppLocalization.localized("A few more answers will clarify your level.", locale: NFAppLocalization.preferredLocale, comment: "Learner-facing reason a skill is recommended next."), priority.estimateUncertainty),
            (NFAppLocalization.localized("Using this skill in a new context may help.", locale: NFAppLocalization.preferredLocale, comment: "Learner-facing reason a skill is recommended next."), priority.transferGap),
            (NFAppLocalization.localized("Adds variety to your recent practice.", locale: NFAppLocalization.preferredLocale, comment: "Learner-facing reason a skill is recommended next."), priority.varietyNeed)
        ]
        let leading = factors.max(by: { $0.1 < $1.1 })
            ?? (NFAppLocalization.localized("A useful next step for your plan.", locale: NFAppLocalization.preferredLocale, comment: "Fallback learner-facing reason a skill is recommended next."), 0)
        return leading.0
    }

    private func practiceRecommendation(for priority: NFSchedulingScoreBreakdown) -> NFPracticeRecommendation {
        let mode: EvidenceClass = priority.transferGap >= max(
            priority.reviewUrgency,
            priority.weaknessRelativeToGoal,
            priority.estimateUncertainty,
            priority.varietyNeed
        ) ? .nearTransfer : .practice
        let duration = min(10, max(5, store.profileSnapshot.dailyDuration / 2))
        return NFPracticeRecommendation(
            lab: priority.lab,
            evidenceClass: mode,
            durationMinutes: duration,
            itemCount: max(5, min(12, duration * 2)),
            timingMode: store.profileSnapshot.timingMode,
            field: store.profileSnapshot.fields.sorted { $0.rawValue < $1.rawValue }.first,
            reasonRaw: (priority.reasons.first ?? .skillGap).rawValue,
            rationale: priorityDetail(priority)
        )
    }

    private func launch(_ recommendation: NFPracticeRecommendation) {
        store.beginSession(
            lab: recommendation.lab,
            source: .focused,
            requestedMinutes: recommendation.durationMinutes,
            evidenceClass: recommendation.evidenceClass,
            field: recommendation.field,
            recommendationRationale: recommendation.rationale,
            targetDifficulty: recommendation.targetDifficulty,
            requestedItemCount: recommendation.itemCount,
            planID: recommendation.launchPlanID,
            planBlockID: recommendation.launchPlanBlockID,
            isTimed: recommendation.explicitTiming
        )
    }

    private func clearProgressFilters() {
        filters = .unfiltered
    }

    private func localizedErrorTitle(_ code: String) -> String {
        if let reflectionCode = NFErrorReflectionCode(rawValue: code) {
            return reflectionCode.title
        }
        let deterministicTitle = NFScoringErrorCopy.title(for: code)
        guard !deterministicTitle.contains(code) else {
            return NFAppLocalization.localized(
                "Other scored pattern",
                locale: NFAppLocalization.preferredLocale,
                comment: "Safe learner-facing fallback for an unrecognized deterministic scoring-error code."
            )
        }
        return deterministicTitle
    }

    private var inputModeOptions: [String] {
        Array(Set(store.standardizedAttempts.map(\.inputModeRaw).filter { !$0.isEmpty && $0 != "unknown" })).sorted()
    }

    private var domainOptions: [STEMField] {
        Array(Set(store.standardizedAttempts.compactMap { STEMField(rawValue: $0.domainContextRaw) }))
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

enum NFProgressPeriod: String, CaseIterable, Identifiable {
    case currentWeek
    case fourWeeks
    case allTime

    var id: String { rawValue }
    var title: String {
        switch self {
        case .currentWeek: NFAppLocalization.localized("Current week", locale: NFAppLocalization.preferredLocale, comment: "Progress-history time filter.")
        case .fourWeeks: NFAppLocalization.localized("Last 4 weeks", locale: NFAppLocalization.preferredLocale, comment: "Progress-history time filter.")
        case .allTime: NFAppLocalization.localized("All time", locale: NFAppLocalization.preferredLocale, comment: "Progress-history time filter.")
        }
    }

    var cutoff: Date? { cutoff(at: Date(), calendar: .current) }

    func cutoff(at date: Date, calendar: Calendar) -> Date? {
        switch self {
        case .currentWeek: calendar.dateInterval(of: .weekOfYear, for: date)?.start
        case .fourWeeks: calendar.date(byAdding: .day, value: -28, to: date)
        case .allTime: nil
        }
    }
}

enum NFProgressTimingFilter: String, CaseIterable, Identifiable {
    case all
    case timed
    case untimed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: NFAppLocalization.localized("Timed + untimed", locale: NFAppLocalization.preferredLocale, comment: "Progress-history timing filter.")
        case .timed: NFAppLocalization.localized("Timed only", locale: NFAppLocalization.preferredLocale, comment: "Progress-history timing filter.")
        case .untimed: NFAppLocalization.localized("Untimed only", locale: NFAppLocalization.preferredLocale, comment: "Progress-history timing filter.")
        }
    }
}

struct NFProgressFilters: Equatable {
    var period: NFProgressPeriod = .fourWeeks
    var lab: TrainingLab?
    var inputMode: String?
    var timing: NFProgressTimingFilter = .all
    var domain: STEMField?

    static let unfiltered = NFProgressFilters(period: .allTime)

    var hasRestrictions: Bool {
        period != .allTime || lab != nil || inputMode != nil || timing != .all || domain != nil
    }

    func includes(_ attempt: AttemptRecord, at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        if let cutoff = period.cutoff(at: date, calendar: calendar), attempt.submittedAt < cutoff { return false }
        if let lab, attempt.gameID != lab.rawValue { return false }
        if let inputMode, attempt.inputModeRaw != inputMode { return false }
        switch timing {
        case .all: break
        case .timed where !attempt.wasTimed: return false
        case .untimed where attempt.wasTimed: return false
        default: break
        }
        if let domain, attempt.domainContextRaw != domain.rawValue { return false }
        return true
    }

    var summary: String {
        [
            period.title,
            lab?.shortTitle ?? NFAppLocalization.localized("all modules", locale: NFAppLocalization.preferredLocale, comment: "Progress-filter summary when every training module is included."),
            inputMode.map(NFInputModality.title(forPersistedValue:)) ?? NFAppLocalization.localized("all inputs", locale: NFAppLocalization.preferredLocale, comment: "Progress-filter summary when every answer-input mode is included."),
            timing.title,
            domain?.title ?? NFAppLocalization.localized("all domains", locale: NFAppLocalization.preferredLocale, comment: "Progress-filter summary when every STEM field is included.")
        ].joined(separator: " · ")
    }
}

/// Immutable, effective observations are the only inputs to public scored charts.
/// Duplicate identities count once; conflicting identities and invalid values are
/// omitted as a whole, so input order cannot decide which result is displayed.
enum NFProgressEvidenceProjection {
    static func eligible(_ observations: [AttemptDTO], at date: Date = Date()) -> [AttemptDTO] {
        validUnique(observations, at: date).filter {
            $0.evidenceClass != .assessmentHoldout && $0.evidenceClass != .nearTransfer
        }
    }

    /// Counts disclose activity coverage only; restricted per-item scores are
    /// never returned to the chart or inspection renderer through this API.
    static func categoryCounts(_ observations: [AttemptDTO], at date: Date = Date()) -> [EvidenceClass: Int] {
        Dictionary(grouping: validUnique(observations, at: date), by: \.evidenceClass).mapValues(\.count)
    }

    private static func validUnique(_ observations: [AttemptDTO], at date: Date) -> [AttemptDTO] {
        Dictionary(grouping: observations, by: \.id).values.compactMap { copies in
            guard let first = copies.first, copies.allSatisfy({ equivalent(first, $0) }),
                  !first.wasSkipped, first.evidenceClass != .documentPractice,
                  !["selfcheck", "sourceselfcheck", "selfreported", "revealed", "solutionrevealed"].contains(
                    first.responseFormatRaw?.lowercased().filter { $0.isLetter || $0.isNumber } ?? ""),
                  first.credit.isFinite, (0...1).contains(first.credit),
                  first.evidenceWeight.isFinite, first.evidenceWeight > 0,
                  first.submittedAt.timeIntervalSinceReferenceDate.isFinite,
                  first.submittedAt <= date else { return nil }
            return first
        }.sorted { $0.submittedAt == $1.submittedAt
            ? $0.id.uuidString < $1.id.uuidString : $0.submittedAt < $1.submittedAt }
    }

    private static func equivalent(_ lhs: AttemptDTO, _ rhs: AttemptDTO) -> Bool {
        lhs.id == rhs.id && lhs.itemID == rhs.itemID && lhs.alternateFormID == rhs.alternateFormID
            && lhs.skillID == rhs.skillID && lhs.skillWeights == rhs.skillWeights && lhs.lab == rhs.lab
            && lhs.credit == rhs.credit && lhs.correct == rhs.correct
            && lhs.evidenceWeight == rhs.evidenceWeight && lhs.evidenceClass == rhs.evidenceClass
            && lhs.submittedAt == rhs.submittedAt && lhs.wasSkipped == rhs.wasSkipped
            && lhs.responseFormatRaw == rhs.responseFormatRaw && lhs.hintCount == rhs.hintCount
            && lhs.wasTimed == rhs.wasTimed && lhs.confidence == rhs.confidence
            && lhs.interruptionCount == rhs.interruptionCount && lhs.accommodationFlags == rhs.accommodationFlags
    }
}

@MainActor
extension AppStore {
    func chartHistoryRecords<IDs: Collection>(from records: [AttemptRecord], matching ids: IDs) -> [AttemptRecord] where IDs.Element == UUID {
        let membership = Set(ids)
        return records.filter { membership.contains($0.id) }
    }

    func publicPracticeChartObservations(from records: [AttemptRecord]) -> [AttemptDTO] {
        let protectedIDs = Set(records.filter {
            historyPresentation(for: .init(attempt: $0)).source == .protectedAssessment
        }.map(\.id))
        return records.filter { !protectedIDs.contains($0.id) }.map(effectiveAttemptDTO)
    }
}

struct NFWeeklyProgressPoint: Identifiable, Sendable {
    let week: Date
    let lab: TrainingLab
    let credit: Double
    let count: Int
    let attemptIDs: [UUID]

    var id: String { "\(week.timeIntervalSinceReferenceDate)|\(lab.rawValue)" }

    static func make(from attempts: [AttemptRecord], calendar: Calendar = .current) -> [NFWeeklyProgressPoint] {
        make(from: attempts.filter { NFReadOnlyAttemptSnapshot(attempt: $0).source != .protectedAssessment }.map(\.dto), calendar: calendar)
    }

    static func make(from observations: [AttemptDTO], calendar: Calendar = .current,
                     at date: Date = Date()) -> [NFWeeklyProgressPoint] {
        let eligible = NFProgressEvidenceProjection.eligible(observations, at: date)
        let grouped = Dictionary(grouping: eligible) { attempt in
            let week = calendar.dateInterval(of: .weekOfYear, for: attempt.submittedAt)?.start
                ?? calendar.startOfDay(for: attempt.submittedAt)
            return "\(week.timeIntervalSinceReferenceDate)|\(attempt.lab.rawValue)"
        }
        return grouped.compactMap { _, records in
            guard let first = records.first else { return nil }
            let week = calendar.dateInterval(of: .weekOfYear, for: first.submittedAt)?.start
                ?? calendar.startOfDay(for: first.submittedAt)
            // Scale weights before summing to avoid overflow on retained legacy values.
            guard let scale = records.map(\.evidenceWeight).max(), scale > 0 else { return nil }
            let available = records.reduce(0) { $0 + $1.evidenceWeight / scale }
            let earned = records.reduce(0) { $0 + $1.credit * ($1.evidenceWeight / scale) }
            guard available.isFinite, available > 0, earned.isFinite else { return nil }
            return NFWeeklyProgressPoint(week: week, lab: first.lab, credit: earned / available,
                count: records.count, attemptIDs: records.map(\.id))
        }.sorted {
            if $0.week != $1.week { return $0.week < $1.week }
            return $0.lab.rawValue < $1.lab.rawValue
        }
    }

    static func inspect(at date: Date?, in points: [NFWeeklyProgressPoint]) -> [NFWeeklyProgressPoint] {
        guard let date, date.timeIntervalSinceReferenceDate.isFinite,
              let nearest = points.min(by: { abs($0.week.timeIntervalSince(date)) < abs($1.week.timeIntervalSince(date)) }) else { return [] }
        return points.filter { $0.week == nearest.week }
    }

    static func accessibilitySummary(for points: [NFWeeklyProgressPoint]) -> String {
        guard let firstWeek = points.map(\.week).min(),
              let lastWeek = points.map(\.week).max() else {
            return NFAppLocalization.localized(
                "Weekly earned-credit chart. No matching scored answers.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Nonvisual summary for an empty weekly progress chart."
            )
        }

        let byLab = Dictionary(grouping: points, by: \.lab)
        let comparisons = byLab.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { lab -> String? in
            guard let series = byLab[lab]?.sorted(by: { $0.week < $1.week }),
                  let first = series.first,
                  let last = series.last else { return nil }
            let change = last.credit - first.credit
            let changeText: String
            if series.count == 1 {
                changeText = NFAppLocalization.localized(
                    "one recorded week",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Chart summary when a module has only one weekly point."
                )
            } else if abs(change) < 0.005 {
                changeText = NFAppLocalization.localized(
                    "unchanged",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Chart summary when a weekly performance series has no meaningful change."
                )
            } else {
                let direction = change > 0
                    ? NFAppLocalization.localized("up", locale: NFAppLocalization.preferredLocale, comment: "Chart trend direction.")
                    : NFAppLocalization.localized("down", locale: NFAppLocalization.preferredLocale, comment: "Chart trend direction.")
                changeText = "\(direction) \(abs(change).formatted(.percent.precision(.fractionLength(0))))"
            }
            return NFAppLocalization.localized("\(lab.shortTitle): \(last.credit.formatted(.percent.precision(.fractionLength(0)))) latest, \(changeText)",
                locale: NFAppLocalization.preferredLocale, comment: "Accessible weekly series summary: activity, latest value, descriptive change.")
        }
        let answerCount = NFAppLocalization.formattedScoredAnswerCount(
            points.reduce(0) { $0 + $1.count }
        )
        return NFAppLocalization.localized(
            "Weekly earned-credit chart from \(NFAppLocalization.formattedDate(firstWeek, date: .abbreviated, time: .omitted)) through \(NFAppLocalization.formattedDate(lastWeek, date: .abbreviated, time: .omitted)), covering \(answerCount). \(comparisons.joined(separator: "; ")).",
            locale: NFAppLocalization.preferredLocale,
            comment: "Nonvisual weekly progress-chart summary with range, answer count, latest module values, and changes."
        )
    }
}

struct NFPracticeRecommendation: Equatable {
    let lab: TrainingLab
    let evidenceClass: EvidenceClass
    let durationMinutes: Int
    let itemCount: Int
    let timingMode: TimingMode
    let field: STEMField?
    let reasonRaw: String
    let rationale: String

    let launchPlanID = "progress.practice-next.v1"

    var launchPlanBlockID: String {
        "\(launchPlanID).\(lab.rawValue).\(reasonRaw)"
    }

    var targetDifficulty: Double {
        evidenceClass == .nearTransfer ? 0.62 : 0.52
    }

    var explicitTiming: Bool? {
        switch timingMode {
        case .untimed: false
        case .adaptive: nil
        case .speedFocus: lab == .mentalMath ? true : nil
        }
    }

    var evidenceTitle: String {
        switch evidenceClass {
        case .practice:
            NFAppLocalization.localized("Focused practice", locale: NFAppLocalization.preferredLocale, comment: "Configured recommendation mode.")
        case .nearTransfer:
            NFAppLocalization.localized("Related transfer", locale: NFAppLocalization.preferredLocale, comment: "Configured recommendation mode.")
        case .appliedTransfer:
            NFAppLocalization.localized("Applied transfer", locale: NFAppLocalization.preferredLocale, comment: "Configured recommendation mode.")
        case .retention:
            NFAppLocalization.localized("Retention review", locale: NFAppLocalization.preferredLocale, comment: "Configured recommendation mode.")
        case .assessmentHoldout:
            NFAppLocalization.localized("Protected skill check", locale: NFAppLocalization.preferredLocale, comment: "Configured recommendation mode.")
        case .documentPractice:
            NFAppLocalization.localized("Personal source practice", locale: NFAppLocalization.preferredLocale, comment: "Configured recommendation mode.")
        }
    }

    var configurationSummary: String {
        let sourceTitle = NFAppLocalization.localized(
            "Focused session",
            locale: NFAppLocalization.preferredLocale,
            comment: "Configured recommendation launch source."
        )
        return "\(evidenceTitle) · \(NFAppLocalization.formattedMinutes(durationMinutes, style: .compact)) · \(timingMode.title) · \(sourceTitle)"
    }
}

/// A single ability-level evidence projection shared by the headline,
/// practice-type coverage, trend, and speed views. Cross-module attempts are
/// included only when their durable skill weights attribute evidence here.
struct NFAbilityEvidenceSnapshot {
    struct Metric: Equatable {
        let credit: Double?
        let count: Int
    }

    let lab: TrainingLab
    let attempts: [AttemptRecord]
    let observations: [AttemptDTO]

    init(lab: TrainingLab, attempts: [AttemptRecord], effectiveObservations: [AttemptDTO]? = nil,
         at date: Date = Date()) {
        self.lab = lab
        let inputIDs = Set(attempts.map(\.id))
        observations = NFProgressEvidenceProjection.eligible(effectiveObservations ?? attempts.filter {
            NFReadOnlyAttemptSnapshot(attempt: $0).source != .protectedAssessment
        }.map(\.dto), at: date)
            .filter { inputIDs.contains($0.id) && Self.attributedWeight(of: $0, to: lab) > 0 }
        let eligibleIDs = Set(observations.map(\.id))
        var seen: Set<UUID> = []
        self.attempts = attempts.filter { eligibleIDs.contains($0.id) && seen.insert($0.id).inserted }
    }

    var evidenceCount: Int { observations.count }
    var credit: Double? { metric(for: Set(EvidenceClass.allCases.filter { $0 != .documentPractice })).credit }
    var lastTrained: Date? { observations.map(\.submittedAt).max() }
    var status: EstimateStatus {
        AdaptiveEngine.reduce(observations).first(where: { $0.lab == lab })?.status ?? .unassessed
    }

    func metric(for classes: Set<EvidenceClass>) -> Metric {
        let matching = observations.filter { classes.contains($0.evidenceClass) }
        guard let scale = matching.map(\.evidenceWeight).max(), scale > 0 else { return Metric(credit: nil, count: 0) }
        let available = matching.reduce(0.0) { $0 + ($1.evidenceWeight / scale) * Self.attributedWeight(of: $1, to: lab) }
        let earned = matching.reduce(0.0) { $0 + $1.credit * ($1.evidenceWeight / scale) * Self.attributedWeight(of: $1, to: lab) }
        guard available.isFinite, available > 0, earned.isFinite else { return Metric(credit: nil, count: 0) }
        return Metric(credit: earned / available, count: matching.count)
    }

    static func attributedWeight(of attempt: AttemptRecord, to lab: TrainingLab) -> Double {
        attributedWeight(of: attempt.dto, to: lab)
    }

    static func attributedWeight(of attempt: AttemptDTO, to lab: TrainingLab) -> Double {
        if let direct = attempt.skillWeights[lab.skillID], direct.isFinite, direct > 0 { return direct }
        guard let dimension = attempt.assessmentDimension, dimension != .confidenceCalibration,
              dimension.lab == lab else { return 0 }
        let weight = attempt.skillWeights[dimension.skillID] ?? 1
        return weight.isFinite && weight > 0 ? weight : 0
    }
}

private struct NFErrorPattern: Identifiable {
    let code: String
    let count: Int
    let last: Date?

    var id: String { code }
}

private struct EvidenceChannelMetric: View {
    let title: String
    let count: Int
    let symbol: String
    let foregroundColor: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(foregroundColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(max(0, count))").font(.headline.monospacedDigit())
                Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .nfCard(cornerRadius: 15, padding: 12)
        .accessibilityElement(children: .combine)
    }
}

private struct PriorityCard: View {
    let title: String
    let reason: String
    let detail: String
    let configuration: String
    let symbol: String
    let accentColor: Color
    let foregroundColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NFIconTile(symbol: symbol, color: accentColor, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(reason.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(foregroundColor)
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                Text(configuration)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(foregroundColor)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle.fill")
                .foregroundStyle(foregroundColor)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .nfCard(cornerRadius: 18, padding: 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Start recommended \(title). \(reason). \(detail). \(configuration).")
    }
}

private struct SkillRow: View {
    let summary: SkillSummary

    var body: some View {
        HStack(spacing: 14) {
            NFIconTile(symbol: summary.lab.symbol, color: NFTheme.color(for: summary.lab.colorToken), size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(summary.lab.title)
                        .font(.headline)
                    Spacer()
                    Text(summary.status.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(summary.evidenceCount == 0 ? .secondary : NFTheme.foregroundColor(for: summary.lab.colorToken))
                }
                HStack(spacing: 8) {
                    EvidenceBand(value: normalizedTheta, uncertainty: summary.uncertainty, color: NFTheme.color(for: summary.lab.colorToken))
                    Text(NFAppLocalization.formattedAnswerCount(summary.evidenceCount))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 82, alignment: .trailing)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.06))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var normalizedTheta: Double { min(1, max(0, (summary.theta + 3) / 6)) }
}

private struct EvidenceBand: View {
    let value: Double
    let uncertainty: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let bandWidth = max(14, min(width, uncertainty / 2 * width))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.12))
                Capsule()
                    .fill(color.opacity(0.22))
                    .frame(width: bandWidth)
                    .offset(x: min(max(0, value * width - bandWidth / 2), width - bandWidth))
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .offset(x: min(max(0, value * width - 4.5), width - 9))
            }
        }
        .frame(height: 9)
        .accessibilityHidden(true)
    }
}

private struct SkillDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(NFNavigationState.self) private var navigation
    let lab: TrainingLab
    @Binding var filters: NFProgressFilters
    @State private var inspectedAnswerIndex: Int?
    @State private var chartDataPage = 0

    private var filteredAttempts: [AttemptRecord] {
        store.standardizedAttempts.filter { filters.includes($0) }
    }

    private var evidenceSnapshot: NFAbilityEvidenceSnapshot {
        NFAbilityEvidenceSnapshot(lab: lab, attempts: filteredAttempts,
            effectiveObservations: store.publicPracticeChartObservations(from: filteredAttempts))
    }

    private var historyAttempts: [AttemptRecord] {
        store.attempts.filter {
            filters.includes($0) && NFAbilityEvidenceSnapshot.attributedWeight(of: $0, to: lab) > 0
        }
    }

    private var hasUnfilteredLabHistory: Bool {
        store.attempts.contains {
            NFAbilityEvidenceSnapshot.attributedWeight(of: $0, to: lab) > 0
        }
    }

    private var hasMatchingLabHistory: Bool {
        !historyAttempts.isEmpty
    }

    private var improvementClaim: NFImprovementClaim? {
        NFImprovementClaimEngine.strongestClaim(
            for: lab,
            attempts: evidenceSnapshot.attempts.map(store.effectiveAttemptDTO)
        )
    }

    private var points: [EvidencePoint] {
        EvidencePoint.make(from: evidenceSnapshot.observations, attributedTo: lab)
    }

    private var speedEvidence: NFSpeedEvidence {
        NFSpeedEvidenceEngine.estimate(for: lab, attempts: evidenceSnapshot.attempts)
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(NFTheme.indigoForeground)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dashboard filters remain active")
                                .font(.subheadline.weight(.semibold))
                            Text(filters.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if filters.hasRestrictions {
                            Button("Clear filters") { filters = .unfiltered }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .nfCard(cornerRadius: 16, padding: 12)

                    HStack(spacing: 16) {
                        NFIconTile(symbol: lab.symbol, color: NFTheme.color(for: lab.colorToken), size: 62)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lab.title)
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            Text(evidenceSnapshot.status.title)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        DetailMetric(value: evidenceSnapshot.credit.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—", label: "Practice credit")
                        DetailMetric(value: "\(evidenceSnapshot.evidenceCount)", label: "Scored practice")
                        DetailMetric(value: evidenceSnapshot.lastTrained.map { NFAppLocalization.formattedDate($0, date: .abbreviated, time: .omitted) } ?? "Not yet", label: "Last trained")
                    }

                    if evidenceSnapshot.attempts.isEmpty {
                        filteredAbilityEmptyState
                    } else {
                        improvementEvidenceCard

                        speedEvidenceCard

                        transferGapCard

                        evidenceChart

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Practice coverage").font(.title2.bold())
                            Text("Every row and the headline above use the same filtered evidence—\(NFAppLocalization.formattedScoredAnswerCount(evidenceSnapshot.evidenceCount))—including cross-module skill attribution.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            EvidenceCoverageRow(label: "Training", detail: metric(for: .practice), symbol: "repeat", color: NFTheme.indigoForeground)
                            EvidenceCoverageRow(label: "Applied transfer", detail: metric(for: .appliedTransfer), symbol: "arrow.triangle.swap", color: NFTheme.roseForeground)
                            EvidenceCoverageRow(label: "Delayed retention", detail: metric(for: .retention), symbol: "clock.arrow.circlepath", color: NFTheme.mintForeground)
                            Text("Protected checks appear in skill summaries; their individual results are not plotted.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .nfCard()
                    }

                    NavigationLink(value: NFProgressRoute.history(lab)) {
                        HStack(spacing: 14) {
                            NFIconTile(symbol: "list.bullet.rectangle.portrait", color: NFTheme.indigo, size: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Answer history").font(.headline)
                                Text("\(NFAppLocalization.formattedIndividualAnswerCount(historyAttempts.count)) · filter by date, activity, result, timing, support, confidence, and source")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .nfCard()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("What this score means", systemImage: "text.book.closed.fill")
                            .font(.title2.bold())
                        Text("This lab focuses on")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NFTheme.indigoForeground)
                        Text(lab.subtitle)
                        Text("Keep in mind")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NFTheme.indigoForeground)
                        Text("Improvement may be strongest on similar questions. Using the skill in unfamiliar situations can take more practice.")
                            .foregroundStyle(.secondary)
                    }
                    .nfCard()
                }
                .padding(20)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(lab.shortTitle)
    }

    private var filteredAbilityEmptyState: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                hasMatchingLabHistory
                    ? "No scored evidence in this view"
                    : hasUnfilteredLabHistory ? "No matching answers" : "No answers for this ability yet",
                systemImage: hasMatchingLabHistory
                    ? "chart.bar.doc.horizontal"
                    : hasUnfilteredLabHistory ? "line.3.horizontal.decrease.circle" : "sparkles.rectangle.stack",
                description: Text(hasMatchingLabHistory
                                  ? "Matching answers are saved, but they are skipped or do not contribute to this protected skill estimate."
                                  : hasUnfilteredLabHistory
                                    ? "Saved answers for this ability exist, but the active dashboard filters exclude them."
                                    : "Complete practice that uses this ability to begin its evidence view.")
            )
            if !hasMatchingLabHistory && hasUnfilteredLabHistory && filters.hasRestrictions {
                Button("Clear filters") { filters = .unfiltered }
                    .buttonStyle(.borderedProminent)
                    .tint(NFTheme.controlTint(for: "indigo"))
                    .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .nfCard()
    }

    private var speedEvidenceCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: speedEvidence.status == .available ? "timer.circle.fill" : "timer")
                .font(.title2)
                .foregroundStyle(speedEvidence.status == .available ? NFTheme.cyanForeground : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(speedEvidence.status.title).font(.headline)
                if let median = speedEvidence.medianActiveSeconds {
                    Text("Typical time \(NFAppLocalization.formattedSeconds(median, style: .compact)) · \(NFAppLocalization.formattedAnswerCount(speedEvidence.eligibleCount))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(speedEvidence.status == .unavailableUntimed
                         ? "Untimed answers count toward accuracy, not speed."
                         : "These saved answers do not include the complete timing and task context needed for a speed estimate.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .nfCard()
    }

    @ViewBuilder
    private var transferGapCard: some View {
        let practice = creditMetric(for: [.practice])
        let transfer = creditMetric(for: [.nearTransfer, .appliedTransfer])
        if practice.count >= 3, transfer.count >= 3 {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.swap").foregroundStyle(NFTheme.amberForeground)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Results by practice type").font(.headline)
                    Text("Practice \(practice.credit.formatted(.percent.precision(.fractionLength(0)))) · Transfer tasks \(transfer.credit.formatted(.percent.precision(.fractionLength(0))))")
                        .font(.subheadline)
                    Text("These question sets may differ in difficulty and support. Their averages do not establish transfer of learning.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .nfCard()
        }
    }

    @ViewBuilder
    private var improvementEvidenceCard: some View {
        if let claim = improvementClaim {
            VStack(alignment: .leading, spacing: 9) {
                Label(claim.code.title, systemImage: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.headline)
                    .foregroundStyle(NFTheme.mintForeground)
                Text("Your recent results improved across two comparable practice periods.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Earlier \(claim.evidence.earlierCredit.formatted(.percent.precision(.fractionLength(0)))) · \(NFAppLocalization.formattedAnswerCount(claim.evidence.earlierCount))")
                    Image(systemName: "arrow.right")
                    Text("Later \(claim.evidence.laterCredit.formatted(.percent.precision(.fractionLength(0)))) · \(NFAppLocalization.formattedAnswerCount(claim.evidence.laterCount))")
                }
                .font(.caption.bold().monospacedDigit())
            }
            .nfCard()
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hourglass.circle.fill").foregroundStyle(NFTheme.amberForeground)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Not enough history yet").font(.headline)
                    Text("Keep practicing over time. NeuroForge will compare separated sessions under similar conditions.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .nfCard()
        }
    }

    @ViewBuilder
    private var evidenceChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Performance by practice type")
                        .font(.title2.bold())
                    Text("Accuracy over completed answers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                NFStatusPill(text: "Your results only", symbol: "person.crop.circle.badge.xmark", color: NFTheme.indigo)
            }

            if points.isEmpty {
                ContentUnavailableView(
                    hasMatchingLabHistory
                        ? "No scored chart data"
                        : hasUnfilteredLabHistory ? "No matching chart data" : "No answers yet",
                    systemImage: hasMatchingLabHistory
                        ? "chart.xyaxis.line"
                        : hasUnfilteredLabHistory ? "line.3.horizontal.decrease.circle" : "chart.xyaxis.line",
                    description: Text(hasMatchingLabHistory
                                      ? "Matching answers exist, but none contributes eligible scored evidence to this chart."
                                      : hasUnfilteredLabHistory
                                        ? "The active dashboard filters exclude this ability’s saved chart data."
                                        : "Complete low-stakes practice to begin this chart.")
                )
                .frame(minHeight: 220)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Answer", point.index),
                        y: .value("Accuracy", point.accuracy)
                    )
                    .foregroundStyle(by: .value("Practice type", point.series))
                    .symbol(by: .value("Practice type", point.series))
                    PointMark(
                        x: .value("Answer", point.index),
                        y: .value("Accuracy", point.accuracy)
                    )
                    .foregroundStyle(by: .value("Practice type", point.series))
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number, format: .percent.precision(.fractionLength(0)))
                            }
                        }
                    }
                }
                .chartXAxisLabel("Answer")
                .chartXSelection(value: $inspectedAnswerIndex)
                .frame(height: 280)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(EvidencePoint.accessibilitySummary(for: points))

                Text("Select a point to inspect the saved answers behind it.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(points.filter { $0.index == inspectedAnswerIndex }) { point in
                    NFProgressPointInspection(date: point.date, activity: point.series,
                        sampleCount: point.attemptIDs.count, value: point.accuracy,
                        onShowHistory: { navigation.progress.append(.chartHistory(Array(point.attemptIDs))) })
                }

                DisclosureGroup("View performance chart data") {
                    let page = min(chartDataPage, max(0, (points.count - 1) / 50))
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(points.dropFirst(page * 50).prefix(50))) { point in
                            Button {
                                navigation.progress.append(.chartHistory(Array(point.attemptIDs)))
                            } label: {
                                NFProgressChartDataRow(date: point.date, activity: point.series,
                                    sampleCount: point.index, value: point.accuracy)
                            }
                            .accessibilityHint("View matching history")
                        }
                        HStack {
                            Button("Previous page") { chartDataPage = max(0, page - 1) }
                                .disabled(page == 0)
                            Spacer()
                            Text("Page \(page + 1)").font(.caption)
                            Spacer()
                            Button("Next page") { chartDataPage = page + 1 }
                                .disabled((page + 1) * 50 >= points.count)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline)
            }
        }
        .nfCard()
    }

    private func metric(for evidenceClass: EvidenceClass) -> String {
        let metric = evidenceSnapshot.metric(for: [evidenceClass])
        guard metric.count > 0, let credit = metric.credit else {
            return NFAppLocalization.localized("No answers", locale: NFAppLocalization.preferredLocale, comment: "Progress metric status when no eligible answers exist.")
        }
        return NFAppLocalization.localized(
            "\(credit.formatted(.percent.precision(.fractionLength(0)))) · \(NFAppLocalization.formattedAnswerCount(metric.count))",
            locale: NFAppLocalization.preferredLocale,
            comment: "Practice metric with locale-formatted score and localized answer count."
        )
    }

    private func creditMetric(for classes: Set<EvidenceClass>) -> (credit: Double, count: Int) {
        let metric = evidenceSnapshot.metric(for: classes)
        return (metric.credit ?? 0, metric.count)
    }
}

private struct DetailMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(value)).font(.headline.monospacedDigit())
            Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nfCard(cornerRadius: 16, padding: 13)
        .accessibilityElement(children: .combine)
    }
}

private struct EvidenceCoverageRow: View {
    let label: String
    let detail: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(label)).font(.subheadline.weight(.semibold))
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NFProgressChartDataRow: View {
    let date: Date
    let activity: String
    let sampleCount: Int
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NFAppLocalization.formattedDate(date, date: .abbreviated, time: .omitted))
                .font(.caption).foregroundStyle(.secondary)
            Text(activity).font(.subheadline.weight(.semibold))
            HStack {
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .font(.body.monospacedDigit())
                Spacer(minLength: 12)
                Text(NFAppLocalization.formattedScoredAnswerCount(sampleCount))
                    .font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct NFProgressPointInspection: View {
    let date: Date
    let activity: String
    let sampleCount: Int
    let value: Double
    let onShowHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NFAppLocalization.formattedDate(date, date: .abbreviated, time: .omitted))
                .font(.caption).foregroundStyle(.secondary)
            Text(activity).font(.headline)
            Text(value, format: .percent.precision(.fractionLength(0)))
                .font(.title3.monospacedDigit())
            Text(NFAppLocalization.formattedScoredAnswerCount(sampleCount))
                .font(.subheadline)
            Button(action: onShowHistory) {
                Label("View matching history", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("progress-point-history")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

struct EvidencePoint: Identifiable {
    let id: UUID
    let index: Int
    let accuracy: Double
    let series: String
    let date: Date
    private let seriesAttemptIDs: [UUID]
    var attemptIDs: ArraySlice<UUID> { seriesAttemptIDs.prefix(index) }

    static func make(from observations: [AttemptDTO], attributedTo lab: TrainingLab? = nil,
                     at date: Date = Date()) -> [EvidencePoint] {
        let sorted = NFProgressEvidenceProjection.eligible(observations, at: date).filter { attempt in
            guard let lab else { return true }
            return NFAbilityEvidenceSnapshot.attributedWeight(of: attempt, to: lab) > 0
        }
        let classes: [(EvidenceClass, String)] = [
            (.practice, "Training"), (.nearTransfer, "Near transfer"), (.appliedTransfer, "Applied transfer"),
            (.retention, "Delayed retention"), (.assessmentHoldout, "Protected assessment")
        ]
        return classes.flatMap { evidenceClass, title in
            let matching = sorted.filter { $0.evidenceClass == evidenceClass }
            // All points share one immutable buffer; each stores only a prefix
            // boundary. Copying a growing IDs array here would be quadratic.
            let seriesIDs = matching.map(\.id)
            var scale = 0.0
            var earnedCredit = 0.0
            var availableEvidence = 0.0
            return matching.enumerated().compactMap { offset, attempt -> EvidencePoint? in
                if attempt.evidenceWeight > scale {
                    let adjustment = scale / attempt.evidenceWeight
                    earnedCredit *= adjustment
                    availableEvidence *= adjustment
                    scale = attempt.evidenceWeight
                }
                let attribution = lab.map { NFAbilityEvidenceSnapshot.attributedWeight(of: attempt, to: $0) } ?? 1
                let weight = (attempt.evidenceWeight / scale) * attribution
                earnedCredit += attempt.credit * weight
                availableEvidence += weight
                guard availableEvidence > 0, availableEvidence.isFinite, earnedCredit.isFinite else { return nil }
                return EvidencePoint(id: attempt.id, index: offset + 1, accuracy: earnedCredit / availableEvidence,
                    series: NFAppLocalization.localizedCatalogValue(title), date: attempt.submittedAt,
                    seriesAttemptIDs: seriesIDs)
            }
        }
    }

    static func accessibilitySummary(for points: [EvidencePoint]) -> String {
        guard let firstDate = points.map(\.date).min(),
              let lastDate = points.map(\.date).max() else {
            return NFAppLocalization.localized(
                "Performance-by-practice-type chart. No matching scored answers.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Nonvisual summary for an empty ability-performance chart."
            )
        }
        let series = Dictionary(grouping: points, by: \.series).keys.sorted().compactMap { name -> String? in
            guard let values = Dictionary(grouping: points, by: \.series)[name]?.sorted(by: { $0.date < $1.date }),
                  let first = values.first,
                  let last = values.last else { return nil }
            let change = last.accuracy - first.accuracy
            let comparison: String
            if values.count == 1 {
                comparison = NFAppLocalization.localized("one answer", locale: NFAppLocalization.preferredLocale, comment: "Ability-chart series summary with one answer.")
            } else if abs(change) < 0.005 {
                comparison = NFAppLocalization.localized("unchanged", locale: NFAppLocalization.preferredLocale, comment: "Chart trend with no meaningful change.")
            } else {
                let direction = change > 0
                    ? NFAppLocalization.localized("up", locale: NFAppLocalization.preferredLocale, comment: "Chart trend direction.")
                    : NFAppLocalization.localized("down", locale: NFAppLocalization.preferredLocale, comment: "Chart trend direction.")
                comparison = "\(direction) \(abs(change).formatted(.percent.precision(.fractionLength(0))))"
            }
            return NFAppLocalization.localized("\(name): \(last.accuracy.formatted(.percent.precision(.fractionLength(0)))) after \(NFAppLocalization.formattedAnswerCount(last.index)), \(comparison)",
                locale: NFAppLocalization.preferredLocale, comment: "Accessible cumulative series summary: practice type, value, count, descriptive change.")
        }
        return NFAppLocalization.localized(
            "Earned credit by practice type from \(NFAppLocalization.formattedDate(firstDate, date: .abbreviated, time: .omitted)) through \(NFAppLocalization.formattedDate(lastDate, date: .abbreviated, time: .omitted)). \(series.joined(separator: "; ")).",
            locale: NFAppLocalization.preferredLocale,
            comment: "Nonvisual ability-performance chart summary with dates, current values, and change."
        )
    }
}

enum NFAttemptHistoryResult: String, CaseIterable, Identifiable {
    case all
    case correct
    case partial
    case incorrect
    case skipped
    case revealed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: NFAppLocalization.localized("All results", locale: NFAppLocalization.preferredLocale, comment: "Answer-history result filter.")
        case .correct: NFAppLocalization.localized("Correct", locale: NFAppLocalization.preferredLocale, comment: "Answer-history result filter.")
        case .partial: NFAppLocalization.localized("Partial credit", locale: NFAppLocalization.preferredLocale, comment: "Answer-history result filter.")
        case .incorrect: NFAppLocalization.localized("Incorrect", locale: NFAppLocalization.preferredLocale, comment: "Answer-history result filter.")
        case .skipped: NFAppLocalization.localized("Skipped", locale: NFAppLocalization.preferredLocale, comment: "Answer-history result filter.")
        case .revealed: NFAppLocalization.localized("Solution viewed — no score", locale: NFAppLocalization.preferredLocale, comment: "Answer-history result for an explicitly revealed solution.")
        }
    }
}

enum NFAttemptHistorySupport: String, CaseIterable, Identifiable {
    case all
    case independent
    case supported

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: NFAppLocalization.localized("All support levels", locale: NFAppLocalization.preferredLocale, comment: "Answer-history support filter.")
        case .independent: NFAppLocalization.localized("Independent", locale: NFAppLocalization.preferredLocale, comment: "Answer-history support filter.")
        case .supported: NFAppLocalization.localized("Support used", locale: NFAppLocalization.preferredLocale, comment: "Answer-history support filter.")
        }
    }
}

enum NFAttemptHistoryConfidence: String, CaseIterable, Identifiable {
    case all
    case guessing
    case uncertain
    case fairlyConfident
    case certain
    case notRecorded

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: NFAppLocalization.localized("All confidence levels", locale: NFAppLocalization.preferredLocale, comment: "Answer-history confidence filter.")
        case .guessing: ConfidenceLevel.guessing.title
        case .uncertain: ConfidenceLevel.uncertain.title
        case .fairlyConfident: ConfidenceLevel.fairlyConfident.title
        case .certain: ConfidenceLevel.certain.title
        case .notRecorded: NFAppLocalization.localized("Not recorded", locale: NFAppLocalization.preferredLocale, comment: "Answer-history confidence filter for responses without confidence data.")
        }
    }
}

enum NFAttemptHistorySource: String, CaseIterable, Identifiable {
    case all
    case appPractice
    case personal
    case protectedAssessment

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: NFAppLocalization.localized("All sources", locale: NFAppLocalization.preferredLocale, comment: "Answer-history source filter.")
        case .appPractice: NFAppLocalization.localized("NeuroForge practice", locale: NFAppLocalization.preferredLocale, comment: "Answer-history source category.")
        case .personal: NFAppLocalization.localized("Personal practice", locale: NFAppLocalization.preferredLocale, comment: "Answer-history source category for generated or imported-source work.")
        case .protectedAssessment: NFAppLocalization.localized("Protected skill checks", locale: NFAppLocalization.preferredLocale, comment: "Answer-history source category.")
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .appPractice: "app.badge"
        case .personal: "lock.doc.fill"
        case .protectedAssessment: "lock.shield.fill"
        }
    }
}

/// A read-only amendment to an immutable historical result. Dismissed notices
/// are deliberately not an input: acknowledging a notice cannot erase a repair.
struct NFHistoryCorrectionPresentation: Equatable {
    let correctedCredit: Double?
    let excludesAccuracy: Bool
    let isSelfReported: Bool
    let excludedScopes: Set<NFHistoricalCorrectionScope>
    let confirmedAssistance: Bool
    let reasons: [String]

    static func make(attemptID: UUID, dispositions: [NFHistoricalPracticeDispositionRecord],
                     corrections: [NFHistoricalContentCorrectionRecommendation], activeIDs: [String]?) -> Self? {
        let identity = attemptID.uuidString
        let candidates = dispositions.filter { $0.attemptID == identity && $0.policyVersion == NFHistoricalPracticeProjection.policyVersion }
            .sorted {
                if $0.revision != $1.revision { return $0.revision < $1.revision }
                if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
                return $0.id < $1.id
            }
        var latest: NFHistoricalPracticeDispositionRecord?
        var seen: Set<String> = []
        for candidate in candidates where seen.insert(candidate.id).inserted {
            guard candidate.supersedesDispositionID == latest?.id else { continue }
            latest = candidate
        }
        let active = corrections.filter { record in
            record.originalAttemptID == identity && record.policyVersion == NFContentCorrectionPolicy.historicalPolicyVersion
                && (activeIDs.map { $0.contains(record.id) } ?? true)
                && record.disposition != .quarantineForReview && record.disposition != .legacyUncalibrated
        }
        let scopes = Set(active.flatMap(\.excludedScopes))
        let selfReported = latest?.disposition == .personalStudy || active.contains { $0.disposition == .selfReported }
        let excluded = scopes.contains(.accuracy) || selfReported
            || latest.map { [.excludedContentCorrection, .excludedInvalidScore].contains($0.disposition) } == true
        let credits = Set(active.compactMap(\.correctedCredit).filter { $0.isFinite && (0...1).contains($0) })
        let retainedCredit = latest.flatMap(\.correctedDerivedCredit).flatMap { $0.isFinite && (0...1).contains($0) ? $0 : nil }
        let correctedCredit = excluded || credits.count > 1 ? nil : (retainedCredit ?? (credits.count == 1 ? credits.first : nil))
        var reasons: [String] = []
        if let latest, latest.disposition != .editorialEvidence, !latest.reason.isEmpty { reasons.append(latest.reason) }
        for record in active where !record.rationale.isEmpty && !reasons.contains(record.rationale) { reasons.append(record.rationale) }
        guard excluded || correctedCredit != nil || !scopes.isEmpty else { return nil }
        return Self(correctedCredit: correctedCredit, excludesAccuracy: excluded || credits.count > 1,
            isSelfReported: selfReported, excludedScopes: scopes,
            confirmedAssistance: active.contains { $0.disposition == .assistedEvidence }, reasons: reasons)
    }
}

/// Immutable, read-only copy of the durable answer fields already exposed by
/// AppStore. Review UI never regenerates or re-scores an attempt.
struct NFReadOnlyAttemptSnapshot: Identifiable {
    let id: UUID
    let sessionID: UUID
    let lab: TrainingLab
    let submittedAt: Date
    let prompt: String
    let response: String
    let rawResponse: String
    private let requiresTypedResponse: Bool
    let selfCheckRating: NFSelfCheckRating?
    private let recordedCorrectAnswer: String
    let result: NFAttemptHistoryResult
    let deterministicCredit: Double
    let wasTimed: Bool
    let activeDurationSeconds: Double
    let hintCount: Int
    let accommodationCount: Int
    let confidence: ConfidenceLevel?
    private let recordedSource: NFAttemptHistorySource
    let evidenceClass: EvidenceClass
    let templateID: String
    let scoringVersion: Int
    let validationVersion: Int
    let inputMode: String
    let sessionSource: SessionSource?
    private(set) var correction: NFHistoryCorrectionPresentation? = nil
    private var protectedSnapshot = false
    var source: NFAttemptHistorySource { protectedSnapshot ? .protectedAssessment : recordedSource }
    var correctAnswer: String { source == .protectedAssessment ? "" : recordedCorrectAnswer }

    init(attempt: AttemptRecord) {
        id = attempt.id
        sessionID = attempt.sessionID
        lab = TrainingLab(rawValue: attempt.gameID) ?? .mentalMath
        submittedAt = attempt.submittedAt
        prompt = attempt.prompt
        rawResponse = attempt.response
        requiresTypedResponse = attempt.scoringVersion >= 8 && ["numeric", "singleChoice", "multipleChoice",
            "orderedSteps", "shortText", "selfCheck", "claimEvidence", "logicState"].contains(attempt.responseFormatRaw)
        let protectedReceipt = [EvidenceClass.assessmentHoldout.rawValue, EvidenceClass.nearTransfer.rawValue].contains(attempt.evidenceClassRaw)
            || attempt.assessmentBlockRaw != nil || attempt.errorCode == "protected_evaluator_unavailable"
            || attempt.sessionSourceRaw == SessionSource.baseline.rawValue
            || attempt.sessionSourceRaw == SessionSource.reassessment.rawValue
        response = NFResponsePresentation.text(attempt.response, requiresTypedEnvelope: requiresTypedResponse)
        if !protectedReceipt, case .selfCheck(let submission) = NFResponsePresentation.decode(attempt.response) {
            selfCheckRating = submission.rating
        } else { selfCheckRating = nil }
        recordedCorrectAnswer = protectedReceipt ? "" : attempt.correctAnswerText
        deterministicCredit = min(1, max(0, attempt.deterministicCredit))
        if protectedReceipt || selfCheckRating != nil {
            // No objective result is available to disclose or use in Correct/Wrong filters.
            result = .all
        } else if attempt.responseFormatRaw == "revealed" || attempt.errorCode == "solution_revealed" {
            result = .revealed
        } else if attempt.wasSkipped {
            result = .skipped
        } else if attempt.isCorrect || deterministicCredit >= 0.999 {
            result = .correct
        } else if deterministicCredit > 0 {
            result = .partial
        } else {
            result = .incorrect
        }
        wasTimed = attempt.wasTimed
        activeDurationSeconds = max(0, attempt.activeDurationSeconds)
        hintCount = max(0, attempt.hintCount)
        accommodationCount = attempt.accommodationFlagsRaw
            .split(separator: ",")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        confidence = attempt.confidenceRaw.flatMap(ConfidenceLevel.init(rawValue:))
        evidenceClass = EvidenceClass(rawValue: attempt.evidenceClassRaw) ?? .practice
        if protectedReceipt {
            recordedSource = .protectedAssessment
        } else if evidenceClass == .documentPractice
                    || attempt.generationID != nil
                    || !attempt.sourceDocumentIDsRaw.isEmpty {
            recordedSource = .personal
        } else {
            recordedSource = .appPractice
        }
        templateID = attempt.templateID
        scoringVersion = max(0, attempt.scoringVersion)
        validationVersion = max(0, attempt.validationVersion)
        inputMode = NFInputModality.title(forPersistedValue: attempt.inputModeRaw)
        sessionSource = SessionSource(rawValue: attempt.sessionSourceRaw)
    }

    var resultTitle: String {
        if source == .protectedAssessment { return NFAppLocalization.localizedCatalogValue("Answer saved", locale: NFAppLocalization.preferredLocale) }
        if let selfCheckRating { return NFResponsePresentation.ratingTitle(selfCheckRating) }
        if correction?.isSelfReported == true { return NFAppLocalization.localizedCatalogValue("Self-check saved", locale: NFAppLocalization.preferredLocale) }
        if correction?.excludesAccuracy == true { return NFAppLocalization.localizedCatalogValue("Excluded from accuracy", locale: NFAppLocalization.preferredLocale) }
        return effectiveResult.title
    }

    var originalResultTitle: String {
        if source == .protectedAssessment { return NFAppLocalization.localizedCatalogValue("Answer saved", locale: NFAppLocalization.preferredLocale) }
        if let selfCheckRating { return NFResponsePresentation.ratingTitle(selfCheckRating) }
        return result.title
    }

    var effectiveResult: NFAttemptHistoryResult {
        guard source != .protectedAssessment, selfCheckRating == nil else { return .all }
        if correction?.excludesAccuracy == true { return .all }
        guard let credit = correction?.correctedCredit else { return result }
        return credit >= 1 ? .correct : (credit > 0 ? .partial : .incorrect)
    }
    var effectiveCredit: Double { correction?.correctedCredit ?? deterministicCredit }
    var hasDisputedKey: Bool { correction?.excludesAccuracy == true && correction?.isSelfReported != true }
    var effectiveWasTimed: Bool { wasTimed && correction?.excludedScopes.contains(.cleanSpeed) != true }

    func applyingHistoricalCorrections(dispositions: [NFHistoricalPracticeDispositionRecord],
                                      corrections: [NFHistoricalContentCorrectionRecommendation], activeIDs: [String]?,
                                      protectedSnapshot: Bool = false) -> Self {
        var copy = self
        copy.protectedSnapshot = self.protectedSnapshot || protectedSnapshot
        // Protection is checked before any correction text/key or derived result
        // is constructed for a user-facing or accessibility presentation.
        copy.correction = copy.source == .protectedAssessment ? nil : NFHistoryCorrectionPresentation.make(
            attemptID: id, dispositions: dispositions, corrections: corrections, activeIDs: activeIDs)
        return copy
    }

    func readableResponse(exercise: NFExercise?) -> String {
        NFResponsePresentation.text(rawResponse,
            exercise: source == .protectedAssessment || exercise?.assessmentProtected == true ? nil : exercise,
            requiresTypedEnvelope: requiresTypedResponse)
    }

    func reviewExplanation(exercise: NFExercise?) -> String {
        guard source != .protectedAssessment, exercise?.assessmentProtected != true else {
            return NFAppLocalization.localizedCatalogValue("Your results appear after this block. Practice this skill with a fresh question.", locale: NFAppLocalization.preferredLocale)
        }
        if let selfCheckRating { return NFResponsePresentation.ratingTitle(selfCheckRating) }
        if correction?.isSelfReported == true { return resultTitle }
        if let exercise {
            // An invalidated key has no newly endorsed explanation. The view
            // labels this exact historical text as disputed before showing it.
            let outcome = hasDisputedKey ? result : effectiveResult
            return outcome == .correct ? exercise.feedback.correctExplanation : exercise.feedback.retryExplanation
        }
        return NFAppLocalization.localizedCatalogValue("The original teaching explanation is unavailable in this older answer.", locale: NFAppLocalization.preferredLocale)
    }

    var timingTitle: String {
        if correction?.excludedScopes.contains(.cleanSpeed) == true {
            return NFAppLocalization.localizedCatalogValue("Timing evidence unavailable", locale: NFAppLocalization.preferredLocale)
        }
        return originalTimingTitle
    }

    var originalTimingTitle: String {
        let duration = NFAppLocalization.formattedSeconds(activeDurationSeconds)
        return wasTimed
            ? NFAppLocalization.localized("Timed · \(duration)", locale: NFAppLocalization.preferredLocale, comment: "Answer-history timing value.")
            : NFAppLocalization.localized("Untimed · \(duration) active", locale: NFAppLocalization.preferredLocale, comment: "Answer-history timing value.")
    }

    var supportTitle: String {
        if correction?.confirmedAssistance == true {
            return NFAppLocalization.localizedCatalogValue("Assisted practice", locale: NFAppLocalization.preferredLocale)
        }
        if correction?.excludedScopes.contains(.independentEvidence) == true || correction?.excludesAccuracy == true {
            return NFAppLocalization.localizedCatalogValue("Independent evidence unavailable", locale: NFAppLocalization.preferredLocale)
        }
        if result == .revealed {
            return NFAppLocalization.localizedCatalogValue("Solution viewed", locale: NFAppLocalization.preferredLocale)
        }
        if hintCount == 0 && accommodationCount == 0 {
            return NFAppLocalization.localized("Independent", locale: NFAppLocalization.preferredLocale, comment: "Answer-history support level.")
        }
        if hintCount > 0 && accommodationCount > 0 {
            return NFAppLocalization.localized(
                "\(NFAppLocalization.formattedHintCount(hintCount)) · accessibility support",
                locale: NFAppLocalization.preferredLocale,
                comment: "Answer-history support summary with a localized hint count."
            )
        }
        if hintCount > 0 {
            return NFAppLocalization.formattedHintCount(hintCount)
        }
        return NFAppLocalization.localized("Accessibility support", locale: NFAppLocalization.preferredLocale, comment: "Answer-history support level without exposing private setting identifiers.")
    }

    var usedSupport: Bool { result == .revealed || hintCount > 0 || accommodationCount > 0 || correction?.confirmedAssistance == true
        || correction?.excludedScopes.contains(.independentEvidence) == true || correction?.excludesAccuracy == true }

    var hasObjectiveResult: Bool { effectiveResult == .correct || effectiveResult == .partial || effectiveResult == .incorrect }

    var confidenceTitle: String {
        confidence?.title
            ?? NFAppLocalization.localized("Not recorded", locale: NFAppLocalization.preferredLocale, comment: "Answer-history confidence value when missing.")
    }

    var activityTitle: String {
        let sourceTitle: String = switch sessionSource {
        case .today: NFAppLocalization.localized("Daily circuit", locale: NFAppLocalization.preferredLocale, comment: "Answer-history activity source.")
        case .focused: NFAppLocalization.localized("Focused practice", locale: NFAppLocalization.preferredLocale, comment: "Answer-history activity source.")
        case .baseline: NFAppLocalization.localized("Starting skill check", locale: NFAppLocalization.preferredLocale, comment: "Answer-history activity source.")
        case .reassessment: NFAppLocalization.localized("Reassessment", locale: NFAppLocalization.preferredLocale, comment: "Answer-history activity source.")
        case .weeklyMission: NFAppLocalization.localized("Weekly mission", locale: NFAppLocalization.preferredLocale, comment: "Answer-history activity source.")
        case nil: NFAppLocalization.localized("Saved activity", locale: NFAppLocalization.preferredLocale, comment: "Answer-history activity source when unavailable.")
        }
        return "\(lab.shortTitle) · \(sourceTitle)"
    }

    var contentVersionTitle: String {
        let promptVersion = Self.promptVersionTitle(for: templateID)
        return NFAppLocalization.localized(
            "\(promptVersion) · scorer \(scoringVersion) · validator \(validationVersion)",
            locale: NFAppLocalization.preferredLocale,
            comment: "Answer-history content-version summary."
        )
    }

    static func promptVersionTitle(
        for templateID: String,
        locale: Locale = NFAppLocalization.preferredLocale
    ) -> String {
        let components = templateID.split { character in
            character == "." || character == "-" || character == "_"
        }
        if let version = components.compactMap({ component -> Int? in
            guard component.first == "v", component.count > 1 else { return nil }
            return Int(component.dropFirst())
        }).first {
            return NFAppLocalization.localized(
                "Prompt template version \(version)",
                locale: locale,
                comment: "Sanitized saved prompt-template version shown without exposing its internal identifier."
            )
        }
        return NFAppLocalization.localized(
            "Saved prompt copy",
            locale: locale,
            comment: "Saved-answer version fallback when no safe public template version can be derived."
        )
    }

    var privacyNote: String {
        switch source {
        case .personal:
            NFAppLocalization.localized(
                "Personal-source identifiers and filenames stay hidden here. The exact saved prompt and your response remain visible only in your private history.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Privacy note for personal answer history."
            )
        case .protectedAssessment:
            NFAppLocalization.localized(
                "The saved prompt and your response are shown, but the protected answer key stays hidden so a future skill check remains valid.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Privacy and validity note for protected assessment history."
            )
        case .appPractice, .all:
            NFAppLocalization.localized(
                "This review is read-only and uses the exact prompt and response saved when scoring occurred.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Integrity note for standard answer history."
            )
        }
    }

    var explanation: String {
        if source == .protectedAssessment {
            return NFAppLocalization.localized(
                "Your results appear after this block. Practice this skill with a fresh question.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Answer-history explanation for protected assessment content."
            )
        }
        if let correction { return correction.reasons.joined(separator: "\n\n") }
        let key = correctAnswer.isEmpty
            ? NFAppLocalization.localized("No additional saved answer key is available for this content version.", locale: NFAppLocalization.preferredLocale, comment: "Answer-history explanation when no saved key exists.")
            : NFAppLocalization.localized("Saved scoring key: \(correctAnswer)", locale: NFAppLocalization.preferredLocale, comment: "Answer-history explanation containing the exact saved scoring key.")
        return NFAppLocalization.localized(
            "The durable scorer recorded this response as \(resultTitle.lowercased()) with \(deterministicCredit.formatted(.percent.precision(.fractionLength(0)))) earned credit. \(key)",
            locale: NFAppLocalization.preferredLocale,
            comment: "Read-only answer-history scoring explanation based only on durable attempt fields."
        )
    }
}

extension AppStore {
    func historyPresentation(for original: NFReadOnlyAttemptSnapshot) -> NFReadOnlyAttemptSnapshot {
        _ = localSessionRevision
        return original.applyingHistoricalCorrections(dispositions: evidenceDispositions,
            corrections: localSessions.archive.contentCorrections ?? [],
            activeIDs: localSessions.archive.activeContentCorrectionIDs?[original.id.uuidString],
            protectedSnapshot: localSessions.archive.snapshots.first { $0.attemptID == original.id }?.exercise.assessmentProtected == true
                || localSessions.archive.unavailableHistorySnapshots?.contains(where: {
                    $0.attemptID == original.id && $0.reason == .protectedContent
                }) == true || localSessions.archive.withheldProtectedConflictAttemptIDs?.contains(original.id) == true)
    }
}

struct NFAttemptHistoryView: View {
    @Environment(AppStore.self) private var store
    let attempts: [NFReadOnlyAttemptSnapshot]
    let title: String
    let subtitle: String

    @State private var searchText = ""
    @State private var period = NFProgressPeriod.allTime
    @State private var activity: TrainingLab?
    @State private var result = NFAttemptHistoryResult.all
    @State private var timing = NFProgressTimingFilter.all
    @State private var support = NFAttemptHistorySupport.all
    @State private var confidence = NFAttemptHistoryConfidence.all
    @State private var source = NFAttemptHistorySource.all
    @State private var showsFilters = true

    init(attempts: [AttemptRecord], title: String, subtitle: String) {
        self.attempts = attempts.map(NFReadOnlyAttemptSnapshot.init(attempt:))
            .sorted { lhs, rhs in
                lhs.submittedAt == rhs.submittedAt
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : lhs.submittedAt > rhs.submittedAt
            }
        self.title = title
        self.subtitle = subtitle
    }

    init(attempts: [NFReadOnlyAttemptSnapshot], title: String, subtitle: String) {
        self.attempts = attempts.sorted { lhs, rhs in
            lhs.submittedAt == rhs.submittedAt
                ? lhs.id.uuidString < rhs.id.uuidString
                : lhs.submittedAt > rhs.submittedAt
        }
        self.title = title
        self.subtitle = subtitle
    }

    private var filteredAttempts: [NFReadOnlyAttemptSnapshot] {
        attempts.map { store.historyPresentation(for: $0) }.filter { attempt in
            if let cutoff = period.cutoff, attempt.submittedAt < cutoff { return false }
            if let activity, attempt.lab != activity { return false }
            if result != .all, attempt.effectiveResult != result { return false }
            switch timing {
            case .all: break
            case .timed where !attempt.effectiveWasTimed: return false
            case .untimed where attempt.effectiveWasTimed: return false
            default: break
            }
            switch support {
            case .all: break
            case .independent where attempt.usedSupport: return false
            case .supported where !attempt.usedSupport: return false
            default: break
            }
            switch confidence {
            case .all: break
            case .guessing where attempt.confidence != .guessing: return false
            case .uncertain where attempt.confidence != .uncertain: return false
            case .fairlyConfident where attempt.confidence != .fairlyConfident: return false
            case .certain where attempt.confidence != .certain: return false
            case .notRecorded where attempt.confidence != nil: return false
            default: break
            }
            if source != .all, attempt.source != source { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty,
               !attempt.prompt.localizedCaseInsensitiveContains(query),
               !attempt.readableResponse(exercise: attempt.source == .protectedAssessment ? nil : store.exerciseSnapshot(for: attempt.id)).localizedCaseInsensitiveContains(query) {
                return false
            }
            return true
        }
    }

    private var activityOptions: [TrainingLab] {
        Array(Set(attempts.map(\.lab))).sorted { $0.rawValue < $1.rawValue }
    }

    private var hasActiveFilters: Bool {
        period != .allTime || activity != nil || result != .all || timing != .all
            || support != .all || confidence != .all || source != .all || !searchText.isEmpty
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    NFSectionHeader(title, eyebrow: "READ-ONLY HISTORY", subtitle: subtitle)

                    Label(
                        "Personal filenames and source identifiers are never shown. Protected answer keys remain hidden.",
                        systemImage: "lock.shield.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .nfCard(cornerRadius: 16, padding: 12)
                    .accessibilityElement(children: .combine)

                    DisclosureGroup(isExpanded: $showsFilters) {
                        historyFilters
                            .padding(.top, 12)
                    } label: {
                        HStack {
                            Label("Filter answer history", systemImage: "line.3.horizontal.decrease.circle")
                                .font(.headline)
                            Spacer(minLength: 0)
                            Text(NFAppLocalization.localized(
                                "\(NFAppLocalization.formattedAnswerCount(filteredAttempts.count)) of \(NFAppLocalization.formattedAnswerCount(attempts.count)) shown",
                                locale: NFAppLocalization.preferredLocale,
                                comment: "Filtered answer-history visible and total counts."
                            ))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .nfCard(cornerRadius: 18, padding: 16)

                    if attempts.isEmpty {
                        ContentUnavailableView(
                            "No saved answers",
                            systemImage: "list.bullet.rectangle.portrait",
                            description: Text("Completed answers for this view will appear here without changing their saved content.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else if filteredAttempts.isEmpty {
                        VStack(spacing: 12) {
                            ContentUnavailableView(
                                "No answers match",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text("Your saved answers are intact. Change or clear the history filters.")
                            )
                            Button("Clear history filters") { clearFilters() }
                                .buttonStyle(.borderedProminent)
                                .tint(NFTheme.controlTint(for: "indigo"))
                                .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                        }
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        ForEach(filteredAttempts) { attempt in
                            NavigationLink(value: NFProgressRoute.attempt(attempt.id)) {
                                NFAttemptHistoryRow(attempt: attempt)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Answer history")
        .navigationDestination(for: NFProgressRoute.self) { route in
            NFProgressRouteView(route: route, filters: .constant(NFProgressFilters()))
        }
        .searchable(text: $searchText, prompt: "Search saved prompts and answers")
    }

    private var historyFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 10)], spacing: 10) {
                Picker("Date", selection: $period) {
                    ForEach(NFProgressPeriod.allCases) { value in Text(value.title).tag(value) }
                }
                Picker("Activity", selection: $activity) {
                    Text("All activities").tag(nil as TrainingLab?)
                    ForEach(activityOptions) { lab in Text(lab.shortTitle).tag(Optional(lab)) }
                }
                Picker("Result", selection: $result) {
                    ForEach(NFAttemptHistoryResult.allCases) { value in Text(value.title).tag(value) }
                }
                Picker("Timing", selection: $timing) {
                    ForEach(NFProgressTimingFilter.allCases) { value in Text(value.title).tag(value) }
                }
                Picker("Support", selection: $support) {
                    ForEach(NFAttemptHistorySupport.allCases) { value in Text(value.title).tag(value) }
                }
                Picker("Confidence", selection: $confidence) {
                    ForEach(NFAttemptHistoryConfidence.allCases) { value in Text(value.title).tag(value) }
                }
                Picker("Source privacy", selection: $source) {
                    ForEach(NFAttemptHistorySource.allCases) { value in Text(value.title).tag(value) }
                }
            }
            .pickerStyle(.menu)

            if hasActiveFilters {
                Button("Clear history filters") { clearFilters() }
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private func clearFilters() {
        period = .allTime
        activity = nil
        result = .all
        timing = .all
        support = .all
        confidence = .all
        source = .all
        searchText = ""
    }
}

private struct NFAttemptHistoryRow: View {
    @Environment(AppStore.self) private var store
    let attempt: NFReadOnlyAttemptSnapshot
    private var presented: NFReadOnlyAttemptSnapshot { store.historyPresentation(for: attempt) }
    private var permittedExercise: NFExercise? {
        guard presented.source != .protectedAssessment else { return nil }
        return store.exerciseSnapshot(for: presented.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(NFAppLocalization.formattedDate(presented.submittedAt, date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.semibold))
                Text(presented.activityTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Label(presented.source.title, systemImage: presented.source.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(presented.source == .personal ? NFTheme.amberForeground : NFTheme.indigoForeground)
            }

            Text(presented.prompt.isEmpty ? "Prompt unavailable in this saved version" : presented.prompt)
                .font(.headline)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Text(presented.readableResponse(exercise: permittedExercise))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { metadata }
                VStack(alignment: .leading, spacing: 5) { metadata }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nfCard(cornerRadius: 18, padding: 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the immutable saved answer review.")
    }

    @ViewBuilder
    private var metadata: some View {
        Text(presented.resultTitle).foregroundStyle(resultColor)
        Text(presented.timingTitle)
        Text(presented.supportTitle)
        Text("Confidence: \(presented.confidenceTitle)")
    }

    private var resultColor: Color {
        if presented.source == .protectedAssessment || presented.selfCheckRating != nil { return .secondary }
        return switch presented.effectiveResult {
        case .correct: NFTheme.mintForeground
        case .partial: NFTheme.amberForeground
        case .incorrect: NFTheme.roseForeground
        case .skipped, .revealed, .all: .secondary
        }
    }
}

struct NFAttemptReviewDetailView: View {
    @Environment(AppStore.self) private var store
    let attempt: NFReadOnlyAttemptSnapshot
    private var presented: NFReadOnlyAttemptSnapshot { store.historyPresentation(for: attempt) }
    private var permittedExercise: NFExercise? {
        guard presented.source != .protectedAssessment else { return nil }
        return store.exerciseSnapshot(for: presented.id)
    }
    private var savedTransferRelationship: NFTransferRelationshipDraft? {
        NFTransferRelationshipHistoryProjection.make(exercise: permittedExercise,
            draft: store.localSessions.archive.snapshots.first(where: { $0.attemptID == presented.id })?.transferRelationship,
            isProtected: presented.source == .protectedAssessment)?.draft
    }
    private var savedScienceStudy: NFScienceStudyDraft? {
        NFScienceStudyHistoryProjection.make(exercise: permittedExercise,
            draft: store.localSessions.archive.snapshots.first(where: { $0.attemptID == presented.id })?.scienceStudy,
            isProtected: presented.source == .protectedAssessment)?.draft
    }
    private var savedDataInspection: NFDataInspectionHistoryProjection? {
        guard presented.source != .protectedAssessment else { return nil }
        return NFDataInspectionHistoryProjection.make(exercise: permittedExercise,
            draft: store.localSessions.archive.snapshots.first { $0.attemptID == presented.id }?.dataInspection,
            isProtected: presented.source == .protectedAssessment)
    }
    private var hasUnavailableDataInspection: Bool {
        guard presented.source != .protectedAssessment else { return false }
        return store.localSessions.archive.snapshots.first { $0.attemptID == presented.id }?.dataInspection != nil
            && savedDataInspection == nil
    }
    private var hasUnavailableTrace: Bool {
        guard presented.source != .protectedAssessment else { return false }
        return store.localSessions.archive.snapshots.first { $0.attemptID == presented.id }?.traceInspection != nil && savedTrace == nil
    }
    private var savedLadderHintCount: Int? {
        guard !hasUnavailableDataInspection, !hasUnavailableMathWorking, !hasUnavailableTrace else { return nil }
        return max(0, presented.hintCount - (savedTrace == nil ? 0 : 1) - (savedDataInspection?.draft.supportCount ?? 0))
    }
    private var hasUnavailableMathWorking: Bool {
        guard presented.source != .protectedAssessment, let exercise = permittedExercise,
              let work = store.localSessions.archive.snapshots.first(where: { $0.attemptID == presented.id })?.mathWork else { return false }
        return !work.isCompatible(with: exercise)
    }
    private var savedMathWork: NFMathWorkDraft? {
        guard presented.source != .protectedAssessment, let exercise = permittedExercise,
              let work = store.localSessions.archive.snapshots.first(where: { $0.attemptID == presented.id })?.mathWork,
              work.isCompatible(with: exercise) else { return nil }
        return work
    }
    private var snapshotUnavailableReason: String? {
        guard presented.source != .protectedAssessment else { return nil }
        return store.historySnapshotUnavailableReason(for: presented.id)
    }
    private var savedTrace: NFTraceInspectionDraft? {
        guard let exercise = permittedExercise,
              let value = store.localSessions.archive.snapshots.first(where: { $0.attemptID == presented.id })?.traceInspection,
              value.isValid(for: exercise) else { return nil }
        return value
    }
    @State private var showsReport = false
    private var savedExpectedAnswer: String? {
        guard presented.source != .protectedAssessment else { return nil }
        if let exercise = permittedExercise { return NFResponsePresentation.expectedAnswer(for: exercise) }
        return presented.correctAnswer.isEmpty ? nil : presented.correctAnswer
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NFSectionHeader(
                        "Saved answer",
                        eyebrow: "READ-ONLY",
                        subtitle: NFAppLocalization.formattedDate(presented.submittedAt, date: .complete, time: .shortened)
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        if let original = store.attempts.first(where: { $0.id == presented.id }),
                           let scope = store.generatedRunSummary(sessionID: original.sessionID) {
                            Text(scope).font(.subheadline).foregroundStyle(.secondary)
                        }
                        LabeledContent("Activity", value: presented.activityTitle)
                        LabeledContent("Result", value: presented.resultTitle)
                        if presented.hasObjectiveResult {
                            LabeledContent("Earned credit", value: presented.effectiveCredit.formatted(.percent.precision(.fractionLength(0))))
                        }
                        LabeledContent("Timing", value: presented.timingTitle)
                        LabeledContent("Support", value: presented.supportTitle)
                        LabeledContent("Confidence", value: presented.confidenceTitle)
                        LabeledContent("Input", value: presented.inputMode)

                    }
                    .nfCard()

                    if presented.source != .protectedAssessment, let correction = presented.correction {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Result correction", systemImage: "info.circle").font(.headline)
                            LabeledContent("Original result", value: presented.originalResultTitle)
                            if presented.selfCheckRating == nil && !correction.isSelfReported {
                                LabeledContent("Original credit", value: presented.deterministicCredit.formatted(.percent.precision(.fractionLength(0))))
                            }
                            ForEach(correction.reasons, id: \.self) { reason in
                                Text(LocalizedStringKey(reason)).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                        .nfCard()
                    }

                    if let reason = snapshotUnavailableReason {
                        Label {
                            Text(verbatim: NFAppLocalization.localizedCatalogValue(reason, locale: NFAppLocalization.preferredLocale))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .foregroundStyle(.secondary)
                        .nfCard()
                        .accessibilityIdentifier("history-snapshot-unavailable")
                    }

                    reviewTextCard(title: "Prompt — exact saved text", text: presented.prompt, symbol: "questionmark.bubble.fill")
                    if presented.source != .protectedAssessment, let exercise = permittedExercise, !exercise.assessmentProtected {
                        NFHistoryStimulusView(exercise: exercise, attemptID: presented.id, sessionID: presented.sessionID)
                    }
                    reviewTextCard(title: "Your saved answer", text: presented.readableResponse(exercise: permittedExercise), symbol: "text.bubble.fill")
                    if let saved = savedTransferRelationship, let exercise = permittedExercise {
                        NFTransferSavedRelationshipView(exercise: exercise, draft: saved).nfCard()
                        NFTransferRelationshipDebriefView(exercise: exercise)
                    }
                    if let graph = NFGraphConstructionHistoryProjection.make(exercise: permittedExercise,
                        response: NFResponsePresentation.decode(presented.rawResponse), isProtected: presented.source == .protectedAssessment) {
                        NFGraphConstructionFeedbackView(projection: graph, showsPlot: true)
                    }
                    if let saved = savedScienceStudy, let exercise = permittedExercise {
                        NFScienceSavedEvidenceView(exercise: exercise, draft: saved).nfCard()
                        if let response = try? JSONDecoder().decode(NFExerciseResponse.self, from: Data(presented.rawResponse.utf8)) {
                            NFScienceStudyFeedbackView(exercise: exercise, response: response)
                        }
                    }
                    if let inspection = savedDataInspection {
                        VStack(alignment: .leading, spacing: 12) {
                            if let prediction = inspection.draft.firstPrediction {
                                LabeledContent("Prediction saved before explanation (%)", value: prediction.value)
                            } else if !inspection.draft.predictionText.isEmpty {
                                LabeledContent("Your prediction draft (%)", value: inspection.draft.predictionText)
                            }
                            if let point = inspection.explanation.data.inspect(id: inspection.draft.selectedPointID) {
                                LabeledContent("Saved displayed outcome", value: point.label)
                                Text("\(point.originalValue) observations")
                            }
                            NFDataDenominatorExplanationView(explanation: inspection.explanation)
                            if inspection.draft.overlayRevealed {
                                Text("Denominator explanation used").font(.caption).foregroundStyle(.secondary)
                            }
                        }.nfCard().accessibilityIdentifier("history-original-data-prediction")
                    } else if hasUnavailableDataInspection {
                        Text("Saved data inspection is unavailable in this version. Your original answer remains saved.")
                            .foregroundStyle(.secondary).accessibilityIdentifier("history-data-inspection-unavailable")
                    }
                    if hasUnavailableMathWorking {
                        Text("Saved calculation working is unavailable in this version. The original answer remains saved.")
                            .foregroundStyle(.secondary).accessibilityIdentifier("history-math-working-unavailable")
                    }
                    if let work = savedMathWork {
                        VStack(alignment: .leading, spacing: 10) {
                            if let estimate = work.lockedEstimate {
                                LabeledContent("Estimate saved before exact work", value: estimate)
                            }
                            ForEach(Array(work.workingValues.enumerated()), id: \.offset) { index, value in
                                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    LabeledContent("Your value after step \(index + 1)", value: value)
                                }
                            }
                        }.nfCard().accessibilityIdentifier("history-original-math-working")
                    }


                    if let trace = savedTrace, let exercise = permittedExercise,
                       let projection = NFCodeTraceProjection.make(exercise: exercise) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Execution inspection", systemImage: "forward.frame").font(.headline)
                            Text("First prediction before inspection").font(.subheadline.bold())
                            Text(NFResponsePresentation.text(trace.prediction, exercise: exercise)).textSelection(.enabled)
                            ForEach(Array((trace.statePredictions ?? []).enumerated()), id: \.offset) { _, prediction in
                                Text("Prediction before step \(prediction.step)").font(.subheadline.bold())
                                Text(prediction.values.keys.sorted().map { "\($0): \(prediction.values[$0] ?? "")" }.joined(separator: ", "))
                                    .font(.body.monospaced()).textSelection(.enabled)
                            }
                            NFCodeTraceView(projection: projection, draft: trace,
                                canInspect: false, predictionIsReady: false, perform: { _ in })
                        }.nfCard().accessibilityIdentifier("history-code-trace")
                    }

                    if let expected = savedExpectedAnswer {
                        if presented.hasDisputedKey {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("This original key is retained for the audit trail and is not endorsed as a valid answer.")
                                    .foregroundStyle(.secondary)
                                reviewTextCard(title: "Original scoring key — disputed", text: expected, symbol: "exclamationmark.triangle")
                            }
                        } else {
                            reviewTextCard(title: "Expected answer", text: expected, symbol: "checkmark.seal")
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label(LocalizedStringKey(presented.hasDisputedKey ? "Original explanation — disputed" : "Explanation"),
                              systemImage: presented.hasDisputedKey ? "exclamationmark.triangle" : "checkmark.seal.fill")
                            .font(.headline)
                        if presented.hasDisputedKey {
                            Text("This original explanation is retained for the audit trail and is not endorsed as valid feedback.")
                                .foregroundStyle(.secondary)
                        }
                        Text(savedExplanation)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .nfCard()

                    if presented.source != .protectedAssessment, (savedLadderHintCount ?? 1) > 0 {
                        let support = NFHistoryContextProjection.make(exercise: permittedExercise,
                            hintCount: savedLadderHintCount ?? 0, isProtected: false, mathWork: savedMathWork)
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Hints used", systemImage: "lightbulb").font(.headline)
                            ForEach(Array(support.usedHints.enumerated()), id: \.offset) { index, hint in
                                if !hint.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Hint \(index + 1)").font(.subheadline.bold())
                                        Text(hint).textSelection(.enabled)
                                    }
                                }
                            }
                            if support.hasUnavailableHints || savedLadderHintCount == nil {
                                Text("The original text of some used hints was not retained.").foregroundStyle(.secondary)
                            }
                        }.nfCard().accessibilityIdentifier("history-used-hints")
                    }

                    NFAttemptAnnotationView(attemptID: presented.id)

                    HStack {
                        Button("Practice this skill") {
                            _ = store.beginSession(lab: presented.lab, source: .focused, evidenceClass: .practice, requestedItemCount: 5, isTimed: false)
                        }.buttonStyle(.borderedProminent)
                        if presented.source != .protectedAssessment && permittedExercise != nil {
                            Button("Report item") { showsReport = true }.buttonStyle(.bordered)
                        }
                    }

                    DisclosureGroup("Technical details") {
                        LabeledContent("Version", value: presented.contentVersionTitle)
                        if presented.source != .protectedAssessment {
                            if presented.correction != nil {
                                LabeledContent("Timing", value: presented.originalTimingTitle)
                            }
                            Text(presented.rawResponse).font(.footnote.monospaced()).textSelection(.enabled)
                        }
                    }
                    .nfCard()

                    Label(presented.privacyNote, systemImage: presented.source.symbol)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .nfCard(cornerRadius: 16, padding: 12)
                        .accessibilityElement(children: .combine)
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Answer review")
        .sheet(isPresented: $showsReport) {
            if presented.source != .protectedAssessment, let exercise = permittedExercise, !exercise.assessmentProtected {
                ReportExerciseView(exercise: exercise, assessmentDescriptorID: nil)
            }
        }
    }

    private var savedExplanation: String {
        if let reason = snapshotUnavailableReason {
            return NFAppLocalization.localizedCatalogValue(reason, locale: NFAppLocalization.preferredLocale)
        }
        return presented.reviewExplanation(exercise: permittedExercise)
    }

    private func reviewTextCard(title: String, text: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(LocalizedStringKey(title), systemImage: symbol)
                .font(.headline)
            Text(text.isEmpty ? "No text was saved for this field." : text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .nfCard()
    }
}

struct NFCompletedTodayReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [NFProgressRoute] = []
    let plan: DailyPlan
    let chapters: [NFCompletedChapterSnapshot]
    let focusedBlockID: String?

    init(
        plan: DailyPlan,
        completedBlockIDs: Set<String>,
        attempts: [AttemptRecord],
        checkpoints: [SessionCheckpointRecord],
        focusedBlockID: String? = nil
    ) {
        self.plan = plan
        self.focusedBlockID = focusedBlockID
        let visibleBlocks = plan.blocks.filter { block in
            completedBlockIDs.contains(block.id) && (focusedBlockID == nil || focusedBlockID == block.id)
        }
        chapters = visibleBlocks.map { block in
            let matchingAttempts = attempts.filter {
                $0.planID == plan.id && $0.planBlockID == block.id
            }
            let matchingCheckpoints = checkpoints.filter {
                $0.planID == plan.id && $0.planBlockID == block.id && $0.isComplete
            }
            return NFCompletedChapterSnapshot(
                block: block,
                attempts: matchingAttempts.map(NFReadOnlyAttemptSnapshot.init(attempt:)),
                completedAt: matchingCheckpoints.map(\.updatedAt).max(),
                scratchpad: matchingCheckpoints
                    .sorted { $0.updatedAt > $1.updatedAt }
                    .map(\.scratchpad)
                    .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            )
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        NFSectionHeader(
                            focusedBlockID == nil ? "Completed circuit review" : "Completed chapter review",
                            eyebrow: "READ-ONLY",
                            subtitle: "Review the exact saved prompts, responses, results, confidence, timing, support, and any retained scratchpad text."
                        )

                        Label(
                            "Reviewing does not reopen, regenerate, or rescore this work.",
                            systemImage: "lock.shield.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .nfCard(cornerRadius: 16, padding: 12)
                        .accessibilityElement(children: .combine)

                        if chapters.isEmpty {
                            ContentUnavailableView(
                                "No completed chapters to review",
                                systemImage: "checkmark.seal",
                                description: Text("Complete a chapter in today’s circuit, then return here to review its saved answers.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 300)
                        } else {
                            ForEach(chapters) { chapter in
                                completedChapter(chapter)
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationDestination(for: NFProgressRoute.self) { route in
                NFProgressRouteView(route: route, filters: .constant(NFProgressFilters()))
            }
            .navigationTitle("Completed review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .nfDesktopPresentationFrame(minWidth: 440, idealWidth: 900, minHeight: 620, idealHeight: 860)
    }

    private func completedChapter(_ chapter: NFCompletedChapterSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                NFIconTile(
                    symbol: chapter.block.lab.symbol,
                    color: NFTheme.color(for: chapter.block.lab.colorToken),
                    size: 48
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.block.title).font(.title3.bold())
                    Text(chapter.block.detail).font(.subheadline).foregroundStyle(.secondary)
                    if let completedAt = chapter.completedAt {
                        Text("Completed \(NFAppLocalization.formattedDate(completedAt, date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                NFStatusPill(text: NFAppLocalization.formattedAnswerCount(chapter.attempts.count), symbol: "checkmark.seal.fill", color: NFTheme.mint)
            }

            if chapter.attempts.isEmpty {
                Text("Completion is recorded, but this chapter has no individual answer rows in the local history.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(chapter.attempts.sorted(by: { $0.submittedAt < $1.submittedAt })) { attempt in
                    NavigationLink(value: NFProgressRoute.attempt(attempt.id)) {
                        NFAttemptHistoryRow(attempt: attempt)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Label("Retained scratchpad", systemImage: "pencil.and.scribble")
                    .font(.headline)
                completedScratchpad(chapter.scratchpad)
            }
            .padding(12)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        }
        .nfCard(cornerRadius: 22, padding: 18)
    }

    @ViewBuilder
    private func completedScratchpad(_ storedValue: String?) -> some View {
        let inspection = NFScratchpadInspection.inspect(storedValue ?? "")
        if let payload = inspection.payload, inspection.canEdit {
        if payload.hasNotes {
            Text(payload.notes)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        #if os(iOS)
        if payload.hasDrawing {
            NFScratchpadDrawingPreview(drawingData: payload.drawingData, originalStoredValue: inspection.originalStoredValue)
        }
        #else
        if payload.hasDrawing {
            Label("A drawing is retained with this chapter and can be reviewed on iPhone or iPad.", systemImage: "scribble.variable")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        #endif
        if !payload.hasNotes && !payload.hasDrawing {
            Text("No scratchpad content was retained in the completed checkpoint.")
                .foregroundStyle(.secondary)
        }
        } else {
            NFScratchpadRecoveryView(storedValue: inspection.originalStoredValue)
        }
    }
}

#if os(iOS)
private struct NFScratchpadDrawingPreview: View {
    let drawingData: Data
    let originalStoredValue: String

    var body: some View {
        Group {
            if let image = previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .padding(8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
            } else {
                NFScratchpadRecoveryView(storedValue: originalStoredValue)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Retained scratchpad drawing")
    }

    private var previewImage: UIImage? {
        guard let drawing = NFScratchpadDrawingSafety.decode(drawingData),
              let plan = NFScratchpadGeometryPolicy.previewPlan(for: drawing.bounds) else { return nil }
        return drawing.image(from: plan.rect, scale: plan.scale)
    }
}
#endif

struct NFCompletedChapterSnapshot: Identifiable {
    let block: PlanBlock
    let attempts: [NFReadOnlyAttemptSnapshot]
    let completedAt: Date?
    let scratchpad: String?

    var id: String { block.id }
}

struct NFProgressRouteView: View {
    @Environment(AppStore.self) private var store
    let route: NFProgressRoute
    @Binding var filters: NFProgressFilters

    var body: some View {
        switch route {
        case .skill(let lab): SkillDetailView(lab: lab, filters: $filters)
        case .history(let lab):
            NFAttemptHistoryView(
                attempts: store.attempts.filter { lab == nil || ($0.gameID == lab?.rawValue && filters.includes($0)) },
                title: "History", subtitle: "Find a prior answer and its explanation."
            )
        case .chartHistory(let ids):
            NFAttemptHistoryView(attempts: store.chartHistoryRecords(from: store.attempts, matching: ids),
                title: "History", subtitle: "Saved answers represented by this chart point.")
        case .attempt(let id):
            if let attempt = store.attempts.first(where: { $0.id == id }) {
                NFAttemptReviewDetailView(attempt: NFReadOnlyAttemptSnapshot(attempt: attempt))
            } else {
                ContentUnavailableView("Saved answer unavailable", systemImage: "doc.questionmark", description: Text("This answer may have been deleted. Return to History to choose another answer."))
            }
        }
    }
}

/// Includes physical-store reloads, private correction/deletion transactions,
/// filters and the day boundary. Raw count/ID equality cannot mask changed rows.
struct NFProgressDashboardRequest: Equatable {
    let reloadID: UUID
    let archiveRevision: UInt64?
    let filters: NFProgressFilters
    let clock: NFProgressDashboardClock
    let section: String
    let isActive: Bool
}

/// One coherent wall-clock/calendar input for row filtering and all reducers.
/// Calendar equality includes week rules, not only the date's midnight boundary.
struct NFProgressDashboardClock: Equatable, Sendable {
    static let maximumRefreshInterval = 60.0
    let capturedAt: Date
    let calendar: Calendar

    func refreshing(isActive: Bool, at date: Date, calendar: Calendar) -> Self {
        guard isActive else { return self }
        return .init(capturedAt: date, calendar: calendar)
    }
}

@MainActor
extension AppStore {
    func progressDashboardRequest(filters: NFProgressFilters, clock: NFProgressDashboardClock,
        section: String = "Overview", isActive: Bool = true) -> NFProgressDashboardRequest {
        .init(reloadID: progressReloadID, archiveRevision: localSessions.archive.transactionRevision,
            filters: filters, clock: clock, section: section, isActive: isActive)
    }

    func progressDashboardInput(filters: NFProgressFilters, clock: NFProgressDashboardClock) -> NFProgressDashboardInput {
        let records = standardizedAttempts.filter { filters.includes($0, at: clock.capturedAt, calendar: clock.calendar) }
        return .init(effectiveAttempts: records.map(effectiveAttemptDTO),
            publicAttempts: publicPracticeChartObservations(from: records),
            diagnostics: records.map { progressDiagnosticObservation(for: $0) },
            capturedAt: clock.capturedAt, calendar: clock.calendar,
            engagement: .init(activities: attempts.map(NFImmutableAttemptRecordSnapshot.init),
                completions: sessionCheckpoints.map { .init(sessionID: $0.sessionID, isComplete: $0.isComplete, updatedAt: $0.updatedAt) },
                trainingDays: profileSnapshot.trainingDays, trackingStartDate: profile?.createdAt,
                excludedLabs: profile?.excludeVisualSpatial == true ? [.spatial, .transfer] : [.transfer]),
            mentalMathInputs: mentalMathProgressInputs(from: records))
    }
}
