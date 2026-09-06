import AppKit
import AbydosKit

/// *New Terminal Here*, the service the Finder offers on a folder.
///
/// **Because the Finder's own *Open in Terminal* is Terminal.app's**, wired to
/// it by the system, and macOS offers that to nobody. What every other terminal
/// does instead — iTerm among them — is advertise a service, which the Finder
/// shows in its Services menu and which System Settings can give a keyboard
/// shortcut. That is the whole of what is on offer, and the settings page says
/// so rather than leaving somebody hunting for a switch that does not exist.
///
/// A folder opens the project it belongs to with the terminal at that folder; a
/// file opens at the folder holding it, because "here" is where the thing is.
@MainActor
final class TerminalService: NSObject {
	/// Where the window comes from — the app delegate's own opening, so a
	/// project already open is raised rather than opened twice.
	var open: ((URL) -> MainWindowController?)?

	/// The service driven directly, since the handler is reachable without the
	/// Finder — what a run can check is what it does with a path, which is the
	/// half that is this app's.
	func openTerminalForTesting(_ path: String) -> String {
		let pasteboard = NSPasteboard(name: .init("abydos.terminal-service.test"))
		pasteboard.clearContents()
		pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
		var error: NSString? = nil
		withUnsafeMutablePointer(to: &error) { pointer in
			openTerminalHere(
				pasteboard,
				userData: nil,
				error: AutoreleasingUnsafeMutablePointer(pointer)
			)
		}
		if let error { return "refused: \(error)" }
		return "opened"
	}

	@objc func openTerminalHere(
		_ pasteboard: NSPasteboard,
		userData: String?,
		error: AutoreleasingUnsafeMutablePointer<NSString>
	) {
		guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
		      let first = urls.first
		else {
			error.pointee = "Nothing to open a terminal in." as NSString
			return
		}

		var directory = first
		var isDirectory: ObjCBool = false
		if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDirectory),
		   !isDirectory.boolValue {
			directory = first.deletingLastPathComponent()
		}

		NSApp.activate(ignoringOtherApps: true)
		// The project the folder belongs to, opened the way everything else
		// opens one — the same door `application(_:open:)` uses, so a window
		// already showing it is raised rather than a second one appearing.
		guard let controller = open?(Project.root(containing: directory)) else {
			error.pointee = "Could not open a window." as NSString
			return
		}
		controller.showWindow(nil)
		controller.openTerminal(in: directory)
	}
}
