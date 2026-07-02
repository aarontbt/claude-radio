import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var playbackEngine: WebViewPlaybackEngine!
    private var mediaKeyController: MediaKeyController!
    private var reconnectManager: ReconnectManager!
    private var statusItemController: StatusItemController!
    private let nowPlayingUpdater = NowPlayingInfoUpdater()
    private let settings = AppSettings()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        playbackEngine = WebViewPlaybackEngine(settings: settings)
        mediaKeyController = MediaKeyController(engine: playbackEngine)
        reconnectManager = ReconnectManager(engine: playbackEngine)
        statusItemController = StatusItemController(engine: playbackEngine, settings: settings)

        playbackEngine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.nowPlayingUpdater.update(state: state)
            }
            .store(in: &cancellables)
    }
}
