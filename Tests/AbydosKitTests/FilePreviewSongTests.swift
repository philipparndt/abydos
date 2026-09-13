import Foundation
import Testing
@testable import AbydosKit

/// A `.song` is text that makes sound: it opens with the sound beside it.
struct FilePreviewSongTests {
	private func url(_ name: String) -> URL {
		URL(fileURLWithPath: "/project/\(name)")
	}

	@Test func aSongIsASong() {
		#expect(FilePreview.kind(for: url("neon.song")) == .song)
		#expect(FilePreview.kind(for: url("NEON.SONG")) == .song)
		#expect(FilePreview.kind(for: url("neon.txt")) == nil)
	}

	/// The `.scad` case: source somebody types whose purpose is what it
	/// makes, so both halves open at once and every mode is offered.
	@Test func aSongOpensWithItsSoundBesideIt() {
		#expect(FilePreview.defaultMode(for: url("neon.song")) == .splitRight)
		#expect(FilePreview.hasReadableSource(url("neon.song")))
		#expect(FilePreview.availableModes(for: url("neon.song")) == PreviewMode.allCases)
	}

	/// Not a file the row's Space plays, and not one with a viewer instead of
	/// a text tab: the text is the point, and the sound is rendered from it.
	@Test func aSongIsTextFirst() {
		#expect(!FilePreview.isPlayable(url("neon.song")))
		#expect(!FilePreview.hasDedicatedViewer(url("neon.song")))
	}
}
