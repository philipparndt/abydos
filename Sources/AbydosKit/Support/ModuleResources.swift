import Foundation

/// Where this module's resources are, looked for rather than assumed.
///
/// SwiftPM generates a `Bundle.module` accessor for any target with resources,
/// and that accessor is not usable in this package. Two reasons, and the second
/// is the one that cost an afternoon:
///
/// - It calls `fatalError` when it cannot find the bundle. A missing colour
///   scheme is not worth taking a process down for, and taking it down is what
///   happens: 0464 was `abydos-backlog start` dying after it had made the
///   worktree and moved the item, because reading one setting reached the
///   scheme library.
/// - It only looks beside the executable and inside `Bundle.main`. The
///   command-line tools ship at `Abydos.app/Contents/Resources/bin/`, so their
///   `Bundle.main` *is* that `bin` directory and the bundles are one level up,
///   in the app's `Resources`. Nothing beside the executable, nothing found.
///
/// So the rule in this package is: never `Bundle.module`, always this. It
/// returns `nil` where the generated accessor would abort, and every caller
/// already had to handle a resource that is not there — a build assembled by
/// hand can leave one out.
public enum ModuleResources {
	/// SwiftPM's name for this target's bundle: `<package>_<target>`. It follows
	/// a rename of either, so a stale name here is resources that cannot be
	/// found by a build that is otherwise correct.
	public static let bundleName = "Abydos_AbydosKit"

	/// Anchor for asking which bundle this code was loaded from, which is what
	/// makes resource lookup work under `swift test` as well as in the app.
	private final class Anchor {}

	/// Directories a resource bundle may sit in, in the order they are tried.
	///
	/// Four contexts have to work and they disagree about where resources sit: a
	/// packaged `.app` (the main bundle's resources), a bare `swift build`
	/// executable (the directory next to the binary), a test run (where
	/// `Bundle.main` is the test runner and not this code), and a tool inside an
	/// `.app` (where the bundles are in the app's `Resources` and the tool is in
	/// a subdirectory of it). Rather than branch on which one we are in, try
	/// each and take the first that actually holds the file.
	///
	/// Shared with the grammar lookup in `LanguageRegistry`: the grammar bundles
	/// and this module's own are copied into the same directory by
	/// `Scripts/bundle.sh` and emitted into the same one by `swift build`, so
	/// two lists of places to look would be two lists to keep in step.
	public static let searchDirectories: [URL] = {
		var candidates: [URL] = []

		// The override SwiftPM's own accessor honours, so a build that puts the
		// bundles somewhere unusual can still say where they went.
		if let path = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"] {
			candidates.append(URL(fileURLWithPath: path))
		}

		if let resources = Bundle.main.resourceURL { candidates.append(resources) }
		candidates.append(Bundle.main.bundleURL)

		let own = Bundle(for: Anchor.self)
		if let resources = own.resourceURL { candidates.append(resources) }
		// SwiftPM places dependency bundles beside the test bundle, one level up.
		candidates.append(own.bundleURL.deletingLastPathComponent())

		// The application this executable ships inside, when it ships inside
		// one. Walked up to rather than assumed one level, so it holds for
		// `Contents/Resources/bin/` and for anywhere else in the bundle a tool
		// is ever put.
		if let resources = applicationResources(containing: Bundle.main.bundleURL) {
			candidates.append(resources)
		}

		return candidates
	}()

	/// This module's resource bundle, or `nil` when this build has none.
	public static let bundle: Bundle? = locate(in: searchDirectories)

	/// A named resource bundle in the first of these directories that has one.
	///
	/// `nil` rather than an abort, which is the difference between this and
	/// SwiftPM's accessor and the only reason this type exists.
	static func locate(_ name: String = bundleName, in directories: [URL]) -> Bundle? {
		for base in directories {
			let url = base.appendingPathComponent("\(name).bundle", isDirectory: true)
			guard FileManager.default.fileExists(atPath: url.path) else { continue }
			if let bundle = Bundle(url: url) { return bundle }
		}
		return nil
	}

	/// A resource of this module, or `nil` — the whole point of this type.
	public static func url(
		forResource name: String?,
		withExtension extension: String?,
		subdirectory: String? = nil
	) -> URL? {
		bundle?.url(forResource: name, withExtension: `extension`, subdirectory: subdirectory)
	}

	/// The `Resources` directory of the `.app` a path is inside, if any.
	///
	/// Found by walking up looking for a `.app`, because the two places a binary
	/// sits in this bundle — `Contents/MacOS/` for the app itself and
	/// `Contents/Resources/bin/` for the tools — are different distances from it,
	/// and a third place is a thing somebody may add.
	static func applicationResources(containing path: URL) -> URL? {
		var directory = path.resolvingSymlinksInPath()
		// Bounded: an absolute path has an end, but a loop that trusts
		// `deletingLastPathComponent` to reach it is a loop that spins on `/`.
		for _ in 0..<8 {
			if directory.pathExtension == "app" {
				return directory
					.appendingPathComponent("Contents", isDirectory: true)
					.appendingPathComponent("Resources", isDirectory: true)
			}
			let parent = directory.deletingLastPathComponent()
			if parent.path == directory.path { return nil }
			directory = parent
		}
		return nil
	}
}
