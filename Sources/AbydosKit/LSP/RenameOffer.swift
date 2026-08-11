import Foundation

/// What is being renamed, once a server has agreed there is something here.
public struct RenameSubject: Equatable, Sendable {
	/// The text to start the field with — the symbol's current name.
	public var name: String
	/// What the field is laid over, which is what will be replaced where the
	/// caret is. The rest of the file's occurrences are the server's business.
	public var range: LSPRange
	/// Whether the server answering knows the code by its text rather than by
	/// its types, which changes what accepting this actually promises.
	public var isSyntactic: Bool

	public init(name: String, range: LSPRange, isSyntactic: Bool = false) {
		self.name = name
		self.range = range
		self.isSyntactic = isSyntactic
	}

	/// The one sentence somebody needs before accepting a refactoring from a
	/// server that reads text rather than types, and nil for one that does not
	/// need saying.
	///
	/// Said where the name is typed rather than after the fact: a warning that
	/// arrives with the result is a warning about something that has already
	/// happened, and a rename is undoable but a person's confidence in the tool
	/// is not.
	public var caveat: String? {
		guard isSyntactic else { return nil }
		return "This server matches names rather than types, "
			+ "so unrelated things called “\(name)” will be renamed too."
	}
}

/// Whether renaming can be offered where the caret is, and why not when it
/// cannot.
///
/// **An offer that fails is worse than an absence**, which is the whole reason
/// this is worked out before anything appears on screen rather than discovered
/// by asking and being refused. There are four ways of not being able to
/// rename, and they are not the same thing to say — two are about this program
/// having nothing to ask, one is a server saying it does not do this, and one
/// is a server saying "not here", which is the ordinary answer for a caret on a
/// comma and must be silent.
public enum RenameOffer: Equatable, Sendable {
	/// Go ahead.
	case offered(RenameSubject)
	/// Nothing is running for this file. Silent: it is most files in most
	/// projects, and what there is to say about a missing server is the strip
	/// above the file.
	case noServer
	/// A server is running and does not rename at all. Worth saying once, by
	/// name, because it is a fact about the server somebody chose.
	case serverCannot(server: String)
	/// The server renames and says there is nothing here. Silent, for the same
	/// reason an empty go-to-declaration is: it is what the caret being on a
	/// bracket looks like, every time.
	case notHere

	/// What to say out loud, and nil for the two that say nothing.
	public var refusal: String? {
		switch self {
		case .offered, .noServer, .notHere: return nil
		case let .serverCannot(server): return "\(server) does not rename."
		}
	}
}
