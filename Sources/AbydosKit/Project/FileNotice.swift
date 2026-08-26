import Foundation
import UniformTypeIdentifiers

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
		/// How big it is, in the units somebody reads, or nil when there is
		/// nothing to measure.
		///
		/// The question a binary file raises first. "This looks like a binary
		/// file" says nothing about whether it is a nine-byte marker or a
		/// gigabyte of video, and the second is the one somebody wants to know
		/// before they open it in a hex editor.
		public let size: String?
		/// Whether the system can be asked to show it.
		public let offersQuickLook: Bool

		public init(
			detail: String,
			path: String?,
			offersActions: Bool,
			size: String? = nil,
			offersQuickLook: Bool = false
		) {
			self.detail = detail
			self.path = path
			self.offersActions = offersActions
			self.size = size
			self.offersQuickLook = offersQuickLook
		}
	}

	/// A notice for a file, asking the file system whether it is there.
	public static func content(for url: URL, reason: String) -> Content {
		content(
			for: url,
			reason: reason,
			exists: FileManager.default.fileExists(atPath: url.path),
			byteCount: ByteSize.ofFile(at: url)
		)
	}

	/// Why a file cannot be opened as text, or nil when it can.
	///
	/// **Binary wins over too-large, and that ordering is the point of putting
	/// this here.** A 400 MB `.mov` was told "This file is 405,7 MB — too large
	/// to open as text", which is a statement about text made about something
	/// that was never text: the size is beside the point, and the sentence
	/// invites somebody to wonder what a smaller one would have done. It is a
	/// binary file. That it is also large is true of most binary files.
	///
	/// The size is not in the sentence either. `Content.size` carries it, in the
	/// units the rest of this app uses — the two together said it twice, once as
	/// `405,7 MB` and once as `387 MiB`, which is the same number twice in two
	/// conventions and reads as a mistake because it is one.
	public static func reason(isBinary: Bool, isTooLargeForText: Bool) -> String? {
		if isBinary { return "This looks like a binary file." }
		if isTooLargeForText { return "This file is too large to open as text." }
		return nil
	}

	/// Whether Quick Look is worth offering for a name.
	///
	/// **Not "always".** Quick Look opens for anything and shows a generic icon
	/// for most of it, and a button that usually does nothing reads as an offer
	/// to do something — which is the argument this file already makes about the
	/// two buttons over a missing file.
	///
	/// So: the kinds the system genuinely previews. A video, which is what
	/// prompted this — the notice for a `.mp4` offered a hex editor and an
	/// external app, and the obvious thing to do with a video is watch it.
	public static func offersQuickLook(forExtension fileExtension: String) -> Bool {
		guard let type = UTType(filenameExtension: fileExtension) else { return false }
		// **No `.archive`.** Quick Look draws a zip as a large icon with its name
		// under it, which is what the notice already shows — and `.bin` is a
		// MacBinary archive by UTI, so including archives offered a preview for
		// every nondescript blob on disk. These are the kinds it actually
		// renders.
		let previewable: [UTType] = [
			.image, .audiovisualContent, .pdf, .font, .presentation, .spreadsheet,
		]
		return previewable.contains { type.conforms(to: $0) }
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
	public static func content(
		for url: URL, reason: String, exists: Bool, byteCount: Int64? = nil
	) -> Content {
		guard !exists else {
			return Content(
				detail: reason,
				path: nil,
				offersActions: true,
				size: byteCount.map(ByteSize.said),
				offersQuickLook: offersQuickLook(forExtension: url.pathExtension)
			)
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
