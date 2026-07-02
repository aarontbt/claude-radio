# AGENTS.md

Claude Radio is an unofficial macOS menu bar app that plays Anthropic's official
24/7 "Claude FM" YouTube livestream (video id `tRsQsTMvPNg`) as background audio.
Menu bar only: no Dock icon, no main window, no settings window.

Human-facing overview is in `README.md`. Built by
[aarontbt](https://github.com/aarontbt), MIT licensed (see `LICENSE`).

## Setup commands

- Install XcodeGen once: `brew install xcodegen`
- Everything else regenerates automatically: `make generate` runs `xcodegen generate`,
  and every other `make` target depends on it.

## Dev environment tips

- `project.yml` is the single source of truth for the Xcode project. **Never
  hand-edit `ClaudeRadio.xcodeproj`.** It is git-ignored and fully regenerated.
- After changing `project.yml` or adding/removing source files, just run any
  `make` target; regeneration happens automatically.
- Source tree:
  ```
  ClaudeRadio/
  ├── App/                # ClaudeRadioApp.swift (@main), AppDelegate.swift (wires everything together)
  ├── Playback/            # PlaybackState, WebViewPlaybackEngine, ReconnectManager (backoff)
  ├── NowPlaying/           # NowPlayingInfoUpdater, MediaKeyController
  ├── MenuBar/             # StatusIconProvider, StatusItemController (status item, click/scroll, dropdown)
  ├── Settings/             # AppSettings (UserDefaults), LaunchAtLogin (SMAppService)
  ├── About/                # AboutView (SwiftUI), AboutWindowController
  └── Resources/Assets.xcassets/   # status-bar icons (SF Symbols), AppIcon (real PNGs)
  ClaudeRadioTests/         # unit tests
  design/                   # AppIcon-source-1024.png (master) + make_icon.swift (regenerates it)
  ```

## Code style

- Swift 6, strict concurrency. `WebViewPlaybackEngine` and `ReconnectManager` are
  `@MainActor`. Anything called from a context that isn't guaranteed to be on the
  main thread (e.g. `MPRemoteCommandCenter` handlers in `MediaKeyController`) must
  hop in explicitly with `Task { @MainActor in ... }`, capturing the specific
  object needed rather than `self`, to satisfy Swift 6's sending checks.
- Status bar icons must always be template images (`isTemplate = true`),
  monochrome. Never colored icons in the menu bar.
- No em dashes and no Oxford commas in prose: `AboutView.swift`'s copy and this
  file. Standing style preference, not a one-time edit.

## Testing instructions

- Run the unit tests: `make test`
- Live playback isn't meaningfully unit-testable (depends on network + YouTube's
  embed player). What's covered instead: `Backoff` (the pure backoff-delay struct
  `ReconnectManager` uses, in `ReconnectManagerTests.swift`), `PlaybackState`
  equality/description (`PlaybackStateTests.swift`), `AppSettings`
  clamping/persistence (`AppSettingsTests.swift`, isolated `UserDefaults(suiteName:)`
  per test, not `.standard`).
- After any change to `Playback/` or `NowPlaying/`, manually re-verify: audio
  plays and is controllable via `play()`/`pause()`/`setVolume()`, audio keeps
  playing with no window visible, the status item shows no Dock icon
  (`LSUIElement`), the app still works with App Sandbox enabled and media keys
  still route to `MPRemoteCommandCenter`.
- Not yet verified by hand: right-click-to-open-menu, scroll-wheel-to-adjust-volume
  on the live status item and hardware media key presses. All three need either
  Accessibility or Screen Recording permission to automate, which this environment
  didn't have granted. Do a hands-on check on a real machine before shipping.

## Build and run

```
make build       # generate + xcodebuild build (output in build/Debug/)
make run          # build + open the app
make archive     # Release archive (build/ClaudeRadio.xcarchive)
make clean       # remove build/, DerivedData/ and the generated .xcodeproj
```

Verify a change actually works by running `make run` and checking: a status item
appears in the menu bar, and `System Events` reports
`background only of process "ClaudeRadio"` as `true` (no Dock icon).

## PR instructions

- Don't commit unless explicitly asked.
- Before calling anything done: build, run the test suite and launch the app for
  real. A change isn't verified until you've watched it work, not just compiled.
- Don't leave temporary diagnostic or self-test code (timers that call debug
  methods, `SPIKE-TEST`/`DIAG`-style logging) in the tree after verifying with it.
  Remove it in the same pass.

## Hard constraints, do not violate

- No Dock icon, no main window. `LSUIElement` stays `YES`; activation policy stays
  `.accessory`. Any `Settings`/other SwiftUI scenes must not present a visible window.
- No scraping or resolving raw YouTube stream URLs (no `yt-dlp`/`youtube-dl`, no
  reverse-engineered CDN links). Only the official `https://www.youtube.com/embed/`
  IFrame Player API.
- Never use the Claude logo/wordmark or Anthropic trademarks in the app icon or UI
  in a way implying official endorsement. The About panel must clearly state the
  app is unofficial/fan-made, with attribution to Anthropic's official Claude
  YouTube channel. Do not add Anthropic/Claude mascot or logo imagery without an
  explicit, informed user override; if asked again, surface this constraint rather
  than silently complying or refusing.
- Don't commit `ClaudeRadio.xcodeproj/`, `build/` or `DerivedData/`. Always
  regenerate via `xcodegen generate`.
- Preserve App Sandbox + `com.apple.security.network.client`; don't add broader
  entitlements without justification (Mac App Store submission is a target channel).
- `tRsQsTMvPNg` is the only stream target for v1. Don't hardcode alternate streams
  without explicit user approval.

## Known gotchas

Facts that cost real debugging time once; don't relearn them the hard way.

- The off-screen `WKWebView` must be hosted in a real `NSWindow` kept within the
  visible screen frame at `alphaValue = 0.01`, not literally off-screen and not
  un-windowed. WebKit throttles JS timers/media in a fully off-screen, occluded,
  or un-windowed web view.
- The host HTML's `baseURL` must never be `https://www.youtube.com`. The IFrame
  API treats that as a self-embed and fails with player error 152. Use a neutral
  origin (currently `https://claude-radio.app`, unregistered, used only as a label).
- `PRODUCT_NAME` in `project.yml` must not contain a space. It breaks XcodeGen's
  default `TEST_HOST` templating for the unit test target. Keep the internal
  product/target name `ClaudeRadio` and set the user-visible name via
  `INFOPLIST_KEY_CFBundleDisplayName` instead.
- `ReconnectManager`'s 15s stall watchdog must stay. The YouTube IFrame player can
  wedge in `.connecting` without ever firing another `stateChange` or `onError`
  event; without the watchdog there is no recovery path short of quitting the app.
- `WebViewPlaybackEngine.runPlayerCommand`'s trailing `true;` in the injected JS
  must stay. Without it, every successful call reports through the completion
  handler as "JavaScript execution returned a result of an unsupported type",
  a false positive that looks like a real error.
- `WebViewPlaybackEngine` routes its `WKScriptMessageHandler` through a private
  `WeakScriptMessageHandler` proxy. Registering `self` directly would create a
  retain cycle (`engine -> webView -> configuration -> userContentController -> engine`).
- `AboutView`'s disclaimer/description/trademark text is one merged `Text` on
  purpose; don't re-split it into multiple `Text` views. `AboutWindowController`
  sets `hosting.sizingOptions = [.minSize, .maxSize]` on purpose; removing it
  brought back a real truncation bug where the window kept a fixed size instead
  of growing to fit longer content.
- Measured memory footprint (main app + WebContent + GPU + Networking helper
  processes) at rest is about 199MB, against a target of under 150MB. This is a
  consequence of the WKWebView architecture validated in an early technical
  spike, not a bug with a small fix. Don't "fix" it without a product discussion;
  the real fix would mean reopening the WKWebView-vs-AVPlayer decision.

## Architecture

- Swift 6 + SwiftUI/AppKit, macOS 14+ (Sonoma) minimum.
- `NSStatusItem` for the menu bar presence, `LSUIElement=YES` / `.accessory`
  activation policy for no Dock icon.
- Playback: an off-screen `WKWebView` loading the YouTube IFrame Player API
  (`https://www.youtube.com/embed/tRsQsTMvPNg`), controlled via
  `evaluateJavaScript`. Chosen over scraping/`yt-dlp` or a backend proxy
  specifically to stay within YouTube's ToS and keep the app Mac-App-Store-eligible.
  **Do not relitigate this choice** without re-validating that background audio,
  App Sandbox, no Dock icon and media keys all still work. If that validation
  fails, the fallback is `AVPlayer` + a resolver.
- Media keys / background audio: `MPRemoteCommandCenter` / `MPNowPlayingInfoCenter`.
- Launch at login: `SMAppService`.
