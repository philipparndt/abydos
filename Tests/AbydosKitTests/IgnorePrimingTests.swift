import Testing
import Foundation
@testable import AbydosKit

/// Asking whether *these* paths are ignored, rather than walking everything.
///
/// `refreshIgnored` asks `git status --ignored`, which walks the whole work
/// tree — and `--ignored` is the flag that turns git's untracked cache off, so
/// it walks cold. On this project, whose `.build` is 6.4 GB and 31,350 files,
/// that is 0.41 s against 0.03 s for the same status without it. The tree
/// paints long before that lands, so every ignored file is drawn as part of the
/// project and then turns grey: a flash of the wrong answer on every project
/// switch.
///
/// `check-ignore` costs the number of paths asked about rather than the size of
/// the repository, which is what makes it the right question for the rows on
/// screen.
struct IgnorePrimingTests {
	private func repository(_ ignore: String) throws -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("ignore-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		for command in [
			["init", "-q", "-b", "main", "."],
			["config", "user.email", "t@example.com"],
			["config", "user.name", "T"],
		] {
			_ = GitRepository.runSync(command, in: root)
		}
		try ignore.write(
			to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8
		)
		return root
	}

	private func write(_ text: String, _ path: String, in root: URL) throws {
		let url = root.appendingPathComponent(path)
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(), withIntermediateDirectories: true
		)
		try text.write(to: url, atomically: true, encoding: .utf8)
	}

	@Test func itNamesTheIgnoredOnesAndLeavesTheRest() async throws {
		let root = try repository("*.log\nbuild/\n")
		defer { try? FileManager.default.removeItem(at: root) }
		try write("x", "noise.log", in: root)
		try write("x", "build/out.o", in: root)
		try write("int main(){}", "src/main.c", in: root)

		let repository = GitRepository(root: root)
		let ignored = await repository.ignored(
			among: ["noise.log", "build", "src/main.c", ".gitignore"]
		)
		#expect(ignored == ["noise.log", "build"])
	}

	/// **A tracked file that matches a rule is not ignored**, and git's own
	/// `status --ignored` says so too. `check-ignore` reads the index, which is
	/// what makes the two agree — and disagreeing here would grey out a file
	/// that is genuinely part of the project.
	@Test func aTrackedFileMatchingARuleIsNotIgnored() async throws {
		let root = try repository("*.log\n")
		defer { try? FileManager.default.removeItem(at: root) }
		try write("x", "kept.log", in: root)
		try write("x", "noise.log", in: root)
		_ = GitRepository.runSync(["add", "-f", ".gitignore", "kept.log"], in: root)
		_ = GitRepository.runSync(["commit", "-qm", "first"], in: root)

		let repository = GitRepository(root: root)
		let ignored = await repository.ignored(among: ["kept.log", "noise.log"])
		#expect(ignored == ["noise.log"], "a tracked file is part of the project")
	}

	/// Nothing matching is an ordinary answer. `check-ignore` exits 1 for it,
	/// and reading that as a failure would leave every row uncoloured.
	@Test func nothingMatchingIsNotAFailure() async throws {
		let root = try repository("*.log\n")
		defer { try? FileManager.default.removeItem(at: root) }
		try write("int main(){}", "src/main.c", in: root)

		#expect(await GitRepository(root: root).ignored(among: ["src/main.c"]).isEmpty)
	}

	@Test func askingAboutNothingRunsNothing() async throws {
		let root = try repository("*.log\n")
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(await GitRepository(root: root).ignored(among: []).isEmpty)
	}

	/// The priming feeds the same cache the full sweep fills, so a row drawn
	/// straight afterwards is already grey.
	@Test func primingColoursTheRowsBeforeTheSweep() async throws {
		let root = try repository("*.log\nbuild/\n")
		defer { try? FileManager.default.removeItem(at: root) }
		try write("x", "noise.log", in: root)
		try write("x", "build/out.o", in: root)

		let repository = GitRepository(root: root)
		// Nothing asked yet: the tree would draw these as part of the project.
		#expect(await repository.status(forRelativePath: "noise.log", isDirectory: false)
			!= .ignored)

		await repository.primeIgnored(for: [
			(path: "noise.log", isDirectory: false),
			(path: "build", isDirectory: true),
		])

		#expect(await repository.status(forRelativePath: "noise.log", isDirectory: false)
			== .ignored)
		#expect(await repository.status(forRelativePath: "build", isDirectory: true) == .ignored)
	}

	/// A directory answered as ignored has to carry its children, which is what
	/// `ignoredDirectories` is for — a build folder is one row and ten thousand
	/// files underneath it.
	@Test func aPrimedDirectoryCarriesWhatIsInsideIt() async throws {
		let root = try repository("build/\n")
		defer { try? FileManager.default.removeItem(at: root) }
		try write("x", "build/deep/out.o", in: root)

		let repository = GitRepository(root: root)
		await repository.primeIgnored(for: [(path: "build", isDirectory: true)])
		#expect(await repository.status(forRelativePath: "build/deep/out.o", isDirectory: false)
			== .ignored)
	}

	/// `-z` changes both directions. Feeding newline-separated paths to it
	/// returns nothing at all, silently, which looks exactly like a project
	/// whose rules match nothing.
	@Test func pathsWithSpacesAndNonAsciiSurvive() async throws {
		let root = try repository("*.log\n")
		defer { try? FileManager.default.removeItem(at: root) }
		try write("x", "my logs/kühlschrank.log", in: root)

		let ignored = await GitRepository(root: root)
			.ignored(among: ["my logs/kühlschrank.log"])
		#expect(ignored == ["my logs/kühlschrank.log"])
	}
}
