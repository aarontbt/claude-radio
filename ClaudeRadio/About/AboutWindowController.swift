import AppKit
import SwiftUI

final class AboutWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(rootView: AboutView())
        // Without this, the window keeps its initial fixed size and SwiftUI's actual
        // content gets clipped instead of the window growing to fit. This is what
        // caused the "truncated lines" bug.
        hosting.sizingOptions = [.minSize, .maxSize]

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "About Claude Radio"
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
