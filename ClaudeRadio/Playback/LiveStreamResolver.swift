import Foundation

/// Resolves the currently live video ID for the Claude YouTube channel by
/// reading the canonical link off `channel/UC.../live`. This only ever feeds a
/// video ID into the official IFrame Player API; it does not resolve or scrape
/// raw CDN stream URLs, which stays forbidden per AGENTS.md.
struct LiveStreamResolver: Sendable {
    enum ResolverError: Error {
        case badStatus(Int)
        case noVideoID
    }

    private let session: URLSession

    init(session: URLSession = LiveStreamResolver.makeDefaultSession()) {
        self.session = session
    }

    private static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        // Kept below ReconnectManager's 15s stall watchdog so a hung resolve
        // never delays the fallback-ID load past the watchdog firing.
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }

    func resolveLiveVideoID() async throws -> String {
        var request = URLRequest(url: ClaudeChannel.liveResolveURL)
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        // Pre-accepts YouTube's EU cookie consent so the request is less likely
        // to be served a consent interstitial in place of the real page.
        request.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ResolverError.badStatus(status)
        }
        guard let html = String(data: data, encoding: .utf8),
              let videoID = Self.extractVideoID(fromHTML: html) else {
            throw ResolverError.noVideoID
        }
        return videoID
    }

    /// Extracts the video ID from the page's canonical link
    /// (`<link rel="canonical" href="https://www.youtube.com/watch?v=XXXXXXXXXXX">`).
    /// When the channel has no active live stream, the canonical link points at
    /// the channel page instead, so this returns `nil` and the caller should
    /// fall back to the last-known-good ID rather than treat this as fatal.
    static func extractVideoID(fromHTML html: String) -> String? {
        let pattern = #"rel="canonical"\s+href="https://www\.youtube\.com/watch\?v=([A-Za-z0-9_-]{11})""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let idRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[idRange])
    }
}
