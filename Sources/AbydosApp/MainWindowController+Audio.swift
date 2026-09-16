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
	/// `--audio-steps`: marks, cuts, undo, save — see `performStepsForTesting`.
	var steps: String?
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
			if let steps = asked.steps {
				pane.performStepsForTesting(steps.split(separator: ",").map(String.init)) {
					print("AUDIO-STEP done")
					fflush(stdout)
				}
			}
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

	/// `--song <steps>`: the front song pane, driven once its first render has
	/// landed, then one step at a time. Steps, separated by commas:
	///
	///  * `report` — the pane's line; `wait:<s>` — that long before the next step.
	///  * `mix`, `stems` — which view; `wave`, `spectrum`, `both` — what is drawn.
	///  * `off:<layer>`, `on:<layer>` — a stem's switch; `wobble:<layer>` — a
	///    press on it that drags a pixel, as real mouse events.
	///  * `export:<wav|flac|m4a>[:stems]` — an export beside the song, waited
	///    for; `export-menu` — what the Export menu offers.
	///  * `caret:<line>` — the caret in the source, which lights the stem it is in.
	///  * `play`, `loop`, `seek:<s>`.
	///  * `edit:<line>:<text>` — that line of the file on disk replaced, the way
	///    a save would leave it, so the pane renders again; `rendered:<n>` —
	///    waits until that many renders have finished.
	func driveSongForTesting(_ steps: String, attempt: Int = 0) {
		guard let pane = editor.songPreview else {
			if attempt < 20 {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
					self?.driveSongForTesting(steps, attempt: attempt + 1)
				}
			} else {
				let groups = editor.groups
				print("SONG: no song pane — " + (groups.isEmpty ? "no editor group"
					: groups.map(\.activeTabDescriptionForTesting).joined(separator: " | ")))
				fflush(stdout)
			}
			return
		}
		let list = steps.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
		pane.whenRendered { [weak self, weak pane] in
			guard let self, let pane else { return }
			self.songStep(list[...], on: pane)
		}
	}

	private func songStep(_ steps: ArraySlice<String>, on pane: SongPreviewView) {
		guard let step = steps.first else { return }
		let rest = steps.dropFirst()
		var delay = 0.0
		switch step {
		case "report":
			print(pane.reportForTesting)
			fflush(stdout)
		case "mix": pane.show(.mix)
		case "stems": pane.show(.stems)
		case "wave", "spectrum", "both": pane.showForTesting(mode: step)
		case "play": pane.playForTesting()
		case "loop": pane.loopForTesting()
		case _ where step.hasPrefix("open:"):
			// `open:<path>` — another file, relative to the song, in the same
			// group: an included file's tab in front while the song plays.
			if let song = editor.activeGroup?.activeTab?.url {
				let path = String(step.dropFirst("open:".count))
				editor.open(fileURL: song.deletingLastPathComponent().appendingPathComponent(path), focusEditor: false)
			}
		case "reopen":
			// The tab closed and the file opened again — a new pane, which is
			// what going to another file and back makes. The rest of the steps
			// run on the new pane, once it has a render, which is the point:
			// whether it needed one.
			guard let url = editor.activeGroup?.activeTab?.url else { return }
			_ = editor.activeGroup?.closeTab(showing: url)
			editor.open(fileURL: url, focusEditor: true)
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				self?.driveSongForTesting(rest.joined(separator: ","))
			}
			return
		default:
			let parts = step.split(separator: ":", maxSplits: 2).map(String.init)
			switch parts.first {
			case "wait": delay = Double(parts.dropFirst().first ?? "") ?? 0
			case "off": pane.setLane(parts.dropFirst().first ?? "", enabled: false)
			case "on": pane.setLane(parts.dropFirst().first ?? "", enabled: true)
			case "wobble": pane.wobbleSwitchForTesting(layer: parts.dropFirst().first ?? "")
			case "export":
				// `export:<wav|flac|m4a>` or `export:flac:stems`, without the
				// replace question — a driven run exports over a scratch copy —
				// and the next step waits for the export to finish.
				let format = SongRender.ExportFormat(rawValue: parts.dropFirst().first ?? "") ?? .wav
				pane.export(as: format, withStems: parts.count > 2, confirm: false) { [weak self] said in
					print("SONG-EXPORT \(format.rawValue): \(said)")
					fflush(stdout)
					self?.songStep(rest, on: pane)
				}
				return
			case "timeline":
				// `timeline:<line>`, 1-based: what the gutter holds for that line.
				let line = Int(parts.dropFirst().first ?? "") ?? 1
				let codeView = editor.activeGroup?.activeTab?.codeView
				let timeline = codeView?.timeline
				let fractions = timeline?.fractions(line: line - 1)
					.map { String(format: "%.3f-%.3f", $0.lowerBound, $0.upperBound) } ?? []
				print("LINE-TIMELINE line=\(line) column=\(timeline == nil ? "none" : "shown")"
					+ " gutter=\(Int(codeView?.gutterWidth ?? 0)) lit=[\(fractions.joined(separator: " "))]"
					+ " loop=\(pane.loopRangeForTesting)"
					+ " playhead=\(codeView?.timelinePlayhead.map { String(format: "%.2f", $0) } ?? "none")"
					+ " tick-pixel=\(codeView?.drawnPlayheadPixel.map(String.init) ?? "none")"
					+ " code=\(timeline?.timeCode(line: line - 1) ?? "none")"
					+ " columns=\(codeView.map { "codes:\($0.showsTimeCodes ? "on" : "off"),bars:\($0.showsTimelineBars ? "on" : "off")" } ?? "none")"
					+ " sounding=[\((codeView?.soundingLines ?? []).sorted().map { String($0 + 1) }.joined(separator: ","))]"
					+ " stopped=\(codeView?.songStoppedLine.map { String($0 + 1) } ?? "none")"
					+ " file=\(editor.activeGroup?.activeTab?.url.lastPathComponent ?? "none")"
					+ " song=\(timeline?.song.flatMap { URL(string: $0)?.lastPathComponent } ?? "none")"
					+ " files=\(timeline?.files.count ?? 0)"
					+ " notes=\(timeline?.notes[line - 1].map { "\($0.notes.count)x\($0.passes.count)" } ?? "none")"
					+ " playing=[\((codeView?.playingNotes ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key + 1):" + $0.value.map { "\($0.lowerBound)-\($0.upperBound)" }.joined(separator: "+") }.joined(separator: " "))]"
					+ " pane-stopped=\(pane.stoppedLineForTesting.map { String($0 + 1) } ?? "none")"
					+ " summary=\"\(timeline?.summary(line: line - 1) ?? "none")\"")
				fflush(stdout)
			case "timeline-click":
				// `timeline-click:<line>:<fraction>` — a press and release on that
				// line's bar at that fraction of it, as real mouse events; with a
				// third number, `timeline-click:<line>:<from>:<to>` drags from one
				// to the other before letting go.
				let numbers = step.split(separator: ":").dropFirst().compactMap { Double($0) }
				if numbers.count >= 2, let codeView = editor.activeGroup?.activeTab?.codeView {
					codeView.clickTimelineForTesting(line: Int(numbers[0]), at: numbers[1], dragTo: numbers.count > 2 ? numbers[2] : nil)
				}
			case "panel":
				// `panel:<points>` — the panel's height, for a capture: opening
				// the debugger restores whatever height this machine remembers.
				if let height = Double(parts.dropFirst().first ?? "") { setPanelHeightForTesting(height) }
			case "debug":
				// `debug` — the song's debug session: threads, the stack shown,
				// its scopes; `debug:continue|pause|step|stop|thread:<n>` — the
				// toolbar's verbs, through the session as the buttons send them.
				let session = bottomPanel.activeDebugSession
				switch parts.dropFirst().first {
				case "continue": session?.resume()
				case "pause": session?.pause()
				case "step": session?.stepOver()
				case "stop": session?.stop()
				case "focus":
					bottomPanel.activeDebugPane?.focusStack()
					print("SONG-DEBUG focus: stack has the keyboard = \(bottomPanel.activeDebugPane?.stackHasKeyboardForTesting ?? false)")
					fflush(stdout)
				case "key":
					// `debug:key:down` and the other arrows, to the first responder.
					let arrows: [String: (UInt16, Int)] = [
						"up": (126, NSUpArrowFunctionKey), "down": (125, NSDownArrowFunctionKey),
						"left": (123, NSLeftArrowFunctionKey), "right": (124, NSRightArrowFunctionKey),
					]
					if let arrow = arrows[parts.count > 2 ? parts[2] : ""], let scalar = UnicodeScalar(UInt32(arrow.1)),
					   let event = NSEvent.keyEvent(
						with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
						windowNumber: window?.windowNumber ?? 0, context: nil,
						characters: String(Character(scalar)), charactersIgnoringModifiers: String(Character(scalar)),
						isARepeat: false, keyCode: arrow.0
					   ) {
						window?.firstResponder?.keyDown(with: event)
					}
				case "thread":
					if let id = Int(parts.count > 2 ? parts[2] : "") { Task { await session?.selectThread(id: id) } }
				default:
					print(songDebugReportForTesting())
					fflush(stdout)
				}
			case "loop-click":
				// `loop-click:<line>[:<fraction>]` — a bar option-clicked, which
				// loops the stretch of the song where that line is heard.
				let numbers = step.split(separator: ":").dropFirst().compactMap { Double($0) }
				if let line = numbers.first, let codeView = editor.activeGroup?.activeTab?.codeView {
					codeView.clickTimelineForTesting(
						line: Int(line), at: numbers.count > 1 ? numbers[1] : 0.5, dragTo: nil, option: true
					)
				}
			case "timecode-click":
				// `timecode-click:<line>` — a press on that line's time code.
				if let line = Int(parts.dropFirst().first ?? ""), let codeView = editor.activeGroup?.activeTab?.codeView {
					codeView.clickTimeCodeForTesting(line: line)
				}
			case "song-columns":
				// `song-columns:codes` or `song-columns:bars` — the gutter menu's toggle.
				if parts.dropFirst().first == "bars" { toggleSongTimelineBars(nil) } else { toggleSongTimeCodes(nil) }
			case "break":
				// `break:<line>` — a breakpoint made or taken away, as a click on the number does.
				if let line = Int(parts.dropFirst().first ?? ""), let url = editor.activeGroup?.activeTab?.url {
					debug.toggleBreakpoint(file: url, line: line)
				}
			case "export-menu":
				let items = pane.exportMenu().items.filter { !$0.isSeparatorItem }
				print("SONG-EXPORT menu: " + items.map { "\($0.title)\($0.isEnabled ? "" : " (disabled)")" }.joined(separator: " | "))
				fflush(stdout)
			case "seek": pane.seekForTesting(seconds: Double(parts.dropFirst().first ?? "") ?? 0)
			case "caret":
				if let line = Int(parts.dropFirst().first ?? ""),
				   let codeView = editor.activeGroup?.activeTab?.codeView {
					codeView.reveal(line: line)
				}
			case "edit":
				if parts.count == 3, let line = Int(parts[1]),
				   let url = editor.activeGroup?.activeTab?.url,
				   let text = try? String(contentsOf: url, encoding: .utf8) {
					var lines = text.components(separatedBy: "\n")
					if lines.indices.contains(line - 1) {
						lines[line - 1] = parts[2]
						try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
					}
				}
			case "rendered":
				// Polled rather than waited on: a render that never comes would
				// otherwise leave the run hanging, and the report after the
				// timeout says how many there were.
				let wanted = Int(parts.dropFirst().first ?? "") ?? 0
				waitForSongRenders(wanted, on: pane, tries: 0) { [weak self] in
					self?.songStep(rest, on: pane)
				}
				return
			default:
				print("SONG: unknown step \(step)")
				fflush(stdout)
			}
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + delay) { [weak self] in
			self?.songStep(rest, on: pane)
		}
	}

	private func waitForSongRenders(_ wanted: Int, on pane: SongPreviewView, tries: Int, then: @escaping () -> Void) {
		if pane.runsForTesting >= wanted, !pane.reportForTesting.contains("state=rerendering") || tries >= 240 {
			pane.whenRendered(then)
			return
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
			self?.waitForSongRenders(wanted, on: pane, tries: tries + 1, then: then)
		}
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
