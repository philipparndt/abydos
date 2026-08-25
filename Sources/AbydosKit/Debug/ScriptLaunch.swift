import Foundation

/// Debugging a program that is a script rather than an executable.
///
/// A launch configuration whose `program` is `./mvnw` used to be handed to
/// lldb-dap, because `LaunchConfiguration.adapterID` answered `lldb` for
/// anything it did not recognise. LLDB then said
///
///     '/Users/…/mvnw' is not a valid executable
///
/// which is true, unhelpful, and comes from a program that was never going to be
/// able to help: a shell script is not a Mach-O binary and there is nothing in
/// it for a native debugger to put a breakpoint on.
///
/// What somebody pointing a launch configuration at `mvnw` wants is not to debug
/// the shell. It is to stop on a breakpoint in the Java the wrapper eventually
/// starts. That is arranged the same way it is for a JVM in a pod, which this
/// app already does: ask the JVM to open a JDWP port and wait, then attach the
/// adapter that lives inside the language server, so the sources it shows are
/// the ones on this disk.
///
/// The only part that differs per wrapper is *how you ask*, and the three ways
/// are not interchangeable — see `Kind`.
public enum ScriptLaunch {
	/// What kind of script this is, which decides how the JVM it starts is asked
	/// to wait for a debugger.
	public enum Kind: String, Equatable, Sendable, CaseIterable {
		/// `mvnw`, `mvnw.cmd` or `mvn`.
		///
		/// `MAVEN_OPTS` reaches the JVM Maven itself runs in, and for most goals
		/// — `test`, `exec:java`, an unforked `spring-boot:run` — that is the JVM
		/// the project's code runs in too. A forked goal starts a second JVM that
		/// does not inherit it, and for those the goal's own debug option is the
		/// only lever; `argLine` for Surefire, `jvmArguments` for Spring Boot.
		case maven

		/// `gradlew` or `gradle`.
		///
		/// **Not through the environment.** `GRADLE_OPTS` reaches the Gradle
		/// *daemon*, a long-lived process that compiles the build and is not
		/// where any of the project's code runs — asking it to suspend at its
		/// first instruction hangs the build before it starts, with the debugger
		/// attached to the wrong JVM.
		///
		/// `--debug-jvm` is the lever that belongs to the task: on a `JavaExec`
		/// or `Test` task it makes the JVM Gradle *forks* wait for a debugger.
		/// Its port is Gradle's own default and there is no command-line flag for
		/// it, which is why this is the one kind that does not get a port of its
		/// own — see `gradleDebugPort`.
		case gradle

		/// Any other script with a `#!` line.
		///
		/// `JAVA_TOOL_OPTIONS` is honoured by every JVM that starts under it,
		/// whatever launches it, which is the only thing that can be said about a
		/// script nobody recognises. The cost is that it reaches *every* JVM the
		/// script starts, so a script that runs two of them has the second fail
		/// to bind the port.
		case script
	}

	/// The port `--debug-jvm` listens on.
	///
	/// Gradle's documented default, and hard-coded because Gradle does not take
	/// it from the command line: `org.gradle.debug.port` configures debugging the
	/// *daemon*, not the forked JVM that `--debug-jvm` opens. Asking the kernel
	/// for a free port and then telling Gradle about it is not possible, so the
	/// honest thing is to use the number Gradle will actually use and to fail
	/// loudly if something else has it.
	public static let gradleDebugPort = 5005

	/// Whether a file is a script, by reading it rather than by its name.
	///
	/// The name says nothing worth trusting: `mvnw` has no extension, plenty of
	/// scripts are called `run`, and a file called `build.sh` may well be a
	/// binary somebody renamed. The two bytes at the front are the fact.
	public static func isScript(at path: String) -> Bool {
		guard let handle = FileHandle(forReadingAtPath: path) else { return false }
		defer { try? handle.close() }
		guard let head = try? handle.read(upToCount: 2) else { return false }
		return head == Data("#!".utf8)
	}

	/// Which kind a script is, or nil when the file is not a script at all.
	public static func kind(ofProgramAt path: String) -> Kind? {
		guard isScript(at: path) else { return nil }
		switch (path as NSString).lastPathComponent.lowercased() {
		case "mvnw", "mvnw.cmd", "mvn": return .maven
		case "gradlew", "gradlew.bat", "gradle": return .gradle
		default: return .script
		}
	}

	/// How to start one script so that a debugger can attach to the JVM it runs.
	public struct Plan: Equatable, Sendable {
		/// Where the JVM will be listening.
		public var port: Int
		/// The environment to run the script with — the caller's, with whatever
		/// this kind needs added to it.
		public var environment: [String: String]
		/// The script's arguments, with whatever this kind needs appended.
		public var arguments: [String]
		/// One line for the console, saying what was arranged. Worth printing:
		/// none of this is visible in the command being run, and when it does
		/// not work the first question is what was actually asked for.
		public var note: String

		public init(port: Int, environment: [String: String], arguments: [String], note: String) {
			self.port = port
			self.environment = environment
			self.arguments = arguments
			self.note = note
		}
	}

	/// The JDWP option that makes a JVM open a port and wait on it.
	///
	/// `server=y` because we connect to it rather than the other way round, and
	/// `suspend=y` so it holds at its first instruction — without it the program
	/// has run past any breakpoint in its startup before the adapter is attached,
	/// which looks exactly like a breakpoint that does not work.
	///
	/// `address=127.0.0.1:port` and not the bare `address=port` that JDK 8 took:
	/// the bare form binds every interface, which puts an unauthenticated
	/// debugger port able to run arbitrary code on the machine's network. The
	/// host-qualified form needs JDK 9.
	public static func jdwpOption(port: Int) -> String {
		"-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=127.0.0.1:\(port)"
	}

	/// Everything one kind needs, ready to run.
	///
	/// - `port`: the port to ask for, when the caller has one. Ignored for
	///   `.gradle`, which cannot be told.
	public static func plan(
		kind: Kind,
		port: Int,
		environment: [String: String],
		arguments: [String]
	) -> Plan {
		switch kind {
		case .maven:
			let asked = adding(jdwpOption(port: port), to: "MAVEN_OPTS", in: environment)
			return Plan(
				port: port,
				environment: asked.environment,
				arguments: arguments,
				note: "Maven will run with JDWP on 127.0.0.1:\(port), waiting for the debugger."
					+ displacementNote(asked.displaced)
			)

		case .gradle:
			// The port is Gradle's, not ours, and it is asked for through the
			// task rather than the environment — but an agent already in the
			// environment would still reach the JVM Gradle forks and collide with
			// the one `--debug-jvm` puts there, so the sweep happens anyway.
			let cleaned = withoutDebugAgents(environment)
			return Plan(
				port: gradleDebugPort,
				environment: cleaned.environment,
				// Appended rather than prepended: it belongs to the task named in
				// the arguments, and Gradle reads it as an option of whatever task
				// came before it.
				arguments: arguments + ["--debug-jvm"],
				note: "Gradle will fork the JVM with --debug-jvm on 127.0.0.1:"
					+ "\(gradleDebugPort), waiting for the debugger."
					+ displacementNote(cleaned.displaced)
			)

		case .script:
			let asked = adding(jdwpOption(port: port), to: "JAVA_TOOL_OPTIONS", in: environment)
			return Plan(
				port: port,
				environment: asked.environment,
				arguments: arguments,
				note: "The first JVM this script starts will open JDWP on 127.0.0.1:\(port), "
					+ "waiting for the debugger."
					+ displacementNote(asked.displaced)
			)
		}
	}

	/// Whether a JVM option is one that loads the JDWP agent.
	///
	/// Two spellings, because both are still written: `-agentlib:jdwp` is the
	/// current one, and `-Xrunjdwp` the JDK 8 form that plenty of scripts and
	/// READMEs still carry — `mvnw`'s own header comment suggests exactly that,
	/// so a project whose `MAVEN_OPTS` has one came by it honestly.
	static func loadsDebugAgent(_ option: String) -> Bool {
		option.hasPrefix("-agentlib:jdwp") || option.hasPrefix("-Xrunjdwp")
	}

	/// Every variable whose contents reach a JVM this app is about to start.
	///
	/// All five are honoured by any JVM started under them, so an agent in any
	/// one of them lands on the same JVM as the one we are adding — and two
	/// agents is a JVM that will not start. `GRADLE_OPTS` is in the list because
	/// the daemon passes it on, and the JDK's own two are here because a machine
	/// that sets `_JAVA_OPTIONS` sets it for everything.
	public static let jvmOptionVariables = [
		"MAVEN_OPTS", "GRADLE_OPTS", "JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS", "JDK_JAVA_OPTIONS",
	]

	/// The environment with every JDWP agent taken out of every variable that
	/// reaches the JVM.
	///
	/// **Per-variable was not enough.** Cleaning only the variable being written
	/// to leaves the collision it was meant to prevent: a launcher script that
	/// puts an agent in `MAVEN_OPTS` and an editor that puts one in
	/// `JAVA_TOOL_OPTIONS` are writing to different variables and the same JVM,
	/// which then refuses to start with `Cannot load this JVM TI agent twice`.
	/// The variable is not the unit of the problem; the JVM is.
	///
	/// A variable that carried nothing is left absent rather than written empty,
	/// so the command line stays as short as it was.
	static func withoutDebugAgents(
		_ environment: [String: String]
	) -> (environment: [String: String], displaced: [String]) {
		var result = environment
		var displaced: [String] = []

		for variable in jvmOptionVariables {
			// The process environment as well as the configuration's, because the
			// pane's shell has both and only what we set here can override it.
			let existing = (environment[variable] ?? ProcessInfo.processInfo.environment[variable])
			guard let existing else { continue }

			let words = existing.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
			let agents = words.filter(loadsDebugAgent)
			guard !agents.isEmpty else { continue }

			displaced += agents.map { "\(variable)=\($0)" }
			result[variable] = words.filter { !loadsDebugAgent($0) }.joined(separator: " ")
		}
		return (result, displaced)
	}

	/// Adds our debug option, having first taken every other one out.
	///
	/// **A JVM will not start with two of them.** It refuses out of VM
	/// initialisation — `Cannot load this JVM TI agent twice`, then
	/// `agent library failed Agent_OnLoad: jdwp`, exit code 1 — before a line of
	/// the program runs. Appending blindly is therefore not a neutral act: for
	/// any configuration or machine that sets its own JDWP option, it produced a
	/// JVM that could not start, and the failure named neither the app nor the
	/// option it had just added.
	///
	/// Ours displaces theirs, rather than the other way round, because ours is
	/// the port the adapter is about to connect to; theirs is a number this app
	/// never learns. Everything else in every variable is kept — see `appending`,
	/// whose reasoning applies unchanged to every option that is not an agent.
	static func adding(
		_ option: String, to variable: String, in environment: [String: String]
	) -> (environment: [String: String], displaced: [String]) {
		let cleaned = withoutDebugAgents(environment)
		var result = cleaned.environment

		let kept = (result[variable] ?? "").trimmingCharacters(in: .whitespaces)
		result[variable] = kept.isEmpty ? option : kept + " " + option
		return (result, cleaned.displaced)
	}

	/// The half-sentence that says what was taken out, or nothing at all.
	///
	/// Printed with the plan because the displacement is otherwise invisible: the
	/// variables are in the environment, not in the command line the run pane
	/// shows, and somebody who put a JDWP option there deliberately is owed the
	/// news that it is not the one in effect.
	static func displacementNote(_ displaced: [String]) -> String {
		guard !displaced.isEmpty else { return "" }
		return " A debug agent was already asked for (\(displaced.joined(separator: " "))); "
			+ "it was taken out, because a JVM will not start with two."
	}

}
