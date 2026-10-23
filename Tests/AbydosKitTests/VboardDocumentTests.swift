import Foundation
import Testing
@testable import AbydosKit

/// A `.vboard` open as a board: putting it there, saving it back, and what a
/// change on the board or on the disk does to it.
///
/// Against the same stub as `VboardClientTests`, answering as `vboard-local`
/// 0.67.0 answered.
@MainActor
struct VboardDocumentTests {
	private func copy(_ fixture: String) throws -> URL {
		let source = try #require(Bundle.module.url(forResource: fixture, withExtension: "vboard", subdirectory: "Fixtures"))
		let directory = try scratch()
		let url = directory.appendingPathComponent("\(fixture).vboard")
		try FileManager.default.copyItem(at: source, to: url)
		return url
	}

	private func scratch() throws -> URL {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vboard-doc-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}

	private func document(_ url: URL, answer: @escaping StubServer.Answer) -> (VboardDocument, StubServer) {
		let stub = StubServer(answer: answer)
		return (VboardDocument(url: url, client: VboardClient(server: stub.base, protocolClasses: [StubProtocol.self])), stub)
	}

	private static let exported = #"{"format":"vboard","version":1,"app":"0.67.0","board":{"name":"Retro"},"items":[{"id":"i_1","type":"sticky","data":{"text":"added on the board"}}],"entries":[],"assets":[]}"#

	// MARK: Opening

	@Test func aBoardFileIsImportedUnderTheDocumentsIdAndKey() async throws {
		let (document, stub) = document(try copy("retro")) { _ in (201, "{}", [:]) }
		#expect(await document.open() == .onBoard)
		let request = try #require(stub.requests.first)
		#expect(request.url.path == "/api/v1/boards/import")
		#expect(request.url.query?.contains("id=\(document.boardID)") == true)
		#expect(request.headers["X-Board-Key"] == document.key.encoded)
		#expect(!document.isDirty)
	}

	@Test func anEmptyFileIsCreatedAndNamedAfterItself() async throws {
		let url = try scratch().appendingPathComponent("my.vboard")
		try Data().write(to: url)
		let (document, stub) = document(url) { _ in (201, "{}", [:]) }
		#expect(await document.open() == .onBoard)
		let request = try #require(stub.requests.first)
		#expect(request.url.path == "/api/v1/boards")
		let body = try JSONSerialization.jsonObject(with: request.body) as? [String: Any]
		#expect(body?["name"] as? String == "my")
		#expect(try Data(contentsOf: url).isEmpty, "opening a file must not write it")
	}

	@Test func aTakenIdIsTriedOnceMoreWithAnother() async throws {
		var answered = 0
		let (document, stub) = document(try copy("retro")) { _ in
			answered += 1
			return answered == 1 ? (409, #"{"error":"taken"}"#, [:]) : (201, "{}", [:])
		}
		#expect(await document.open() == .onBoard)
		let ids = stub.requests.compactMap { URLComponents(url: $0.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value }
		#expect(ids.count == 2)
		#expect(ids[0] != ids[1])
		#expect(ids[1] == document.boardID)
	}

	@Test func anEncryptedFileIsNeverSent() async throws {
		let (document, stub) = document(try copy("encrypted")) { _ in (201, "{}", [:]) }
		#expect(await document.open() == .refusedFile(.encrypted))
		#expect(stub.requests.isEmpty)
	}

	@Test func aServerThatWantsASignInSaysSo() async throws {
		let (document, _) = document(try copy("retro")) { _ in (401, #"{"error":"login"}"#, [:]) }
		#expect(await document.open() == .failed(.signedOut))
	}

	// MARK: Changes and saving

	@Test func aChangeOnTheBoardMarksItAndASaveClearsIt() async throws {
		let url = try copy("retro")
		let (document, _) = document(url) { request in
			request.method == "GET" ? (200, Self.exported, [:]) : (201, "{}", [:])
		}
		_ = await document.open()
		var told = 0
		document.onDirtyChanged = { told += 1 }
		document.noteChange()
		document.noteChange()
		#expect(document.isDirty)
		#expect(told == 1)
		try await document.save()
		#expect(!document.isDirty)
		#expect(told == 2)
		#expect(String(decoding: try Data(contentsOf: url), as: UTF8.self) == Self.exported)
		#expect(!document.hasChangedOnDisk, "the save is the document's own write")
	}

	@Test func aChangeThatArrivesDuringTheSaveKeepsTheDot() async throws {
		let url = try copy("retro")
		var document: VboardDocument!
		let made = self.document(url) { request in
			guard request.method == "GET" else { return (201, "{}", [:]) }
			// A colleague moves an item while the export is on its way.
			DispatchQueue.main.sync { document.noteChange() }
			return (200, Self.exported, [:])
		}
		document = made.0
		_ = await document.open()
		document.noteChange()
		try await document.save()
		#expect(document.isDirty)
	}

	@Test func aSaveThatFailsLeavesTheFileAndTheDot() async throws {
		let url = try copy("retro")
		let before = try Data(contentsOf: url)
		let (document, _) = document(url) { request in
			request.method == "GET" ? (200, "<!doctype html>sign in", [:]) : (201, "{}", [:])
		}
		_ = await document.open()
		document.noteChange()
		await #expect(throws: VboardDocument.SaveFailure.server(.signedOut)) { try await document.save() }
		#expect(try Data(contentsOf: url) == before)
		#expect(document.isDirty)
		let leftovers = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
		#expect(leftovers == ["retro.vboard"])
	}

	@Test func itIsNeverAutoSaved() async throws {
		let (document, _) = document(try copy("retro")) { _ in (201, "{}", [:]) }
		document.noteChange()
		#expect(!document.autoSaveIfNeeded())
		#expect(document.isDirty)
	}

	// MARK: Somebody else writing the file

	@Test func anExternalWriteIsNoticed() async throws {
		let url = try copy("retro")
		let (document, _) = document(url) { _ in (201, "{}", [:]) }
		_ = await document.open()
		#expect(!document.hasChangedOnDisk)
		try Data(Self.exported.utf8).write(to: url)
		#expect(document.hasChangedOnDisk)
	}

	@Test func aNewerFileReplacesTheBoardInPlace() async throws {
		var imports = 0
		let (document, _) = document(try copy("retro")) { _ in
			imports += 1
			return imports == 1 ? (201, "{}", [:]) : (200, #"{"replaced":true}"#, [:])
		}
		_ = await document.open()
		let id = document.boardID, key = document.key
		#expect(await document.reload() == .replaced)
		#expect(document.boardID == id)
		#expect(document.key == key)
	}

	@Test func anOlderFileEndsTheBoardAndOpensANewOneWithANewKey() async throws {
		var imports = 0
		let (document, stub) = document(try copy("retro")) { request in
			switch request.method {
			case "DELETE": return (204, "", [:])
			default:
				imports += 1
				// The first import opens; the replace is refused as not newer.
				return imports == 2 ? (409, #"{"error":"not newer"}"#, [:]) : (201, "{}", [:])
			}
		}
		_ = await document.open()
		let id = document.boardID, key = document.key
		#expect(await document.reload() == .reopened)
		#expect(document.boardID != id)
		#expect(document.key != key)
		#expect(stub.requests.contains { $0.method == "DELETE" && $0.url.path.hasSuffix(id) })
	}
}
