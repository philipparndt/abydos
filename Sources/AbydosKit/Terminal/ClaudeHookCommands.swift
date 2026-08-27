import Foundation

/// Wiring the hook up from the command line.
///
/// `install`, `remove` and `status`, printing what they did: this edits a file
/// somebody owns, so it says which file, what went in it, and where the copy
/// of the old one is.
public enum ClaudeHookCommands {
	/// What has to go in the settings for Claude Code to find the hook.
	///
	/// The binary by its real path, because Claude Code runs hooks through
	/// `sh -c` with a minimal environment — a bare name would only work if the
	/// app happened to be on whatever PATH that gives it.
	public static func command(for binary: String) -> String {
		URL(fileURLWithPath: binary).resolvingSymlinksInPath().path
	}

	public static func runSetup(_ action: String, hookBinary: String) -> Never {
		let url = ClaudeHookSetup.settingsURL
		let hookCommand = command(for: hookBinary)
		do {
			let settings = try ClaudeHookSetup.read(at: url)

			switch action {
			case "install":
				let updated = ClaudeHookSetup.adding(command: hookCommand, to: settings)
				let backup = try ClaudeHookSetup.write(updated, to: url)
				print("Wired Abydos into \(url.path)")
				print("  \(hookCommand)")
				print("  events: \(ClaudeHookSetup.events.joined(separator: ", "))")
				if let backup { print("  the file as it was: \(backup.lastPathComponent)") }
				print("Restart the Claude sessions you have running so they pick the hooks up.")

			case "remove":
				let updated = ClaudeHookSetup.removing(from: settings)
				let backup = try ClaudeHookSetup.write(updated, to: url)
				print("Removed Abydos\u{2019}s hooks from \(url.path)")
				if let backup { print("  the file as it was: \(backup.lastPathComponent)") }

			default:
				let installed = ClaudeHookSetup.isInstalled(command: hookCommand, in: settings)
				print(installed
					? "Abydos\u{2019}s Claude hooks are installed in \(url.path)"
					: "Abydos\u{2019}s Claude hooks are not installed \u{2014} run: abydos-hook install")
				print("  this binary: \(hookCommand)")
			}
		} catch {
			FileHandle.standardError.write(Data("abydos-hook: \(error)\n".utf8))
			exit(1)
		}
		exit(0)
	}
}
