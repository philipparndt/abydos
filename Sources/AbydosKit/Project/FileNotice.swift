import Foundation

/// What the editor should say about a file it cannot show.
///
/// Split out of the view so it can be tested: the app target has no test target
/// of its own, and the decision here — whether there is anything to *do* about
/// the file — is the part worth pinning down.
public enum FileNotice {
	/// The notice, as content rather than as controls.
	public struct Content: Equatable, Sendable {
		/// The sentence under the file's name.
		public let detail: String
		/// Where the file was, shown when there is nothing to offer instead.
		/// Nil when the buttons are there to fill that space.
		public let path: String?
		/// Whether to offer Open in Hex Editor and Open Externally.
		public let offersActions: Bool

		public init(detail: String, path: String?, offersActions: Bool) {
			self.detail = detail
			self.path = path
			self.offersActions = offersActions
		}
	}

	/// A notice for a file, asking the file system whether it is there.
	public static func content(for url: URL, reason: String) -> Content {
		content(for: url, reason: reason, exists: FileManager.default.fileExists(atPath: url.path))
	}

	/// The same, told whether the file exists, which is what the tests use.
	///
	/// **A file that is not there has nothing to open.** Both buttons were being
	/// offered over "there is no such file": Open Externally hands a missing path
	/// to `NSWorkspace`, which does nothing at all, and Open in Hex Editor opens
	/// a view of no bytes. Two controls that cannot work are worse than none,
	/// because they read as an offer to fix it.
	///
	/// What is useful instead is *where it was*. A tab outliving its file is
	/// nearly always a session restored after the file was moved, renamed or
	/// deleted somewhere else, and the question in somebody's head is which file
	/// this was — which the name alone does not answer when four projects each
	/// have a `main.py`. So the path takes the space the buttons were in.
	///
	/// The reason is replaced rather than kept for the same case. It arrives as
	/// an `NSError`'s description — "The file “main.py” couldn't be opened
	/// because there is no such file." — which names the file a second time
	/// under a heading that is already the file's name, and explains an opening
	/// nobody asked for. One short sentence says it instead, and the path says
	/// the rest.
	public static func content(for url: URL, reason: String, exists: Bool) -> Content {
		guard !exists else {
			return Content(detail: reason, path: nil, offersActions: true)
		}
		return Content(
			detail: "This file no longer exists.",
			// Written the way somebody would say it, and the way every other
			// path in this app is shown.
			path: (url.path as NSString).abbreviatingWithTildeInPath,
			offersActions: false
		)
	}
}
