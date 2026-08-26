import Foundation
import Testing
@testable import AbydosKit

/// What the editor offers over a file it cannot show.
///
/// The case worth pinning down is the one that was wrong: a file that is not
/// there was offered Open Externally and Open in Hex Editor, neither of which
/// can do anything with a path that resolves to nothing. Two controls that
/// cannot work read as an offer to fix it.
struct FileNoticeTests {
	private let file = URL(fileURLWithPath: "/Users/me/project/main.py")

	@Test func aFileThatIsThereKeepsItsActionsAndItsReason() {
		let content = FileNotice.content(
			for: file, reason: "This file is not text.", exists: true
		)
		#expect(content.offersActions)
		#expect(content.detail == "This file is not text.")
		// The buttons are in that space, so nothing else may be.
		#expect(content.path == nil)
	}

	@Test func aFileThatIsGoneOffersNothingToOpen() {
		let content = FileNotice.content(
			for: file,
			reason: "The file “main.py” couldn’t be opened because there is no such file.",
			exists: false
		)
		#expect(!content.offersActions)
	}

	/// The name is already the heading, so the sentence says the new thing.
	@Test func aFileThatIsGoneSaysSoWithoutRepeatingItsName() {
		let content = FileNotice.content(
			for: file,
			reason: "The file “main.py” couldn’t be opened because there is no such file.",
			exists: false
		)
		#expect(content.detail == "This file no longer exists.")
		#expect(!content.detail.contains("main.py"))
	}

	/// Which of four projects' `main.py` this was is the actual question, and
	/// only the path answers it.
	@Test func aFileThatIsGoneSaysWhereItWas() {
		let content = FileNotice.content(for: file, reason: "gone", exists: false)
		#expect(content.path == "/Users/me/project/main.py")
	}

	/// Shown the way every other path in this app is.
	@Test func aPathUnderHomeIsWrittenWithATilde() {
		let underHome = URL(fileURLWithPath: NSHomeDirectory() + "/dev/thing/main.py")
		let content = FileNotice.content(for: underHome, reason: "gone", exists: false)
		#expect(content.path == "~/dev/thing/main.py")
	}

	/// The real entry point, which asks the file system rather than being told.
	@Test func theDiskIsAskedWhenNobodySays() {
		let missing = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-notice-\(UUID().uuidString)/main.py")
		#expect(!FileNotice.content(for: missing, reason: "gone").offersActions)

		let present = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-notice-\(UUID().uuidString).bin")
		try? Data([0x00, 0x01]).write(to: present)
		defer { try? FileManager.default.removeItem(at: present) }
		#expect(FileNotice.content(for: present, reason: "not text").offersActions)
	}

	// MARK: - How big it is, and whether the system can show it

	/// "This looks like a binary file" says nothing about whether it is a
	/// nine-byte marker or a gigabyte of video, and the second is what somebody
	/// wants to know before opening a hex editor on it.
	@Test func aFileThatIsThereSaysHowBigItIs() {
		let content = FileNotice.content(
			for: URL(fileURLWithPath: "/tmp/file-storage.mp4"),
			reason: "This looks like a binary file.",
			exists: true,
			byteCount: 25_400_000
		)
		#expect(content.size == "24 MiB")
		#expect(content.detail == "This looks like a binary file.", "the sentence is unchanged")
	}

	@Test func aSizeTooSmallToRoundKeepsItsDecimal() {
		let content = FileNotice.content(
			for: URL(fileURLWithPath: "/tmp/a.mp4"), reason: "x", exists: true, byteCount: 1_536
		)
		#expect(content.size == "1.5 KiB")
	}

	@Test func aFileWithNothingToMeasureSaysNothingAboutSize() {
		let content = FileNotice.content(
			for: URL(fileURLWithPath: "/tmp/a.mp4"), reason: "x", exists: true, byteCount: nil
		)
		#expect(content.size == nil)
	}

	/// A file that is gone has no size and nothing to preview — the same
	/// argument that takes its buttons away.
	@Test func aMissingFileOffersNothingAtAll() {
		let content = FileNotice.content(
			for: URL(fileURLWithPath: "/tmp/gone.mp4"), reason: "x", exists: false, byteCount: 900
		)
		#expect(content.size == nil)
		#expect(content.offersQuickLook == false)
		#expect(content.offersActions == false)
	}

	/// The kinds the system genuinely previews. A button that usually does
	/// nothing reads as an offer to do something.
	@Test func quickLookIsOfferedForWhatQuickLookCanShow() {
		for shown in ["mp4", "mov", "m4a", "png", "jpg", "heic", "pdf", "ttf", "key"] {
			#expect(FileNotice.offersQuickLook(forExtension: shown), "\(shown) should be previewable")
		}
	}

	@Test func quickLookIsNotOfferedForWhatItCannotShow() {
		// `zip` among them: Quick Look shows an archive as a large icon with its
		// name under it, which is what this notice already shows.
		for hidden in ["o", "a", "dylib", "bin", "zip", "class", "pyc", ""] {
			#expect(
				!FileNotice.offersQuickLook(forExtension: hidden),
				"\(hidden) would open a panel showing a generic icon"
			)
		}
	}

	@Test func aVideoOffersQuickLookAndAnObjectFileDoesNot() {
		let video = FileNotice.content(
			for: URL(fileURLWithPath: "/tmp/file-storage.mp4"), reason: "x", exists: true
		)
		let object = FileNotice.content(
			for: URL(fileURLWithPath: "/tmp/main.o"), reason: "x", exists: true
		)
		#expect(video.offersQuickLook)
		#expect(!object.offersQuickLook)
	}

	// MARK: - Which sentence a file gets

	/// A 400 MB `.mov` was told it was too large to open as text — a statement
	/// about text, about something that was never text.
	@Test func aBinaryFileIsCalledBinaryHoweverLargeItIs() {
		#expect(
			FileNotice.reason(isBinary: true, isTooLargeForText: true)
				== "This looks like a binary file."
		)
	}

	@Test func aLargeTextFileIsCalledTooLarge() {
		#expect(
			FileNotice.reason(isBinary: false, isTooLargeForText: true)
				== "This file is too large to open as text."
		)
	}

	@Test func aFileThatCanBeOpenedGetsNoNotice() {
		#expect(FileNotice.reason(isBinary: false, isTooLargeForText: false) == nil)
	}

	/// The number belongs to `size`, once, in this app's units — not in the
	/// sentence as well in somebody else's.
	@Test func theSentenceCarriesNoSize() {
		for sentence in [
			FileNotice.reason(isBinary: true, isTooLargeForText: true),
			FileNotice.reason(isBinary: false, isTooLargeForText: true),
		] {
			#expect(sentence?.contains("MB") == false)
			#expect(sentence?.contains("MiB") == false)
		}
	}
}
