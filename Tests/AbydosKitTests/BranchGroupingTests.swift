import Testing
import Foundation
@testable import AbydosKit

/// How a hundred branches are arranged so somebody can find one.
///
/// The report was "the branches are not sorted", about a list that *is* sorted
/// — by commit date. Which is a fair description of what it looks like:
///
///     backup/2026-08-24-0723-wip
///     master
///     chore/gradle
///     worktree-agent-a6a6d984161f1007d
///     feat/git
///     backup/feat/git-16-23-07
///
/// Every one of those is where its last commit put it, and from the outside
/// that is indistinguishable from no order at all.
struct BranchGroupingTests {
	/// The names from the report, in the order the old menu showed them.
	static let reported = [
		"backup/2026-08-24-0723-wip", "master", "chore/gradle",
		"chore/reduce-budles-build-aggregate", "chore/reduce-bundles-merge",
		"worktree-agent-a6a6d984161f1007d", "feat/git", "backup/feat/git-16-23-07",
		"feat/aarch64", "osgi_resolution", "feat/agent",
		"fix/remove-launching-of-server-ref", "fix/validator", "target-platform-2025-03",
		"fix/macos-open", "backup/target-platform-2025-03-07-43-02", "fix-name",
		"target-platform", "update-launcher", "macos/java", "chore/install-script",
	]

	// MARK: - Folders

	/// By the *first* slash. `backup/feat/git-16-23-07` is a backup, which is how
	/// whoever made it thinks of it — filing it under `feat`, beside the branch
	/// it is a backup *of*, is the one place it will be mistaken for it.
	@Test func theFolderIsEverythingBeforeTheFirstSlash() {
		#expect(BranchGrouping.folder(of: "feat/git") == "feat")
		#expect(BranchGrouping.folder(of: "backup/feat/git-16-23-07") == "backup")
		#expect(BranchGrouping.folder(of: "master") == nil)
		#expect(BranchGrouping.folder(of: "fix-name") == nil, "a dash is not a folder")
		#expect(BranchGrouping.folder(of: "/leading") == nil, "an empty folder is no folder")
	}

	@Test func branchesAreGatheredIntoTheirFolders() {
		let arranged = BranchGrouping.arrange(Self.reported)
		let folders = arranged.sections.compactMap(\.folder)

		#expect(folders == ["backup", "chore", "feat", "fix", "macos"], "\(folders)")
		let backups = arranged.sections.first { $0.folder == "backup" }?.branches
		#expect(backups?.count == 3)
		#expect(backups?.contains("backup/feat/git-16-23-07") == true)
	}

	/// The branches in no folder come first: they are the short names, usually
	/// the long-lived ones, and putting them below the folders buries them.
	@Test func branchesInNoFolderComeBeforeTheFolders() {
		let arranged = BranchGrouping.arrange(Self.reported)
		#expect(arranged.sections.first?.folder == nil)
		#expect(arranged.sections.first?.branches.contains("osgi_resolution") == true)
		#expect(arranged.sections.first?.branches.contains("target-platform") == true)
	}

	// MARK: - Sorting

	@Test func eachFolderIsSortedByName() {
		let arranged = BranchGrouping.arrange(Self.reported)
		let chore = arranged.sections.first { $0.folder == "chore" }?.branches
		#expect(chore == [
			"chore/gradle", "chore/install-script",
			"chore/reduce-budles-build-aggregate", "chore/reduce-bundles-merge",
		], "\(chore ?? [])")
	}

	/// Numbers read as numbers, which is what anybody numbering branches means.
	@Test func numbersInNamesSortAsNumbers() {
		let arranged = BranchGrouping.arrange(["fix/10", "fix/9", "fix/1"])
		#expect(arranged.sections.first { $0.folder == "fix" }?.branches
			== ["fix/1", "fix/9", "fix/10"])
	}

	// MARK: - What is pinned

	/// The two nobody should have to hunt for. The default especially: it is
	/// almost never the most recently committed to, so a list ordered by date
	/// sinks it to the bottom.
	@Test func theCurrentAndDefaultBranchesArePinnedInThatOrder() {
		let arranged = BranchGrouping.arrange(
			Self.reported, current: "feat/git", default: "master"
		)
		#expect(arranged.pinned == ["feat/git", "master"])
	}

	/// Pinned once, not twice, when they are the same branch.
	@Test func beingOnTheDefaultBranchPinsItOnce() {
		let arranged = BranchGrouping.arrange(
			Self.reported, current: "master", default: "master"
		)
		#expect(arranged.pinned == ["master"])
	}

	/// A pin for a branch that is not there would be a row that checks out
	/// nothing — which is what a `main` fallback does in a repository using
	/// `master`.
	@Test func aDefaultThatDoesNotExistIsNotPinned() {
		let arranged = BranchGrouping.arrange(["master", "feat/x"], default: "main")
		#expect(arranged.pinned.isEmpty)
		#expect(arranged.flattened.contains("master"))
	}

	/// And a pinned branch is not also listed below, or it would check out from
	/// two rows and look like two branches.
	@Test func aPinnedBranchIsNotRepeatedInItsFolder() {
		let arranged = BranchGrouping.arrange(
			Self.reported, current: "feat/git", default: "master"
		)
		let feat = arranged.sections.first { $0.folder == "feat" }?.branches ?? []
		#expect(!feat.contains("feat/git"))
		#expect(arranged.flattened.filter { $0 == "feat/git" }.count == 1)
	}

	// MARK: - Nothing lost

	/// Every branch appears exactly once, however it was arranged. A grouping
	/// that quietly dropped one would be a branch nobody can reach.
	@Test func everyBranchIsShownExactlyOnce() {
		let arranged = BranchGrouping.arrange(
			Self.reported, current: "feat/git", default: "master"
		)
		#expect(Set(arranged.flattened) == Set(Self.reported))
		#expect(arranged.flattened.count == Self.reported.count)
	}

	@Test func anEmptyListArrangesToNothing() {
		let arranged = BranchGrouping.arrange([], current: "main", default: "main")
		#expect(arranged.pinned.isEmpty)
		#expect(arranged.sections.isEmpty)
		#expect(arranged.flattened.isEmpty)
	}

	// MARK: - Which branch git calls the default

	@Test func theDefaultComesFromTheRemoteHeadWhenThereIsOne() async throws {
		let root = try await makeRepository(branch: "trunk")
		defer { try? FileManager.default.removeItem(at: root) }
		// What a fetched remote leaves behind.
		_ = await GitRepository.run(
			["update-ref", "refs/remotes/origin/trunk", "HEAD"], in: root
		)
		_ = await GitRepository.run(
			["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/trunk"], in: root
		)

		#expect(await BranchGrouping.defaultBranch(in: root) == "trunk")
	}

	/// Without a remote head, the usual names — and only if they exist.
	@Test func theUsualNamesAreTheFallback() async throws {
		let root = try await makeRepository(branch: "master")
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(await BranchGrouping.defaultBranch(in: root) == "master")
	}

	@Test func aRepositoryWithNeitherNameNorRemoteHasNoDefault() async throws {
		let root = try await makeRepository(branch: "develop")
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(await BranchGrouping.defaultBranch(in: root) == nil)
	}

	/// The refs tree's LOCAL section can be put in date order, and the spec
	/// pins this list to that one: two lists of the same branches in one
	/// window must not disagree. Pins stay pins, folders stay in name order,
	/// and the branches inside each group take the dates.
	@Test func aDateOrderPutsTheNewestFirstWithinEachGroup() {
		let arranged = BranchGrouping.arrange(
			["old", "new", "feat/a-old", "feat/b-new", "main"],
			current: "main",
			by: .newestFirst,
			created: [
				"old": Date(timeIntervalSince1970: 1),
				"new": Date(timeIntervalSince1970: 9),
				"feat/a-old": Date(timeIntervalSince1970: 2),
				"feat/b-new": Date(timeIntervalSince1970: 8),
			]
		)
		#expect(arranged.pinned == ["main"])
		#expect(arranged.sections.first?.branches == ["new", "old"])
		#expect(arranged.sections.last?.folder == "feat")
		#expect(arranged.sections.last?.branches == ["feat/b-new", "feat/a-old"])
	}

	// MARK: - Helpers

	private func makeRepository(branch: String) async throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-branch-group-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		_ = await GitRepository.run(["init", "-q", "-b", branch], in: root)
		_ = await GitRepository.run(["config", "user.email", "test@example.com"], in: root)
		_ = await GitRepository.run(["config", "user.name", "Test"], in: root)
		try "one\n".write(
			to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8
		)
		_ = await GitRepository.run(["add", "-A"], in: root)
		_ = await GitRepository.run(["commit", "-qm", "initial"], in: root)
		return root
	}
}
