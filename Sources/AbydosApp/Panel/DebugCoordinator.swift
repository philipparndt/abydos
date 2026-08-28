import AppKit
import AbydosKit

/// Breakpoints, and the line a stopped program is on.
///
/// A breakpoint outlives the session it was set for — that is most of what
/// makes it a breakpoint rather than a command — so it is kept here, per file,
/// whether or not anything is running. `pendingBreakpoints` is that record;
/// `executionMarker` is where the program stopped; `anchoringWork` is the
/// debounce that keeps a breakpoint on the line it was put on while somebody
/// types above it.
///
/// It runs no programs. Starting one is the run coordinator's, and this object
/// is told what it needs to know.
@MainActor
final class DebugCoordinator {
	private let editor: EditorAreaController
	private let panel: BottomPanel

	/// The session, when there is one. Owned by the panel that shows it.
	var debugSession: () -> DebugSession? = { nil }
	/// The project the window is showing, which is whose breakpoints these are.
	var projectRoot: () -> URL? = { nil }
	/// The window a breakpoint's options sheet is put on.
	var hostWindow: () -> NSWindow? = { nil }
	/// Written where a project's breakpoints are remembered.
	var onRememberBreakpoints: () -> Void = {}
	/// The stepping verbs, which belong to whoever is driving the session.
	var onDebugContinue: (Any?) -> Void = { _ in }
	var onDebugStepOver: (Any?) -> Void = { _ in }
	var onDebugStepInto: (Any?) -> Void = { _ in }
	var onDebugStepOut: (Any?) -> Void = { _ in }
	var onWatchFromEditor: (String) -> Void = { _ in }

	init(editor: EditorAreaController, panel: BottomPanel) {
		self.editor = editor
		self.panel = panel
	}

	/// Where execution is stopped, for saying so.
	var executionMarker: (file: String, line: Int)?

	/// Looks at where the debugger stopped, without moving it.
	func inspectDebugStateForTesting() {
		let stoppedAt = executionMarker.map { "\(($0.file as NSString).lastPathComponent):\($0.line)" }
			?? "not stopped"
		print("INSPECT: stopped at \(stoppedAt)")
		// What the editor is drawing beside the code, which is the half of a
		// stop that used to be readable only in the panel.
		print("VALUES:\n\(editor.inlineValueReportForTesting())")
		panel.exerciseDebugExtrasForTesting()

		// And the editor's way in, which is the one somebody actually uses:
		// select an expression, ask to watch it, and the answer should be in
		// front of them rather than behind the console tab.
		onWatchFromEditor("answer * 3")
		let pane = panel.activeDebugPane
		let added = pane?.debugSession.watches.contains { $0.expression == "answer * 3" } ?? false
		print("EDITORWATCH: added=\(added) showsConsole=\(pane?.showsConsoleForTesting ?? true)")
	}

	/// Puts a condition on a breakpoint before the program runs.
	func setBreakpointConditionForTesting(line: Int, condition: String) {
		guard let url = editor.activeGroup?.activeTabURL else { return }
		setBreakpointOptions(
			file: FilePath.canonical(url), line: line,
			condition: condition, hitCondition: nil, logMessage: nil
		)
		print("COND: \(condition) on line \(line)")
	}

	/// Walks the debugger a step at a time, saying where it stopped.
	func reportDebugStepForTesting(step: Int) {
		guard let session = debugSession() else {
			print("DEBUG: no session yet (step \(step))")
			return
		}
		let where_ = executionMarker.map { "\(($0.file as NSString).lastPathComponent):\($0.line)" }
			?? "not stopped"
		print("DEBUG: step \(step) state=\(session.isActive ? "active" : "inactive") at \(where_)")
		// What is beside the code at this step, which is the claim that the
		// values follow execution rather than being drawn once and left.
		print("VALUES:\n\(editor.inlineValueReportForTesting())")

		if step == 0 {
			panel.writeDebugToolbarImageForTesting(to: "build/debug-toolbar.png")
		}

		// Menu commands, the same ones the function keys send.
		switch step {
		case 0, 1: onDebugStepOver(nil)
		case 2: onDebugStepInto(nil)
		case 3: onDebugStepOut(nil)
		// The last step lets it run to the end, so there is an exit code to
		// report rather than one we killed before it had one.
		default: onDebugContinue(nil)
		}

		if step >= 3 {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
				guard let self else { return }
				self.panel.writeDebugToolbarImageForTesting(to: "build/exit-toolbar.png")
				let state = self.debugSession().map { String(describing: $0.state) } ?? "none"
				print("EXIT: code=\(self.debugSession()?.exitCode.map(String.init) ?? "none") state=\(state)")
			fflush(stdout)
			}
		}
	}

	/// Breakpoints set before a session exists, so they survive between runs.
	/// Breakpoints set before a session exists, with whatever conditions they
	/// were given. Whole breakpoints rather than line numbers, or a condition
	/// put on one before launching — which is when somebody actually sets them
	/// — would be dropped on the way in.
	var pendingBreakpoints: [String: [Breakpoint]] = [:]

	/// The breakpoints worth writing down: the running session's if there is
	/// one, since it holds what the adapter has confirmed, and the pending set
	/// otherwise.
	func breakpointsToRemember() -> [String: [Breakpoint]] {
		currentDebugSession?.breakpoints ?? pendingBreakpoints
	}

	/// The running session, when it is this project's.
	///
	/// Everything below asks the session first and the pending set second, and
	/// a session outlives the project switch that leaves it running — so asked
	/// plainly, a debug pane still running in the project you came from answers
	/// for the one you are in now. Its breakpoints are then drawn in this
	/// project's gutter and written into this project's session file, as this
	/// project's own.
	///
	/// The pane knows which project it is debugging, and a subproject scope
	/// counts as inside it: a session launched in one module of a repository is
	/// still that repository's.
	///
	/// Nil root means nobody has said which project this is, and then the old
	/// answer is the only one there is.
	private var currentDebugSession: DebugSession? {
		guard let pane = panel.activeDebugPane else { return nil }
		guard let root = projectRoot() else { return pane.debugSession }
		return FilePath.isInside(pane.debuggedProject, of: root) ? pane.debugSession : nil
	}

	/// Whether a session handed in from outside is the one this project started.
	private func belongsToCurrentProject(_ session: DebugSession) -> Bool {
		projectRoot() == nil || currentDebugSession === session
	}

	/// The breakpoints of a project the window has just arrived at, in place of
	/// whatever it was holding.
	///
	/// Including none, for a project that has never had one. Nothing used to
	/// take the old set away — the gutter was filled from the session file only
	/// *if it was empty* — so the first project worked in kept its breakpoints
	/// across every switch after it, and each project visited then wrote them
	/// down as its own. A `screencasts` checkout with no debugger ever pointed
	/// at it held breakpoints in an unrelated Java application and in a Go
	/// example, and would have gone on collecting one from every project ever
	/// debugged in that window.
	func adoptBreakpoints(_ breakpoints: [String: [Breakpoint]]) {
		pendingBreakpoints = breakpoints
		publishPendingBreakpoints()
	}

	func toggleBreakpoint(file: URL, line: Int) {
		// The debugger reports files by their real path, so breakpoints are
		// keyed the same way or they are set against a name nothing else uses.
		let path = FilePath.canonical(file)

		// Anchored either way: what it was put on is only knowable now, while the
		// file still looks the way it did when it was clicked.
		defer { scheduleAnchoring(inFile: file) }

		if let session = currentDebugSession {
			session.toggleBreakpoint(file: path, line: line)
			syncBreakpointsToEditor(from: session)
			onRememberBreakpoints()
			return
		}

		// No session yet: remember it, and hand the set over when one starts.
		var list = pendingBreakpoints[path] ?? []
		if let index = list.firstIndex(where: { $0.line == line }) {
			list.remove(at: index)
		} else {
			list.append(Breakpoint(file: path, line: line))
			list.sort { $0.line < $1.line }
		}
		pendingBreakpoints[path] = list.isEmpty ? nil : list
		publishPendingBreakpoints()
		onRememberBreakpoints()
	}

	/// A file's breakpoints, from the session when one is running and from the
	/// pending set otherwise — the two are kept in step, so either answers.
	func breakpoints(inFile path: String) -> [Breakpoint] {
		currentDebugSession?.breakpoints(inFile: path) ?? pendingBreakpoints[path] ?? []
	}

	/// Puts a file's breakpoints back, wherever they are being kept.
	func replaceBreakpoints(inFile path: String, with list: [Breakpoint]) {
		if let session = currentDebugSession {
			session.replaceBreakpoints(inFile: path, with: list)
			syncBreakpointsToEditor(from: session)
			return
		}
		pendingBreakpoints[path] = list.isEmpty ? nil : list
		publishPendingBreakpoints()
	}

	/// Anchoring waiting for the file to stop changing, per file.
	private var anchoringWork: [String: DispatchWorkItem] = [:]

	func scheduleAnchoring(inFile url: URL) {
		let path = FilePath.canonical(url)
		anchoringWork[path]?.cancel()
		let work = DispatchWorkItem { [weak self] in
			self?.anchoringWork[path] = nil
			self?.anchorBreakpoints(inFile: url)
		}
		anchoringWork[path] = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
	}

	private func applyAnchors(_ anchors: [Int: BreakpointAnchors.Anchor], inFile path: String) {
		if let session = currentDebugSession {
			session.setBreakpointAnchors(inFile: path, anchors)
			pendingBreakpoints = session.breakpoints
			return
		}
		guard var list = pendingBreakpoints[path] else { return }
		for index in list.indices {
			guard let anchor = anchors[list[index].line] else { continue }
			list[index].anchor = anchor
		}
		pendingBreakpoints[path] = list
	}

	/// Puts a file's breakpoints back on the code they were set on, after
	/// something else rewrote the file.
	///
	/// Nothing reported an edit — an agent, a `git checkout` and a formatter all
	/// just leave a different file behind — so there is nothing to shift the
	/// lines by. Each breakpoint goes to wherever its anchor now points.
	func reanchorBreakpoints(inFile url: URL) {
		let path = FilePath.canonical(url)
		guard !breakpoints(inFile: path).isEmpty, let document = editor.document(for: url) else {
			return
		}

		// Any anchoring still pending was scheduled against the text this file
		// has just stopped holding; letting it run would pin the breakpoints to
		// the new file at the old lines, which is the thing being undone here.
		anchoringWork[path]?.cancel()
		anchoringWork[path] = nil

		// The reload abandoned the old tree and queued a parse of the new text;
		// this query is behind it on the same queue, so it waits for the parse
		// rather than reading an empty outline and concluding every breakpoint
		// has lost its symbol.
		document.symbols { [weak self] symbols in
			guard let self else { return }
			let lines = (0..<document.lineCount).map { document.lineText($0) }
			self.replaceBreakpoints(
				inFile: path,
				with: BreakpointAnchors.resolve(
					// Read again rather than captured: the parse took a moment,
					// and a breakpoint set in it is one somebody just clicked.
					breakpoints: self.breakpoints(inFile: path), in: symbols, lines: lines
				)
			)
		}
	}

	/// Turns a breakpoint off, or on again, wherever it is kept.
	func setBreakpoint(file: URL, line: Int, enabled: Bool) {
		let path = FilePath.canonical(file)
		if let session = currentDebugSession {
			session.setBreakpoint(file: path, line: line, enabled: enabled)
			syncBreakpointsToEditor(from: session)
			return
		}
		guard var list = pendingBreakpoints[path],
		      let index = list.firstIndex(where: { $0.line == line })
		else { return }
		list[index].isEnabled = enabled
		if !enabled { list[index].isVerified = false }
		pendingBreakpoints[path] = list
		publishPendingBreakpoints()
	}

	/// Takes a breakpoint away — dragging it out of the gutter, or Delete.
	func deleteBreakpoint(file: URL, line: Int) {
		let path = FilePath.canonical(file)
		if let session = currentDebugSession {
			session.removeBreakpoint(file: path, line: line)
			syncBreakpointsToEditor(from: session)
			return
		}
		guard var list = pendingBreakpoints[path] else { return }
		list.removeAll { $0.line == line }
		pendingBreakpoints[path] = list.isEmpty ? nil : list
		publishPendingBreakpoints()
	}

	/// Silences every breakpoint but one, or brings them all back.
	func setOtherBreakpoints(file: URL, line: Int, enabled: Bool) {
		let path = FilePath.canonical(file)
		if let session = currentDebugSession {
			session.setOtherBreakpoints(file: path, line: line, enabled: enabled)
			syncBreakpointsToEditor(from: session)
			return
		}
		for (candidate, list) in pendingBreakpoints {
			var updated = list
			for index in updated.indices where !(candidate == path && updated[index].line == line) {
				updated[index].isEnabled = enabled
				if !enabled { updated[index].isVerified = false }
			}
			pendingBreakpoints[candidate] = updated
		}
		publishPendingBreakpoints()
	}

	/// Draws the breakpoints that exist before anything is running.
	func publishPendingBreakpoints() {
		var mapped: [String: [Int: CodeView.BreakpointMark]] = [:]
		var conditional: [String: Set<Int>] = [:]
		for (file, list) in pendingBreakpoints {
			mapped[file] = Dictionary(uniqueKeysWithValues: list.map { ($0.line, Self.mark(for: $0)) })
			conditional[file] = Set(list.filter(\.isConditional).map(\.line))
		}
		editor.setBreakpoints(mapped)
		editor.setConditionalBreakpoints(conditional)
	}

	func syncBreakpointsToEditor(from session: DebugSession) {
		// Not for a session running behind the window in the project it came
		// from: it is still reporting its breakpoints as they are verified, and
		// each report would replace the gutter of the project on screen and be
		// kept as that project's to write down.
		guard belongsToCurrentProject(session) else { return }

		var mapped: [String: [Int: CodeView.BreakpointMark]] = [:]
		var conditional: [String: Set<Int>] = [:]
		for (file, list) in session.breakpoints {
			mapped[file] = Dictionary(uniqueKeysWithValues: list.map { ($0.line, Self.mark(for: $0)) })
			conditional[file] = Set(list.filter(\.isConditional).map(\.line))
		}
		// Kept, so they survive the session ending and are there for the next
		// one — conditions included.
		pendingBreakpoints = session.breakpoints
		editor.setBreakpoints(mapped)
		editor.setConditionalBreakpoints(conditional)
	}

	/// Applies breakpoint options, to the session if there is one and to the
	/// pending set either way.
	func setBreakpointOptions(
		file path: String,
		line: Int,
		condition: String?,
		hitCondition: String?,
		logMessage: String?
	) {
		if let session = currentDebugSession {
			session.setBreakpointOptions(
				file: path, line: line,
				condition: condition, hitCondition: hitCondition, logMessage: logMessage
			)
			syncBreakpointsToEditor(from: session)
			return
		}

		var list = pendingBreakpoints[path] ?? []
		if let index = list.firstIndex(where: { $0.line == line }) {
			list[index].condition = condition?.isEmpty == true ? nil : condition
			list[index].hitCondition = hitCondition?.isEmpty == true ? nil : hitCondition
			list[index].logMessage = logMessage?.isEmpty == true ? nil : logMessage
			pendingBreakpoints[path] = list
			publishPendingBreakpoints()
		}
	}

	/// Asks what a breakpoint should do, and tells the session.
	///
	/// A breakpoint you have to sit and press Continue at four hundred times
	/// because the interesting case is the last one is not much of a
	/// breakpoint; a condition is what makes it one.
	func editBreakpoint(file: URL, line: Int) {
		let path = FilePath.canonical(file)

		// Works whether or not anything is running: conditions are nearly always
		// set while writing the code, before the first launch.
		let session = currentDebugSession
		let existing = session?.breakpoint(file: path, line: line)
			?? pendingBreakpoints[path]?.first { $0.line == line }
			?? {
				// Right-clicking a line with no breakpoint sets one there
				// first: it is plainly what was meant.
				toggleBreakpoint(file: file, line: line)
				return session?.breakpoint(file: path, line: line)
					?? pendingBreakpoints[path]?.first { $0.line == line }
					?? Breakpoint(file: path, line: line)
			}()

		let sheet = BreakpointOptionsSheet(
			line: line,
			fileName: file.lastPathComponent,
			// The file's own language, so a Go condition is coloured as Go and
			// a Swift one as Swift.
			languageId: LanguageRegistry.shared.languageId(for: file) ?? "",
			existing: existing
		) { [weak self] condition, hits, message in
			self?.setBreakpointOptions(
				file: path,
				line: line,
				condition: condition,
				hitCondition: hits,
				logMessage: message
			)
		}
		// A window of its own, begun on this one. `presentAsSheet` needs a view
		// controller to present from and this window has a content view rather
		// than a controller — asking for one returns nil, and the sheet simply
		// never appeared.
		guard let window = hostWindow() else { return }
		window.beginSheet(NSWindow(contentViewController: sheet), completionHandler: nil)
	}

	/// Sets a breakpoint and turns it off, as clicking its marker does.
	func disableBreakpointForTesting(line: Int) {
		guard let url = editor.activeGroup.activeTabURL else { return }
		toggleBreakpoint(file: url, line: line)
		setBreakpoint(file: url, line: line, enabled: false)
	}

	/// Opens the breakpoint options sheet, as right-clicking the gutter does.
	func editBreakpointForTesting(line: Int) {
		guard let url = editor.activeGroup.activeTabURL else { return }
		editBreakpoint(file: url, line: line)
	}

	func toggleBreakpointForTesting(line: Int) {
		guard let url = editor.activeGroup.activeTabURL else { return }
		toggleBreakpoint(file: url, line: line)
	}

	/// Where the open file's breakpoints are and what each is anchored to.
	///
	/// Anchoring is invisible until a file is rewritten under it, and the gutter
	/// only says which line — not what the breakpoint believes it is on. This
	/// says both, so a rewrite can be checked rather than looked at.
	func breakpointReportForTesting() -> String {
		guard let url = editor.activeGroup.activeTabURL else { return "no file open" }
		let list = breakpoints(inFile: FilePath.canonical(url))
		guard !list.isEmpty else { return "no breakpoints" }

		return list.map { breakpoint in
			guard let anchor = breakpoint.anchor else { return "line \(breakpoint.line): unanchored" }
			let symbol = anchor.path.isEmpty ? "(no symbol)" : anchor.path.joined(separator: ".")
			return "line \(breakpoint.line): \(symbol)+\(anchor.offset) \"\(anchor.text)\""
		}
		.joined(separator: "\n")
	}

	/// What the gutter needs to know about a breakpoint.
	private static func mark(for breakpoint: Breakpoint) -> CodeView.BreakpointMark {
		CodeView.BreakpointMark(
			isEnabled: breakpoint.isEnabled,
			isVerified: breakpoint.isVerified,
			isConditional: breakpoint.isConditional
		)
	}

	/// Records where a file's breakpoints sit in its code.
	///
	/// A line number is enough right up until something rewrites the file
	/// without saying what it changed. What survives that is the symbol the
	/// breakpoint is inside and the line it is on, which can only be read while
	/// the file still looks the way the breakpoint was set against.
	func anchorBreakpoints(inFile url: URL) {
		let path = FilePath.canonical(url)
		let lines = breakpoints(inFile: path).map(\.line)
		guard !lines.isEmpty, let document = editor.document(for: url) else { return }

		// The symbols come off the parser's own queue, behind whatever reparse
		// the last edit left running, so this sees the tree for the text as it
		// is now rather than an outline that is one edit behind.
		document.symbols { [weak self] symbols in
			var anchors: [Int: BreakpointAnchors.Anchor] = [:]
			for line in lines where line <= document.lineCount {
				anchors[line] = BreakpointAnchors.anchor(
					line: line,
					text: document.lineText(line - 1),
					in: symbols,
					lineCount: document.lineCount
				)
			}
			self?.applyAnchors(anchors, inFile: path)
		}
	}
}
