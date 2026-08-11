import Foundation
import Testing
@testable import AbydosKit

/// Finding this module's resources from wherever the code is running.
///
/// Written for 0464: `abydos-backlog start` aborted in SwiftPM's generated
/// `Bundle.module` accessor after it had made a worktree and moved an item. The
/// tool ships at `Abydos.app/Contents/Resources/bin/`, so its `Bundle.main` is
/// that `bin` directory and the bundles are one level up — and the accessor
/// answers "not beside the executable" with `fatalError`.
struct ModuleResourcesTests {
	private func temporaryDirectory() throws -> URL {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("resources-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	@Test func nothingToFindIsNilRatherThanAnAbort() throws {
		let empty = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(at: empty) }

		#expect(ModuleResources.locate(in: []) == nil)
		#expect(ModuleResources.locate(in: [empty]) == nil)
		// A directory that is not there at all, which is the ordinary case for a
		// candidate: every one of them is a guess and most of them are wrong.
		#expect(ModuleResources.locate(in: [empty.appendingPathComponent("gone")]) == nil)
	}

	/// Both layouts, because the two builds that matter disagree: `swift build`
	/// emits a flat bundle and a packaged `.app` carries the wrapped form.
	@Test(arguments: ["", "Contents/Resources"])
	func aBundleIsFoundInEitherLayout(_ layout: String) throws {
		let root = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(at: root) }

		var inside = root.appendingPathComponent("Some_Target.bundle", isDirectory: true)
		if !layout.isEmpty { inside = inside.appendingPathComponent(layout, isDirectory: true) }
		try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
		try "hello\n".write(to: inside.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)

		let bundle = try #require(ModuleResources.locate("Some_Target", in: [root]))
		#expect(bundle.url(forResource: "hello", withExtension: "txt") != nil)
	}

	/// The case the bug was: a tool inside the application, whose resources are
	/// not beside it.
	@Test func aToolInsideAnApplicationLooksInTheApplicationsResources() {
		let bin = URL(fileURLWithPath: "/Applications/Abydos.app/Contents/Resources/bin")
		#expect(ModuleResources.applicationResources(containing: bin)?.path
			== "/Applications/Abydos.app/Contents/Resources")

		// And the app's own executable, which is a different distance from the
		// bundle — hence walking up rather than counting components.
		let macOS = URL(fileURLWithPath: "/Applications/Abydos.app/Contents/MacOS")
		#expect(ModuleResources.applicationResources(containing: macOS)?.path
			== "/Applications/Abydos.app/Contents/Resources")
	}

	@Test func anExecutableInNoApplicationHasNoApplicationResources() {
		// `make install-cli` puts these tools here, where there is no bundle at
		// all. Nothing to find is a fallback, never a crash.
		#expect(ModuleResources.applicationResources(containing: URL(fileURLWithPath: "/usr/local/bin")) == nil)
		#expect(ModuleResources.applicationResources(containing: URL(fileURLWithPath: "/")) == nil)
	}

	/// The resources this module actually ships, through the resolver rather than
	/// through the accessor. If this fails the app draws in the grey fallback.
	@Test func theShippedResourcesAreFound() throws {
		#expect(ModuleResources.bundle != nil)
		#expect(SchemeLibrary.bundledDirectory != nil)
		#expect(ModuleResources.url(forResource: "Schemes", withExtension: nil) != nil)
	}

	/// The rule, as a test, because the accessor is generated and therefore
	/// always available to whoever types it next.
	///
	/// `Bundle.module` cannot be used in this package: it aborts the process when
	/// it cannot find the bundle, and there are two shipped executables it cannot
	/// find the bundle from. Comments are allowed to name it — this file and
	/// `ModuleResources` both explain why not — so only code counts.
	@Test func noSourceReachesForBundleModule() throws {
		let sources = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Sources")

		var offenders: [String] = []
		let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
		while let url = files?.nextObject() as? URL {
			guard url.pathExtension == "swift" else { continue }
			guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
			let code = text.components(separatedBy: "\n")
				.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
			if code.contains(where: { $0.contains("Bundle.module") }) {
				offenders.append(url.lastPathComponent)
			}
		}
		let named = offenders.joined(separator: ", ")
		#expect(
			offenders.isEmpty,
			"use ModuleResources instead — Bundle.module aborts when it cannot find the bundle: \(named)"
		)
	}
}
