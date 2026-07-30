import Foundation

/// A breakpoint the user set, independent of any running session.
public struct Breakpoint: Equatable, Hashable, Sendable {
	public let file: String
	public let line: Int
	public var isEnabled: Bool
	/// Set once the adapter confirms it; an unverified breakpoint is drawn
	/// hollow, because a filled marker where execution can never stop is a lie.
	public var isVerified: Bool

	public init(file: String, line: Int, isEnabled: Bool = true, isVerified: Bool = false) {
		self.file = file
		self.line = line
		self.isEnabled = isEnabled
		self.isVerified = isVerified
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
/// The session owns the debugger state and publishes it; views render whatever
/// it currently holds. Keeping it free of view code means the protocol
/// choreography — which requests must precede which, what has to be re-fetched
/// after a stop — is testable against a stub adapter.
public final class DebugSession {
	public enum State: Equatable, Sendable {
		case idle
		case starting
		case running
		case stopped(reason: String)
		case terminated
	}

	public private(set) var state: State = .idle {
		didSet { if state != oldValue { onStateChange?(state) } }
	}

	/// Breakpoints by file, kept across runs so they survive restarting.
	public private(set) var breakpoints: [String: [Breakpoint]] = [:]

	public private(set) var stackFrames: [StackFrame] = []
	public private(set) var scopes: [Scope] = []
	/// Frame whose variables are shown.
	public private(set) var selectedFrameID: Int?

	public var onStateChange: ((State) -> Void)?
	public var onStackChanged: (() -> Void)?
	public var onVariablesChanged: (() -> Void)?
	public var onBreakpointsChanged: (() -> Void)?
	public var onOutput: ((String) -> Void)?
	/// Fired when execution stops somewhere with a source location.
	public var onStoppedAt: ((_ file: String, _ line: Int) -> Void)?

	private let client: DAPClient
	private let projectRoot: URL
	private var currentThreadID: Int?

	public init(projectRoot: URL, client: DAPClient = DAPClient()) {
		self.projectRoot = projectRoot
		self.client = client
		wireEvents()
	}

	// MARK: - Breakpoints

	/// Toggles a breakpoint, syncing to the adapter when one is attached.
	public func toggleBreakpoint(file: String, line: Int) {
		var list = breakpoints[file] ?? []
		if let index = list.firstIndex(where: { $0.line == line }) {
			list.remove(at: index)
		} else {
			list.append(Breakpoint(file: file, line: line))
			list.sort { $0.line < $1.line }
		}
		breakpoints[file] = list.isEmpty ? nil : list
		onBreakpointsChanged?()

		if isActive { Task { await syncBreakpoints(for: file) } }
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
	private func syncBreakpoints(for file: String) async {
		let lines = (breakpoints[file] ?? []).filter(\.isEnabled).map { ["line": $0.line] }
		let response = try? await client.request("setBreakpoints", arguments: [
			"source": ["path": file],
			"breakpoints": lines,
			"sourceModified": false,
		])

		// The adapter reports which it could actually bind.
		guard let verified = response?["breakpoints"] as? [[String: Any]] else { return }
		var list = breakpoints[file] ?? []
		for (index, entry) in verified.enumerated() where index < list.count {
			list[index].isVerified = entry["verified"] as? Bool ?? false
		}
		breakpoints[file] = list
		onBreakpointsChanged?()
	}

	// MARK: - Session

	/// Launches `dlv dap` and runs the given package under it.
	public func launch(delveExecutable: String, package: String) async throws {
		state = .starting

		try client.start(
			executable: delveExecutable,
			arguments: ["dap"],
			workingDirectory: projectRoot
		)

		_ = try await client.request("initialize", arguments: [
			"clientID": "ideai",
			"clientName": "ideai",
			"adapterID": "go",
			"pathFormat": "path",
			"linesStartAt1": true,
			"columnsStartAt1": true,
			"supportsVariableType": true,
			"supportsRunInTerminalRequest": false,
		])

		// Launch is sent before waiting for `initialized`; the adapter replies to
		// it once configuration is done, which is why it is not awaited here.
		client.send("launch", arguments: [
			"request": "launch",
			"mode": "debug",
			"program": absolutePackagePath(package),
			"cwd": projectRoot.path,
		])
	}

	private func absolutePackagePath(_ package: String) -> String {
		if package.hasPrefix("/") { return package }
		let trimmed = package.hasPrefix("./") ? String(package.dropFirst(2)) : package
		return projectRoot.appendingPathComponent(trimmed).path
	}

	public func stop() {
		client.send("disconnect", arguments: ["terminateDebuggee": true])
		client.stop()
		state = .terminated
		stackFrames = []
		scopes = []
		onStackChanged?()
		onVariablesChanged?()
	}

	// MARK: - Execution control

	public func resume() {
		guard let thread = currentThreadID else { return }
		client.send("continue", arguments: ["threadId": thread])
		state = .running
	}

	public func pause() {
		guard let thread = currentThreadID else { return }
		client.send("pause", arguments: ["threadId": thread])
	}

	public func stepOver() { step("next") }
	public func stepInto() { step("stepIn") }
	public func stepOut() { step("stepOut") }

	private func step(_ command: String) {
		guard let thread = currentThreadID else { return }
		client.send(command, arguments: ["threadId": thread])
		state = .running
	}

	// MARK: - Events

	private func wireEvents() {
		client.onOutput = { [weak self] _, text in
			self?.onOutput?(text)
		}
		client.onTerminated = { [weak self] in
			self?.state = .terminated
		}
		client.onEvent = { [weak self] event, body in
			guard let self else { return }
			switch event {
			case "initialized":
				// Only now may breakpoints be sent; the adapter is ready for
				// configuration. Sending them earlier is silently dropped.
				Task { await self.configurationDone() }

			case "stopped":
				self.currentThreadID = body["threadId"] as? Int
				let reason = body["reason"] as? String ?? "pause"
				self.state = .stopped(reason: reason)
				Task { await self.refreshStack() }

			case "continued":
				self.state = .running

			case "terminated", "exited":
				self.state = .terminated
				self.stackFrames = []
				self.scopes = []
				self.onStackChanged?()
				self.onVariablesChanged?()

			default:
				break
			}
		}
	}

	private func configurationDone() async {
		for file in breakpoints.keys {
			await syncBreakpoints(for: file)
		}
		_ = try? await client.request("configurationDone")
		state = .running
	}

	// MARK: - Stack and variables

	/// Re-reads the stack after a stop, then the top frame's variables.
	private func refreshStack() async {
		guard let thread = currentThreadID else { return }

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
		onStackChanged?()

		if let top = stackFrames.first {
			if let file = top.file { onStoppedAt?(file, top.line) }
			await selectFrame(id: top.id)
		}
	}

	/// Loads the scopes and top-level variables for a frame.
	public func selectFrame(id: Int) async {
		selectedFrameID = id

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
		onVariablesChanged?()
	}

	/// Children of a variable container.
	public func variables(reference: Int) async -> [Variable] {
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
	public func toggleExpansion(scopeIndex: Int, path: [Int]) async {
		guard scopes.indices.contains(scopeIndex) else { return }
		var scope = scopes[scopeIndex]
		scope.variables = await toggle(in: scope.variables, path: path)
		scopes[scopeIndex] = scope
		onVariablesChanged?()
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
