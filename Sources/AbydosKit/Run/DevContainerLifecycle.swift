import Foundation

/// The six moments a `devcontainer.json` can hang a command on.
///
/// The raw value is the field name, because every message about one of these
/// names the field somebody would go and edit: "postCreateCommand exited 3" is
/// a sentence they can act on and "a setup command failed" is not.
///
/// The order is the order they run in, and `allCases` relies on it.
public enum DevContainerStage: String, Equatable, Sendable, CaseIterable {
	/// On this machine, before the container exists at all.
	case initializeCommand
	/// Once, when the container is created.
	case onCreateCommand
	/// Once, when the container is created — after `onCreateCommand`, and
	/// separate from it because a prebuild runs this one again and that one not.
	case updateContentCommand
	/// Once, when the container is created, and the last of the three.
	case postCreateCommand
	/// Every time the container starts, creation included.
	case postStartCommand
	/// Every time something attaches to it — a terminal, a language server.
	case postAttachCommand

	/// The three that belong to creating the container, in order.
	///
	/// The distinction this whole file exists for: these run once for the life
	/// of a container and the two after them run again and again. Getting it
	/// wrong means re-running an installer on every launch, or never running it.
	public static let creation: [DevContainerStage] =
		[.onCreateCommand, .updateContentCommand, .postCreateCommand]

	/// The ones that run inside the container, which is all of them but the
	/// first.
	public var runsInContainer: Bool { self != .initializeCommand }
}

/// One lifecycle command, in the three shapes the spec gives it.
public enum DevContainerCommand: Equatable, Sendable {
	/// `"npm ci && npm run build"` — run through a shell, so `&&`, `$HOME` and
	/// a redirection mean what the person who wrote them meant.
	case shell(String)
	/// `["npm", "ci"]` — argv with no shell between, which is how a file says
	/// "these are the arguments; do not parse them again".
	case argv([String])
	/// `{"install": "npm ci", "fetch": "go mod download"}` — several named
	/// commands, which the spec says run in parallel.
	case named([String: DevContainerCommand])

	/// What to run it as, inside the container or on this machine.
	///
	/// `/bin/sh` rather than `bash`: the string form is shell syntax, and the
	/// one shell every image has is `sh`. An image that wants bash can say so in
	/// the command.
	public var invocation: [String] {
		switch self {
		case let .shell(text): return ["/bin/sh", "-c", text]
		case let .argv(parts): return parts
		case .named: return []
		}
	}

	/// How it reads in a message: as it was written in the file.
	public var line: String {
		switch self {
		case let .shell(text): return text
		case let .argv(parts): return parts.joined(separator: " ")
		case let .named(members):
			return members.keys.sorted().map { "\($0): \(members[$0]?.line ?? "")" }
				.joined(separator: ", ")
		}
	}

	/// The named members, in a fixed order, or the command itself under no name.
	///
	/// Sorted, so that which one is reported first is a fact about the names
	/// rather than about the order a JSON dictionary happened to come apart in.
	public var members: [(name: String?, command: DevContainerCommand)] {
		guard case let .named(members) = self else { return [(nil, self)] }
		return members.keys.sorted().compactMap { name in
			members[name].map { (name, $0) }
		}
	}

	/// One out of the file, or nil when it is not a shape the spec allows.
	///
	/// Nested objects are the one thing refused rather than flattened: the spec
	/// has no meaning for them, and inventing one would be this app deciding
	/// what somebody else's file meant.
	public static func read(_ value: Any?, allowingNames: Bool = true) -> DevContainerCommand? {
		if let text = value as? String { return .shell(text) }
		if let parts = value as? [Any] {
			let strings = parts.compactMap { $0 as? String }
			guard strings.count == parts.count, !strings.isEmpty else { return nil }
			return .argv(strings)
		}
		if allowingNames, let table = value as? [String: Any] {
			var members: [String: DevContainerCommand] = [:]
			for (name, member) in table {
				guard let command = read(member, allowingNames: false) else { return nil }
				members[name] = command
			}
			return members.isEmpty ? nil : .named(members)
		}
		return nil
	}

	/// Every string in it, put through the substitutions.
	public func resolved(_ transform: (String) -> String) -> DevContainerCommand {
		switch self {
		case let .shell(text): return .shell(transform(text))
		case let .argv(parts): return .argv(parts.map(transform))
		case let .named(members):
			return .named(members.mapValues { $0.resolved(transform) })
		}
	}
}

/// What a `devcontainer.json` asks to be run, and when.
public struct DevContainerLifecycle: Equatable, Sendable {
	private var commands: [DevContainerStage: DevContainerCommand]
	/// Which command the file says the container is ready after.
	///
	/// Read, and honoured as a floor rather than as a starting gun — see
	/// `DevContainers.runLifecycle`, where the reason is written down.
	public let waitFor: DevContainerStage?

	public init(
		commands: [DevContainerStage: DevContainerCommand] = [:],
		waitFor: DevContainerStage? = nil
	) {
		self.commands = commands
		self.waitFor = waitFor
	}

	public subscript(stage: DevContainerStage) -> DevContainerCommand? { commands[stage] }

	public var isEmpty: Bool { commands.isEmpty }

	/// Whether anything has to run when the container is created.
	public var hasCreationCommands: Bool {
		DevContainerStage.creation.contains { commands[$0] != nil }
	}

	/// The stages that have a command, in the order they run.
	public var stages: [DevContainerStage] {
		DevContainerStage.allCases.filter { commands[$0] != nil }
	}
}
