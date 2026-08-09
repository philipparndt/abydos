import Foundation

/// The tools that belong to a toolchain, asked of the selected Xcode by name.
///
/// The Makefile says this at length for the build — `SWIFT := xcrun swift`,
/// with a paragraph about the morning macOS 27 arrived and swiftly's Swift
/// could no longer compile Foundation — and the editor had never been told.
/// So the build ran one Swift and the diagnostics on screen came from another:
/// measured on this machine, `sourcekit-lsp` and `clangd` were both swiftly's
/// while `xcrun` answered with Xcode's, because `~/.swiftly/bin` comes before
/// `/usr/bin` on a login shell's `PATH` and the search started there.
///
/// A red squiggle the compiler does not agree with is worse than a slow
/// machine, because it is believed. So for these tools the `PATH` is not asked
/// at all: `xcrun --find` asks the Xcode that owns the SDK everything else is
/// built against, and that is the one the editor has to mean.
///
/// Only these tools. Everything else — gopls, rust-analyzer, pyright — belongs
/// to a version manager rather than to Xcode, and asking `xcrun` for one would
/// find nothing and be a slower way of finding nothing.
public enum XcodeToolchain {
	/// The commands that come out of a toolchain rather than off the `PATH`.
	///
	/// Each is a program a *toolchain manager also ships*, which is what makes
	/// the ambiguity real: `swiftly` puts its own `sourcekit-lsp`, `clangd` and
	/// `lldb-dap` in front of Xcode's, and each of the three then disagrees with
	/// the compiler the build used — about a diagnostic, about a header, about
	/// what a frame contains.
	public static let commands: Set<String> = ["sourcekit-lsp", "clangd", "lldb-dap"]

	/// Whether this tool is one Xcode owns.
	public static func owns(_ tool: String) -> Bool { commands.contains(tool) }

	/// Where the selected Xcode keeps a tool, or nil when it has none by that
	/// name.
	///
	/// Read once per tool per run. `xcrun` is a process, this is asked every time
	/// the status bar wants to know whether a server is installed, and the answer
	/// only changes when somebody runs `xcode-select` — which is not something to
	/// pay for on every keystroke.
	public static func path(for tool: String) -> String? {
		if let remembered = found.recorded(for: tool) { return remembered }
		let path = ask(for: tool)
		found.remember(path, for: tool)
		return path
	}

	private static let found = Answers()

	private static func ask(for tool: String) -> String? {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
		process.arguments = ["--find", tool]
		let output = Pipe()
		process.standardOutput = output
		process.standardError = Pipe()
		// Nothing is typed at it, and a handle left open is a handle the tool
		// waits on.
		process.standardInput = FileHandle.nullDevice

		guard (try? process.run()) != nil else { return nil }
		let data = ProcessPipes.drain(process, out: output)
		guard process.terminationStatus == 0 else { return nil }

		let path = String(data: data, encoding: .utf8)?
			.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		return FileManager.default.isExecutableFile(atPath: path) ? path : nil
	}

	/// What `xcrun` has already been asked, including the tools it had no answer
	/// for — "not in Xcode" is worth remembering too, or a missing tool costs a
	/// process every time somebody asks.
	private final class Answers: @unchecked Sendable {
		private let lock = NSLock()
		private var answers: [String: String?] = [:]

		/// Doubly optional on purpose: "asked, and Xcode has no such tool" is a
		/// different answer from "not asked yet", and collapsing the two costs a
		/// process every time somebody looks.
		func recorded(for tool: String) -> String?? {
			lock.lock()
			defer { lock.unlock() }
			return answers[tool]
		}

		func remember(_ path: String?, for tool: String) {
			lock.lock()
			answers[tool] = path
			lock.unlock()
		}
	}
}
