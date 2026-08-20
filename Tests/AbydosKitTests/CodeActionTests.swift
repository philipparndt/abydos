import Foundation
import Testing
@testable import AbydosKit

/// What a server offers, as it arrives on the wire.
///
/// The four shapes are the whole subject: an action with an edit, one with a
/// command, one with neither — which is a server waiting to be asked rather
/// than an action that does nothing — and the bare `Command` from before code
/// actions existed. Each is a different thing to do when somebody takes it, and
/// telling them apart wrong is silent: the menu works, and nothing happens.
struct CodeActionTests {
	private func edit(_ text: String) -> [String: Any] {
		[
			"documentChanges": [[
				"textDocument": ["uri": "file:///a.java", "version": 1],
				"edits": [[
					"range": [
						"start": ["line": 0, "character": 0],
						"end": ["line": 0, "character": 0],
					],
					"newText": text,
				]],
			]],
		]
	}

	@Test func readsAnActionThatCarriesItsEdit() {
		let action = LSPCodeAction(json: [
			"title": "Import 'List' (java.util)",
			"kind": "quickfix",
			"isPreferred": true,
			"edit": edit("import java.util.List;\n"),
		])
		#expect(action?.title == "Import 'List' (java.util)")
		#expect(action?.kind == "quickfix")
		#expect(action?.isQuickFix == true)
		#expect(action?.isPreferred == true)
		#expect(action?.needsResolving == false)
		#expect(action?.edit?.changes.count == 1)
	}

	/// **The one that must not be read as an empty edit.** A server that
	/// resolves answers cheaply and fills in the work for the one that was
	/// chosen; an action with neither an edit nor a command is that, and taking
	/// it means asking first.
	@Test func anActionWithNoWorkInItIsOneToAskAbout() {
		let action = LSPCodeAction(json: [
			"title": "Extract method",
			"kind": "refactor.extract",
			"data": ["handle": "Foo.java", "proposal": 3],
		])
		#expect(action?.needsResolving == true)
		#expect(action?.edit == nil)
		#expect(action?.command == nil)
	}

	/// The older shape: `command` is a string rather than an object, and there
	/// is no `kind` at all. A client that reads it as an action finds no work in
	/// it and calls it unresolved, which is a resolve request a server that
	/// never offered one will refuse.
	@Test func readsABareCommand() {
		let action = LSPCodeAction(json: [
			"title": "Organize imports",
			"command": "java.action.organizeImports",
			"arguments": ["file:///a.java"],
		])
		#expect(action?.title == "Organize imports")
		#expect(action?.needsResolving == false)
		#expect(action?.command?.command == "java.action.organizeImports")
		#expect(action?.command?.argumentList.count == 1)
	}

	@Test func readsAnActionWhoseWorkIsACommand() {
		let action = LSPCodeAction(json: [
			"title": "Generate getters",
			"kind": "source.generate.accessors",
			"command": [
				"title": "Generate getters",
				"command": "java.action.generateAccessors",
				"arguments": [["uri": "file:///a.java"]],
			],
		])
		#expect(action?.needsResolving == false)
		#expect(action?.command?.command == "java.action.generateAccessors")
		#expect(action?.isSourceAction == true)
	}

	/// A server may send an action it will not run, with a reason meant to be
	/// read. Dropping it and dropping the reason are different mistakes and both
	/// leave somebody wondering.
	@Test func readsAnActionTheServerWillNotRun() {
		let action = LSPCodeAction(json: [
			"title": "Extract method",
			"kind": "refactor.extract",
			"disabled": ["reason": "Cannot extract from a field initialiser"],
		])
		#expect(action?.isDisabled == true)
		#expect(action?.disabledReason == "Cannot extract from a field initialiser")
	}

	@Test func aListSkipsWhatItCannotRead() {
		let actions = LSPCodeAction.list(from: [
			["title": "Fix it", "kind": "quickfix"],
			["kind": "quickfix"],   // no title, and not a command either
			"nonsense",
		])
		#expect(actions.map(\.title) == ["Fix it"])
	}

	/// `source.*` is about the file, not about a caret. Whatever the menu at the
	/// caret shows, these are not it.
	@Test func saysWhichActionsHaveNoCursor() {
		#expect(LSPCodeAction(title: "x", kind: "source.organizeImports").isSourceAction)
		#expect(LSPCodeAction(title: "x", kind: "source.fixAll").isSourceAction)
		#expect(!LSPCodeAction(title: "x", kind: "refactor.extract").isSourceAction)
		#expect(!LSPCodeAction(title: "x", kind: nil).isSourceAction)
	}

	/// **What resolving sends back is the action, not a description of it.**
	/// `data` is the server's own note about which proposal this was; a client
	/// that rebuilds the object from the fields it understands sends a different
	/// action back and gets somebody else's edit, or none.
	@Test func anActionKeepsTheBytesItArrivedAs() {
		let action = LSPCodeAction(json: [
			"title": "Extract method",
			"kind": "refactor.extract",
			"data": ["handle": "=probe/src<p{Foo.java", "proposal": 3],
		])
		let sent = action?.raw?.value as? [String: Any]
		let data = sent?["data"] as? [String: Any]
		#expect(data?["handle"] as? String == "=probe/src<p{Foo.java")
		#expect(data?["proposal"] as? Int == 3)
	}
}

/// The request that comes the other way.
///
/// `workspace/applyEdit` is the first inbound request here that changes files:
/// the server asks, this program writes, and the server waits to be told
/// whether it happened. **What is checked is mostly the unhappy half** — a
/// handler that refuses, no handler at all, and an edit that cannot be read —
/// because answering `true` to any of those teaches the server that a file says
/// something it does not, and everything it sends next is built on that.
struct ApplyEditRequestTests {
	/// What the handler was asked to apply.
	private final class Asked: @unchecked Sendable {
		private let lock = NSLock()
		private var seen: (label: String, changes: Int)?

		func note(_ label: String, changes: Int) {
			lock.lock(); seen = (label, changes); lock.unlock()
		}

		var label: String? { lock.lock(); defer { lock.unlock() }; return seen?.label }
		var changes: Int? { lock.lock(); defer { lock.unlock() }; return seen?.changes }
	}

	/// What the client wrote, since a reply is written rather than returned.
	private final class Replies: @unchecked Sendable {
		private let lock = NSLock()
		private var messages: [[String: Any]] = []

		func record(_ message: [String: Any]) {
			lock.lock(); messages.append(message); lock.unlock()
		}

		var count: Int { lock.lock(); defer { lock.unlock() }; return messages.count }

		/// The result of the reply to a given id.
		func result(id: Int) -> [String: Any]? {
			lock.lock(); defer { lock.unlock() }
			return messages.first { $0["id"] as? Int == id }?["result"] as? [String: Any]
		}
	}

	private func framed(_ object: [String: Any]) -> Data {
		let payload = try! JSONSerialization.data(withJSONObject: object)
		var data = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
		data.append(payload)
		return data
	}

	private func request(id: Int, newText: String = "import java.util.List;\n") -> [String: Any] {
		[
			"jsonrpc": "2.0",
			"id": id,
			"method": "workspace/applyEdit",
			"params": [
				"label": "Organize imports",
				"edit": [
					"documentChanges": [[
						"textDocument": ["uri": "file:///a.java", "version": 1],
						"edits": [[
							"range": [
								"start": ["line": 0, "character": 0],
								"end": ["line": 0, "character": 0],
							],
							"newText": newText,
						]],
					]],
				],
			],
		]
	}

	@Test func anEditThisEditorMakesIsAnsweredAsMade() async {
		let client = LSPClient()
		// A queue of this test's own: the main one belongs to the harness.
		client.callbackQueue = DispatchQueue(label: "apply-edit-tests")
		let replies = Replies()
		client.wroteForTesting = { replies.record($0) }

		let seen = Asked()
		client.onApplyEdit = { edit, label, answer in
			seen.note(label ?? "", changes: edit.changes.count)
			answer(true, nil)
		}

		client.consume(framed(request(id: 7)))
		await waitUntil("the reply was written") { replies.count == 1 }

		#expect(seen.label == "Organize imports")
		#expect(seen.changes == 1)
		#expect(replies.result(id: 7)?["applied"] as? Bool == true)
		// Nothing failed, so there is nothing to say about a failure.
		#expect(replies.result(id: 7)?["failureReason"] == nil)
	}

	/// **The scenario this exists for.** A server asks to edit a file this
	/// program cannot write; the honest answer is that it was not applied, with
	/// what happened, rather than an optimistic `true`.
	@Test func anEditThisEditorCannotMakeIsAnsweredAsRefused() async {
		let client = LSPClient()
		client.callbackQueue = DispatchQueue(label: "apply-edit-tests")
		let replies = Replies()
		client.wroteForTesting = { replies.record($0) }

		client.onApplyEdit = { _, _, answer in
			answer(false, "“a.java” could not be written: permission denied")
		}

		client.consume(framed(request(id: 8)))
		await waitUntil("the reply was written") { replies.count == 1 }

		#expect(replies.result(id: 8)?["applied"] as? Bool == false)
		#expect(replies.result(id: 8)?["failureReason"] as? String
			== "“a.java” could not be written: permission denied")
	}

	/// A client with nothing willing to write still has to answer, or a server
	/// waiting on it stops working — the same rule the `default` branch keeps
	/// for every other inbound request.
	@Test func anEditNobodyIsListeningForIsStillAnswered() async {
		let client = LSPClient()
		client.callbackQueue = DispatchQueue(label: "apply-edit-tests")
		let replies = Replies()
		client.wroteForTesting = { replies.record($0) }

		client.consume(framed(request(id: 9)))
		await waitUntil("the reply was written") { replies.count == 1 }

		#expect(replies.result(id: 9)?["applied"] as? Bool == false)
		#expect(replies.result(id: 9)?["failureReason"] != nil)
	}

	/// All of it or none of it, one layer up: an edit with an entry this client
	/// cannot read is refused rather than half applied.
	@Test func anEditThatCannotBeReadIsRefusedRatherThanGuessedAt() async {
		let client = LSPClient()
		client.callbackQueue = DispatchQueue(label: "apply-edit-tests")
		let replies = Replies()
		client.wroteForTesting = { replies.record($0) }
		let asked = Asked()
		client.onApplyEdit = { _, _, answer in
			asked.note("asked", changes: 1)
			answer(true, nil)
		}

		client.consume(framed([
			"jsonrpc": "2.0",
			"id": 10,
			"method": "workspace/applyEdit",
			"params": ["edit": ["documentChanges": [["kind": "somethingNewer", "uri": "file:///a.java"]]]],
		]))
		await waitUntil("the reply was written") { replies.count == 1 }

		#expect(replies.result(id: 10)?["applied"] as? Bool == false)
		// And the handler was never troubled with it.
		#expect(asked.label == nil)
	}

	/// A handler that answers twice must not put two replies on the wire: an id
	/// is answered once, and the second would be read as an answer to something
	/// else entirely.
	@Test func anAnswerGivenTwiceIsWrittenOnce() async {
		let client = LSPClient()
		client.callbackQueue = DispatchQueue(label: "apply-edit-tests")
		let replies = Replies()
		client.wroteForTesting = { replies.record($0) }
		client.onApplyEdit = { _, _, answer in
			answer(true, nil)
			answer(false, "and again")
		}

		client.consume(framed(request(id: 11)))
		await waitUntil("the reply was written") { replies.count == 1 }
		// Long enough for a second write to have arrived if one were coming.
		try? await Task.sleep(nanoseconds: 200_000_000)
		#expect(replies.count == 1)
		#expect(replies.result(id: 11)?["applied"] as? Bool == true)
	}
}
