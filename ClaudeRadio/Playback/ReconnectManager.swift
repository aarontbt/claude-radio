import Combine
import Foundation
import os.log

/// Exponential backoff delay sequence, doubling from `initial` up to `max`. Pure
/// value type so the progression can be unit-tested without a real playback engine.
struct Backoff: Equatable {
    let initial: TimeInterval
    let max: TimeInterval
    private(set) var current: TimeInterval

    init(initial: TimeInterval = 2, max: TimeInterval = 60) {
        self.initial = initial
        self.max = max
        self.current = initial
    }

    /// Returns the delay to use now, then advances the sequence for next time.
    mutating func next() -> TimeInterval {
        let delay = current
        current = Swift.min(current * 2, max)
        return delay
    }

    mutating func reset() {
        current = initial
    }
}

/// Reloads the playback engine with exponential backoff whenever it drops into
/// .error, OR whenever it's stuck in .connecting for too long without ever firing
/// an error event. The stall watchdog matters because the YouTube IFrame player can
/// wedge mid-buffering (observed: rapid unstarted/buffering flapping that just stops,
/// with no onError call). Without it, the status icon is stuck on "connecting"
/// forever with no way to recover short of quitting the app. Backoff resets once the
/// stream successfully starts playing again.
@MainActor
final class ReconnectManager {
    private static let logger = Logger(subsystem: "com.xenohawk.ClaudeRadio", category: "Reconnect")
    private static let connectingStallTimeout: TimeInterval = 15

    private let engine: WebViewPlaybackEngine
    private var cancellable: AnyCancellable?
    private var reconnectWorkItem: DispatchWorkItem?
    private var stallWatchdog: DispatchWorkItem?
    private var backoff = Backoff()

    init(engine: WebViewPlaybackEngine) {
        self.engine = engine
        cancellable = engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handle(state: state)
            }
    }

    private func handle(state: PlaybackState) {
        switch state {
        case .error:
            stallWatchdog?.cancel()
            scheduleReconnect()
        case .playing:
            backoff.reset()
            reconnectWorkItem?.cancel()
            stallWatchdog?.cancel()
        case .connecting:
            armStallWatchdog()
        case .idle, .paused:
            stallWatchdog?.cancel()
        }
    }

    private func armStallWatchdog() {
        stallWatchdog?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Self.logger.error("stuck in .connecting for \(Self.connectingStallTimeout, privacy: .public)s with no error event, treating as a stall")
            self.scheduleReconnect()
        }
        stallWatchdog = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectingStallTimeout, execute: workItem)
    }

    private func scheduleReconnect() {
        reconnectWorkItem?.cancel()
        let delay = backoff.next()
        Self.logger.notice("scheduling reconnect in \(delay, privacy: .public)s")

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Self.logger.notice("reconnecting now")
            self.engine.reload()
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
