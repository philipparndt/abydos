import Foundation
import Testing
@testable import AbydosKit

/// The three answers that are not errors, and what each tells somebody to do.
///
/// **The one thing this must never look like is an empty list.** "No pull
/// requests are open" is a sentence about the repository; "the CLI is not
/// logged in" is a sentence about the machine. A reader cannot tell them apart
/// from a blank pane, and only one of them is something they can act on.
struct GitHubCLITests {
	@Test func eachAbsenceSaysWhatIsWrongAndWhatToDo() {
		let missing = ForgeAbsence.cliNotInstalled
		#expect(missing.summary.contains("not installed"))
		#expect(missing.remedy.contains("brew install gh"))

		let out = ForgeAbsence.cliNotLoggedIn(host: "ghe.example.com")
		#expect(out.summary.contains("ghe.example.com"))
		// The command that fixes it, with the host in it — an Enterprise login
		// is not `gh auth login` and being told the wrong command is worse than
		// being told none.
		#expect(out.remedy.contains("gh auth login --hostname ghe.example.com"))

		let elsewhere = ForgeAbsence.noGitHubRemote
		#expect(elsewhere.summary.contains("no GitHub remote"))
		#expect(!elsewhere.remedy.isEmpty)
	}

	/// Three different sentences, because each sends somebody to a different
	/// place. A single "something went wrong" would send them to all three.
	@Test func theThreeDoNotSayTheSameThing() {
		let said = [
			ForgeAbsence.cliNotInstalled,
			.cliNotLoggedIn(host: "github.com"),
			.noGitHubRemote,
		].map { $0.summary + $0.remedy }
		#expect(Set(said).count == 3)
	}

	/// A reply that could not be made carries the sentence to put on screen, and
	/// a reply that was made carries none — so a pane cannot show both a list
	/// and a complaint.
	@Test func aReplyEitherHasAValueOrHasSomethingToSay() {
		let answered = ForgeReply<[Int]>.answered([1, 2])
		#expect(answered.value == [1, 2])
		#expect(answered.trouble == nil)

		let unavailable = ForgeReply<[Int]>.unavailable(.cliNotInstalled)
		#expect(unavailable.value == nil)
		#expect(unavailable.trouble?.contains("brew install gh") == true)

		let failed = ForgeReply<[Int]>.failed("could not resolve to a Repository")
		#expect(failed.value == nil)
		#expect(failed.trouble == "could not resolve to a Repository")
	}

	/// A repository that is nobody's forge is the third answer, and it is
	/// decided by `GitForge` rather than by anything here — nothing in this
	/// layer parses a remote.
	@Test func aPlainPathIsNotAForge() {
		#expect(GitForge.repository(fromRemote: "/Users/somebody/dev/thing") == nil)
		#expect(GitForge.repository(fromRemote: "") == nil)
	}
}

/// Splitting one diff of many files into one diff per file, and what a tick is
/// recorded against.
struct FileDiffsTests {
	private let diff = """
	diff --git a/one.txt b/one.txt
	index 111..222 100644
	--- a/one.txt
	+++ b/one.txt
	@@ -1 +1,2 @@
	 first
	+second
	diff --git a/dir/two.txt b/dir/two.txt
	new file mode 100644
	index 000..333
	--- /dev/null
	+++ b/dir/two.txt
	@@ -0,0 +1 @@
	+brand new
	"""

	@Test func oneDiffBecomesOnePerFile() {
		let pieces = FileDiffs.split(diff)
		#expect(Set(pieces.keys) == ["one.txt", "dir/two.txt"])
		#expect(pieces["one.txt"]?.contains("+second") == true)
		#expect(pieces["one.txt"]?.contains("brand new") == false)
		#expect(pieces["dir/two.txt"]?.hasPrefix("diff --git ") == true)
	}

	/// **A path with a space in it is why the header is split from the middle.**
	/// Taking the last field of the line gives half a filename, and the files
	/// that have spaces in them are exactly the ones whose names are hardest to
	/// notice being wrong.
	@Test func aPathWithASpaceInItSurvives() {
		#expect(FileDiffs.path(fromHeader: "diff --git a/my notes.md b/my notes.md") == "my notes.md")
	}

	/// A rename has two different paths, and the right-hand one is the file's
	/// name now — which is what every other list here calls it by.
	@Test func aRenameIsKnownByWhereItLanded() {
		#expect(
			FileDiffs.path(fromHeader: "diff --git a/old/name.txt b/new/name.txt")
				== "new/name.txt"
		)
	}

	@Test func nothingBeforeTheFirstHeaderIsKept() {
		let noise = "warning: something\n" + diff
		#expect(Set(FileDiffs.split(noise).keys) == ["one.txt", "dir/two.txt"])
	}

	/// **The token is the diff, and not the head commit.** A rebase moves the
	/// head without changing a single file's diff — and clearing every tick on
	/// every push is how a checklist comes to be ignored.
	@Test func theTokenFollowsTheDiffAndNotTheCommit() {
		let before = FileDiffs.split(diff)
		let rebased = FileDiffs.split(diff.replacingOccurrences(of: "index 111..222", with: "index 999..aaa"))

		// The index line changed, so that file's token moves with it — which is
		// the honest answer: what was read is what git printed.
		#expect(
			FileDiffs.token(forDiff: before["one.txt"] ?? "")
				!= FileDiffs.token(forDiff: rebased["one.txt"] ?? "")
		)
		// The file the rebase did not touch keeps its token, which is the case
		// a reviewer meets most often and would resent losing.
		#expect(
			FileDiffs.token(forDiff: before["dir/two.txt"] ?? "")
				== FileDiffs.token(forDiff: rebased["dir/two.txt"] ?? "")
		)
	}

	@Test func theSameTextIsTheSameToken() {
		#expect(FileDiffs.token(forDiff: "a") == FileDiffs.token(forDiff: "a"))
		#expect(FileDiffs.token(forDiff: "a") != FileDiffs.token(forDiff: "b"))
		#expect(!FileDiffs.token(forDiff: "").isEmpty)
	}
}
