import Foundation

final class AppSettings {
    private enum Keys {
        static let volume = "volume"
        static let launchAtLogin = "launchAtLogin"
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
}
