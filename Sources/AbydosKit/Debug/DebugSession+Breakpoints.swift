import Foundation

/// Breakpoints: what somebody has set, and telling the adapter about them.
///
/// The set outlives any session — lines are marked in an editor before anything
/// is running and survive a program ending — so this is about two things at
/// once: the list itself, and the DAP rule that a file's breakpoints are always
/// sent whole rather than one at a time.
extension DebugSession {
	// MARK: - Breakpoints

	/// Toggles a breakpoint, syncing to the adapter when one is attached.
	public func toggleBreakpoint(file: String, line: Int) {
		// Keyed by the real path, which is how the adapter names files.
		let file = FilePath.canonical(file)
		var list = breakpoints[file] ?? []
		if let index = list.firstIndex(where: { $0.line == line }) {
			list.remove(at: index)
		} else {
			list.append(Breakpoint(file: file, line: line))
			list.sort { $0.line < $1.line }
		}
		breakpoints[file] = list.isEmpty ? nil : list
		onMain { [weak self] in self?.onBreakpointsChanged?() }

		if isActive { Task { await syncBreakpoints(for: file) } }
	}

	/// Takes over a set of breakpoints whole, before anything is running.
	///
	/// Replaying them as toggles loses everything a `Breakpoint` carries beyond
	/// its line: `toggleBreakpoint` builds a fresh one, which is enabled, so a
	/// breakpoint somebody had switched off came back on the moment a session
	/// started — and it was sent to the adapter, and it stopped there.
	///
	/// Nothing is verified here. Whether a line can be bound is a fact about a
	/// program that is not running yet; the adapter says so when the
	/// breakpoints are sent.
	public func adopt(_ incoming: [String: [Breakpoint]]) {
		var adopted: [String: [Breakpoint]] = [:]
		for (file, list) in incoming {
			let canonical = FilePath.canonical(file)
			adopted[canonical] = list
				.sorted { $0.line < $1.line }
				.map { breakpoint in
					var copy = breakpoint
					copy.isVerified = false
					return copy
				}
		}
		breakpoints = adopted
		onMain { [weak self] in self?.onBreakpointsChanged?() }
	}

	/// Turns a breakpoint off without losing it, or on again.
	///
	/// A disabled breakpoint stays where it was put, and is not sent to the
	/// adapter: it is a breakpoint somebody wants back later, not one they want
	/// now. Xcode's click on the marker means exactly this.
	public func setBreakpoint(file: String, line: Int, enabled: Bool) {
		let file = FilePath.canonical(file)
		guard var list = breakpoints[file], let index = list.firstIndex(where: { $0.line == line })
		else { return }

		guard list[index].isEnabled != enabled else { return }
		list[index].isEnabled = enabled
		// Nothing is bound while it is off; saying otherwise would draw it as
		// though execution could still stop there.
		if !enabled { list[index].isVerified = false }
		breakpoints[file] = list
		onMain { [weak self] in self?.onBreakpointsChanged?() }

		if isActive { Task { await syncBreakpoints(for: file) } }
	}

	/// Records where a file's breakpoints sit in the code, keyed by line.
	///
	/// Nothing the adapter needs to hear about: the anchor is how a breakpoint
	/// finds its line again after something else rewrites the file, which is
	/// this side's problem entirely. Nothing on screen changes either, so no
	/// redraw is asked for.
	public func setBreakpointAnchors(
		inFile file: String,
		_ anchors: [Int: BreakpointAnchors.Anchor]
	) {
		let file = FilePath.canonical(file)
		guard var list = breakpoints[file] else { return }
		for index in list.indices {
			guard let anchor = anchors[list[index].line] else { continue }
			list[index].anchor = anchor
		}
		breakpoints[file] = list
	}

	/// Puts a file's breakpoints where the text moved them.
	public func replaceBreakpoints(inFile file: String, with list: [Breakpoint]) {
		let file = FilePath.canonical(file)
		breakpoints[file] = list.isEmpty ? nil : list
		onMain { [weak self] in self?.onBreakpointsChanged?() }
		if isActive { Task { await syncBreakpoints(for: file) } }
	}

	/// Takes a breakpoint away — what dragging one out of the gutter means.
	public func removeBreakpoint(file: String, line: Int) {
		let file = FilePath.canonical(file)
		guard var list = breakpoints[file], let index = list.firstIndex(where: { $0.line == line })
		else { return }

		list.remove(at: index)
		breakpoints[file] = list.isEmpty ? nil : list
		onMain { [weak self] in self?.onBreakpointsChanged?() }

		if isActive { Task { await syncBreakpoints(for: file) } }
	}

	/// Turns every breakpoint off except the one named, or every one back on.
	///
	/// "Disable other breakpoints" is the thing somebody reaches for when one
	/// of thirty is the interesting one and stopping at the rest is in the way.
	public func setOtherBreakpoints(file: String, line: Int, enabled: Bool) {
		let keep = FilePath.canonical(file)
		for (path, list) in breakpoints {
			var updated = list
			for index in updated.indices where !(path == keep && updated[index].line == line) {
				updated[index].isEnabled = enabled
				if !enabled { updated[index].isVerified = false }
			}
			breakpoints[path] = updated
		}
		onMain { [weak self] in self?.onBreakpointsChanged?() }

		guard isActive else { return }
		let files = Array(breakpoints.keys)
		Task { for path in files { await syncBreakpoints(for: path) } }
	}

	/// Gives a breakpoint a condition, a hit count, or a message to log.
	///
	/// Passing nil for everything makes it an ordinary breakpoint again.
	public func setBreakpointOptions(
		file: String,
		line: Int,
		condition: String?,
		hitCondition: String?,
		logMessage: String?
	) {
		let file = FilePath.canonical(file)
		guard var list = breakpoints[file], let index = list.firstIndex(where: { $0.line == line })
		else { return }

		list[index].condition = condition?.isEmpty == true ? nil : condition
		list[index].hitCondition = hitCondition?.isEmpty == true ? nil : hitCondition
		list[index].logMessage = logMessage?.isEmpty == true ? nil : logMessage
		breakpoints[file] = list
		onMain { [weak self] in self?.onBreakpointsChanged?() }

		if isActive { Task { await syncBreakpoints(for: file) } }
	}

	public func breakpoint(file: String, line: Int) -> Breakpoint? {
		breakpoints[FilePath.canonical(file)]?.first { $0.line == line }
	}

	public func breakpoints(inFile file: String) -> [Breakpoint] {
		breakpoints[file] ?? []
	}

	public func hasBreakpoint(file: String, line: Int) -> Bool {
		breakpoints[file]?.contains { $0.line == line } ?? false
	}

	public var isActive: Bool {
		switch state {
		case .idle, .terminated: return false
		default: return true
		}
	}

	/// Sends the breakpoints for one file. DAP replaces the whole set per file,
	/// so they are always sent together rather than incrementally.
	func syncBreakpoints(for file: String) async {
		let lines = (breakpoints[file] ?? []).filter(\.isEnabled).map(\.wireFormat)
		let response = try? await client.request("setBreakpoints", arguments: [
			"source": ["path": file],
			"breakpoints": lines,
			"sourceModified": false,
		])

		// The adapter reports which it could actually bind — one entry per
		// breakpoint that was sent, so the answers line up with the enabled
		// ones rather than with the whole list.
		guard let verified = response?["breakpoints"] as? [[String: Any]] else { return }
		var list = breakpoints[file] ?? []
		let sent = list.indices.filter { list[$0].isEnabled }
		for (position, index) in sent.enumerated() where position < verified.count {
			list[index].isVerified = verified[position]["verified"] as? Bool ?? false
		}
		breakpoints[file] = list
		onMain { [weak self] in self?.onBreakpointsChanged?() }
	}
}
