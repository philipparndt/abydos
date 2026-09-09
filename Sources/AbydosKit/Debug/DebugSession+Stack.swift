import Foundation

/// The stack, the scopes and the variables under them.
///
/// Everything here is re-read after a stop or a change of frame, and the order
/// matters: threads, then frames, then the top frame's scopes, then whatever is
/// open under them. A view that renders what the session holds is correct only
/// because this sequence is.
extension DebugSession {
	// MARK: - Stack and variables

	/// Re-reads the stack after a stop, then the top frame's variables.
	func refreshStack() async {
		guard let thread = currentThreadID else { return }
		selectedThreadID = thread
		await refreshThreads()
		await refreshStack(thread: thread, reportStop: true)
	}

	/// Reads one thread's stack.
	///
	/// `reportStop` is false when the user picked another goroutine: the editor
	/// should follow the stack, but nothing has stopped, so the execution
	/// marker must not move as though it had.
	func refreshStack(thread: Int, reportStop: Bool) async {
		let response = try? await client.request("stackTrace", arguments: [
			"threadId": thread,
			"startFrame": 0,
			"levels": 50,
		])
		let frames = (response?["stackFrames"] as? [[String: Any]]) ?? []

		stackFrames = frames.map { frame in
			let source = frame["source"] as? [String: Any]
			return StackFrame(
				id: frame["id"] as? Int ?? 0,
				name: frame["name"] as? String ?? "?",
				file: source?["path"] as? String,
				line: frame["line"] as? Int ?? 0
			)
		}
		let top = stackFrames.first
		onMain { [weak self] in
			guard let self else { return }
			self.onStackChanged?()
			// Opening the file is AppKit work, so it belongs on this side of
			// the hop with everything else.
			if reportStop, let file = top?.file, let line = top?.line {
				for observer in self.stoppedObservers { observer(file, line) }
			}
		}

		if let top { await selectFrame(id: top.id) }
	}

	/// Loads the scopes and top-level variables for a frame.
	public func selectFrame(id: Int) async {
		selectedFrameID = id
		// A watch means something different in each frame, so it is re-read
		// whenever the frame changes rather than only when execution stops.
		defer { Task { await refreshWatches() } }

		let response = try? await client.request("scopes", arguments: ["frameId": id])
		let raw = (response?["scopes"] as? [[String: Any]]) ?? []

		var loaded: [Scope] = []
		for entry in raw {
			var scope = Scope(
				name: entry["name"] as? String ?? "Scope",
				variablesReference: entry["variablesReference"] as? Int ?? 0
			)
			// Registers are noise in a Go session; skip them by default.
			if scope.name.lowercased().contains("registers") { continue }
			scope.variables = await variables(reference: scope.variablesReference)
			loaded.append(scope)
		}

		scopes = loaded
		// The frame's own file and line: a variable is in scope in the frame it
		// belongs to, so every other file gets nothing — the same rule the
		// execution marker follows.
		let frame = stackFrames.first { $0.id == id }
		if let file = frame?.file, let line = frame?.line {
			inlineValues = InlineValueSet(
				file: file, line: line, values: InlineValues.byName(loaded)
			)
		} else {
			inlineValues = nil
		}
		sayVariablesChanged()
	}

	/// Children of a variable container.
	public func variables(reference: Int) async -> [Variable] {
		childrenRequestsForTesting += 1
		guard reference > 0 else { return [] }
		let response = try? await client.request("variables", arguments: ["variablesReference": reference])
		let raw = (response?["variables"] as? [[String: Any]]) ?? []

		return raw.map { entry in
			Variable(
				name: entry["name"] as? String ?? "",
				value: entry["value"] as? String ?? "",
				type: entry["type"] as? String,
				variablesReference: entry["variablesReference"] as? Int ?? 0
			)
		}
	}

	/// Expands or collapses a variable, loading children on first expand.
	/// Opens or closes a watched value, or something inside one.
	///
	/// **An empty path is the watch itself**, which is what a scope's variables
	/// never need: a variable is always reached through its scope, so its path
	/// has at least one step in it. A watch is a root of its own, and the whole
	/// reason its values could not be browsed is that there was nothing to
	/// address that root with.
	///
	/// Below the root it is the same walk as a scope's, so it is the same code:
	/// `evaluate` hands back a `variablesReference` exactly as a variable does,
	/// and everything under it is ordinary variables.
	public func toggleWatchExpansion(id: UUID, path: [Int] = []) async {
		guard let watch = watches.first(where: { $0.id == id }) else { return }

		if path.isEmpty {
			guard watch.isExpandable else { return }
			let opening = !watch.isExpanded
			// Fetched outside the lock: this is a request to the debugger and
			// waiting for one with the watch list held would stop every other
			// refresh in the session.
			var fetched: [Variable]?
			if opening, watch.children == nil, watch.isExpandable {
				fetched = await variables(reference: watch.variablesReference)
			}
			updateWatch(id: id) {
				$0.isExpanded = opening
				if let fetched { $0.children = fetched }
			}
		} else {
			let updated = await toggle(in: watch.children ?? [], path: path)
			updateWatch(id: id) { $0.children = updated }
		}
		onMain { [weak self] in self?.onWatchesChanged?() }
	}

	/// Fills in a watch that is open but has nothing under it yet.
	///
	/// After a refresh: the values are new, the handle is new, and the tree is
	/// still showing the row opened. Separate from the toggle above because it
	/// must not close anything — it is not somebody pressing a triangle, it is
	/// the tree catching up.
	public func loadOpenWatchChildren() async {
		for watch in watches where watch.isExpanded && watch.children == nil && watch.isExpandable {
			let fetched = await variables(reference: watch.variablesReference)
			updateWatch(id: watch.id) { $0.children = fetched }
		}
		onMain { [weak self] in self?.onWatchesChanged?() }
	}

	/// Puts in a watch as a stopped debugger would have answered it.
	///
	/// The expansion rules are about state, not about the wire: what they have
	/// to get right is that a row stays open across a refresh and that the
	/// values under it do not. Driving a real adapter to assert that would be a
	/// live test of something that is not live.
	///
	/// **Deliberately not `addWatch`, and that is not tidiness.** `addWatch`
	/// starts a refresh of its own, and with nothing running that refresh clears
	/// every reference — so a test that added a watch and then said what it
	/// evaluated to was racing a task it did not know it had started. It passed
	/// alone and failed in the suite, which is the worst way for a test to be
	/// wrong.
	public func seedWatchForTesting(
		expression: String, reference: Int = 0, children: [Variable]? = nil
	) -> UUID {
		let watch = WatchExpression(
			expression: expression, value: "…", variablesReference: reference, children: children
		)
		withWatches { $0.append(watch) }
		return watch.id
	}

	public func setWatchChildrenForTesting(id: UUID, children: [Variable]) {
		updateWatch(id: id) { $0.children = children }
	}

	public func toggleExpansion(scopeIndex: Int, path: [Int]) async {
		guard scopes.indices.contains(scopeIndex) else { return }
		var scope = scopes[scopeIndex]
		scope.variables = await toggle(in: scope.variables, path: path)
		scopes[scopeIndex] = scope
		sayVariablesChanged()
	}

	private func toggle(in variables: [Variable], path: [Int]) async -> [Variable] {
		guard let index = path.first, variables.indices.contains(index) else { return variables }
		var updated = variables
		var variable = updated[index]

		if path.count == 1 {
			variable.isExpanded.toggle()
			// Children are fetched once, on first expansion.
			if variable.isExpanded, variable.children == nil {
				variable.children = await self.variables(reference: variable.variablesReference)
			}
		} else {
			variable.children = await toggle(in: variable.children ?? [], path: Array(path.dropFirst()))
		}

		updated[index] = variable
		return updated
	}

	/// Evaluates an expression in the selected frame.
	public func evaluate(_ expression: String) async -> String? {
		guard let frame = selectedFrameID else { return nil }
		let response = try? await client.request("evaluate", arguments: [
			"expression": expression,
			"frameId": frame,
			"context": "watch",
		])
		return response?["result"] as? String
	}
}
