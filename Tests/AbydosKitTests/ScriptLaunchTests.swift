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

	/// **The poll must not spend the JVM's handshake.** A `connect` that closes
	/// without sending `JDWP-Handshake` makes the JVM give up on the session —
	///
	///     Debugger failed to attach: handshake failed - connection prematurally closed
	///
	/// — and the debugger that arrives next is refused, leaving a suspended JVM
	/// waiting for one that can never come. Polling five times a second, the
	/// probe was always the first thing to reach the port, so this was not a rare
	/// race: it broke every launch it was watching.
	@Test func pollingAPortDoesNotSpendTheJVMsHandshake() async throws {
		let java = URL(fileURLWithPath: "/usr/bin/java")
		try #require(FileManager.default.isExecutableFile(atPath: java.path))

		let port = try #require(DebugPort.free())
		let process = Process()
		process.executableURL = java
		process.arguments = [ScriptLaunch.jdwpOption(port: port), "-version"]
		process.standardOutput = Pipe()
		process.standardError = Pipe()
		try process.run()
		defer { if process.isRunning { process.terminate() } }

		// Watched the way a launch watches it: repeatedly, and first.
		#expect(await DebugPort.waitUntilOpen(port, timeout: 30))
		for _ in 0 ..< 10 { _ = DebugPort.isOpen(port) }

		// And a real debugger can still attach, which is what the old probe
		// destroyed before anything else got the chance to try.
		#expect(jdwpHandshakeSucceeds(onPort: port), "the JVM should still take a debugger")
	}

	/// A real JDWP handshake: those fourteen bytes, and the same fourteen back.
	///
	/// Written out rather than mocked because the claim is about what a JVM does
	/// with the socket, and nothing but the socket can settle it.
	private func jdwpHandshakeSucceeds(onPort port: Int) -> Bool {
		let descriptor = socket(AF_INET, SOCK_STREAM, 0)
		guard descriptor >= 0 else { return false }
		defer { close(descriptor) }

		// A read timeout, so a JVM that says nothing fails the test rather than
		// hanging the suite.
		var limit = timeval(tv_sec: 5, tv_usec: 0)
		setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))

		var address = sockaddr_in()
		address.sin_family = sa_family_t(AF_INET)
		address.sin_addr.s_addr = inet_addr("127.0.0.1")
		address.sin_port = in_port_t(UInt16(port).bigEndian)

		let connected = withUnsafePointer(to: &address) { pointer in
			pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
			}
		}
		guard connected == 0 else { return false }

		let greeting = Array("JDWP-Handshake".utf8)
		// Qualified: this type has a `write(_:named:)` of its own.
		guard Darwin.write(descriptor, greeting, greeting.count) == greeting.count else { return false }

		// `expected` in a local: reading `reply.count` inside a mutable-bytes
		// closure is an overlapping access to `reply`.
		let expected = greeting.count
		var reply = [UInt8](repeating: 0, count: expected)
		var filled = 0
		while filled < expected {
			let got = reply.withUnsafeMutableBytes { buffer -> Int in
				Darwin.read(descriptor, buffer.baseAddress!.advanced(by: filled), expected - filled)
			}
			guard got > 0 else { return false }
			filled += got
		}
		return reply == greeting
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

	// MARK: - Not asking for two debug agents

	/// A JVM refuses to start with two JDWP agents on it: `Cannot load this JVM
	/// TI agent twice`, then `agent library failed Agent_OnLoad: jdwp`, out of VM
	/// initialisation with exit code 1 and before a line of the program runs.
	///
	/// A configuration that carries its own option in `MAVEN_OPTS` is a normal
	/// thing to have — `mvnw`'s own header comment suggests exactly that — so
	/// appending to it blindly turned pressing Debug into a JVM that could not
	/// start, with nothing in the failure naming the option that had just been
	/// added.
	@Test func aDebugAgentAlreadyInTheOptionsIsDisplacedRatherThanStacked() {
		let existing = "-Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=8000 -Xmx8G"
		let plan = ScriptLaunch.plan(
			kind: .maven, port: 41234, environment: ["MAVEN_OPTS": existing], arguments: ["test"]
		)

		let options = plan.environment["MAVEN_OPTS"] ?? ""
		#expect(!options.contains("-Xrunjdwp"), "the old agent has to be gone, not merely followed")
		#expect(options.contains("address=127.0.0.1:41234"), "ours is the port the adapter wants")
		// Exactly one, counted rather than eyeballed: this is the whole bug.
		#expect(options.components(separatedBy: "-agentlib:jdwp").count - 1 == 1)
		// Everything that was not an agent survives — a lost -Xmx8G is a build
		// that dies differently.
		#expect(options.contains("-Xmx8G"))
	}

	/// The same for an unrecognised script, which is asked through
	/// `JAVA_TOOL_OPTIONS` — and where the variable more often already has
	/// something in it that matters.
	@Test func javaToolOptionsKeepsWhatIsNotAnAgent() {
		let existing = "-Djavax.net.ssl.trustStore=/Users/someone/cacerts -agentlib:jdwp=address=1"
		let plan = ScriptLaunch.plan(
			kind: .script, port: 5150, environment: ["JAVA_TOOL_OPTIONS": existing], arguments: []
		)

		let options = plan.environment["JAVA_TOOL_OPTIONS"] ?? ""
		#expect(options.contains("-Djavax.net.ssl.trustStore=/Users/someone/cacerts"))
		#expect(options.components(separatedBy: "-agentlib:jdwp").count - 1 == 1)
		#expect(options.contains("address=127.0.0.1:5150"))
	}

	/// Displacing somebody's option silently would be worse than stacking it:
	/// the variable is in the environment rather than in the command the run
	/// pane shows, so the plan's note is the only place it can be said.
	@Test func displacingAnAgentIsSaidInTheNote() {
		let plan = ScriptLaunch.plan(
			kind: .maven,
			port: 41234,
			environment: ["MAVEN_OPTS": "-Xrunjdwp:address=8000"],
			arguments: []
		)
		#expect(plan.note.contains("-Xrunjdwp:address=8000"))
		#expect(plan.note.contains("will not start with two"))
	}

	/// And nothing is said when there was nothing to displace.
	@Test func anUntouchedNoteSaysNothingAboutDisplacement() {
		let plan = ScriptLaunch.plan(kind: .maven, port: 41234, environment: [:], arguments: [])
		#expect(!plan.note.contains("taken out"))
	}

	// MARK: - Where the waiting happens

	/// **The poll must not run on the main thread.** It blocks for up to a
	/// quarter of a second per probe and keeps that up for two minutes, so a
	/// wait that inherited the window's actor would freeze the project for the
	/// whole launch — which is exactly what a launch that has already failed
	/// used to do, since nothing was going to open the port.
	///
	/// Asserted about the probe rather than about the UI, because the probe is
	/// the part that blocks and the only part a test can hold still.
	@MainActor
	@Test func theProbeNeverRunsOnTheMainThread() async {
		let seen = ThreadWitness()
		let opened = await DebugPort.waitUntilOpen(
			1, timeout: 0.3, interval: 0.1, isOpen: { _ in seen.record(); return false }
		)

		#expect(!opened)
		#expect(seen.probes > 0, "the test proves nothing if it never probed")
		#expect(seen.onMain == 0, "\(seen.onMain) of \(seen.probes) probes blocked the main thread")
	}
}

/// Which thread the probes ran on, countable from another one.
private final class ThreadWitness: @unchecked Sendable {
	private let lock = NSLock()
	private var total = 0
	private var main = 0

	func record() {
		let isMain = Thread.isMainThread
		lock.lock()
		defer { lock.unlock() }
		total += 1
		if isMain { main += 1 }
	}

	var probes: Int { lock.withLock { total } }
	var onMain: Int { lock.withLock { main } }
}
