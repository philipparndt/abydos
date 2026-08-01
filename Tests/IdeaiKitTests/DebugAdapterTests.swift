import Foundation
import Testing
@testable import IdeaiKit

/// Which debugger to use, and what to tell it.
struct DebugAdapterTests {
	@Test func knowsDelveAndLLDB() {
		#expect(DebugAdapters.adapter(id: "delve")?.command == "dlv")
		#expect(DebugAdapters.adapter(id: "lldb")?.command == "lldb-dap")
		#expect(DebugAdapters.adapter(id: "gdb") == nil)
	}

	/// Delve is a server; LLDB's adapter speaks over its own pipes. Getting
	/// this wrong means writing into a void and waiting for ever.
	@Test func knowsHowEachOneIsSpokenTo() {
		#expect(DebugAdapters.delve.transport == .socket)
		#expect(DebugAdapters.lldb.transport == .standardIO)
	}

	/// Adapters branch on what the client calls them.
	@Test func callsEachAdapterWhatItExpects() {
		#expect(DebugAdapters.delve.adapterID == "go")
		#expect(DebugAdapters.lldb.adapterID == "lldb")
	}

	// MARK: - Choosing one

	private func makeTree(_ paths: [String]) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("adapters-\(UUID().uuidString)")
		for path in paths {
			let url = root.appendingPathComponent(path)
			try FileManager.default.createDirectory(
				at: url.deletingLastPathComponent(), withIntermediateDirectories: true
			)
			try "x".write(to: url, atomically: true, encoding: .utf8)
		}
		return root
	}

	@Test func choosesDelveForAGoModule() throws {
		let root = try makeTree(["go.mod", "cmd/server/main.go"])
		defer { try? FileManager.default.removeItem(at: root) }

		let chosen = DebugAdapters.adapter(
			forProgramAt: root.appendingPathComponent("cmd/server").path, projectRoot: root
		)
		#expect(chosen.id == "delve")
	}

	/// The module need not be at the project root — Go repositories often keep
	/// go.mod in a subdirectory.
	@Test func findsAModuleAboveTheProgram() throws {
		let root = try makeTree(["service/go.mod", "service/cmd/main.go"])
		defer { try? FileManager.default.removeItem(at: root) }

		let chosen = DebugAdapters.adapter(
			forProgramAt: root.appendingPathComponent("service/cmd").path, projectRoot: root
		)
		#expect(chosen.id == "delve")
	}

	@Test func choosesLLDBForAnythingElse() throws {
		let root = try makeTree(["Cargo.toml", "target/debug/app"])
		defer { try? FileManager.default.removeItem(at: root) }

		let chosen = DebugAdapters.adapter(
			forProgramAt: root.appendingPathComponent("target/debug/app").path, projectRoot: root
		)
		#expect(chosen.id == "lldb")
	}

	// MARK: - Requests

	/// Delve builds what it is pointed at; LLDB debugs a binary that exists.
	@Test func shapesTheLaunchRequestPerAdapter() {
		let go = DebugAdapters.launchArguments(
			for: .init(
				id: "delve", name: "Delve", command: "dlv", arguments: [],
				transport: .socket, adapterID: "go", installHint: ""
			),
			program: "/x/cmd", workingDirectory: "/x"
		)
		#expect(go["mode"] as? String == "debug")
		#expect(go["program"] as? String == "/x/cmd")
		#expect(go["cwd"] as? String == "/x")

		let native = DebugAdapters.launchArguments(
			for: DebugAdapters.lldb, program: "/x/app", workingDirectory: "/x"
		)
		#expect(native["mode"] == nil)
		// Stopping at the entry point strands you in the C runtime.
		#expect(native["stopOnEntry"] as? Bool == false)
	}

	@Test func passesProgramArgumentsWhenThereAreAny() {
		let withArgs = DebugAdapters.launchArguments(
			for: DebugAdapters.lldb, program: "/x/app", workingDirectory: "/x",
			arguments: ["--verbose", "file.txt"]
		)
		#expect(withArgs["args"] as? [String] == ["--verbose", "file.txt"])

		let without = DebugAdapters.launchArguments(
			for: DebugAdapters.lldb, program: "/x/app", workingDirectory: "/x"
		)
		#expect(without["args"] == nil)
	}

	/// Delve names the process differently from everything else.
	@Test func shapesTheAttachRequestPerAdapter() {
		let go = DebugAdapters.attachArguments(for: DebugAdapters.delve, pid: 4242)
		#expect(go["processId"] as? Int == 4242)
		#expect(go["mode"] as? String == "local")

		let native = DebugAdapters.attachArguments(for: DebugAdapters.lldb, pid: 4242)
		#expect(native["pid"] as? Int == 4242)
		#expect(native["request"] as? String == "attach")
	}
}

/// What is running, for attaching to.
struct RunningProcessTests {
	@Test func readsPidsAndNames() {
		let processes = RunningProcesses.parse("""
		  501 /Applications/Ghostty.app/Contents/MacOS/ghostty
		  733 /Users/x/dev/app/server
		""")
		#expect(processes.count == 2)
		#expect(processes.first?.pid == 733)
		#expect(processes.first?.name == "server")
		#expect(processes.last?.name == "ghostty")
	}

	/// Nobody attaches a debugger to WindowServer, and there are hundreds of
	/// them: a list containing every daemon is one nothing can be found in.
	@Test func leavesOutTheSystem() {
		let processes = RunningProcesses.parse("""
		  100 /System/Library/CoreServices/WindowServer
		  101 /usr/libexec/secinitd
		  102 /usr/sbin/cupsd
		  103 /Users/x/dev/app/server
		""")
		#expect(processes.map(\.name) == ["server"])
	}

	@Test func neverOffersItself() {
		let own = Int(ProcessInfo.processInfo.processIdentifier)
		let processes = RunningProcesses.parse("  \(own) /Users/x/ideai\n  9 /Users/x/app")
		#expect(!processes.contains { $0.pid == own })
	}

	@Test func survivesLinesItCannotRead() {
		let processes = RunningProcesses.parse("nonsense\n\n  42 /Users/x/app\n  bad /Users/x/other")
		#expect(processes.map(\.pid) == [42])
	}

	/// Against the real machine, which is the only way to know `ps` was read
	/// correctly at all.
	@Test func findsSomethingActuallyRunning() {
		let processes = RunningProcesses.list()
		#expect(!processes.isEmpty)
		#expect(processes.allSatisfy { $0.pid > 0 && !$0.name.isEmpty })
	}
}
