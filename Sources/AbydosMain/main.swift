import AppKit
import AbydosApp
import AbydosKit

// First, before anything can read a preference.
//
// A run given a launch-option verb is being driven from outside rather than
// used, and everything it would otherwise write — the preferences, the session
// beside the project, the list of recent projects — belongs to whoever is at
// the keyboard rather than to the run. `DrivenRun` is where that is decided and
// why; item 0522 is what deciding it nowhere cost. `Settings.shared` is a
// `static let` and so is built on first use, which makes this line's position
// the whole of the ordering.
DrivenRun.begin()

// An SPM executable has no Info.plist, so the things a bundled app gets for free
// are set up by hand here. `Scripts/bundle.sh` wraps this binary into a real
// .app, which is what gives it a Dock icon and lets the window vend a proper
// unified titlebar.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
