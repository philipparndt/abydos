import Foundation
import Testing
@testable import AbydosKit

/// What a URL that names no file does to the two places one used to reach.
///
/// Both of these were crash reports before they were tests. An open-URL Apple
/// Event carries whatever string the sender wrote — no scheme required — and
/// nothing between that event and either of these had asked whether the result
/// was a file at all. One wedged a window for a hundred and seventy-six
/// seconds; the other aborted the app outright.
struct NonFileURLTests {
	/// Every shape that has to be survived, and what makes each one awkward.
	///
	/// `notes.txt` and `a/b/c` are the relative ones the climb never escaped.
	/// The trailing slashes are the ones `hasDirectoryPath` calls directories.
	/// `https:` has a `path` that looks absolute — `/a` — while being no file.
	private static let notFiles: [String] = [
		"notes.txt",
		"a/b/c",
		"notes/",
		"..",
		"../../..",
		"https://example.com/a",
		"https://example.com/a/",
		"abydos://open/x",
		"mailto:someone@example.com",
	]

	@Test(arguments: NonFileURLTests.notFiles)
	func aURLThatNamesNoFileFindsNoProject(_ text: String) throws {
		let url = try #require(URL(string: text))
		#expect(!url.isFileURL, "the fixture is only interesting while this holds")

		// The claim is that it *answers*. Before the guard this did not return
		// at all for the relative ones: `deletingLastPathComponent` walks
		// `notes.txt` → `.` → `..` → `../..` without ever reaching a fixed
		// point, and the loop's only exit is a parent that compares equal to
		// its child. A test that hangs is the failure being reported.
		#expect(ProjectRoot.find(from: url) == nil)
	}

	@Test(arguments: NonFileURLTests.notFiles)
	func gitRefusesToRunSomewhereThatIsNotAFile(_ text: String) throws {
		let url = try #require(URL(string: text))

		// `-[NSTask setCurrentDirectoryURL:]` raises an Objective-C exception
		// for this, which Swift cannot catch, so the process died on the
		// assignment. Reaching the expectation below at all is most of the
		// claim; the exit code is the rest of it.
		let result = GitRepository.runSync(["status", "--porcelain"], in: url)
		#expect(result.exitCode == -1)
		#expect(result.stderr.contains("not a file URL"))
	}

	/// The guard is about the *kind* of URL, not about whether it resolves.
	///
	/// A path that does not exist is a failure with an answer in it: `NSTask`
	/// takes it and git says what was wrong. Refusing it here would turn every
	/// report of a deleted working directory into the same blank -1.
	@Test func aDirectoryThatIsNotThereStillReachesGit() {
		let missing = URL(fileURLWithPath: "/no/such/directory/\(UUID().uuidString)")
		let result = GitRepository.runSync(["status", "--porcelain"], in: missing)

		#expect(!result.stderr.contains("not a file URL"))
	}

	/// A relative *file* URL is absolute by the time it is one, so the guard
	/// does not cost the ordinary case anything.
	@Test func aFileURLBuiltFromARelativePathIsStillAFileURL() throws {
		let url = URL(fileURLWithPath: "notes.txt")

		#expect(url.isFileURL)
		#expect(url.path.hasPrefix("/"))
		// It resolves against the working directory, so it names a file that
		// is merely absent rather than a URL that names none.
		#expect(!GitRepository.runSync(["status"], in: url).stderr.contains("not a file URL"))
	}
}
