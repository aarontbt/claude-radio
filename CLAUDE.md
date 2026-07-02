# Claude Radio

Unofficial macOS menu bar app that plays Anthropic's official 24/7 "Claude FM" YouTube
livestream (video id `tRsQsTMvPNg`) as background audio. Menu bar only: no Dock icon,
no main window, no settings window. Full requirements/rationale/feature phases (P0/P1/P2)
live in `PRD.md`. Read it before making architecture-level changes.

Built by [aarontbt](https://github.com/aarontbt), MIT licensed (see `LICENSE`).

## Status

Milestone 0 (repo bootstrap) and **Milestone 1 (technical spike, PRD §10) both
complete and passed**. The `WKWebView` + YouTube IFrame Player API approach is
validated. Empirically confirmed:
- Audio plays and reaches YT player state `1` (playing); `play()`/`pause()` JS calls
  reliably drive real state transitions (verified via timed self-test, not just autoplay).
- Persists in the background: the off-screen `WKWebView` is hosted in a real `NSWindow`
  kept within the visible screen frame at `alphaValue = 0.01` (not literally off-screen
  and not un-windowed). A fully un-windowed `WKWebView`, or one in an off-screen or
  occluded window, risks WebKit throttling JS timers/media. This is why
  `WebViewPlaybackEngine` positions the host window this way; don't "simplify" it back
  to off-screen coordinates or no window without re-testing.
- App Sandbox: playback works despite non-fatal WebKit `WebContent` sandbox log noise
  (pasteboard/RunningBoard/networkd-settings denials). This is expected sandbox friction
  for a sandboxed `WKWebView` host, not blocking.
- `LSUIElement=YES` / `.accessory` confirmed via `System Events` (`background only` is
  `true`). No Dock icon.
- One gotcha found and fixed: do **not** set the host HTML's `baseURL` to
  `https://www.youtube.com`. The IFrame API treats that as a self-embed and fails with
  YT player error 152. Use a neutral origin (currently `https://claude-radio.app`,
  unregistered, used only as an origin label).
- Not yet verified: hardware media key routing via `MPRemoteCommandCenter`. Wiring
  exists (`NowPlaying/MediaKeyController.swift`) but needs a physical key-press test,
  which couldn't be automated (no Accessibility permission in this environment).

**Milestone 2 (P0 feature build-out) complete.** Built: full icon state machine
(`MenuBar/StatusIconProvider.swift`), `StatusItemController` (left-click toggles
play/pause, right-click opens the full dropdown, scroll-over-icon adjusts volume),
volume slider embedded in the menu, `ReconnectManager` exponential backoff,
`Settings/AppSettings.swift` (UserDefaults-backed volume + launch-at-login),
`Settings/LaunchAtLogin.swift` (`SMAppService`), `About/AboutView.swift` +
`AboutWindowController`. Empirically confirmed via temporary self-test hooks (added,
verified, then removed; don't leave `SPIKE-TEST`-style code in the tree):
- `SMAppService.mainApp.register()`/`.unregister()` both succeed even when launched
  from the ad-hoc-signed `build/Debug/` output (not `/Applications`). No special
  handling needed for dev builds.
- `AboutWindowController.show()` genuinely presents an on-screen window
  (`window.isVisible == true`, `occlusionState == .visible`, real frame on the
  built-in display) despite `.accessory` activation policy. Accessory apps can show
  on-demand windows fine; this isn't a workaround.
- A product-name gotcha: `PRODUCT_NAME: "Claude Radio"` (with a space) breaks
  XcodeGen's default `TEST_HOST` templating for the unit test target. Fixed by keeping
  the internal product/target name `ClaudeRadio` (no space) and setting the
  user-visible name via `INFOPLIST_KEY_CFBundleDisplayName`. The built app is
  `build/Debug/ClaudeRadio.app`, not `"Claude Radio.app"`.

**Follow-up polish pass**: every dropdown item now has a template SF Symbol icon
(Play/Pause swaps `play.fill`/`pause.fill` in `render(state:)`, Launch at Login uses
`power`, Open in YouTube uses `arrow.up.forward.square`, About uses `info.circle`,
Quit uses `xmark.circle`) via `StatusItemController.symbol(_:)`. Quit and the Launch
at Login checkmark-state toggle were already present since Milestone 2 (re-confirmed,
not re-added). `launchAtLoginMenuItem.state` mirrors `LaunchAtLogin.isEnabled` and
flips on every successful `toggleLaunchAtLogin()` call.

**Bugfix: "Play gets stuck"** (found via real user report, reproduced and fixed).
Clicking Play could leave the icon frozen on the "connecting" spinner forever with no
audio. Root cause: the YouTube IFrame player normally flaps between `stateChange -1`
(unstarted) and `3` (buffering) for under a second before reaching `1` (playing). That
flapping itself is normal live-stream startup behavior, not a bug. But occasionally the
player wedges mid-flap and never fires another `stateChange` or `onError` event at all,
and `ReconnectManager` previously only reacted to explicit `.error`, so a silent stall
had no recovery path. Fixed by adding a stall watchdog
(`ReconnectManager.armStallWatchdog()`, `connectingStallTimeout = 15s`): any time state
enters `.connecting`, a 15s timer arms; if it fires before state moves on, it's treated
as a stall and reconnects through the same backoff path as `.error`. This also now
protects the *initial* page load (before any Play click), which previously had zero
timeout if the WKWebView's first `youtube.com` fetch hung. Don't remove this watchdog
without a replacement. `.connecting` reaching a dead end with no further events is a
real, observed failure mode, not a hypothetical.

**About panel: mascot request declined, kept short, attribution added.**
The user asked to add Anthropic's official Claude mascot to the About panel; declined
(with the user's sign-off) because it directly contradicts the PRD's own explicit
stance and the "no Claude logo/mascot" hard constraint below. Using Anthropic's actual
trademarked artwork in an unofficial, redistributed app risks implying endorsement,
which is exactly what that constraint exists to prevent. Kept the original SF Symbol
glyph instead. **Do not add Anthropic/Claude mascot or logo imagery here without an
explicit, informed user override of that constraint.** If asked again, surface the
same conflict rather than silently complying or silently refusing.
`AboutView.swift` was first expanded with a long attribution paragraph, which exposed
a real bug: `AboutWindowController` created its `NSWindow` at a fixed initial size, so
longer SwiftUI content just got clipped instead of the window growing. Fixed by
setting `hosting.sizingOptions = [.minSize, .maxSize]` on the `NSHostingController`.
The user then asked for the About text to be short and simple and for all em dashes
and Oxford commas removed from the copy, which is now the standing style for this
file's content: keep About panel text brief, and avoid em dashes and Oxford commas
throughout `AboutView.swift` and this file. Text was then further condensed into a
single paragraph (disclaimer, description and trademark note merged into one `Text`)
with the links and the "Built by" credit kept as separate elements below it. Don't
re-split that paragraph back into multiple `Text` views. Don't remove `sizingOptions` or
re-introduce a fixed-size `NSWindow` for this panel; any future copy growth will
silently truncate again without it.

**Code review pass (advisor-assisted) fixed five real issues, flagged one that
isn't a code fix.** In severity order:
1. `WebViewPlaybackEngine`'s `onStateChange` handler never mapped YT state `0`
   ("ended") to anything, so a live stream that dropped via "ended" (not "error")
   left the icon showing "playing" forever with no recovery. Now maps `case 0` to
   `.error`, which `ReconnectManager` already knows how to recover from. Verified
   end to end with a temporary JS-injection self-test: play, simulate ended, watch
   the reconnect/backoff/reload cycle actually fire, then removed the test hook.
2. **Not fixed, flagged instead**: measured actual memory footprint (main app +
   WebContent + GPU + Networking helper processes) at rest, paused, not even
   playing: about 199MB, versus the PRD's "Memory < 150 MB" goal. This is a
   consequence of the WKWebView architecture choice validated in the Milestone 1
   spike, not a bug with a small fix. Revisiting it means reopening the
   WKWebView-vs-AVPlayer decision, which needs a product call, not a silent
   rewrite. Don't "fix" this without discussing the tradeoff first.
3. `play()`/`pause()`/`setVolume()` called `player.X()` with no completion handler
   and no guard, so a click during the first ~1-2s load threw a JS ReferenceError
   that was silently discarded. `runPlayerCommand()` now wraps calls in a
   `typeof player !== 'undefined'` guard and logs any real evaluateJavaScript
   error. Watch out if touching this again: the guarded block evaluates to
   `undefined`, which WKWebView's completion handler reports as "JavaScript
   execution returned a result of an unsupported type", a false positive on every
   successful call. Fixed by appending `true;` so the script always returns a
   bridgeable value. If you remove that trailing `true;`, you'll reintroduce log
   spam that looks like errors but isn't.
4. `WebViewPlaybackEngine` registered itself directly as the `WKScriptMessageHandler`,
   which `WKUserContentController` retains strongly, creating
   `engine -> webView -> configuration -> userContentController -> engine`. Fixed
   with a private `WeakScriptMessageHandler` proxy that holds a weak reference and
   forwards through `MainActor.assumeIsolated` (safe here because WebKit documents
   `WKScriptMessageHandler` callbacks as always arriving on the main thread).
5. Isolation was inconsistent: only `StatusItemController` was `@MainActor`, while
   `WebViewPlaybackEngine`'s `state` was mutated from a WKWebView callback and read
   from `MediaKeyController`'s `MPRemoteCommandCenter` handlers, which are **not**
   guaranteed to run on the main thread. `WebViewPlaybackEngine` and
   `ReconnectManager` are now `@MainActor`. `MediaKeyController` stays actor-agnostic
   but hops into `Task { @MainActor in ... }` for every engine call, capturing the
   `engine` reference directly (not `self`) to satisfy Swift 6's sending checks.

Also from that pass: `NowPlayingInfoUpdater` used to publish "Claude FM by
Anthropic" to Control Center even while `.idle`/`.connecting`/`.error`, before the
user had ever pressed Play. It now only publishes for `.paused`/`.playing` and
clears the Now Playing entry otherwise. Stale "spike"/"unproven" comments in
`WebViewPlaybackEngine.swift`, `MediaKeyController.swift` and
`NowPlayingInfoUpdater.swift` (left over from Milestone 1, before these were
validated and shipped) were rewritten to reflect current status. All remaining em
dashes in source files (`WebViewPlaybackEngine.swift`, `ReconnectManager.swift`,
`StatusIconProvider.swift`, `StatusItemController.swift`,
`AboutWindowController.swift`) were removed to match the standing style rule.

**App icon added, then restyled per user request.** `Resources/Assets.xcassets/AppIcon.appiconset`
previously had no actual images (just an empty `Contents.json`). Now has real PNGs
at all ten required mac sizes. Current design: a rounded-square background in
`#D4A27F` (warm tan, with a subtle lighter-center/deeper-edge gradient) with a
hand-drawn-style glyph, a slightly irregular dot and three wobbly (deterministic
sine-perturbed, not random) radio-wave arcs in dark coffee-brown ink, drawn from
scratch in Core Graphics (`design/make_icon.swift`, master at
`design/AppIcon-source-1024.png`, both kept in the repo so the icon can be
regenerated or restyled without redrawing by hand). No Claude logo or mascot
artwork, consistent with the hard constraint below.
**Worth knowing**: `#D4A27F` is in the same warm terracotta/tan family as
Anthropic's own brand palette, though not their exact logo color. Flagged this to
the user before applying it (a single color is a much weaker trademark concern than
a logo/mascot, unlike the declined mascot request above) and they confirmed. If this
choice is ever revisited, that's the tradeoff being made. To regenerate:
`swift design/make_icon.swift <output.png>` produces a fresh 1024x1024 master, then
`sips -z <px> <px>` down to each size named in `AppIcon.appiconset/Contents.json`.

**Not verified, needs a manual pass at the physical machine**: right-click-to-open-menu
and scroll-wheel-to-adjust-volume on the live status item, and hardware media key
presses. All three require either Accessibility or Screen Recording TCC permission to
automate or observe, which this dev environment didn't have granted. The code follows
standard, well-established AppKit patterns for all three (local `NSEvent` monitor
filtered by the status item's window for scroll; the `statusItem.menu` +
`performClick(nil)` + clear-menu trick for right-click; `MPRemoteCommandCenter` target
registration for media keys). Do a hands-on check before shipping.

**Next: Milestone 3 (P1)**: now-playing metadata, mute-on-fullscreen-app-activation,
`UserNotifications` error alerts, more connection-status icon variants. Also still
outstanding from Milestone 2: a notarization dry run, and a decision on the memory
footprint versus the PRD's Goals budget (see the code review notes above).

## Architecture

- Swift 6 + SwiftUI/AppKit, macOS 14+ (Sonoma) minimum.
- `NSStatusItem` for the menu bar presence, `LSUIElement=YES` / `.accessory` activation
  policy for no Dock icon.
- Playback: an off-screen `WKWebView` loading the YouTube IFrame Player API
  (`https://www.youtube.com/embed/tRsQsTMvPNg`), controlled via `evaluateJavaScript`.
  Chosen over scraping/`yt-dlp` or a backend proxy specifically to stay within YouTube's
  ToS and keep the app Mac-App-Store-eligible. **Do not relitigate this choice** except
  by re-running/updating the Milestone 1 spike results (PRD §10). If the spike fails,
  the documented fallback is `AVPlayer` + a resolver.
- Media keys / background audio: `MPRemoteCommandCenter` / `MPNowPlayingInfoCenter`.
- Launch at login: `SMAppService`.

## Project scaffolding: XcodeGen

`project.yml` is the single source of truth for the Xcode project. **Never hand-edit
`ClaudeRadio.xcodeproj`.** It is git-ignored and fully regenerated. After changing
`project.yml` or adding/removing source files, run `xcodegen generate` (or any Makefile
target below, which regenerates automatically).

## Build / run / test

```
make generate   # xcodegen generate
make build       # generate + xcodebuild build (output in build/Debug/)
make test        # generate + xcodebuild test
make run          # build + open the app
make archive     # Release archive (build/ClaudeRadio.xcarchive)
make clean       # remove build/, DerivedData/ and the generated .xcodeproj
```

Verify a change actually works by running `make run` and checking: a status item
appears in the menu bar, `Activity Monitor`/`ps` shows no Dock presence (or check via
`System Events`: `background only of process "ClaudeRadio"` should be `true`).

## Hard constraints, do not violate

- No Dock icon, no main window. `LSUIElement` stays `YES`; activation policy stays
  `.accessory`. Any `Settings`/other SwiftUI scenes must not present a visible window.
- No scraping or resolving raw YouTube stream URLs (no `yt-dlp`/`youtube-dl`, no
  reverse-engineered CDN links). Only the official `https://www.youtube.com/embed/`
  IFrame Player API.
- Status bar icons must always be template images (`isTemplate = true`), monochrome.
  Never use colored icons in the menu bar.
- Never use the Claude logo/wordmark or Anthropic trademarks in the app icon or UI in a
  way implying official endorsement. The About panel must clearly state the app is
  unofficial/fan-made, with attribution to Anthropic's official Claude YouTube channel.
- Don't commit `ClaudeRadio.xcodeproj/`, `build/` or `DerivedData/`. Always regenerate
  via `xcodegen generate`.
- Preserve App Sandbox + `com.apple.security.network.client`; don't add broader
  entitlements without justification (Mac App Store submission is a target channel).
- `tRsQsTMvPNg` is the only stream target for v1. Don't hardcode alternate streams
  without a PRD update.
- Keep About panel copy short and simple, and avoid em dashes and Oxford commas in it
  (and in this file). This is a standing style preference, not a one-time edit.

## Source tree

```
ClaudeRadio/
├── App/                  # ClaudeRadioApp.swift (@main), AppDelegate.swift (.accessory policy, wires everything together)
├── Playback/              # PlaybackState, WebViewPlaybackEngine (spike-validated), ReconnectManager (backoff)
├── NowPlaying/             # NowPlayingInfoUpdater, MediaKeyController (media-key routing itself not hardware-tested)
├── MenuBar/               # StatusIconProvider (per-state SF Symbols), StatusItemController (status item, click/scroll, full dropdown)
├── Settings/               # AppSettings (UserDefaults: volume, launchAtLogin), LaunchAtLogin (SMAppService)
├── About/                  # AboutView (SwiftUI, short unofficial-app disclaimer + attribution + author credit), AboutWindowController
└── Resources/Assets.xcassets/   # template status-bar icons (SF Symbols), AppIcon (real PNGs, original design, no Claude logo)
ClaudeRadioTests/           # unit tests
design/                     # AppIcon-source-1024.png (master) + make_icon.swift (regenerates it)
```

## Testing notes

Live playback isn't meaningfully unit-testable (depends on network + YouTube's embed
player). What's covered: `Backoff` (the pure backoff-delay struct `ReconnectManager`
uses, in `ReconnectManagerTests.swift`), `PlaybackState` equality/description
(`PlaybackStateTests.swift`), `AppSettings` clamping/persistence
(`AppSettingsTests.swift`, uses an isolated `UserDefaults(suiteName:)` per test, not
`.standard`). Re-run the PRD §10 manual verification checklist by hand after any change
to `Playback/` or `NowPlaying/`.
