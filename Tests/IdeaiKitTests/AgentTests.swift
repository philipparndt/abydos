import Testing
import Foundation
@testable import IdeaiKit

/// The MCP server is exercised over real HTTP, because the whole point is that
/// an external process can reach it.
@Suite(.serialized)
struct MCPServerTests {
	private func makeServer() throws -> MCPServer {
		let server = MCPServer(token: "test-token")
		// Tool handlers would otherwise wait on a main queue no test services.
		server.callbackQueue = DispatchQueue(label: "ideai.tests.mcp")
		try server.start()
		return server
	}

	/// Sends one JSON-RPC message and returns the decoded reply.
	private func call(
		_ server: MCPServer,
		method: String,
		params: [String: Any]? = nil,
		id: Int? = 1,
		token: String? = "test-token"
	) async throws -> [String: Any]? {
		var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/mcp")!)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		if let token {
			request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		}

		var body: [String: Any] = ["jsonrpc": "2.0", "method": method]
		if let id { body["id"] = id }
		if let params { body["params"] = params }
		request.httpBody = try JSONSerialization.data(withJSONObject: body)

		let (data, response) = try await URLSession.shared.data(for: request)
		if let http = response as? HTTPURLResponse, http.statusCode == 401 {
			return ["unauthorized": true]
		}
		guard !data.isEmpty else { return nil }
		return try JSONSerialization.jsonObject(with: data) as? [String: Any]
	}

	@Test func startsOnLoopbackAndReportsPort() throws {
		let server = try makeServer()
		defer { server.stop() }
		#expect(server.port > 0)
	}

	@Test func handshakeReportsToolCapability() async throws {
		let server = try makeServer()
		defer { server.stop() }

		let reply = try await call(server, method: "initialize", params: [
			"protocolVersion": "2025-06-18",
			"capabilities": [:],
			"clientInfo": ["name": "test", "version": "1"],
		])

		let result = reply?["result"] as? [String: Any]
		#expect(result?["protocolVersion"] as? String == "2025-06-18")
		#expect((result?["capabilities"] as? [String: Any])?["tools"] != nil)
	}

	/// Loopback is not access control — any local process can reach the port.
	@Test func rejectsRequestsWithoutTheToken() async throws {
		let server = try makeServer()
		defer { server.stop() }

		let reply = try await call(server, method: "initialize", token: "wrong-token")
		#expect(reply?["unauthorized"] as? Bool == true)
	}

	@Test func listsRegisteredTools() async throws {
		let server = try makeServer()
		defer { server.stop() }

		server.register(MCPServer.Tool(
			name: "example_tool",
			description: "Does a thing.",
			inputSchema: ["type": "object", "properties": [:]]
		) { _ in "done" })

		let reply = try await call(server, method: "tools/list")
		let tools = (reply?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
		#expect(tools?.count == 1)
		#expect(tools?.first?["name"] as? String == "example_tool")
		#expect(tools?.first?["inputSchema"] != nil)
	}

	@Test func callsToolAndReturnsItsText() async throws {
		let server = try makeServer()
		defer { server.stop() }

		let received = Received()
		server.register(MCPServer.Tool(
			name: "echo",
			description: "Echoes.",
			inputSchema: ["type": "object"]
		) { arguments in
			received.value = arguments["message"] as? String
			return "ok: \(arguments["message"] as? String ?? "")"
		})

		let reply = try await call(server, method: "tools/call", params: [
			"name": "echo",
			"arguments": ["message": "hello"],
		])

		#expect(received.value == "hello")
		let content = (reply?["result"] as? [String: Any])?["content"] as? [[String: Any]]
		#expect(content?.first?["text"] as? String == "ok: hello")
	}

	@Test func reportsUnknownTool() async throws {
		let server = try makeServer()
		defer { server.stop() }

		let reply = try await call(server, method: "tools/call", params: ["name": "missing"])
		#expect(reply?["error"] != nil)
	}

	/// Notifications carry no id and must not produce a response body.
	@Test func acceptsNotificationsWithoutReplying() async throws {
		let server = try makeServer()
		defer { server.stop() }

		let reply = try await call(server, method: "notifications/initialized", id: nil)
		#expect(reply == nil)
	}

	@Test func configurationPointsAtThisServer() throws {
		let server = try makeServer()
		defer { server.stop() }

		let json = server.configurationJSON()
		#expect(json.contains("127.0.0.1:\(server.port)"))
		#expect(json.contains("Bearer test-token"))
		#expect(json.contains("\"type\":\"http\"") || json.contains("\"type\" : \"http\""))
	}

	@Test func qualifiedNamesMatchTheMCPConvention() throws {
		let server = try makeServer()
		defer { server.stop() }
		server.register(MCPServer.Tool(name: "alpha", description: "", inputSchema: [:]) { _ in "" })
		#expect(server.qualifiedToolNames() == ["mcp__ideai__alpha"])
	}
}

/// Findings ingestion, independent of transport.
struct ReviewSessionTests {
	private func makeSession() -> ReviewSession {
		ReviewSession(projectRoot: URL(fileURLWithPath: "/tmp/project"))
	}

	@Test func ingestsWellFormedFindings() {
		let session = makeSession()
		let added = session.add(rawFindings: [
			["file": "a.swift", "line": 12, "severity": "error", "title": "Boom", "detail": "why"],
		])
		#expect(added == 1)
		#expect(session.findings.first?.severity == .error)
		#expect(session.findings.first?.line == 12)
	}

	/// A model that mislabels one entry should not cost the user the rest of the
	/// review, so ingestion is tolerant rather than all-or-nothing.
	@Test func skipsMalformedEntriesButKeepsTheRest() {
		let session = makeSession()
		let added = session.add(rawFindings: [
			["line": 3, "severity": "error", "title": "no file"],          // dropped
			["file": "b.swift", "line": 4, "severity": "nonsense", "title": "Odd"],
			["file": "c.swift", "title": "no line"],
		])
		#expect(added == 2)
		// An unrecognised severity degrades to info rather than being discarded.
		#expect(session.findings.contains { $0.title == "Odd" && $0.severity == .info })
		// A missing line defaults to the top of the file.
		#expect(session.findings.contains { $0.file == "c.swift" && $0.line == 1 })
	}

	@Test func sortsWorstFirstThenByLocation() {
		let session = makeSession()
		session.add(rawFindings: [
			["file": "z.swift", "line": 1, "severity": "info", "title": "i"],
			["file": "a.swift", "line": 9, "severity": "error", "title": "e2"],
			["file": "a.swift", "line": 2, "severity": "error", "title": "e1"],
			["file": "m.swift", "line": 1, "severity": "warning", "title": "w"],
		])
		#expect(session.findings.map(\.title) == ["e1", "e2", "w", "i"])
	}

	@Test func resolvesPathsAgainstTheProjectRoot() {
		let session = makeSession()
		session.add(rawFindings: [["file": "src/a.swift", "line": 1, "severity": "info", "title": "t"]])
		let url = session.absoluteURL(for: session.findings[0])
		#expect(url.path == "/tmp/project/src/a.swift")
	}

	@Test func absolutePathsAreLeftAlone() {
		let session = makeSession()
		session.add(rawFindings: [["file": "/other/x.swift", "line": 1, "severity": "info", "title": "t"]])
		#expect(session.absoluteURL(for: session.findings[0]).path == "/other/x.swift")
	}

	@Test func toolsCoverReportingProgressAndCompletion() {
		let session = makeSession()
		let names = Set(session.makeTools().map(\.name))
		#expect(names == ["report_review_findings", "report_review_status", "complete_review"])
	}

	@Test func statusAndCompletionFlowThroughTools() {
		let session = makeSession()
		let tools = Dictionary(uniqueKeysWithValues: session.makeTools().map { ($0.name, $0) })

		_ = tools["report_review_status"]?.handler(["message": "scanning"])
		#expect(session.statusMessage == "scanning")

		_ = tools["complete_review"]?.handler(["summary": "all done"])
		#expect(session.isComplete)
		#expect(session.statusMessage == "all done")
	}

	@Test func findingsToolIngestsThroughItsHandler() {
		let session = makeSession()
		let tool = session.makeTools().first { $0.name == "report_review_findings" }
		let output = tool?.handler([
			"findings": [["file": "a.swift", "line": 1, "severity": "warning", "title": "t", "detail": "d"]],
		])
		#expect(session.findings.count == 1)
		#expect(output?.contains("1 finding") == true)
	}

	@Test func changeCallbackFires() {
		let session = makeSession()
		let counter = Counter()
		session.onChange = { counter.value += 1 }
		session.add(rawFindings: [["file": "a", "line": 1, "severity": "info", "title": "t"]])
		#expect(counter.value == 1)
	}
}

/// The launcher builds the command line; nothing is executed here.
struct AgentLauncherTests {
	@Test func reviewCommandIsolatesMCPConfiguration() throws {
		let server = MCPServer(token: "tok")
		try server.start()
		defer { server.stop() }
		server.register(MCPServer.Tool(name: "report_review_findings", description: "", inputSchema: [:]) { _ in "" })

		let command = AgentLauncher.reviewCommand(
			executable: "/usr/bin/claude",
			server: server,
			prompt: "review it"
		)

		#expect(command.arguments.contains("--mcp-config"))
		// Without this the user's own MCP servers would join the session.
		#expect(command.arguments.contains("--strict-mcp-config"))
		#expect(command.arguments.contains("mcp__ideai__report_review_findings"))
		// The prompt must come before --allowedTools, which is variadic and would
		// otherwise swallow it as another tool name.
		#expect(command.arguments.first == "review it")
		let toolsIndex = command.arguments.firstIndex(of: "--allowedTools") ?? 0
		#expect(toolsIndex > 0)
		// Interactive, so the user can take the session over.
		#expect(!command.arguments.contains("--print"))
	}

	@Test func promptNamesTheToolsAndTheBaseBranch() {
		let prompt = AgentLauncher.reviewPrompt(baseBranch: "develop")
		#expect(prompt.contains("develop"))
		#expect(prompt.contains("report_review_findings"))
		#expect(prompt.contains("complete_review"))
	}
}

private final class Received: @unchecked Sendable {
	var value: String?
}

private final class Counter {
	var value = 0
}
