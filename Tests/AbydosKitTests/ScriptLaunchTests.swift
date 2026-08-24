import Testing
import Foundation
@testable import AbydosKit

/// Launching a program that is a script.
///
/// A launch configuration pointing at `./mvnw` used to reach lldb-dap, which
/// answered `'/…/mvnw' is not a valid executable` — a true sentence about the
/// wrong program. A shell script has nothing in it for a native debugger; what
/// has to be debugged is the JVM it eventually starts.
struct ScriptLaunchTests {
	private func write(_ contents: String, named name: String) throws -> URL {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-script-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let file = directory.appendingPathComponent(name)
		try contents.write(to: file, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755], ofItemAtPath: file.path
		)
		return file
	}

	// MARK: - Telling a script from a binary

	/// By the two bytes at the front, not by the name. `mvnw` has no extension,
	/// plenty of scripts are called `run`, and a renamed binary would lie.
	@Test func aScriptIsRecognisedByItsShebangAndNotItsName() throws {
		let wrapper = try write("#!/bin/sh\necho hi\n", named: "mvnw")
		defer { try? FileManager.default.removeItem(at: wrapper.deletingLastPathComponent()) }

		#expect(ScriptLaunch.isScript(at: wrapper.path))
		#expect(ScriptLaunch.kind(ofProgramAt: wrapper.path) == .maven)
	}

	@Test func aBinaryIsNotAScriptHoweverItIsNamed() throws {
		// A real Mach-O, so this is not a test about made-up bytes.
		#expect(!ScriptLaunch.isScript(at: "/bin/sh"))
		#expect(ScriptLaunch.kind(ofProgramAt: "/bin/sh") == nil)
	}

	/// A file called `mvnw` that is somehow not a script is not treated as one:
	/// the name is never the deciding fact.
	@Test func aNamedWrapperThatIsNotAScriptIsNotOne() throws {
		let notAScript = try write("PK\u{3}\u{4}not a script\n", named: "mvnw")
		defer { try? FileManager.default.removeItem(at: notAScript.deletingLastPathComponent()) }

		#expect(ScriptLaunch.kind(ofProgramAt: notAScript.path) == nil)
	}

	@Test func missingFilesAreNotScripts() {
		#expect(!ScriptLaunch.isScript(at: "/nowhere/at/all/mvnw"))
		#expect(ScriptLaunch.kind(ofProgramAt: "/nowhere/at/all/mvnw") == nil)
	}

	@Test func theWrappersAreRecognisedByName() throws {
		for (name, expected) in [
			("mvnw", ScriptLaunch.Kind.maven),
			("mvn", .maven),
			("gradlew", .gradle),
			("gradle", .gradle),
			("run.sh", .script),
			("start", .script),
		] {
			let file = try write("#!/bin/sh\n", named: name)
			defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
			#expect(ScriptLaunch.kind(ofProgramAt: file.path) == expected, "\(name)")
		}
	}

	// MARK: - What each kind is asked for

	/// Maven runs its plugins in its own JVM, and `MAVEN_OPTS` is what reaches
	/// it.
	@Test func mavenIsAskedThroughItsOwnOptions() {
		let plan = ScriptLaunch.plan(kind: .maven, port: 41234, environment: [:], arguments: ["test"])

		#expect(plan.port == 41234)
		#expect(plan.arguments == ["test"], "Maven needs no extra arguments")
		let options = plan.environment["MAVEN_OPTS"] ?? ""
		#expect(options.contains("-agentlib:jdwp="))
		#expect(options.contains("address=127.0.0.1:41234"))
		#expect(options.contains("suspend=y"))
	}

	/// **Not** through the environment. `GRADLE_OPTS` reaches the daemon, which
	/// is not where any of the project's code runs — suspending it hangs the
	/// build with the debugger attached to the wrong JVM.
	@Test func gradleIsAskedThroughTheTaskAndNotTheEnvironment() {
		let plan = ScriptLaunch.plan(kind: .gradle, port: 41234, environment: [:], arguments: ["run"])

		#expect(plan.arguments == ["run", "--debug-jvm"])
		#expect(plan.environment["GRADLE_OPTS"] == nil)
		#expect(plan.environment["JAVA_TOOL_OPTIONS"] == nil)
		// Gradle's own port, because Gradle takes no argument for it. Asking the
		// kernel for a free one and telling Gradle about it is not possible, so
		// the number here has to be the number Gradle will really use.
		#expect(plan.port == ScriptLaunch.gradleDebugPort)
	}

	/// Any JVM started under `JAVA_TOOL_OPTIONS` honours it, which is the only
	/// thing that can be said about a script nobody recognises.
	@Test func anUnknownScriptIsAskedThroughTheUniversalVariable() {
		let plan = ScriptLaunch.plan(kind: .script, port: 5555, environment: [:], arguments: [])

		#expect(plan.environment["JAVA_TOOL_OPTIONS"]?.contains("address=127.0.0.1:5555") == true)
		#expect(plan.arguments.isEmpty)
	}

	/// The port is bound to loopback and not to every interface.
	///
	/// The bare `address=<port>` form that JDK 8 accepted listens on all of them,
	/// which puts an unauthenticated port that runs arbitrary code on whatever
	/// network the machine is on.
	@Test func theDebugPortIsBoundToLoopbackOnly() {
		let option = ScriptLaunch.jdwpOption(port: 6006)
		#expect(option.contains("address=127.0.0.1:6006"))
		#expect(!option.contains("address=6006"))
	}

	// MARK: - Not trampling what is already set

	/// This is not hypothetical: a machine here carries a `JAVA_TOOL_OPTIONS`
	/// naming a trust store, and a build that lost it fails to reach an internal
	/// repository — with nothing in the failure to connect it back to the
	/// debugger.
	@Test func anExistingOptionsVariableIsAddedToRatherThanReplaced() {
		let existing = ["JAVA_TOOL_OPTIONS": "-Djavax.net.ssl.trustStore=/Users/x/cacerts"]
		let plan = ScriptLaunch.plan(kind: .script, port: 7007, environment: existing, arguments: [])

		let options = plan.environment["JAVA_TOOL_OPTIONS"] ?? ""
		#expect(options.contains("-Djavax.net.ssl.trustStore=/Users/x/cacerts"))
		#expect(options.contains("address=127.0.0.1:7007"))
	}

	@Test func theRestOfTheEnvironmentIsCarriedThrough() {
		let plan = ScriptLaunch.plan(
			kind: .maven, port: 1, environment: ["PATH": "/usr/bin", "TERM": "xterm"], arguments: []
		)
		#expect(plan.environment["PATH"] == "/usr/bin")
		#expect(plan.environment["TERM"] == "xterm")
	}

	// MARK: - The port

	@Test func aFreePortIsFoundAndIsNotOpen() throws {
		let port = try #require(DebugPort.free())
		#expect(port > 0)
		#expect(!DebugPort.isOpen(port), "a port just released should have nothing on it")
	}

	@Test func aListeningPortIsSeenAsOpen() async throws {
		let listener = try TinyListener()
		defer { listener.stop() }

		#expect(DebugPort.isOpen(listener.port))
		#expect(await DebugPort.waitUntilOpen(listener.port, timeout: 2))
	}

	/// The wait gives up rather than hanging, and says so by returning false.
	@Test func waitingGivesUpOnAPortNothingOpens() async throws {
		let port = try #require(DebugPort.free())
		#expect(!(await DebugPort.waitUntilOpen(port, timeout: 0.4, interval: 0.1)))
	}

	/// It polls rather than asking once, because a JVM under Maven or Gradle
	/// does not open its port until the build has resolved and compiled.
	@Test func waitingKeepsAskingUntilThePortAppears() async {
		let answers = Answers(openFrom: 3)
		let opened = await DebugPort.waitUntilOpen(
			1234, timeout: 5, interval: 0.01, isOpen: { _ in answers.next() }
		)
		#expect(opened)
		#expect(answers.asked >= 3, "it has to have asked more than once")
	}

	/// A real JVM, told the real option, opens the real port — the one claim in
	/// here that nothing but a JVM can settle.
	@Test func aJVMToldToWaitOpensThePortForReal() async throws {
		let java = URL(fileURLWithPath: "/usr/bin/java")
		try #require(FileManager.default.isExecutableFile(atPath: java.path))

		let port = try #require(DebugPort.free())
		let process = Process()
		process.executableURL = java
		// `-version` is enough: the agent binds and suspends before the JVM gets
		// as far as doing anything, which is the whole point of `suspend=y`.
		process.arguments = [ScriptLaunch.jdwpOption(port: port), "-version"]
		process.standardOutput = Pipe()
		process.standardError = Pipe()
		try process.run()
		defer { if process.isRunning { process.terminate() } }

		#expect(
			await DebugPort.waitUntilOpen(port, timeout: 30),
			"a JVM given \(ScriptLaunch.jdwpOption(port: port)) has to be listening on \(port)"
		)
	}

	// MARK: - Helpers

	/// Counts the asks and starts answering yes at a given one.
	private final class Answers: @unchecked Sendable {
		private let lock = NSLock()
		private let openFrom: Int
		private var count = 0

		init(openFrom: Int) { self.openFrom = openFrom }

		var asked: Int { lock.withLock { count } }

		func next() -> Bool {
			lock.withLock {
				count += 1
				return count >= openFrom
			}
		}
	}

	/// A socket that listens and accepts nothing, which is all `isOpen` asks of
	/// it — a JVM suspended on JDWP looks the same from the outside.
	private final class TinyListener {
		let port: Int
		private let descriptor: Int32

		init() throws {
			// Everything through locals, and the properties assigned at the end:
			// a closure that mentions `self.descriptor` before `port` is set does
			// not compile.
			let fileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
			guard fileDescriptor >= 0 else { throw Failure.noSocket }

			var reuse: Int32 = 1
			setsockopt(
				fileDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuse,
				socklen_t(MemoryLayout<Int32>.size)
			)

			var address = sockaddr_in()
			address.sin_family = sa_family_t(AF_INET)
			address.sin_addr.s_addr = inet_addr("127.0.0.1")
			address.sin_port = 0

			let bound = withUnsafePointer(to: &address) { pointer in
				pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
					bind(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
				}
			}
			// A backlog deep enough to absorb the probes: nothing here ever
			// accepts, and `isOpen` connects each time it asks. With a backlog of
			// one, the second probe met a full queue — which is how the blocking
			// `connect` in `DebugPort.isOpen` was found.
			guard bound == 0, listen(fileDescriptor, 16) == 0 else {
				close(fileDescriptor)
				throw Failure.noSocket
			}

			var assigned = sockaddr_in()
			var length = socklen_t(MemoryLayout<sockaddr_in>.size)
			_ = withUnsafeMutablePointer(to: &assigned) { pointer in
				pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
					getsockname(fileDescriptor, $0, &length)
				}
			}

			descriptor = fileDescriptor
			port = Int(UInt16(bigEndian: assigned.sin_port))
		}

		func stop() { close(descriptor) }

		enum Failure: Error { case noSocket }
	}
}

/// What the launch-configuration editor says about a script before it is run.
struct ScriptLaunchCheckTests {
	private let root = URL(fileURLWithPath: "/p")

	private func problems(
		program: String, kind: ScriptLaunch.Kind?
	) -> [LaunchConfigurationCheck.Problem] {
		LaunchConfigurationCheck.problems(
			for: LaunchConfiguration(name: "run", type: "go", program: program),
			root: root,
			fileExists: { _ in true },
			scriptKind: { _ in kind }
		)
	}

	/// The message LLDB used to give was about the wrong program. This one names
	/// what will actually happen.
	@Test func aMavenWrapperIsExplainedRatherThanRefused() {
		let found = problems(program: "mvnw", kind: .maven)
		let note = found.first { $0.field == "program" }
		#expect(note != nil)
		#expect(note?.message.contains("JVM Maven starts") == true)
	}

	/// Gradle's fixed port is worth knowing before pressing play, not after two
	/// launches have collided on it.
	@Test func gradlesFixedPortIsSaidUpFront() {
		let found = problems(program: "gradlew", kind: .gradle)
		let note = found.first { $0.field == "program" }
		#expect(note?.fix?.contains("\(ScriptLaunch.gradleDebugPort)") == true)
	}

	@Test func anUnknownScriptIsToldItHasNoNativeDebugger() {
		let found = problems(program: "start.sh", kind: .script)
		#expect(found.contains { $0.message.contains("no native debugger") })
	}

	/// And a binary gets none of this.
	@Test func aBinarySaysNothingAboutScripts() {
		let found = problems(program: "build/app", kind: nil)
		#expect(!found.contains { $0.message.contains("script") })
	}
}
