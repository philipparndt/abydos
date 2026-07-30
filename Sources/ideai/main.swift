import AppKit

// An SPM executable has no Info.plist, so the things a bundled app gets for free
// are set up by hand here. `Scripts/bundle.sh` wraps this binary into a real
// .app, which is what gives it a Dock icon and lets the window vend a proper
// unified titlebar.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
