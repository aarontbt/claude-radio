import AppKit
import Combine
import WebKit
import os.log

/// Plays the Claude FM YouTube livestream via an off-screen WKWebView running the
/// YouTube IFrame Player API. Validated in the PRD.md §10 technical spike
/// (background audio, App Sandbox, no Dock icon, media keys all confirmed working).
/// Do not swap this for a scraping/yt-dlp approach. See CLAUDE.md.
@MainActor
final class WebViewPlaybackEngine: NSObject, ObservableObject {
    @Published private(set) var state: PlaybackState = .idle

    private static let videoID = "tRsQsTMvPNg"
    private static let logger = Logger(subsystem: "com.xenohawk.ClaudeRadio", category: "Playback")

    private var webView: WKWebView!
    private var hostWindow: NSWindow!

    override init() {
        super.init()
        setUpWebView()
    }

    private func setUpWebView() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []

        // WKUserContentController strongly retains its message handler. Registering
        // self directly would create self -> webView -> configuration ->
        // userContentController -> self, a real retain cycle (harmless today since
        // this engine lives for the app's whole lifetime, but incorrect ARC hygiene).
        // Route through a weak proxy instead.
        let userContentController = WKUserContentController()
        userContentController.add(WeakScriptMessageHandler(target: self), name: "playerEvent")
        config.userContentController = userContentController

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 2, height: 2), configuration: config)
        webView.navigationDelegate = self

        // Host the web view in a real, on-screen (but effectively invisible) window.
        // WKWebView instances that are never attached to a window, or that live in a
        // fully off-screen/occluded window, can have their JS timers and media playback
        // throttled by WebKit. Keeping the window within the visible screen frame with
        // alpha ~0 avoids that while never being visible to the user.
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 2, height: 2)
        let window = NSWindow(
            contentRect: NSRect(x: screenFrame.minX, y: screenFrame.minY, width: 2, height: 2),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.alphaValue = 0.01
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
        window.contentView = webView
        window.orderFront(nil)
        hostWindow = window

        loadPlayer()
    }

    private func loadPlayer() {
        state = .connecting
        // Deliberately NOT youtube.com: the IFrame API validates the embedding
        // origin, and using youtube.com as our own host page's origin triggers
        // a self-embed error (observed as YT player error 152 in the spike).
        webView.loadHTMLString(Self.embedHTML(videoID: Self.videoID), baseURL: URL(string: "https://claude-radio.app"))
    }

    func play() {
        runPlayerCommand("player.playVideo();")
    }

    func pause() {
        runPlayerCommand("player.pauseVideo();")
    }

    func setVolume(_ volume: Int) {
        runPlayerCommand("player.setVolume(\(volume));")
    }

    func reload() {
        loadPlayer()
    }

    /// Guards against calling into `player` before `onYouTubeIframeAPIReady` has run
    /// (a click during the first ~1-2s load would otherwise throw a JS ReferenceError
    /// that we'd never see), and logs any other evaluateJavaScript failure instead of
    /// silently discarding it.
    private func runPlayerCommand(_ command: String) {
        // The trailing `true;` gives evaluateJavaScript a bridgeable return value.
        // Without it, the block evaluates to `undefined`, which WKWebView reports
        // through the completion handler as "JavaScript execution returned a result
        // of an unsupported type" on every successful call, a false positive that
        // would otherwise drown out real errors in the log.
        let js = "if (typeof player !== 'undefined') { \(command) } true;"
        webView.evaluateJavaScript(js) { [weak self] _, error in
            if let error {
                Self.logger.error("player command failed: \(error.localizedDescription, privacy: .public)")
            }
            _ = self
        }
    }

    private static func embedHTML(videoID: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><style>html,body{margin:0;background:#000;}</style></head>
        <body>
        <div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player;
        function post(msg) { window.webkit.messageHandlers.playerEvent.postMessage(msg); }
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            height: '2', width: '2', videoId: '\(videoID)',
            playerVars: { autoplay: 0, controls: 0 },
            events: {
              onReady: function(e) { post({type: 'ready'}); },
              onStateChange: function(e) { post({type: 'stateChange', state: e.data}); },
              onError: function(e) { post({type: 'error', data: e.data}); }
            }
          });
        }
        </script>
        </body></html>
        """
    }

    fileprivate func handlePlayerMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            Self.logger.notice("player ready")
            state = .paused
        case "stateChange":
            let ytState = body["state"] as? Int ?? -99
            Self.logger.notice("player stateChange: \(ytState)")
            switch ytState {
            case 1: state = .playing
            case 2: state = .paused
            case 3: state = .connecting
            case -1, 5: state = .connecting
            case 0:
                // "Ended." For a 24/7 livestream this is how a dropped broadcast
                // often surfaces (not always via onError), so treat it as a failure
                // ReconnectManager should recover from, not a dead end.
                Self.logger.error("player reported ended (state 0), treating as a stream drop")
                state = .error("YouTube stream ended")
            default:
                break
            }
        case "error":
            let data = body["data"] as? Int ?? -1
            Self.logger.error("player error: \(data)")
            state = .error("YouTube player error \(data)")
        default:
            break
        }
    }
}

extension WebViewPlaybackEngine: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Self.logger.error("navigation failed: \(error.localizedDescription)")
        state = .error(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Self.logger.error("provisional navigation failed: \(error.localizedDescription)")
        state = .error(error.localizedDescription)
    }
}

/// Holds a weak reference to the real handler so WKUserContentController's strong
/// retain of this proxy doesn't keep the engine alive indefinitely.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WebViewPlaybackEngine?

    init(target: WebViewPlaybackEngine) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            target?.handlePlayerMessage(message)
        }
    }
}
