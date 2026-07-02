enum PlaybackState: Equatable, CustomStringConvertible {
    case idle
    case connecting
    case playing
    case paused
    case error(String)

    var description: String {
        switch self {
        case .idle: return "idle"
        case .connecting: return "connecting"
        case .playing: return "playing"
        case .paused: return "paused"
        case .error(let message): return "error(\(message))"
        }
    }
}
