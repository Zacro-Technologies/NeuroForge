import CoreText
import SwiftMath
import SwiftUI

/// Native, offline LaTeX typesetting shared by authored and AI-generated
/// exercises. Invalid input falls back to readable text instead of showing an
/// error from the rendering engine.
struct NFLaTeXEquationView: View {
    let source: String
    var fontSize: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var fontScale: CGFloat = 1

    private var scaledFontSize: CGFloat { fontSize * fontScale }

    private var canRender: Bool {
        var error: NSError?
        return MTMathListBuilder.build(fromString: source, error: &error) != nil
            && error == nil
    }

    var body: some View {
        Group {
            if canRender {
                NFPlatformMathLabel(source: source, fontSize: scaledFontSize)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(verbatim: NFLearningTextParser.displayText(forEquation: source))
                    .font(.system(size: scaledFontSize, weight: .medium, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: NFLearningTextParser.accessibilityLabel(
            forEquation: source
        )))
    }
}

#if os(iOS)
private struct NFPlatformMathLabel: UIViewRepresentable {
    let source: String
    let fontSize: CGFloat

    func makeUIView(context: Context) -> MTMathUILabel {
        let view = MTMathUILabel()
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.displayErrorInline = false
        return view
    }

    func updateUIView(_ view: MTMathUILabel, context: Context) {
        configure(view)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: MTMathUILabel,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else {
            return uiView.intrinsicContentSize
        }
        uiView.preferredMaxLayoutWidth = width
        let measured = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: min(width, max(1, measured.width)), height: max(fontSize, measured.height))
    }

    private func configure(_ view: MTMathUILabel) {
        view.latex = source
        let font = MTFontManager().font(withName: MathFont.latinModernFont.rawValue, size: fontSize)
        font?.fallbackFont = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
        view.font = font
        view.fontSize = fontSize
        view.textAlignment = .left
        view.labelMode = .display
        view.textColor = .label
        view.backgroundColor = .clear
        view.invalidateIntrinsicContentSize()
    }
}
#elseif os(macOS)
private struct NFPlatformMathLabel: NSViewRepresentable {
    let source: String
    let fontSize: CGFloat

    func makeNSView(context: Context) -> MTMathUILabel {
        let view = MTMathUILabel()
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.displayErrorInline = false
        return view
    }

    func updateNSView(_ view: MTMathUILabel, context: Context) {
        configure(view)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: MTMathUILabel,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else {
            return nsView.intrinsicContentSize
        }
        nsView.preferredMaxLayoutWidth = width
        let measured = nsView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: min(width, max(1, measured.width)), height: max(fontSize, measured.height))
    }

    private func configure(_ view: MTMathUILabel) {
        view.latex = source
        let font = MTFontManager().font(withName: MathFont.latinModernFont.rawValue, size: fontSize)
        font?.fallbackFont = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
        view.font = font
        view.fontSize = fontSize
        view.textAlignment = .left
        view.labelMode = .display
        view.textColor = .labelColor
        view.layer?.backgroundColor = .clear
        view.invalidateIntrinsicContentSize()
    }
}
#endif
