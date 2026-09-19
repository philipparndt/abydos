import AbydosKit
import AppKit

/// Exporting a song as WAV, FLAC or M4A, the mix alone or with its stems.
///
/// Asked for on 2026-09-14, once `mat` wrote more than WAV (4143e44): the pane
/// is where a song is listened to, so it is where the file that leaves the
/// project is made. **Beside the song, like a diagram's picture**: `neon.flac`
/// and `neon stems/`, through the pane's own cache, so exporting a song the
/// pane has just rendered reads every layer back and costs the encode.
///
/// **It asks before it replaces.** A picture beside a diagram is always the
/// diagram's; a `neon.wav` beside `neon.song` may be a recording the song plays
/// from, and an export that silently overwrote it would destroy the input to
/// make the output.
extension SongPreviewView {
	/// The Export button's menu, and the right-click one: the mix, then the
	/// mix with its stems, each in every format.
	func exportMenu() -> NSMenu {
		let menu = NSMenu(title: "Export")
		menu.autoenablesItems = false
		let formats = Self.formatsSupported(by: executable)
		for withStems in [false, true] {
			if withStems { menu.addItem(.separator()) }
			for format in SongRender.ExportFormat.allCases {
				let title = (withStems ? "Mix and Stems as " : "Mix as ") + format.title
				let item = NSMenuItem(title: title, action: #selector(exportChosen(_:)), keyEquivalent: "")
				item.target = self
				item.representedObject = format.rawValue + (withStems ? ":stems" : "")
				let possible = executable != nil && !isExporting && (format == .wav || formats)
				item.isEnabled = possible
				if format != .wav, !formats, executable != nil {
					item.toolTip = "This mat writes only WAV. Update it: cargo install --path crates/mat-cli"
				}
				menu.addItem(item)
			}
		}
		return menu
	}

	func showExportMenu() {
		let menu = exportMenu()
		menu.popUp(positioning: nil, at: NSPoint(x: 0, y: exportButton.bounds.height + 2), in: exportButton)
	}

	@objc private func exportChosen(_ sender: NSMenuItem) {
		guard let code = sender.representedObject as? String else { return }
		let parts = code.split(separator: ":")
		guard let format = parts.first.flatMap({ SongRender.ExportFormat(rawValue: String($0)) }) else { return }
		export(as: format, withStems: parts.count > 1)
	}

	/// Renders the song into the export's files.
	///
	/// - Parameters:
	///   - confirm: ask before replacing what is there; a driven run over a
	///     scratch copy says no.
	///   - then: told a line saying what happened, once it has.
	func export(
		as format: SongRender.ExportFormat, withStems: Bool, confirm: Bool = true, then: ((String) -> Void)? = nil
	) {
		guard let executable, !isExporting else { then?("not exported: nothing to run, or an export is running"); return }
		let export = SongRender.export(of: url, as: format, withStems: withStems)
		if confirm, !export.replaces.isEmpty {
			let alert = NSAlert()
			let names = export.replaces.map(\.lastPathComponent)
			alert.messageText = "Replace \(names.joined(separator: " and "))?"
			alert.informativeText = "\(names.count == 1 ? "It" : "They") will be written again from \(url.lastPathComponent)."
			alert.addButton(withTitle: "Replace")
			alert.addButton(withTitle: "Cancel")
			guard alert.runModal() == .alertFirstButtonReturn else { then?("not exported: cancelled"); return }
		}

		let line = SongRender.exportCommand(
			executable: executable, song: url, export: export, cache: SongRender.cacheDirectory(for: url)
		)
		let invocation = UserShell.invocation(for: line)
		let process = Process()
		process.executableURL = URL(fileURLWithPath: invocation.executable)
		process.arguments = invocation.arguments
		process.currentDirectoryURL = url.deletingLastPathComponent()
		let output = Pipe()
		let errors = Pipe()
		process.standardOutput = output
		process.standardError = errors
		process.standardInput = FileHandle.nullDevice
		guard ToolProcesses.shared.adopt(process, as: "Song export") else {
			Toast.post("Could not export \(url.lastPathComponent)", detail: ToolProcesses.shared.tooManyMessage)
			then?("not exported: too many tools running")
			return
		}

		isExporting = true
		exportButton.isEnabled = false
		let what = format.title + (withStems ? " with stems" : "")
		Toast.post("Exporting \(url.lastPathComponent) as \(what)…", kind: .information)
		let song = url
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			var said = ""
			do {
				try process.run()
				let captured = ProcessPipes.drainText(process, out: output, err: errors)
				said = captured.stdout + "\n" + captured.stderr
			} catch {
				said = error.localizedDescription
			}
			ToolProcesses.shared.forget(process)
			let status = process.endedStatus ?? -1
			let report = said
			DispatchQueue.main.async {
				self?.isExporting = false
				self?.exportButton.isEnabled = true
				guard status == 0, FileManager.default.fileExists(atPath: export.mix.path) else {
					Toast.post("Could not export \(song.lastPathComponent)", detail: SongRender.complaint(in: report))
					then?("failed: " + SongRender.complaint(in: report))
					return
				}
				let stems = export.stems.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) }?
					.filter { $0.hasSuffix("." + format.rawValue) }.count
				let detail = stems.map { "And \($0) stems in \(export.stems?.lastPathComponent ?? "")." }
				Toast.post(Toast(
					kind: .information, title: "Exported \(export.mix.lastPathComponent)", detail: detail,
					actionTitle: "Reveal in Finder",
					action: { NSWorkspace.shared.activateFileViewerSelecting([export.mix]) }
				))
				then?("wrote \(export.mix.lastPathComponent)" + (stems.map { " and \($0) stems" } ?? ""))
			}
		}
	}

	/// Whether this `mat` writes FLAC and M4A, asked once per executable.
	static func formatsSupported(by executable: String?) -> Bool {
		guard let executable else { return false }
		return SongRender.supportsFormats(help: renderHelp(of: executable))
	}

	/// Whether this `mat` writes the mix while it renders, so the pane can play
	/// a song before it is rendered. Asked, because a `mat` from before a5f7d05
	/// refuses `--stream` and with it the render.
	static func streamingSupported(by executable: String?) -> Bool {
		guard let executable else { return false }
		return SongRender.supportsStreaming(help: renderHelp(of: executable))
	}

	/// What `mat render --help` says, asked once per executable.
	static func renderHelp(of executable: String) -> String {
		if let known = renderHelpText[executable] { return known }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = ["render", "--help"]
		let output = Pipe()
		process.standardOutput = output
		process.standardError = FileHandle.nullDevice
		var help = ""
		if (try? process.run()) != nil {
			let data = output.fileHandleForReading.readDataToEndOfFile()
			process.waitUntilExit()
			help = String(decoding: data, as: UTF8.self)
		}
		renderHelpText[executable] = help
		return help
	}
}

/// What each `mat` said for itself, for the life of the process.
@MainActor private var renderHelpText: [String: String] = [:]
