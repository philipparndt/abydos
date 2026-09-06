import AbydosKit
import AppKit

/// The hex editor from the launch options: `--hex "goto:0x10,select:4,inspect"`.
///
/// Each step does what the control does and the report says what the status
/// bar, the inspector and the outline say afterwards — so a screenshot has a
/// transcript beside it and a claim can be checked without one.
extension HexEditorController {
	/// Performs the steps in order, waiting for the ones that run behind the
	/// editor, and returns the report.
	func performForTesting(_ steps: String) async -> String {
		var report: [String] = ["HEX \(url.lastPathComponent) \(document.count) bytes"]
		for raw in steps.split(separator: ",", omittingEmptySubsequences: true) {
			let step = raw.trimmingCharacters(in: .whitespaces)
			let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
			let verb = parts[0]
			let argument = parts.count > 1 ? parts[1] : ""
			switch verb {
			case "goto":
				let complaint = goTo(argument)
				report.append("goto \(argument): \(complaint ?? statusText)")
			case "select":
				let count = Int(argument) ?? 0
				editor.select(editor.caret..<(editor.caret + count))
				report.append("select \(count): \(statusText)")
			case "find", "findtext", "findnumber":
				let kind: HexBar.FindKind = verb == "find" ? .hex : verb == "findtext" ? .text : .number
				bar.setKind(kind)
				bar.setQuery(argument)
				await searchTask?.value
				await Task.yield()
				let shown = matches.prefix(8).map { String(format: "0x%llX", $0) }.joined(separator: " ")
				report.append("\(verb) \(argument): \(bar.status) at \(shown)\(matches.count > 8 ? " …" : "")")
			case "next":
				stepMatch(by: 1)
				report.append("next: \(statusText) · \(bar.status)")
			case "previous":
				stepMatch(by: -1)
				report.append("previous: \(statusText) · \(bar.status)")
			case "type":
				focusEditor()
				editor.activeColumn = .hex
				editor.insertText(argument)
				let edited = document.editedRanges.map { String(format: "0x%llX+%lld", $0.lowerBound, $0.count) }
				report.append("type \(argument): \(statusText) dirty=\(isDirty) edited=\(edited)")
			case "typetext":
				editor.activeColumn = .text
				editor.insertText(argument)
				report.append("typetext \(argument): \(statusText) dirty=\(isDirty)")
			case "insert":
				editor.setInsertMode(!editor.insertMode)
				bar.setInsert(editor.insertMode)
				report.append("insert: \(editor.insertMode ? "on" : "off") · \(statusText)")
			case "delete":
				editor.deleteBackward()
				report.append("delete: \(statusText) count=\(document.count)")
			case "undo":
				editor.undo.undo()
				report.append("undo: dirty=\(isDirty) count=\(document.count)")
			case "bytes":
				let range = editor.selection ?? editor.caret..<min(document.count, editor.caret + 16)
				let hex = document.bytes(in: range).map { String(format: "%02X", $0) }.joined(separator: " ")
				report.append("bytes \(String(format: "0x%llX", range.lowerBound)): " + hex)
			case "inspect":
				// The field label comes from the parse, which runs behind the
				// editor; the report waits for it so "field:" is an answer.
				await structureTask?.value
				await Task.yield()
				let readings = inspector.readingsForTesting
				let shown = ByteValues.Field.allCases.map { "\($0.name)=\(readings[$0.name] ?? "")" }
				report.append("inspect \(order.said): " + shown.joined(separator: " · "))
				report.append("field: \(fieldLabelText ?? "none")")
			case "order":
				order = argument == "big" ? .big : .little
				inspector.setOrder(order)
				refreshInspectorValues()
				report.append("order: \(order.said)")
			case "value":
				// value:<field>=<text>
				let pieces = argument.split(separator: "=", maxSplits: 1).map(String.init)
				if pieces.count == 2,
				   let field = ByteValues.Field.allCases.first(where: { $0.name.lowercased() == pieces[0].lowercased() }) {
					let complaint = write(pieces[1], as: field)
					report.append("value \(argument): \(complaint ?? "written") · \(statusText)")
				} else {
					report.append("value \(argument): no such field")
				}
			case "checksum":
				let wanted = argument.lowercased().replacingOccurrences(of: "-", with: "")
				if let kind = Checksum.allCases.first(where: { $0.rawValue == wanted }) {
					toggleChecksum(kind)
					await checksumTasks[kind]?.value
					await Task.yield()
					report.append("checksum \(kind.name): \(inspector.checksumsForTesting[kind.name] ?? "") (\(checksumScopeText))")
				} else {
					report.append("checksum \(argument): unknown")
				}
			case "digests":
				// What every checksum row says now, stale ones included.
				let rows = Checksum.allCases.map { "\($0.name)=\(inspector.checksumsForTesting[$0.name] ?? "")" }
				report.append("digests: " + rows.joined(separator: " · "))
			case "structure":
				await structureTask?.value
				await Task.yield()
				report.append("structure: \(inspector.structure.headerText)")
				report.append(contentsOf: inspector.structure.rowsForTesting.prefix(60).map { "  " + $0 })
			case "entropy":
				await statisticsTask?.value
				await Task.yield()
				let done = statistics.completedBlocks
				let mean = statistics.blocks.compactMap { $0 }.map(\.entropy).reduce(0, +) / Double(max(1, done))
				report.append(String(
					format: "entropy: %d/%d blocks of %d bytes, mean %.2f bits",
					done, statistics.blocks.count, statistics.blockSize, mean
				))
				report.append(contentsOf: inspector.notesForTesting.map { "  note: " + $0 })
			case "session":
				// What the session file would keep of this tab, and a restore of
				// it into this same tab, so the round trip is one step.
				let state = sessionState
				report.append("session: caret=\(state.caret) rows=\(state.bytesPerRow) encoding=\(state.encoding) order=\(state.order) claude=\(state.claudeFields.count) fields, summary \(state.claudeSummary?.count ?? 0) chars, prompt \(state.claudePrompt?.count ?? 0) chars")
				editor.moveCaret(to: 0, extending: false)
				claudeNodes = []
				claudeSummary = nil
				restore(state)
				report.append("restored: \(statusText) claude=\(claudeNodes.count) fields, summary \(claudeSummary?.count ?? 0) chars")
			case "structure-click":
				await structureTask?.value
				await Task.yield()
				report.append("structure-click \(argument): " + inspector.structure.clickRowForTesting(Int(argument) ?? 0))
			case "value-frames":
				report.append(contentsOf: inspector.valueFramesForTesting.prefix(6).map { "  " + $0 })
			case "structure-focus":
				await structureTask?.value
				await Task.yield()
				report.append("structure-focus: " + inspector.structure.focusForTesting())
			case "structure-key":
				report.append("structure-key \(argument): " + inspector.structure.pressForTesting(argument) + " · \(statusText)")
			case "entropy-hover":
				// The pointer at a fraction of the curve's width, without a pointer.
				await statisticsTask?.value
				inspector.curve.layoutSubtreeIfNeeded()
				inspector.curve.hover(atFraction: CGFloat(Double(argument) ?? 0.5))
				report.append("entropy-hover \(argument): \(inspector.curve.hoverTextForTesting ?? "nothing under the pointer")")
			case "strings":
				await stringsTask?.value
				await Task.yield()
				if !argument.isEmpty { inspector.setStringsFilter(argument) }
				report.append("strings \(argument): \(strings.strings.count) found, \(strings.unlisted) unlisted")
				report.append(contentsOf: inspector.stringsForTesting.prefix(10).map { "  " + $0 })
			case "ask":
				report.append("ask: available=\(HexAnalysis.isAvailable)")
				toggleAsk()
				await askTask?.value
				await Task.yield()
				if let failure = lastFailure {
					report.append("  failed: \(failure)")
				} else {
					report.append("  summary: \(claudeSummary ?? "none")")
					let rows = inspector.structure.rowsForTesting.filter { $0.contains("[claude]") }
					report.append(contentsOf: rows.map { "  " + $0 })
					report.append("  prompt: \(lastPrompt?.count ?? 0) characters")
				}
			case "save":
				do {
					try save()
					report.append("save: written, dirty=\(isDirty)")
				} catch {
					report.append("save: failed: \(error)")
				}
			case "rows":
				editor.bytesPerRow = Int(argument) ?? 16
				bar.setBytesPerRow(editor.bytesPerRow)
				report.append("rows: \(editor.bytesPerRow)")
			case "minimap":
				report.append("minimap: \(minimap.count) bytes, viewport \(minimap.visibleRange), \(minimap.matches.count) ticks, mode \(minimap.mode)")
			case "inspector":
				setInspectorShown(!isInspectorShown)
				report.append("inspector: \(isInspectorShown ? "shown" : "hidden")")
			case "copy":
				let shape = HexEditorView.CopyShape.allCases.first { $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "").hasSuffix(argument.lowercased()) } ?? .hex
				editor.copy(as: shape)
				report.append("copy \(shape.rawValue): \(NSPasteboard.general.string(forType: .string) ?? "")")
			case "paste":
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(argument, forType: .string)
				editor.paste(from: NSPasteboard.general)
				report.append("paste \(argument): \(statusText)")
			case "wait":
				try? await Task.sleep(nanoseconds: UInt64((Double(argument) ?? 0.5) * 1_000_000_000))
				report.append("wait \(argument)")
			default:
				report.append("\(step): unknown step")
			}
		}
		return report.joined(separator: "\n")
	}
}
