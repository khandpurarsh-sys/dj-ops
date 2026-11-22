import SwiftUI

/** Native policy/info page (Android PolicyScreen.kt parity): body text quoted verbatim
 *  from the site's own page (PolicyContent), rendered in the app's type, no WebView.
 *  "#"-prefixed lines are gold section headers. */
struct PolicyView: View {
    let page: StorePage
    let onBack: () -> Void

    private var content: (title: String, body: String)? { PolicyContent.page(forURL: page.url) }

    var body: some View {
        VStack(spacing: 0) {
            Header(dark: false, bagCount: 0, onBack: onBack, onBag: {})
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 26)
                    SerifTitle(text: content?.title ?? page.title, color: Dj.navy, size: 32)
                    Spacer().frame(height: 16)
                    if let content {
                        ForEach(Array(content.body.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, raw in
                            let line = raw.trimmingCharacters(in: .whitespaces)
                            if line.isEmpty {
                                Spacer().frame(height: 6)
                            } else if line.hasPrefix("#") {
                                Text(line.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased())
                                    .font(Dj.assistant(11, weight: .semibold)).tracking(2.2)
                                    .foregroundStyle(Dj.gold)
                                    .padding(.top, 12).padding(.bottom, 4)
                            } else {
                                Text(line)
                                    .font(Dj.assistant(14.5)).lineSpacing(7.5)
                                    .foregroundStyle(Dj.ink2)
                            }
                        }
                    } else {
                        Text("See dressjet.com for this page.")
                            .font(Dj.assistant(14)).lineSpacing(7)
                            .foregroundStyle(Dj.ink2)
                    }
                    Spacer().frame(height: 46)
                }
                .padding(.horizontal, 26)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.white.ignoresSafeArea())
    }
}
