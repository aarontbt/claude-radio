import AppKit
import Combine
import os.log

/// Owns the NSStatusItem and its dropdown. Left-click on the icon toggles
/// play/pause directly; right-click opens the full menu (volume, launch at
/// login, open in YouTube, about, quit). Matches PRD §5 P0 "Click icon to
/// toggle; dropdown button as alternative".
@MainActor
final class StatusItemController {
    private static let logger = Logger(subsystem: "com.xenohawk.ClaudeRadio", category: "MenuBar")
    private static let streamURL = URL(string: "https://www.youtube.com/watch?v=tRsQsTMvPNg")!

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let engine: WebViewPlaybackEngine
    private let settings: AppSettings
    private let aboutWindowController = AboutWindowController()

    private var cancellables = Set<AnyCancellable>()
    private var scrollMonitor: Any?

    private var playPauseMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!
    private var volumeSlider: NSSlider!

    init(engine: WebViewPlaybackEngine, settings: AppSettings) {
        self.engine = engine
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        configureButton()
        buildMenu()
        observeState()
        installScrollMonitor()
    }

    isolated deinit {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
    }

    // MARK: - Button

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = StatusIconProvider.image(for: .idle)
        button.target = self
        button.action = #selector(buttonClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func buttonClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePlayPause()
        }
    }

    private func showContextMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Menu

    private func buildMenu() {
        playPauseMenuItem = NSMenuItem(title: "Play", action: #selector(togglePlayPause), keyEquivalent: "")
        playPauseMenuItem.target = self
        playPauseMenuItem.image = Self.symbol("play.fill")
        menu.addItem(playPauseMenuItem)

        menu.addItem(makeVolumeMenuItem())
        menu.addItem(.separator())

        launchAtLoginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.image = Self.symbol("power")
        launchAtLoginMenuItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchAtLoginMenuItem)

        let openItem = NSMenuItem(title: "Open in YouTube", action: #selector(openInYouTube), keyEquivalent: "")
        openItem.target = self
        openItem.image = Self.symbol("arrow.up.forward.square")
        menu.addItem(openItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About Claude Radio", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.image = Self.symbol("info.circle")
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = Self.symbol("xmark.circle")
        menu.addItem(quitItem)
    }

    /// Template image so the icon tints correctly when the menu row is highlighted
    /// (matches system menu item icon behavior).
    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    private func makeVolumeMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))

        let icon = NSImageView(frame: NSRect(x: 14, y: 3, width: 18, height: 18))
        icon.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Volume")
        icon.contentTintColor = .secondaryLabelColor
        container.addSubview(icon)

        let slider = NSSlider(value: Double(settings.volume), minValue: 0, maxValue: 100, target: self, action: #selector(volumeSliderChanged(_:)))
        slider.frame = NSRect(x: 38, y: 2, width: 150, height: 20)
        container.addSubview(slider)
        volumeSlider = slider

        item.view = container
        return item
    }

    // MARK: - State observation

    private func observeState() {
        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.render(state: state)
            }
            .store(in: &cancellables)
    }

    private func render(state: PlaybackState) {
        statusItem.button?.image = StatusIconProvider.image(for: state)
        let isPlaying = state == .playing
        playPauseMenuItem.title = isPlaying ? "Pause" : "Play"
        playPauseMenuItem.image = Self.symbol(isPlaying ? "pause.fill" : "play.fill")

        // The IFrame player only accepts setVolume once it exists; .paused/.playing
        // both mean the player object is live (idle/connecting do not).
        if state == .paused || state == .playing {
            engine.setVolume(settings.volume)
        }
    }

    // MARK: - Actions

    @objc private func togglePlayPause() {
        switch engine.state {
        case .playing, .connecting:
            engine.pause()
        default:
            engine.play()
        }
    }

    @objc private func volumeSliderChanged(_ sender: NSSlider) {
        let volume = Int(sender.doubleValue)
        settings.volume = volume
        engine.setVolume(volume)
    }

    @objc private func toggleLaunchAtLogin() {
        let newValue = !settings.launchAtLogin
        do {
            try LaunchAtLogin.setEnabled(newValue)
            settings.launchAtLogin = newValue
            launchAtLoginMenuItem.state = newValue ? .on : .off
        } catch {
            Self.logger.error("failed to toggle launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func openInYouTube() {
        NSWorkspace.shared.open(Self.streamURL)
    }

    @objc private func showAbout() {
        aboutWindowController.show()
    }

    // MARK: - Scroll-to-adjust-volume

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let buttonWindow = self.statusItem.button?.window, event.window == buttonWindow else {
                return event
            }
            self.adjustVolume(by: event.scrollingDeltaY)
            return event
        }
    }

    private func adjustVolume(by scrollDeltaY: CGFloat) {
        let step = Int((scrollDeltaY / 2).rounded())
        guard step != 0 else { return }
        let newVolume = min(max(settings.volume + step, 0), 100)
        guard newVolume != settings.volume else { return }
        settings.volume = newVolume
        volumeSlider?.doubleValue = Double(newVolume)
        engine.setVolume(newVolume)
    }
}
