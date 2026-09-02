import SwiftUI

struct NFMethodologyEntry: Identifiable, Equatable, Sendable {
    let lab: TrainingLab
    let purpose: String
    let method: String
    let limits: String
    let evidence: String

    var id: String { lab.rawValue }

    var searchableText: String {
        [lab.title, lab.subtitle, purpose, method, limits, evidence]
            .map { NFAppLocalization.localizedCatalogValue($0) }
            .joined(separator: " ")
    }
}

enum NFMethodologyCatalog {
    static let version = 1
    static let entries: [NFMethodologyEntry] = [
        NFMethodologyEntry(
            lab: .mentalMath,
            purpose: "Build numerical fluency, estimation, magnitude checks, and deliberate tool judgment used in STEM work.",
            method: "Deterministic item families vary numbers, representations, and decisive steps. Accuracy evidence is kept separate from eligible timed evidence.",
            limits: "Fluency on these item families is not a global mathematics score. Untimed work does not produce a speed estimate, and transfer is tested separately.",
            evidence: "Practice, alternate-form transfer, delayed retention, confidence, interruptions, and scoring-rule provenance are retained as separate inspectable channels."
        ),
        NFMethodologyEntry(
            lab: .spatial,
            purpose: "Practice transformations among diagrams, coordinates, projections, cross-sections, nets, and 3D forms.",
            method: "Tasks persist viewpoint, rotation magnitude, object complexity, distractor similarity, and response mode. Native 3D and static 2D presentations share deterministic scoring.",
            limits: "Visual-spatial tasks are not construct-equivalent for every accessibility need. The domain can be excluded and left unassessed without a completion penalty.",
            evidence: "Performance is interpreted only alongside presentation and difficulty parameters; no age norm or intelligence ranking is produced."
        ),
        NFMethodologyEntry(
            lab: .quantitative,
            purpose: "Develop magnitude, dimensional analysis, scaling, uncertainty, probability, base-rate, and signal-versus-noise reasoning.",
            method: "Prompts require an auditable choice, numeric response, ordering, or structured judgment scored by deterministic rules.",
            limits: "Short app tasks do not establish expertise in statistics or a scientific field. Context familiarity may affect performance.",
            evidence: "Credit, error code, confidence, representation, domain context, and unfamiliar-transfer performance remain independently inspectable."
        ),
        NFMethodologyEntry(
            lab: .scientificReasoning,
            purpose: "Practice controls, confounds, figure-to-claim alignment, competing hypotheses, causal caution, and reproducibility.",
            method: "Controlled scenarios vary surface field while preserving a defined reasoning structure and deterministic reference rationale.",
            limits: "A short scenario cannot reproduce every constraint of laboratory or field research. Correct answers depend on stated assumptions.",
            evidence: "Repeated scorer codes and confidence mismatches can schedule review; AI explanations cannot alter the saved score or evidence class."
        ),
        NFMethodologyEntry(
            lab: .logicDebugging,
            purpose: "Practice assumptions, counterexamples, proof steps, state tracking, edge cases, and invariants.",
            method: "Bounded traces and authored logic items use explicit expected states or choices. Pseudocode executes only in the restricted local interpreter.",
            limits: "These tasks sample defined debugging and reasoning mechanics, not overall programming ability or proof expertise.",
            evidence: "Item seed, mechanic, response, deterministic credit, error code, revisions, and transfer form are stored for inspection."
        ),
        NFMethodologyEntry(
            lab: .retrieval,
            purpose: "Support durable recall and concept reconstruction from study material the learner explicitly imports.",
            method: "Citation-stable local chunks ground questions and delayed alternate prompts. Source-derived work remains personal practice.",
            limits: "Extraction and OCR can misread symbols or equations. Learners should compare important answers with the original source.",
            evidence: "Citations, source identifiers, route provenance, review outcome, and retention timing are exportable; source practice is excluded from standardized estimates."
        ),
        NFMethodologyEntry(
            lab: .transfer,
            purpose: "Test whether familiar structure can be applied through changed context, representation, field, or delayed application.",
            method: "Weekly missions combine at least two selected skills using a persisted deterministic transfer brief and alternate surface form.",
            limits: "Success on one unfamiliar item is narrow evidence. Broad claims require repeated independent transfer and delayed retention.",
            evidence: "Selected skill weights, transfer dimensions, mission family, seed, result, and evidence class remain available for audit."
        )
    ]

    static func entry(for lab: TrainingLab) -> NFMethodologyEntry {
        entries.first(where: { $0.lab == lab })!
    }
}

struct MethodologyLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedLab: TrainingLab?
    let showsDismissButton: Bool

    init(initialLab: TrainingLab? = nil, showsDismissButton: Bool = false) {
        _selectedLab = State(initialValue: initialLab)
        self.showsDismissButton = showsDismissButton
    }

    private var visibleEntries: [NFMethodologyEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return NFMethodologyCatalog.entries.filter { entry in
            (selectedLab == nil || selectedLab == entry.lab)
                && (trimmed.isEmpty || entry.searchableText.localizedCaseInsensitiveContains(trimmed))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        NFSectionHeader(
                            "Methodology & evidence",
                            eyebrow: "Searchable offline library",
                            subtitle: "Purpose, method, limits, and retained evidence for every training lab. NeuroForge reports defined task performance—not intelligence, diagnosis, or treatment.",
                            headingLevel: .h1
                        )

                        Picker("Lab", selection: $selectedLab) {
                            Text("All labs").tag(nil as TrainingLab?)
                            ForEach(TrainingLab.allCases) { lab in
                                Text(lab.shortTitle).tag(Optional(lab))
                            }
                        }
                        .pickerStyle(.menu)
                        .nfCard(cornerRadius: 16, padding: 12)

                        if visibleEntries.isEmpty {
                            ContentUnavailableView.search(text: query)
                        } else {
                            ForEach(visibleEntries) { entry in
                                MethodologyEntryCard(entry: entry)
                            }
                        }

                        Label(
                            "Catalog v\(NFMethodologyCatalog.version) ships in the app bundle and remains available offline.",
                            systemImage: "checkmark.shield.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Methodology")
            .searchable(text: $query, prompt: "Search purpose, method, limits, evidence")
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }
}

private struct MethodologyEntryCard: View {
    let entry: NFMethodologyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                NFIconTile(
                    symbol: entry.lab.symbol,
                    color: NFTheme.color(for: entry.lab.colorToken),
                    size: 48
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.lab.title).font(.title2.bold())
                        .accessibilityHeading(.h2)
                    Text(entry.lab.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            methodologySection("Purpose", entry.purpose, symbol: "target")
            methodologySection("Method", entry.method, symbol: "point.3.connected.trianglepath.dotted")
            methodologySection("Limits", entry.limits, symbol: "exclamationmark.shield")
            methodologySection("Evidence retained", entry.evidence, symbol: "list.bullet.clipboard")
        }
        .nfCard()
    }

    private func methodologySection(_ title: String, _ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(NFTheme.indigoForeground)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NFTheme.indigoForeground)
                    .accessibilityHeading(.h3)
                Text(LocalizedStringKey(text)).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
}
