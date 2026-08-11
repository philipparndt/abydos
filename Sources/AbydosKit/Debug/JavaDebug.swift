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
	/// The command jdtls answers with a debug port.
	public static let startCommand = "vscode.java.startDebugSession"
	/// The command that reports a project's classpath.
	public static let classpathCommand = "java.project.getClasspaths"
	/// The command that lists the classes with a `main` method, as the language
	/// server sees them.
	public static let mainClassCommand = "vscode.java.resolveMainClass"
	/// The command that compiles what the server has imported.
	///
	/// **The step between a classpath and a class file, and 0452 found it by
	/// getting a `ClassNotFoundException` from a project that was perfectly
	/// correct.** jdtls compiles into the output directory the build file names —
	/// `target/classes` for Maven — and it does that *after* the import, so the
	/// first launch of a session can be handed an entirely right classpath with
	/// nothing in it yet. VS Code's Java extension builds before it launches for
	/// this reason, and so does this.
	public static let buildCommand = "vscode.java.buildWorkspace"

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
