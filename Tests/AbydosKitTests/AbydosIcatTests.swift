import Foundation
import Testing
@testable import AbydosKit

/// What `abydos-icat` puts on the wire.
///
/// The script is the one part of the graphics support that is not Swift, and it
/// is the part that broke: a picture arrived missing its last few kilobytes, so
/// no terminal could decode it and every image came out as reserved space with
/// nothing in it. Nothing on this side of the pipe could have caught that —
/// only reading what the script actually wrote.
struct AbydosIcatTests {
	private var script: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()   // AbydosKitTests
			.deletingLastPathComponent()   // Tests
			.deletingLastPathComponent()   // repository
			.appendingPathComponent("Scripts/abydos-icat")
	}

	/// Runs it with its output on a pipe and hands back what it wrote.
	private func run(on file: URL) throws -> Data {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments = [script.path, file.path]
		// Without TMUX the plain form is used, which is the one worth checking:
		// the passthrough form only wraps it.
		var environment = ProcessInfo.processInfo.environment
		environment.removeValue(forKey: "TMUX")
		environment["TERM"] = "xterm-256color"
		process.environment = environment

		let out = Pipe(), err = Pipe()
		process.standardOutput = out
		process.standardError = err
		process.standardInput = Pipe()
		try process.run()
		let captured = ProcessPipes.drain(process, out: out, err: err, stdin: nil)
		return captured.stdout
	}

	/// The base64 carried by every `_G` sequence in what it wrote.
	private func payload(of output: Data) -> Data {
		var joined = Data()
		var index = output.startIndex
		let start = Data([0x1B, 0x5F])          // ESC _
		let terminator = Data([0x1B, 0x5C])     // ESC \

		while let opening = output[index...].range(of: start) {
			guard let closing = output[opening.upperBound...].range(of: terminator) else { break }
			let body = output[opening.upperBound..<closing.lowerBound]
			if let semicolon = body.firstIndex(of: 0x3B) {
				joined.append(contentsOf: body[body.index(after: semicolon)...])
			}
			index = closing.upperBound
		}
		return joined
	}

	/// Everything the script was given arrives, to the byte.
	///
	/// The size is chosen so the base64 does *not* divide into whole 4096-byte
	/// chunks — which is every real picture, and was the bug. `fold` ends its
	/// last line without a newline, `read` returns false on a line with no
	/// newline even though it read one, and the loop body was skipped: the last
	/// chunk was never sent. It went unnoticed because the one image it was
	/// tried on happened to encode to exactly fifty-seven whole chunks.
	@Test func everyByteOfThePictureIsSent() throws {
		let file = FileManager.default.temporaryDirectory
			.appendingPathComponent("icat-\(UUID().uuidString).png")
		defer { try? FileManager.default.removeItem(at: file) }

		// Not a real PNG: the script passes a `.png` through untouched, and
		// what is being checked is the transport rather than the picture.
		var bytes = Data(count: 0)
		for index in 0..<100_003 { bytes.append(UInt8(index % 251)) }
		try bytes.write(to: file)

		let base64 = payload(of: try run(on: file))
		#expect(base64.count % 4 == 0)
		// The property that matters, and the one that would have caught it.
		#expect(base64.count % 4096 != 0, "pick a size that does not divide evenly")

		let decoded = try #require(Data(base64Encoded: base64))
		#expect(decoded.count == bytes.count)
		#expect(decoded == bytes)
	}

	/// A picture small enough for one chunk is sent in one, with the keys and
	/// the end marker on it.
	@Test func aSmallPictureIsOneChunkWithTheKeysOnIt() throws {
		let file = FileManager.default.temporaryDirectory
			.appendingPathComponent("icat-\(UUID().uuidString).png")
		defer { try? FileManager.default.removeItem(at: file) }
		try Data([UInt8](repeating: 0x7A, count: 300)).write(to: file)

		let output = try run(on: file)
		let text = String(decoding: output, as: UTF8.self)
		#expect(text.contains("f=100,a=T"))
		#expect(text.contains("m=0"))
		#expect(payload(of: output).count == 400)
	}
}
