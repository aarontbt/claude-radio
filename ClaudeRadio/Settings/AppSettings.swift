import Foundation

final class AppSettings {
    private enum Keys {
        static let volume = "volume"
        static let launchAtLogin = "launchAtLogin"
        static let lastKnownVideoID = "lastKnownVideoID"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Keys.volume) == nil {
            defaults.set(70, forKey: Keys.volume)
        }
    }

    var volume: Int {
        get { defaults.integer(forKey: Keys.volume) }
        set { defaults.set(min(max(newValue, 0), 100), forKey: Keys.volume) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    /// The most recently resolved live video ID, used as the playback fallback
    /// when live resolution fails. Defaults to `ClaudeChannel.seedVideoID`.
    var lastKnownVideoID: String {
        get { defaults.string(forKey: Keys.lastKnownVideoID) ?? ClaudeChannel.seedVideoID }
        set { defaults.set(newValue, forKey: Keys.lastKnownVideoID) }
    }
}
