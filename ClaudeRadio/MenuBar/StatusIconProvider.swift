import AppKit

enum StatusIconProvider {
    static func image(for state: PlaybackState) -> NSImage? {
        let symbolName: String
        let description: String
        switch state {
        case .idle, .paused:
            symbolName = "dot.radiowaves.left.and.right"
            description = "Claude Radio, paused"
        case .connecting:
            symbolName = "arrow.triangle.2.circlepath"
            description = "Claude Radio, connecting"
        case .playing:
            symbolName = "waveform"
            description = "Claude Radio, playing"
        case .error:
            symbolName = "exclamationmark.triangle"
            description = "Claude Radio, error"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }
}
