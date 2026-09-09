import Foundation

/// Building a Go package for a pod.
public enum DevPodBuild {
	public enum Failure: Error, Equatable {
		case noToolchain
		case failed(String)
		case unsupported(String)
	}

	/// How a project is built for the pod.
	///
	/// The pod runs Linux and this machine does not, so something has to
	/// cross-compile. Which something depends on the language, and one of them
	/// — the project's own build — beats every guess this app could make.
	public enum Strategy: Equatable {
		/// The project says how: a make target, given the target system.
		case make(targets: [String], directory: String, artefact: String)
		case go(package: String)
		case zig(directory: String)
		/// Odin's linker cannot make a Linux binary on a Mac, but it will emit
		/// the objects, and zig's linker will take them.
		case odin(directory: String)
		/// C and C++ go through zig, which cross-compiles both and is already
		/// here for Odin's sake.
		case clang(directory: String, isCPlusPlus: Bool)
		/// Rust needs its own standard library for the target, which only
		/// rustup can install.
		case rust(directory: String)
		/// Maven, which builds a jar — and a jar is the same file whatever the
		/// pod's architecture is, so nothing is cross-compiled here.
		case maven(directory: String)
		case gradle(directory: String)
	}

	/// Which debugger has to be in the pod for this project.
	///
	/// Delve debugs Go and nothing else; everything that compiles to a native
	/// binary is held by gdbserver instead. `nil` means this cannot tell — a
	/// make step builds whatever it likes — and the caller should assume it
	/// needs both rather than guess wrong.
	public enum Debugger: Equatable {
		case delve
		case gdbserver
		/// A JVM, which needs no debugger in the pod at all — it *is* one, given
		/// the flag. What the pod needs instead is a Java to run the jar with.
		case jdwp
	}

	public static func debugger(for configuration: LaunchConfiguration, root: URL) -> Debugger? {
		switch strategy(for: configuration, root: root) {
		case .go: return .delve
		case .zig, .odin, .clang, .rust: return .gdbserver
		case .maven, .gradle: return .jdwp
		case .make, nil:
			// Nothing was recognised, so the only evidence left is what the
			// configuration calls itself.
			switch configuration.type {
			case "go": return .delve
			case "lldb", "cppdbg", "codelldb": return .gdbserver
			case "java", "kotlin": return .jdwp
			default: return nil
			}
		}
	}

	/// Works out how to build a configuration for the cluster.
	///
	/// The project's own build first: a Makefile that already cross-compiles
	/// knows things this cannot, and a project in a language nothing here
	/// handles still works if it has one.
	public static func strategy(
		for configuration: LaunchConfiguration,
		root: URL
	) -> Strategy? {
		if let step = configuration.makeStep {
			return .make(
				targets: step.targets,
				directory: step.directory,
				artefact: configuration.program
			)
		}

		let program = configuration.expandedProgram(root: root)
		let directory = URL(fileURLWithPath: program).hasDirectoryPath
			? URL(fileURLWithPath: program)
			: URL(fileURLWithPath: program).deletingLastPathComponent()
		let manager = FileManager.default

		if configuration.type == "go" || manager.fileExists(atPath: root.appendingPathComponent("go.mod").path) {
			return .go(package: program)
		}
		// A Java configuration names a class, so the directory it belongs to is
		// the module holding the build file — worked out from `cwd`, which for a
		// Java configuration is the module, and from the root when it is not.
		let workingDirectory = URL(fileURLWithPath: configuration.expandedWorkingDirectory(root: root))
		for candidate in [workingDirectory, directory, root] {
			if manager.fileExists(atPath: candidate.appendingPathComponent("pom.xml").path) {
				return .maven(directory: candidate.path)
			}
			for name in ["build.gradle.kts", "build.gradle"]
			where manager.fileExists(atPath: candidate.appendingPathComponent(name).path) {
				return .gradle(directory: candidate.path)
			}
		}
		if manager.fileExists(atPath: root.appendingPathComponent("build.zig").path) {
			return .zig(directory: root.path)
		}
		if manager.fileExists(atPath: root.appendingPathComponent("Cargo.toml").path) {
			return .rust(directory: root.path)
		}
		if hasSource(withExtension: "odin", in: directory) || hasSource(withExtension: "odin", in: root) {
			return .odin(directory: directory.path)
		}
		for (ext, isCPlusPlus) in [("cpp", true), ("cc", true), ("cxx", true), ("c", false)]
		where hasSource(withExtension: ext, in: directory) || hasSource(withExtension: ext, in: root) {
			let holder = hasSource(withExtension: ext, in: directory) ? directory : root
			return .clang(directory: holder.path, isCPlusPlus: isCPlusPlus)
		}
		return nil
	}

	/// The sources a whole-directory build compiles.
	///
	/// Everything with that extension in the directory, and in a `src` beside
	/// it: enough for a project small enough not to have a build of its own.
	/// Anything larger says how in a make step.
	public static func sources(withExtension ext: String, in directory: URL) -> [URL] {
		let manager = FileManager.default
		var found: [URL] = []
		for place in [directory, directory.appendingPathComponent("src")] {
			let entries = (try? manager.contentsOfDirectory(atPath: place.path)) ?? []
			found += entries
				.filter { ($0 as NSString).pathExtension == ext }
				.map { place.appendingPathComponent($0) }
		}
		return found.sorted { $0.path < $1.path }
	}

	/// What zig is told, to compile a C or C++ project for the pod.
	///
	/// Pure, so what runs can be read and tested rather than found out by
	/// running it. Unoptimised and with debug information, for the reason the
	/// Go build is: a breakpoint has to land where it was put.
	public static func clangArguments(
		compiler: String,
		sources: [String],
		architecture: String,
		output: String,
		isCPlusPlus: Bool
	) -> [String] {
		var arguments = [compiler, isCPlusPlus ? "c++" : "cc"]
		arguments += ["-target", "\(machine(architecture))-linux-musl"]
		arguments += ["-g", "-O0"]
		if isCPlusPlus { arguments.append("-std=c++20") }
		arguments += sources
		arguments += ["-o", output]
		return arguments
	}

	/// The Rust target triple for an architecture.
	public static func rustTriple(_ architecture: String) -> String {
		"\(machine(architecture))-unknown-linux-musl"
	}

	private static func hasSource(withExtension ext: String, in directory: URL) -> Bool {
		let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
		if contents.contains(where: { ($0 as NSString).pathExtension == ext }) { return true }
		// One level down, since `src/` is where most projects put it.
		for entry in contents {
			let child = directory.appendingPathComponent(entry)
			var isDirectory: ObjCBool = false
			guard FileManager.default.fileExists(atPath: child.path, isDirectory: &isDirectory),
			      isDirectory.boolValue, !entry.hasPrefix(".")
			else { continue }
			let inside = (try? FileManager.default.contentsOfDirectory(atPath: child.path)) ?? []
			if inside.contains(where: { ($0 as NSString).pathExtension == ext }) { return true }
		}
		return false
	}

	/// Builds whatever the configuration is for, for the cluster.
	public static func build(
		configuration: LaunchConfiguration,
		root: URL,
		architecture: String,
		output: URL,
		progress: (@Sendable (String) -> Void)? = nil
	) async throws -> URL {
		guard let strategy = strategy(for: configuration, root: root) else {
			throw Failure.unsupported(
				"""
				Nothing here knows how to build this for linux/\(architecture).

				Go, Zig and Odin are built directly. For anything else, give the \
				configuration a make step that cross-compiles and points at the \
				binary it produces — make is told the target system:

				    ABYDOS_TARGET_OS=linux ABYDOS_TARGET_ARCH=\(architecture)
				"""
			)
		}

		switch strategy {
		case let .make(targets, directory, artefact):
			return try await buildWithMake(
				targets: targets,
				directory: URL(fileURLWithPath: LaunchConfiguration.expand(directory, root: root)),
				artefact: URL(fileURLWithPath: LaunchConfiguration.expand(artefact, root: root)),
				architecture: architecture,
				progress: progress
			)
		case let .go(package):
			return try await buildGo(
				package: package,
				in: URL(fileURLWithPath: package).hasDirectoryPath
					? URL(fileURLWithPath: package)
					: root,
				architecture: architecture,
				output: output
			)
		case let .zig(directory):
			return try await buildZig(
				in: URL(fileURLWithPath: directory),
				architecture: architecture,
				output: output,
				progress: progress
			)
		case let .odin(directory):
			return try await buildOdin(
				in: URL(fileURLWithPath: directory),
				architecture: architecture,
				output: output,
				progress: progress
			)
		case let .clang(directory, isCPlusPlus):
			return try await buildClang(
				in: URL(fileURLWithPath: directory),
				architecture: architecture,
				output: output,
				isCPlusPlus: isCPlusPlus,
				progress: progress
			)
		case let .rust(directory):
			return try await buildRust(
				in: URL(fileURLWithPath: directory),
				architecture: architecture,
				output: output,
				progress: progress
			)
		case let .maven(directory):
			return try await buildMaven(
				in: URL(fileURLWithPath: directory), root: root, progress: progress
			)
		case let .gradle(directory):
			return try await buildGradle(
				in: URL(fileURLWithPath: directory), root: root, progress: progress
			)
		}
	}

	/// Packages a Maven module, and finds the jar it produced.
	///
	/// Nothing is cross-compiled and nothing is told which architecture the pod
	/// is: a jar is bytecode, and the same file runs on the arm64 laptop and the
	/// amd64 node. `-DskipTests` because this is a push into a development pod
	/// and waiting for the suite is not what run means.
	static func buildMaven(
		in directory: URL,
		root: URL,
		progress: (@Sendable (String) -> Void)?
	) async throws -> URL {
		let maven = MavenProject.executable(for: directory, root: root)
		let goals = ["package", "-DskipTests", "-q"]
		progress?("$ \(maven) \(goals.joined(separator: " "))  (in \(directory.lastPathComponent))")

		let result = await ShellEnvironment.run(
			([maven] + goals).map(shellQuoted).joined(separator: " "),
			in: directory,
			environment: javaEnvironment()
		)
		guard result.exitCode == 0 else {
			throw Failure.failed(result.error.isEmpty ? result.output : result.error)
		}

		// A pod is given the jar and nothing else — no local repository, no
		// classpath — so a jar with dependencies outside it starts and dies on
		// its first import. Said before it happens, because the exception that
		// follows names a class rather than the packaging.
		if let project = MavenProject.read(at: directory.appendingPathComponent("pom.xml")),
		   !project.dependencies.isEmpty,
		   !project.isSpringBoot,
		   !project.plugins.contains(where: { $0.contains("shade") || $0.contains("assembly") }) {
			progress?(
				"note: this module has dependencies and builds a plain jar. The pod runs "
					+ "`java -jar` with nothing else on the classpath, so it needs a jar that "
					+ "carries them — the shade or assembly plugin, or Spring Boot's."
			)
		}
		return try jar(in: directory.appendingPathComponent("target"), what: "Maven")
	}

	/// Builds a Gradle module, and finds the jar it produced.
	///
	/// `bootJar` when Spring Boot is there, because its plain `jar` builds
	/// something with no dependencies in it that dies on its first import;
	/// otherwise `assemble`, which is the task every Java build has.
	static func buildGradle(
		in directory: URL,
		root: URL,
		progress: (@Sendable (String) -> Void)?
	) async throws -> URL {
		let gradle = GradleBuild.executable(for: directory, root: root)
		let build = GradleBuild.find(in: directory, maxDepth: 0).first.flatMap(GradleBuild.read(at:))
		let task = build?.isSpringBoot == true ? "bootJar" : "assemble"

		// The wrapper lives at the root of the build and a module is named the
		// way Gradle names it, so this runs where gradlew is.
		let wrapperDirectory = gradle.hasSuffix("gradlew")
			? URL(fileURLWithPath: gradle).deletingLastPathComponent()
			: directory
		let prefix = gradle.hasSuffix("gradlew")
			? RunConfigurationDiscovery.gradlePath(of: directory, under: wrapperDirectory)
			: ""

		progress?("$ \(gradle) \(prefix + task)  (in \(wrapperDirectory.lastPathComponent))")
		let result = await ShellEnvironment.run(
			([gradle, prefix + task, "-x", "test", "--console=plain"]).map(shellQuoted).joined(separator: " "),
			in: wrapperDirectory,
			environment: javaEnvironment()
		)
		guard result.exitCode == 0 else {
			throw Failure.failed(result.error.isEmpty ? result.output : result.error)
		}

		// The same warning Maven's build gives, for the same reason: `assemble`
		// on a plain Java build produces a jar with only this module in it.
		if let build, !build.isSpringBoot,
		   !build.plugins.contains(where: { $0.contains("shadow") }) {
			progress?(
				"note: `assemble` builds a jar holding this module and nothing else. The pod "
					+ "runs it with `java -jar` and no other classpath, so a build with "
					+ "dependencies needs the shadow plugin or Spring Boot's `bootJar`."
			)
		}
		return try jar(in: directory.appendingPathComponent("build/libs"), what: "Gradle")
	}

	/// The jar a build left behind.
	///
	/// The newest, and never a `-sources` or `-javadoc` one: those are built
	/// alongside the real artefact by projects that publish, and pushing one
	/// into a pod produces a JVM complaining about a missing main class.
	static func jar(in directory: URL, what: String) throws -> URL {
		let manager = FileManager.default
		let entries = (try? manager.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
		)) ?? []

		let jars = entries
			.filter { $0.pathExtension == "jar" }
			.filter { !$0.lastPathComponent.hasSuffix("-sources.jar") }
			.filter { !$0.lastPathComponent.hasSuffix("-javadoc.jar") }
			.filter { !$0.lastPathComponent.hasSuffix("-plain.jar") }
			.sorted { left, right in
				let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]))?
					.contentModificationDate ?? .distantPast
				let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]))?
					.contentModificationDate ?? .distantPast
				return leftDate > rightDate
			}

		guard let newest = jars.first else {
			throw Failure.failed(
				"""
				\(what) reported success but left no jar in \(directory.path).

				A module that builds a library rather than an application produces \
				nothing runnable. Point the configuration at the module that does, \
				or give the build a task that assembles one.
				"""
			)
		}
		return newest
	}

	/// A build's environment, with a JDK in it.
	///
	/// The same problem the language servers have: a GUI app has no login
	/// shell, so `mvnw` starts and then cannot find a `java` to run Maven with.
	static func javaEnvironment() -> [String: String] {
		guard let home = JavaTooling.javaHome() else { return [:] }
		return ["JAVA_HOME": home, "PATH": "\(home)/bin:" + Executables.searchPaths.joined(separator: ":")]
	}

	/// Cross-compiles a Go package, keeping what a debugger needs.
	///
	/// Static, because the image the pod runs has no libc in it; unoptimised
	/// and un-inlined, because otherwise a breakpoint lands on a line the
	/// compiler moved and a variable reads `<optimized out>`.
	public static func build(
		package: String,
		in directory: URL,
		architecture: String,
		output: URL
	) async throws -> URL {
		try await buildGo(
			package: package, in: directory, architecture: architecture, output: output
		)
	}

	private static func buildGo(
		package: String,
		in directory: URL,
		architecture: String,
		output: URL
	) async throws -> URL {
		guard let go = GoTooling.findGoExecutable() else { throw Failure.noToolchain }

		let result = await ShellEnvironment.run(
			[
				shellQuoted(go), "build",
				"-gcflags", "'all=-N -l'",
				"-o", shellQuoted(output.path),
				shellQuoted(package),
			].joined(separator: " "),
			in: directory,
			environment: [
				"GOOS": "linux",
				"GOARCH": architecture,
				"CGO_ENABLED": "0",
			]
		)
		guard result.exitCode == 0 else {
			throw Failure.failed(result.error.isEmpty ? result.output : result.error)
		}
		return output
	}

	/// Runs the project's own build, told what it is building for.
	private static func buildWithMake(
		targets: [String],
		directory: URL,
		artefact: URL,
		architecture: String,
		progress: (@Sendable (String) -> Void)?
	) async throws -> URL {
		let command = (["make"] + targets).map(shellQuoted).joined(separator: " ")
		progress?("$ " + command + "  (in \(directory.lastPathComponent))")

		let result = await ShellEnvironment.run(
			command,
			in: directory,
			environment: [
				// What the project needs in order to cross-compile, in the
				// terms each toolchain uses.
				"ABYDOS_TARGET_OS": "linux",
				"ABYDOS_TARGET_ARCH": architecture,
				"GOOS": "linux",
				"GOARCH": architecture,
				"CGO_ENABLED": "0",
			]
		)
		guard result.exitCode == 0 else {
			throw Failure.failed(result.error.isEmpty ? result.output : result.error)
		}
		guard FileManager.default.fileExists(atPath: artefact.path) else {
			throw Failure.failed(
				"The build finished but \(artefact.path) is not there. "
					+ "The configuration's program is what gets pushed into the pod, so it has "
					+ "to be the binary the build produces."
			)
		}
		return artefact
	}

	/// Zig cross-compiles out of the box, which is most of why it is here.
	private static func buildZig(
		in directory: URL,
		architecture: String,
		output: URL,
		progress: (@Sendable (String) -> Void)?
	) async throws -> URL {
		guard let zig = tool("zig") else {
			throw Failure.unsupported("This looks like a Zig project, but `zig` is not installed.")
		}
		let triple = "\(machine(architecture))-linux-musl"
		progress?("$ zig build -Dtarget=\(triple)")

		let result = await ShellEnvironment.run(
			[shellQuoted(zig), "build", "-Dtarget=" + triple].joined(separator: " "),
			in: directory
		)
		guard result.exitCode == 0 else {
			throw Failure.failed(result.error.isEmpty ? result.output : result.error)
		}

		// Whatever it put in zig-out/bin, which is where `zig build` installs.
		let binaries = directory.appendingPathComponent("zig-out/bin")
		let produced = ((try? FileManager.default.contentsOfDirectory(atPath: binaries.path)) ?? [])
			.map { binaries.appendingPathComponent($0) }
		guard let binary = produced.first else {
			throw Failure.failed("zig build produced nothing in zig-out/bin.")
		}
		try? FileManager.default.removeItem(at: output)
		try FileManager.default.copyItem(at: binary, to: output)
		return output
	}

	/// Odin, in two steps.
	///
	/// Its own linker refuses to make a Linux binary on a Mac — "linking for
	/// cross compilation for this platform is not yet supported" — but it will
	/// emit the objects, and zig ships a linker that takes them.
	private static func buildOdin(
		in directory: URL,
		architecture: String,
		output: URL,
		progress: (@Sendable (String) -> Void)?
	) async throws -> URL {
		guard let odin = tool("odin") else {
			throw Failure.unsupported("This looks like an Odin project, but `odin` is not installed.")
		}
		guard let zig = tool("zig") else {
			throw Failure.unsupported(
				"""
				Odin's linker cannot make a Linux binary on a Mac, so zig's is used instead — \
				and `zig` is not installed.

				    brew install zig
				"""
			)
		}

		let objects = output.deletingLastPathComponent()
			.appendingPathComponent(output.lastPathComponent + "-objects")
		try? FileManager.default.removeItem(at: objects)
		try FileManager.default.createDirectory(at: objects, withIntermediateDirectories: true)

		let source = FileManager.default.fileExists(atPath: directory.appendingPathComponent("src").path)
			? directory.appendingPathComponent("src")
			: directory
		let target = "linux_\(architecture == "arm64" ? "arm64" : "amd64")"
		progress?("$ odin build \(source.lastPathComponent) -build-mode:obj -target:\(target)")

		let compiled = await ShellEnvironment.run(
			[
				shellQuoted(odin), "build", shellQuoted(source.path),
				"-build-mode:obj", "-debug",
				"-out:" + shellQuoted(objects.appendingPathComponent("out").path),
				"-target:" + target,
			].joined(separator: " "),
			in: directory
		)
		guard compiled.exitCode == 0 else {
			throw Failure.failed(compiled.error.isEmpty ? compiled.output : compiled.error)
		}

		let produced = ((try? FileManager.default.contentsOfDirectory(atPath: objects.path)) ?? [])
			.filter { $0.hasSuffix(".obj") || $0.hasSuffix(".o") }
			.sorted()
		guard !produced.isEmpty else {
			throw Failure.failed("Odin produced no object files to link.")
		}

		let triple = "\(machine(architecture))-linux-musl"
		progress?("$ zig cc -target \(triple) \(produced.count) objects")
		let linked = await ShellEnvironment.run(
			([shellQuoted(zig), "cc", "-target", triple]
				+ produced.map { shellQuoted(objects.appendingPathComponent($0).path) }
				+ ["-o", shellQuoted(output.path)]).joined(separator: " "),
			in: directory
		)
		guard linked.exitCode == 0 else {
			throw Failure.failed(linked.error.isEmpty ? linked.output : linked.error)
		}
		try? FileManager.default.removeItem(at: objects)
		return output
	}

	/// C and C++, through zig — a cross compiler for both, already here for
	/// Odin's sake.
	private static func buildClang(
		in directory: URL,
		architecture: String,
		output: URL,
		isCPlusPlus: Bool,
		progress: (@Sendable (String) -> Void)?
	) async throws -> URL {
		guard let zig = tool("zig") else {
			throw Failure.unsupported(
				"Building C for Linux on a Mac needs a cross compiler, and zig is the one "
					+ "this uses:\n\n    brew install zig"
			)
		}

		var files: [URL] = []
		for ext in isCPlusPlus ? ["cpp", "cc", "cxx"] : ["c"] {
			files += sources(withExtension: ext, in: directory)
		}
		guard !files.isEmpty else {
			throw Failure.failed("No sources to compile in \(directory.path).")
		}

		let arguments = clangArguments(
			compiler: zig,
			sources: files.map(\.path),
			architecture: architecture,
			output: output.path,
			isCPlusPlus: isCPlusPlus
		)
		progress?(
			"$ zig \(isCPlusPlus ? "c++" : "cc") -target \(machine(architecture))-linux-musl "
				+ "\(files.count) source\(files.count == 1 ? "" : "s")"
		)

		let result = await ShellEnvironment.run(
			arguments.map(shellQuoted).joined(separator: " "),
			in: directory
		)
		guard result.exitCode == 0 else {
			throw Failure.failed(result.error.isEmpty ? result.output : result.error)
		}
		return output
	}

	/// Rust, which needs its standard library for the target.
	///
	/// Only rustup can put that there, so when it is missing this says which
	/// command to run rather than failing with a page of linker errors.
	private static func buildRust(
		in directory: URL,
		architecture: String,
		output: URL,
		progress: (@Sendable (String) -> Void)?
	) async throws -> URL {
		guard let cargo = tool("cargo") else {
			throw Failure.unsupported("This looks like a Rust project, but `cargo` is not installed.")
		}
		let triple = rustTriple(architecture)

		let installed = await ShellEnvironment.run("rustup target list --installed", in: directory)
		guard installed.output.contains(triple) else {
			throw Failure.unsupported(
				"Rust needs its standard library for the target, and \(triple) is not "
					+ "installed:\n\n    rustup target add \(triple)\n\n"
					+ "zig links it, so nothing else is needed."
			)
		}
		guard let zig = tool("zig") else {
			throw Failure.unsupported(
				"Linking Rust for Linux on a Mac needs zig's linker: brew install zig"
			)
		}

		// cargo takes one word as the linker, so the target and the compiler go
		// into a script it can run.
		let wrapper = output.deletingLastPathComponent()
			.appendingPathComponent("ideai-\(triple)-linker.sh")
		// zig's own spelling, not cargo's: cargo says
		// aarch64-unknown-linux-musl and zig says aarch64-linux-musl, and zig
		// rejects the other one with "UnknownOperatingSystem".
		try "#!/bin/sh\nexec \(zig) cc -target \(machine(architecture))-linux-musl \"$@\"\n"
			.write(to: wrapper, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755], ofItemAtPath: wrapper.path
		)

		let variable = "CARGO_TARGET_"
			+ triple.uppercased().replacingOccurrences(of: "-", with: "_") + "_LINKER"
		progress?("$ cargo build --target \(triple)")

		let result = await ShellEnvironment.run(
			[shellQuoted(cargo), "build", "--target", triple].joined(separator: " "),
			in: directory,
			environment: [
				variable: wrapper.path,
				// Rust ships musl's startup files and so does zig, and the
				// linker will not take both — "duplicate symbol: _start".
				// zig's are the ones that match the linker doing the work.
				"RUSTFLAGS": "-C link-self-contained=no",
			]
		)
		guard result.exitCode == 0 else {
			throw Failure.failed(result.error.isEmpty ? result.output : result.error)
		}

		// A regular file, not `build/` or `deps/`: a directory is executable as
		// far as the file manager is concerned, and copying one where a binary
		// should be produced a push that could not open its own file.
		let binaries = directory.appendingPathComponent("target/\(triple)/debug")
		let produced = ((try? FileManager.default.contentsOfDirectory(atPath: binaries.path)) ?? [])
			.filter { !$0.hasPrefix(".") && !$0.contains(".") }
			.map { binaries.appendingPathComponent($0) }
			.filter { url in
				(try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
					&& FileManager.default.isExecutableFile(atPath: url.path)
			}
		guard let binary = produced.first else {
			throw Failure.failed("cargo built nothing runnable in \(binaries.path).")
		}
		try? FileManager.default.removeItem(at: output)
		try FileManager.default.copyItem(at: binary, to: output)
		return output
	}

	/// `arm64` as a compiler spells it.
	static func machine(_ architecture: String) -> String {
		architecture == "arm64" ? "aarch64" : "x86_64"
	}

	private static func tool(_ name: String) -> String? { Executables.locate(name) }

	private static func shellQuoted(_ word: String) -> String {
		guard word.contains(where: { !$0.isLetter && !$0.isNumber && !"-_./=:@".contains($0) })
		else { return word }
		return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}
}
