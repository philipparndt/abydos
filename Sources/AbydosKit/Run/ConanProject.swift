import Foundation

/// A Conan package, and the three things anybody does with one.
///
/// Conan is a package manager rather than a build system: it fetches and builds
/// dependencies, generates the files a build system then uses, and — for a
/// package of your own — builds and packages it. So there are no targets to
/// enumerate the way a Makefile has goals. There are commands, and which of
/// them make sense depends only on which files are present.
///
/// `conanfile.py` is Python and is not read here beyond the two lines that
/// state what the package is called. Running it to ask would mean running
/// somebody's build script to populate a menu.
public enum ConanProject: Equatable, Sendable {
	/// `conanfile.py`: a package of your own, which can be built and created.
	case recipe(URL)
	/// `conanfile.txt`: a list of dependencies for a project that is not itself
	/// a package. It can be installed, and nothing else.
	case requirements(URL)

	public var file: URL {
		switch self {
		case let .recipe(url), let .requirements(url): return url
		}
	}

	/// Where conan runs: the directory holding the file.
	public var directory: URL { file.deletingLastPathComponent() }

	/// What a project can be asked to do.
	public enum Action: String, CaseIterable, Sendable {
		/// Fetch and build the dependencies, and generate the files the build
		/// system will use.
		case install
		/// Build this package locally, in the layout `install` prepared.
		case build
		/// Build it and put it in the local cache as a package, which is what
		/// another project would consume.
		case create
		/// Build and run the package's own test package.
		case test

		public var title: String {
			switch self {
			case .install: return "Conan Install"
			case .build:   return "Conan Build"
			case .create:  return "Conan Create"
			case .test:    return "Conan Test"
			}
		}
	}

	/// The actions that make sense here.
	///
	/// A `conanfile.txt` has no recipe to build or create — it only says what
	/// to fetch — so offering those would be offering an error message.
	public var actions: [Action] {
		switch self {
		case .recipe:
			return [.install, .build, .create, .test]
		case .requirements:
			return [.install]
		}
	}

	/// The command line for an action, as Conan 2 spells it.
	///
	/// `--build=missing` on install because the alternative is a failure
	/// telling somebody to add it: a dependency with no binary for this
	/// platform is the ordinary case on macOS on ARM, and building it is what
	/// they were going to do next anyway.
	public func command(for action: Action) -> (executable: String, arguments: [String]) {
		switch action {
		case .install:
			return ("conan", ["install", ".", "--build=missing"])
		case .build:
			return ("conan", ["build", "."])
		case .create:
			return ("conan", ["create", ".", "--build=missing"])
		case .test:
			// The convention Conan itself documents: a `test_package`
			// directory beside the recipe, built against the package.
			return ("conan", ["test", "test_package", "."])
		}
	}

	/// Whether the file this describes is worth offering at all.
	public var isUsable: Bool {
        switch self {
        case let .recipe(url), let .requirements(url):
            return !url.path.isEmpty
        }
    }

	/// The conanfile a directory holds, or nil.
	///
	/// The recipe wins where both are present, which happens in a package that
	/// keeps a `conanfile.txt` for its examples: the recipe is the project.
	public static func find(
		in directory: URL,
		fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
	) -> ConanProject? {
		let recipe = directory.appendingPathComponent("conanfile.py")
		if fileExists(recipe.path) { return .recipe(recipe) }

		let requirements = directory.appendingPathComponent("conanfile.txt")
		if fileExists(requirements.path) { return .requirements(requirements) }

		return nil
	}

	/// What the package calls itself, for naming the configurations after it.
	///
	/// Read rather than executed: `name = "fmt"` at the top of a recipe is a
	/// line, and running the file to ask would mean running somebody's build
	/// script to fill in a menu.
	public static func packageName(inRecipe contents: String) -> String? {
		for line in contents.components(separatedBy: "\n") {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard trimmed.hasPrefix("name") else { continue }
			let after = trimmed.dropFirst("name".count).drop { $0 == " " || $0 == "\t" }
			guard after.first == "=" else { continue }

			let value = after.dropFirst().drop { $0 == " " || $0 == "\t" }
			guard let quote = value.first, quote == "\"" || quote == "'" else { continue }
			let rest = value.dropFirst()
			guard let end = rest.firstIndex(of: quote) else { continue }

			let name = String(rest[rest.startIndex..<end])
			if !name.isEmpty { return name }
		}
		return nil
	}
}
