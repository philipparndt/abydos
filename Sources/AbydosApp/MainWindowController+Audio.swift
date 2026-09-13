import AbydosKit
import AppKit

/// What a driven run asks of the front sound tab.
struct AudioDriving {
	var view: String?
	var seek: Double?
	var zoom: (Double, Double)?
	var loop = false
	var play = false
	var wait: Double = 0
	var report = false
}

/// Driving the sound tab from a script.
extension MainWindowController {
	/// Waits for the front sound tab to finish its analysis, then does what the
	/// run asked, waits as long as it said, and says what the tab holds.
	///
	/// Waited for rather than timed: an hour-long file takes seconds, a short
	/// one a moment, and a report printed before the analysis lands says
	/// nothing about what it found.
	func driveAudioForTesting(_ asked: AudioDriving, attempt: Int = 0) {
		guard let pane = editor.activeGroup?.audioPreview else {
			if attempt < 20 {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
					self?.driveAudioForTesting(asked, attempt: attempt + 1)
				}
			} else {
				print("AUDIO: nothing showing a sound")
				fflush(stdout)
			}
			return
		}
		pane.whenAnalysed {
			if let view = asked.view { pane.showForTesting(view) }
			if let zoom = asked.zoom { pane.zoomForTesting(from: zoom.0, to: zoom.1) }
			if let seek = asked.seek { pane.seekForTesting(seconds: seek) }
			if asked.loop { pane.loopForTesting() }
			if asked.play { pane.playForTesting() }
			guard asked.report else { return }
			// After the seek, and the detail read a zoom starts, have landed.
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + asked.wait) {
				print("AUDIO: " + pane.reportForTesting)
				fflush(stdout)
			}
		}
	}

	/// `open:<path>`, `close:<name>` and `audio-tabs` in a tree script: another
	/// tab over a playing sound, and every sound tab's state — the front one's
	/// report cannot say what a tab behind it is doing.
	func audioStepForTesting(_ step: String) -> Bool {
		if step.hasPrefix("open:") {
			editor.open(fileURL: URL(fileURLWithPath: String(step.dropFirst("open:".count))), focusEditor: true)
			return true
		}
		if step.hasPrefix("close:") {
			let name = String(step.dropFirst("close:".count))
			for group in editor.groups {
				guard let tab = group.tabs.first(where: { $0.url.lastPathComponent == name }) else { continue }
				// Held past the close, so what the closing did to a sound is on
				// the line: a closed tab that is still playing is the fault.
				let pane = tab.contentView as? AudioFileView
				let closed = group.closeTab(showing: tab.url)
				print("TREE close \(name): \(closed)" + (pane.map { " — " + $0.reportForTesting } ?? ""))
				return true
			}
			print("TREE close \(name): no such tab")
			return true
		}
		// `audio-key:left`, `audio-key:shift-right` — the key, sent to the front
		// sound tab as the keyboard would, then the tab's report.
		if step.hasPrefix("audio-key:") {
			let name = String(step.dropFirst("audio-key:".count))
			guard let pane = editor.activeGroup?.audioPreview else {
				print("TREE audio-key: nothing showing a sound")
				return true
			}
			let shift = name.hasPrefix("shift-")
			let code: UInt16 = name.hasSuffix("left") ? 123 : name.hasSuffix("right") ? 124 : 49
			if let event = NSEvent.keyEvent(
				with: .keyDown, location: .zero, modifierFlags: shift ? .shift : [],
				timestamp: 0, windowNumber: window?.windowNumber ?? 0, context: nil,
				characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
			) {
				pane.keyDown(with: event)
			}
			print("TREE audio-key \(name): " + pane.reportForTesting)
			return true
		}
		guard step == "audio-tabs" else { return false }
		var lines: [String] = []
		for group in editor.groups {
			for tab in group.tabs {
				let front = group.activeTab === tab ? "front" : "behind"
				let said: String
				if let pane = tab.contentView as? AudioFileView {
					said = pane.reportForTesting
				} else if let video: VideoFileView = EditorViewController.pane(in: tab.contentView) {
					said = video.reportForTesting
				} else {
					continue
				}
				lines.append("\(tab.url.lastPathComponent) \(front) icon=\(tab.pageSymbol ?? "file") " + said)
			}
		}
		let tabs = editor.groups.flatMap(\.tabs).map(\.url.lastPathComponent).joined(separator: ", ")
		print("TREE audio-tabs [\(tabs)]:\n  " + (lines.isEmpty ? "none" : lines.joined(separator: "\n  ")))
		return true
	}

	/// Space on a sound's or a video's row: the tab showing it plays or pauses,
	/// in whichever group has it, and a file with no tab yet is opened first —
	/// provisionally, as the row's selection would have — and then played.
	func togglePlayback(of url: URL) -> Bool {
		for group in editor.groups where group.togglePlayback(showing: url) { return true }
		editor.open(fileURL: url, focusEditor: false, preview: true)
		return editor.activeGroup?.togglePlayback(showing: url) ?? false
	}
}
