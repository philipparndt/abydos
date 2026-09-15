import AppKit
import AbydosKit

/// A song pane playing, as a program in the debugger.
///
/// Asked for on 2026-09-15: "while playing the debugger shall also be open,
/// showing the threads". Pressing play on a song opens the debug pane on a
/// session whose adapter is `SongDebugAdapter`: the tracks are its threads,
/// the toolbar's continue, pause, step and stop move the song, and a
/// breakpoint the song stops on is a stop the pane shows with a stack.
///
/// A program already being debugged is left alone — a song played beside a Go
/// session does not take its pane away.
@MainActor
final class SongDebugLink {
	let adapter: SongDebugAdapter
	let target: SongDebugTarget
	weak var session: DebugSession?
	/// The last change the adapter was told of, so a render landing or a
	/// second `playingChanged` does not say the same stop twice.
	var lastSaid = "playing"

	init(adapter: SongDebugAdapter, target: SongDebugTarget) {
		self.adapter = adapter
		self.target = target
	}
}

extension MainWindowController {
	func songPlayback(_ target: SongDebugTarget, _ change: SongPlaybackChange) {
		if let link = songDebug, let pane = target.pane, link.target.pane === pane,
		   let session = link.session, session.isActive {
			tell(link, change)
			return
		}
		guard case .playing = change, target.pane != nil else { return }
		if let active = bottomPanel.activeDebugSession, active.isActive {
			// Somebody's program: not ours to replace.
			guard let link = songDebug, link.session === active else { return }
			// Another song's session: this one takes over.
			active.stop()
		}
		startSongDebugging(target)
	}

	private func tell(_ link: SongDebugLink, _ change: SongPlaybackChange) {
		switch change {
		case .tick:
			link.adapter.tick()
		case .playing:
			guard link.lastSaid != "playing" else { return }
			link.lastSaid = "playing"
			link.adapter.continued()
		case let .stopped(line):
			let said = "stopped \(line.map(String.init) ?? "pause")"
			guard link.lastSaid != said else { return }
			link.lastSaid = said
			link.adapter.stopped(line: line)
		case .ended:
			guard link.lastSaid != "ended" else { return }
			link.lastSaid = "ended"
			link.adapter.ended()
		}
	}

	private func startSongDebugging(_ target: SongDebugTarget) {
		let program = FilePath.canonical(target.url)
		let adapter = SongDebugAdapter(
			program: program,
			timeline: target.timeline,
			lineText: target.lineText,
			now: { [weak target] in target?.pane?.currentSecondsForDebugger ?? 0 }
		)
		adapter.onContinue = { [weak target] in target?.pane?.playForDebugger() }
		adapter.onPause = { [weak target] in target?.pane?.pauseForAnother() }
		adapter.onStep = { [weak target] seconds in target?.pane?.seekFromSource(seconds) }
		adapter.onDisconnect = { [weak target] in target?.pane?.pauseForAnother() }

		setPanelVisible(true)
		guard let session = bottomPanel.startDebugging(
			adapter: DebugAdapters.song,
			executable: "",
			start: .inProcess(adapter: adapter, program: program),
			breakpoints: debug.pendingBreakpoints
		) else { return }
		wire(session)
		let link = SongDebugLink(adapter: adapter, target: target)
		link.session = session
		songDebug = link
	}

	/// What the song's debug session holds, for a driven run.
	func songDebugReportForTesting() -> String {
		guard let session = bottomPanel.activeDebugSession else { return "SONG-DEBUG: no session" }
		let threads = session.threads.map { "\($0.id):\($0.name)" }.joined(separator: " | ")
		let frames = session.stackFrames.map { "\($0.name)@\($0.line)" }.joined(separator: " > ")
		let scopes = session.scopes.map { scope in
			"\(scope.name){" + scope.variables.map { "\($0.name)=\($0.value)" }.joined(separator: ", ") + "}"
		}.joined(separator: " ")
		return "SONG-DEBUG: adapter=\(session.adapter?.id ?? "none") state=\(session.state)"
			+ " selected=\(session.selectedThreadID.map(String.init) ?? "none")"
			+ " marker=\(debug.executionMarker.map { "\(($0.file as NSString).lastPathComponent):\($0.line)" } ?? "none")"
			+ " panel=\(isPanelVisible ? "shown" : "hidden")"
			+ "\n  threads=[\(threads)]\n  frames=[\(frames)]\n  scopes=\(scopes)"
	}
}
