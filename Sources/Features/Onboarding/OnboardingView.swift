import SwiftUI

#if os(iOS)
import UIKit
#endif

enum NFOnboardingKeyboardFocusTarget: Hashable {
  case primaryAction
  case context(String)
  case goal(String)
  case duration(Int)
  case timing(String)
}

enum NFOnboardingKeyboardFocusPolicy {
  static func defaultTarget(forStepRawValue rawValue: Int) -> NFOnboardingKeyboardFocusTarget {
    switch rawValue {
    case 1: .context(STEMField.general.rawValue)
    case 2: .duration(5)
    default: .primaryAction
    }
  }
}

struct OnboardingView: View {
  let onComplete: (OnboardingDraft) -> Bool

  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State private var showsSample = false
  @State private var sampleRequestsSetup = false
  @State private var showsRestore = false
  @State private var draft = OnboardingDraft()
  @State private var step: OnboardingStep = .welcome
  @FocusState private var keyboardFocus: NFOnboardingKeyboardFocusTarget?
  @AppStorage("nf.onboarding.step") private var savedStepRaw = 0
  @AppStorage("nf.onboarding.draft") private var savedDraftJSON = ""

  var body: some View {
    ZStack {
      AppBackground()

      VStack(spacing: 0) {
        navigationHeader
          .frame(maxWidth: 760)
          .padding(.horizontal, onboardingHorizontalPadding)
          .padding(.top, 18)
          .padding(.bottom, 14)
          .frame(maxWidth: .infinity)
          .background(.ultraThinMaterial)
          .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
          }

        GeometryReader { viewport in
          ScrollViewReader { scrollProxy in
            ScrollView {
              VStack(spacing: 0) {
                Color.clear
                  .frame(height: 1)
                  .id(OnboardingScrollAnchor.pageTop)

                page
                  .frame(
                    width: min(
                      760,
                      max(0, viewport.size.width - (onboardingHorizontalPadding * 2))
                    ),
                    alignment: .leading
                  )
                  .padding(.horizontal, onboardingHorizontalPadding)
                  .padding(.top, step == .welcome ? 18 : 24)
                  .padding(.bottom, 24)
                  .accessibilityIdentifier("onboarding-step-\(step.rawValue + 1)")
              }
              .frame(width: viewport.size.width)
            }
            .scrollIndicators(.hidden)
            .onChange(of: step) { _, _ in
              scrollProxy.scrollTo(OnboardingScrollAnchor.pageTop, anchor: .top)
            }
          }
        }
      }
    }
    .accessibilityIdentifier("onboarding-root")
    .sheet(isPresented: $showsSample, onDismiss: {
      guard sampleRequestsSetup else { return }
      sampleRequestsSetup = false
      if step == .welcome { goForward() }
    }) {
      NFOnboardingSampleView {
        sampleRequestsSetup = true
        showsSample = false
      }
    }
    .sheet(isPresented: $showsRestore) {
      NavigationStack { SettingsView() }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      actionBar
        .frame(maxWidth: 760)
        .padding(.horizontal, onboardingHorizontalPadding)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
          Divider().opacity(0.45)
        }
    }
    .tint(NFTheme.indigoForeground)
    .environment(\.locale, NFAppLocalization.locale(identifier: draft.preferredLanguageCode))
    .animation(shouldReduceMotion ? nil : .snappy(duration: 0.32), value: step)
    .onAppear {
      restoreDraft()
      focusDefaultControl()
    }
    .onChange(of: step) { _, value in
      savedStepRaw = value.rawValue
      focusDefaultControl()
    }
    .onChange(of: draft) { _, value in
      if let data = try? JSONEncoder().encode(value), let encoded = String(data: data, encoding: .utf8) {
        savedDraftJSON = encoded
      }
    }
    .onChange(of: draft.preferredLanguageCode) { _, languageCode in
      NFAppLocalization.setPreferredLanguageCode(languageCode)
    }
  }

  private var shouldReduceMotion: Bool {
    systemReduceMotion || draft.reducedMotion
  }

  private var onboardingHorizontalPadding: CGFloat {
    horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize ? 16 : 24
  }

  private var navigationHeader: some View {
    VStack(spacing: 12) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) {
          navigationLeadingItem
          Spacer()
          stepLabel
        }
        VStack(alignment: .leading, spacing: 8) {
          navigationLeadingItem
          stepLabel
        }
      }

      ProgressView(
        value: Double(step.rawValue + 1),
        total: Double(OnboardingStep.allCases.count)
      )
      .tint(NFTheme.indigoForeground)
      .accessibilityLabel("Onboarding progress")
      .accessibilityValue("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }
  }

  @ViewBuilder
  private var navigationLeadingItem: some View {
    if step == .welcome {
      Label("NeuroForge", systemImage: "atom")
        .font(.headline.weight(.semibold))
        .foregroundStyle(NFTheme.indigoForeground)
    } else {
      Button(action: goBack) {
        Label("Back", systemImage: "chevron.left")
      }
      .buttonStyle(.plain)
      .font(.subheadline.weight(.semibold))
      .accessibilityHint("Returns to the previous setup step without clearing your choices")
    }
  }

  private var stepLabel: some View {
    Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .contentTransition(.numericText())
  }

  @ViewBuilder
  private var page: some View {
    switch step {
    case .welcome:
      welcomePage
        .transition(pageTransition)
    case .focus:
      profilePage
        .transition(pageTransition)
    case .routine:
      schedulePage
        .transition(pageTransition)
    }
  }

  private var pageTransition: AnyTransition {
    shouldReduceMotion
      ? .opacity
      : .asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
      )
  }

  private var actionBar: some View {
    VStack(spacing: 8) {
      if step == .routine {
        Button { finishOnboarding(startBaseline: false) } label: {
          onboardingPrimaryActionLabel(
            title: "Start practice",
            symbol: "play.fill"
          )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding-primary-action")
        .focused($keyboardFocus, equals: .primaryAction)
        .keyboardShortcut(.defaultAction)

        Button { finishOnboarding(startBaseline: true) } label: {
          Text("Take a short skill check")
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("onboarding-skill-check-action")
      } else {
        Button(action: { if step == .welcome { showsSample = true } else { goForward() } }) {
          onboardingPrimaryActionLabel(
            title: step == .welcome ? "Try a sample" : "Continue",
            symbol: dynamicTypeSize.isAccessibilitySize ? nil : "arrow.right"
          )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding-primary-action")
        .disabled(!canContinue)
        .focused($keyboardFocus, equals: .primaryAction)
        .keyboardShortcut(.defaultAction)
        if step == .welcome {
          Button("Set up my practice", action: goForward).buttonStyle(.borderless)
          Button("Restore a backup") { showsRestore = true }.buttonStyle(.borderless)
        }
      }
    }
  }

  private var welcomePage: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 14) {
        ZStack {
          RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
              LinearGradient(
                colors: [NFTheme.indigo, NFTheme.cyan],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(width: 64, height: 64)

          Image(systemName: "atom")
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(.white)
            .accessibilityHidden(true)
        }

        VStack(alignment: .leading, spacing: 10) {
          Text("Build an all-round STEM toolkit.")
            .font(.system(.title, design: .rounded, weight: .bold))
            .lineLimit(nil)
            .multilineTextAlignment(.leading)

          Text(
            "Train six practical abilities through short daily circuits, then apply them across the subjects you care about."
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(nil)
          .multilineTextAlignment(.leading)
        }
      }

      VStack(spacing: 9) {
        WelcomeRow(
          symbol: "circle.hexagongrid.fill",
          color: NFTheme.indigo,
          title: "Six connected abilities",
          detail: "Number sense, quantitative thinking, spatial reasoning, scientific evidence, logic and debugging, and research recall."
        )
        WelcomeRow(
          symbol: "arrow.triangle.2.circlepath",
          color: NFTheme.cyan,
          title: "One adaptive daily circuit",
          detail: "Recall, practice, apply, and reflect in a circuit that fits the time and energy you have."
        )
        WelcomeRow(
          symbol: "shield.checkered",
          color: NFTheme.mint,
          title: "Progress without punishment",
          detail: "Completed practice builds momentum. Rest days and lower-energy sessions never erase what you have earned."
        )
      }
    }
  }

  private var profilePage: some View {
    VStack(alignment: .leading, spacing: 24) {
      NFSectionHeader(
        "Shape your balanced practice",
        eyebrow: "Your circuit",
        subtitle: "Your routine keeps broad STEM coverage over time. Choose contexts and emphasis areas to make it yours."
      )

      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text("STEM contexts")
            .font(.headline)
          Text("Choose the subjects that should frame examples. They do not limit the abilities you train.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        FlowLayout(spacing: 9) {
          ForEach(STEMField.allCases) { field in
            ChoiceChip(
              title: field.title,
              symbol: fieldSymbol(field),
              isSelected: draft.fields.contains(field),
              action: { toggleField(field) }
            )
            .focused($keyboardFocus, equals: .context(field.rawValue))
          }
        }
      }
      .nfCard()

      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Emphasis areas")
            .font(.headline)
          Text("Choose what should receive extra attention. The full STEM foundation stays in your training mix.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        FlowLayout(spacing: 9) {
          ForEach(TrainingGoal.allCases) { goal in
            ChoiceChip(
              title: goal.title,
              symbol: goalSymbol(goal),
              isSelected: draft.goals.contains(goal),
              action: { toggleGoal(goal) }
            )
            .focused($keyboardFocus, equals: .goal(goal.rawValue))
          }
        }
      }
      .nfCard()
    }
  }

  private var schedulePage: some View {
    VStack(alignment: .leading, spacing: 24) {
      Text("Start with a short session. Your next practice will adjust as you answer.").font(.headline)
      NFSectionHeader(
        "Set your daily circuit",
        eyebrow: "Your rhythm",
        subtitle: "Choose a length and pace you can sustain. You can adjust either later."
      )

      VStack(alignment: .leading, spacing: 16) {
        Text("Circuit length")
          .font(.headline)

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
          ForEach([5, 10, 15, 20], id: \.self) { minutes in
            DurationButton(
              minutes: minutes,
              isSelected: draft.dailyDuration == minutes,
              action: { draft.dailyDuration = minutes }
            )
            .focused($keyboardFocus, equals: .duration(minutes))
          }
        }
      }
      .nfCard()

      VStack(alignment: .leading, spacing: 16) {
        Text("Pace")
          .font(.headline)

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
          ForEach(TimingMode.allCases) { mode in
            let isSelected = draft.timingMode == mode
            Button {
              draft.timingMode = mode
            } label: {
              HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(isSelected ? NFTheme.indigoForeground : .secondary)
                  .accessibilityHidden(true)
                Text(mode.title)
                  .foregroundStyle(.primary)
                  .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
              }
              .padding(12)
              .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
              .background(
                isSelected ? NFTheme.indigo.opacity(0.12) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
              )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mode.title)
            .nfSelectionAccessibility(isSelected)
            .focused($keyboardFocus, equals: .timing(mode.rawValue))
          }
        }

        Text(timingDescription(draft.timingMode))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .nfCard()

    }
  }

  private var canContinue: Bool {
    true
  }

  private func onboardingPrimaryActionLabel(
    title: LocalizedStringKey,
    symbol: String?
  ) -> some View {
    HStack(spacing: 10) {
      if let symbol {
        Image(systemName: symbol)
          .accessibilityHidden(true)
      }
      Text(title)
        .lineLimit(2)
        .multilineTextAlignment(.center)
    }
    .font(.headline.weight(.semibold))
    .foregroundStyle(.white)
    .padding(.horizontal, 14)
    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 10 : 12)
    .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 56 : 50)
    .background(
      NFTheme.indigo,
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func goForward() {
    guard canContinue, let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
    step = next
  }

  private func goBack() {
    guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
    step = previous
  }

  private func finishOnboarding(startBaseline: Bool) {
    draft.startBaselineImmediately = startBaseline
    guard onComplete(draft) else { return }
    savedStepRaw = 0
    savedDraftJSON = ""
  }

  private func restoreDraft() {
    step = savedStepRaw <= 0 ? .welcome : savedStepRaw == 1 ? .focus : .routine
    guard let data = savedDraftJSON.data(using: .utf8), let restored = try? JSONDecoder().decode(OnboardingDraft.self, from: data) else { return }
    draft = restored
  }

  private func focusDefaultControl() {
    let target = NFOnboardingKeyboardFocusPolicy.defaultTarget(forStepRawValue: step.rawValue)
    Task { @MainActor in
      await Task.yield()
      keyboardFocus = target
    }
  }

  private func toggleField(_ field: STEMField) {
    if draft.fields.contains(field) {
      draft.fields.remove(field)
      if draft.fields.isEmpty {
        draft.fields = [.general]
      }
    } else if field == .general {
      draft.fields = [.general]
    } else {
      draft.fields.remove(.general)
      draft.fields.insert(field)
    }
  }

  private func toggleGoal(_ goal: TrainingGoal) {
    if draft.goals.contains(goal) {
      if draft.goals.count > 1 {
        draft.goals.remove(goal)
      }
    } else {
      draft.goals.insert(goal)
    }
  }

  private func fieldSymbol(_ field: STEMField) -> String {
    switch field {
    case .general: "atom"
    case .mathematics: "function"
    case .physics: "waveform.path.ecg"
    case .computing: "cpu"
    case .engineering: "gearshape.2.fill"
    case .lifeSciences: "leaf.fill"
    case .chemistry: "flask.fill"
    case .dataScience: "chart.xyaxis.line"
    }
  }

  private func goalSymbol(_ goal: TrainingGoal) -> String {
    switch goal {
    case .mentalMath: "function"
    case .problemSolving: "puzzlepiece.fill"
    case .researchReading: "text.book.closed.fill"
    case .dataReasoning: "chart.bar.xaxis"
    case .experimentalDesign: "flask.fill"
    case .programming: "chevron.left.forwardslash.chevron.right"
    case .spatialReasoning: "cube.transparent"
    }
  }

  private func timingDescription(_ mode: TimingMode) -> String {
    switch mode {
    case .untimed:
      NFAppLocalization.localized("Focus on accuracy and strategy; speed will not be rated.", locale: NFAppLocalization.preferredLocale, comment: "Description of the untimed training preference.")
    case .adaptive:
      NFAppLocalization.localized("Adds short timed sets only when they are useful, while keeping accuracy first.", locale: NFAppLocalization.preferredLocale, comment: "Description of the adaptive timing preference.")
    case .speedFocus:
      NFAppLocalization.localized("Some practice sets emphasize efficient responding; skill checks and reflection stay untimed.", locale: NFAppLocalization.preferredLocale, comment: "Description of the speed-focus training preference.")
    }
  }

}

private enum OnboardingStep: Int, CaseIterable {
  case welcome
  case focus
  case routine
}

private enum OnboardingScrollAnchor: Hashable {
  case pageTop
}

struct NFInputCalibrationPanel: View {
  private enum TrialPhase: Equatable {
    case idle
    case waiting(mode: NFPreferredAnswerMode, trial: Int)
    case responding(mode: NFPreferredAnswerMode, trial: Int)

    var activeMode: NFPreferredAnswerMode? {
      switch self {
      case .idle: nil
      case let .waiting(mode, _), let .responding(mode, _): mode
      }
    }
  }

  @Binding var draft: OnboardingDraft
  @State private var phase: TrialPhase = .idle
  @State private var cueStartedAt: Date?
  @State private var samplesByMode: [String: [Double]] = [:]
  @State private var statusByMode: [String: String] = [:]
  @State private var cueTask: Task<Void, Never>?

  private let trialCount = NFInputCalibrationMetrics.requiredTrialCount

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Picker("Preferred answer mode", selection: $draft.preferredAnswerMode) {
        ForEach(availableAnswerModes) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.menu)

      Text("Start a sample and wait for the “Respond now” cue. Complete three trials; early responses are discarded so the result measures your input more reliably.")
        .font(.footnote)
        .foregroundStyle(.secondary)

      calibrationRow(
        mode: .keyboard,
        symbol: "keyboard",
        title: "Keyboard",
        value: draft.keyboardLatencyMilliseconds
      )
      calibrationRow(
        mode: .touch,
        symbol: "hand.tap.fill",
        title: "Touch or pointer",
        value: draft.touchLatencyMilliseconds
      )
      if supportsPencilCalibration {
        calibrationRow(
          mode: .pencil,
          symbol: "pencil.tip",
          title: "Apple Pencil (optional)",
          value: draft.pencilLatencyMilliseconds
        )
        Text("Apple Pencil calibration is offered only on supported iPads. Each sample must be activated with the Pencil tip; finger, pointer, keyboard, and assistive activations are not recorded as Pencil input.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(nil)
          .multilineTextAlignment(.leading)
      }

      if draft.hasInputCalibrationSample {
        Label {
          Text("At least one local input sample is recorded.")
            .foregroundStyle(.primary)
        } icon: {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(NFTheme.mintForeground)
            .accessibilityHidden(true)
        }
        .font(.footnote.weight(.semibold))
      } else {
        Label("Optional — you can run this later in Settings.", systemImage: "clock")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .nfCard()
    .onAppear {
      if draft.preferredAnswerMode == .pencil, !supportsPencilCalibration {
        draft.preferredAnswerMode = .adaptive
      }
    }
    .onDisappear {
      cueTask?.cancel()
    }
  }

  private func calibrationRow(
    mode: NFPreferredAnswerMode,
    symbol: String,
    title: String,
    value: Double?
  ) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        calibrationIdentity(symbol: symbol, title: title, value: value, mode: mode)
        Spacer(minLength: 8)
        calibrationButton(mode: mode, hasValue: value != nil)
      }
      VStack(alignment: .leading, spacing: 10) {
        calibrationIdentity(symbol: symbol, title: title, value: value, mode: mode)
        calibrationButton(mode: mode, hasValue: value != nil)
      }
    }
    .padding(12)
    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private func calibrationIdentity(
    symbol: String,
    title: String,
    value: Double?,
    mode: NFPreferredAnswerMode
  ) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol)
        .foregroundStyle(NFTheme.indigoForeground)
        .frame(width: 28)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold))
        Text(value.map {
          NFAppLocalization.localized("Median sample \($0.formatted(.number.precision(.fractionLength(0)))) ms",
            locale: NFAppLocalization.preferredLocale,
            comment: "Input-calibration status; the placeholder is the median response time in milliseconds."
          )
        } ?? NFAppLocalization.localized("Not sampled", locale: NFAppLocalization.preferredLocale, comment: "Input-calibration status before a sample is recorded."))
          .font(.caption)
          .foregroundStyle(.secondary)
        if let status = statusByMode[mode.rawValue] {
          Text(status)
            .font(.caption)
            .foregroundStyle(status.hasPrefix("Too early") ? NFTheme.amberForeground : .secondary)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
        }
      }
    }
  }

  @ViewBuilder
  private func calibrationButton(mode: NFPreferredAnswerMode, hasValue: Bool) -> some View {
    #if os(iOS)
    if mode == .pencil {
      NFPencilVerifiedCalibrationButton(
        title: NFAppLocalization.localizedCatalogValue(
          buttonTitle(for: mode, hasValue: hasValue),
          locale: NFAppLocalization.preferredLocale
        ),
        hint: NFAppLocalization.localizedCatalogValue(
          buttonHint(for: mode),
          locale: NFAppLocalization.preferredLocale
        ),
        isEnabled: phase.activeMode == nil || phase.activeMode == mode,
        onPencilActivation: { handleCalibrationAction(for: mode) },
        onUnverifiedActivation: { rejectUnverifiedPencilActivation() }
      )
      .frame(minWidth: 88, minHeight: 44)
    } else {
      standardCalibrationButton(mode: mode, hasValue: hasValue)
    }
    #else
    standardCalibrationButton(mode: mode, hasValue: hasValue)
    #endif
  }

  private func standardCalibrationButton(mode: NFPreferredAnswerMode, hasValue: Bool) -> some View {
    Button {
      handleCalibrationAction(for: mode)
    } label: {
      Text(LocalizedStringKey(buttonTitle(for: mode, hasValue: hasValue)))
        .frame(minWidth: 88)
    }
    .buttonStyle(.bordered)
    .tint(isResponding(mode) ? NFTheme.mintForeground : NFTheme.controlTint)
    .disabled(phase.activeMode != nil && phase.activeMode != mode)
    .accessibilityHint(Text(LocalizedStringKey(buttonHint(for: mode))))
  }

  private func rejectUnverifiedPencilActivation() {
    statusByMode[NFPreferredAnswerMode.pencil.rawValue] = NFAppLocalization.localized(
      "Apple Pencil was not detected. Touch this button directly with the Pencil tip; this attempt was not recorded.",
      locale: NFAppLocalization.preferredLocale,
      comment: "Input-calibration feedback when the Pencil-specific control receives another input type."
    )
  }

  private func buttonTitle(for mode: NFPreferredAnswerMode, hasValue: Bool) -> String {
    switch phase {
    case let .waiting(activeMode, _) where activeMode == mode: "Wait for cue"
    case let .responding(activeMode, _) where activeMode == mode: "Respond now"
    default: hasValue ? "Re-run three trials" : "Start three trials"
    }
  }

  private func buttonHint(for mode: NFPreferredAnswerMode) -> String {
    switch phase {
    case let .waiting(activeMode, _) where activeMode == mode:
      "Wait until this control says Respond now. Activating early discards the trial."
    case let .responding(activeMode, _) where activeMode == mode:
      "Activate immediately to record this response-latency trial."
    default:
      "Starts three local response-latency trials with randomized cues."
    }
  }

  private func isResponding(_ mode: NFPreferredAnswerMode) -> Bool {
    if case let .responding(activeMode, _) = phase { return activeMode == mode }
    return false
  }

  private func handleCalibrationAction(for mode: NFPreferredAnswerMode) {
    switch phase {
    case .idle:
      samplesByMode[mode.rawValue] = []
      scheduleCue(for: mode, trial: 1)
    case let .waiting(activeMode, trial) where activeMode == mode:
      cueTask?.cancel()
      cueStartedAt = nil
      phase = .idle
      statusByMode[mode.rawValue] = NFAppLocalization.localized(
        "Too early. Trial \(trial) was discarded; start again when you are ready.",
        locale: NFAppLocalization.preferredLocale,
        comment: "Input-calibration feedback after an anticipatory response; the placeholder is the discarded trial number."
      )
    case let .responding(activeMode, trial) where activeMode == mode:
      recordResponse(for: mode, trial: trial)
    default:
      break
    }
  }

  private func scheduleCue(for mode: NFPreferredAnswerMode, trial: Int) {
    cueTask?.cancel()
    cueStartedAt = nil
    phase = .waiting(mode: mode, trial: trial)
    statusByMode[mode.rawValue] = NFAppLocalization.localized(
      "Trial \(trial) of \(trialCount). Wait for the cue.",
      locale: NFAppLocalization.preferredLocale,
      comment: "Input-calibration waiting status; placeholders are current and total trial counts."
    )
    let delayMilliseconds = Int.random(in: 900...1_800)
    cueTask = Task { @MainActor in
      do {
        try await Task.sleep(for: .milliseconds(delayMilliseconds))
      } catch {
        return
      }
      guard phase == .waiting(mode: mode, trial: trial) else { return }
      cueStartedAt = Date()
      phase = .responding(mode: mode, trial: trial)
      statusByMode[mode.rawValue] = NFAppLocalization.localized(
        "Respond now — trial \(trial) of \(trialCount).",
        locale: NFAppLocalization.preferredLocale,
        comment: "Input-calibration response cue; placeholders are current and total trial counts."
      )
    }
  }

  private func recordResponse(for mode: NFPreferredAnswerMode, trial: Int) {
    guard let cueStartedAt else { return }
    let milliseconds = min(60_000, max(0, Date().timeIntervalSince(cueStartedAt) * 1_000))
    var samples = samplesByMode[mode.rawValue, default: []]
    samples.append(milliseconds)
    samplesByMode[mode.rawValue] = samples
    self.cueStartedAt = nil

    if samples.count < trialCount {
      scheduleCue(for: mode, trial: trial + 1)
      return
    }

    let median = NFInputCalibrationMetrics.median(samples)
    switch mode {
    case .keyboard: draft.keyboardLatencyMilliseconds = median
    case .touch: draft.touchLatencyMilliseconds = median
    case .pencil: draft.pencilLatencyMilliseconds = median
    case .adaptive: break
    }
    phase = .idle
    statusByMode[mode.rawValue] = NFAppLocalization.localized(
      "Complete. Median \(median.formatted(.number.precision(.fractionLength(0)))) ms; spread \(NFInputCalibrationMetrics.spread(samples).formatted(.number.precision(.fractionLength(0)))) ms.",
      locale: NFAppLocalization.preferredLocale,
      comment: "Completed input-calibration result; placeholders are median response time and trial spread in milliseconds."
    )
  }

  private var availableAnswerModes: [NFPreferredAnswerMode] {
    NFPreferredAnswerMode.allCases.filter { $0 != .pencil || supportsPencilCalibration }
  }

  private var supportsPencilCalibration: Bool {
    NFInputCalibrationCapabilities.supportsPencil
  }
}

enum NFInputCalibrationCapabilities {
  @MainActor
  static var supportsPencil: Bool {
    #if os(iOS) && !targetEnvironment(macCatalyst)
    canOfferPencilCalibration(
      isIOS: true,
      isPad: UIDevice.current.userInterfaceIdiom == .pad,
      isMacCatalyst: false
    )
    #else
    false
    #endif
  }

  static func canOfferPencilCalibration(
    isIOS: Bool,
    isPad: Bool,
    isMacCatalyst: Bool
  ) -> Bool {
    isIOS && isPad && !isMacCatalyst
  }
}

#if os(iOS)
private struct NFPencilVerifiedCalibrationButton: UIViewRepresentable {
  let title: String
  let hint: String
  let isEnabled: Bool
  let onPencilActivation: () -> Void
  let onUnverifiedActivation: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
      onPencilActivation: onPencilActivation,
      onUnverifiedActivation: onUnverifiedActivation
    )
  }

  func makeUIView(context: Context) -> NFPencilOnlyButton {
    let button = NFPencilOnlyButton(type: .system)
    button.configuration = .bordered()
    button.activationHandler = context.coordinator.handleActivation
    button.setContentHuggingPriority(.required, for: .horizontal)
    return button
  }

  func updateUIView(_ button: NFPencilOnlyButton, context: Context) {
    context.coordinator.onPencilActivation = onPencilActivation
    context.coordinator.onUnverifiedActivation = onUnverifiedActivation
    button.setTitle(title, for: .normal)
    button.accessibilityLabel = title
    button.accessibilityHint = hint
    button.isEnabled = isEnabled
  }

  @MainActor
  final class Coordinator {
    var onPencilActivation: () -> Void
    var onUnverifiedActivation: () -> Void

    init(onPencilActivation: @escaping () -> Void, onUnverifiedActivation: @escaping () -> Void) {
      self.onPencilActivation = onPencilActivation
      self.onUnverifiedActivation = onUnverifiedActivation
    }

    func handleActivation(isVerifiedPencil: Bool) {
      if isVerifiedPencil {
        onPencilActivation()
      } else {
        onUnverifiedActivation()
      }
    }
  }
}

@MainActor
private final class NFPencilOnlyButton: UIButton {
  var activationHandler: ((Bool) -> Void)?
  private var beganWithPencil = false

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    beganWithPencil = touches.contains { $0.type == .pencil }
    super.touchesBegan(touches, with: event)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    let endedInside = touches.contains { bounds.contains($0.location(in: self)) }
    let verified = beganWithPencil && endedInside && touches.contains { $0.type == .pencil }
    super.touchesEnded(touches, with: event)
    beganWithPencil = false
    if endedInside { activationHandler?(verified) }
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    beganWithPencil = false
    super.touchesCancelled(touches, with: event)
  }

  override func accessibilityActivate() -> Bool {
    activationHandler?(false)
    return true
  }
}
#endif

enum NFInputCalibrationMetrics {
  static let requiredTrialCount = 3

  static func median(_ samples: [Double]) -> Double {
    let sorted = samples.sorted()
    guard !sorted.isEmpty else { return 0 }
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
      return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
  }

  static func spread(_ samples: [Double]) -> Double {
    guard let minimum = samples.min(), let maximum = samples.max() else { return 0 }
    return maximum - minimum
  }
}

private struct WelcomeRow: View {
  let symbol: String
  let color: Color
  let title: String
  let detail: String

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      NFIconTile(symbol: symbol, color: color, size: 36)
      VStack(alignment: .leading, spacing: 3) {
        Text(LocalizedStringKey(title))
          .font(.headline)
        Text(LocalizedStringKey(detail))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(nil)
          .multilineTextAlignment(.leading)
      }
      Spacer(minLength: 0)
    }
    .padding(11)
    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}

private struct ChoiceChip: View {
  let title: String
  let symbol: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        Image(systemName: symbol)
          .accessibilityHidden(true)
        Text(LocalizedStringKey(title))
        if isSelected {
          Image(systemName: "checkmark")
            .font(.caption.weight(.bold))
            .accessibilityHidden(true)
        }
      }
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(isSelected ? NFTheme.indigoForeground : .primary)
      .padding(.horizontal, 13)
      .padding(.vertical, 9)
      .background(
        isSelected ? NFTheme.indigo.opacity(0.13) : Color.primary.opacity(0.045),
        in: Capsule()
      )
      .overlay {
        Capsule()
          .strokeBorder(
            isSelected ? NFTheme.indigo.opacity(0.55) : Color.primary.opacity(0.09),
            lineWidth: 1
          )
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .nfSelectionAccessibility(isSelected)
  }
}

private struct DurationButton: View {
  let minutes: Int
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Text("\(minutes)")
          .font(.title2.weight(.bold))
          .contentTransition(.numericText())
        Text("minutes")
          .font(.caption)
      }
      .foregroundStyle(isSelected ? Color.white : Color.primary)
      .frame(maxWidth: .infinity, minHeight: 66)
      .background(
        isSelected ? NFTheme.indigo : Color.primary.opacity(0.05),
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.08))
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(NFAppLocalization.formattedMinutes(minutes))
    .nfSelectionAccessibility(isSelected)
  }
}
