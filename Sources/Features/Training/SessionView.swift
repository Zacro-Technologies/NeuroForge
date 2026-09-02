import SwiftUI

/// Shared confidence indicator used by the universal, authored-practice, and
/// source-review flows. The retired mental-math-only `SessionView` no longer
/// lives in this file; every session launch is routed through
/// `UniversalSessionView`.
struct ConfidenceGlyph: View {
    let level: ConfidenceLevel

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index <= filledCount ? NFTheme.cyan : Color.secondary.opacity(0.18))
                    .frame(width: 5, height: CGFloat(8 + index * 3))
            }
        }
        .frame(width: 32)
        .accessibilityHidden(true)
    }

    private var filledCount: Int {
        switch level {
        case .guessing: 0
        case .uncertain: 1
        case .fairlyConfident: 2
        case .certain: 3
        }
    }
}

extension View {
    @ViewBuilder
    func numericKeyboard() -> some View {
        #if os(iOS)
        // Unlike the decimal pad, this layout keeps minus, locale decimal
        // separators, fractions, and scientific notation reachable. The
        // alphabet toggle also makes `e`/`E` available when the schema permits
        // exponents, and Return remains available for explicit submission.
        self.keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }
}
