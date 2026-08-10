import Foundation

/// Turning tmux's own status bar off, and putting it back.
///
/// With the panel showing tmux's windows as tabs, tmux's bar is the same list
/// twice. Reporting the pane a line taller and hiding that line — the clever
/// version — never really worked: tmux paints the bar once at attach and then
/// stops repainting a row it no longer owns, so the old one shows through.
///
/// So this asks instead. `~/.tmux.conf` is the file that decides, it belongs to
/// the person using it, and an edit here is one they can see, keep, or undo —
/// by pressing the button again or by deleting three lines.
public enum TmuxConfig {
	public static var configURL: URL {
		FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".tmux.conf")
	}

	/// What is written, between markers so it can be taken out exactly.
	static let openingMarker = "# >>> ideai: tmux's own status bar"
	static let closingMarker = "# <<< ideai"

	private static let block = """
	\(openingMarker)
	# ideai shows this session's windows as tabs, so the bar below them would be
	# the same list twice. Delete this block, or press the button in ideai's
	# settings again, to have it back.
	set -g status off
	\(closingMarker)
	"""

	/// Whether ideai's block is in a config.
	public static func hidesStatus(in config: String) -> Bool {
		config.contains(openingMarker)
	}

	/// The config with the block added, or unchanged if it is already there.
	///
	/// Appended, never woven in: a config is somebody's own file, read top to
	/// bottom, and the last word on an option is the one that counts.
	public static func adding(to config: String) -> String {
		guard !hidesStatus(in: config) else { return config }
		let body = trimmed(config)
		return body.isEmpty ? block + "\n" : body + "\n\n" + block + "\n"
	}

	/// The config with the block taken out, and nothing else touched.
	public static func removing(from config: String) -> String {
		// A file without our block is not ours to tidy: it goes back exactly as
		// it came, trailing newlines and all.
		guard hidesStatus(in: config) else { return config }

		var lines = config.components(separatedBy: "\n")
		var kept: [String] = []
		var inside = false

		for line in lines {
			if line.hasPrefix(openingMarker) {
				inside = true
				// The blank line that was put in front of the block goes with
				// it, so pressing the button twice leaves the file as it was.
				if kept.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
					kept.removeLast()
				}
				continue
			}
			if inside {
				if line.hasPrefix(closingMarker) { inside = false }
				continue
			}
			kept.append(line)
		}

		lines = kept
		let body = trimmed(lines.joined(separator: "\n"))
		return body.isEmpty ? "" : body + "\n"
	}

	/// A config's text without the blank lines at the end.
	///
	/// Both ends of this normalise the same way, so pressing the button twice
	/// leaves the file as it found it rather than a newline longer each time.
	private static func trimmed(_ config: String) -> String {
		var text = config
		while text.hasSuffix("\n") || text.hasSuffix(" ") || text.hasSuffix("\t") {
			text.removeLast()
		}
		return text
	}

	// MARK: - The file, and the server

	public enum Failure: Error, Equatable {
		case unreadable(String)
		case unwritable(String)
	}

	public static func read(at url: URL = configURL) throws -> String {
		guard FileManager.default.fileExists(atPath: url.path) else { return "" }
		guard let text = try? String(contentsOf: url, encoding: .utf8) else {
			throw Failure.unreadable(url.path)
		}
		return text
	}

	/// Writes the config back, keeping a copy of what was there.
	@discardableResult
	public static func write(_ config: String, to url: URL = configURL) throws -> URL? {
		var backup: URL?
		if FileManager.default.fileExists(atPath: url.path) {
			let stamp = ISO8601DateFormatter().string(from: Date())
				.replacingOccurrences(of: ":", with: "-")
			let copy = url.deletingLastPathComponent()
				.appendingPathComponent(".tmux.conf.bak-\(stamp)")
			try? FileManager.default.copyItem(at: url, to: copy)
			backup = copy
		}
		do {
			try config.write(to: url, atomically: true, encoding: .utf8)
		} catch {
			throw Failure.unwritable(url.path)
		}
		return backup
	}

	/// Whether the bar is off in the config as it stands.
	public static func isStatusHidden() -> Bool {
		((try? read()) ?? "").isEmpty ? false : hidesStatus(in: (try? read()) ?? "")
	}

	/// Turns the bar off — or back on — in the config and in the server that is
	/// running now.
	///
	/// Both, because either alone is half an answer: the file decides what
	/// happens next time, and the running server is what somebody is looking at.
	@discardableResult
	public static func setStatusHidden(_ hidden: Bool) throws -> URL? {
		let config = try read()
		let updated = hidden ? adding(to: config) : removing(from: config)
		let backup = updated == config ? nil : try write(updated)
		applyToRunningServer(hidden: hidden)
		return backup
	}

	/// Tells a server that is already running, so nobody has to reload.
	private static func applyToRunningServer(hidden: Bool) {
		guard let tmux = Executables.locate("tmux") else { return }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: tmux)
		// Global, matching what the config says, rather than one session's:
		// the config line is `set -g`, and the two should not disagree.
		process.arguments = hidden
			? ["set-option", "-g", "status", "off"]
			: ["set-option", "-gu", "status"]
		// Rather than inheriting it, for the reason in `TmuxSocketPath`.
		process.environment = TmuxSocketPath.environment
		process.standardError = FileHandle.nullDevice
		process.standardOutput = FileHandle.nullDevice
		try? process.run()
		process.waitUntilExit()
	}
}
