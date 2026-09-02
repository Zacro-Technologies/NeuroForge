import SwiftUI

struct InputCalibrationSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: OnboardingDraft
    @State private var saveError: String?
    @State private var isShowingResetConfirmation = false
    @State private var isShowingDiscardConfirmation = false
    @AccessibilityFocusState private var saveErrorIsFocused: Bool
    private let originalDraft: OnboardingDraft

    init(draft: OnboardingDraft) {
        _draft = State(initialValue: draft)
        originalDraft = draft
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        NFSectionHeader(
                            "Input calibration",
                            eyebrow: "Local equipment check",
                            subtitle: calibrationSubtitle,
                            headingLevel: .h1
                        )
                        previousCalibrationCard
                        NFInputCalibrationPanel(draft: $draft)
                        if let saveError {
                            Label {
                                Text(saveError)
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(NFTheme.roseForeground)
                                    .accessibilityHidden(true)
                            }
                            .font(.footnote)
                            .accessibilityFocused($saveErrorIsFocused)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Input calibration")
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
                ToolbarItem {
                    Button("Reset calibration", role: .destructive) {
                        isShowingResetConfirmation = true
                    }
                    .disabled(store.latestInputCalibration == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try store.saveInputCalibration(
                                preferredAnswerMode: draft.preferredAnswerMode,
                                keyboardLatencyMilliseconds: draft.keyboardLatencyMilliseconds,
                                touchLatencyMilliseconds: draft.touchLatencyMilliseconds,
                                pencilLatencyMilliseconds: draft.pencilLatencyMilliseconds
                            )
                            dismiss()
                        } catch {
                            saveError = NFAppLocalization.localized(
                                "The calibration remains unchanged. Try again."
                            )
                            saveErrorIsFocused = true
                        }
                    }
                    .disabled(!draft.hasInputCalibrationSample)
                }
            }
        }
        .nfDesktopPresentationFrame(
            minWidth: 420,
            idealWidth: 760,
            minHeight: 560,
            idealHeight: 760
        )
        .nfGuardsUnsavedEditor(
            isDirty,
            title: NFAppLocalization.localized("Input calibration", comment: "Dirty-editor name used in the global navigation warning.")
        )
        .confirmationDialog(
            "Discard calibration changes?",
            isPresented: $isShowingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard changes", role: .destructive) { dismiss() }
        } message: {
            Text("New input samples and answer-mode changes will be lost.")
        }
        .alert("Reset saved input calibration?", isPresented: $isShowingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset calibration", role: .destructive) {
                resetCalibration()
            }
        } message: {
            Text("This clears the active latency samples and returns the preferred answer mode to adaptive. Correctness, mastery, answers, and prior exported records are unchanged.")
        }
    }

    private var calibrationSubtitle: String {
        if NFInputCalibrationCapabilities.supportsPencil {
            return "Re-run three-trial samples after changing a keyboard, pointer, touch setup, or Apple Pencil. These measurements never change correctness or mastery."
        }
        return "Re-run three-trial samples after changing a keyboard, pointer, or touch setup. These measurements never change correctness or mastery."
    }

    private var isDirty: Bool { draft != originalDraft }

    @ViewBuilder
    private var previousCalibrationCard: some View {
        if let calibration = store.latestInputCalibration {
            VStack(alignment: .leading, spacing: 10) {
                Text("Saved calibration")
                    .font(.headline)
                    .accessibilityHeading(.h2)
                Text(calibrationDate(calibration.completedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                comparisonRow(
                    "Keyboard",
                    previous: calibration.keyboardLatencyMilliseconds,
                    proposed: draft.keyboardLatencyMilliseconds
                )
                comparisonRow(
                    "Touch or pointer",
                    previous: calibration.touchLatencyMilliseconds,
                    proposed: draft.touchLatencyMilliseconds
                )
                if NFInputCalibrationCapabilities.supportsPencil {
                    comparisonRow(
                        "Apple Pencil",
                        previous: calibration.pencilLatencyMilliseconds,
                        proposed: draft.pencilLatencyMilliseconds
                    )
                }
                Text("New samples replace the active median only after you choose Save.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .nfCard()
        } else {
            Label("No saved calibration. Input remains adaptive.", systemImage: "gauge.with.dots.needle.0percent")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .nfCard()
        }
    }

    private func comparisonRow(
        _ title: String,
        previous: Double?,
        proposed: Double?
    ) -> some View {
        LabeledContent(LocalizedStringKey(title)) {
            Text(comparisonText(previous: previous, proposed: proposed))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func comparisonText(previous: Double?, proposed: Double?) -> String {
        let previousText = latencyText(previous)
        let proposedText = latencyText(proposed)
        guard previousText != proposedText else { return previousText }
        return NFAppLocalization.localized(
            "Saved \(previousText) → new \(proposedText)",
            locale: NFAppLocalization.preferredLocale,
            comment: "Input-calibration comparison between saved and newly measured latency."
        )
    }

    private func latencyText(_ value: Double?) -> String {
        guard let value else {
            return NFAppLocalization.localized("Not sampled", locale: NFAppLocalization.preferredLocale, comment: "Input-calibration status before a sample is recorded.")
        }
        return NFAppLocalization.localized(
            "\(value.formatted(.number.precision(.fractionLength(0)))) ms",
            locale: NFAppLocalization.preferredLocale,
            comment: "Input-calibration response time in milliseconds."
        )
    }

    private func calibrationDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = NFAppLocalization.preferredLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func resetCalibration() {
        do {
            try store.saveInputCalibration(
                preferredAnswerMode: .adaptive,
                keyboardLatencyMilliseconds: nil,
                touchLatencyMilliseconds: nil,
                pencilLatencyMilliseconds: nil
            )
            draft.preferredAnswerMode = .adaptive
            draft.keyboardLatencyMilliseconds = nil
            draft.touchLatencyMilliseconds = nil
            draft.pencilLatencyMilliseconds = nil
            saveError = nil
        } catch {
            saveError = NFAppLocalization.localized(
                "The saved calibration was not reset. Try again."
            )
            saveErrorIsFocused = true
        }
    }
}
