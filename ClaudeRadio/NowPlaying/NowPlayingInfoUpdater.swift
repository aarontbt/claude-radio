import MediaPlayer

/// Publishes Now Playing metadata for Control Center and hardware media keys.
/// Only shows an entry while a player session actually exists (.paused/.playing);
/// clears it otherwise so Control Center doesn't advertise playback that isn't
/// happening (e.g. before the first Play, or while reconnecting after an error).
struct NowPlayingInfoUpdater {
    func update(state: PlaybackState) {
        switch state {
        case .paused, .playing:
            let info: [String: Any] = [
                MPMediaItemPropertyTitle: "Claude FM",
                MPMediaItemPropertyArtist: "Anthropic",
                MPNowPlayingInfoPropertyIsLiveStream: true,
                MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
            ]
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            MPNowPlayingInfoCenter.default().playbackState = state == .playing ? .playing : .paused
        case .idle, .connecting, .error:
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
    }
}
