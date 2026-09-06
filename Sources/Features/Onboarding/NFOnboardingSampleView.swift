import SwiftUI

/// An authored, untimed instructional sample. It deliberately creates no attempt
/// or protected evidence and does not require profile setup.
struct NFOnboardingSampleView: View {
    @Environment(\.dismiss) private var dismiss
    let onSetUp: () -> Void
    @State private var choice: Int?
    @State private var checked = false
    @State private var showsDataSample = false
    private var options: [String] {
        showsDataSample
            ? ["The observed average was higher in group A.", "The method caused everyone to improve.", "The result proves group A will always do better."]
            : ["30 × 6 − 6", "30 × 6 + 6", "30 × 6 − 1"]
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("Sample practice · untimed", systemImage: "sparkles").font(.footnote).id("sample-top")
                    Text(showsDataSample ? "Read a comparison carefully" : "Make multiplication easier").font(.title.bold())
                    Text(showsDataSample ? "Group A averaged 8 points and group B averaged 6 points. Which conclusion does this comparison support?" : "Which calculation gives the same answer as 29 × 6?").font(.title2)
                    Text(showsDataSample ? "No information about assignment, variation or prior scores is given." : "Think of 29 as one less than 30.").foregroundStyle(.secondary)
                    ForEach(options.indices, id: \.self) { index in
                        Button { choice = index } label: {
                            HStack(spacing: 12) {
                                Image(systemName: choice == index ? "largecircle.fill.circle" : "circle")
                                    .accessibilityHidden(true)
                                Text(LocalizedStringKey(options[index]))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                                .foregroundStyle(NFTheme.indigoForeground)
                                .background(NFTheme.indigo.opacity(choice == index ? 0.24 : 0.1), in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(NFTheme.indigoForeground.opacity(choice == index ? 0.8 : 0.2)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(checked)
                        .accessibilityLabel(Text(LocalizedStringKey(options[index])))
                        .accessibilityAddTraits(choice == index ? .isSelected : [])
                    }
                    if checked {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(choice == 0 ? "Correct" : "Let's review this").font(.headline)
                            Text(showsDataSample ? "8 is greater than 6, so the observed average was higher in group A. The comparison alone does not show what caused the difference or whether it will recur." : "30 groups of 6 make 180. Remove one group of 6: 180 − 6 = 174. So 29 × 6 = 30 × 6 − 6.")
                            Text(showsDataSample ? "Separate what was observed from what might explain it." : "Use a nearby multiple of ten, then adjust by one group.").font(.headline)
                            Text("This sample does not change your skill estimate.").font(.footnote).foregroundStyle(.secondary)
                        }
                        .nfCard()
                        .id("sample-feedback")
                        .onAppear { scrollProxy.scrollTo("sample-feedback", anchor: .top) }
                    }
                }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .onChange(of: showsDataSample) { _, _ in scrollProxy.scrollTo("sample-top", anchor: .top) }
            }
            .navigationTitle("Try a sample")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button {
                        if checked { onSetUp() } else { checked = true }
                    } label: {
                        Text(checked ? "Make this fit me" : "Check answer")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(.white)
                            .background(NFTheme.indigo, in: RoundedRectangle(cornerRadius: 16))
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(choice == nil)
                    .opacity(choice == nil ? 0.5 : 1)
                    .buttonStyle(.plain)
                    if checked {
                        Button("Try another skill") {
                            showsDataSample.toggle(); choice = nil; checked = false
                        }.buttonStyle(.borderless)
                    }
                }
                .padding().frame(maxWidth: .infinity).background(.bar)
            }
        }
    }
}
