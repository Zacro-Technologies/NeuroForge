import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct NFThemeSRGBComponents: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let white = NFThemeSRGBComponents(red: 1, green: 1, blue: 1)
    static let black = NFThemeSRGBComponents(red: 0, green: 0, blue: 0)

    func contrastRatio(against other: NFThemeSRGBComponents) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var relativeLuminance: Double {
        0.2126 * linearized(red) + 0.7152 * linearized(green) + 0.0722 * linearized(blue)
    }

    private func linearized(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}

struct NFThemeAdaptiveForegroundSpec: Equatable, Sendable {
    let light: NFThemeSRGBComponents
    let dark: NFThemeSRGBComponents
}

struct NFThemeAdaptiveControlSpec: Equatable, Sendable {
    let fill: NFThemeAdaptiveForegroundSpec
    let foreground: NFThemeAdaptiveForegroundSpec
}

enum NFTheme {
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.16)
    static let midnight = Color(red: 0.035, green: 0.055, blue: 0.11)
    static let indigo = Color(red: 0.33, green: 0.35, blue: 0.96)
    static let electricBlue = Color(red: 0.16, green: 0.56, blue: 1.00)
    static let violet = Color(red: 0.57, green: 0.30, blue: 0.96)
    static let cyan = Color(red: 0.20, green: 0.76, blue: 0.86)
    static let mint = Color(red: 0.27, green: 0.82, blue: 0.64)
    static let amber = Color(red: 0.95, green: 0.64, blue: 0.23)
    static let gold = Color(red: 1.00, green: 0.76, blue: 0.24)
    static let rose = Color(red: 0.93, green: 0.37, blue: 0.61)

    // Bright accents are intended for fills on the dark brand surface. These
    // semantic variants remain distinguishable as text and small symbols on
    // both light and dark system materials.
    static let indigoForegroundSpec = NFThemeAdaptiveForegroundSpec(
        light: .init(red: 0.20, green: 0.22, blue: 0.68),
        dark: .init(red: 0.72, green: 0.73, blue: 1.00)
    )
    static let cyanForegroundSpec = NFThemeAdaptiveForegroundSpec(
        light: .init(red: 0.00, green: 0.39, blue: 0.47),
        dark: .init(red: 0.48, green: 0.88, blue: 0.94)
    )
    static let mintForegroundSpec = NFThemeAdaptiveForegroundSpec(
        light: .init(red: 0.00, green: 0.38, blue: 0.25),
        dark: .init(red: 0.48, green: 0.91, blue: 0.73)
    )
    static let amberForegroundSpec = NFThemeAdaptiveForegroundSpec(
        light: .init(red: 0.48, green: 0.27, blue: 0.00),
        dark: .init(red: 1.00, green: 0.77, blue: 0.42)
    )
    static let roseForegroundSpec = NFThemeAdaptiveForegroundSpec(
        light: .init(red: 0.63, green: 0.15, blue: 0.36),
        dark: .init(red: 1.00, green: 0.65, blue: 0.78)
    )
    static let violetForegroundSpec = NFThemeAdaptiveForegroundSpec(
        light: .init(red: 0.36, green: 0.16, blue: 0.68),
        dark: .init(red: 0.78, green: 0.67, blue: 1.00)
    )
    static let electricBlueForegroundSpec = NFThemeAdaptiveForegroundSpec(
        light: .init(red: 0.05, green: 0.35, blue: 0.72),
        dark: .init(red: 0.50, green: 0.75, blue: 1.00)
    )
    static let goldForegroundSpec = NFThemeAdaptiveForegroundSpec(
        light: .init(red: 0.43, green: 0.28, blue: 0.00),
        dark: .init(red: 1.00, green: 0.82, blue: 0.40)
    )
    static let controlTintSpec = NFThemeAdaptiveForegroundSpec(
        light: .init(red: 0.24, green: 0.25, blue: 0.72),
        dark: .init(red: 0.46, green: 0.48, blue: 0.98)
    )
    static let roseControlTintSpec = NFThemeAdaptiveForegroundSpec(
        light: .init(red: 0.63, green: 0.15, blue: 0.36),
        dark: .init(red: 0.93, green: 0.37, blue: 0.61)
    )
    static let roseControlForegroundSpec = NFThemeAdaptiveForegroundSpec(
        light: .white,
        dark: .black
    )
    static let controlForegroundSpec = NFThemeAdaptiveForegroundSpec(
        light: .white,
        dark: .black
    )

    /// Prominent accent controls use an explicitly tested fill/label pair.
    /// Light appearances receive the darker semantic hue; bright dark-mode
    /// hues receive black labels unless the hue itself remains dark enough for
    /// white. This avoids relying on SwiftUI's default on-tint label choice.
    static let accentControlSpecifications: [String: NFThemeAdaptiveControlSpec] = [
        "indigo": .init(
            fill: .init(
                light: indigoForegroundSpec.light,
                dark: .init(red: 0.33, green: 0.35, blue: 0.96)
            ),
            foreground: .init(light: .white, dark: .white)
        ),
        "cyan": .init(
            fill: .init(
                light: cyanForegroundSpec.light,
                dark: .init(red: 0.20, green: 0.76, blue: 0.86)
            ),
            foreground: .init(light: .white, dark: .black)
        ),
        "orange": .init(
            fill: .init(
                light: amberForegroundSpec.light,
                dark: .init(red: 0.95, green: 0.64, blue: 0.23)
            ),
            foreground: .init(light: .white, dark: .black)
        ),
        "green": .init(
            fill: .init(
                light: mintForegroundSpec.light,
                dark: .init(red: 0.27, green: 0.82, blue: 0.64)
            ),
            foreground: .init(light: .white, dark: .black)
        ),
        "purple": .init(
            fill: .init(
                light: violetForegroundSpec.light,
                dark: .init(red: 0.57, green: 0.30, blue: 0.96)
            ),
            foreground: .init(light: .white, dark: .white)
        ),
        "blue": .init(
            fill: .init(
                light: electricBlueForegroundSpec.light,
                dark: .init(red: 0.16, green: 0.56, blue: 1.00)
            ),
            foreground: .init(light: .white, dark: .black)
        ),
        "pink": .init(fill: roseControlTintSpec, foreground: roseControlForegroundSpec)
    ]

    /// Source-of-truth values used by the adaptive colors and contrast tests.
    static let semanticForegroundSpecifications: [String: NFThemeAdaptiveForegroundSpec] = [
        "indigo": indigoForegroundSpec,
        "cyan": cyanForegroundSpec,
        "mint": mintForegroundSpec,
        "amber": amberForegroundSpec,
        "rose": roseForegroundSpec,
        "violet": violetForegroundSpec,
        "electricBlue": electricBlueForegroundSpec,
        "gold": goldForegroundSpec,
        "control": controlTintSpec
    ]

    static let indigoForeground = adaptiveForeground(indigoForegroundSpec)
    static let cyanForeground = adaptiveForeground(cyanForegroundSpec)
    static let mintForeground = adaptiveForeground(mintForegroundSpec)
    static let amberForeground = adaptiveForeground(amberForegroundSpec)
    static let roseForeground = adaptiveForeground(roseForegroundSpec)
    static let violetForeground = adaptiveForeground(violetForegroundSpec)
    static let electricBlueForeground = adaptiveForeground(electricBlueForegroundSpec)
    static let goldForeground = adaptiveForeground(goldForegroundSpec)

    /// A high-contrast control tint for prominent buttons on system surfaces.
    static let controlTint = adaptiveForeground(controlTintSpec)
    static let controlForeground = adaptiveForeground(controlForegroundSpec)

    /// Paired fill and foreground for rose-branded prominent controls. The
    /// foreground intentionally switches to black with the brighter dark-mode
    /// fill so the control does not depend on SwiftUI's default white label.
    static let roseControlTint = adaptiveForeground(roseControlTintSpec)
    static let roseControlForeground = adaptiveForeground(roseControlForegroundSpec)

    static func controlTint(for token: String) -> Color {
        adaptiveForeground(controlSpecification(for: token).fill)
    }

    static func controlForeground(for token: String) -> Color {
        adaptiveForeground(controlSpecification(for: token).foreground)
    }

    static func controlSpecification(for token: String) -> NFThemeAdaptiveControlSpec {
        accentControlSpecifications[token] ?? accentControlSpecifications["indigo"]!
    }

    static func color(for token: String) -> Color {
        switch token {
        case "cyan": cyan
        case "orange": amber
        case "green": mint
        case "purple": .purple
        case "blue": .blue
        case "pink": rose
        default: indigo
        }
    }

    static func foregroundColor(for token: String) -> Color {
        switch token {
        case "cyan": cyanForeground
        case "orange": amberForeground
        case "green": mintForeground
        case "pink": roseForeground
        case "purple": violetForeground
        case "blue": electricBlueForeground
        default: indigoForeground
        }
    }

    private static func adaptiveForeground(_ spec: NFThemeAdaptiveForegroundSpec) -> Color {
        #if os(macOS)
        let color = NSColor(name: nil) { appearance in
            let components = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? spec.dark
                : spec.light
            return NSColor(
                srgbRed: components.red,
                green: components.green,
                blue: components.blue,
                alpha: 1
            )
        }
        return Color(nsColor: color)
        #else
        return Color(uiColor: UIColor { traits in
            let components = traits.userInterfaceStyle == .dark ? spec.dark : spec.light
            return UIColor(
                red: components.red,
                green: components.green,
                blue: components.blue,
                alpha: 1
            )
        })
        #endif
    }
}

struct AppBackground: View {
    var body: some View {
        // A background must never contribute an intrinsic minimum width to its
        // foreground. The decorative 430-point orb previously forced compact
        // screens wider than their viewport at accessibility text sizes.
        GeometryReader { proxy in
            ZStack {
                Color.windowBackground
                LinearGradient(
                    colors: [NFTheme.violet.opacity(0.10), NFTheme.cyan.opacity(0.04), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(NFTheme.electricBlue.opacity(0.07))
                    .frame(width: 430, height: 430)
                    .blur(radius: 24)
                    .offset(x: 190, y: -310)
                Circle()
                    .fill(NFTheme.rose.opacity(0.045))
                    .frame(width: 330, height: 330)
                    .blur(radius: 30)
                    .offset(x: -210, y: 390)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct NFCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.075), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 16, y: 8)
    }
}

struct NFGameCardModifier: ViewModifier {
    let accent: Color
    let secondary: Color
    var cornerRadius: CGFloat = 28
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.22), secondary.opacity(0.10), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [accent.opacity(0.38), secondary.opacity(0.16), .primary.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: accent.opacity(0.10), radius: 22, y: 10)
    }
}

struct NFForgeProgressBar: View {
    let progress: Double
    var accent: Color = NFTheme.gold
    var secondary: Color = NFTheme.rose
    var height: CGFloat = 9
    var accessibilityLabelText: String = "Progress"

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.09))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent, secondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * min(1, max(0, progress)))
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(accessibilityLabelText)))
        .accessibilityValue(
            Text(min(1, max(0, progress)), format: .percent.precision(.fractionLength(0)))
        )
    }
}

extension View {
    func nfCard(cornerRadius: CGFloat = 22, padding: CGFloat = 18) -> some View {
        modifier(NFCardModifier(cornerRadius: cornerRadius, padding: padding))
    }

    func nfGameCard(
        accent: Color = NFTheme.indigo,
        secondary: Color = NFTheme.cyan,
        cornerRadius: CGFloat = 28,
        padding: CGFloat = 20
    ) -> some View {
        modifier(NFGameCardModifier(
            accent: accent,
            secondary: secondary,
            cornerRadius: cornerRadius,
            padding: padding
        ))
    }

    /// Keeps desktop sheets comfortably sized without forcing iPhone and iPad
    /// presentations beyond the space their host actually provides.
    @ViewBuilder
    func nfDesktopPresentationFrame(
        minWidth: CGFloat,
        idealWidth: CGFloat? = nil,
        minHeight: CGFloat,
        idealHeight: CGFloat? = nil
    ) -> some View {
        #if os(macOS)
        frame(
            minWidth: minWidth,
            idealWidth: idealWidth,
            minHeight: minHeight,
            idealHeight: idealHeight
        )
        #else
        self
        #endif
    }

    /// Applies the same spoken selection contract to every custom control.
    func nfSelectionAccessibility(_ isSelected: Bool) -> some View {
        accessibilityValue(Text(LocalizedStringKey(isSelected ? "Selected" : "Not selected")))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

enum NFLearningTextBlock: Equatable {
    case markdown(String)
    case plainText(String)
    case code(language: String?, source: String)
    case displayMath(source: String)
}

/// A small, deterministic block parser for learner-facing prose. It deliberately
/// recognizes only display-level constructs; inline Markdown remains the system
/// Markdown parser's responsibility.
enum NFLearningTextParser {
    private enum TokenKind {
        case codeFence
        case dollarMath
        case bracketMath
    }

    private struct Token {
        let kind: TokenKind
        let range: Range<String.Index>
    }

    static func parse(_ text: String) -> [NFLearningTextBlock] {
        guard !text.isEmpty else { return [] }

        var blocks: [NFLearningTextBlock] = []
        var plainTextStart = text.startIndex
        var searchStart = text.startIndex

        while let token = nextToken(in: text, from: searchStart) {
            switch token.kind {
            case .codeFence:
                guard let lineBreak = text[token.range.upperBound...].firstIndex(of: "\n"),
                      let closingFence = text.range(
                        of: "```",
                        range: text.index(after: lineBreak)..<text.endIndex
                      ) else {
                    searchStart = token.range.upperBound
                    continue
                }

                appendMarkdown(text[plainTextStart..<token.range.lowerBound], to: &blocks)
                let languageText = String(text[token.range.upperBound..<lineBreak])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let sourceStart = text.index(after: lineBreak)
                let source = trimmingFenceLineEnding(String(text[sourceStart..<closingFence.lowerBound]))
                blocks.append(.code(
                    language: languageText.isEmpty ? nil : languageText,
                    source: source
                ))
                plainTextStart = closingFence.upperBound
                searchStart = closingFence.upperBound

            case .dollarMath:
                guard let closing = text.range(
                    of: "$$",
                    range: token.range.upperBound..<text.endIndex
                ) else {
                    searchStart = token.range.upperBound
                    continue
                }
                appendMarkdown(text[plainTextStart..<token.range.lowerBound], to: &blocks)
                appendMath(text[token.range.upperBound..<closing.lowerBound], to: &blocks)
                plainTextStart = closing.upperBound
                searchStart = closing.upperBound

            case .bracketMath:
                guard let closing = text.range(
                    of: "\\]",
                    range: token.range.upperBound..<text.endIndex
                ) else {
                    searchStart = token.range.upperBound
                    continue
                }
                appendMarkdown(text[plainTextStart..<token.range.lowerBound], to: &blocks)
                appendMath(text[token.range.upperBound..<closing.lowerBound], to: &blocks)
                plainTextStart = closing.upperBound
                searchStart = closing.upperBound
            }
        }

        appendMarkdown(text[plainTextStart..<text.endIndex], to: &blocks)
        return blocks
    }

    static func parse(
        _ text: String,
        sourceLanguage: String?,
        contentTypeTags: [String]
    ) -> [NFLearningTextBlock] {
        let tags = Set(contentTypeTags.map { $0.lowercased() })
        let normalizedLanguage = sourceLanguage?.lowercased()
        if normalizedLanguage == "latex" || !tags.isDisjoint(with: ["latex", "math", "equation"]) {
            return [.displayMath(source: strippingMathDelimiters(text))]
        }
        if sourceLanguage != nil || !tags.isDisjoint(with: ["source-code", "code", "fenced-code"]) {
            let parsed = parse(text)
            if parsed.contains(where: { block in
                if case .code = block { return true }
                return false
            }) {
                return parsed
            }
            return [.code(language: sourceLanguage, source: text)]
        }
        if !tags.isDisjoint(with: ["csv", "table", "rows", "schema-summary"]) {
            return [.code(language: "table", source: text)]
        }
        if tags.contains("plain-text") && !tags.contains("markdown") {
            return [.plainText(text)]
        }
        return parse(text)
    }

    static func accessibilityLabel(forEquation source: String) -> String {
        var spoken = source
        spoken = spoken.replacingOccurrences(
            of: #"\\frac\s*\{([^{}]+)\}\s*\{([^{}]+)\}"#,
            with: "$1 divided by $2",
            options: .regularExpression
        )
        spoken = spoken.replacingOccurrences(
            of: #"\\sqrt\s*\{([^{}]+)\}"#,
            with: "square root of $1",
            options: .regularExpression
        )

        let replacements: [(String, String)] = [
            ("\\left", ""), ("\\right", ""),
            ("\\times", " times "), ("\\cdot", " times "),
            ("\\div", " divided by "), ("\\pm", " plus or minus "),
            ("\\leq", " less than or equal to "), ("\\le", " less than or equal to "),
            ("\\geq", " greater than or equal to "), ("\\ge", " greater than or equal to "),
            ("\\neq", " not equal to "), ("\\approx", " approximately "),
            ("\\rightarrow", " leads to "), ("\\to", " leads to "),
            ("\\alpha", " alpha "), ("\\beta", " beta "),
            ("\\gamma", " gamma "), ("\\delta", " delta "),
            ("\\theta", " theta "), ("\\lambda", " lambda "),
            ("\\mu", " mu "), ("\\pi", " pi "), ("\\sigma", " sigma "),
            ("^", " to the power of "), ("_", " subscript "),
            ("=", " equals "), ("+", " plus "), ("−", " minus "), ("-", " minus "),
            ("{", " "), ("}", " "), ("\\", " ")
        ]
        for (symbol, words) in replacements {
            spoken = spoken.replacingOccurrences(of: symbol, with: words)
        }

        let normalized = spoken.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return normalized.isEmpty ? source : normalized
    }

    static func strippingMathDelimiters(_ source: String) -> String {
        var result = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let delimiters = [("$$", "$$"), ("\\[", "\\]"), ("\\(", "\\)")]
        for (opening, closing) in delimiters
        where result.hasPrefix(opening) && result.hasSuffix(closing) {
            result = String(result.dropFirst(opening.count).dropLast(closing.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return result
    }

    static func safeMarkdown(_ source: String) -> AttributedString? {
        guard var attributed = try? AttributedString(markdown: source) else { return nil }
        // Imported documents are learning content, not navigation authority.
        attributed.link = nil
        return attributed
    }

    /// Produces a compact, readable equation when a full math typesetter is not
    /// available. The source remains the accessibility authority.
    static func displayText(forEquation source: String) -> String {
        var display = source
        display = display.replacingOccurrences(
            of: #"\\frac\s*\{([^{}]+)\}\s*\{([^{}]+)\}"#,
            with: "($1)⁄($2)",
            options: .regularExpression
        )
        display = display.replacingOccurrences(
            of: #"\\sqrt\s*\{([^{}]+)\}"#,
            with: "√($1)",
            options: .regularExpression
        )
        display = display.replacingOccurrences(
            of: #"\\(?:text|mathrm|mathbf|ce)\s*\{([^{}]+)\}"#,
            with: "$1",
            options: .regularExpression
        )

        let replacements: [(String, String)] = [
            ("\\rightarrow", "→"), ("\\Rightarrow", "⇒"),
            ("\\leftrightarrow", "↔"), ("\\times", "×"),
            ("\\cdot", "·"), ("\\div", "÷"), ("\\pm", "±"),
            ("\\leq", "≤"), ("\\le", "≤"), ("\\geq", "≥"),
            ("\\ge", "≥"), ("\\neq", "≠"), ("\\approx", "≈"),
            ("\\infty", "∞"), ("\\sum", "∑"), ("\\prod", "∏"),
            ("\\Delta", "Δ"), ("\\delta", "δ"), ("\\alpha", "α"),
            ("\\beta", "β"), ("\\gamma", "γ"), ("\\theta", "θ"),
            ("\\lambda", "λ"), ("\\mu", "μ"), ("\\pi", "π"),
            ("\\sigma", "σ"), ("\\left", ""), ("\\right", ""),
            ("\\to", "→"), ("\\,", " "), ("\\;", " ")
        ]
        for (source, replacement) in replacements {
            display = display.replacingOccurrences(of: source, with: replacement)
        }
        display = transformEquationScripts(display)
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "\\", with: "")
        return display.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func transformEquationScripts(_ source: String) -> String {
        let superscript: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
            "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
            "n": "ⁿ", "i": "ⁱ"
        ]
        let subscriptGlyphs: [Character: Character] = [
            "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
            "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
            "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
            "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ",
            "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ",
            "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ",
            "v": "ᵥ", "x": "ₓ"
        ]
        let characters = Array(source)
        var output = ""
        var index = 0

        while index < characters.count {
            let marker = characters[index]
            guard marker == "^" || marker == "_", index + 1 < characters.count else {
                output.append(marker)
                index += 1
                continue
            }

            let map = marker == "^" ? superscript : subscriptGlyphs
            var token: [Character] = []
            var next = index + 1
            if characters[next] == "{" {
                next += 1
                while next < characters.count, characters[next] != "}" {
                    token.append(characters[next])
                    next += 1
                }
                if next < characters.count { next += 1 }
            } else {
                token.append(characters[next])
                next += 1
            }

            if !token.isEmpty, token.allSatisfy({ map[$0] != nil }) {
                token.compactMap { map[$0] }.forEach { output.append($0) }
            } else {
                output.append(marker)
                output.append(contentsOf: token)
            }
            index = next
        }
        return output
    }

    private static func nextToken(in text: String, from start: String.Index) -> Token? {
        let searchRange = start..<text.endIndex
        let candidates: [Token?] = [
            text.range(of: "```", range: searchRange).map { Token(kind: .codeFence, range: $0) },
            text.range(of: "$$", range: searchRange).map { Token(kind: .dollarMath, range: $0) },
            text.range(of: "\\[", range: searchRange).map { Token(kind: .bracketMath, range: $0) }
        ]
        return candidates.compactMap { $0 }.min {
            $0.range.lowerBound < $1.range.lowerBound
        }
    }

    private static func appendMarkdown(
        _ source: Substring,
        to blocks: inout [NFLearningTextBlock]
    ) {
        let text = String(source)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        blocks.append(.markdown(text))
    }

    private static func appendMath(
        _ source: Substring,
        to blocks: inout [NFLearningTextBlock]
    ) {
        let equation = String(source).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !equation.isEmpty else { return }
        blocks.append(.displayMath(source: equation))
    }

    private static func trimmingFenceLineEnding(_ source: String) -> String {
        if source.hasSuffix("\r\n") {
            return String(source.dropLast(2))
        }
        if source.hasSuffix("\n") {
            return String(source.dropLast())
        }
        return source
    }
}

/// Renders learner-facing content without requiring each feature to build its
/// own Markdown, code, and display-math presentation rules.
struct NFFormattedLearningText: View {
    private let blocks: [NFLearningTextBlock]
    private let font: Font

    init(
        _ text: String,
        font: Font = .body,
        sourceLanguage: String? = nil,
        contentTypeTags: [String] = []
    ) {
        blocks = NFLearningTextParser.parse(
            text,
            sourceLanguage: sourceLanguage,
            contentTypeTags: contentTypeTags
        )
        self.font = font
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: NFLearningTextBlock) -> some View {
        switch block {
        case let .markdown(source):
            if let attributed = NFLearningTextParser.safeMarkdown(source) {
                Text(attributed)
                    .font(font)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                Text(verbatim: source)
                    .font(font)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

        case let .plainText(source):
            Text(verbatim: source)
                .font(font)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

        case let .code(language, source):
            VStack(alignment: .leading, spacing: 8) {
                if let language {
                    Text(verbatim: language.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                ScrollView(.horizontal) {
                    Text(verbatim: source)
                        .font(.system(.body, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: false)
                        .textSelection(.enabled)
                        .padding(.vertical, 2)
                }
            }
            .nfCard(cornerRadius: 14, padding: 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: source))

        case let .displayMath(source):
            NFLaTeXEquationView(source: source)
                .padding(.vertical, 3)
            .nfCard(cornerRadius: 14, padding: 12)
        }
    }

}

struct NFIconTile: View {
    let symbol: String
    var color: Color = NFTheme.indigo
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct NFSectionHeader: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?
    let headingLevel: AccessibilityHeadingLevel

    init(
        _ title: String,
        eyebrow: String? = nil,
        subtitle: String? = nil,
        headingLevel: AccessibilityHeadingLevel = .h2
    ) {
        self.title = title
        self.eyebrow = eyebrow
        self.subtitle = subtitle
        self.headingLevel = headingLevel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow {
                Text(LocalizedStringKey(eyebrow))
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(NFTheme.indigoForeground)
            }
            Text(LocalizedStringKey(title))
                .font(.system(.title, design: .rounded, weight: .bold))
                .accessibilityHeading(headingLevel)
            if let subtitle {
                Text(LocalizedStringKey(subtitle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct NFStatusPill: View {
    let text: String
    let symbol: String
    var color: Color = NFTheme.mint

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(text))
                .foregroundStyle(.primary)
        }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let idealWidth = subviews.reduce(CGFloat.zero) {
            $0 + $1.sizeThatFits(.unspecified).width + spacing
        }
        let width = max(1, proposal.width ?? idealWidth)
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = constrainedSize(for: subview, maximumWidth: width)
            if rowWidth + size.width > width, rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: height + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var point = bounds.origin
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = constrainedSize(for: subview, maximumWidth: bounds.width)
            if point.x + size.width > bounds.maxX, point.x > bounds.minX {
                point.x = bounds.minX
                point.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: point, proposal: ProposedViewSize(size))
            point.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func constrainedSize(for subview: LayoutSubview, maximumWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard ideal.width > maximumWidth else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: maximumWidth, height: nil))
    }
}

extension Color {
    static var windowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
}
