import Foundation
import Testing
@testable import AbydosKit

/// The folder beside a project, across the app's rename.
///
/// The folder is data — launch configurations somebody wrote and committed,
/// breakpoints they placed, the session they left open — and data outlives the
/// name of the program that wrote it. A rename that reads only the new name is
/// a rename that throws all of that away on projects that predate it.
struct ProjectFolderMigrationTests {
	static func project(folder: String?) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("folder-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

		guard let folder else { return root }
		let run = root.appendingPathComponent("\(folder)/run")
		try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
		try "{}".write(to: run.appendingPathComponent("thing.json"), atomically: true, encoding: .utf8)
		return root
	}

	@Test func readsTheOldFolderWhenThatIsWhatAProjectHas() throws {
		let root = try Self.project(folder: ".ideai")
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(AbydosFolder.exists(in: root))
		#expect(AbydosFolder.url(in: root).lastPathComponent == ".ideai")
		#expect(FileManager.default.fileExists(
			atPath: AbydosFolder.runDirectory(in: root).appendingPathComponent("thing.json").path
		))
	}

	/// Moved rather than copied: two folders would both be read by something
	/// eventually, and a configuration edited in one while the other still
	/// exists is a bug nobody enjoys.
	@Test func movesItAcrossTheFirstTimeSomethingIsWritten() throws {
		let root = try Self.project(folder: ".ideai")
		defer { try? FileManager.default.removeItem(at: root) }

		_ = try AbydosFolder.create(in: root)

		#expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".abydos/run/thing.json").path))
		#expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".ideai").path))
		#expect(AbydosFolder.url(in: root).lastPathComponent == ".abydos")
	}

	/// A project that has both has been worked in since the rename. The old one
	/// is then somebody's to delete, and moving over the new one would lose
	/// what they have done since.
	@Test func leavesBothAloneWhenBothExist() throws {
		let root = try Self.project(folder: ".abydos")
		defer { try? FileManager.default.removeItem(at: root) }
		try FileManager.default.createDirectory(
			at: root.appendingPathComponent(".ideai/run"), withIntermediateDirectories: true
		)

		#expect(try AbydosFolder.migrateIfNeeded(in: root) == false)
		#expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".ideai").path))
		// The new one is what is read while both are there.
		#expect(AbydosFolder.url(in: root).lastPathComponent == ".abydos")
	}

	@Test func aProjectWithNeitherGetsTheNewName() throws {
		let root = try Self.project(folder: nil)
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(!AbydosFolder.exists(in: root))
		#expect(AbydosFolder.url(in: root).lastPathComponent == ".abydos")

		_ = try AbydosFolder.create(in: root)
		#expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".abydos/.gitignore").path))
	}

	/// Everything that lives in the folder follows it, since they are all
	/// spelled from the same place.
	@Test func theSessionAndTheConfigurationsFollowTheFolder() throws {
		let root = try Self.project(folder: ".ideai")
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(AbydosFolder.sessionFile(in: root).path.contains("/.ideai/"))
		_ = try AbydosFolder.create(in: root)
		#expect(AbydosFolder.sessionFile(in: root).path.contains("/.abydos/"))
	}
}
