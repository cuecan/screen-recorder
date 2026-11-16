import Foundation
import Observation
import ProjectKit
import SwiftUI

/// The line of news from cuecan.com in the projects window (docs/decisions.md, 97).
///
/// It asks one address at most once a day and keeps what it was told in the app's preferences. The only
/// thing it sends is a random identifier made on this Mac (`installID`), so cuecan.com can count how many
/// copies are in use; it's tied to nothing else. What to show and when to ask is ProjectKit's
/// (`NewsState`); this fetches and remembers.
@Observable
final class NewsModel {
    /// Every installed copy asks this address, so it can't move.
    static let endpoint = URL(string: "https://cuecan.com/mac/news.json")
    private static let storageKey = "news"
    private static let installKey = "installID"
    /// The request header that carries `installID`.
    static let installHeader = "X-CueCan-Install"

    private(set) var state: NewsState
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isAsking = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(NewsState.self, from: $0) } ?? NewsState()
    }

    /// A random identifier for this copy, made the first time news is asked for and kept in the app's
    /// preferences. It comes from nothing about the Mac or the creator, and deleting the preferences
    /// makes a new one.
    private var installID: String {
        if let known = defaults.string(forKey: Self.installKey), UUID(uuidString: known) != nil { return known }
        let made = UUID().uuidString
        defaults.set(made, forKey: Self.installKey)
        return made
    }

    /// The message to show, if any.
    var visible: NewsItem? { state.visible }

    /// Asks the endpoint if the last answer is a day old. A failed request changes nothing and is tried
    /// again the next time the projects window opens.
    func refreshIfDue() async {
        guard let endpoint = Self.endpoint, !isAsking, state.isDue(at: .now) else { return }
        isAsking = true
        defer { isAsking = false }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        request.setValue(installID, forHTTPHeaderField: Self.installHeader)
        guard let (body, response) = try? await URLSession(configuration: .ephemeral).data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode
        else { return }
        state.answered(status == 200 ? body : nil, at: .now)
        save()
    }

    /// Hides the message showing now, for good.
    func dismiss() {
        state.dismiss()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// The message, at the foot of the sidebar: its words open its link, and the cross puts it away.
struct NewsBanner: View {
    let item: NewsItem
    let dismiss: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button { openURL(item.link) } label: {
                Text(item.text)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(item.link.host() ?? "")
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 8))
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(EdgeInsets(top: 0, leading: 12, bottom: 12, trailing: 12))
    }
}

#if DEBUG
#Preview("News banner", traits: .fixedLayout(width: 260, height: 120)) {
    if let link = URL(string: "https://cuecan.com"), let item = NewsItem(id: "preview", text: "Placeholder: one line of news from cuecan.com.", link: link) {
        NewsBanner(item: item, dismiss: {})
    }
}
#endif
