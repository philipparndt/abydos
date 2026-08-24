import Testing
import Foundation
@testable import AbydosKit

/// What opening a project costs before anything is on screen, and why the two
/// walks that dominate it do not belong on the main thread.
///
/// Switching into a large work tree held the main thread for **2,419 ms** —
/// measured with `--switch-to` at load 10.55, on a synthetic tree of 13,363
/// folders and 72,500 untracked files. The window stopped answering for that
/// whole time, which is what "it feels like it has crashed" was, and the
/// terminal stopped drawing with it.
///
/// Two phases were all of it:
///
///     nav.refreshDependencies     1195.74 ms
///     lsp.suitedDefinitions       1189.96 ms
///     ...everything else            ~29 ms
///
/// Both are directory walks. Both now run off the main thread, and the switch
/// measures 29 ms.
///
/// **Every bound here is on processor time**, as the rest of the performance
/// suite is and for the reason written at the top of `PerformanceTests`: this
/// runs beside several hundred other tests, and a wall clock over it would be
/// measuring what the machine was doing instead.
struct ProjectWalkCostTests {
	/// A project shaped like the one that was slow: many sibling modules, each
	/// with build output under it, and a manifest at the top.
	///
	/// Smaller than the real thing on purpose — a suite that built thirteen
	/// thousand directories would cost more than it proves. The claim being
	/// tested is that cost grows with the *tree*, which a few hundred folders
	/// already shows.
	static func makeWideProject(modules: Int, buildsEach: Int) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-walk-\(UUID().uuidString)")
		let manager = FileManager.default
		for module in 0..<modules {
			for build in 0..<buildsEach {
				let directory = root
					.appendingPathComponent("module\(module)")
					.appendingPathComponent("build\(build)")
				try manager.createDirectory(at: directory, withIntermediateDirectories: true)
				try "x".write(
					to: directory.appendingPathComponent("C.class"),
					atomically: true, encoding: .utf8
				)
			}
		}
		return root
	}

	// MARK: - Why it is not on the main thread

	/// The dependency read walks the project, so what it costs is a property of
	/// the tree rather than of the manifest.
	///
	/// Printed rather than bounded tightly: the number that mattered was
	/// measured in the app, and this is the tripwire that says the walk is still
	/// a walk. A change that made it free would be a change that stopped looking.
	@Test func theDependencyReadCostGrowsWithTheTree() throws {
		let small = try Self.makeWideProject(modules: 10, buildsEach: 4)
		let wide = try Self.makeWideProject(modules: 80, buildsEach: 4)
		defer {
			try? FileManager.default.removeItem(at: small)
			try? FileManager.default.removeItem(at: wide)
		}

		let cheap = PerformanceTests.cpuTime("dependency read, 10 modules") {
			_ = ExternalDependencies.read(project: small)
		}
        let dear = PerformanceTests.cpuTime("dependency read, 80 modules") {
			_ = ExternalDependencies.read(project: wide)
		}

		print(String(format: "PERF dependency read grew %.1fx for 8x the tree — %@",
			cheap > 0 ? dear / cheap : 0, MachineLoad.said))

		// The claim is only that it is a walk: eight times the tree costs
		// materially more than one. Anything tighter would be asserting the
		// filesystem's mood.
		guard Stopwatch.maySay("PERF", "dependency read") else { return }
		#expect(dear > cheap, "the read did not grow with the tree — \(MachineLoad.said)")
	}

	/// The language-server scan is the second walk, and it is the same shape.
	@Test func theLanguageServerScanCostGrowsWithTheTree() throws {
		let small = try Self.makeWideProject(modules: 10, buildsEach: 4)
		let wide = try Self.makeWideProject(modules: 80, buildsEach: 4)
		defer {
			try? FileManager.default.removeItem(at: small)
			try? FileManager.default.removeItem(at: wide)
		}

		let choices = LanguageServerChoices()
		let cheap = PerformanceTests.cpuTime("server scan, 10 modules") {
			_ = LanguageServers.suitedDefinitions(in: small, choosing: choices)
		}
		let dear = PerformanceTests.cpuTime("server scan, 80 modules") {
			_ = LanguageServers.suitedDefinitions(in: wide, choosing: choices)
		}

		print(String(format: "PERF server scan grew %.1fx for 8x the tree — %@",
			cheap > 0 ? dear / cheap : 0, MachineLoad.said))

		guard Stopwatch.maySay("PERF", "server scan") else { return }
		#expect(dear > cheap, "the scan did not grow with the tree — \(MachineLoad.said)")
	}

	// MARK: - That they may be run off it

	/// Moving work to a background queue is only safe if it is safe there, so
	/// the claim is tested rather than assumed: the same project, read from
	/// several queues at once, gives every caller the same answer.
	@Test func theDependencyReadIsSafeToRunOffTheMainThread() async throws {
		let root = try Self.makeWideProject(modules: 12, buildsEach: 3)
		defer { try? FileManager.default.removeItem(at: root) }
		try "// swift-tools-version:6.0\n".write(
			to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
		)

		let expected = ExternalDependencies.read(project: root)

		let answers = await withTaskGroup(of: Int.self) { group in
			for _ in 0..<8 {
				group.addTask { ExternalDependencies.read(project: root).count }
			}
			var seen: [Int] = []
			for await count in group { seen.append(count) }
			return seen
		}

		#expect(answers.count == 8)
		#expect(answers.allSatisfy { $0 == expected.count },
		        "concurrent reads disagreed: \(answers) against \(expected.count)")
	}

	/// The same for the scan, which holds a `DirectoryIndex` for the length of
	/// one call — so two calls at once must not be sharing it.
	@Test func theLanguageServerScanIsSafeToRunOffTheMainThread() async throws {
		let root = try Self.makeWideProject(modules: 12, buildsEach: 3)
		defer { try? FileManager.default.removeItem(at: root) }
		try "module example\n".write(
			to: root.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8
		)

		let choices = LanguageServerChoices()
		let expected = LanguageServers.suitedDefinitions(in: root, choosing: choices).map(\.name)

		let answers = await withTaskGroup(of: [String].self) { group in
			for _ in 0..<8 {
				group.addTask {
					LanguageServers.suitedDefinitions(in: root, choosing: choices).map(\.name)
				}
			}
			var seen: [[String]] = []
			for await names in group { seen.append(names) }
			return seen
		}

		#expect(answers.count == 8)
		#expect(answers.allSatisfy { $0 == expected },
		        "concurrent scans disagreed: \(answers) against \(expected)")
	}

	/// And that the scan still finds what it is for. A walk moved off the main
	/// thread that stopped answering would be fast and useless.
	@Test func theScanStillFindsAProjectsMarkers() throws {
		let root = try Self.makeWideProject(modules: 4, buildsEach: 2)
		defer { try? FileManager.default.removeItem(at: root) }
		try "module example\n".write(
			to: root.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8
		)

		let found = LanguageServers.suitedDefinitions(in: root, choosing: LanguageServerChoices())
		#expect(found.contains { $0.languageIds.contains("go") },
		        "a project with a go.mod found no Go server: \(found.map(\.name))")
	}
}
