import Foundation

/// Debugging Java, which is arranged differently from everything else here.
///
/// Every other debugger in this app is a program: point at `dlv` or `lldb-dap`,
/// start it, speak the protocol down its pipe. Java's is not. The adapter is an
/// Eclipse bundle loaded *inside* the language server, and the only way to
/// reach it is to ask jdtls — over LSP — to start a debug session, which
/// answers with a port on this machine. From there it is an ordinary DAP
/// connection.
///
/// That is not an implementation detail worth hiding: it means Java debugging
/// needs a running language server, and a project whose server has not
/// finished importing cannot be debugged yet. Saying so is better than a
/// timeout with no cause.
public enum JavaDebug {
	/// How long to let jdtls think about a question asked while a debug session
	/// is being arranged.
	///
	/// **`executeCommand`'s default of 30 seconds is a small-project number.**
	/// Two of these questions — the debug port and the classpath — were left at
	/// it while the build beside them asks for 300, and on a thousand-module
	/// Maven reactor neither answers inside half a minute. Measured there:
	/// `java.project.getClasspaths` timed out at 30 seconds, and all the window
	/// said was that Java could not be debugged yet, about a server that was
	/// working on the answer.
	///
	/// Not unbounded, because a jdtls that has genuinely stopped answering has to
	/// end in a sentence rather than a spinner. `javaLaunchTarget` allows the
	/// whole arrangement 600 seconds; one question inside it gets a quarter.
	public static let queryTimeout: TimeInterval = 150

	/// The command jdtls answers with a debug port.
	public static let startCommand = "vscode.java.startDebugSession"
	/// The command that reports a project's classpath.
	public static let classpathCommand = "java.project.getClasspaths"
	/// The command that lists the classes with a `main` method, as the language
	/// server sees them.
	public static let mainClassCommand = "vscode.java.resolveMainClass"
	/// The command that carries the debugger's settings into the adapter.
	///
	/// **Which is where hot code replace is turned on**, and it is a setting of
	/// the adapter's rather than anything this app implements:
	/// `hotCodeReplace` is `AUTO`, `MANUAL` or `NEVER`, and in `AUTO` the
	/// provider inside the bundle swaps whenever the workspace it listens to
	/// gains new class files — which is whenever jdtls has finished compiling.
	public static let settingsCommand = "vscode.java.updateDebugSettings"

	/// The command that compiles what the server has imported.
	///
	/// **The step between a classpath and a class file, and 0452 found it by
	/// getting a `ClassNotFoundException` from a project that was perfectly
	/// correct.** jdtls compiles into the output directory the build file names —
	/// `target/classes` for Maven — and it does that *after* the import, so the
	/// first launch of a session can be handed an entirely right classpath with
	/// nothing in it yet. VS Code's Java extension builds before it launches for
	/// this reason, and so does this.
	///
	/// **And it was not doing it, for as long as it has existed.** The argument
	/// went as a bare `false` and the command wants a JSON *string*, so every
	/// call threw inside the server —
	///
	///     ClassCastException: class java.lang.Boolean cannot be cast to
	///     class java.lang.String
	///
	/// — on jdtls's stderr, into a `try?` that dropped it, so nothing anywhere
	/// said the compile had not happened. Found while adding hot code replace,
	/// by reading the log after a launch: with the argument encoded the server
	/// answers `Compile compile INFO: Time cost for ECJ: 1ms`, a line that had
	/// never appeared before.
	public static let buildCommand = "vscode.java.buildWorkspace"

	/// The argument shape `vscode.java.buildWorkspace` wants.
	///
	/// The third command in this family to take its options pre-encoded, after
	/// `classpathOptions` and `HotSwap.settings`. Assume any of them does.
	public static func buildOptions(fullBuild: Bool = false) -> String {
		"{\"isFullBuild\":\(fullBuild)}"
	}

	/// The argument shape `java.project.getClasspaths` wants.
	///
	/// A JSON *string*, not an object — the command takes its options
	/// pre-encoded, and an object goes in and comes back as a class cast
	/// failure inside the server.
	public static func classpathOptions(runtime: Bool = true) -> String {
		"{\"scope\":\"\(runtime ? "runtime" : "test")\"}"
	}

	/// What a Java debug session is asked to do.
	public struct Request: Equatable, Sendable {
		public enum Kind: String, Equatable, Sendable {
			/// Start a JVM here and debug it.
			case launch
			/// Connect to a JVM that is already running with JDWP open —
			/// which, for this app, means one in a pod behind a port-forward.
			case attach
		}

		public var kind: Kind
		/// Fully qualified, as the JVM names it.
		public var mainClass: String
		/// Every jar and class directory the program needs. Java has no idea
		/// what its own classpath is; the language server does, because it has
		/// read the build file.
		public var classPaths: [String]
		/// The name jdtls gave the project, which the adapter uses to find
		/// sources for the frames it reports.
		public var projectName: String?
		public var workingDirectory: String?
		public var arguments: [String]
		public var vmArguments: [String]
		public var environment: [String: String]
		/// Where the JVM is, for an attach.
		public var host: String
		public var port: Int

		public init(
			kind: Kind = .launch,
			mainClass: String = "",
			classPaths: [String] = [],
			projectName: String? = nil,
			workingDirectory: String? = nil,
			arguments: [String] = [],
			vmArguments: [String] = [],
			environment: [String: String] = [:],
			host: String = "127.0.0.1",
			port: Int = 0
		) {
			self.kind = kind
			self.mainClass = mainClass
			self.classPaths = classPaths
			self.projectName = projectName
			self.workingDirectory = workingDirectory
			self.arguments = arguments
			self.vmArguments = vmArguments
			self.environment = environment
			self.host = host
			self.port = port
		}

		/// The request as java-debug expects it.
		///
		/// `console: internalConsole` on purpose: the alternative opens a
		/// terminal of the adapter's choosing, and this app has a console of its
		/// own that the output belongs in.
		public var wireFormat: [String: Any] {
			var request: [String: Any] = ["request": kind.rawValue]
			if let projectName { request["projectName"] = projectName }

			switch kind {
			case .launch:
				request["mainClass"] = mainClass
				request["classPaths"] = classPaths
				request["console"] = "internalConsole"
				// The adapter would otherwise stop in the JVM's own startup code
				// on some versions, which is nobody's breakpoint.
				request["stopOnEntry"] = false
				if let workingDirectory { request["cwd"] = workingDirectory }
				if !arguments.isEmpty { request["args"] = arguments }
				if !vmArguments.isEmpty { request["vmArgs"] = vmArguments.joined(separator: " ") }
				if !environment.isEmpty { request["env"] = environment }
			case .attach:
				request["hostName"] = host
				request["port"] = port
				// The sources are here, the program is in a pod, and the adapter
				// has to be told they belong together or every frame comes back
				// without a file.
				if !classPaths.isEmpty { request["sourcePaths"] = classPaths }
			}
			return request
		}
	}

	// MARK: - Hot code replace

	/// Replacing the body of a method in a JVM that is already running.
	///
	/// **Everything here was read out of the bundle rather than remembered**, with
	/// `javap` over `com.microsoft.java.debug.plugin-0.53.2.jar` and the
	/// `com.microsoft.java.debug.core-0.53.2.jar` inside it, because three
	/// guesses about it were wrong and each would have been built on:
	///
	///  - **There is no capability.** `Types$Capabilities` has eighteen fields
	///    and not one of them is about hot code replace, so nothing can be asked
	///    ahead of time and whether it is possible is learnt from a refusal.
	///  - **The request takes no arguments.** `RedefineClassesArguments` has no
	///    fields at all, because `JavaHotCodeReplaceProvider` is an
	///    `IResourceChangeListener` that keeps its own `deltaClassNames` — it
	///    watches the workspace and already knows what was recompiled. There is
	///    no way to hand it a class file, which is what the plan for OSGi had
	///    depended on.
	///  - **It drops to frame by itself.** `attemptPopFrames`,
	///    `attemptDropToFrame` and `attemptStepIn` are all in the provider, so a
	///    method affected by a swap is entered again rather than left to run its
	///    old body out. Not this app's to decline, only to explain.
	public enum HotSwap {
		/// The custom DAP request. Sent only in `MANUAL`; in `AUTO` the provider
		/// swaps on its own and this is never needed.
		public static let command = "redefineClasses"

		/// The event the adapter raises about a swap, at every stage of one.
		public static let event = "hotcodereplace"

		/// How the adapter is asked to behave, by `settingsCommand`.
		public enum Mode: String, Sendable {
			case auto = "AUTO"
			case manual = "MANUAL"
			case never = "NEVER"
		}

		/// The argument shape `vscode.java.updateDebugSettings` wants.
		///
		/// **A JSON *string*, not an object**, which is the same trap
		/// `classpathOptions` records for `java.project.getClasspaths` — the
		/// commands in this family take their options pre-encoded. Passing a
		/// dictionary got it as far as the server and no further:
		///
		///     SEVERE: Parameters for userSettings must be json string:
		///             {hotCodeReplace=AUTO}
		///
		/// Which is a message on jdtls's stderr and nothing at all in the app, so
		/// the setting silently did not take. Found by driving it; a unit test
		/// over this function cannot see it, and one is here anyway so the shape
		/// cannot drift back.
		/// **And `logLevel` with it, which is not optional in practice.**
		/// `DebugSettingUtils` merges this JSON into the current settings and
		/// then, unconditionally, hands `logLevel` to `LogUtils.configLogLevel`,
		/// which parses it as a `java.util.logging.Level`. It is null until
		/// somebody sets it, so a settings update that says only what it came to
		/// say ends in
		///
		///     NullPointerException: Cannot invoke "String.length()"
		///     because "name" is null
		///       at java.util.logging.Level.parse
		///       at LogUtils.configLogLevel
		///
		/// on jdtls's stderr. `WARNING` rather than `INFO` because this server
		/// exists to host a debug adapter and its logging is already in the app's
		/// own log at the volume it wants.
		public static func settings(mode: Mode, logLevel: String = "WARNING") -> String {
			"{\"hotCodeReplace\":\"\(mode.rawValue)\",\"logLevel\":\"\(logLevel)\"}"
		}

		/// What one `hotcodereplace` event says.
		///
		/// The five change types are the adapter's own, and they arrive in a
		/// sequence rather than one at a time: `STARTING` when it begins,
		/// `BUILD_COMPLETE` when the compile it was waiting for landed, `END`
		/// when classes were actually redefined, and `ERROR` or `WARNING`
		/// instead when they were not.
		public enum Stage: String, Equatable, Sendable {
			case starting = "STARTING"
			case buildComplete = "BUILD_COMPLETE"
			case end = "END"
			case error = "ERROR"
			case warning = "WARNING"
		}

		public struct Event: Equatable, Sendable {
			public let stage: Stage
			public let message: String?

			public init(stage: Stage, message: String?) {
				self.stage = stage
				self.message = message
			}
		}

		/// Reads one, or nil when the body is not one this understands.
		///
		/// A change type this app has not seen answers nil rather than being
		/// forced into the nearest case: the adapter may grow one, and a new
		/// stage silently reported as an error would be a lie about somebody's
		/// session.
		public static func event(from body: [String: Any]) -> Event? {
			guard let said = body["changeType"] as? String,
			      let stage = Stage(rawValue: said)
			else { return nil }
			let message = (body["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
			return Event(stage: stage, message: message)
		}

		/// What came back from a `redefineClasses` request.
		public struct Result: Equatable, Sendable {
			/// The classes the JVM took, as the adapter names them.
			public let changed: [String]
			/// Why it took none, when it took none.
			public let errorMessage: String?

			public init(changed: [String], errorMessage: String?) {
				self.changed = changed
				self.errorMessage = errorMessage
			}

			/// Whether anything was actually swapped.
			public var didSwap: Bool { !changed.isEmpty }
		}

		public static func result(from body: [String: Any]) -> Result {
			let changed = (body["changedClasses"] as? [Any])?.compactMap { $0 as? String } ?? []
			let message = (body["errorMessage"] as? String).flatMap { $0.isEmpty ? nil : $0 }
			return Result(changed: changed, errorMessage: message)
		}

		/// Whether a failure is about the session rather than about the change.
		///
		/// **The one distinction the reporting turns on**, and the adapter does
		/// not draw it: a change HotSpot refuses is ordinary and says nothing
		/// about the session, while a session that cannot swap at all should say
		/// so once and then stop. There is no field for it, so the only evidence
		/// is the wording.
		///
		/// **Deliberately narrow.** It answers true only for the things that
		/// cannot be about one edit — a VM that does not support redefinition at
		/// all, or an adapter with no provider in it. Everything else is treated
		/// as being about the change, because a refusal wrongly classified as
		/// "this session cannot swap" silences every later save, and a message
		/// nobody sees is worse than one they see twice.
		public static func isAboutTheSession(_ message: String) -> Bool {
			let said = message.lowercased()
			// "does not support hot code replace", "hot code replace is not
			// supported", "unsupported operation: redefine".
			if said.contains("not support") || said.contains("unsupported") {
				return said.contains("hot code replace")
					|| said.contains("hotcodereplace")
					|| said.contains("redefin")
			}
			// A provider that was never installed answers about itself.
			return said.contains("no hot code replace provider")
		}

		/// Whether an event says the stack was moved under somebody.
		///
		/// The provider drops to an affected frame and enters it again, so a
		/// session stopped inside a method it just swapped is somewhere else
		/// afterwards. Unexplained that reads as the debugger losing its place.
		public static func movedTheStack(_ event: Event, wasStopped: Bool) -> Bool {
			event.stage == .end && wasStopped
		}
	}

	/// The JVM flag that opens a debugger port on a program being started
	/// somewhere else.
	///
	/// `suspend=y` because the point of debugging a program in a pod is to be
	/// there when it starts: without it the interesting half of a service's life
	/// — its configuration, its first connection — is over before the debugger
	/// attaches. `*:` rather than `localhost:` because the connection arrives
	/// from outside the container, through the port-forward.
	public static func jdwpArgument(port: Int, suspend: Bool = true) -> String {
		"-agentlib:jdwp=transport=dt_socket,server=y,suspend=\(suspend ? "y" : "n"),address=*:\(port)"
	}
}
