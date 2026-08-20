import Foundation

/// A piece of a server's message kept exactly as it arrived.
///
/// **Some things a server sends have to go back to it unchanged.** A code
/// action carries a `data` field that is the server's own bookkeeping — jdtls
/// puts a compilation-unit handle and a proposal index in it — and
/// `codeAction/resolve` takes the *whole action back*, `data` included, to say
/// which one to fill in. Reading those fields into a struct and writing a new
/// object out would hand the server something it never sent.
///
/// Held as JSON bytes rather than as `[String: Any]` for one reason: everything
/// on this path is `Sendable`, and a dictionary of `Any` is not. Wrapped in an
/// array on the way in and unwrapped on the way out, so a bare string or number
/// keeps working — `JSONSerialization` will not write a fragment on its own.
public struct LSPRawJSON: Equatable, Sendable {
	private let bytes: Data

	public init?(_ value: Any?) {
		guard let value else { return nil }
		guard let data = try? JSONSerialization.data(withJSONObject: [value]) else { return nil }
		bytes = data
	}

	/// What was sent, as it was sent.
	public var value: Any? {
		guard let array = try? JSONSerialization.jsonObject(with: bytes) as? [Any] else { return nil }
		return array.first
	}
}

/// Something a server can be asked to run, by name.
///
/// The escape hatch of the protocol: a command is a string the server knows and
/// a list of arguments it gave itself, and running one goes back through
/// `workspace/executeCommand`. The arguments are the server's own — often
/// handles into its internal state — so they are kept as they arrived.
public struct LSPCommand: Equatable, Sendable {
	/// What to show somebody, when a command is all there is to show.
	public var title: String
	public var command: String
	public var arguments: LSPRawJSON?

	public init(title: String, command: String, arguments: LSPRawJSON? = nil) {
		self.title = title
		self.command = command
		self.arguments = arguments
	}

	public init?(json: Any?) {
		guard let dictionary = json as? [String: Any],
		      let command = dictionary["command"] as? String
		else { return nil }
		self.init(
			title: dictionary["title"] as? String ?? command,
			command: command,
			arguments: LSPRawJSON(dictionary["arguments"])
		)
	}

	/// The arguments as `executeCommand` wants them: an array, empty when the
	/// server sent none.
	public var argumentList: [Any] { (arguments?.value as? [Any]) ?? [] }
}

/// One thing a server offers to do about a place in a file.
///
/// **Four shapes arrive under one request**, and telling them apart is most of
/// what this type is for:
///
///  1. An action with a `WorkspaceEdit` — take it and apply the edit.
///  2. An action with a `command` — take it and run the command, after which
///     the server may ask *this* program to apply an edit.
///  3. An action with neither, which is not an empty action: it is a server
///     answering cheaply and waiting to be asked for the work on
///     `codeAction/resolve`. Treating this as nothing to do is a menu that
///     works and does nothing, which is why `needsResolving` exists and why
///     there is a scenario about it.
///  4. A bare `Command`, from before code actions existed. It has `command` as
///     a *string* where an action has it as an object, and that is the only way
///     to tell them apart.
///
/// The action is kept as it arrived as well, because resolving sends it back.
public struct LSPCodeAction: Equatable, Sendable {
	/// What the menu says. The server's own words, never edited here.
	public var title: String
	/// `quickfix`, `refactor.extract`, `source.organizeImports` — a
	/// dot-separated hierarchy the protocol leaves open, so it is a string and
	/// asked about by prefix.
	public var kind: String?
	/// The server saying this is the obvious one, which is what a "fix this"
	/// keystroke would take without asking.
	public var isPreferred: Bool
	/// Why this cannot be run now. An action a server marks disabled is still
	/// sent, with a reason meant to be shown.
	public var disabledReason: String?
	public var edit: WorkspaceEdit?
	public var command: LSPCommand?
	/// The action exactly as the server sent it, for `codeAction/resolve`.
	public var raw: LSPRawJSON?

	public init(
		title: String,
		kind: String? = nil,
		isPreferred: Bool = false,
		disabledReason: String? = nil,
		edit: WorkspaceEdit? = nil,
		command: LSPCommand? = nil,
		raw: LSPRawJSON? = nil
	) {
		self.title = title
		self.kind = kind
		self.isPreferred = isPreferred
		self.disabledReason = disabledReason
		self.edit = edit
		self.command = command
		self.raw = raw
	}

	public init?(json: Any?) {
		guard let dictionary = json as? [String: Any] else { return nil }

		// A bare `Command`: `command` is a string rather than an object. This is
		// the older shape and servers still send it — a client that reads it as
		// an action with no work in it would show the title and do nothing.
		if dictionary["command"] is String {
			guard let command = LSPCommand(json: dictionary) else { return nil }
			self.init(title: command.title, command: command, raw: LSPRawJSON(dictionary))
			return
		}

		guard let title = dictionary["title"] as? String else { return nil }
		let disabled = (dictionary["disabled"] as? [String: Any])?["reason"] as? String
		self.init(
			title: title,
			kind: dictionary["kind"] as? String,
			isPreferred: dictionary["isPreferred"] as? Bool ?? false,
			disabledReason: disabled,
			edit: WorkspaceEdit(json: dictionary["edit"]),
			command: LSPCommand(json: dictionary["command"]),
			raw: LSPRawJSON(dictionary)
		)
	}

	public static func list(from result: Any?) -> [LSPCodeAction] {
		guard let array = result as? [Any] else { return [] }
		return array.compactMap { LSPCodeAction(json: $0) }
	}

	/// Whether the work has to be asked for before this can be taken.
	///
	/// **Nothing to do is not the same as not yet told what to do.** A server
	/// that supports resolving sends the list without edits and fills one in
	/// when asked; an action with neither an edit nor a command is that, and is
	/// resolved on the way to being applied.
	public var needsResolving: Bool { edit == nil && command == nil }

	/// Whether this can be run at all.
	public var isDisabled: Bool { disabledReason != nil }

	/// Whether this is about the file rather than about a position.
	///
	/// `source.organizeImports` has no caret: it is the whole file's imports,
	/// and it does not belong in a menu that appears where somebody is typing.
	public var isSourceAction: Bool { kind?.hasPrefix("source") ?? false }

	/// Whether this fixes something that was reported as wrong.
	public var isQuickFix: Bool { kind?.hasPrefix("quickfix") ?? false }
}

/// An answer that can only be given once.
///
/// A JSON-RPC id is answered exactly once: twice is a protocol violation and a
/// server that has moved on reads the second reply as an answer to something
/// else. The handler applying an edit is somebody else's code — a window that
/// may be closing, a callback that may be called twice by accident — so the
/// rule is kept here rather than assumed of them.
final class OnceAnswer: @unchecked Sendable {
	private let lock = NSLock()
	private var say: ((Bool, String?) -> Void)?

	init(_ answer: @escaping (Bool, String?) -> Void) { say = answer }

	func say(_ applied: Bool, _ reason: String?) {
		lock.lock()
		let answer = say
		say = nil
		lock.unlock()
		answer?(applied, reason)
	}
}
