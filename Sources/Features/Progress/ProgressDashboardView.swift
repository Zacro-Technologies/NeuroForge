import Charts
import SwiftUI

#if os(iOS)
import PencilKit
import UIKit
#endif

struct ProgressDashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedSkill: TrainingLab?
    @State private var filters = NFProgressFilters()
    @State private var showsFilters = false
    @State private var showsProgressDetails = false
    @State private var showsMethodology = false

    private var hasAnyStandardizedHistory: Bool {
        !store.standardizedAttempts.isEmpty
    }

    private var hasMatchingStandardizedHistory: Bool {
        !filteredAttempts.isEmpty
    }

    private var filteredAttempts: [AttemptRecord] {
        store.standardizedAttempts.filter { filters.includes($0) }
    }

    private var filteredSummaries: [SkillSummary] {
        AdaptiveEngine.reduce(filteredAttempts.map(\.dto))
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
        filteredAttempts.filter { !$0.wasSkipped && $0.evidenceWeight > 0 }.count
    }

    private var personalPracticeCount: Int {
        store.attempts.filter {
            filters.includes($0)
                && !$0.wasSkipped
                && $0.evidenceClassRaw == EvidenceClass.documentPractice.rawValue
        }.count
    }

    private var errorPatterns: [NFErrorPattern] {
        var grouped: [String: (count: Int, last: Date?)] = [:]

        for attempt in filteredAttempts where !attempt.isCorrect && !attempt.wasSkipped && attempt.evidenceWeight > 0 {
            guard let code = store.effectiveErrorCode(for: attempt) else { continue }
            let existing = grouped[code]
            grouped[code] = (
                count: (existing?.count ?? 0) + 1,
                last: max(existing?.last ?? .distantPast, attempt.submittedAt)
            )
        }

        return grouped
            .map { NFErrorPattern(code: $0.key, count: $0.value.count, last: $0.value.last) }
            .sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs.code < rhs.code : lhs.count > rhs.count
            }
    }

    private var insightSnapshot: NFProgressInsightSnapshot {
        NFProgressInsightEngine.makeSnapshot(
            at: Date(),
            attempts: filteredAttempts,
            errorCodeOverrides: store.attemptReflections.reduce(into: [UUID: String]()) { result, reflection in
                guard result[reflection.attemptID] == nil,
                      let code = reflection.selectedErrorCodeRaw else { return }
                result[reflection.attemptID] = code
            }
        )
    }

    private var consistencySnapshot: NFConsistencySnapshot {
        NFConsistencyEngine.makeSnapshot(
            at: Date(),
            attempts: store.standardizedAttempts,
            trainingDays: store.profileSnapshot.trainingDays,
            trackingStartDate: store.profile?.createdAt
        )
    }

    private var mentalMathMetrics: [NFMentalMathMetricKind: NFMentalMathMetricResult] {
        NFMentalMathMetricReducer.reduce(
            NFMentalMathProgressAdapter.observations(from: filteredAttempts)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        NFSectionHeader(
                            "Your progress",
                            eyebrow: "Personal learning",
                            subtitle: "See what is improving and what is worth practicing next."
                        )
                        overviewHero
                        forgeJourneyCard
                        prioritySection
                        weeklyTrendCard
                        consistencyCard
                        DisclosureGroup(isExpanded: $showsFilters) {
                            progressFiltersCard
                                .padding(.top, 12)
                        } label: {
                            Label("Filter progress", systemImage: "line.3.horizontal.decrease.circle")
                                .font(.headline)
                        }
                        .nfCard(cornerRadius: 18, padding: 16)
                        DisclosureGroup(isExpanded: $showsProgressDetails) {
                            VStack(alignment: .leading, spacing: 24) {
                                deterministicInsightsCard
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
                        DisclosureGroup(isExpanded: $showsMethodology) {
                            methodologyNote
                                .padding(.top, 10)
                        } label: {
                            Label("How progress is calculated", systemImage: "info.circle")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(20)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Progress")
            .navigationDestination(item: $selectedSkill) { lab in
                SkillDetailView(lab: lab, filters: $filters)
            }
        }
    }

    private var overviewHero: some View {
        let hasOnlyPersonalPractice = totalEvidence == 0 && personalPracticeCount > 0
        let isFilteredEmpty = hasAnyStandardizedHistory && !hasMatchingStandardizedHistory
        let hasMatchingUnscoredActivity = hasMatchingStandardizedHistory && totalEvidence == 0
        return HStack(spacing: 24) {
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
                        : totalEvidence == 0 ? "Your skill map starts unassessed." : "Your skill map is taking shape.")
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

    private var forgeJourneyCard: some View {
        let progress = store.forgeProgress
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
                "Forge XP celebrates completed practice and breadth. It is separate from accuracy, transfer, retention, and skill evidence.",
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
        let points = NFWeeklyProgressPoint.make(from: filteredAttempts)
        return VStack(alignment: .leading, spacing: 12) {
            NFSectionHeader(
                "Weekly performance by module",
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
                .frame(height: 260)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(NFWeeklyProgressPoint.accessibilitySummary(for: points))

                DisclosureGroup("View weekly chart data") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(points) { point in
                            HStack(alignment: .firstTextBaseline) {
                                Text(NFAppLocalization.formattedDate(point.week, date: .abbreviated, time: .omitted))
                                Text(point.lab.shortTitle)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 12)
                                Text(point.credit, format: .percent.precision(.fractionLength(0)))
                                    .font(.body.monospacedDigit())
                                Text(NFAppLocalization.formattedAnswerCount(point.count))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
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

    private var consistencyCard: some View {
        let snapshot = consistencySnapshot
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

    private var deterministicInsightsCard: some View {
        let insights = insightSnapshot
        return VStack(alignment: .leading, spacing: 14) {
            NFSectionHeader(
                "Patterns worth noticing",
                subtitle: "Based on your scored practice."
            )

            insightSection(
                title: "Strengths",
                empty: "Complete a little more varied practice to reveal strengths.",
                insights: Array(insights.strengths.prefix(3)),
                symbol: "checkmark.seal.fill",
                foregroundColor: NFTheme.mintForeground
            )
            insightSection(
                title: "Confidence to revisit",
                empty: "No repeated high-confidence mistakes in this view.",
                insights: Array(insights.overconfidenceHotspots.prefix(3)),
                symbol: "gauge.with.dots.needle.67percent",
                foregroundColor: NFTheme.amberForeground
            )
            insightSection(
                title: "Reviews due",
                empty: "Nothing is due for review.",
                insights: Array(insights.reviewsDue.prefix(4)),
                symbol: "clock.arrow.circlepath",
                foregroundColor: NFTheme.cyanForeground
            )
        }
        .nfCard()
    }

    @ViewBuilder
    private func insightSection(
        title: String,
        empty: String,
        insights: [NFProgressInsight],
        symbol: String,
        foregroundColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(LocalizedStringKey(title))
            } icon: {
                Image(systemName: symbol)
            }
                .font(.headline)
                .foregroundStyle(foregroundColor)
            if insights.isEmpty {
                Text(LocalizedStringKey(empty)).font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(insights) { insight in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(insight.title).font(.subheadline.weight(.semibold))
                        Text(insight.detail).font(.footnote).foregroundStyle(.secondary)
                        Text("Based on \(NFAppLocalization.formattedAnswerCount(insight.evidenceAttemptIDs.count))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
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
        let personal = store.attempts.filter { filters.includes($0) && $0.evidenceClassRaw == EvidenceClass.documentPractice.rawValue }
        let scorable = filteredAttempts.filter { !$0.wasSkipped && $0.evidenceWeight > 0 }
        let assessment = scorable.filter { $0.evidenceClassRaw == EvidenceClass.assessmentHoldout.rawValue }
        let practice = scorable.filter { $0.evidenceClassRaw == EvidenceClass.practice.rawValue }
        let transfer = scorable.filter {
            $0.evidenceClassRaw == EvidenceClass.nearTransfer.rawValue || $0.evidenceClassRaw == EvidenceClass.appliedTransfer.rawValue
        }
        let retention = scorable.filter { $0.evidenceClassRaw == EvidenceClass.retention.rawValue }
        return VStack(alignment: .leading, spacing: 13) {
            NFSectionHeader("Kinds of practice", subtitle: "See where your completed questions came from.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                EvidenceChannelMetric(title: "Practice", count: practice.count, symbol: "repeat", foregroundColor: NFTheme.indigoForeground)
                EvidenceChannelMetric(title: "Transfer", count: transfer.count, symbol: "arrow.triangle.swap", foregroundColor: NFTheme.roseForeground)
                EvidenceChannelMetric(title: "Retention", count: retention.count, symbol: "clock.arrow.circlepath", foregroundColor: NFTheme.mintForeground)
                EvidenceChannelMetric(title: "Protected assessment", count: assessment.count, symbol: "lock.shield.fill", foregroundColor: NFTheme.cyanForeground)
                EvidenceChannelMetric(title: "Personal AI/source", count: personal.count, symbol: "apple.intelligence", foregroundColor: NFTheme.amberForeground)
            }
        }
    }

    private var mentalMathMetricsCard: some View {
        let metrics = mentalMathMetrics
        return VStack(alignment: .leading, spacing: 14) {
            NFSectionHeader(
                "Mental-math details",
                subtitle: "Accuracy, speed, strategy, retention, and transfer stay separate."
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
        case .independentAccuracy: NFAppLocalization.localized("Independent accuracy", locale: NFAppLocalization.preferredLocale, comment: "Independent mental-math progress metric.")
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
                            selectedSkill = summary.lab
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
        let confidenceAttempts = filteredAttempts.filter { $0.confidenceRaw != nil && !$0.wasSkipped && $0.evidenceWeight > 0 }
        let calibrated = confidenceAttempts.filter { attempt in
            guard let confidence = attempt.confidenceRaw.flatMap(ConfidenceLevel.init(rawValue:)) else { return false }
            return (confidence.probability >= 0.5) == attempt.isCorrect
        }.count
        let fraction = confidenceAttempts.isEmpty ? 0 : Double(calibrated) / Double(confidenceAttempts.count)

        return HStack(spacing: 20) {
            Gauge(value: fraction) {
                Text("Calibration")
            } currentValueLabel: {
                Text(confidenceAttempts.isEmpty ? "—" : fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.headline.monospacedDigit())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(Gradient(colors: [NFTheme.amber, NFTheme.cyan, NFTheme.mint]))
            .frame(width: 90)

            VStack(alignment: .leading, spacing: 5) {
                Text("Confidence calibration")
                    .font(.headline)
                Text(
                    confidenceAttempts.isEmpty
                        ? "Answer a few questions to see how confidence matches accuracy."
                        : "Confidence matched accuracy for \(calibrated) of \(NFAppLocalization.formattedAnswerCount(confidenceAttempts.count))."
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
            if errorPatterns.isEmpty {
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

    var cutoff: Date? {
        let calendar = Calendar.current
        return switch self {
        case .currentWeek: calendar.dateInterval(of: .weekOfYear, for: Date())?.start
        case .fourWeeks: calendar.date(byAdding: .day, value: -28, to: Date())
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

struct NFProgressFilters {
    var period: NFProgressPeriod = .fourWeeks
    var lab: TrainingLab?
    var inputMode: String?
    var timing: NFProgressTimingFilter = .all
    var domain: STEMField?

    static let unfiltered = NFProgressFilters(period: .allTime)

    var hasRestrictions: Bool {
        period != .allTime || lab != nil || inputMode != nil || timing != .all || domain != nil
    }

    func includes(_ attempt: AttemptRecord) -> Bool {
        if let cutoff = period.cutoff, attempt.submittedAt < cutoff { return false }
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

struct NFWeeklyProgressPoint: Identifiable {
    let week: Date
    let lab: TrainingLab
    let credit: Double
    let count: Int

    var id: String { "\(week.timeIntervalSinceReferenceDate)|\(lab.rawValue)" }

    static func make(from attempts: [AttemptRecord], calendar: Calendar = .current) -> [NFWeeklyProgressPoint] {
        let eligible = attempts.filter { !$0.wasSkipped && $0.evidenceWeight > 0 }
        let grouped = Dictionary(grouping: eligible) { attempt in
            let week = calendar.dateInterval(of: .weekOfYear, for: attempt.submittedAt)?.start
                ?? calendar.startOfDay(for: attempt.submittedAt)
            let lab = TrainingLab(rawValue: attempt.gameID) ?? .mentalMath
            return "\(week.timeIntervalSinceReferenceDate)|\(lab.rawValue)"
        }
        return grouped.compactMap { _, records in
            guard let first = records.first else { return nil }
            let week = calendar.dateInterval(of: .weekOfYear, for: first.submittedAt)?.start
                ?? calendar.startOfDay(for: first.submittedAt)
            let lab = TrainingLab(rawValue: first.gameID) ?? .mentalMath
            let available = records.reduce(0) { $0 + max(0, $1.evidenceWeight) }
            guard available > 0 else { return nil }
            let earned = records.reduce(0) {
                $0 + min(1, max(0, $1.deterministicCredit)) * max(0, $1.evidenceWeight)
            }
            return NFWeeklyProgressPoint(week: week, lab: lab, credit: earned / available, count: records.count)
        }.sorted {
            if $0.week != $1.week { return $0.week < $1.week }
            return $0.lab.rawValue < $1.lab.rawValue
        }
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
            return "\(lab.shortTitle): \(last.credit.formatted(.percent.precision(.fractionLength(0)))) latest, \(changeText)"
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

    init(lab: TrainingLab, attempts: [AttemptRecord]) {
        self.lab = lab
        self.attempts = attempts.filter { attempt in
            !attempt.wasSkipped
                && attempt.evidenceWeight > 0
                && EvidenceClass(rawValue: attempt.evidenceClassRaw) != .documentPractice
                && Self.attributedWeight(of: attempt, to: lab) > 0
        }
    }

    var evidenceCount: Int { attempts.count }

    var credit: Double? {
        metric(for: Set(EvidenceClass.allCases.filter { $0 != .documentPractice })).credit
    }

    var lastTrained: Date? {
        attempts.map(\.submittedAt).max()
    }

    var status: EstimateStatus {
        AdaptiveEngine.reduce(attempts.map(\.dto)).first(where: { $0.lab == lab })?.status
            ?? .unassessed
    }

    func metric(for classes: Set<EvidenceClass>) -> Metric {
        let matching = attempts.filter {
            classes.contains(EvidenceClass(rawValue: $0.evidenceClassRaw) ?? .practice)
        }
        let available = matching.reduce(0.0) { result, attempt in
            result + max(0, attempt.evidenceWeight) * Self.attributedWeight(of: attempt, to: lab)
        }
        guard available > 0 else { return Metric(credit: nil, count: 0) }
        let earned = matching.reduce(0.0) { result, attempt in
            let evidence = max(0, attempt.evidenceWeight) * Self.attributedWeight(of: attempt, to: lab)
            return result + min(1, max(0, attempt.deterministicCredit)) * evidence
        }
        return Metric(credit: earned / available, count: matching.count)
    }

    static func attributedWeight(of attempt: AttemptRecord, to lab: TrainingLab) -> Double {
        if let direct = attempt.skillWeights[lab.skillID], direct > 0 {
            return direct
        }
        guard let dimension = attempt.dto.assessmentDimension,
              dimension != .confidenceCalibration,
              dimension.lab == lab else {
            return 0
        }
        return attempt.skillWeights[dimension.skillID] ?? 1
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
    let lab: TrainingLab
    @Binding var filters: NFProgressFilters

    private var filteredAttempts: [AttemptRecord] {
        store.standardizedAttempts.filter { filters.includes($0) }
    }

    private var evidenceSnapshot: NFAbilityEvidenceSnapshot {
        NFAbilityEvidenceSnapshot(lab: lab, attempts: filteredAttempts)
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
            attempts: evidenceSnapshot.attempts.map(\.dto)
        )
    }

    private var points: [EvidencePoint] {
        EvidencePoint.make(from: evidenceSnapshot.attempts)
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
                        DetailMetric(value: evidenceSnapshot.credit.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—", label: "Earned credit")
                        DetailMetric(value: "\(evidenceSnapshot.evidenceCount)", label: "Scored answers")
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
                            EvidenceCoverageRow(label: "Near transfer", detail: metric(for: .nearTransfer), symbol: "arrow.left.arrow.right", color: NFTheme.cyanForeground)
                            EvidenceCoverageRow(label: "Applied transfer", detail: metric(for: .appliedTransfer), symbol: "arrow.triangle.swap", color: NFTheme.roseForeground)
                            EvidenceCoverageRow(label: "Delayed retention", detail: metric(for: .retention), symbol: "clock.arrow.circlepath", color: NFTheme.mintForeground)
                            EvidenceCoverageRow(label: "Protected assessment", detail: metric(for: .assessmentHoldout), symbol: "lock.shield.fill", color: NFTheme.cyanForeground)
                        }
                        .nfCard()
                    }

                    NavigationLink {
                        NFAttemptHistoryView(
                            attempts: historyAttempts,
                            title: "\(lab.shortTitle) answer history",
                            subtitle: "Exact saved prompts and responses under the active dashboard filters."
                        )
                    } label: {
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
                         : "Complete at least \(NFAppLocalization.formattedAnswerCount(NFSpeedEvidenceEngine.minimumEligibleAttempts)) with correct, uninterrupted timed responses. You have \(NFAppLocalization.formattedAnswerCount(speedEvidence.eligibleCount)).")
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
        if practice.count >= 3, transfer.count >= 3, practice.credit - transfer.credit >= 0.15 {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.swap").foregroundStyle(NFTheme.amberForeground)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Transfer gap is visible").font(.headline)
                    Text("Practice credit is \(practice.credit.formatted(.percent.precision(.fractionLength(0)))) while unfamiliar transfer is \(transfer.credit.formatted(.percent.precision(.fractionLength(0)))). Gains are currently limited to more familiar mechanics; the app will keep measuring transfer separately.")
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
                .frame(height: 280)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(EvidencePoint.accessibilitySummary(for: points))

                DisclosureGroup("View performance chart data") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(points) { point in
                            HStack(alignment: .firstTextBaseline) {
                                Text(NFAppLocalization.formattedDate(point.date, date: .abbreviated, time: .shortened))
                                Text(point.series)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 12)
                                Text(point.accuracy, format: .percent.precision(.fractionLength(0)))
                                    .font(.body.monospacedDigit())
                                Text("after \(point.index)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
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

private struct EvidencePoint: Identifiable {
    let id: UUID
    let index: Int
    let accuracy: Double
    let series: String
    let date: Date

    static func make(from attempts: [AttemptRecord]) -> [EvidencePoint] {
        let sorted = attempts
            .filter { !$0.wasSkipped && $0.evidenceWeight > 0 }
            .sorted { $0.submittedAt < $1.submittedAt }
        let classes: [(EvidenceClass, String)] = [
            (.practice, "Training"),
            (.nearTransfer, "Near transfer"),
            (.appliedTransfer, "Applied transfer"),
            (.retention, "Delayed retention"),
            (.assessmentHoldout, "Protected assessment")
        ]
        return classes.flatMap { evidenceClass, title in
            let matching = sorted.filter { EvidenceClass(rawValue: $0.evidenceClassRaw) == evidenceClass }
            var earnedCredit = 0.0
            var availableEvidence = 0.0
            return matching.enumerated().map { offset, attempt in
                let weight = max(0, attempt.evidenceWeight)
                earnedCredit += min(1, max(0, attempt.deterministicCredit)) * weight
                availableEvidence += weight
                return EvidencePoint(
                    id: attempt.id,
                    index: offset + 1,
                    accuracy: earnedCredit / availableEvidence,
                    series: NFAppLocalization.localizedCatalogValue(title),
                    date: attempt.submittedAt
                )
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
            return "\(name): \(last.accuracy.formatted(.percent.precision(.fractionLength(0)))) after \(NFAppLocalization.formattedAnswerCount(last.index)), \(comparison)"
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

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: NFAppLocalization.localized("All results", locale: NFAppLocalization.preferredLocale, comment: "Answer-history result filter.")
        case .correct: NFAppLocalization.localized("Correct", locale: NFAppLocalization.preferredLocale, comment: "Answer-history result filter.")
        case .partial: NFAppLocalization.localized("Partial credit", locale: NFAppLocalization.preferredLocale, comment: "Answer-history result filter.")
        case .incorrect: NFAppLocalization.localized("Incorrect", locale: NFAppLocalization.preferredLocale, comment: "Answer-history result filter.")
        case .skipped: NFAppLocalization.localized("Skipped", locale: NFAppLocalization.preferredLocale, comment: "Answer-history result filter.")
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

/// Immutable, read-only copy of the durable answer fields already exposed by
/// AppStore. Review UI never regenerates or re-scores an attempt.
struct NFReadOnlyAttemptSnapshot: Identifiable {
    let id: UUID
    let lab: TrainingLab
    let submittedAt: Date
    let prompt: String
    let response: String
    let correctAnswer: String
    let result: NFAttemptHistoryResult
    let deterministicCredit: Double
    let wasTimed: Bool
    let activeDurationSeconds: Double
    let hintCount: Int
    let accommodationCount: Int
    let confidence: ConfidenceLevel?
    let source: NFAttemptHistorySource
    let evidenceClass: EvidenceClass
    let templateID: String
    let scoringVersion: Int
    let validationVersion: Int
    let inputMode: String
    let sessionSource: SessionSource?

    init(attempt: AttemptRecord) {
        id = attempt.id
        lab = TrainingLab(rawValue: attempt.gameID) ?? .mentalMath
        submittedAt = attempt.submittedAt
        prompt = attempt.prompt
        response = attempt.response
        correctAnswer = attempt.correctAnswerText
        deterministicCredit = min(1, max(0, attempt.deterministicCredit))
        if attempt.wasSkipped {
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
        if evidenceClass == .assessmentHoldout {
            source = .protectedAssessment
        } else if evidenceClass == .documentPractice
                    || attempt.generationID != nil
                    || !attempt.sourceDocumentIDsRaw.isEmpty {
            source = .personal
        } else {
            source = .appPractice
        }
        templateID = attempt.templateID
        scoringVersion = max(0, attempt.scoringVersion)
        validationVersion = max(0, attempt.validationVersion)
        inputMode = NFInputModality.title(forPersistedValue: attempt.inputModeRaw)
        sessionSource = SessionSource(rawValue: attempt.sessionSourceRaw)
    }

    var resultTitle: String { result.title }

    var timingTitle: String {
        let duration = NFAppLocalization.formattedSeconds(activeDurationSeconds)
        return wasTimed
            ? NFAppLocalization.localized("Timed · \(duration)", locale: NFAppLocalization.preferredLocale, comment: "Answer-history timing value.")
            : NFAppLocalization.localized("Untimed · \(duration) active", locale: NFAppLocalization.preferredLocale, comment: "Answer-history timing value.")
    }

    var supportTitle: String {
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

    var usedSupport: Bool { hintCount > 0 || accommodationCount > 0 }

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
                "The detailed key is intentionally withheld for protected skill-check content. Your recorded result and earned credit are shown above.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Answer-history explanation for protected assessment content."
            )
        }
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

struct NFAttemptHistoryView: View {
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
        attempts.filter { attempt in
            if let cutoff = period.cutoff, attempt.submittedAt < cutoff { return false }
            if let activity, attempt.lab != activity { return false }
            if result != .all, attempt.result != result { return false }
            switch timing {
            case .all: break
            case .timed where !attempt.wasTimed: return false
            case .untimed where attempt.wasTimed: return false
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
               !attempt.response.localizedCaseInsensitiveContains(query) {
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
                            NavigationLink {
                                NFAttemptReviewDetailView(attempt: attempt)
                            } label: {
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
    let attempt: NFReadOnlyAttemptSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(NFAppLocalization.formattedDate(attempt.submittedAt, date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.semibold))
                Text(attempt.activityTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Label(attempt.source.title, systemImage: attempt.source.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(attempt.source == .personal ? NFTheme.amberForeground : NFTheme.indigoForeground)
            }

            Text(attempt.prompt.isEmpty ? "Prompt unavailable in this saved version" : attempt.prompt)
                .font(.headline)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Text("Answer: \(attempt.response.isEmpty ? "No response saved" : attempt.response)")
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
        Text(attempt.resultTitle).foregroundStyle(resultColor)
        Text(attempt.timingTitle)
        Text(attempt.supportTitle)
        Text("Confidence: \(attempt.confidenceTitle)")
    }

    private var resultColor: Color {
        switch attempt.result {
        case .correct: NFTheme.mintForeground
        case .partial: NFTheme.amberForeground
        case .incorrect: NFTheme.roseForeground
        case .skipped, .all: .secondary
        }
    }
}

struct NFAttemptReviewDetailView: View {
    let attempt: NFReadOnlyAttemptSnapshot

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NFSectionHeader(
                        "Saved answer",
                        eyebrow: "READ-ONLY",
                        subtitle: NFAppLocalization.formattedDate(attempt.submittedAt, date: .complete, time: .shortened)
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Activity", value: attempt.activityTitle)
                        LabeledContent("Result", value: attempt.resultTitle)
                        LabeledContent("Earned credit", value: attempt.deterministicCredit.formatted(.percent.precision(.fractionLength(0))))
                        LabeledContent("Timing", value: attempt.timingTitle)
                        LabeledContent("Support", value: attempt.supportTitle)
                        LabeledContent("Confidence", value: attempt.confidenceTitle)
                        LabeledContent("Input", value: attempt.inputMode)
                        LabeledContent("Version", value: attempt.contentVersionTitle)
                    }
                    .nfCard()

                    reviewTextCard(title: "Prompt — exact saved text", text: attempt.prompt, symbol: "questionmark.bubble.fill")
                    reviewTextCard(title: "Your answer — exact saved response", text: attempt.response, symbol: "text.bubble.fill")

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Scoring explanation", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                        Text(attempt.explanation)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .nfCard()

                    Label(attempt.privacyNote, systemImage: attempt.source.symbol)
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
    }

    private func reviewTextCard(title: String, text: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
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
        NavigationStack {
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
                    NavigationLink {
                        NFAttemptReviewDetailView(attempt: attempt)
                    } label: {
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
        let payload = NFScratchpadPayload.decode(storedValue ?? "")
        if payload.hasNotes {
            Text(payload.notes)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        #if os(iOS)
        if payload.hasDrawing {
            NFScratchpadDrawingPreview(drawingData: payload.drawingData)
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
    }
}

#if os(iOS)
private struct NFScratchpadDrawingPreview: View {
    let drawingData: Data

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
                Label("A scratchpad drawing was retained, but its preview is unavailable.", systemImage: "scribble.variable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Retained scratchpad drawing")
    }

    private var previewImage: UIImage? {
        guard let drawing = try? PKDrawing(data: drawingData), !drawing.bounds.isEmpty else { return nil }
        return drawing.image(from: drawing.bounds.insetBy(dx: -12, dy: -12), scale: 2)
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
