import Foundation
import Testing
@testable import AbydosKit

/// The shape of what java-debug is sent, and who is asked to start it.
struct JavaDebugTests {
	@Test func launchesAClassWithItsClasspath() {
		let request = JavaDebug.Request(
			kind: .launch,
			mainClass: "com.example.api.Server",
			classPaths: ["/p/target/classes", "/m/spring-core.jar"],
			projectName: "api",
			workingDirectory: "/p",
			arguments: ["--stage", "dev"],
			vmArguments: ["-Xmx512m"],
			environment: ["STAGE": "dev"]
		)
		let wire = request.wireFormat

		#expect(wire["request"] as? String == "launch")
		#expect(wire["mainClass"] as? String == "com.example.api.Server")
		#expect(wire["classPaths"] as? [String] == ["/p/target/classes", "/m/spring-core.jar"])
		#expect(wire["projectName"] as? String == "api")
		#expect(wire["cwd"] as? String == "/p")
		#expect(wire["args"] as? [String] == ["--stage", "dev"])
		// The adapter takes VM arguments as one string, not a list.
		#expect(wire["vmArgs"] as? String == "-Xmx512m")
		#expect((wire["env"] as? [String: String])?["STAGE"] == "dev")
		// Its own console would open a terminal of the adapter's choosing.
		#expect(wire["console"] as? String == "internalConsole")
	}

	/// An attach says where the JVM is and nothing about how to start it — it
	/// is already running, in a pod, behind a forwarded port.
	@Test func attachesToAJVMSomewhereElse() {
		let request = JavaDebug.Request(
			kind: .attach,
			mainClass: "com.example.api.Server",
			classPaths: ["/p/target/classes"],
			host: "127.0.0.1",
			port: 51234
		)
		let wire = request.wireFormat

		#expect(wire["request"] as? String == "attach")
		#expect(wire["hostName"] as? String == "127.0.0.1")
		#expect(wire["port"] as? Int == 51234)
		// The sources are here even though the program is not.
		#expect(wire["sourcePaths"] as? [String] == ["/p/target/classes"])
		#expect(wire["mainClass"] == nil)
		#expect(wire["cwd"] == nil)
	}

	/// The flag the pod's JVM is started with, which is what the attach then
	/// connects to.
	@Test func opensADebuggerPortOnTheJVMInThePod() {
		#expect(JavaDebug.jdwpArgument(port: 2345)
			== "-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=*:2345")
		#expect(JavaDebug.jdwpArgument(port: 2345, suspend: false).contains("suspend=n"))
	}

	/// The classpath command takes its options pre-encoded, and an object goes
	/// in and comes back as a failure inside the server.
	@Test func asksForTheClasspathTheWayTheServerWantsIt() {
		#expect(JavaDebug.classpathOptions() == "{\"scope\":\"runtime\"}")
		#expect(JavaDebug.classpathOptions(runtime: false) == "{\"scope\":\"test\"}")
	}

	/// Java's adapter is not a program, and picking it has to say so.
	@Test func javasAdapterIsHostedByTheLanguageServer() {
		#expect(DebugAdapters.java.transport == .languageServer)
		#expect(DebugAdapters.adapter(id: "java") == DebugAdapters.java)
	}

	@Test func picksTheAdapterFromTheBuildFileBesideTheProgram() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }

		let module = root.appendingPathComponent("api")
		try JavaTestDirectory.write("<project/>", to: module.appendingPathComponent("pom.xml"))
		#expect(DebugAdapters.adapter(
			forProgramAt: module.appendingPathComponent("src/main/java/App.java").path,
			projectRoot: root
		) == DebugAdapters.java)

		let goModule = root.appendingPathComponent("service")
		try JavaTestDirectory.write("module x\n", to: goModule.appendingPathComponent("go.mod"))
		#expect(DebugAdapters.adapter(
			forProgramAt: goModule.appendingPathComponent("main.go").path, projectRoot: root
		) == DebugAdapters.delve)
	}

	/// A configuration says which debugger, and a Java one says Java.
	@Test func javaConfigurationsChooseJavasAdapter() {
		#expect(LaunchConfiguration(name: "x", type: "java").adapterID == "java")
		#expect(LaunchConfiguration(name: "x", type: "go").adapterID == "delve")
		#expect(LaunchConfiguration(name: "x", type: "lldb").adapterID == "lldb")
	}

	/// A JVM is not pointed at a file, so `program` is the class — unless the
	/// configuration was written VS Code's way, which spells it `mainClass`.
	@Test func findsTheClassAConfigurationStarts() {
		#expect(LaunchConfiguration(name: "x", type: "java", program: "com.example.Server")
			.javaMainClass == "com.example.Server")
		#expect(LaunchConfiguration(
			name: "x", type: "java", program: "${workspaceFolder}",
			extras: ["mainClass": .string("com.example.Other")]
		).javaMainClass == "com.example.Other")
		// A path is not a class, and neither is an unexpanded variable.
		#expect(LaunchConfiguration(name: "x", type: "java", program: "${workspaceFolder}").javaMainClass == nil)
		#expect(LaunchConfiguration(name: "x", type: "go", program: "com.example.Server").javaMainClass == nil)
	}

	@Test func readsVMArgumentsInEitherShape() {
		#expect(LaunchConfiguration(
			name: "x", type: "java", extras: ["vmArgs": .string("-Xmx1g -Dfoo=bar")]
		).javaVMArguments == ["-Xmx1g", "-Dfoo=bar"])
		#expect(LaunchConfiguration(
			name: "x", type: "java", extras: ["vmArgs": .array([.string("-Xmx1g")])]
		).javaVMArguments == ["-Xmx1g"])
	}
}
