import AppKit
import AbydosKit

/// The third root: what past agent sessions left behind for this project.
///
/// **The same shape as `DependencyTree`, deliberately.** A row that is not a
/// file, holding rows that are — so from a session's row down, the tree is
/// ordinary files and everything it does with a file it does with these: they
/// list lazily, they open, the arrow keys walk them, and one of them can be
/// revealed.
///
/// It is a root and not a shelf inside *Dependencies* because what a session
/// left is not what the project is made from. `DependencyTree` argues against a
/// third root and its strongest reason — that a root would have to exist before
/// anything was found to put in it, which is a permanent empty row on every
/// project — does not apply: whether a session left anything is knowable before
/// anybody asks, because the directory is either there or it is not. So this
/// follows the rule *Dependencies* follows and is absent when it holds nothing.
final class SessionNode {
	enum Row {
		/// The root. Its subtitle counts what is under it.
		case section(count: Int)
		/// One session, labelled by what was asked of it rather than by its id.
		case session(AgentSession, asked: String?)
	}

	let row: Row
	let childNodes: [SessionNode]
	/// The directory whose contents are this row's children.
	let fileRoot: FileNode?

	init(row: Row, childNodes: [SessionNode] = [], fileRoot: FileNode? = nil) {
		self.row = row
		self.childNodes = childNodes
		self.fileRoot = fileRoot
	}

	/// A name for this row that survives a rebuild.
	///
	/// The section is the only one of its kind and a session has an id, so
	/// neither needs anything cleverer — and both need *something*, because the
	/// root rebuilds whenever a session's size changes and `reloadData` throws
	/// away every row's identity. Expansion is put back by this, the way the
	/// Dependencies section's own rows are put back by theirs.
	var identity: String {
		switch row {
		case .section: return "sessions"
		case let .session(session, _): return session.id
		}
	}

	var title: String {
		switch row {
		case .section: return "Claude Sessions"
		case let .session(session, asked):
			// **What it was for, not which id it had.** A UUID identifies
			// nothing to a person; the first thing asked of a session is what
			// somebody remembers about it. Where the transcript said nothing,
			// the id's first characters are all there is — beside a date and a
			// size, which the subtitle carries either way.
			return asked ?? String(session.id.prefix(8))
		}
	}

	/// The grey half of the row.
	var subtitle: String? {
		switch row {
		case let .section(count):
			return count == 1 ? "1 session" : "\(count) sessions"
		case let .session(session, _):
			// **A session the hook spoke for says so, and nothing else does.**
			// One known only by a recent transcript is dated like any other row:
			// "active" would be a claim about somebody's attention that a
			// modification time cannot support.
			let when = session.liveness == .running ? "running" : Self.said(session.lastWrote)
			// Until the walk has happened there is nothing true to say about how
			// much is in it, so nothing is said. A subtitle that reads "0 files"
			// before the measuring pass lands is a lie for the tenth of a second
			// it is up, and this row is drawn the moment the project opens.
			guard session.isMeasured else { return when }
			// And a live session that has written nothing goes on saying nothing
			// about it, rather than "0 files" — which is the same lie, told after
			// the walk instead of before it.
			guard session.fileCount > 0 else { return when }
			let files = session.fileCount == 1 ? "1 file" : "\(session.fileCount) files"
			return "\(when)  ·  \(files)  ·  \(Self.said(session.bytes))"
		}
	}

	/// The whole of it, for a tooltip: the transcript's path is here and nowhere
	/// else, because it is worth having and is not worth opening.
	var detail: String? {
		switch row {
		case .section:
			return "What past Claude Code sessions left behind for this project."
		case let .session(session, asked):
			var lines = [asked ?? "(nothing was asked, or the transcript is gone)"]
			lines.append(session.directory.path)
			if let transcript = session.transcript {
				lines.append("transcript: " + transcript.path)
			}
			return lines.joined(separator: "\n")
		}
	}

	var isExpandable: Bool {
		switch row {
		case .section: return !childNodes.isEmpty
		case .session: return fileRoot != nil
		}
	}

	/// The session this row is, for the rows that are one.
	var session: AgentSession? {
		guard case let .session(session, _) = row else { return nil }
		return session
	}

	// MARK: - Building it

	/// The same from sessions already in hand, which is what the measuring pass
	/// hands back.
	static func build(_ sessions: [AgentSession]) -> SessionNode? {
		// Which of them are rows, and in what order: `AgentSessions.rows` is
		// where that is decided and argued, because the cheap read asks the same
		// question and there is no second right answer to it.
		let sessions = AgentSessions.rows(from: sessions)
		guard !sessions.isEmpty else { return nil }

		let rows = sessions.map { session -> SessionNode in
			SessionNode(
				row: .session(session, asked: session.transcript.flatMap {
					AgentSessions.firstRequest(in: $0)
				}),
				fileRoot: fileRoot(for: session)
			)
		}
		return SessionNode(row: .section(count: rows.count), childNodes: rows)
	}

	/// Which directory a session's row opens onto.
	///
	/// **The answer to the design's third open question.** A session that only
	/// ever wrote a scratchpad opens straight onto its files — an intermediate
	/// `scratchpad` row would be a click for nothing, since there is nothing
	/// beside it. One that also ran subagents opens onto the session's own
	/// directory, so that `scratchpad` and `tasks` are both there, named as they
	/// are on disk. Nothing is invented either way: both are directories that
	/// exist.
	private static func fileRoot(for session: AgentSession) -> FileNode? {
		// **A disclosure triangle is a claim that there is something behind
		// it**, and a session running now has an empty scratch directory until a
		// tool needs a temporary file. It gets one when it has something.
		guard session.hasAnything else { return nil }
		if session.tasks != nil {
			return FileNode(url: session.directory, isDirectory: true)
		}
		guard let scratchpad = session.scratchpad else { return nil }
		return FileNode(url: scratchpad, isDirectory: true)
	}

	/// What has to change before the root is worth redrawing.
	///
	/// The sessions, their sizes and when they last wrote — not the labels,
	/// which are read from transcripts and cost a file open each. A rebuild
	/// throws away every row's identity and collapses whatever somebody had
	/// open, so it happens when the answer has actually changed and not when it
	/// has merely been asked for again.
	var identityForRefresh: String {
		childNodes.compactMap(\.session)
			.map {
				// Liveness among them, or a row would go on saying `running`
				// after the session ended: the files did not move, so nothing
				// else here would differ and the redraw would be skipped.
				"\($0.id):\($0.liveness.rawValue):\($0.fileCount):\($0.bytes):\($0.lastWrote.timeIntervalSince1970)"
			}
			.joined(separator: "|")
	}

	/// Which sessions these are, without their sizes — what tells "the same
	/// sessions, now measured" from "a different project's".
	var identityIgnoringSize: String {
		sessions.map(\.id).joined(separator: "|")
	}

	/// The sessions this holds, for the pass that measures them.
	var sessions: [AgentSession] { childNodes.compactMap(\.session) }

	/// The session a file belongs to, for a reveal.
	func session(containing url: URL) -> SessionNode? {
		let path = FilePath.canonical(url)
		return childNodes.first { node in
			guard let root = node.fileRoot else { return false }
			let base = FilePath.canonical(root.url)
			return path == base || path.hasPrefix(base + "/")
		}
	}

	// MARK: - Saying it

	/// When, as a person would say it: the time today, the day this week, the
	/// date before that.
	private static func said(_ date: Date) -> String {
		let calendar = Calendar.current
		let formatter = DateFormatter()
		if calendar.isDateInToday(date) {
			formatter.dateFormat = "HH:mm"
			return "today " + formatter.string(from: date)
		}
		if calendar.isDateInYesterday(date) {
			formatter.dateFormat = "HH:mm"
			return "yesterday " + formatter.string(from: date)
		}
		formatter.dateFormat = "d MMM"
		return formatter.string(from: date)
	}

	/// A size, in the units somebody reads.
	private static func said(_ bytes: Int64) -> String {
		let units = ["KiB", "MiB", "GiB"]
		guard bytes >= 1024 else { return "\(bytes) B" }
		var value = Double(bytes) / 1024
		var unit = 0
		while value >= 1024, unit < units.count - 1 { value /= 1024; unit += 1 }
		return value >= 10
			? "\(Int(value.rounded())) \(units[unit])"
			: String(format: "%.1f %@", value, units[unit])
	}
}
