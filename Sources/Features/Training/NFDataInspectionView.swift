import Charts
import SwiftUI

/// A chart is authorized by a specific retained data contract. Arbitrary tables
/// are not interpreted as categorical measurements or stripped of their units.
struct NFInspectableDataProjection: Equatable, Sendable {
    struct Point: Identifiable, Equatable, Sendable {
        let id: Int
        let label: String
        let count: Int
        let originalValue: String
    }

    let headers: [String]
    let points: [Point]
    let accessibilitySummary: String
    let localeIdentifier: String
    var verticalRange: ClosedRange<Double> { 0...Double(max(1, points.map(\.count).max() ?? 1)) }

    static func make(exercise: NFExercise, representation: NFExerciseRepresentation) -> Self? {
        // This shipped contract states that these two exhaustive outcomes are
        // observation counts. Its response remains a separate percentage.
        guard !exercise.assessmentProtected, [.practice, .documentPractice].contains(exercise.purpose), exercise.evidenceClass == exercise.purpose.evidenceClass,
              exercise.availabilityReason == nil, exercise.schemaVersion == 2,
              exercise.lab == .quantitative, exercise.generatorVersion == 4,
              exercise.provenance.generatorID == "nf.exercise.fallback",
              exercise.provenance.generatorVersion == 4,
              exercise.templateID == "nf.fallback.quantitative.\(exercise.purpose == .practice ? "practice" : "document").v4.observed.proportion",
              exercise.independentRepresentations.contains(representation),
              case let .table(headers, rows, summary) = representation,
              headers.count == 2, rows.count == 2, rows.allSatisfy({ $0.count == 2 }),
              headers.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(rows.map { $0[0] }).count == rows.count else { return nil }
        var points: [Point] = []
        for (index, row) in rows.enumerated() {
            let raw = row[1]
            guard !row[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }),
                  let count = Int(raw), (1...1_000_000).contains(count) else { return nil }
            points.append(.init(id: index, label: row[0], count: count, originalValue: raw))
        }
        return .init(headers: headers, points: points, accessibilitySummary: summary,
            localeIdentifier: exercise.localeIdentifier)
    }

    func inspect(id: Int?) -> Point? { points.first { $0.id == id } }
    func inspect(label: String?) -> Point? { points.first { $0.label == label } }
}

/// Marks, point inspection and the accessible table share the same original
/// count values. Selection is view state and has no response/scoring binding.
struct NFDataInspectionView: View {
    let data: NFInspectableDataProjection
    var controlledPointID: Int? = nil
    var onSelect: ((Int) -> Void)? = nil
    var highlightPointID: Int? = nil
    var onBeginInspection: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedCategory: String?
    @State private var tableExpanded = false

    private var selectedPoint: NFInspectableDataProjection.Point? {
        (onSelect == nil ? data.inspect(label: selectedCategory) : data.inspect(id: controlledPointID)) ?? data.points.first
    }
    private var locale: Locale { Locale(identifier: data.localeIdentifier) }
    private var countAxis: String {
        NFAppLocalization.localized("Count (observations)", locale: locale,
            comment: "Vertical axis for an observed-proportion chart; values are observation counts, not percentages.")
    }
    private var selection: Binding<Int> {
        Binding(get: { selectedPoint?.id ?? 0 }, set: { id in select(id) })
    }

    private var categorySelection: Binding<String?> {
        Binding(get: { selectedPoint?.label }, set: { label in
            if let point = data.inspect(label: label) { select(point.id) }
        })
    }
    private func select(_ id: Int) {
        guard let point = data.inspect(id: id) else { return }
        onBeginInspection?()
        if let onSelect { onSelect(id) } else { selectedCategory = point.label }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(data.accessibilitySummary).font(.subheadline)
            Chart(data.points) { point in
                BarMark(x: .value(data.headers[0], point.label), y: .value(countAxis, point.count))
                    .foregroundStyle(NFTheme.indigo)
                    .opacity(point.id == (highlightPointID ?? selectedPoint?.id) ? 1 : 0.65)
            }
            .chartYScale(domain: data.verticalRange)
            .chartXAxisLabel(data.headers[0])
            .chartYAxisLabel(countAxis)
            .chartXSelection(value: categorySelection)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 260 : 200)
            .accessibilityLabel(Text(data.accessibilitySummary))
            .accessibilityValue(Text(NFAppLocalization.localized(
                "The vertical scale starts at zero and shows observation counts. Inspect either outcome for its exact value.",
                locale: locale, comment: "Nonvisual explanation of an observation-count chart and its inspection controls.")))
            .accessibilityIdentifier("session-data-chart")

            Menu {
                ForEach(data.points) { point in
                    Button { select(point.id) } label: {
                        if point.id == selectedPoint?.id {
                            Label(point.label, systemImage: "checkmark")
                        } else {
                            Text(point.label)
                        }
                    }
                }
            } label: {
                HStack {
                    Text("Inspect outcome")
                    Spacer()
                    Text(selectedPoint?.label ?? "")
                    Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityIdentifier("session-data-inspection")
            if let point = selectedPoint {
                VStack(alignment: .leading, spacing: 6) {
                    Text(point.label).font(.headline)
                    Text(NFAppLocalization.localized("\(point.originalValue) observations", locale: locale,
                        comment: "Exact observation count for the selected data outcome; the value comes from the retained table."))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("session-data-inspected-point")
            }

            // Scope this identifier to the header: DisclosureGroup propagates
            // an outer identifier over its independently accessible data rows.
            Button { tableExpanded.toggle() } label: {
                HStack {
                    Text("Data table")
                    Spacer()
                    Image(systemName: tableExpanded ? "chevron.down" : "chevron.right")
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityIdentifier("session-data-table")
            .accessibilityValue(Text(tableExpanded ? "Expanded" : "Collapsed"))
            if tableExpanded {
                ForEach(data.points) { point in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(point.label).font(.headline)
                        Text(countAxis).font(.caption).foregroundStyle(.secondary)
                        Text(point.originalValue)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("session-data-row-\(point.id)")
                }
            }
        }
        .nfCard(cornerRadius: 16, padding: 16)
        .onChange(of: data) { _, _ in selectedCategory = nil; tableExpanded = false }
        .onChange(of: tableExpanded) { _, expanded in if expanded { onBeginInspection?() } }
    }
}


/// This explanation is admitted only for the shipped exact part/whole recipe.
/// Rows remain observation counts; the separately scored quantity is a percent.
struct NFObservedProportionExplanation: Equatable, Sendable {
    let data: NFInspectableDataProjection
    let criterionPointID: Int
    let qualifyingCount: Int
    let otherCount: Int
    var totalCount: Int { qualifyingCount + otherCount }

    static func make(exercise: NFExercise) -> Self? {
        guard !exercise.assessmentProtected, case let .numeric(schema) = exercise.interaction,
              schema.answer.canonicalUnit == "%", schema.answer.unitRequired else { return nil }
        let candidates = exercise.independentRepresentations.compactMap {
            NFInspectableDataProjection.make(exercise: exercise, representation: $0)
        }
        guard candidates.count == 1, let data = candidates.first, data.points.count == 2,
              let expected = try? NFExactNumber(numerator: Int64(100 * data.points[0].count),
                  denominator: Int64(data.points[0].count + data.points[1].count)),
              expected == schema.answer.authoritativeValue else { return nil }
        return .init(data: data, criterionPointID: data.points[0].id,
            qualifyingCount: data.points[0].count, otherCount: data.points[1].count)
    }
}

/// Exact local learning state. The first prediction is frozen before assistance
/// appears, independently of the editable, ultimately scored answer.
struct NFDataInspectionDraft: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let policyVersion: String
    let exerciseDigest: String
    var selectedPointID: Int
    var predictionText: String = ""
    var firstPrediction: NFNumericSubmission? = nil
    var predictionLockedAtActiveSeconds: Double? = nil
    var overlayRevealed = false
    var overlayExpanded = false
    static let policyVersion = "ObservedProportionInspectionV1"

    var supportCount: Int { overlayRevealed ? 1 : 0 }
    var isSupported: Bool {
        guard schemaVersion == 1, policyVersion == Self.policyVersion,
              exerciseDigest.count == 64, exerciseDigest.allSatisfy(\.isHexDigit),
              predictionText.count <= 500, selectedPointID >= 0,
              !overlayExpanded || overlayRevealed,
              overlayRevealed == (firstPrediction != nil),
              (firstPrediction == nil) == (predictionLockedAtActiveSeconds == nil) else { return false }
        if let firstPrediction {
            guard firstPrediction.value == predictionText, firstPrediction.unit == "%",
                  predictionLockedAtActiveSeconds.map(NFSessionDurationPolicy.isValid) == true else { return false }
        }
        return true
    }
    func isCompatible(with exercise: NFExercise) -> Bool {
        guard isSupported, !exercise.assessmentProtected,
              exerciseDigest == (try? NFLocalItemCheckpoint.digest(exercise)),
              let explanation = NFObservedProportionExplanation.make(exercise: exercise),
              explanation.data.inspect(id: selectedPointID) != nil else { return false }
        return firstPrediction == nil || predictionIsValid(for: exercise)
    }
    func predictionGuidance(for exercise: NFExercise) -> String? {
        guard !predictionText.isEmpty, case .numeric(let schema) = exercise.interaction else { return nil }
        return NFExerciseResponseValidator.validateNumeric(.init(value: predictionText, unit: "%"),
            schema: schema, localeIdentifier: exercise.localeIdentifier).issue?.guidance
    }
    func predictionIsValid(for exercise: NFExercise) -> Bool {
        guard predictionText.count <= 500, case .numeric(let schema) = exercise.interaction else { return false }
        return NFExerciseResponseValidator.validateNumeric(.init(value: predictionText, unit: "%"),
            schema: schema, localeIdentifier: exercise.localeIdentifier).isValid
    }
    func revealing(exercise: NFExercise, activeSeconds: Double) -> Self? {
        guard !overlayRevealed, isCompatible(with: exercise), predictionIsValid(for: exercise),
              NFSessionDurationPolicy.isValid(activeSeconds) else { return nil }
        var next = self
        next.firstPrediction = .init(value: predictionText, unit: "%")
        next.predictionLockedAtActiveSeconds = activeSeconds
        next.overlayRevealed = true; next.overlayExpanded = true
        return next
    }
    func selecting(pointID: Int, exercise: NFExercise) -> Self? {
        guard isCompatible(with: exercise),
              NFObservedProportionExplanation.make(exercise: exercise)?.data.inspect(id: pointID) != nil else { return nil }
        var next = self; next.selectedPointID = pointID; return next
    }
    static func initial(for exercise: NFExercise) -> Self? {
        guard let explanation = NFObservedProportionExplanation.make(exercise: exercise),
              let digest = try? NFLocalItemCheckpoint.digest(exercise) else { return nil }
        return .init(policyVersion: policyVersion, exerciseDigest: digest, selectedPointID: explanation.criterionPointID)
    }
    func recoveryText(exercise: NFExercise) -> String? {
        guard isCompatible(with: exercise), !predictionText.isEmpty else { return nil }
        return NFAppLocalization.localized("Your predicted percentage: \(predictionText)", locale: NFAppLocalization.preferredLocale,
            comment: "Copyable original predicted percentage, kept apart from the final answer.")
    }
}

struct NFDataInspectionHistoryProjection: Equatable, Sendable {
    let draft: NFDataInspectionDraft
    let explanation: NFObservedProportionExplanation
    static func make(exercise: NFExercise?, draft: NFDataInspectionDraft?, isProtected: Bool) -> Self? {
        guard !isProtected, let exercise, !exercise.assessmentProtected,
              let draft, draft.isCompatible(with: exercise),
              let explanation = NFObservedProportionExplanation.make(exercise: exercise) else { return nil }
        return .init(draft: draft, explanation: explanation)
    }
}


/// Separate optional assistance; the original final-answer field remains the
/// only scored response. No explanation is constructed before a saved reveal.
struct NFDataPredictionView: View {
    let draft: NFDataInspectionDraft
    let exercise: NFExercise
    let canEdit: Bool
    let setPrediction: (String) -> Void
    let reveal: () -> Void
    let toggleOverlay: () -> Void
    var focusResetToken: UUID? = nil
    @FocusState private var predictionIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let prediction = draft.firstPrediction {
                LabeledContent("Prediction saved before explanation (%)", value: prediction.value)
                    .accessibilityIdentifier("session-data-saved-prediction")
                Button(LocalizedStringKey(draft.overlayExpanded ? "Hide denominator explanation" : "Show saved denominator explanation"), action: toggleOverlay)
                    .buttonStyle(.bordered).disabled(!canEdit)
            } else {
                Text("Predict before using the explanation").font(.headline)
                Text("Your prediction stays saved while you revise your final answer.").font(.subheadline)
                HStack(alignment: .firstTextBaseline) {
                    TextField("Predicted percentage", text: Binding(get: { draft.predictionText }, set: { setPrediction($0) }))
                        .textFieldStyle(.roundedBorder).font(.title2.monospacedDigit()).frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .focused($predictionIsFocused)
                        .simultaneousGesture(TapGesture().onEnded { predictionIsFocused = true })
                        .accessibilityIdentifier("session-data-prediction-input")
                        .onSubmit { if draft.predictionIsValid(for: exercise) { revealPrediction() } }
                    Text("%").accessibilityLabel("Percent")
                }.disabled(!canEdit)
                if let guidance = draft.predictionGuidance(for: exercise) {
                    Text(guidance).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Save prediction and inspect denominator", action: revealPrediction)
                    .buttonStyle(.bordered).disabled(!canEdit || !draft.predictionIsValid(for: exercise))
                    .accessibilityIdentifier("session-data-reveal-denominator")
                Text("This explanation is recorded as support. It does not change final-answer credit.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if draft.overlayExpanded, draft.overlayRevealed,
               let explanation = NFObservedProportionExplanation.make(exercise: exercise) {
                NFDataDenominatorExplanationView(explanation: explanation, requestsFocus: true)
                    .accessibilityIdentifier("session-data-denominator-explanation")
            }
        }.nfCard(cornerRadius: 16, padding: 16)
            .onChange(of: focusResetToken) { _, _ in predictionIsFocused = false }
    }
    private func revealPrediction() {
        predictionIsFocused = false
        reveal()
    }
}

struct NFDataDenominatorExplanationView: View {
    let explanation: NFObservedProportionExplanation
    var requestsFocus = false
    @AccessibilityFocusState private var headingFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Use the complete sample as the denominator").font(.headline)
                .accessibilityHeading(.h2).accessibilityFocused($headingFocused)
            Text("\(explanation.qualifyingCount) + \(explanation.otherCount) = \(explanation.totalCount) observations in the whole sample.")
            Text("\(explanation.qualifyingCount) of those \(explanation.totalCount) observations meet the criterion.")
            Text("For the percentage, divide \(explanation.qualifyingCount) by \(explanation.totalCount), then multiply by 100.")
            Text("Counts describe the bars. Percent describes the share of the complete sample.")
                .font(.subheadline).foregroundStyle(.secondary)
        }.accessibilityElement(children: .contain)
        .task {
            guard requestsFocus else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            headingFocused = true
        }
    }
}


/// A single typed point is shared by pointer, keyboard and assistive controls.
/// The chart never stores an independent pixel-position answer.
struct NFGraphConstructionEditor: View {
    let graph: NFGraphConstructionContract
    let response: NFExerciseResponse
    let canEdit: Bool
    let revealsExpected: Bool
    let updateResponse: (NFExerciseResponse) -> Bool
    @State private var editHistory = NFGraphConstructionEditHistory()
    @State private var isPlacingPoint = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var point: NFGraphConstructionContract.Point? { graph.point(from: response) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Construct one point").font(.headline)
                .accessibilityIdentifier("session-graph-construction")
            Text("The horizontal axis shows time in seconds; the vertical axis shows distance in meters. Both scales start at zero. Time grid lines are 1 second apart and distance grid lines are 5 meters apart. Coordinates adjust in one-unit steps.")
                .font(.subheadline)
            Text("Choose Move point on grid to enable one drag. The grid returns to scrolling after you place the point. Coordinate controls are always available.")
                .font(.footnote).foregroundStyle(.secondary)
            NFGraphConstructionPlot(graph: graph, point: point,
                expected: revealsExpected ? graph.expectedPoint : nil, canEdit: canEdit,
                pointerEnabled: isPlacingPoint,
                updatePoint: { apply($0) })
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 340 : 280)
            Button { isPlacingPoint.toggle() } label: {
                Text(isPlacingPoint ? "Cancel point placement" : "Move point on grid")
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.bordered).disabled(!canEdit)
            .accessibilityIdentifier("graph-enable-point-placement")
            Text("Given measurement: square. Your point: circle. The expected point appears as a diamond only after saving.")
                .font(.footnote).foregroundStyle(.secondary)
            ForEach(NFGraphConstructionContract.Axis.allCases, id: \.self) { axis in
                let title = axis == .x ? graph.xTitle : graph.yTitle
                let value = point.map { String(axis == .x ? $0.x : $0.y) } ?? "—"
                HStack(spacing: 8) {
                    LabeledContent(title, value: value).font(.body.monospacedDigit())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(title)).accessibilityValue(Text(value))
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: adjust(axis: axis, delta: 1)
                            case .decrement: adjust(axis: axis, delta: -1)
                            @unknown default: break
                            }
                        }
                        .accessibilityIdentifier("graph-adjust-" + axis.rawValue)
                    Button { adjust(axis: axis, delta: -1) } label: {
                        Image(systemName: "minus").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Decrease \(title)"))
                    .accessibilityValue(Text(value))
                    .accessibilityIdentifier("graph-adjust-" + axis.rawValue + "-decrement")
                    Button { adjust(axis: axis, delta: 1) } label: {
                        Image(systemName: "plus").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Increase \(title)"))
                    .accessibilityValue(Text(value))
                    .accessibilityIdentifier("graph-adjust-" + axis.rawValue + "-increment")
                }
                .buttonStyle(.bordered).disabled(!canEdit)
            }
            Button { apply(.init(x: 0, y: 0)) } label: {
                Text("Place point at the origin").frame(minHeight: 44).contentShape(Rectangle())
            }
                .buttonStyle(.bordered).disabled(!canEdit)
                .accessibilityIdentifier("graph-place-origin")
            Button {
                guard canEdit, let previous = editHistory.undo(current: response) else { return }
                if !updateResponse(previous) { editHistory = .init() }
            } label: {
                Text("Undo point change").frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.bordered).disabled(!canEdit || editHistory.edits.isEmpty)
            .accessibilityIdentifier("graph-undo-point")
            if let point { Text("Your point: (\(point.x) s, \(point.y) m)").font(.body.monospacedDigit()) }
            else { Text("No point has been placed on the grid.").foregroundStyle(.secondary) }
            NFGraphConstructionTable(graph: graph)
        }
        .nfCard(cornerRadius: 16, padding: 16)
        .onChange(of: response) { _, current in editHistory.synchronize(current: current) }
        .onChange(of: canEdit) { _, editable in if !editable { editHistory = .init(); isPlacingPoint = false } }
    }
    private func adjust(axis: NFGraphConstructionContract.Axis, delta: Int) {
        guard canEdit, let next = graph.adjusted(point, axis: axis, delta: delta) else { return }
        apply(next)
    }
    private func apply(_ next: NFGraphConstructionContract.Point) {
        guard canEdit else { return }
        isPlacingPoint = false
        let previous = response, updated = next.response
        if updateResponse(updated) { editHistory.record(previous: previous, next: updated) }
    }
}

private struct NFGraphConstructionTable: View {
    let graph: NFGraphConstructionContract
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Given data table").font(.headline)
            Text(graph.sourceDescription).font(.subheadline)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow { Text(graph.xTitle).bold(); Text(graph.yTitle).bold() }
                GridRow { Text(String(graph.baseline.x)); Text(String(graph.baseline.y)) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(graph.xTitle): \(graph.baseline.x); \(graph.yTitle): \(graph.baseline.y)"))
        }.accessibilityElement(children: .contain).accessibilityIdentifier("graph-source-table")
    }
}

private struct NFGraphConstructionPlot: View {
    let graph: NFGraphConstructionContract
    let point: NFGraphConstructionContract.Point?
    let expected: NFGraphConstructionContract.Point?
    let canEdit: Bool
    var pointerEnabled = false
    let updatePoint: (NFGraphConstructionContract.Point) -> Void
    @GestureState private var previewPoint: NFGraphConstructionContract.Point?
    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(x: 42, y: 24, width: max(1, proxy.size.width - 62), height: max(1, proxy.size.height - 62))
            Canvas { context, _ in
                guard graph.isSupported else { return }
                var grid = Path()
                for tick in 0...graph.maximumX {
                    let x = bounds.minX + CGFloat(tick) / CGFloat(graph.maximumX) * bounds.width
                    grid.move(to: .init(x: x, y: bounds.minY)); grid.addLine(to: .init(x: x, y: bounds.maxY))
                    context.draw(Text(String(tick)).font(.caption), at: .init(x: x, y: bounds.maxY + 14))
                }
                for tick in stride(from: 0, through: graph.maximumY, by: 5) {
                    let y = bounds.maxY - CGFloat(tick) / CGFloat(graph.maximumY) * bounds.height
                    grid.move(to: .init(x: bounds.minX, y: y)); grid.addLine(to: .init(x: bounds.maxX, y: y))
                    context.draw(Text(String(tick)).font(.caption), at: .init(x: bounds.minX - 16, y: y))
                }
                context.stroke(grid, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
                func location(_ value: NFGraphConstructionContract.Point) -> CGPoint {
                    .init(x: bounds.minX + CGFloat(value.x) / CGFloat(graph.maximumX) * bounds.width,
                        y: bounds.maxY - CGFloat(value.y) / CGFloat(graph.maximumY) * bounds.height)
                }
                let given = location(graph.baseline)
                context.fill(Path(CGRect(x: given.x - 5, y: given.y - 5, width: 10, height: 10)), with: .color(.secondary))
                if let expected, graph.contains(expected) {
                    let p = location(expected)
                    var diamond = Path(); diamond.addLines([.init(x: p.x, y: p.y - 11), .init(x: p.x + 11, y: p.y), .init(x: p.x, y: p.y + 11), .init(x: p.x - 11, y: p.y)]); diamond.closeSubpath()
                    context.stroke(diamond, with: .color(NFTheme.mintForeground), lineWidth: 3)
                }
                if let point = canEdit ? (previewPoint ?? point) : point, graph.contains(point) {
                    let p = location(point)
                    context.fill(Path(ellipseIn: .init(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(NFTheme.indigo))
                }
            }
            .accessibilityHidden(true)
            Rectangle().fill(.clear).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .updating($previewPoint) { event, state, _ in
                        guard pointerEnabled else { return }
                        state = point(at: event.location, bounds: bounds)
                    }
                    .onEnded { event in
                        guard pointerEnabled, let next = point(at: event.location, bounds: bounds) else { return }
                        updatePoint(next)
                    }, including: canEdit && pointerEnabled ? .all : .none)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) { Text(graph.yTitle).font(.caption.bold()) }
        .overlay(alignment: .bottomTrailing) { Text(graph.xTitle).font(.caption.bold()) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Time and distance plotting grid"))
        .accessibilityValue(point.map { Text("Your point: (\($0.x) s, \($0.y) m)") }
            ?? Text("No point has been placed on the grid."))
        .accessibilityIdentifier("graph-point-plot")
    }
    private func point(at location: CGPoint, bounds: CGRect) -> NFGraphConstructionContract.Point? {
        guard canEdit, bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 1, bounds.height > 1 else { return nil }
        return graph.snapped(normalizedX: Double((location.x - bounds.minX) / bounds.width),
            normalizedY: Double((bounds.maxY - location.y) / bounds.height))
    }
}

struct NFGraphConstructionFeedbackView: View {
    let projection: NFGraphConstructionHistoryProjection
    var showsPlot = false
    var body: some View {
        let graph = projection.graph
        VStack(alignment: .leading, spacing: 12) {
            Text("Compare the coordinate pair").font(.headline)
            if showsPlot {
                NFGraphConstructionPlot(graph: graph, point: projection.savedPoint, expected: graph.expectedPoint,
                    canEdit: false, updatePoint: { _ in }).frame(height: 280)
                Text("Given measurement: square. Saved point: circle. Expected point: diamond.").font(.footnote)
            }
            if case let .logicState(saved) = projection.response {
                Text(graph.responseDescription(saved)).textSelection(.enabled)
            }
            if projection.savedPoint == nil {
                Text("The saved response cannot be plotted on this grid. Its original coordinate text is retained.").foregroundStyle(.secondary)
            }
            if let expected = graph.expectedPoint {
                Text("Expected point: (\(expected.x) s, \(expected.y) m)").font(.body.monospacedDigit())
                Text("At constant speed, \(graph.targetX) × \(graph.baseline.y) = \(expected.y) meters. The horizontal coordinate is the requested time, not the distance.")
            }
        }.nfCard(cornerRadius: 16, padding: 16).accessibilityIdentifier("graph-saved-comparison")
    }
}


/// The visible marks and the accessible table share the exact saved figure.
/// Plot inspection never writes a learner response or exposes the answer key.
struct NFRetrievalAssetStimulusView: View {
    let asset: NFRetrievalAssetContract
    var body: some View {
        if asset.isSupported {
            if let figure = asset.figure {
                VStack(alignment: .leading, spacing: 12) {
                    Text(figure.summary).font(.subheadline)
                    Chart {
                        if figure.kind == .observations {
                            ForEach(figure.points) { point in
                                BarMark(x: .value(figure.xTitle, point.label), y: .value(figure.yTitle, point.y))
                                    .foregroundStyle(NFTheme.indigo)
                            }
                        } else {
                            if figure.kind == .rectangle {
                                RectangleMark(xStart: .value(figure.xTitle, 0),
                                    xEnd: .value(figure.xTitle, figure.points.map(\.x).max() ?? 0),
                                    yStart: .value(figure.yTitle, 0),
                                    yEnd: .value(figure.yTitle, figure.points.map(\.y).max() ?? 0))
                                    .foregroundStyle(NFTheme.indigo.opacity(0.2))
                            }
                            ForEach(figure.points) { point in
                                if figure.kind == .line {
                                    LineMark(x: .value(figure.xTitle, point.x), y: .value(figure.yTitle, point.y))
                                        .foregroundStyle(NFTheme.indigo)
                                }
                                PointMark(x: .value(figure.xTitle, point.x), y: .value(figure.yTitle, point.y))
                                    .foregroundStyle(NFTheme.indigo)
                                    .annotation(position: .top) { Text(point.label).font(.caption.bold()) }
                            }

                        }
                    }
                    .chartYScale(domain: figure.yBounds)
                    .chartXAxisLabel(figure.xTitle)
                    .chartYAxisLabel(figure.yTitle)
                    .frame(minHeight: 220, idealHeight: 260)
                    .accessibilityHidden(true)

                    if case let .table(headers, rows, _) = figure.table {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                HStack(alignment: .top) {
                                    ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(headers[column]).font(.caption.bold())
                                            Text(cell).monospacedDigit()
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(zip(headers, row).map { "\($0.0): \($0.1)" }.joined(separator: "; "))
                            }
                        }
                        .accessibilityIdentifier("retrieval-source-data")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("retrieval-source-figure")
            } else {
                ForEach(Array(asset.representations.enumerated()), id: \.offset) { _, representation in
                    if case let .equation(latex, spoken) = representation {
                        NFLaTeXEquationView(source: latex).accessibilityLabel(spoken)
                            .accessibilityIdentifier("retrieval-missing-equation")
                    }
                }
            }
        }
    }
}
