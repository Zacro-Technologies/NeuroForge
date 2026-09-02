import SwiftUI

private func mentalMathProgressionStatus(
    from attempts: [AttemptRecord]
) -> NFMentalMathProgressionStatus {
    NFMentalMathProgressionPolicy.status(for: attempts
        .filter {
            $0.gameID == TrainingLab.mentalMath.rawValue
                && $0.evidenceClassRaw != EvidenceClass.documentPractice.rawValue
        }
        .map {
            NFMentalMathProgressionObservation(
                submittedAt: $0.submittedAt,
                isCorrect: $0.isCorrect,
                errorCode: $0.errorCode,
                strategyID: $0.templateID,
                wasTimed: $0.wasTimed,
                wasSkipped: $0.wasSkipped,
                evidenceWeight: $0.evidenceWeight
            )
        })
}

private func trainSubskills(for lab: TrainingLab) -> [NFDefaultContentActivity] {
    NFDefaultContentCatalog.activities(for: lab)
}

extension AppStore {
    /// Catalog browsing is learner-directed practice, even when the practiced
    /// mechanic is about structural transfer. Protected transfer evidence is
    /// created only by scheduled tasks with an explicit transfer brief.
    @discardableResult
    func beginDefaultCatalogSession(
        _ selection: NFDefaultContentSelection,
        requestedMinutes: Int? = nil,
        requestedItemCount: Int? = 10,
        isTimed: Bool = false
    ) -> Bool {
        let activity = selection.activity
        let priorExposureCount = attempts.lazy.filter {
            $0.gameID == activity.lab.rawValue
                && $0.domainContextRaw == selection.field.rawValue
                && ($0.assessmentMechanicID == activity.mechanicID
                    || ($0.assessmentMechanicID == nil
                        && $0.templateID.contains(activity.templateSlug)))
        }.count
        let seed = NFStableDeterminism.hash64(
            "default-catalog|v\(NFDefaultContentCatalog.version)|\(activity.id)|\(selection.field.rawValue)|\(todayPlan.seed)|exposure-\(priorExposureCount)"
        )
        return beginSession(
            lab: activity.lab,
            source: .focused,
            requestedMinutes: requestedMinutes ?? activity.recommendedMinutes,
            evidenceClass: activity.defaultEvidenceClass,
            field: selection.field,
            topic: activity.localizedTitle,
            targetDifficulty: activity.defaultDifficulty,
            requestedItemCount: requestedItemCount,
            seedOverride: seed,
            isTimed: isTimed,
            mechanicID: activity.mechanicID
        )
    }
}

struct TrainCatalogView: View {
    @Environment(AppStore.self) private var store
    @State private var searchText = ""
    @State private var selection: TrainingLab?
    @State private var showAIStudio = false
    @State private var showsPracticeCatalog = false
    @State private var pendingCatalogSelection: NFDefaultContentSelection?

    private var filteredLabs: [TrainingLab] {
        let availableLabs = foundationalLabs
        guard !trimmedSearchText.isEmpty else { return availableLabs }
        return availableLabs.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedSearchText) ||
            $0.subtitle.localizedCaseInsensitiveContains(trimmedSearchText) ||
            trainSubskills(for: $0).contains {
                $0.title.localizedCaseInsensitiveContains(trimmedSearchText)
                    || $0.localizedTitle.localizedCaseInsensitiveContains(trimmedSearchText)
                    || $0.localizedSummary.localizedCaseInsensitiveContains(trimmedSearchText)
                    || $0.keywords.contains(where: {
                        $0.localizedCaseInsensitiveContains(trimmedSearchText)
                    })
            }
        }
    }

    private var availableLabs: [TrainingLab] {
        TrainingLab.allCases.filter {
            !(store.profile?.excludeVisualSpatial == true && $0 == .spatial)
        }
    }

    private var foundationalLabs: [TrainingLab] {
        availableLabs.filter { $0 != .transfer }
    }

    private var showsTransferChallenge: Bool {
        guard availableLabs.contains(.transfer) else { return false }
        guard !trimmedSearchText.isEmpty else { return true }
        let transfer = TrainingLab.transfer
        let searchTerms = [
            transfer.title,
            transfer.subtitle,
            "cross-ability challenge",
            "apply skills together"
        ]
        return searchTerms.contains {
            $0.localizedCaseInsensitiveContains(trimmedSearchText)
        } || trainSubskills(for: transfer).contains {
            $0.title.localizedCaseInsensitiveContains(trimmedSearchText)
                || $0.localizedTitle.localizedCaseInsensitiveContains(trimmedSearchText)
                || $0.localizedSummary.localizedCaseInsensitiveContains(trimmedSearchText)
                || $0.keywords.contains(where: {
                    $0.localizedCaseInsensitiveContains(trimmedSearchText)
                })
        }
    }

    private var visibleCatalogFamilyCount: Int {
        availableLabs.reduce(into: 0) { count, lab in
            count += NFDefaultContentCatalog.activities(for: lab).count
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var defaultCatalogField: STEMField {
        store.profileSnapshot.fields.sorted { $0.rawValue < $1.rawValue }.first ?? .general
    }

    private var recommendedLab: TrainingLab {
        let available = Set(foundationalLabs)
        return store.currentPriorityBreakdowns
            .map(\.lab)
            .first(where: available.contains)
            ?? foundationalLabs.first(where: { summary(for: $0).evidenceCount == 0 })
            ?? .mentalMath
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if trimmedSearchText.isEmpty {
                            NFSectionHeader(
                                "Build your STEM toolkit",
                                eyebrow: "Focused practice",
                                subtitle: "Follow your recommendation or choose a foundational ability path."
                            )

                            recommendedCard

                            foundationalAbilitySection

                            crossAbilityChallengeSection

                            moreWaysToPracticeSection
                        } else {
                            searchResultsSection
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Practice")
            .searchable(text: $searchText, prompt: "Search ability paths and skills")
            .sheet(isPresented: $showAIStudio) {
                AIStudioView()
                    .environment(store)
            }
            .sheet(isPresented: $showsPracticeCatalog, onDismiss: startPendingCatalogActivity) {
                NFDefaultContentBrowser(
                    excludedLabs: store.profile?.excludeVisualSpatial == true ? [.spatial] : [],
                    defaultField: defaultCatalogField
                ) { selection in
                    pendingCatalogSelection = selection
                    showsPracticeCatalog = false
                }
            }
            .navigationDestination(item: $selection) { lab in
                LabDetailView(lab: lab)
            }
            .onAppear(perform: openRequestedAIStudioIfNeeded)
            .onChange(of: store.shouldOpenAIStudio) { _, _ in
                openRequestedAIStudioIfNeeded()
            }
        }
    }

    private func startPendingCatalogActivity() {
        guard let selection = pendingCatalogSelection else { return }
        pendingCatalogSelection = nil
        store.beginDefaultCatalogSession(selection)
    }

    private func openRequestedAIStudioIfNeeded() {
        guard store.shouldOpenAIStudio else { return }
        store.shouldOpenAIStudio = false
        showAIStudio = true
    }

    private var foundationalAbilitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NFSectionHeader(
                "Foundational ability paths",
                subtitle: "Train each part of the toolkit on its own, then combine them in crossover work."
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 265), spacing: 14)], spacing: 14) {
                ForEach(foundationalLabs) { lab in
                    Button {
                        selection = lab
                    } label: {
                        LabCard(lab: lab, summary: summary(for: lab))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var crossAbilityChallengeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NFSectionHeader(
                "Cross-ability challenge",
                subtitle: "Apply familiar skills together in an unfamiliar context."
            )
            crossAbilityChallengeCard
        }
    }

    private var moreWaysToPracticeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NFSectionHeader(
                "More ways to practice",
                subtitle: "Browse an exact activity or create a question set for your own topic."
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                practiceCatalogCard
                aiStudioCard
            }
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Search results")
                .font(.title2.bold())
            if filteredLabs.isEmpty && !showsTransferChallenge {
                ContentUnavailableView {
                    Label("No matching practice", systemImage: "magnifyingglass")
                } description: {
                    Text("Try another ability, skill, or challenge name.")
                } actions: {
                    Button("Clear search") { searchText = "" }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 265), spacing: 14)], spacing: 14) {
                    ForEach(filteredLabs) { lab in
                        Button {
                            selection = lab
                        } label: {
                            LabCard(lab: lab, summary: summary(for: lab))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if showsTransferChallenge {
                    crossAbilityChallengeCard
                }
            }
        }
    }

    private var crossAbilityChallengeCard: some View {
        let lab = TrainingLab.transfer
        let labSummary = summary(for: lab)
        return Button {
            selection = lab
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    NFIconTile(
                        symbol: lab.symbol,
                        color: NFTheme.color(for: lab.colorToken),
                        size: 54
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Crossover")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NFTheme.foregroundColor(for: lab.colorToken))
                            .textCase(.uppercase)
                        Text("Apply skills together")
                            .font(.title3.bold())
                    }
                    Spacer(minLength: 0)
                }

                Text(lab.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(labSummary.status.title)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Label("Open challenge", systemImage: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NFTheme.foregroundColor(for: lab.colorToken))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .nfCard(cornerRadius: 22, padding: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var aiStudioCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [NFTheme.rose.opacity(0.28), NFTheme.indigo.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(NFTheme.roseForeground)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Custom question sets")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("Create practice for a topic")
                        .font(.title3.bold())
                }
            }

            Text(NFAppLocalization.localized(
                "Choose from \(NFStarterQuestionSetCatalog.sets.count) starter sets, enter your own topic, or use imported material.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Train catalog question-set summary with starter-set count."
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Create question set") { showAIStudio = true }
                .buttonStyle(.borderedProminent)
                .tint(NFTheme.roseControlTint)
                .foregroundStyle(NFTheme.roseControlForeground)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("open-ai-studio")
        }
        .nfCard(cornerRadius: 24)
    }

    private var practiceCatalogCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [NFTheme.indigo.opacity(0.24), NFTheme.cyan.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "square.grid.3x3.square")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(NFTheme.indigoForeground)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Activity catalog")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("Choose a specific challenge")
                        .font(.title3.bold())
                }
            }

            Text(NFAppLocalization.localized(
                "Browse \(visibleCatalogFamilyCount) activity families across \(availableLabs.count) paths, available offline and adaptable to \(STEMField.allCases.count) STEM contexts.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Practice catalog summary of the bundled deterministic activity families, ability paths, and STEM contexts."
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Browse activities") { showsPracticeCatalog = true }
                .buttonStyle(.borderedProminent)
                .tint(NFTheme.controlTint(for: "indigo"))
                .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
        .nfCard(cornerRadius: 24)
    }

    private var recommendedCard: some View {
        let lab = recommendedLab
        let summary = summary(for: lab)
        let progression = mentalMathProgressionStatus(from: store.attempts)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                NFIconTile(symbol: lab.symbol, color: NFTheme.color(for: lab.colorToken), size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommended practice")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(lab.title)
                        .font(.title3.bold())
                }
            }

            Text(recommendationDetail(for: lab, summary: summary, progression: progression))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Start 10 questions") {
                store.beginSession(
                    lab: lab,
                    source: .focused,
                    requestedItemCount: 10,
                    isTimed: summary.evidenceCount > 0
                        && (lab != .mentalMath || progression.timingEligible)
                        && store.profileSnapshot.timingMode != .untimed
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(NFTheme.controlTint(for: lab.colorToken))
            .foregroundStyle(NFTheme.controlForeground(for: lab.colorToken))
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .nfCard(cornerRadius: 24)
    }

    private func recommendationDetail(
        for lab: TrainingLab,
        summary: SkillSummary,
        progression: NFMentalMathProgressionStatus
    ) -> String {
        if lab == .mentalMath, summary.evidenceCount > 0 {
            return NFAppLocalization.localized(
                "\(progression.stage.title) stage · \(progression.nextGateDescription)",
                locale: NFAppLocalization.preferredLocale,
                comment: "Mental-math recommendation with progression stage and next requirement."
            )
        }
        if let priority = store.currentPriorityBreakdowns.first(where: { $0.lab == lab }),
           let reason = priority.reasons.first?.title {
            return reason
        }
        return summary.evidenceCount == 0
            ? NFAppLocalization.localized(
                "Start with an untimed session.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Recommendation before a learner has practice evidence."
            )
            : NFAppLocalization.localized(
                "Revisit this skill with a fresh set.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Recommendation when a learner already has practice evidence."
            )
    }

    private func summary(for lab: TrainingLab) -> SkillSummary {
        store.skillSummaries.first(where: { $0.lab == lab }) ?? SkillSummary(
            id: lab.skillID,
            lab: lab,
            theta: 0,
            uncertainty: 1,
            evidenceCount: 0,
            accuracy: nil,
            status: .unassessed,
            calibrationBias: nil,
            lastTrained: nil
        )
    }
}

private struct LabCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let lab: TrainingLab
    let summary: SkillSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                NFIconTile(symbol: lab.symbol, color: NFTheme.color(for: lab.colorToken), size: 48)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(lab.title)
                    .font(.headline)
                Text(lab.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
            Spacer(minLength: 0)
            HStack {
                Text(summary.status.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(
                    summary.evidenceCount == 0
                        ? "No practice yet"
                        : NFAppLocalization.formattedAnswerCount(summary.evidenceCount)
                )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .nfCard(cornerRadius: 20, padding: 16)
        .contentShape(Rectangle())
    }
}

private struct LabDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let lab: TrainingLab
    @State private var questionCount = 10
    @State private var mode = "Accuracy first"
    @State private var selectedSubskill: NFDefaultContentActivity?

    private var mentalMathProgression: NFMentalMathProgressionStatus {
        mentalMathProgressionStatus(from: store.attempts)
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 18) {
                        NFIconTile(symbol: lab.symbol, color: NFTheme.color(for: lab.colorToken), size: 66)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(lab.title)
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            Text(lab.subtitle)
                                .foregroundStyle(.secondary)
                        }
                    }

                    evidenceSummary

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Choose a focus").font(.title2.bold())
                        Text("Every bundled activity is available here; mixed practice continues to rotate formats automatically.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                            focusButton(nil, title: "Mixed practice", summary: lab.subtitle)
                            ForEach(trainSubskills(for: lab)) { skill in
                                focusButton(
                                    skill,
                                    title: skill.localizedTitle,
                                    summary: skill.localizedSummary
                                )
                            }
                        }

                        if let selectedSubskill {
                            selectedActivityEvidence(selectedSubskill)
                        }
                    }
                    .nfCard()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Practice setup").font(.title2.bold())
                        NFPracticeCountSelector(selection: $questionCount)
                        Picker("Mode", selection: $mode) {
                            Text("Accuracy first").tag("Accuracy first")
                            Text("Untimed").tag("Untimed")
                            if lab == .mentalMath {
                                Text(mentalMathProgression.timingEligible ? "Automaticity" : "Automaticity (locked)")
                                    .tag("Automaticity")
                                    .disabled(!mentalMathProgression.timingEligible)
                                if selectedSubskill == nil {
                                    Text(mentalMathProgression.transferEligible ? "Transfer mix" : "Transfer mix (locked)")
                                        .tag("Transfer mix")
                                        .disabled(!mentalMathProgression.transferEligible)
                                }
                            } else if selectedSubskill == nil && lab != .transfer {
                                Text("Transfer mix").tag("Transfer mix")
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedSubskill) { _, activity in
                            if activity != nil && mode == "Transfer mix" {
                                mode = "Accuracy first"
                            }
                        }

                        Button {
                            startPractice()
                        } label: {
                            Label(
                                selectedSubskill.map {
                                    NFAppLocalization.localized(
                                        "Start \($0.localizedTitle) practice",
                                        locale: NFAppLocalization.preferredLocale,
                                        comment: "Button that starts focused practice for the selected subskill."
                                    )
                                } ?? NFAppLocalization.localized(
                                    "Start mixed practice",
                                    locale: NFAppLocalization.preferredLocale,
                                    comment: "Button that starts a mixed focused-practice session."
                                ),
                                systemImage: "play.fill"
                            )
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NFTheme.controlTint(for: lab.colorToken))
                        .foregroundStyle(NFTheme.controlForeground(for: lab.colorToken))
                        .controlSize(.large)

                        if store.profileSnapshot.timingMode == .untimed {
                            Label(
                                "Your global Untimed preference applies to every focused session, including Accuracy first and Transfer mix.",
                                systemImage: "timer"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }

                        if lab == .mentalMath {
                            Label(
                                "\(mentalMathProgression.stage.title) stage · \(mentalMathProgression.nextGateDescription)",
                                systemImage: mentalMathProgression.timingEligible ? "timer" : "lock.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }

                        if lab == .retrieval {
                            Button {
                                if store.documents.isEmpty {
                                    store.requestSourceReviewDocumentImport()
                                } else {
                                    store.requestSourceReviews()
                                }
                            } label: {
                                Label(
                                    store.documents.isEmpty ? "Import and start source review" : "Review a saved source",
                                    systemImage: store.documents.isEmpty ? "doc.badge.plus" : "text.book.closed.fill"
                                )
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityHint(store.documents.isEmpty
                                ? "Opens the file picker, indexes your source locally, then continues into retrieval practice."
                                : "Opens the next cited source-review excerpt.")
                        }
                    }
                    .nfCard()

                    evidenceCard
                }
                .padding(20)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(lab.shortTitle)
    }

    private func startPractice() {
        let isTimed = store.profileSnapshot.timingMode != .untimed
            && mode != "Untimed"
            && mode != "Accuracy first"
            && (lab != .mentalMath || mentalMathProgression.timingEligible)
        if let selectedSubskill {
            let field = store.profileSnapshot.fields
                .sorted { $0.rawValue < $1.rawValue }
                .first ?? .general
            store.beginDefaultCatalogSession(
                NFDefaultContentSelection(activity: selectedSubskill, field: field),
                requestedItemCount: questionCount,
                isTimed: isTimed
            )
            return
        }
        store.beginSession(
            lab: lab,
            source: .focused,
            evidenceClass: mode == "Transfer mix"
                && lab != .transfer
                && (lab != .mentalMath || mentalMathProgression.transferEligible)
                ? .appliedTransfer
                : .practice,
            targetDifficulty: mode == "Accuracy first" ? 0.4 : 0.58,
            requestedItemCount: questionCount,
            isTimed: isTimed
        )
    }

    private func focusButton(
        _ skill: NFDefaultContentActivity?,
        title: String,
        summary: String
    ) -> some View {
        let isSelected = selectedSubskill == skill
        return Button {
            selectedSubskill = skill
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : (skill?.kind.symbol ?? "shuffle"))
                        .foregroundStyle(isSelected ? NFTheme.foregroundColor(for: lab.colorToken) : .secondary)
                    Text(LocalizedStringKey(title))
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                Text(LocalizedStringKey(summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                if let skill {
                    Text(skill.kind.title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(NFTheme.foregroundColor(for: lab.colorToken))
                        .textCase(.uppercase)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(
                isSelected ? NFTheme.color(for: lab.colorToken).opacity(0.12) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
        .nfSelectionAccessibility(isSelected)
    }

    private func selectedActivityEvidence(_ activity: NFDefaultContentActivity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Label(
                activity.researchBasis.localizedTitle,
                systemImage: "checkmark.shield.fill"
            )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NFTheme.indigoForeground)
            Text(activity.researchBasis.localizedNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(activity.researchBasis.references) { reference in
                Link(destination: reference.url) {
                    Label(reference.shortCitation, systemImage: "arrow.up.right.square")
                }
                .font(.caption)
            }
        }
        .padding(.top, 4)
    }

    private var evidenceSummary: some View {
        let summary = store.skillSummaries.first(where: { $0.lab == lab })
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                evidenceMetric(
                    value: summary?.status.title ?? NFAppLocalization.localized("Unassessed", locale: NFAppLocalization.preferredLocale, comment: "Training-module status before the learner has recorded assessment evidence."),
                    label: "Current level"
                )
                Divider().frame(height: 38)
                evidenceMetric(value: "\(summary?.evidenceCount ?? 0)", label: "Answers", monospaced: true)
                Divider().frame(height: 38)
                evidenceMetric(
                    value: summary?.accuracy.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
                    label: "Practice accuracy",
                    monospaced: true
                )
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 12) {
                evidenceMetric(
                    value: summary?.status.title ?? NFAppLocalization.localized("Unassessed", locale: NFAppLocalization.preferredLocale, comment: "Training-module status before the learner has recorded assessment evidence."),
                    label: "Current level"
                )
                Divider()
                evidenceMetric(value: "\(summary?.evidenceCount ?? 0)", label: "Answers", monospaced: true)
                Divider()
                evidenceMetric(
                    value: summary?.accuracy.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
                    label: "Practice accuracy",
                    monospaced: true
                )
            }
        }
        .nfCard()
    }

    private func evidenceMetric(value: String, label: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(value))
                .font(monospaced ? .headline.monospacedDigit() : .headline)
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var evidenceCard: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("This lab trains \(lab.subtitle.lowercased()). Progress is based on completed practice; unfamiliar tasks are checked separately.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    MethodologyLibraryView(initialLab: lab)
                } label: {
                    Label("Read method and limitations", systemImage: "text.book.closed.fill")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        } label: {
            Label("About this lab", systemImage: "text.book.closed")
                .font(.headline)
        }
        .nfCard()
    }

}

struct NFPracticeCountSelector: View {
    @Binding var selection: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let choices = [5, 10, 20, 30]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Questions")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(choices, id: \.self) { count in
                    let isSelected = selection == count
                    Button {
                        selection = count
                    } label: {
                        Text(NFAppLocalization.formattedQuestionCount(count))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                isSelected ? NFTheme.controlTint : Color.primary.opacity(0.055),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? Color.clear : Color.primary.opacity(0.12)
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NFAppLocalization.formattedQuestionCount(count))
                    .nfSelectionAccessibility(isSelected)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Number of questions")
        .accessibilityValue(
            NFAppLocalization.localized(
                "\(NFAppLocalization.formattedQuestionCount(selection)) selected",
                locale: NFAppLocalization.preferredLocale,
                comment: "Selected question count in the focused-practice picker."
            )
        )
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        return Array(
            repeating: GridItem(.flexible(minimum: 68), spacing: 8),
            count: count
        )
    }
}

private struct NFDefaultContentBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedLab: TrainingLab?
    @State private var selectedKind: NFDefaultActivityKind?
    @State private var selectedField: STEMField
    let excludedLabs: Set<TrainingLab>
    let onSelect: (NFDefaultContentSelection) -> Void

    init(
        excludedLabs: Set<TrainingLab>,
        defaultField: STEMField,
        onSelect: @escaping (NFDefaultContentSelection) -> Void
    ) {
        self.excludedLabs = excludedLabs
        self.onSelect = onSelect
        _selectedField = State(initialValue: defaultField)
    }

    private var availableActivities: [NFDefaultContentActivity] {
        NFDefaultContentCatalog.activities.filter { !excludedLabs.contains($0.lab) }
    }

    private var visibleActivities: [NFDefaultContentActivity] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let activities = query.isEmpty
            ? availableActivities.filter {
                (selectedLab == nil || $0.lab == selectedLab)
                    && (selectedKind == nil || $0.kind == selectedKind)
            }
            : NFDefaultContentCatalog.search(
                query,
                lab: selectedLab,
                kind: selectedKind
            )
        return activities.filter { !excludedLabs.contains($0.lab) }
    }

    private var availableLabs: [TrainingLab] {
        TrainingLab.allCases.filter { !excludedLabs.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Offline activity catalog")
                                .font(.title.bold())
                            Text(NFAppLocalization.localized(
                                "\(visibleActivities.count) of \(availableActivities.count) activity families",
                                locale: NFAppLocalization.preferredLocale,
                                comment: "Filtered result count in the deterministic practice catalog."
                            ))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { filters }
                            VStack(alignment: .leading, spacing: 10) { filters }
                        }
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                        if visibleActivities.isEmpty {
                            ContentUnavailableView {
                                Label("No matching activities", systemImage: "magnifyingglass")
                            } description: {
                                Text("Try another skill, lab, or activity type.")
                            } actions: {
                                Button("Reset search and filters") {
                                    searchText = ""
                                    selectedLab = nil
                                    selectedKind = nil
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity, minHeight: 360)
                        } else {
                            ForEach(visibleActivities) { activity in
                                Button {
                                    onSelect(NFDefaultContentSelection(activity: activity, field: selectedField))
                                } label: {
                                    activityRow(activity)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        NavigationLink {
                            MethodologyLibraryView()
                        } label: {
                            Label("Read method and limitations", systemImage: "text.book.closed.fill")
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(20)
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Practice catalog")
            .searchable(text: $searchText, prompt: "Search activities and skills")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .nfDesktopPresentationFrame(minWidth: 430, idealWidth: 780, minHeight: 600, idealHeight: 820)
    }

    @ViewBuilder
    private var filters: some View {
        Picker("Lab", selection: $selectedLab) {
            Text("All labs").tag(nil as TrainingLab?)
            ForEach(availableLabs) { lab in
                Text(lab.shortTitle).tag(Optional(lab))
            }
        }
        .pickerStyle(.menu)

        Picker("Activity type", selection: $selectedKind) {
            Text("All activity types").tag(nil as NFDefaultActivityKind?)
            ForEach(NFDefaultActivityKind.allCases) { kind in
                Text(kind.title).tag(Optional(kind))
            }
        }
        .pickerStyle(.menu)

        Picker("Field", selection: $selectedField) {
            ForEach(STEMField.allCases) { field in
                Text(field.title).tag(field)
            }
        }
        .pickerStyle(.menu)
    }

    private func activityRow(_ activity: NFDefaultContentActivity) -> some View {
        HStack(alignment: .top, spacing: 14) {
            NFIconTile(
                symbol: activity.kind.symbol,
                color: NFTheme.color(for: activity.lab.colorToken),
                size: 46
            )
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(activity.localizedTitle)
                        .font(.headline)
                    Spacer(minLength: 6)
                    Text(activity.kind.title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(NFTheme.foregroundColor(for: activity.lab.colorToken))
                        .textCase(.uppercase)
                }
                Text(activity.localizedSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Text(activity.lab.shortTitle)
                    Text("·")
                    Text(selectedField.title)
                    Text("·")
                    Text(NFAppLocalization.formattedMinutes(activity.recommendedMinutes, style: .compact))
                    if !activity.researchBasis.references.isEmpty {
                        Text("·")
                        Text(activity.researchBasis.references.map(\.shortCitation).joined(separator: ", "))
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(NFTheme.foregroundColor(for: activity.lab.colorToken))
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 17))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Starts an untimed five-minute focused session.")
    }
}

private struct LabSample: Sendable {
    let id: String
    let prompt: String
    let context: String
    let choices: [String]
    let correctIndex: Int
    let explanation: String

    static func sample(for lab: TrainingLab) -> LabSample {
        switch lab {
        case .spatial:
            LabSample(id: "sp.rotate.coordinate.v1", prompt: "Rotate the point (2, 1) by 90° counterclockwise about the origin.", context: "Coordinate transformation", choices: ["(−1, 2)", "(1, −2)", "(−2, −1)", "(2, −1)"], correctIndex: 0, explanation: "A 90° counterclockwise rotation maps (x, y) to (−y, x).")
        case .quantitative:
            LabSample(id: "qnt.base_rate.v1", prompt: "A condition affects 1 in 100 people. A test catches 90% of cases and has a 5% false-positive rate. Which fact most limits a positive result?", context: "Base-rate reasoning", choices: ["The condition is rare", "Sensitivity is below 100%", "The sample is large", "The units are percentages"], correctIndex: 0, explanation: "When the base rate is low, false positives among many unaffected people can outnumber true positives.")
        case .scientificReasoning:
            LabSample(id: "sci.confound.v1", prompt: "Students choose either an online or in-person course. The online group scores higher. What blocks a causal conclusion?", context: "Experimental design", choices: ["Self-selection into course format", "The outcome is numerical", "Two groups were compared", "The scores have a mean"], correctIndex: 0, explanation: "Self-selection can make baseline motivation or preparation differ between groups.")
        case .logicDebugging:
            LabSample(id: "logic.edge.v1", prompt: "A loop checks indices 0 through count inclusive. What is the first issue to test?", context: "Boundary reasoning", choices: ["Out-of-bounds at index count", "The loop is too fast", "The syntax uses an integer", "The array needs sorting"], correctIndex: 0, explanation: "For count elements, the last valid zero-based index is count − 1.")
        case .retrieval:
            LabSample(id: "ret.structure.v1", prompt: "Which review best tests retention rather than immediate familiarity?", context: "Retrieval scheduling", choices: ["An alternate prompt after a delay", "The same prompt immediately", "Rereading the answer", "Highlighting the paragraph"], correctIndex: 0, explanation: "A delayed alternate form reduces cue familiarity and better probes retention.")
        case .transfer:
            LabSample(id: "trf.representation.v1", prompt: "A graph and an equation describe the same exponential decay. What makes this a transfer check?", context: "Representation shift", choices: ["The underlying relation is preserved while the representation changes", "The colors differ", "Both contain numbers", "The task is timed"], correctIndex: 0, explanation: "Transfer keeps the target structure while changing surface cues or representation.")
        case .mentalMath:
            LabSample(id: "mm.tool.v1", prompt: "Which task most clearly calls for an estimate before an exact tool result?", context: "Tool judgment", choices: ["Auditing a simulation output", "Recalling 7 × 8", "Naming an axis", "Reading a title"], correctIndex: 0, explanation: "An independent magnitude estimate can expose a precise but implausible output.")
        }
    }
}

struct DeterministicLabPracticeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let lab: TrainingLab
    var evidenceClass: EvidenceClass = .practice
    var source: SessionSource = .focused
    @State private var selectedIndex: Int?
    @State private var stage = 0
    @State private var saved = false
    @State private var saveError: String?

    private var sample: LabSample { .sample(for: lab) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        NFStatusPill(text: sample.context, symbol: lab.symbol, color: NFTheme.color(for: lab.colorToken))
                        Text(LocalizedStringKey(sample.prompt))
                            .font(.system(.title, design: .rounded, weight: .bold))

                        if stage == 0 {
                            ForEach(sample.choices.indices, id: \.self) { index in
                                Button {
                                    selectedIndex = index
                                    stage = 1
                                } label: {
                                    HStack {
                                        Text(LocalizedStringKey(sample.choices[index]))
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        Image(systemName: "circle")
                                    }
                                    .padding(16)
                                    .frame(maxWidth: .infinity)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                                }
                                .buttonStyle(.plain)
                            }
                        } else if stage == 1 {
                            Text("How confident are you?")
                                .font(.title2.bold())
                            ForEach(ConfidenceLevel.allCases) { confidence in
                                Button(confidence.title) {
                                    commit(confidence)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            Label(selectedIndex == sample.correctIndex ? "Correct" : "Revisit the key distinction", systemImage: selectedIndex == sample.correctIndex ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                                .font(.title2.bold())
                                .foregroundStyle(selectedIndex == sample.correctIndex ? NFTheme.mintForeground : NFTheme.amberForeground)
                            Text(LocalizedStringKey(sample.explanation))
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .nfCard()
                            Button("Done") { dismiss() }
                                .buttonStyle(.borderedProminent)
                                .tint(NFTheme.controlTint(for: lab.colorToken))
                                .foregroundStyle(NFTheme.controlForeground(for: lab.colorToken))
                                .controlSize(.large)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(lab.shortTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Save interrupted", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(LocalizedStringKey(saveError ?? ""))
            }
        }
        .nfDesktopPresentationFrame(minWidth: 360, minHeight: 560)
        .interactiveDismissDisabled(stage > 0 && stage < 2)
    }

    private func commit(_ confidence: ConfidenceLevel) {
        guard let selectedIndex else { return }
        do {
            try store.saveLabAttempt(
                lab: lab,
                itemID: sample.id,
                prompt: sample.prompt,
                response: sample.choices[selectedIndex],
                correctAnswer: sample.choices[sample.correctIndex],
                isCorrect: selectedIndex == sample.correctIndex,
                confidence: confidence,
                evidenceClass: evidenceClass,
                source: source
            )
            saved = true
            stage = 2
        } catch {
            saveError = "The response remains on screen so you can retry."
        }
    }
}
