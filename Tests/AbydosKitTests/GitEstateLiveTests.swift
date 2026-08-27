import Foundation
import Testing
@testable import AbydosKit

/// The estate against real submodules on disk.
///
/// Every claim here is about what git does, and a fixture cannot answer any of
/// them: what the index calls a gitlink, where a submodule's git directory
/// lands, and which of a submodule's states the superproject can see.
struct GitEstateLiveTests {
	@Test func theInventoryIsReadFromTheIndex() async throws {
		let estate = try SyntheticEstate.make(count: 3, named: "inventory")
		defer { estate.remove() }

		let read = await GitEstate.read(from: estate.root)
		#expect(read.holdsSubmodules)
		#expect(read.submodules.map(\.path) == ["svc-1", "svc-2", "svc-3"])
		#expect(read.submodules.filter { $0.recordedCommit.count == 40 }.count == 3)
		#expect(read.submodules.filter(\.isCheckedOut).count == 3)
		#expect(read.submodules.first?.url == "../pool/svc-1")
	}

	@Test func aRepositoryWithNoSubmodulesIsAnEstateOfOne() async throws {
		let estate = try SyntheticEstate.make(count: 0, named: "plain")
		defer { estate.remove() }

		let read = await GitEstate.read(from: estate.root)
		#expect(!read.holdsSubmodules)
		#expect(read.repositoryRoots == [estate.root.standardizedFileURL])
	}

	/// A fresh clone without `--recurse-submodules` leaves exactly this, and so
	/// does removing a service that somebody else has not pulled yet. It is
	/// shown as absent — the estate is read, not administered.
	@Test func aSubmoduleTheIndexNamesAndDiskLacksIsAbsent() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "absent")
		defer { estate.remove() }

		// Take the checkout away, leaving the index untouched.
		try FileManager.default.removeItem(
			at: estate.root.appendingPathComponent("svc-2")
		)

		let read = await GitEstate.read(from: estate.root)
		#expect(read.submodules.map(\.path) == ["svc-1", "svc-2"], "it is still in the index")
		#expect(read.submodules.first(where: { $0.path == "svc-2" })?.isCheckedOut == false)
		#expect(!read.repositoryRoots.contains(estate.root.appendingPathComponent("svc-2")),
			"nothing is run in a repository that is not there")
	}

	/// The layout the whole watching design rests on: one watcher over the
	/// superproject's `.git` sees every submodule's refs and index, because
	/// every submodule's git directory is inside it.
	@Test func everySubmodulesGitDirectoryIsUnderTheSuperprojects() async throws {
		let estate = try SyntheticEstate.make(count: 3, named: "layout")
		defer { estate.remove() }

		let modules = estate.root.appendingPathComponent(".git/modules")
		for name in estate.submodulePaths {
			#expect(
				FileManager.default.fileExists(
					atPath: modules.appendingPathComponent(name).path
				),
				"\(name) has no git directory under the superproject"
			)

			// And the submodule's own `.git` is the file that points there —
			// the same fact `ProjectRoot.isSubmodulePointer` reads.
			let pointer = estate.root.appendingPathComponent(name).appendingPathComponent(".git")
			let contents = try String(contentsOf: pointer, encoding: .utf8)
			#expect(contents.contains("/modules/"), "\(name): \(contents)")
		}
	}
}
