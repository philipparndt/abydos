import Foundation
import Testing
@testable import AbydosKit

/// A permalink, and what it cannot promise.
///
/// The URL building is arithmetic and is tested as such. The rest needs a real
/// repository, because the two ways a permalink is a dead letter — a commit that
/// was never pushed, a file with uncommitted changes — are facts git holds and
/// nothing else does.
///
/// **The remote here is a bare repository in a temporary directory**, and
/// `git push` to it is a file copy between two folders on this machine. Nothing
/// leaves it; the same shape `GitHistoryTests` already uses to tell pushed from
/// unpushed.
struct CodeLinkURLTests {
	private let forge = GitForge.Repository(host: "github.com", owner: "philipparndt", name: "abydos")

	@Test func aFileAtACommitWithItsLine() {
		let place = CodePlace(path: "Sources/AbydosApp/Editor/CodeView.swift", line: 2324)
		let url = forge.url(
			forFile: "Sources/AbydosApp/Editor/CodeView.swift",
			atCommit: "1c5f3687aa", place: place
		)
		#expect(url?.absoluteString == "https://github.com/philipparndt/abydos/blob/1c5f3687aa/"
			+ "Sources/AbydosApp/Editor/CodeView.swift#L2324")
	}

	@Test func aRangeIsTheForgesOwnSpelling() {
		let place = CodePlace(path: "a/b.swift", line: 12, endLine: 18)
		#expect(forge.url(forFile: "a/b.swift", atCommit: "abc123", place: place)?
			.absoluteString.hasSuffix("#L12-L18") == true)
	}

	/// No place: the file at that commit, which is what a link to a *file*
	/// rather than to a line is.
	@Test func noLineMeansNoFragment() {
		#expect(forge.url(forFile: "a/b.swift", atCommit: "abc123", place: nil)?
			.absoluteString == "https://github.com/philipparndt/abydos/blob/abc123/a/b.swift")
	}

	/// A path with a space in it is a URL with an escape in it — per component,
	/// so the slashes stay slashes.
	@Test func aPathIsEscapedComponentByComponent() {
		let url = forge.url(forFile: "My Notes/a b.swift", atCommit: "abc123", place: nil)
		#expect(url?.absoluteString == "https://github.com/philipparndt/abydos/blob/abc123/"
			+ "My%20Notes/a%20b.swift")
	}

	@Test func nothingToLinkToIsNoURL() {
		#expect(forge.url(forFile: "", atCommit: "abc123", place: nil) == nil)
		#expect(forge.url(forFile: "a.swift", atCommit: "", place: nil) == nil)
	}

	// MARK: - What it cannot promise

	/// **The commonest mistake somebody can make with this**, and the one the
	/// recipient discovers rather than the sender.
	@Test func anUnpushedCommitIsNamedAsOne() {
		let state = CodeLink.State(commit: "1c5f3687aabbccdd", isOnARemote: false, isFileDirty: false)
		let said = CodeLink.caveat(for: state)
		#expect(said?.contains("1c5f368") == true)
		#expect(said?.contains("not on the remote") == true)
		#expect(said?.contains("pushed") == true)
	}

	/// Said as what it does to the link, not as a fact about the file.
	@Test func aDirtyFileIsSaidAsWhichLineTheLinkOpens() {
		let state = CodeLink.State(commit: "1c5f3687aabbccdd", isOnARemote: true, isFileDirty: true)
		let said = CodeLink.caveat(for: state)
		#expect(said?.contains("not the line on screen") == true)
		// The words that would leave the reader to work it out for themselves.
		#expect(said?.contains("Uncommitted changes.") != true)
	}

	@Test func bothAtOnceSaysBoth() {
		let state = CodeLink.State(commit: "abcdef1234", isOnARemote: false, isFileDirty: true)
		let said = CodeLink.caveat(for: state)
		#expect(said?.contains("not on the remote") == true)
		#expect(said?.contains("not the line on screen") == true)
	}

	/// The ordinary case says nothing. A sentence that appears every time is a
	/// sentence nobody reads.
	@Test func aCleanPushedCommitSaysNothing() {
		#expect(CodeLink.caveat(for: CodeLink.State(
			commit: "abcdef1234", isOnARemote: true, isFileDirty: false
		)) == nil)
	}
}

/// The same three questions, asked of a real repository.
@Suite(.serialized) struct CodeLinkStateTests {
	private func makeRepository() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("code-link-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		_ = GitRepository.runSync(["init", "-q", "-b", "main", "."], in: root)
		_ = GitRepository.runSync(["config", "user.email", "probe@example.com"], in: root)
		_ = GitRepository.runSync(["config", "user.name", "Probe"], in: root)
		try "one\ntwo\nthree\n".write(
			to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8
		)
		_ = GitRepository.runSync(["add", "-A"], in: root)
		_ = GitRepository.runSync(["commit", "-qm", "first"], in: root)
		return root
	}

	@Test func aCommitWithNoRemoteIsNotOnOne() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let state = try #require(await CodeLink.state(of: "a.txt", in: root))
		#expect(state.commit.count == 40)
		#expect(!state.isOnARemote)
		#expect(!state.isFileDirty)
	}

	/// Pushed to a bare repository beside it — a file copy on this machine, and
	/// the only way to make "is on a remote" true without a network.
	@Test func aPushedCommitIsOnARemote() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		let remote = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("code-link-remote-\(UUID().uuidString).git")
		defer { try? FileManager.default.removeItem(at: remote) }

		_ = GitRepository.runSync(["init", "-q", "--bare", remote.path], in: root)
		_ = GitRepository.runSync(["remote", "add", "origin", remote.path], in: root)
		_ = GitRepository.runSync(["push", "-q", "origin", "main"], in: root)
		_ = GitRepository.runSync(["fetch", "-q", "origin"], in: root)

		let state = try #require(await CodeLink.state(of: "a.txt", in: root))
		#expect(state.isOnARemote)
		#expect(CodeLink.caveat(for: state) == nil)
	}

	@Test func aFileEditedSinceTheCommitIsDirty() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		try "one\nedited\ntwo\nthree\n".write(
			to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8
		)
		let state = try #require(await CodeLink.state(of: "a.txt", in: root))
		#expect(state.isFileDirty)
		#expect(CodeLink.caveat(for: state)?.contains("not the line on screen") == true)
	}

	/// One file's changes are not another's. A permalink to a file nobody has
	/// touched promises nothing it cannot keep, however dirty the tree is.
	@Test func anotherFilesChangesAreNotThisFilesProblem() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		try "new\n".write(
			to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8
		)
		let state = try #require(await CodeLink.state(of: "a.txt", in: root))
		#expect(!state.isFileDirty)
	}

	/// A checkout with no commits has nothing to link to, and says so by
	/// answering nothing rather than by inventing a commit.
	@Test func aRepositoryWithNoCommitsHasNoLink() async throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("code-link-empty-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		_ = GitRepository.runSync(["init", "-q", "-b", "main", "."], in: root)

		#expect(await CodeLink.state(of: "a.txt", in: root) == nil)
	}

	/// No remote, so no permalink: the entry is not offered rather than offering
	/// a URL this app had to invent a host for.
	@Test func noRemoteMeansNoPermalink() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(await CodeLink.permalink(
			for: CodePlace(path: "a.txt", line: 2),
			repositoryPath: "a.txt", repository: root
		) == nil)
	}

	/// A remote git understands and this app does not — a local path is a remote
	/// with no host at all.
	@Test func aRemoteWithNoHostMeansNoPermalink() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		let remote = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("code-link-remote-\(UUID().uuidString).git")
		defer { try? FileManager.default.removeItem(at: remote) }
		_ = GitRepository.runSync(["init", "-q", "--bare", remote.path], in: root)
		_ = GitRepository.runSync(["remote", "add", "origin", remote.path], in: root)

		#expect(await CodeLink.permalink(
			for: CodePlace(path: "a.txt", line: 2),
			repositoryPath: "a.txt", repository: root
		) == nil)
	}

	/// And the whole of it, with a remote that does have a host.
	@Test func aPermalinkNamesTheHeadCommitAndCarriesWhatMustBeSaid() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		_ = GitRepository.runSync(
			["remote", "add", "origin", "git@github.com:philipparndt/probe.git"], in: root
		)

		let link = try #require(await CodeLink.permalink(
			for: CodePlace(path: "a.txt", line: 2),
			repositoryPath: "a.txt", repository: root
		))
		#expect(link.url.absoluteString.hasPrefix("https://github.com/philipparndt/probe/blob/"))
		#expect(link.url.absoluteString.hasSuffix("/a.txt#L2"))
		// The commit is not on that remote — nothing was pushed to GitHub and
		// nothing will be — so the link says so.
		#expect(link.caveat?.contains("not on the remote") == true)
		#expect(link.url.absoluteString.contains(link.commit))
	}
}

/// Following a link back, which is the half that keeps a bookmark worth
/// keeping.
struct FollowedLinkTests {
	@Test func readsItsOwnPermalink() {
		let followed = CodeLink.follow(
			"https://github.com/philipparndt/abydos/blob/1c5f3687/Sources/App/Main.swift#L42"
		)
		#expect(followed?.path == "Sources/App/Main.swift")
		#expect(followed?.commit == "1c5f3687")
		#expect(followed?.line == 42)
		#expect(followed?.endLine == nil)
	}

	@Test func readsARange() {
		let followed = CodeLink.follow(
			"https://github.com/o/n/blob/abc/a/b.swift#L12-L18"
		)
		#expect(followed?.line == 12)
		#expect(followed?.endLine == 18)
	}

	/// A link to a file with no line lands at the top rather than being refused:
	/// somebody sending the file is sending something meaningful.
	@Test func aFileWithNoLineLandsAtTheTop() {
		#expect(CodeLink.follow("https://github.com/o/n/blob/abc/a/b.swift")?.line == 1)
	}

	@Test func aPathWithAnEscapeInItIsPutBack() {
		#expect(CodeLink.follow("https://github.com/o/n/blob/abc/My%20Notes/a%20b.swift#L3")?
			.path == "My Notes/a b.swift")
	}

	/// **Only the shape this program writes.** A `tree` URL is a directory and a
	/// `blame` URL is a different page of the same file; following one as though
	/// it were a permalink is guessing.
	@Test func somethingElseIsNotAPermalink() {
		#expect(CodeLink.follow("https://github.com/o/n/tree/main/Sources") == nil)
		#expect(CodeLink.follow("https://github.com/o/n/blame/abc/a.swift#L3") == nil)
		#expect(CodeLink.follow("https://github.com/o/n") == nil)
		#expect(CodeLink.follow("Sources/App/Main.swift:42") == nil)
		#expect(CodeLink.follow("") == nil)
	}

	// MARK: - Where the line ended up

	@Test func aSentenceOnlyWhenThereIsSomethingToSay() {
		#expect(CodeLink.Landing.unchanged(line: 42).said(commit: "1c5f3687aa") == nil)
		#expect(CodeLink.Landing.unknown(line: 42).said(commit: "1c5f3687aa") == nil)
		let moved = CodeLink.Landing.moved(from: 42, to: 50).said(commit: "1c5f3687aa")
		#expect(moved == "Line 42 at 1c5f368 is line 50 now.")
		#expect(CodeLink.Landing.gone(line: 42).said(commit: "abc")?
			.contains("no longer in the file") == true)
	}

	@Test func theCaretGoesWhereTheTextWent() {
		#expect(CodeLink.Landing.moved(from: 42, to: 50).line == 50)
		#expect(CodeLink.Landing.gone(line: 42).line == 42)
	}
}

/// Landing, against a real repository whose file has moved under the link.
@Suite(.serialized) struct LandingTests {
	private func makeRepository(_ contents: String) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("landing-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		_ = GitRepository.runSync(["init", "-q", "-b", "main", "."], in: root)
		_ = GitRepository.runSync(["config", "user.email", "probe@example.com"], in: root)
		_ = GitRepository.runSync(["config", "user.name", "Probe"], in: root)
		try contents.write(to: root.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
		_ = GitRepository.runSync(["add", "-A"], in: root)
		_ = GitRepository.runSync(["commit", "-qm", "first"], in: root)
		return root
	}

	private func head(of root: URL) -> String {
		GitRepository.runSync(["rev-parse", "HEAD"], in: root)
			.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// **The failure that makes people stop keeping bookmarks**: eight lines
	/// added above, and line 3 is now somewhere else.
	@Test func aLineThatMovedIsFoundWhereItWent() async throws {
		let root = try makeRepository("one\ntwo\nthe line that matters\nfour\n")
		defer { try? FileManager.default.removeItem(at: root) }
		let commit = head(of: root)

		try "added\nadded\nadded\none\ntwo\nthe line that matters\nfour\n".write(
			to: root.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8
		)

		let followed = CodeLink.Followed(path: "a.swift", commit: commit, line: 3)
		#expect(await CodeLink.land(followed, in: root) == .moved(from: 3, to: 6))
	}

	@Test func aLineThatDidNotMoveSaysNothing() async throws {
		let root = try makeRepository("one\ntwo\nthree\n")
		defer { try? FileManager.default.removeItem(at: root) }
		let commit = head(of: root)

		let followed = CodeLink.Followed(path: "a.swift", commit: commit, line: 2)
		let landing = await CodeLink.land(followed, in: root)
		#expect(landing == .unchanged(line: 2))
		#expect(landing.said(commit: commit) == nil)
	}

	@Test func aLineWhoseTextHasGoneLandsWhereTheLinkSaid() async throws {
		let root = try makeRepository("one\ndeleted line\nthree\n")
		defer { try? FileManager.default.removeItem(at: root) }
		let commit = head(of: root)

		try "one\nthree\n".write(
			to: root.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8
		)
		#expect(await CodeLink.land(
			CodeLink.Followed(path: "a.swift", commit: commit, line: 2), in: root
		) == .gone(line: 2))
	}

	/// A commit this checkout has never seen: the number is taken at its word
	/// rather than a line being invented for it.
	@Test func aCommitThisCheckoutDoesNotHaveIsNotGuessedAt() async throws {
		let root = try makeRepository("one\ntwo\n")
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(await CodeLink.land(
			CodeLink.Followed(path: "a.swift", commit: "0000000000000000000000000000000000000000", line: 2),
			in: root
		) == .unknown(line: 2))
	}

	/// A file that was not in that commit — added since — is the same answer for
	/// the same reason.
	@Test func aFileThatWasNotInThatCommitIsNotGuessedAt() async throws {
		let root = try makeRepository("one\n")
		defer { try? FileManager.default.removeItem(at: root) }
		let commit = head(of: root)

		try "new\n".write(to: root.appendingPathComponent("b.swift"), atomically: true, encoding: .utf8)
		#expect(await CodeLink.land(
			CodeLink.Followed(path: "b.swift", commit: commit, line: 1), in: root
		) == .unknown(line: 1))
	}
}
