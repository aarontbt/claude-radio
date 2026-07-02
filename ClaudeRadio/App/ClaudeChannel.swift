import Foundation

/// Constants for Anthropic's official Claude YouTube channel. Single source of
/// truth shared by Playback, MenuBar and About so the channel/stream identity
/// never drifts between hardcoded copies.
enum ClaudeChannel {
    /// Immutable channel ID (unlike the `@claude` handle, which the channel owner
    /// could rename), used to resolve the currently live video ID.
    static let channelID = "UCV03SRZXJEz-hchIAogeJOg"

    /// Last-known-good live video ID, used only as a `AppSettings.lastKnownVideoID`
    /// seed and fallback if live resolution fails. Not a fixed stream target.
    static let seedVideoID = "tRsQsTMvPNg"

    /// Page whose canonical link resolves to the channel's current live video ID.
    /// See `LiveStreamResolver`.
    static let liveResolveURL = URL(string: "https://www.youtube.com/channel/\(channelID)/live")!

    /// Evergreen handle-based live URL for human-facing links; the browser
    /// resolves this to the current live video itself.
    static let liveWatchURL = URL(string: "https://www.youtube.com/@claude/live")!

    static let channelURL = URL(string: "https://www.youtube.com/@claude")!
}
