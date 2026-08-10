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
}
