import Foundation
@testable import AbydosKit

/// A superproject with submodules in it, built on disk.
///
/// Exists so that claims about an estate are reproducible rather than numbers
/// somebody once saw on a machine that is no longer in that state. Everything
/// about submodules is a claim about what git does — that a submodule's git
/// directory lands under the superproject's `.git/modules`, that a dirty work
/// tree inside one is invisible to `--ignore-submodules=dirty` — and none of
/// that can be tested against a fixture.
///
/// Small by default. A test that wants two hundred says so, and pays for it.
struct SyntheticEstate {
	let root: URL
	let pool: URL
	let submodulePaths: [String]

	private static func git(_ arguments: [String], in directory: URL) -> Int32 {
		// `protocol.file.allow` because adding a submodule from a path on this
		// machine is what a test can do and what git refuses by default since
		// CVE-2022-39253. Nothing here reaches a network.
		GitRepository.runSync(
			["-c", "protocol.file.allow=always"] + arguments, in: directory
		).exitCode
	}

	@discardableResult
	static func run(_ arguments: [String], in directory: URL) -> Int32 {
		git(arguments, in: directory)
	}

	/// A superproject holding `count` submodules named `svc-1`…`svc-<count>`.
	///
	/// `named` gives the temporary directory a name a failing run can be found
	/// by; the whole of it is removed by `remove()`.
	static func make(count: Int, named label: String = "estate") throws -> SyntheticEstate {
		let base = FileManager.default.temporaryDirectory
			.appendingPathComponent("\(label)-\(UUID().uuidString)")
		let pool = base.appendingPathComponent("pool")
		let root = base.appendingPathComponent("super")
		try FileManager.default.createDirectory(at: pool, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

		var paths: [String] = []
		for index in 1...max(count, 1) where count > 0 {
			let name = "svc-\(index)"
			let directory = pool.appendingPathComponent(name)
			try FileManager.default.createDirectory(
				at: directory.appendingPathComponent("src"), withIntermediateDirectories: true
			)
			try "one\n".write(
				to: directory.appendingPathComponent("src/Main.java"),
				atomically: true, encoding: .utf8
			)
			try initialise(directory)
			paths.append(name)
		}

		try initialise(root)
		try "# super\n".write(
			to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8
		)
		_ = git(["add", "."], in: root)
		_ = git(["commit", "-qm", "the superproject"], in: root)

		for name in paths {
			_ = git(
				["submodule", "add", "-q", "../pool/\(name)", name], in: root
			)
		}
		if !paths.isEmpty {
			_ = git(["add", "-A"], in: root)
			_ = git(["commit", "-qm", "\(paths.count) submodules"], in: root)
		}

		return SyntheticEstate(root: root, pool: pool, submodulePaths: paths)
	}

	private static func initialise(_ directory: URL) throws {
		for command in [
			["init", "-q", "-b", "main", "."],
			["config", "user.email", "t@example.com"],
			["config", "user.name", "T"],
		] {
			_ = git(command, in: directory)
		}
		let file = directory.appendingPathComponent("src/Main.java")
		if FileManager.default.fileExists(atPath: file.path) {
			_ = git(["add", "."], in: directory)
			_ = git(["commit", "-qm", "first"], in: directory)
		}
	}

	// MARK: - Disturbing it

	/// Writes into a submodule's work tree without committing: a dirty work
	/// tree, which the superproject must not report.
	func dirty(_ name: String, text: String = "changed\n") throws {
		try text.write(
			to: root.appendingPathComponent(name).appendingPathComponent("src/Main.java"),
			atomically: true, encoding: .utf8
		)
	}

	/// Moves a submodule's HEAD past what the superproject records: a moved
	/// gitlink, which the superproject must report.
	///
	/// **`saying` matters more than it looks.** A commit's hash is its content,
	/// its parent, its author and its timestamp — and a timestamp has
	/// second-resolution — so two empty commits made on the same parent, in the
	/// same second, with the same message are *the same commit*. Two branches
	/// advanced with the default label therefore do not diverge at all, and a
	/// merge of them fast-forwards. That cost an afternoon of a conflict test
	/// that reported no conflict, and git was right every time.
	@discardableResult
	func advance(_ name: String, by commits: Int = 1, saying label: String = "moved") -> Int32 {
		let directory = root.appendingPathComponent(name)
		var last: Int32 = 0
		for index in 0..<commits {
			last = Self.git(
				["commit", "-q", "--allow-empty", "-m", "\(label) \(index)"], in: directory
			)
		}
		return last
	}

	func remove() {
		try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
	}
}
