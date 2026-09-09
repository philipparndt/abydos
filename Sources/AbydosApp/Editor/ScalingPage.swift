import AppKit
import CryptoKit
import QuickLookUI
import GoSTL
import AbydosKit
import SwiftUI

/// A page of the app's own that re-reads the zoom and the palette when they
/// change, the way every pane of the window does.
///
/// A page lives in a tab rather than in the window's own furniture, so nothing
/// in `MainWindowController.applySettings` reaches one on its way round. This
/// is how a page asks to be included: the editor calls it for every tab holding
/// one, and a page that does not conform is left alone.
@MainActor
protocol ScalingPage: NSView {
	func applySettings()
}

/// Detects binary content so the editor does not try to render it.
enum FileInspector {
	static func isProbablyBinary(url: URL) -> Bool {
		guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
		defer { try? handle.close() }
		guard let sample = try? handle.read(upToCount: 8_000), !sample.isEmpty else { return false }

		// A NUL byte in the first few KB is the standard heuristic — it is what
		// git itself uses to decide a file is binary.
		return sample.contains(0)
	}
}
