import Foundation

/// Watch expressions: adding them, removing them, and re-evaluating every one
/// of them in the frame that is selected now.
///
/// The list itself and the lock around it stay with the session, because more
/// than one refresh can be in the air at once. What is here is what is done to
/// it, which is where the rule lives that a watch is matched back up by id and
/// never by index.
extension DebugSession {
	public func addWatch(_ expression: String) {
		let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		withWatches { $0.append(WatchExpression(expression: trimmed)) }
		onMain { [weak self] in self?.onWatchesChanged?() }
		Task { await refreshWatches() }
	}

	public func removeWatch(id: UUID) {
		withWatches { $0.removeAll { $0.id == id } }
		onMain { [weak self] in self?.onWatchesChanged?() }
	}

	public func removeAllWatches() {
		withWatches { $0.removeAll() }
		onMain { [weak self] in self?.onWatchesChanged?() }
	}

	/// Re-evaluates every watch in the selected frame.
	///
	/// After every stop and every frame change, because a watch that still
	/// shows the value from two stops ago is worse than no watch at all.
	public func refreshWatches() async {
		// A snapshot, since the list can be added to or emptied while this runs.
		// What comes back is applied to the watch it was asked about, by id, and
		// dropped if that watch has gone.
		let current = watches
		guard !current.isEmpty else { return }
		guard let frame = selectedFrameID else {
			withWatches {
				for index in $0.indices {
					$0[index].value = nil
					$0[index].failed = false
					// Nothing is stopped, so the handle is about nothing. The
					// row stays open and fills in again at the next stop.
					$0[index].variablesReference = 0
					$0[index].children = nil
				}
			}
			onMain { [weak self] in self?.onWatchesChanged?() }
			return
		}

		for watch in current {
			let response = try? await client.request("evaluate", arguments: [
				"expression": watch.expression,
				"frameId": frame,
				"context": "watch",
			])
			if let result = response?["result"] as? String {
				updateWatch(id: watch.id) {
					$0.value = result
					$0.failed = false
					$0.variablesReference = response?["variablesReference"] as? Int ?? 0
					// The handle is new, so anything held under the old one is
					// no longer about anything. Still open, and asked again on
					// the way back up.
					$0.children = nil
				}
			} else {
				// An expression that does not compile here is not an error to
				// report; it is simply out of scope in this frame, which is
				// worth saying quietly rather than clearing the row.
				updateWatch(id: watch.id) {
					$0.failed = true
					$0.value = "not available here"
					$0.variablesReference = 0
					$0.children = nil
				}
			}
		}
		onMain { [weak self] in self?.onWatchesChanged?() }
	}
}
