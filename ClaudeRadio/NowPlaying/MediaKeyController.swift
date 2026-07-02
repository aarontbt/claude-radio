import MediaPlayer

/// Wires hardware media keys (MediaPlayPause etc.) to the playback engine via
/// MPRemoteCommandCenter. Command handlers aren't guaranteed to run on the main
/// thread, so every call into the (MainActor-isolated) engine hops via `Task`.
/// Registration and Now Playing wiring are verified working; the actual hardware
/// key press itself still needs a manual check (see CLAUDE.md).
final class MediaKeyController {
    init(engine: WebViewPlaybackEngine) {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true

        center.playCommand.addTarget { [weak engine] _ in
            Task { @MainActor in
                engine?.play()
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak engine] _ in
            Task { @MainActor in
                engine?.pause()
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak engine] _ in
            Task { @MainActor in
                guard let engine else { return }
                if engine.state == .playing {
                    engine.pause()
                } else {
                    engine.play()
                }
            }
            return .success
        }
    }
}
