import SwiftUI

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: OnboardingDraft
    @State private var saveError: String?
    @State private var isShowingDiscardConfirmation = false
    private let originalDraft: OnboardingDraft
    let onSave: (OnboardingDraft) throws -> Void

    init(draft: OnboardingDraft, onSave: @escaping (OnboardingDraft) throws -> Void) {
        _draft = State(initialValue: draft)
        originalDraft = draft
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        NFSectionHeader(
                            "Profile & training preferences",
                            eyebrow: "Editable at any time",
                            subtitle: "Changes affect future scheduling and field context. They never rewrite past attempts or assessment evidence."
                        )

                        VStack(alignment: .leading, spacing: 14) {
                            Picker("Stage", selection: $draft.stage) {
                                ForEach(Stage.allCases) { Text($0.title).tag($0) }
                            }.pickerStyle(.menu)
                            Picker("Preferred language", selection: $draft.preferredLanguageCode) {
                                Text("English").tag("en")
                                Text("日本語").tag("ja")
                            }
                            .pickerStyle(.segmented)
                            .accessibilityLabel(Text("Preferred language"))
                            .accessibilityValue(
                                Text(draft.preferredLanguageCode == "ja" ? "日本語" : "English")
                            )
                        }.nfCard()

                        selectableSection("STEM fields", subtitle: "Questions can draw from these subjects.") {
                            ForEach(STEMField.allCases) { field in
                                profileChip(field.title, selected: draft.fields.contains(field)) { toggleField(field) }
                            }
                        }

                        selectableSection("Training goals", subtitle: "The app uses these to prioritize your practice.") {
                            ForEach(TrainingGoal.allCases) { goal in
                                profileChip(goal.title, selected: draft.goals.contains(goal)) { toggleGoal(goal) }
                            }
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            Text("Training shape").font(.title2.bold())
                            Picker("Daily duration", selection: $draft.dailyDuration) {
                                ForEach([5, 10, 15, 20], id: \.self) {
                                    Text(NFAppLocalization.formattedMinutes($0, style: .compact)).tag($0)
                                }
                            }.pickerStyle(.segmented)
                            Picker("Timing", selection: $draft.timingMode) {
                                ForEach(TimingMode.allCases) { Text($0.title).tag($0) }
                            }.pickerStyle(.menu)
                            Picker("Training-day boundary", selection: $draft.dayBoundaryHour) {
                                ForEach([0, 2, 4, 6, 8, 10, 12], id: \.self) { hour in
                                    Text(NFTrainingDayBoundaryFormatter.title(for: hour)).tag(hour)
                                }
                            }.pickerStyle(.menu)
                            Text("Activity before this hour belongs to the prior training day. Saving a change rebuilds the current not-yet-started plan.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Full-plan days").font(.subheadline.weight(.semibold))
                            FlowLayout(spacing: 8) {
                                ForEach(Array(zip([1, 2, 3, 4, 5, 6, 7], localizedWeekdaySymbols)), id: \.0) { day, label in
                                    profileChip(label, selected: draft.trainingDays.contains(day)) { toggleDay(day) }
                                }
                            }
                        }.nfCard()

                        VStack(spacing: 0) {
                            Toggle(isOn: $draft.reducedMotion) { Label("Reduce motion", systemImage: "figure.walk.motion") }.padding(14)
                            Divider()
                            Toggle(isOn: $draft.hideTimers) { Label("Hide timers", systemImage: "timer") }.padding(14)
                            Divider()
                            Toggle(isOn: $draft.excludeVisualSpatial) { Label("Exclude visual-spatial tasks", systemImage: "eye.slash.fill") }.padding(14)
                        }.nfCard(padding: 0)

                        Text("Excluding visual-spatial work updates today’s unstarted plan. Other changes apply to your next plan.")
                            .font(.footnote).foregroundStyle(.secondary)

                        Button("Save") { saveAndDismiss() }
                            .buttonStyle(.borderedProminent)
                            .tint(NFTheme.controlTint(for: "indigo"))
                            .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                            .disabled(!canSave)
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Edit profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            isShowingDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndDismiss() }
                        .disabled(!canSave)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
        .environment(\.locale, Locale(identifier: draft.preferredLanguageCode))
        .nfDesktopPresentationFrame(
            minWidth: 420,
            idealWidth: 800,
            minHeight: 620,
            idealHeight: 850
        )
        .nfGuardsUnsavedEditor(
            isDirty,
            title: NFAppLocalization.localized("Profile editor", comment: "Dirty-editor name used in the global navigation warning.")
        )
        .confirmationDialog(
            "Discard profile changes?",
            isPresented: $isShowingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard changes", role: .destructive) { dismiss() }
        } message: {
            Text("Your unsaved profile and training preference changes will be lost.")
        }
        .alert("Preferences not saved", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(saveError ?? "Try saving again."))
        }
    }

    private var canSave: Bool {
        !draft.fields.isEmpty && !draft.goals.isEmpty && !draft.trainingDays.isEmpty
    }

    private var isDirty: Bool { draft != originalDraft }

    private var localizedWeekdaySymbols: [String] {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: draft.preferredLanguageCode)
        return calendar.shortWeekdaySymbols
    }

    private func saveAndDismiss() {
        do {
            try onSave(draft)
            saveError = nil
            dismiss()
        } catch {
            saveError = NFAppLocalization.localized(
                "Your changes remain on screen. Try saving again.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Profile editor save failure that keeps the learner's draft visible."
            )
        }
    }

    private func selectableSection<Content: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(title)).font(.title2.bold())
            Text(LocalizedStringKey(subtitle)).font(.subheadline).foregroundStyle(.secondary)
            FlowLayout(spacing: 8) { content() }
        }.nfCard()
    }

    private func profileChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                Text(LocalizedStringKey(title))
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 11).padding(.vertical, 8)
            .foregroundStyle(selected ? NFTheme.indigoForeground : .primary)
            .background(selected ? NFTheme.indigo.opacity(0.12) : .primary.opacity(0.04), in: Capsule())
        }
        .frame(minHeight: 44)
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .nfSelectionAccessibility(selected)
    }

    private func toggleField(_ field: STEMField) {
        if draft.fields.contains(field) {
            if draft.fields.count > 1 { draft.fields.remove(field) }
        } else if field == .general {
            draft.fields = [.general]
        } else {
            draft.fields.remove(.general)
            draft.fields.insert(field)
        }
    }

    private func toggleGoal(_ goal: TrainingGoal) {
        if draft.goals.contains(goal) {
            if draft.goals.count > 1 { draft.goals.remove(goal) }
        } else { draft.goals.insert(goal) }
    }

    private func toggleDay(_ day: Int) {
        if draft.trainingDays.contains(day) {
            if draft.trainingDays.count > 1 { draft.trainingDays.remove(day) }
        } else { draft.trainingDays.insert(day) }
    }
}
