import Foundation

/// One message from cuecan.com, shown as a line in the projects window (docs/decisions.md, 97).
///
/// The server only supplies words and a link; the app draws them. So the worst a wrong answer can do is
/// show a wrong sentence.
public struct NewsItem: Codable, Equatable, Sendable {
    /// Names the message, so one that was dismissed stays gone.
    public var id: String
    /// The line shown, on one line of text.
    public var text: String
    /// Where a click goes: always https.
    public var link: URL

    /// The longest line shown. A longer one is treated as no message.
    public static let longestText = 140

    public init?(id: String, text: String, link: URL) {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !id.isEmpty, !text.isEmpty, text.count <= Self.longestText else { return nil }
        guard link.scheme?.lowercased() == "https", link.host() != nil else { return nil }
        self.id = id
        self.text = text
        self.link = link
    }

    /// The message in the endpoint's answer, or nil when it holds none: an empty object, a missing field,
    /// a link that isn't https, or anything that isn't the expected JSON.
    public init?(answer: Data) {
        struct Answer: Decodable {
            var id: String?
            var text: String?
            var link: String?
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: answer),
              let id = answer.id, let text = answer.text, let link = answer.link.flatMap(URL.init(string:))
        else { return nil }
        self.init(id: id, text: text, link: link)
    }
}

/// What the app remembers about the news between launches: when it last asked, what it was told, and what
/// the creator dismissed.
public struct NewsState: Codable, Equatable, Sendable {
    public var lastAnswered: Date?
    public var item: NewsItem?
    public var dismissed: String?

    /// How long an answer stands before the app asks again.
    public static let interval: TimeInterval = 24 * 60 * 60

    public init(lastAnswered: Date? = nil, item: NewsItem? = nil, dismissed: String? = nil) {
        self.lastAnswered = lastAnswered
        self.item = item
        self.dismissed = dismissed
    }

    /// Whether to ask the endpoint now: never asked, or the last answer is a day old. A clock set back
    /// counts as due, so a wrong date can't silence it for good.
    public func isDue(at now: Date) -> Bool {
        guard let lastAnswered else { return true }
        let age = now.timeIntervalSince(lastAnswered)
        return age >= Self.interval || age < 0
    }

    /// The message to show, if there is one the creator hasn't dismissed.
    public var visible: NewsItem? {
        guard let item, item.id != dismissed else { return nil }
        return item
    }

    /// Takes the endpoint's answer: its body when it answered 200, nil for any other status. Not called
    /// when the request failed, so the last message stays while the Mac is offline.
    public mutating func answered(_ body: Data?, at now: Date) {
        lastAnswered = now
        item = body.flatMap(NewsItem.init(answer:))
    }

    /// Hides the message showing now, for good.
    public mutating func dismiss() {
        if let item { dismissed = item.id }
    }
}
