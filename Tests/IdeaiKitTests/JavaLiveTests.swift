import Foundation
import Testing
@testable import IdeaiKit

/// Against the real Java language server, when the machine has one.
///
/// Skipped rather than failed where jdtls is not installed, the way the Swift
/// integration test is: whether somebody has it is a fact about their machine.
/// When it is there, this is what proves the handshake this app sends is one
/// jdtls accepts — every other Java test in this suite checks what we *send*,
/// and a server that rejects it would still pass all of them.
///
/// One test rather than four, and one server rather than four. jdtls holds a
/// JVM open and importing a project costs seconds of CPU; four of them running
/// beside the rest of the suite is enough load to push the wall-clock
/// performance tests over their budget, which reads as a regression in the
/// editor rather than as this file being greedy.
struct JavaLiveTests {
	@Test func jdtlsHostsTheWholeOfJavaSupport() async throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		guard let server = LanguageServers.resolve(languageId: "java", root: root) else { return }
		// A Maven project, so the server is rooted where the POM is.
		#expect(FilePath.canonical(server.root) == FilePath.canonical(root))

		let client = LSPClient()
		defer { client.stop() }

		LanguageServers.prepare(server.definition, root: root)
		try client.start(
			executable: server.executable,
			arguments: LanguageServers.arguments(for: server.definition, root: root),
			workingDirectory: root,
			environment: LanguageServers.serverEnvironment
		)

		// 1. The handshake, with the options this app sends.
		let capabilities = try await client.initialize(
			rootURL: root,
			options: LanguageServers.initializationOptions(for: server.definition, root: root),
			timeout: 120
		)
		#expect(!capabilities.isEmpty)
		#expect(capabilities["hoverProvider"] != nil)
		#expect(capabilities["definitionProvider"] != nil)
		// Java's debugger arrives through this one, and jdtls only offers it
		// when the initialize request was one it understood.
		#expect(capabilities["executeCommandProvider"] != nil)

		let file = root.appendingPathComponent("src/main/java/com/example/live/Server.java")
		let text = try String(contentsOf: file, encoding: .utf8)
		client.didOpen(uri: file.absoluteString, languageId: "java", version: 1, text: text)

		// 2. Symbols, which are also how the import having finished is known:
		// everything after this depends on a project jdtls has compiled.
		var symbols: [LSPSymbol] = []
		for _ in 0..<30 {
			symbols = (try? await client.documentSymbols(uri: file.absoluteString)) ?? []
			if !symbols.isEmpty { break }
			try? await Task.sleep(nanoseconds: 2_000_000_000)
		}
		#expect(symbols.map(\.name).contains { $0.contains("Server") })
		#expect(symbols.map(\.name).contains { $0.contains("greeting") })

		// 3. The classpath, which a JVM cannot be started without and which
		// nothing but the build knows.
		var classPaths: [String] = []
		for _ in 0..<15 {
			let result = try? await client.executeCommand(
				JavaDebug.classpathCommand,
				arguments: [file.absoluteString, JavaDebug.classpathOptions()]
			)
			classPaths = (result as? [String: Any])?["classpaths"] as? [String] ?? []
			if !classPaths.isEmpty { break }
			try? await Task.sleep(nanoseconds: 2_000_000_000)
		}
		#expect(!classPaths.isEmpty)
		#expect(classPaths.contains { $0.contains("target/classes") })

		// 4. The adapter itself, which exists only when the java-debug bundle
		// was found here and named in the initialize request.
		guard JavaTooling.debugPlugin() != nil else { return }
		let answer = try await client.executeCommand(JavaDebug.startCommand)
		let adapterPort = (answer as? Int) ?? (answer as? NSNumber)?.intValue ?? 0
		#expect(adapterPort > 0, "jdtls should answer with a port to speak DAP on")
		guard adapterPort > 0 else { return }

		// 5. And a real JVM, stopping where the breakpoint is.
		//
		// The adapter's events are handled off the main queue: this test is not
		// on it, and waiting for a main-thread hop that nothing is pumping is
		// how a live test hangs rather than fails.
		let dap = DAPClient()
		dap.callbackQueue = .global()
		let session = DebugSession(projectRoot: root, client: dap)
		defer { session.stop() }

		// Line 9 is `return "up";` inside `greeting()`, which `main` calls
		// once. The statement rather than the signature above it: a breakpoint
		// on a declaration slides to the next executable line, and a test that
		// expected the line it asked for would be testing the wrong thing.
		session.toggleBreakpoint(file: FilePath.canonical(file), line: 9)

		try await session.startJava(port: adapterPort, request: JavaDebug.Request(
			kind: .launch,
			mainClass: "com.example.live.Server",
			classPaths: classPaths,
			projectName: "live",
			workingDirectory: FilePath.canonical(root)
		))

		var frames: [StackFrame] = []
		for _ in 0..<60 {
			if case .stopped = session.state, !session.stackFrames.isEmpty {
				frames = session.stackFrames
				break
			}
			try? await Task.sleep(nanoseconds: 500_000_000)
		}

		let top = try #require(frames.first, "the JVM did not stop anywhere")
		#expect(top.line == 9, "the JVM should stop on the line the breakpoint is on")
		#expect(top.file?.hasSuffix("Server.java") == true)
		// The frame below it is the caller, which is what makes this a stack
		// rather than a line number.
		#expect(frames.count >= 2)
		#expect(frames.contains { $0.name.contains("main") })
	}

	/// A Maven project written into a temporary directory, because a live
	/// server needs a real one to import and the fixtures elsewhere in this
	/// suite are strings.
	private func makeProject() throws -> URL {
		let root = try JavaTestDirectory.make()
		try JavaTestDirectory.write("""
		<?xml version="1.0" encoding="UTF-8"?>
		<project xmlns="http://maven.apache.org/POM/4.0.0">
			<modelVersion>4.0.0</modelVersion>
			<groupId>com.example</groupId>
			<artifactId>live</artifactId>
			<version>1.0.0</version>
			<properties>
				<maven.compiler.release>21</maven.compiler.release>
			</properties>
		</project>
		""", to: root.appendingPathComponent("pom.xml"))
		try JavaTestDirectory.write("""
		package com.example.live;

		public class Server {
			public static void main(String[] args) {
				System.out.println(greeting());
			}

			static String greeting() {
				return "up";
			}
		}
		""", to: root.appendingPathComponent("src/main/java/com/example/live/Server.java"))
		return root
	}
}
