import AbydosKit
import AppKit

/// Cutting a sound to a selection: `i` and `o` mark it, *Keep* and *Delete*
/// cut it, ⌘Z and ⇧⌘Z step through cuts, and ⌘S writes the file.
///
/// Asked for on 2026-09-14. **A cut writes a working copy, never the file** —
/// a sound tab had no edited state before this, and a cut applied straight to
/// disk with no way back would be the one gesture in it that could lose
/// somebody's work. See `AudioCut` for the frames and the files.
extension AudioFileView {
	/// Where working copies go: one directory for every sound tab, a file per
	/// cut, deleted when its tab closes.
	static var workingDirectory: URL {
		FileManager.default.temporaryDirectory.appendingPathComponent("abydos-audio-edits", isDirectory: true)
	}

	var isDirty: Bool { cutState.working != nil }

	/// The file the tab is playing and drawing: the last cut, or the file.
	var source: URL { cutState.working ?? url }

	// MARK: - Marks

	func markIn() {
		cutState.inPoint = currentSeconds
		selectionChanged()
	}

	func markOut() {
		cutState.outPoint = currentSeconds
		selectionChanged()
	}

	/// `i` twice: the selection starts where it ended, so the next one carries
	/// on from the last — which is how a recording is cut into samples one
	/// after another. `o` twice is the same going backwards: the selection ends
	/// where it began.
	///
	/// Asked for 2026-09-16: "ii should set the start to the end and oo the end
	/// to the current start (ii can be used to continue with the next sample)".
	/// The other mark is let go, so what is left is one mark at the boundary and
	/// the next press of the other key makes the new selection.
	func carryOnFromSelection() {
		guard let out = cutState.outPoint else { return }
		cutState.inPoint = out
		cutState.outPoint = nil
		seek(to: out)
		selectionChanged()
	}

	func carryBackFromSelection() {
		guard let start = cutState.inPoint else { return }
		cutState.outPoint = start
		cutState.inPoint = nil
		seek(to: start)
		selectionChanged()
	}

	func clearSelection() {
		cutState.inPoint = nil
		cutState.outPoint = nil
		selectionChanged()
	}

	/// The frames between the marks, when both are set and they differ.
	var selectedFrames: Range<Int>? {
		guard let a = cutState.inPoint, let b = cutState.outPoint, let playback else { return nil }
		let frames = AudioCut.frames(from: a, to: b, sampleRate: playback.sampleRate, frameCount: Int(playback.frameCount))
		return frames.isEmpty ? nil : frames
	}

	func selectionChanged() {
		canvas.marks = (cutState.inPoint, cutState.outPoint)
		let frames = selectedFrames
		keepButton.isHidden = frames == nil
		deleteButton.isHidden = frames == nil
		saveAsButton.isHidden = frames == nil
		if let frames, let playback, playback.sampleRate > 0 {
			let seconds = Double(frames.count) / playback.sampleRate
			selectionLabel.stringValue = "selected " + Self.clock(seconds, milliseconds: true)
		} else if let mark = cutState.inPoint ?? cutState.outPoint {
			selectionLabel.stringValue = (cutState.inPoint != nil ? "in " : "out ") + Self.clock(mark, milliseconds: true)
		} else {
			selectionLabel.stringValue = ""
		}
		selectionLabel.isHidden = selectionLabel.stringValue.isEmpty
	}

	// MARK: - Cutting

	func keepSelection(then: (() -> Void)? = nil) {
		guard let frames = selectedFrames else { then?(); return }
		apply(.keep(frames), playheadAfter: 0, then: then)
	}

	func deleteSelection(then: (() -> Void)? = nil) {
		guard let frames = selectedFrames, let playback else { then?(); return }
		apply(.delete(frames), playheadAfter: Double(frames.lowerBound) / playback.sampleRate, then: then)
	}

	/// Renders the cut into a new working copy off the main thread, and puts
	/// it in the tab.
	private func apply(_ cut: AudioCut, playheadAfter: Double, then: (() -> Void)?) {
		guard !cutState.isCutting else { then?(); return }
		cutState.isCutting = true
		let from = source
		// Taken here, on the main actor, and handed to the write: the view's
		// statics are the main actor's to read.
		let directory = Self.workingDirectory
		let destination = directory.appendingPathComponent(UUID().uuidString + ".caf")
		Task { @MainActor [weak self] in
			let result = await Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
				do {
					try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
					try cut.write(from: from, to: destination)
					return .success(())
				} catch {
					return .failure(error)
				}
			}.value
			guard let self else { return }
			self.cutState.isCutting = false
			switch result {
			case .success:
				self.cutState.undo.append(self.cutState.working)
				self.discard(self.cutState.redo)
				self.cutState.redo = []
				self.cutState.inPoint = nil
				self.cutState.outPoint = nil
				self.show(working: destination, playhead: playheadAfter)
			case .failure(let error):
				try? FileManager.default.removeItem(at: destination)
				Toast.post("Could not cut \(self.url.lastPathComponent)", detail: error.localizedDescription, kind: .warning)
			}
			then?()
		}
	}

	/// Puts a working copy — or the file itself, for nil — in the tab: the
	/// player, the drawing, the dot.
	func show(working: URL?, playhead: Double) {
		let wasPlaying = playback?.isPlaying == true
		let looping = playback?.isLooping == true
		playback?.tearDown()
		if wasPlaying { onPlayingChanged?(false) }
		cutState.working = working
		playback = try? AudioPlayback(url: source)
		playback?.isLooping = looping
		playback?.onStopped = { [weak self] in self?.playingChanged() }
		playback?.seek(toSeconds: playhead)
		canvas.playhead = playhead
		selectionChanged()
		reanalyse()
		onDirtyChanged?()
	}

	// MARK: - Undo

	@objc func undo(_ sender: Any?) {
		guard let previous = cutState.undo.popLast() else { return }
		cutState.redo.append(cutState.working)
		show(working: previous, playhead: currentSeconds)
	}

	@objc func redo(_ sender: Any?) {
		guard let next = cutState.redo.popLast() else { return }
		cutState.undo.append(cutState.working)
		show(working: next, playhead: currentSeconds)
	}

	// MARK: - Saving

	/// Writes the last cut over the file in its own format. Throws, and keeps
	/// the edit, when it cannot — an MP3, a full disk.
	func save() throws {
		guard let working = cutState.working else { return }
		try AudioCut.save(working, over: url)
		let finished = (cutState.undo + cutState.redo).compactMap { $0 } + [working]
		let playhead = min(currentSeconds, playback?.duration ?? 0)
		cutState = CutState()
		// The file now, and the working copies after: the player has the last
		// one open until `show` lets it go.
		show(working: nil, playhead: playhead)
		for copy in finished {
			try? FileManager.default.removeItem(at: copy)
		}
	}

	/// Writes the selection to a file of its own, leaving this one alone.
	///
	/// Asked for 2026-09-16: "when selecting a part in a wav file, it should be
	/// also possible to save as (save the selection to a new file)". The name
	/// offered carries where in the file the selection starts, so cutting a
	/// recording into samples numbers them as it goes.
	func saveSelectionAs() {
		guard let frames = selectedFrames, let playback, playback.sampleRate > 0 else { return }
		let start = Double(frames.lowerBound) / playback.sampleRate
		let panel = NSSavePanel()
		panel.title = "Save Selection"
		panel.nameFieldStringValue = AudioCut.name(of: url, at: start)
		panel.directoryURL = url.deletingLastPathComponent()
		panel.canCreateDirectories = true
		panel.isExtensionHidden = false
		let source = self.source
		panel.beginSheetModal(for: window ?? NSApp.keyWindow ?? NSWindow()) { [weak self] answer in
			guard answer == .OK, let destination = panel.url else { return }
			self?.write(frames: frames, of: source, to: destination)
		}
	}

	/// The frames, written. Said aloud either way: a file written somewhere
	/// else is a thing somebody has to be able to find.
	func write(frames: Range<Int>, of source: URL, to destination: URL) {
		do {
			try AudioCut.keep(frames).write(from: source, toNew: destination)
			Toast.post(Toast(
				kind: .information, title: "Wrote \(destination.lastPathComponent)",
				detail: "The selection, \(Self.clock(Double(frames.count) / (playback?.sampleRate ?? 48_000), milliseconds: true)) of it.",
				actionTitle: "Reveal in Finder",
				action: { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
			))
			lastWrittenForTesting = destination
		} catch {
			Toast.post(
				"Could not write \(destination.lastPathComponent)",
				detail: error.localizedDescription, kind: .warning
			)
		}
	}

	/// The working copies a tab is finished with.
	func discard(_ copies: [URL?]) {
		for copy in copies.compactMap({ $0 }) where copy != cutState.working {
			try? FileManager.default.removeItem(at: copy)
		}
	}

	/// Every working copy this tab made, for when it closes.
	func discardAllWorkingCopies() {
		let all = (cutState.undo + cutState.redo + [cutState.working]).compactMap { $0 }
		for copy in all {
			try? FileManager.default.removeItem(at: copy)
		}
	}

	// MARK: - Driving

	/// Steps, comma-separated: `seek:<s>`, `in`, `out`, `in-again`, `out-again`,
	/// `clear`, `keep`, `delete`, `undo`, `redo`, `save`, `save-as:<path>`,
	/// `report`. Cuts are waited for.
	func performStepsForTesting(_ steps: [String], then: @escaping () -> Void) {
		guard let step = steps.first else { return then() }
		let rest = Array(steps.dropFirst())
		let next = { [weak self] in self?.performStepsForTesting(rest, then: then) ?? then() }
		switch step {
		case "in": markIn()
		case "out": markOut()
		// `ii` and `oo` from the keyboard.
		case "in-again": carryOnFromSelection()
		case "out-again": carryBackFromSelection()
		case "clear": clearSelection()
		case "keep": return keepSelection { next() }
		case "delete": return deleteSelection { next() }
		case "undo": undo(nil)
		case "redo": redo(nil)
		case "save":
			do {
				try save()
				print("AUDIO-STEP save: written")
			} catch {
				print("AUDIO-STEP save: \(error.localizedDescription)")
			}
		case "report":
			print("AUDIO-STEP " + cutReportForTesting)
		default:
			if step.hasPrefix("seek:"), let seconds = Double(step.dropFirst("seek:".count)) {
				seekForTesting(seconds: seconds)
			} else if step.hasPrefix("save-as:") {
				// The panel is not driven; where it would have written is.
				let path = String(step.dropFirst("save-as:".count))
				if let frames = selectedFrames {
					write(frames: frames, of: source, to: URL(fileURLWithPath: path))
					print("AUDIO-STEP save-as: \(URL(fileURLWithPath: path).lastPathComponent)")
				} else {
					print("AUDIO-STEP save-as: nothing selected")
				}
			} else {
				print("AUDIO-STEP unknown step \(step)")
			}
		}
		fflush(stdout)
		// After an undo or a save the drawing is read again; the next step
		// waits for it, as a person would.
		whenAnalysed { next() }
	}

	var cutReportForTesting: String {
		let frames = playback.map { Int($0.frameCount) } ?? 0
		let onDisk = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
		return "\(url.lastPathComponent) frames=\(frames)"
			+ String(format: " duration=%.3f playhead=%.3f", playback?.duration ?? 0, currentSeconds)
			+ " dirty=\(isDirty) undo=\(cutState.undo.count) redo=\(cutState.redo.count)"
			+ " selection=\(selectedFrames.map { "\($0.lowerBound)..<\($0.upperBound)" } ?? "none")"
			+ " label=\"\(selectionLabel.stringValue)\" buttons=\(keepButton.isHidden ? "hidden" : "shown")"
			+ " save-as=\(saveAsButton.isHidden ? "hidden" : "shown")"
			+ " bytes-on-disk=\(onDisk) source=\(source == url ? "file" : "working copy")"
			+ " marks=\(cutState.inPoint.map { String(format: "%.3f", $0) } ?? "-")"
			+ "/\(cutState.outPoint.map { String(format: "%.3f", $0) } ?? "-")"
			+ " wrote=\(lastWrittenForTesting?.lastPathComponent ?? "-")"
	}
}

/// What a sound tab has cut and not saved.
struct CutState {
	var inPoint: Double?
	var outPoint: Double?
	/// The last cut, or nil when the tab shows the file as it is on disk.
	var working: URL?
	/// Earlier states, the last one on top; nil in the stack is the file.
	var undo: [URL?] = []
	var redo: [URL?] = []
	var isCutting = false
}
