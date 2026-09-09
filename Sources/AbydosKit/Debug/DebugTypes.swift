import Foundation

/// A breakpoint the user set, independent of any running session.
public struct Breakpoint: Equatable, Hashable, Sendable {
	public let file: String
	public let line: Int
	public var isEnabled: Bool
	/// Set once the adapter confirms it; an unverified breakpoint is drawn
	/// hollow, because a filled marker where execution can never stop is a lie.
	public var isVerified: Bool

	/// An expression that must be true to stop here.
	///
	/// The difference between a breakpoint you can use and one you have to sit
	/// and press Continue at four hundred times because the interesting case is
	/// the last one.
	public var condition: String?

	/// Stop only after this many hits — `> 5`, or just `5` meaning the same.
	public var hitCondition: String?

	/// Print this and carry on rather than stopping.
	///
	/// A print statement that needs no rebuild and leaves no mess behind.
	public var logMessage: String?

	/// Where in the code this was put, rather than at which line number.
	///
	/// A line number stops meaning anything once something rewrites the file
	/// without saying what it changed — an agent, a `git checkout`, a formatter.
	/// The anchor is what survives that: the symbol the breakpoint was inside,
	/// how far into it, and what was written on the line. Nil until the file has
	/// been parsed, and for files with no grammar to parse them.
	public var anchor: BreakpointAnchors.Anchor?

	/// Whether this breakpoint does anything beyond stopping every time.
	public var isConditional: Bool {
		condition?.isEmpty == false || hitCondition?.isEmpty == false || logMessage?.isEmpty == false
	}

	public init(
		file: String,
		line: Int,
		isEnabled: Bool = true,
		isVerified: Bool = false,
		condition: String? = nil,
		hitCondition: String? = nil,
		logMessage: String? = nil,
		anchor: BreakpointAnchors.Anchor? = nil
	) {
		self.file = file
		self.line = line
		self.isEnabled = isEnabled
		self.isVerified = isVerified
		self.condition = condition
		self.hitCondition = hitCondition
		self.logMessage = logMessage
		self.anchor = anchor
	}

	/// How the protocol wants it.
	public var wireFormat: [String: Any] {
		var entry: [String: Any] = ["line": line]
		if let condition, !condition.isEmpty { entry["condition"] = condition }
		if let hitCondition, !hitCondition.isEmpty { entry["hitCondition"] = hitCondition }
		if let logMessage, !logMessage.isEmpty { entry["logMessage"] = logMessage }
		return entry
	}
}

/// One goroutine, or one thread in anything that is not Go.
public struct DebugThread: Equatable, Sendable, Identifiable {
	public let id: Int
	public let name: String

	public init(id: Int, name: String) {
		self.id = id
		self.name = name
	}
}

/// An expression being watched, and what it last came to.
public struct WatchExpression: Equatable, Sendable, Identifiable {
	public let id: UUID
	public var expression: String
	/// What it evaluated to where execution is now, or the error if it could
	/// not be evaluated there.
	public var value: String?
	public var failed: Bool
	/// Set when the value can be opened up, as a struct or a slice can.
	public var variablesReference: Int

	/// Whether it has been opened. Kept across a refresh: a watch somebody
	/// opened at one stop should still be open at the next, showing that stop's
	/// values rather than closing itself every time execution moves.
	public var isExpanded: Bool

	/// What is inside it, once asked for. Nil means not asked.
	///
	/// Thrown away by every refresh, because `variablesReference` is a handle
	/// into one stopped state and means nothing at the next one — a tree still
	/// showing the fields it had two stops ago is exactly the fault
	/// `refreshWatches` exists to prevent, one level down.
	public var children: [Variable]?

	/// Whether it is worth offering a triangle beside.
	public var isExpandable: Bool { variablesReference != 0 }

	public init(
		id: UUID = UUID(),
		expression: String,
		value: String? = nil,
		failed: Bool = false,
		variablesReference: Int = 0,
		isExpanded: Bool = false,
		children: [Variable]? = nil
	) {
		self.id = id
		self.expression = expression
		self.value = value
		self.failed = failed
		self.variablesReference = variablesReference
		self.isExpanded = isExpanded
		self.children = children
	}
}

public struct StackFrame: Identifiable, Equatable, Sendable {
	public let id: Int
	public let name: String
	public let file: String?
	public let line: Int

	public init(id: Int, name: String, file: String?, line: Int) {
		self.id = id
		self.name = name
		self.file = file
		self.line = line
	}
}

public struct Variable: Identifiable, Equatable, Sendable {
	public let id = UUID()
	public let name: String
	public let value: String
	public let type: String?
	/// Non-zero when the value can be expanded; the handle to ask with.
	public let variablesReference: Int
	public var children: [Variable]?
	public var isExpanded = false

	public var isExpandable: Bool { variablesReference > 0 }

	public init(name: String, value: String, type: String?, variablesReference: Int) {
		self.name = name
		self.value = value
		self.type = type
		self.variablesReference = variablesReference
	}
}

public struct Scope: Equatable, Sendable {
	public let name: String
	public let variablesReference: Int
	public var variables: [Variable] = []
	public var isExpanded = true

	public init(name: String, variablesReference: Int) {
		self.name = name
		self.variablesReference = variablesReference
	}
}

/// Drives a debug adapter: breakpoints, stepping, stack and variables.
///
