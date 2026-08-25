import Foundation

/// Where Java lives on this machine, and what a Java project holds.
///
/// The same job `GoTooling` does for Go, and awkward for the same reason: a GUI
/// app inherits almost none of a login shell, so `JAVA_HOME` is usually unset
/// and the toolchain has to be found rather than assumed. Java adds a wrinkle
/// Go does not have — several JDKs are normally installed at once, and the one
/// that runs the language server is not necessarily the one a project compiles
/// against.
public enum JavaTooling {
	/// A JDK on this machine.
	public struct Runtime: Equatable, Sendable {
		/// Eclipse's name for the execution environment — `JavaSE-21`, and
		/// `JavaSE-1.8` for the one everybody still has a service on. This is the
		/// spelling jdtls expects; anything else is ignored without a word.
		public let name: String
		/// The JDK's home, the directory holding `bin/java` and `release`.
		public let home: String
		/// The feature version: 8, 17, 21.
		public let version: Int

		public init(name: String, home: String, version: Int) {
			self.name = name
			self.home = home
			self.version = version
		}
	}

	// MARK: - Toolchains

	/// The JDK to run things with, newest first.
	///
	/// `JAVA_HOME` wins when it is set, because somebody set it deliberately.
	public static func javaHome() -> String? {
		if let home = ProcessInfo.processInfo.environment["JAVA_HOME"],
		   FileManager.default.isExecutableFile(atPath: home + "/bin/java") {
			return home
		}
		return installedRuntimes().first?.home
	}

	/// The `java` binary to run, or nil when there is no JDK.
	///
	/// `/usr/bin/java` exists on every Mac and is a stub that prints an
	/// installation prompt when no JDK is present, so it is used only after the
	/// real ones have been looked for.
	public static func javaExecutable() -> String? {
		if let home = javaHome(), FileManager.default.isExecutableFile(atPath: home + "/bin/java") {
			return home + "/bin/java"
		}
		return FileManager.default.isExecutableFile(atPath: "/usr/bin/java") ? "/usr/bin/java" : nil
	}

	/// Every JDK this machine has, newest first.
	///
	/// The directories are the ones the common installers use: Apple's own
	/// location, which is where Temurin, Corretto and Zulu all land, Homebrew's
	/// keg, and SDKMAN's candidates. Reported so a project targeting 17 can be
	/// compiled against 17 even though the server itself runs on 21.
	public static func installedRuntimes() -> [Runtime] {
		let home = FileManager.default.homeDirectoryForCurrentUser.path
		var homes: [String] = []

		for directory in [
			"/Library/Java/JavaVirtualMachines",
			home + "/Library/Java/JavaVirtualMachines",
		] {
			let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
			homes += entries.map { "\(directory)/\($0)/Contents/Home" }
		}

		// SDKMAN keeps each JDK as its own directory and a `current` symlink
		// beside them, which would otherwise be reported twice.
		let candidates = home + "/.sdkman/candidates/java"
		for entry in (try? FileManager.default.contentsOfDirectory(atPath: candidates)) ?? []
		where entry != "current" {
			homes.append("\(candidates)/\(entry)")
		}

		for keg in (try? FileManager.default.contentsOfDirectory(atPath: "/opt/homebrew/opt")) ?? []
		where keg.hasPrefix("openjdk") {
			homes.append("/opt/homebrew/opt/\(keg)/libexec/openjdk.jdk/Contents/Home")
		}

		var seen = Set<String>()
		var runtimes: [Runtime] = []
		for path in homes {
			let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
			guard seen.insert(resolved).inserted,
			      FileManager.default.isExecutableFile(atPath: resolved + "/bin/javac"),
			      let version = featureVersion(ofJDKAt: resolved)
			else { continue }
			runtimes.append(Runtime(
				name: environmentName(forVersion: version), home: resolved, version: version
			))
		}
		return runtimes.sorted { $0.version > $1.version }
	}

	/// The feature version of a JDK, read from the `release` file it ships.
	///
	/// Reading a file rather than running `java -version`: this is called while
	/// deciding what to tell a language server, and starting a JVM per installed
	/// JDK to ask it its own version would be several seconds of nothing.
	static func featureVersion(ofJDKAt home: String) -> Int? {
		guard let text = try? String(contentsOfFile: home + "/release", encoding: .utf8) else {
			return nil
		}
		for line in text.components(separatedBy: .newlines) {
			guard line.hasPrefix("JAVA_VERSION=") else { continue }
			let value = line
				.dropFirst("JAVA_VERSION=".count)
				.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
			return featureVersion(ofVersionString: value)
		}
		return nil
	}

	/// `21.0.12` is 21, and `1.8.0_402` is 8 — Java changed how it numbers
	/// itself at 9 and both spellings are still in the wild.
	public static func featureVersion(ofVersionString value: String) -> Int? {
		let parts = value.split(separator: ".")
		guard let first = parts.first, let major = Int(first) else { return nil }
		if major == 1 {
			guard parts.count > 1 else { return nil }
			return Int(parts[1].prefix(while: \.isNumber))
		}
		return major
	}

	public static func environmentName(forVersion version: Int) -> String {
		version <= 8 ? "JavaSE-1.\(version)" : "JavaSE-\(version)"
	}

	// MARK: - The language server's workspace

	/// Where jdtls keeps its index for a project.
	///
	/// Outside the project on purpose. It is a few hundred megabytes of derived
	/// state that changes on every keystroke, and putting it in the repository
	/// means either committing it or teaching every project's `.gitignore`
	/// about this editor.
	///
	/// Named after the project and then after the hash of its path, so two
	/// checkouts of the same repository do not share an index — they have
	/// different files in them, and jdtls would quietly serve one project's
	/// answers for the other.
	public static func serverWorkspace(for root: URL) -> URL {
		let path = FilePath.canonical(root)
		let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
			?? URL(fileURLWithPath: NSTemporaryDirectory())
		return caches
			.appendingPathComponent("ideai/jdtls", isDirectory: true)
			.appendingPathComponent("\(root.lastPathComponent)-\(shortHash(path))", isDirectory: true)
	}

	/// A short, stable hash of a string. Not a cryptographic one — it only has
	/// to keep two projects apart and survive a restart.
	static func shortHash(_ value: String) -> String {
		var hash: UInt64 = 0xcbf2_9ce4_8422_2325
		for byte in value.utf8 {
			hash ^= UInt64(byte)
			hash = hash &* 0x100_0000_01b3
		}
		return String(hash, radix: 36)
	}

	// MARK: - The debugger

	/// The java-debug bundle, which is what makes debugging Java possible.
	///
	/// It is not a program: it is an Eclipse plugin that jdtls loads, and the
	/// debug adapter is then started *by the language server* rather than by us.
	/// So it has to be found as a jar and named in the initialize request, and
	/// there is nowhere standard to look — every editor's package manager puts
	/// it somewhere else. All of their places are searched, and
	/// `ABYDOS_JAVA_DEBUG_PLUGIN` overrides the lot.
	public static func debugPlugin() -> String? {
		if let override = ProcessInfo.processInfo.environment["ABYDOS_JAVA_DEBUG_PLUGIN"],
		   FileManager.default.isReadableFile(atPath: override) {
			return override
		}

		let home = FileManager.default.homeDirectoryForCurrentUser.path
		let directories = [
			home + "/.local/share/java-debug",
			home + "/.local/share/nvim/mason/packages/java-debug-adapter/extension/server",
			home + "/.local/share/vim/mason/packages/java-debug-adapter/extension/server",
			"/opt/homebrew/share/java-debug",
			"/usr/local/share/java-debug",
		] + vscodeExtensionDirectories(home: home)

		for directory in directories {
			let entries = ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [])
				.filter { $0.hasPrefix("com.microsoft.java.debug.plugin") && $0.hasSuffix(".jar") }
				.sorted()
			// Sorted and last: several versions side by side is the normal state
			// of an extensions directory, and the newest is the one to load.
			if let newest = entries.last { return "\(directory)/\(newest)" }
		}
		return nil
	}

	/// The `server` directories of any installed VS Code Java debug extension.
	private static func vscodeExtensionDirectories(home: String) -> [String] {
		var found: [String] = []
		for root in ["\(home)/.vscode/extensions", "\(home)/.vscode-insiders/extensions",
		             "\(home)/.cursor/extensions", "\(home)/.windsurf/extensions"] {
			let entries = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
			found += entries
				.filter { $0.hasPrefix("vscjava.vscode-java-debug") }
				.sorted()
				.map { "\(root)/\($0)/server" }
		}
		return found
	}

	/// What to say when the debugger cannot be assembled, in the shape the
	/// language server banner already uses: what it is for, where to get it,
	/// where it has to end up, and how to tell whether it worked.
	public static let debugPluginManual = """
	Debugging Java needs one more piece than running it does. The debugger is not
	a program of its own: it is an Eclipse bundle that the Java language server
	loads, so it has to be on this machine before jdtls starts.

	INSTALL

	  git clone https://github.com/microsoft/java-debug
	  cd java-debug && ./mvnw clean install

	WHERE IT HAS TO END UP

	  ~/.local/share/java-debug/com.microsoft.java.debug.plugin-<version>.jar

	The jar is left in com.microsoft.java.debug.plugin/target/ — copy it there.
	An installation made by another editor is found too: VS Code's Java debug
	extension and Mason's java-debug-adapter are both looked for. Anywhere else,
	set ABYDOS_JAVA_DEBUG_PLUGIN to the jar.

	AFTERWARDS

	The Java language server has to be restarted to load it, which reopening the
	project does.
	"""

	// MARK: - What is in a project

	/// A class with a `main` method, which is what "run this" means in Java.
	public struct MainClass: Equatable, Sendable {
		/// Fully qualified: `com.example.api.Server`, which is what the JVM and
		/// every debug adapter want.
		public let name: String
		public let file: String
		/// 1-based, so a play button can sit beside the method.
		public let line: Int
		/// The module directory the class belongs to — where its build file is,
		/// which is the directory a build has to run in.
		public let module: String

		public init(name: String, file: String, line: Int, module: String) {
			self.name = name
			self.file = file
			self.line = line
			self.module = module
		}

		/// The last component, for a menu that has no room for the package.
		public var simpleName: String {
			name.components(separatedBy: ".").last ?? name
		}
	}

	/// Directories not worth walking into when looking for sources.
	static let skipped: Set<String> = [
		"target", "build", "out", ".git", ".gradle", ".idea", "node_modules", "bin",
	]

	/// Of several source files, the one nearest a directory.
	///
	/// **Which module a classpath is asked about decides which classpath comes
	/// back.** jdtls answers `java.project.getClasspaths` about the module the
	/// file it is given belongs to, so the file is not an incidental anchor — it
	/// chooses the answer. Taking the project's *first* main class meant a
	/// thousand-module repository resolved whichever one the directory walk
	/// reached first: a launch configuration for the Eclipse client was handed
	/// `cli/com.vector.acli.application`'s classpath, and the attach then mapped
	/// frames against the wrong module's jars.
	///
	/// Nearness is counted in shared leading path components with the
	/// configuration's own working directory, which gives the useful answer
	/// without needing to know what a module is. A file inside that directory
	/// shares all of them and wins outright. When the directory holds no Java at
	/// all — an assembly module that is one pom and nothing else, which is what
	/// an OSGi product launch points at — the count still prefers a sibling under
	/// `almplus/client/…` over something under `cli/…`, which is the intent
	/// expressed as arithmetic rather than as a special case.
	///
	/// Ties go to the shorter path: equally near, the one less deep is the more
	/// likely module root.
	public static func nearestFile(to directory: String, among files: [String]) -> String? {
		let target = FilePath.canonicalEvenIfMissing(URL(fileURLWithPath: directory))
			.split(separator: "/").map(String.init)

		return files
			.map { file -> (file: String, shared: Int, depth: Int) in
				let parts = FilePath.canonicalEvenIfMissing(URL(fileURLWithPath: file))
					.split(separator: "/").map(String.init)
				var shared = 0
				for (mine, theirs) in zip(target, parts) {
					guard mine == theirs else { break }
					shared += 1
				}
				return (file, shared, parts.count)
			}
			// Sorted rather than reduced, so the tie-break is written down.
			.sorted { ($0.shared, -$0.depth) > ($1.shared, -$1.depth) }
			.first?.file
	}

	/// A Java source file near a directory, for naming the module a launch
	/// belongs to.
	///
	/// **The anchor does not have to be a main class.** What it is for is naming
	/// a module: jdtls answers `java.project.getClasspaths` about the project the
	/// file it is handed belongs to, so any file in the right module produces the
	/// right classpath. Looking for a *main* class instead meant reading every
	/// source file in the repository to learn something a handful of directory
	/// reads answers — and on the checkout this was measured on, the seven files
	/// with a `main` in them were found among 13,754 that had none.
	///
	/// Conventional locations first, and up rather than down: `src/main/java`
	/// under the working directory, then under each of its parents as far as the
	/// project root. A launch configuration points at the module it runs, so the
	/// first probe usually answers, and each one is a single `stat`.
	///
	/// Only when none of them exists does it walk *downward*, breadth-first from
	/// the working directory, and then under a budget: a configuration whose
	/// directory is the repository root would otherwise be the whole-repository
	/// walk this exists to avoid. `limit` directories are read and the best
	/// answer so far is given, which for choosing between modules is the same
	/// kind of answer a longer walk would have reached.
	public static func nearestJavaFile(
		to directory: URL, under root: URL, limit: Int = 400
	) -> String? {
		let manager = FileManager.default
		let rootPath = FilePath.canonicalEvenIfMissing(root)

		// Upward: the module the launch names, then the ones containing it.
		var cursor = directory
		while true {
			for suffix in ["src/main/java", "src/main/kotlin"] {
				let sources = cursor.appendingPathComponent(suffix)
				guard manager.fileExists(atPath: sources.path) else { continue }
				if let found = firstSourceFile(under: sources, limit: limit) { return found }
			}
			let parent = cursor.deletingLastPathComponent()
			// Stop at the project root, and at the filesystem root for a
			// directory that somehow sits outside it.
			guard FilePath.canonicalEvenIfMissing(cursor) != rootPath,
			      parent.path != cursor.path
			else { break }
			cursor = parent
		}

		// Downward, under a budget. A repository of modules with no `src/main`
		// above the working directory is the case this covers — and a root-level
		// configuration, where any module is as good an answer as the old scan
		// gave.
		return firstJavaFile(under: directory, limit: limit)
			?? firstJavaFile(under: root, limit: limit)
	}

	/// The first Java or Kotlin source under a directory, looking for a *module*
	/// rather than for a file.
	///
	/// **A plain breadth-first walk does not work on a deep repository, and the
	/// first version of this returned nil on the one it was written for.** Sources
	/// live at `almplus/client/core/<module>/src/main/java/com/vector/…/X.java`:
	/// nine levels down, under a root with 17,987 directories beneath it. Breadth
	/// first spends its whole budget on levels two and three and never reaches a
	/// file — and nil is worse than slow, because the caller then falls back to
	/// the *first* main class in the project, which is the wrong-module anchor
	/// that `nearestFile` exists to prevent.
	///
	/// So the walk looks for the thing that is actually shallow: a module, which
	/// announces itself with a `src/main` source root. Two `stat`s per directory
	/// visited, and `src` itself is never descended — the package chain below it
	/// is handled by `firstSourceFile`, which knows it is a chain. What is left to
	/// walk is the module tree, which is shallow and narrow.
	static func firstJavaFile(under directory: URL, limit: Int) -> String? {
		let manager = FileManager.default
		var queue = [directory]
		var read = 0
		var fallback: String?

		while !queue.isEmpty, read < limit {
			let current = queue.removeFirst()
			read += 1

			for suffix in ["src/main/java", "src/main/kotlin"] {
				let sources = current.appendingPathComponent(suffix)
				guard manager.fileExists(atPath: sources.path) else { continue }
				if let found = firstSourceFile(under: sources, limit: limit) { return found }
			}

			guard let entries = try? manager.contentsOfDirectory(
				at: current,
				includingPropertiesForKeys: [.isDirectoryKey],
				options: [.skipsHiddenFiles]
			) else { continue }

			for entry in entries {
				if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
					// `src` is not descended: its package tree is a chain, and
					// walking it here is how the budget was spent for nothing.
					guard !skipped.contains(entry.lastPathComponent),
					      entry.lastPathComponent != "src"
					else { continue }
					queue.append(entry)
					continue
				}
				// A source lying outside any module — a script beside the root. Kept
				// only in case no module turns up at all.
				guard entry.pathExtension == "java" || entry.pathExtension == "kt",
				      !entry.path.contains("/src/test/")
				else { continue }
				if fallback == nil { fallback = FilePath.canonical(entry) }
			}
		}
		return fallback
	}

	/// The shallowest source file under a source root.
	///
	/// Breadth-first, which for a package tree means the file nearest the top of
	/// it. Bounded like everything else here, and it can legitimately find
	/// nothing: a source root holding only test helpers, or only directories, is a
	/// module that cannot anchor anything and the caller moves on to the next one.
	static func firstSourceFile(under root: URL, limit: Int) -> String? {
		let manager = FileManager.default
		var queue = [root]
		var read = 0

		while !queue.isEmpty, read < limit {
			let current = queue.removeFirst()
			read += 1
			guard let entries = try? manager.contentsOfDirectory(
				at: current,
				includingPropertiesForKeys: [.isDirectoryKey],
				options: [.skipsHiddenFiles]
			) else { continue }

			for entry in entries {
				if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
					guard !skipped.contains(entry.lastPathComponent) else { continue }
					queue.append(entry)
					continue
				}
				guard entry.pathExtension == "java" || entry.pathExtension == "kt",
				      !entry.path.contains("/src/test/")
				else { continue }
				return FilePath.canonical(entry)
			}
		}
		return nil
	}

	/// `mainClasses`, off whichever actor is asking, and only once.
	///
	/// **The scan reads every `.java` and `.kt` file in the project** — 13,754 of
	/// them in the repository this was measured on — so on a large checkout it is
	/// seconds at best. Run from the main actor it is a spinning cursor with
	/// nothing on screen to explain it, and the callers that reach for this are
	/// main-actor code arranging a debug session, which is the worst moment to
	/// stop drawing.
	///
	/// Through `MainClassCache`, so that the two callers who want this answer
	/// within seconds of each other — the discovery walk a project open starts,
	/// and a Debug press that needs an anchor — wait on one scan instead of
	/// running two.
	public static func mainClassesOffMain(in root: URL, limit: Int = 40) async -> [MainClass] {
		await MainClassCache.shared.classes(in: root, limit: limit)
	}

	/// Forgets what the last scan of a project found.
	///
	/// Called when the file-system watcher sees a change worth rescanning for: a
	/// cached list of main classes is only as good as the tree it was read from,
	/// and a branch switch invalidates all of it.
	public static func forgetMainClasses(in root: URL) async {
		await MainClassCache.shared.invalidate(root)
	}

	/// Every class in a project that can be run.
	///
	/// A scan of the source rather than a question to the language server: this
	/// has to answer before jdtls has finished importing a large project, which
	/// takes tens of seconds, and the answer barely changes.
	///
	/// Reads every source file in the project, so anything on the main actor
	/// wants `mainClassesOffMain` instead.
	public static func mainClasses(in root: URL, limit: Int = 40) -> [MainClass] {
		var found: [MainClass] = []
		let manager = FileManager.default

		guard let enumerator = manager.enumerator(
			at: root,
			includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
			options: [.skipsHiddenFiles]
		) else { return [] }

		for case let url as URL in enumerator {
			if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
				if skipped.contains(url.lastPathComponent) { enumerator.skipDescendants() }
				continue
			}
			let isKotlin = url.pathExtension == "kt"
			// Test sources hold their own `main` methods now and then, and none of
			// them is what somebody means by running the project.
			guard url.pathExtension == "java" || isKotlin,
			      !url.path.contains("/src/test/"),
			      // Every source file in the project is read, so the one
			      // generated file that is a megabyte of constants does not get
			      // to cost a second on its own.
			      (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0 < 1_000_000,
			      let bytes = try? Data(contentsOf: url),
			      // The cheap question first, and it answers no for almost every
			      // file: one without `main(` in its bytes anywhere cannot hold a
			      // main method, and is never turned into a String at all. See
			      // `contains(_:in:)` for what that is worth.
			      contains(isKotlin ? "fun main" : "main(", in: bytes),
			      let text = String(data: bytes, encoding: .utf8),
			      let line = mainMethodLine(in: text, isKotlin: isKotlin)
			else { continue }

			let type = typeName(of: url, source: text)
			let qualified = [packageName(in: text), type].compactMap { $0 }.joined(separator: ".")
			found.append(MainClass(
				name: qualified,
				file: FilePath.canonical(url),
				line: line,
				module: FilePath.canonical(moduleDirectory(for: url, under: root))
			))
			if found.count >= limit { break }
		}
		return found.sorted { $0.name < $1.name }
	}

	/// The 1-based line of a `main` method, or nil when the file has none.
	///
	/// Text rather than a parse tree, so that this answers for a file with a
	/// syntax error in it too — which, while somebody is typing, is most of
	/// them.
	public static func mainMethodLine(in source: String, isKotlin: Bool = false) -> Int? {
		for (index, raw) in source.components(separatedBy: "\n").enumerated() {
			let line = raw.trimmingCharacters(in: .whitespaces)
			guard !line.hasPrefix("//"), !line.hasPrefix("*") else { continue }

			if isKotlin {
				if line.hasPrefix("fun main(") || line.hasPrefix("fun main (") { return index + 1 }
				continue
			}
			// `public static void main(String[] args)`, in any of the orders the
			// language allows and with any spelling of the parameter type.
			guard line.contains("main("), line.contains("static"), line.contains("void") else { continue }
			guard line.contains("String") else { continue }
			return index + 1
		}
		return nil
	}

	/// Whether a byte sequence appears anywhere in a file's bytes.
	///
	/// **`memmem`, and deliberately nothing from `String`.** This is asked once
	/// per source file in the project, and the Swift spellings of it are what the
	/// scan used to cost. `line.contains("main(")` is a Unicode
	/// canonical-equivalence search, and reaching it at all meant first splitting
	/// the file into a `String` per line: about a million lines and twice as many
	/// allocations for a repository of 13,754 sources, which measured 96–139 s.
	/// The same walk with this in front of it takes 5 s and finds exactly the
	/// same classes, because a file whose bytes do not contain `main(` cannot
	/// have a line that does.
	///
	/// `Data.firstRange(of:)` is not the shortcut it looks like — it is a generic
	/// collection search, and substituting it for this changed nothing
	/// measurable.
	///
	/// A prefilter is only sound if it never rejects a file the real test would
	/// have accepted. Both needles are substrings of what `mainMethodLine` looks
	/// for on a line — `main(` of its own `contains("main(")`, and `fun main` of
	/// both `fun main(` and `fun main (` — so every file this drops is one that
	/// would have been dropped anyway.
	static func contains(_ needle: String, in bytes: Data) -> Bool {
		let pattern = Array(needle.utf8)
		guard !pattern.isEmpty, bytes.count >= pattern.count else { return false }
		return bytes.withUnsafeBytes { haystack in
			guard let start = haystack.baseAddress else { return false }
			return pattern.withUnsafeBytes { sought in
				memmem(start, haystack.count, sought.baseAddress, sought.count) != nil
			}
		}
	}

	/// The `package` a file declares, or nil for the default package.
	public static func packageName(in source: String) -> String? {
		for raw in source.components(separatedBy: "\n") {
			let line = raw.trimmingCharacters(in: .whitespaces)
			guard line.hasPrefix("package ") else { continue }
			let name = line
				.dropFirst("package ".count)
				.prefix { $0 != ";" && $0 != "/" }
				.trimmingCharacters(in: .whitespaces)
			return name.isEmpty ? nil : name
		}
		return nil
	}

	/// The type a file declares, which Java requires to match the file name.
	///
	/// Kotlin does not have that rule: a `main` in `App.kt` outside any class is
	/// compiled into `AppKt`, which is the name the JVM has to be given.
	static func typeName(of url: URL, source: String) -> String {
		let base = url.deletingPathExtension().lastPathComponent
		guard url.pathExtension == "kt" else { return base }
		// A `@file:JvmName` overrides even that.
		for raw in source.components(separatedBy: "\n") {
			let line = raw.trimmingCharacters(in: .whitespaces)
			guard line.hasPrefix("@file:JvmName(") else { continue }
			let name = line.drop { $0 != "\"" }.dropFirst().prefix { $0 != "\"" }
			if !name.isEmpty { return String(name) }
		}
		return base + "Kt"
	}

	/// The module a source file belongs to: the nearest directory above it with
	/// a build file, stopping at the project root.
	static func moduleDirectory(for file: URL, under root: URL) -> URL {
		let rootPath = FilePath.canonical(root)
		var cursor = file.deletingLastPathComponent()
		while FilePath.canonical(cursor).hasPrefix(rootPath) {
			if buildFile(in: cursor) != nil { return cursor }
			let parent = cursor.deletingLastPathComponent()
			if parent.path == cursor.path { break }
			cursor = parent
		}
		return root
	}

	/// The build file a directory holds, if it holds one.
	public static func buildFile(in directory: URL) -> URL? {
		for name in ["pom.xml", "build.gradle.kts", "build.gradle"] {
			let url = directory.appendingPathComponent(name)
			if FileManager.default.fileExists(atPath: url.path) { return url }
		}
		return nil
	}

	/// Whether a directory is the root of a Java project this app understands.
	public static func isJavaProject(_ root: URL) -> Bool {
		buildFile(in: root) != nil
			|| FileManager.default.fileExists(atPath: root.appendingPathComponent("settings.gradle").path)
			|| FileManager.default.fileExists(atPath: root.appendingPathComponent("settings.gradle.kts").path)
	}
}

/// The project scan, run once and shared.
///
/// **Two callers want this answer within seconds of each other.** Opening a
/// project starts a discovery walk, and pressing Debug needs to know which
/// module a launch belongs to; before this they each ran their own scan of the
/// same tree. On a repository where the walk takes a minute that is two minutes
/// of CPU for one answer, and the second walk starts at precisely the moment
/// somebody is sitting waiting for it.
///
/// An actor rather than a lock, because the interesting case is not
/// serialising around a *finished* scan but joining one still running: a second
/// caller awaits the first's task and is handed its result. A lock would have
/// made the second caller wait and then scan anyway, or blocked a cooperative
/// thread for the duration, which is worse than the problem.
actor MainClassCache {
	static let shared = MainClassCache()

	/// The limit is part of the key: a scan that stopped at 40 has not answered
	/// the question a caller asking for 200 is asking.
	private struct Key: Hashable {
		let root: String
		let limit: Int
	}

	private var finished: [Key: [JavaTooling.MainClass]] = [:]
	private var inFlight: [Key: Task<[JavaTooling.MainClass], Never>] = [:]
	/// Bumped by `invalidate`, so a scan can tell whether the tree changed
	/// underneath it while it was walking.
	private var generation: [String: Int] = [:]

	/// How many scans this cache has started, per project.
	///
	/// The only way to tell a second caller that *joined* a scan from one that
	/// quietly ran its own, which is the whole behaviour here and is otherwise
	/// invisible: both spellings return the same list.
	///
	/// Per project rather than one number, because the tests that read it run in
	/// parallel: a single counter is incremented by whichever other test happens
	/// to be scanning its own fixture at the time, and the assertion fails for a
	/// reason that has nothing to do with what it is testing.
	private var scans: [String: Int] = [:]

	func scansStarted(for root: URL) -> Int {
		scans[FilePath.canonical(root)] ?? 0
	}

	func classes(in root: URL, limit: Int) async -> [JavaTooling.MainClass] {
		let path = FilePath.canonical(root)
		let key = Key(root: path, limit: limit)
		if let kept = finished[key] { return kept }
		if let running = inFlight[key] { return await running.value }

		let startedAt = generation[path] ?? 0
		scans[path, default: 0] += 1
		let task = Task.detached { JavaTooling.mainClasses(in: root, limit: limit) }
		inFlight[key] = task
		let found = await task.value
		inFlight[key] = nil

		// A change that arrived while the walk was running makes its answer stale
		// before it can be stored — it saw part of the tree before the change and
		// part after. Still returned, because it is the best answer in existence
		// and whoever asked is waiting for it; just not kept for the next caller.
		if (generation[path] ?? 0) == startedAt { finished[key] = found }
		return found
	}

	/// Forgets a project's scan, and marks any scan now running as stale.
	func invalidate(_ root: URL) {
		let path = FilePath.canonical(root)
		generation[path, default: 0] += 1
		finished = finished.filter { $0.key.root != path }
	}
}
