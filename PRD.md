# PRD: Claude Radio — macOS Menu Bar App

**Version**: 1.3  
**Date**: 2026-07-02  
**Status**: Draft  
**Repo**: `claude-radio`  
**Working title**: "Claude Radio" — naming decision gate in §13 (must resolve before Week 5 release prep)

---

## 1. Overview

**Claude Radio** is a lightweight macOS menu bar application that plays the official Claude FM 24/7 livestream — *"music for thinking and building"* — from Anthropic's Claude YouTube channel. It provides one-click background focus music directly from the menu bar: no browser tab, no Dock icon, no clutter. Just press play and keep thinking.

**Stream source**: [Claude FM on YouTube](https://www.youtube.com/watch?v=tRsQsTMvPNg)  
**Channel**: [youtube.com/@claude](https://www.youtube.com/@claude) (official Anthropic)  
**Tagline**: *"Press play and keep thinking. Made and curated by musicians."*

> **Unofficial**: This app is not affiliated with, endorsed by, or sponsored by Anthropic. It plays a publicly embeddable YouTube livestream. "Claude" is a trademark of Anthropic; the app name may change before public release (see §13).

---

## 2. Problem Statement

- The Claude FM stream lives on YouTube, requiring a browser tab or heavy desktop window to play.
- Browser playback is distracting — tabs, notifications, visual clutter — and consumes unnecessary system resources.
- There is no simple, always-accessible native macOS solution to listen to this specific stream with minimal friction.
- Developers, designers, and writers want zero-click ambient music while in their editor or flow state.

---

## 3. Target Audience

| Persona | Description |
|---------|-------------|
| **Focus workers** | Developers, designers, writers who want background music without browser overhead |
| **Claude fans** | Users of Anthropic's Claude who appreciate the curated music aesthetic |
| **Minimalists** | macOS users who prefer native, low-resource apps over Electron bloat |

---

## 4. Goals & Non-Goals

### Goals

- Play the Claude FM stream reliably from the macOS menu bar
- One-click play/pause with zero UI windows
- Minimal system resource footprint (CPU < 5%, Memory < 350 MB for IFrame approach; < 120 MB for AVPlayer approach — see §6.3)
- Global media key integration for play/pause
- Open at Login support via `SMAppService`
- Graceful auto-reconnect on network interruptions and sleep/wake
- No analytics, no telemetry, no user accounts — the only network traffic is the YouTube embed itself

### Non-Goals (v1)

- No video display — audio only
- No equalizer or audio effects
- No recording or stream capture
- No Linux/Windows support
- No playlist management or multi-stream switching
- No user accounts or cloud sync

---

## 5. Features

### P0 — Must Have (v1.0)

| Feature | Description |
|---------|-------------|
| **Menu bar icon** | `NSStatusItem` with template image (radio-wave icon); reflects play/pause/connecting/error state |
| **Play / Pause** | Click icon to toggle; dropdown button as alternative |
| **Volume control** | Slider in dropdown; scroll-wheel over menu bar icon for quick adjust |
| **Auto-reconnect** | Exponential backoff retry on stream drop, network change, or sleep/wake |
| **Open at Login** | Toggle in dropdown; uses `SMAppService.mainApp.register()` (macOS 13+) — appears in System Settings → General → Login Items, no admin privileges needed |
| **Media key support** | `MPRemoteCommandCenter` play/pause commands; `MPNowPlayingInfoCenter` for Now Playing UI |
| **Audio session pre-warming** | Use `ProcessInfo.processInfo.beginActivity(options: .background)` on launch to prevent App Nap suspension of the WKWebView |
| **Open in YouTube** | Menu item to open the stream URL in default browser (fallback) |
| **Quit** | Standard quit menu item |

### P1 — Should Have (v1.1)

| Feature | Description |
|---------|-------------|
| **Now-playing metadata** | Display track/artist if extractable from stream or YouTube description; bridge to `MPNowPlayingInfoCenter` |
| **Mute on fullscreen** | Auto-mute when a fullscreen app (e.g., Zoom, Keynote) activates |
| **Error notifications** | `UserNotifications` framework for stream-down alerts |
| **Connection status indicator** | Subtle icon variant for connecting / error states |
| **Ad detection (feature-flagged)** | Best-effort ad detection with auto-mute — shipped behind a feature flag, disabled by default until spike validates accuracy (see §6.6) |

### P2 — Nice to Have (Future)

| Feature | Description |
|---------|-------------|
| **Custom global hotkey** | e.g., `⌥⌘R` to toggle playback (requires Accessibility permission) |
| **Sleep timer** | Auto-pause after N minutes |
| **AppleScript control** | Scriptable play/pause/volume for automation |
| **Multiple streams** | Support additional Claude FM streams or custom YouTube livestream URLs |
| **AirPlay routing** | System audio output picker integration |
| **Mini artwork** | Album art thumbnail in dropdown popover |
| **Memory watchdog** | Auto-reload WKWebView every N hours or when memory exceeds threshold (see §6.8) |

---

## 6. Technical Architecture

### 6.1 Language & Framework

- **Swift 6** + **SwiftUI** (macOS 14+ Sonoma)
- **AppKit** `NSStatusItem` for menu bar presence (SwiftUI `MenuBarExtra` also viable)
- **WKWebView** (off-screen) for YouTube IFrame Player API — primary approach (see §6.3)
- **MediaPlayer** framework (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`) for media keys and Now Playing
- **ProcessInfo** for background activity assertion (prevents App Nap)
- **SMAppService** for Open at Login

> **Note**: `AVAudioSession` is an iOS/tvOS-only API and does not exist on macOS. On macOS, WKWebView handles audio output natively via CoreAudio. No special audio session configuration is needed — the key mechanism for keeping audio alive in a backgrounded `LSUIElement` app is `ProcessInfo.processInfo.beginActivity(options: .background)`.

### 6.2 App Configuration

| Setting | Value | Reason |
|---------|-------|--------|
| `LSUIElement` | `YES` | Accessory app — no Dock icon, no main window |
| App Sandbox | Enabled | Required for Mac App Store; security best practice |
| `com.apple.security.network.client` | Granted | Network access for stream playback |
| Hardened Runtime | Enabled | Notarization requirement |
| Minimum macOS | 14.0 (Sonoma) | `MenuBarExtra` + `SMAppService` support; Swift 6 concurrency |

### 6.3 Stream Playback Strategy

> **This is the single biggest technical risk. See §8 (Risks) and §11 (Technical Spike).**

**Primary approach: YouTube IFrame Player API in an off-screen `WKWebView`**

The app embeds a hidden `WKWebView` loading the YouTube IFrame Player with `videoId=tRsQsTMvPNg`. Audio plays through the web view's audio session while the UI remains entirely in the menu bar. Control is via `evaluateJavaScript` calls to the IFrame API (`playVideo()`, `pauseVideo()`, `setVolume()`).

**Why this approach:**
- Stays within YouTube's Terms of Service (uses official embed player, not scraping)
- No `yt-dlp` dependency or URL extraction needed
- Mac App Store compatible
- Handles stream URL rotation automatically (the IFrame player resolves it — YouTube rotates underlying media URLs for 24/7 streams, which would break a direct AVPlayer approach)

**Trade-offs:**
- Higher memory footprint (~200–350 MB with WKWebView vs. ~80–120 MB with AVPlayer)
- WKWebView may be throttled or suspended in `LSUIElement` apps with no visible window
- Less control over audio pipeline (no direct `AVAudioEngine` access)

**Alternative approach (spike fallback): `yt-dlp` subprocess → `AVPlayer`**

If the IFrame approach fails on background suspension or sustained playback, the fallback is:
1. Run `yt-dlp` as a subprocess to extract the HLS manifest URL from the YouTube livestream
2. Feed the manifest URL to `AVPlayer` for native audio playback
3. Re-run `yt-dlp` periodically (every 30–60 min) to refresh expired URLs

**Trade-offs:**
- Lower memory and CPU footprint
- Direct `AVPlayer` API access (volume, routing, metadata)
- **ToS risk**: `yt-dlp` extracts direct stream URLs, which YouTube's ToS may prohibit
- **URL expiration**: YouTube rotates 24/7 stream URLs; requires periodic re-resolution
- **Bundling complexity**: `yt-dlp` is a Python tool; would need to bundle a Python runtime or use a compiled alternative
- **App Store incompatibility**: Subprocess execution of external tools is not allowed in App Sandbox

**Other approaches (not recommended):**

| Approach | Pros | Cons |
|----------|------|------|
| Backend proxy resolver | Clean app, server handles extraction | Infrastructure cost, single point of failure, still ToS gray area |
| Invidious API | Simple HTTP API | Instance reliability, same ToS concerns |
| Open in default browser | Zero implementation | Not a menu bar app; defeats the purpose |

### 6.4 Code Architecture

The app should abstract the playback backend behind a `StreamPlayer` protocol so the IFrame and AVPlayer approaches are swappable:

```swift
protocol StreamPlayer {
    func play()
    func pause()
    func setVolume(_ volume: Float)  // 0.0–1.0
    var isPlaying: Bool { get }
    var state: PlayerState { get }   // .idle, .connecting, .playing, .paused, .error
    var onStateChange: ((PlayerState) -> Void)? { get set }
}

enum PlayerState {
    case idle, connecting, playing, paused, error(String)
}
```

**Module structure:**

```
ClaudeRadio/
├── App/
│   ├── AppDelegate.swift          # LSUIElement lifecycle, status item
│   └── ClaudeRadioApp.swift       # SwiftUI @main entry
├── Player/
│   ├── StreamPlayer.swift          # Protocol
│   ├── YouTubeIFramePlayer.swift   # WKWebView + IFrame API implementation
│   └── AVPlayerBackend.swift       # AVPlayer + yt-dlp implementation (fallback)
├── MenuBar/
│   ├── StatusItemController.swift  # NSStatusItem, icon states
│   └── MenuBarView.swift           # SwiftUI dropdown content
├── MediaKeys/
│   └── RemoteCommandController.swift  # MPRemoteCommandCenter wiring
└── Support/
    ├── StreamConfig.swift          # videoId, embed URL, youtube-nocookie domain
    └── BackgroundActivity.swift    # ProcessInfo.beginActivity wrapper
```

### 6.5 High-Level Flow

```
App Launch
  → Register NSStatusItem (menu bar icon)
  → ProcessInfo.beginActivity(.background) — prevent App Nap
  → Create off-screen WKWebView (or AVPlayer backend)
  → Load YouTube IFrame Player with videoId via youtube-nocookie.com
  → User clicks Play → evaluateJavaScript("player.playVideo()")
  → MPRemoteCommandCenter handles media keys → play/pause
  → MPNowPlayingInfoCenter updates Now Playing UI
  → Monitor stream status; reload web view on failure
  → On sleep/wake: detect via NSWorkspace.didWakeNotification → reconnect
```

### 6.6 Ad Handling Strategy

YouTube may insert ads into the Claude FM livestream (pre-roll, mid-roll). The IFrame Player API does **not** expose reliable ad-specific events for livestreams — `onStateChange` values (`-1` unstarted, `3` buffering) overlap with normal stream transitions and cannot be used to distinguish ads.

**Best-effort detection approach:**

1. **Monitor `player.getCurrentTime()` delta**: During ad playback, `getCurrentTime()` may jump or stall relative to the live edge. Detect anomalies as a possible ad signal.
2. **Monitor `player.getVideoData()`**: Some ad states change the `video_id` or title temporarily. Compare against the known stream ID `tRsQsTMvPNg`.
3. **Volume ducking**: If ad detection triggers, optionally auto-mute the web view (`player.mute()`) and restore on signal end.

**Limitations:**

- Ad detection on livestreams is inherently unreliable — the IFrame API was designed for VOD, not 24/7 streams.
- Mid-roll ads on live streams may not trigger any detectable state change.
- The app must **not** attempt to block or skip ads — this would violate YouTube's ToS.
- Ads are part of the free YouTube stream experience.

**Design decision:** Ad detection is **P1, feature-flagged, disabled by default**. The spike (§11) must validate detection accuracy before the feature is enabled. If detection proves too noisy, demote to P2 or remove entirely. Users should be able to toggle "Auto-mute during ads" in the dropdown.

### 6.7 Autoplay Restrictions

Modern macOS WKWebView inherits Safari's autoplay policy: media with audio may be **blocked from autoplaying** without a prior user gesture. In an `LSUIElement` app with no visible window, there is no natural user gesture to satisfy this requirement.

**Mitigation strategies (to be tested in spike):**

1. **User-initiated first play**: The first `playVideo()` call is triggered by the user clicking the menu bar icon — this counts as a user gesture and should satisfy the autoplay policy for subsequent programmatic calls.
2. **Muted autoplay then unmute**: Load the embed with `mute=1&autoplay=1`, then call `player.unMute()` after the user's first click. Muted autoplay is generally allowed.
3. **WKWebView configuration**: Set `mediaTypesRequiringUserActionForPlayback = []` on the WKWebView configuration to relax the autoplay policy (may work in sandboxed apps, needs testing).

If none of these work, the app will require a one-time "click to enable audio" interaction on first launch — acceptable UX for a menu bar app.

### 6.8 macOS-Specific Behavior

A 24/7 menu bar audio app has unique macOS concerns:

| Concern | Behavior | Mitigation |
|---------|----------|------------|
| **Audio device switching** | If user unplugs headphones or connects AirPods, CoreAudio handles routing automatically for WKWebView. | Test in spike; no code needed unless issues arise. |
| **Sleep/wake cycle** | WKWebView may stop playback when Mac sleeps. On wake, the stream is disconnected. | Listen to `NSWorkspace.didWakeNotification`; trigger auto-reconnect with backoff. |
| **Battery impact** | A WKWebView rendering a YouTube embed continuously can be a significant battery drain on MacBooks. | Consider optional "Pause on battery" setting (P2). Monitor energy impact in Instruments during spike. |
| **Memory pressure** | WKWebView with a 24/7 stream can accumulate memory over hours (JavaScript heap, video buffer). | P2: Memory watchdog — reload WKWebView every N hours or when memory exceeds threshold (e.g., 400 MB). For v1, document as known limitation. |
| **App Nap** | macOS may suspend the app's process when it has no visible window and isn't "active." | `ProcessInfo.processInfo.beginActivity(options: .background)` prevents App Nap. Must be called on launch and held for app lifetime. |

### 6.9 MPNowPlayingInfoCenter Integration

`MPNowPlayingInfoCenter` expects an `MPMediaItem` with title, artist, duration, etc. For a WKWebView-based player, this requires a bridge:

1. Extract metadata from the YouTube embed via JavaScript (`player.getVideoData()` returns `{ video_id, title, author }`)
2. Bridge to `MPNowPlayingItem` / `MPNowPlayingInfoCenter` dictionary
3. Wire `MPRemoteCommandCenter.playCommand` / `pauseCommand` to `evaluateJavaScript` calls

This bridge is non-trivial and should be validated in the spike. For a live stream, `duration` is unknown — set `MPNowPlayingInfoPropertyMediaType` to `.audio` and omit `duration`.

---

## 7. UX / Design

### Menu Bar Icon

- **Template image** (monochrome, adapts to light/dark mode) — radio-wave or speaker icon
- **States**:
  - ▶ Playing — animated waveform or filled icon
  - ⏸ Paused — dimmed icon
  - ⟳ Connecting — spinner overlay
  - ⚠ Error — exclamation badge

### Dropdown Menu

```
┌─────────────────────────────┐
│  Claude FM                  │
│  music for thinking & building │
│  ───────────────────────────│
│  ▶ Play  /  ⏸ Pause         │
│  🔊 ━━━━━━━━○━━━━ Volume    │
│  ───────────────────────────│
│  ✓ Open at Login            │
│  ↗ Open in YouTube          │
│  ───────────────────────────│
│  About Claude Radio         │
│  Quit                       │
└─────────────────────────────┘
```

### Accessibility

Accessibility is required for App Store submission and is the right thing to do:

- **VoiceOver labels**: `NSStatusItem.button?.accessibilityLabel = "Claude Radio, playing"` / `"Claude Radio, paused"` — update on state change
- **Keyboard navigation**: All menu items reachable via arrow keys; Enter to activate
- **Reduce Motion**: Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` — disable icon animations when enabled
- **High contrast**: Provide high-contrast icon variants for `accessibilityDisplayShouldIncreaseContrast`
- **Dynamic Type**: Not applicable (no text in the menu bar icon); dropdown text uses system font sizing

### Design Principles

- **Zero windows**: All interaction via menu bar popover. No main window, no settings window.
- **Template images only**: Never use colored PNGs for status items (breaks dark mode).
- **Instant feedback**: Icon state changes immediately on click, even before stream responds.
- **Attribution**: About panel clearly states the stream is from Anthropic's official Claude YouTube channel and that the app is unofficial.

---

## 8. Privacy

| Aspect | Policy |
|--------|--------|
| **Analytics** | Zero. No crash reporting, no usage tracking, no telemetry. |
| **Telemetry** | Zero. The app does not phone home. |
| **Accounts** | None. No login, no sign-up, no cloud sync. |
| **Network traffic** | Single destination: YouTube IFrame embed loaded from `youtube-nocookie.com` (privacy-enhanced YouTube embed domain — no tracking cookies set on the user). |
| **Data collection** | None. No personal data collected, stored, or transmitted. |
| **Filesystem** | App Sandbox enabled. No access outside app container. |
| **Open source** | Recommended. Open-sourcing the repo allows users to audit the code and verify the privacy claims. |

> **Clarification**: The "no data leaves the device" goal in §4 refers to the app itself not collecting or transmitting user data. The YouTube embed call is inherently a network request to Google's servers (IP address, request headers). Using `youtube-nocookie.com` minimizes this to the bare minimum — no cookies, no ad tracking — but the request itself cannot be avoided.

---

## 9. Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Cold-start to first audio** | < 5 seconds | From app launch to audible stream (with pre-loaded WKWebView) |
| **CPU idle** | < 2% | Activity Monitor / Instruments, app running but paused |
| **CPU playing** | < 5% | Activity Monitor / Instruments, stream playing for 10 min |
| **Memory (IFrame)** | < 350 MB | Xcode memory graph, 8-hour soak test |
| **Memory (AVPlayer)** | < 120 MB | Xcode memory graph, 8-hour soak test |
| **Crash-free rate** | > 99.5% | 24-hour soak test, no crashes or panics |
| **Auto-reconnect success** | Within 30s | After network restoration, stream resumes automatically |
| **Media key response latency** | < 200ms | From key press to play/pause state change |
| **Sleep/wake recovery** | < 10s | From wake notification to stream resumed |
| **Ad detection false positives** | 0 over 1h | If feature flag enabled — spike validation criterion |

---

## 10. Distribution

| Channel | Phase | Notes |
|---------|-------|-------|
| **GitHub Releases (DMG)** | v1.0 — **primary** | Signed + notarized DMG with Sparkle auto-update. Fastest iteration, no Apple review cycle. Best for a 24/7 stream app that may need urgent fixes. |
| **Homebrew Cask** | v1.1 | `brew install --cask claude-radio` (or renamed). After stable v1.0. |
| **Mac App Store** | v1.2+ | After trademark clarity (likely with rename to "Focus FM" or similar). Requires Apple Developer account ($99/yr). Sandbox-compatible with IFrame approach. |

**Rationale**: GitHub Releases first for faster iteration. A 24/7 stream app may need urgent fixes when YouTube changes the IFrame API or the stream goes down — the App Store review cycle (1–7 days) is too slow for that. App Store submission deferred until the app is stable and the naming/trademark question is resolved.

**Code signing & notarization**: Required for both App Store and direct distribution (Gatekeeper). Developer ID certificate for direct distribution; App Store certificate for MAS.

---

## 11. Technical Spike (Pre-Build Validation)

> **Before any feature work, validate the core technical risk in a 1–2 day dual-path spike.**

### Spike Goal

Prove that audio from the Claude FM YouTube livestream can be played and controlled from a headless `LSUIElement` menu bar app. Evaluate both the IFrame and AVPlayer approaches in parallel.

### Track A: IFrame (WKWebView + YouTube IFrame Player API)

| # | Test | Pass Criteria |
|---|------|---------------|
| A1 | Load `https://www.youtube-nocookie.com/embed/tRsQsTMvPNg` in off-screen WKWebView | Page loads, no errors |
| A2 | Audio plays without any visible window | Audible audio |
| A3 | `player.playVideo()` / `player.pauseVideo()` via `evaluateJavaScript` | State changes correctly |
| A4 | `player.setVolume(50)` via JS injection | Volume changes |
| A5 | Audio continues when app is backgrounded (no visible window) | Audio persists for 30+ minutes |
| A6 | `ProcessInfo.beginActivity(.background)` prevents App Nap | Audio persists 30+ min with no visible window |
| A7 | `MPRemoteCommandCenter` play/pause responds to media keys | < 200ms latency |
| A8 | `LSUIElement = YES` removes Dock icon | No Dock icon, menu bar icon present |
| A9 | App Sandbox enabled — audio still plays | No sandbox denial |
| A10 | Sleep/wake: stream resumes after Mac sleeps and wakes | Auto-reconnect within 10s |
| A11 | Sustained playback: 30+ min with memory monitoring | Memory < 350 MB after 30 min |
| A12 | Autoplay: test muted-autoplay-then-unmute workaround | Audio enabled after first user click |
| A13 | Ad detection: monitor `getCurrentTime()` and `getVideoData()` for anomalies | Document detection accuracy over 1h sample |
| A14 | `MPNowPlayingInfoCenter` displays stream title/author from `player.getVideoData()`; Now Playing widget in Control Center reflects state within 2s of play/pause | Now Playing UI updates correctly |
| A15 | Study **YTAudioBar** open-source codebase (GitHub) for WKWebView configuration, autoplay handling, and App Nap prevention | Document reusable patterns; don't reinvent solved problems |

### Track B: AVPlayer (yt-dlp subprocess → AVPlayer)

| # | Test | Pass Criteria |
|---|------|---------------|
| B1 | `yt-dlp` extracts HLS manifest URL from livestream | Valid manifest URL returned |
| B2 | `AVPlayer` plays the manifest URL | Audible audio |
| B3 | `AVPlayer` volume control works | Volume changes |
| B4 | Audio continues in background (LSUIElement) | Audio persists for 30+ minutes |
| B5 | URL expiration: how long before the URL stops working? | Document TTL (expected < 60 min) |
| B6 | Auto-refresh: re-run `yt-dlp` on URL expiration | Stream resumes after refresh |
| B7 | Memory footprint after 30 min | Memory < 120 MB |
| B8 | Media key response via `MPRemoteCommandCenter` | < 200ms latency |

### Decision Criteria

| Criterion | IFrame (Track A) | AVPlayer (Track B) |
|-----------|------------------|-------------------|
| **ToS safety** | ✅ Official embed | ⚠️ Gray area — URL extraction |
| **URL rotation** | ✅ Handled automatically | ❌ Requires periodic re-resolution |
| **App Store** | ✅ Compatible | ❌ Subprocess not allowed in sandbox |
| **Memory** | ⚠️ ~200–350 MB | ✅ ~80–120 MB |
| **Sustained playback** | ❓ Must pass A5/A6/A11 | ✅ Likely fine |
| **Autoplay** | ❓ Must pass A12 | ✅ No autoplay restrictions |

**Go/no-go gate**: The spike must pass before any feature work begins. If Track A passes A1–A11, proceed with IFrame. If A5/A6 (background persistence) fails, fall back to Track B with documented ToS risk. If both fail, the project is blocked — reassess scope.

---

## 12. Known Limitations (v1)

- **YouTube ads** may interrupt the stream; auto-mute is best-effort (feature-flagged), not guaranteed
- **YouTube ToS** permits embed playback, but commercial use / redistribution of the stream may be restricted
- **Unofficial**: not affiliated with or endorsed by Anthropic
- **"Claude" trademark** is Anthropic's; the app name may need to change before App Store submission
- **Autoplay** may require a one-time user click on first launch (Safari autoplay policy)
- **Stream may go offline**: app will retry silently and show error icon; no notification spam
- **Memory growth**: WKWebView may accumulate memory over multi-hour sessions; v1 does not include a memory watchdog (planned for P2)
- **No offline playback**: requires continuous internet connection
- **No track metadata** in v1: now-playing info depends on YouTube API availability (P1)
- **Single stream only**: v1 plays only the Claude FM stream; custom URLs are P2

---

## 13. Open Questions

1. **Final app name — DECISION GATE (deadline: end of Week 4)**:
   - **Working title**: "Claude Radio"
   - **Risk**: "Claude" is Anthropic's registered trademark; shipping under this name risks DMCA takedown, App Store rejection, or cease-and-desist — even for a free, open-source, unofficial app.
   - **Options**: (a) "Claude Radio" — keep, accept legal risk; (b) "Focus FM" — neutral, evokes the focus-music use case; (c) "Menu Bar FM" — descriptive, safe; (d) other.
   - **Gate criteria**: Must resolve before Week 5 (release prep). If no explicit permission from Anthropic by then, **default to "Focus FM"** with Claude FM as the default preset stream URL.
   - **Recommendation**: Commit to "Focus FM" now to avoid rebranding assets, repo URL, and App Store metadata later.
2. **Ad detection accuracy threshold**: what false-positive rate is acceptable to ship the feature? Need spike data (A13) to decide.
3. **Minimum macOS version**: 14.0 (Sonoma) vs. 13.0 (Ventura) — affects `SMAppService` and `MenuBarExtra` availability. **Recommendation**: 14.0 for v1; consider 13.0 backport if demand exists.
4. **Stream metadata**: is there any way to get now-playing track info from the Claude FM stream? Check YouTube description updates, stream chat, or IFrame `getVideoData()`.
5. **WKWebView long-term memory**: does memory stabilize or grow unboundedly over 8+ hours? Spike tests 30 min; need a longer soak test before release.

---

## 14. Development Milestones

| Week | Milestone | Deliverables |
|------|-----------|--------------|
| **1** | Dual-path spike | Track A + Track B prototypes; pick winner; go/no-go decision |
| **2** | Core menu bar app | Icon, play/pause, volume, player backend integration |
| **3** | Persistence & media | Open at Login, media keys, auto-reconnect, sleep/wake handling |
| **4** | Polish | Error states, accessibility, ad detection (if spike validates), `MPNowPlayingInfoCenter` |
| **5** | Release prep | Code signing, notarization, Sparkle integration, GitHub Release (v1.0 DMG) |
| **6+** | Post-release | P1 features, Homebrew Cask, App Store prep (with rename if needed) |

---

## 15. Competitive Context

Web research (2026-07-02) confirms this is an active category with multiple shipped apps:

| App | Platform | Description | Relevance |
|-----|----------|-------------|-----------|
| **Tubist** | [Mac App Store](https://apps.apple.com/us/app/tubist-menu-bar-for-youtube/id1603180719) | Menu bar YouTube player; audio continues while you work, switch apps, or close browser tabs | **Strong precedent**: proves Apple approves menu bar YouTube embed apps — de-risks App Store lane |
| **YTAudioBar** | Open source (GitHub) | macOS menu bar YouTube audio player, Swift/SwiftUI | **Technical reference**: study their WKWebView configuration during spike — likely solved autoplay, background persistence, and App Nap already |
| **Petit Player** | [getpetit.github.io](https://getpetit.github.io/) | Menu bar YouTube Music player with global shortcuts, PiP, media keys | Shows feature expectations for the category (shortcuts, PiP) |
| **YouTube Lofi Music** | [onmymenubar.app](https://onmymenubar.app/youtube-lofi-music/) | Menu bar app with 7 pre-built lofi/chillhop/ambient stations | **Closest conceptual competitor**: pre-built station model; Claude Radio is single-stream zero-config |

**Differentiation**: Claude Radio is the only menu bar app dedicated to the Claude FM stream specifically, with zero-config single-stream UX. Competitors are general-purpose YouTube browsers or multi-station players. Claude Radio is a one-stream radio — not a browser replacement, not a playlist manager.

**Impact on App Store risk**: Tubist's active App Store presence is strong evidence that Apple approves this app category. The "website wrapper" rejection risk (§16) is downgraded accordingly.

---

## 16. Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| **YouTube ToS violation** (if scraping URLs) | 🔴 High | Use official IFrame Player API via `WKWebView` — stays within ToS. Do NOT extract direct stream URLs. |
| **Anthropic trademark / branding** | 🔴 High | "Claude" is Anthropic's trademark. (1) Use original icon — never the Claude logo. (2) Clearly state "unofficial" in About panel. (3) If Anthropic objects or App Store flags it, **rename to "Focus FM" or "Menu Bar FM"**. (4) Design the app from day one to support custom stream URLs so branding is decoupled from stream source. |
| **Stream goes offline** | 🟡 Medium | Detect player state `ENDED` / error events; show error icon; offer "Open in YouTube" fallback. |
| **macOS background audio termination** | 🟡 Medium | `ProcessInfo.beginActivity(options: .background)` prevents App Nap. Test sustained playback over 30+ min in spike. |
| **Menu bar icon rendering in dark mode** | 🟢 Low | Use template images exclusively; test both appearances. |
| **Global hotkey conflicts** | 🟢 Low | v1 uses only `MediaPlayPause` (conflict-free). Custom hotkeys deferred to P2. |
| **YouTube IFrame API changes** | 🟡 Medium | Pin to a known-working IFrame API version; abstract player interface for swappable backend. |
| **App Store rejection — "website wrapper"** | 🟢 Low | **Tubist** (menu bar YouTube player) is actively approved on the Mac App Store — strong precedent that Apple accepts this category. Mitigate by ensuring genuine native functionality: menu bar integration, media keys, volume control, Open at Login, accessibility support — not just a web view. |
| **WKWebView suspension in LSUIElement apps** | 🟡 Medium | Some macOS versions throttle or suspend web views with no visible window. Spike must test sustained playback over 30+ minutes, after sleep/wake, and on battery. Mitigation: `ProcessInfo.beginActivity(.background)` + 1×1px off-screen window if needed. |
| **YouTube ads interrupting stream** | 🟡 Medium | Ads are part of the free YouTube stream experience. Best-effort auto-mute during detected ads (§6.6), feature-flagged. Do NOT attempt to block or skip — ToS violation. Document as a known limitation. |
| **Memory growth over long sessions** | 🟡 Medium | WKWebView may accumulate memory over hours. v1: document as known limitation. P2: memory watchdog that reloads WKWebView when memory exceeds threshold. |
| **Battery drain on MacBooks** | 🟢 Low | WKWebView rendering continuously can drain battery. P2: optional "Pause on battery" setting. Monitor energy impact in spike. |

---

## 17. Appendix

| Resource | URL |
|----------|-----|
| Claude FM stream | [youtube.com/watch?v=tRsQsTMvPNg](https://www.youtube.com/watch?v=tRsQsTMvPNg) |
| Claude YouTube channel | [youtube.com/@claude](https://www.youtube.com/@claude) |
| YouTube IFrame Player API | [developers.google.com/youtube/iframe_api_reference](https://developers.google.com/youtube/iframe_api_reference) |
| YouTube nocookie embed domain | `youtube-nocookie.com` — privacy-enhanced embed (no tracking cookies) |
| Apple `MenuBarExtra` docs | [developer.apple.com/documentation/swiftui/menubaretra](https://developer.apple.com/documentation/swiftui/menubaretra) |
| `NSStatusItem` docs | [developer.apple.com/documentation/appkit/nsstatusitem](https://developer.apple.com/documentation/appkit/nsstatusitem) |
| `SMAppService` (login items) | [developer.apple.com/documentation/servicemanagement/smappservice](https://developer.apple.com/documentation/servicemanagement/smappservice) |
| `MPRemoteCommandCenter` | [developer.apple.com/documentation/mediaplayer/mpremotecommandcenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter) |
| `MPNowPlayingInfoCenter` | [developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter) |
| `ProcessInfo.beginActivity` | [developer.apple.com/documentation/foundation/processinfo](https://developer.apple.com/documentation/foundation/processinfo) |
| Sparkle auto-update framework | [github.com/sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) |
| Apple Accessibility Guidelines | [developer.apple.com/design/human-interface-guidelines/accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) |

---

*This PRD is a living document. Update the status field as the project progresses through spike → alpha → beta → release.*