import Testing
import Foundation
@testable import AbydosKit

/// Where the list of a project's files comes from, and how it stays true.
///
/// **Serialised, and modest about concurrency.** Each build shells out to git,
/// and a suite that asked for thirty-two at once starved thirty unrelated tests'
/// `git init` earlier this week. Six is more than the behaviour needs.
@Suite(.serialized)
struct FileIndexTests {
	private func makeProject(files: [String], asRepository: Bool) async throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-file-index-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		for path in files {
			let url = root.appendingPathComponent(path)
			try FileManager.default.createDirectory(
				at: url.deletingLastPathComponent(), withIntermediateDirectories: true
			)
			try "x\n".write(to: url, atomically: true, encoding: .utf8)
		}
		guard asRepository else { return root }
		_ = await GitRepository.run(["init", "-q"], in: root)
		_ = await GitRepository.run(["config", "user.email", "test@example.com"], in: root)
		_ = await GitRepository.run(["config", "user.name", "Test"], in: root)
		_ = await GitRepository.run(["add", "-A"], in: root)
		_ = await GitRepository.run(["commit", "-qm", "initial"], in: root)
		return root
	}

	// MARK: - Where the list comes from

	@Test func aWorkTreeIsListedByGit() async throws {
		let root = try await makeProject(
			files: ["a.swift", "deep/b.swift"], asRepository: true
		)
		defer { try? FileManager.default.removeItem(at: root) }

		let tracked = await ProjectFiles.tracked(in: root)
		#expect(tracked != nil, "a work tree answered as if it were not one")
		#expect(Set(tracked ?? []) == ["a.swift", "deep/b.swift"])
	}

	/// A directory that is not a work tree has nothing to ask, so it is walked.
	@Test func aDirectoryWithNoRepositoryIsWalkedInstead() async throws {
		let root = try await makeProject(
			files: ["a.swift", "deep/b.swift"], asRepository: false
		)
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(await ProjectFiles.tracked(in: root) == nil)
		let listed = await ProjectFiles.list(in: root)
		#expect(Set(listed) == ["a.swift", "deep/b.swift"])
	}

	/// A work tree with nothing committed is a real answer of no files, not the
	/// same as "there is no repository here".
	@Test func anEmptyWorkTreeAnswersEmptyRatherThanAbsent() async throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-empty-repo-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		_ = await GitRepository.run(["init", "-q"], in: root)

		#expect(await ProjectFiles.tracked(in: root)?.isEmpty == true)
	}

	/// The walk's exclusions are the shared ones, so a directory added to the
	/// setting is skipped by the palette and by project search alike.
	@Test func theWalkSkipsExcludedDirectories() async throws {
		let root = try await makeProject(
			files: ["keep.swift", "node_modules/skip.swift", "build/skip.swift"],
			asRepository: false
		)
		defer { try? FileManager.default.removeItem(at: root) }

		let listed = await ProjectFiles.list(in: root)

		#expect(listed.contains("keep.swift"))
		#expect(!listed.contains { $0.hasPrefix("node_modules/") }, "\(listed)")
		#expect(!listed.contains { $0.hasPrefix("build/") }, "\(listed)")
	}

	/// A project under `/tmp` is reached through `/private/tmp`, and without
	/// canonicalising both sides every file failed to be under its own root.
	@Test func pathsAreRelativeToTheRootEvenUnderTmp() async throws {
		let root = try await makeProject(files: ["a/b.swift"], asRepository: false)
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(await ProjectFiles.list(in: root) == ["a/b.swift"])
	}

	// MARK: - The index

	@Test func theIndexAnswersFromWhatItListed() async throws {
		let root = try await makeProject(
			files: ["Sources/Git/Client.swift", "Sources/Model/Git.swift"], asRepository: true
		)
		defer { try? FileManager.default.removeItem(at: root) }

		let index = FileIndex(root: root)
		#expect(!(await index.isReady))
		await index.prepare()

		#expect(await index.isReady)
		#expect(await index.count == 2)
		#expect(await index.matches("Git").first == "Sources/Model/Git.swift")
	}

	/// Several callers wanting the list at once get one build, not several. Each
	/// is a `git ls-files` over the whole repository.
	@Test func concurrentPreparesAreJoinedRatherThanRepeated() async throws {
		let root = try await makeProject(files: ["a.swift"], asRepository: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let index = FileIndex(root: root)

		await withTaskGroup(of: Void.self) { group in
			for _ in 0..<6 { group.addTask { await index.prepare() } }
			for await _ in group {}
		}

		#expect(await index.isReady)
		#expect(await index.count == 1, "the list was built more than once, or torn")
	}

	// MARK: - Staying true

	/// The file somebody is about to look for is the one they just saved — and
	/// it is untracked, so git would not have listed it.
	@Test func aFileCreatedAfterTheBuildIsFound() async throws {
		let root = try await makeProject(files: ["a.swift"], asRepository: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let index = FileIndex(root: root)
		await index.prepare()
		#expect(await index.matches("fresh").isEmpty)

        let fresh = root.appendingPathComponent("fresh.swift")
		try "new\n".write(to: fresh, atomically: true, encoding: .utf8)
		await index.noticed(changed: [fresh])

		#expect(await index.matches("fresh") == ["fresh.swift"])
	}

	@Test func aDeletedFileStopsBeingListed() async throws {
		let root = try await makeProject(files: ["gone.swift"], asRepository: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let index = FileIndex(root: root)
		await index.prepare()

		let gone = root.appendingPathComponent("gone.swift")
		try FileManager.default.removeItem(at: gone)
		await index.noticed(changed: [gone])

		#expect(await index.matches("gone").isEmpty)
		#expect(await index.count == 0)
	}

	/// A filesystem event names files inside `node_modules` like any other, so
	/// without the same exclusions a build would put back, one file at a time,
	/// everything the walk exists to keep out.
	@Test func aFileInAnExcludedDirectoryIsNotAddedByAnEvent() async throws {
		let root = try await makeProject(files: ["a.swift"], asRepository: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let index = FileIndex(root: root)
		await index.prepare()

		let noisy = root.appendingPathComponent("node_modules/pkg/index.js")
		try FileManager.default.createDirectory(
			at: noisy.deletingLastPathComponent(), withIntermediateDirectories: true
		)
		try "x\n".write(to: noisy, atomically: true, encoding: .utf8)
		await index.noticed(changed: [noisy])

		#expect(await index.matches("index.js").isEmpty)
	}

	/// A file outside the project is not the project's.
	@Test func aFileOutsideTheProjectIsIgnored() async throws {
		let root = try await makeProject(files: ["a.swift"], asRepository: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let index = FileIndex(root: root)
		await index.prepare()

		await index.noticed(changed: [URL(fileURLWithPath: "/etc/hosts")])

		#expect(await index.count == 1)
	}

	/// The case an event cannot describe: the kernel gave up naming a burst file
	/// by file, so the list is thrown away and taken again.
	@Test func rebuildingPicksUpEverythingAgain() async throws {
		let root = try await makeProject(files: ["a.swift"], asRepository: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let index = FileIndex(root: root)
		await index.prepare()

		let second = root.appendingPathComponent("b.swift")
		try "x\n".write(to: second, atomically: true, encoding: .utf8)
		_ = await GitRepository.run(["add", "-A"], in: root)
		await index.rebuild()

		#expect(await index.count == 2)
		#expect(await index.matches("b.swift") == ["b.swift"])
	}
}
