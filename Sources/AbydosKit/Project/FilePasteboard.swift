import AppKit
import Foundation

/// A list of files on a pasteboard, in the one shape that serves everything
/// which reads one.
///
/// ⌘C in the project tree has always written the paths as text, which is what a
/// terminal wants and the only thing a terminal can use. Making the same ⌘C
/// paste as a *file* in the Finder is where the obvious change is the wrong
/// one, so it was measured rather than reasoned about:
///
/// | what is written | types on an item | `string(forType: .string)` | files read back |
/// |---|---|---|---|
/// | `writeObjects([NSURL])` | `public.file-url` | **nil** | 2 |
/// | one item per file, `.fileURL` + the POSIX path as `.string` | both | `/…/Makefile\n/…/Package.swift` | 2 |
///
/// `NSURL` carries no string representation of its own, so the obvious swap
/// would have made files pasteable and silently destroyed the terminal paste —
/// which is the whole of what ⌘C in the tree does today. One `NSPasteboardItem`
/// per file carrying both types gives both, and AppKit joins the per-item
/// strings with newlines by itself, so the text form comes out character for
/// character what it was.
public enum FilePasteboard {
	/// Puts files on the board as files *and* as their paths, in the order
	/// given — which for the tree is tree order, since that is the order a list
	/// of files reads in.
	public static func write(_ urls: [URL], to board: NSPasteboard = .general) {
		board.clearContents()
		guard !urls.isEmpty else { return }
		board.writeObjects(urls.map { url in
			let item = NSPasteboardItem()
			// The file-url type's value is the absolute URL string; `.string` is
			// the POSIX path, because that is what gets pasted into a shell.
			item.setString(url.standardizedFileURL.absoluteString, forType: .fileURL)
			item.setString(url.standardizedFileURL.path, forType: .string)
			return item
		})
	}

	/// The files on the board, or nothing when it holds none.
	///
	/// `urlReadingFileURLsOnly` so that a web page's address on the board — which
	/// is also an `NSURL` — is not offered as something to paste into a folder.
	public static func files(on board: NSPasteboard = .general) -> [URL] {
		let objects = board.readObjects(
			forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
		)
		return (objects ?? []).compactMap { $0 as? URL }
	}

	/// Whether the board carries a picture — asked of its types, with nothing
	/// read. This is what menu validation calls, and a menu validates every
	/// time it opens; the bytes are read once, by `picture`, when ⌘V arrives.
	public static func hasPicture(on board: NSPasteboard = .general) -> Bool {
		board.availableType(from: [.png, .tiff]) != nil
	}

	/// The board's picture as PNG bytes, or nil when it holds none it can read.
	///
	/// The board's own PNG when it has one, byte for byte: a program that put a
	/// PNG there had already encoded it, and `NSImage(pasteboard:)` — the
	/// obvious call — would pick a representation by its own rules and encode
	/// again from a bitmap, so a file that was right could come out larger.
	/// Only a board with TIFF alone is decoded and encoded here.
	///
	/// Decoded before it is believed, in either case: a board is allowed to
	/// declare a type and carry rubbish under it, and a file named `.png` that
	/// no decoder opens is worse than a paste that said no.
	public static func picture(on board: NSPasteboard = .general) -> Data? {
		if let png = board.data(forType: .png), NSBitmapImageRep(data: png) != nil {
			return png
		}
		guard let tiff = board.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: tiff)
		else { return nil }
		return bitmap.representation(using: .png, properties: [:])
	}
}
