import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AbydosKit

/// What `abydos-icat` decides before it draws anything.
///
/// "Given a terminal or a pipe, a TERM, a tmux, and an answer or silence, what
/// should happen" is a function of those five things and nothing else, and the
/// script keeps it that way — `--explain-support` hands it its five answers and
/// prints what it decided, so every combination can be put to the real code
/// rather than to a copy of it. The cases are the point: telling somebody their
/// tmux needs configuring when it is their terminal that cannot draw pictures
/// sends them to fix the wrong thing, and both of those look identical from
/// inside the script if the order of the questions is wrong.
struct IcatSupportDecisionTests {
	private var script: URL { icatScript }

	/// Asks the script what it would do, and hands back the word and the
	/// sentence that goes with it.
	private func decide(
		tty: Bool,
		term: String,
		tmux: Bool,
		passthrough: Bool,
		answered: Bool,
		name: String = "Terminal.app"
	) throws -> (decision: String, message: String) {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments = [
			script.path, "--explain-support",
			tty ? "yes" : "no", term,
			tmux ? "yes" : "no", passthrough ? "yes" : "no",
			answered ? "yes" : "no", name,
		]
		let out = Pipe(), err = Pipe()
		process.standardOutput = out
		process.standardError = err
		process.standardInput = FileHandle.nullDevice
		try process.run()
		let captured = ProcessPipes.drain(process, out: out, err: err, stdin: nil)
		let lines = String(decoding: captured.stdout, as: UTF8.self)
			.split(separator: "\n", omittingEmptySubsequences: true)
		return (
			lines.first.map(String.init) ?? "",
			lines.dropFirst().joined(separator: " ")
		)
	}

	/// A pipe or a file has no graphics protocol to have, so nothing is asked
	/// and nothing is drawn.
	@Test func aPipeIsNotATerminalWhateverElseIsTrue() throws {
		for term in ["xterm-256color", "dumb", ""] {
			for answered in [true, false] {
				let result = try decide(
					tty: false, term: term, tmux: false, passthrough: false, answered: answered
				)
				#expect(result.decision == "not-a-terminal")
				#expect(result.message.contains("pipe"))
			}
		}
	}

	/// A terminal that has said it draws nothing but text is believed, without
	/// being asked a question it cannot answer.
	@Test func aTextOnlyTerminalIsTakenAtItsWord() throws {
		for term in ["dumb", "unknown"] {
			let result = try decide(
				tty: true, term: term, tmux: false, passthrough: false, answered: true
			)
			#expect(result.decision == "text-only-terminal")
			#expect(result.message.contains("TERM is \(term)"))
		}
	}

	@Test func anUnsetTermIsItsOwnAnswer() throws {
		let result = try decide(
			tty: true, term: "", tmux: false, passthrough: false, answered: false
		)
		#expect(result.decision == "no-terminal-type")
		#expect(result.message.contains("TERM is not set"))
	}

	/// The one that is actionable, and the reason the tmux answers are separate
	/// at all: `allow-passthrough` is a setting somebody can change, and saying
	/// so is worth more than naming the terminal.
	@Test func tmuxEatingTheEscapesIsSaidAsSuch() throws {
		let result = try decide(
			tty: true, term: "screen-256color", tmux: true, passthrough: false, answered: false
		)
		#expect(result.decision == "tmux-in-the-way")
		#expect(result.message.contains("allow-passthrough on"))
	}

	/// tmux out of the way and still silence means the terminal, and must not
	/// read as the sentence above — somebody sent to their tmux config by this
	/// one has been sent somewhere there is nothing to fix.
	@Test func silenceBehindAWorkingTmuxNamesTheTerminalInstead() throws {
		let result = try decide(
			tty: true, term: "screen-256color", tmux: true, passthrough: true,
			answered: false, name: "Terminal.app"
		)
		#expect(result.decision == "terminal-behind-tmux-silent")
		#expect(result.message.contains("Terminal.app"))
		#expect(!result.message.contains("allow-passthrough"))
	}

	/// No tmux, no answer: the terminal is named, and tmux is not mentioned to
	/// somebody who is not running it.
	@Test func silenceWithNoTmuxNamesTheTerminal() throws {
		let result = try decide(
			tty: true, term: "xterm-256color", tmux: false, passthrough: false,
			answered: false, name: "Terminal.app"
		)
		#expect(result.decision == "terminal-silent")
		#expect(result.message.contains("Terminal.app"))
		#expect(!result.message.lowercased().contains("tmux"))
	}

	/// An answer is an answer, tmux or no tmux.
	@Test func anAnsweringTerminalIsSupported() throws {
		for tmux in [true, false] {
			let result = try decide(
				tty: true, term: "xterm-256color", tmux: tmux, passthrough: true, answered: true
			)
			#expect(result.decision == "supported")
		}
	}

	/// Every decision has a sentence, and every sentence names the command and
	/// says something to do about it.
	@Test func everyAnswerIsOneUsableSentence() throws {
		var seen = Set<String>()
		for tty in [true, false] {
			for term in ["xterm-256color", "dumb", ""] {
				for tmux in [true, false] {
					for passthrough in [true, false] {
						for answered in [true, false] {
							let result = try decide(
								tty: tty, term: term, tmux: tmux,
								passthrough: passthrough, answered: answered
							)
							#expect(!result.decision.isEmpty)
							#expect(result.message.hasPrefix("abydos-icat: "))
							// One sentence, not a paragraph.
							#expect(!result.message.contains("\n"))
							seen.insert(result.decision)
						}
					}
				}
			}
		}
		#expect(seen == [
			"not-a-terminal", "no-terminal-type", "text-only-terminal",
			"tmux-in-the-way", "terminal-behind-tmux-silent", "terminal-silent",
			"supported",
		])
	}
}

/// What `abydos-icat` puts on the wire, run against a terminal that answers.
///
/// The script is the one part of the graphics support that is not Swift, and it
/// is the part that broke: a picture arrived missing its last few kilobytes, so
/// no terminal could decode it and every image came out as reserved space with
/// nothing in it. Nothing on this side of the pipe could have caught that —
/// only reading what the script actually wrote.
///
/// It has to be a real pty and not a pair of pipes, and it has to answer: the
/// script asks the terminal whether it has the graphics protocol and says so
/// plainly when nothing answers, so a pipe now gets a sentence rather than
/// fourteen kilobytes of base64. Which is the behaviour being relied on here —
/// `aSilentTerminalIsToldSoInsteadOfDrawnAt` is the same harness with the
/// answer withheld.
///
/// Serialized deliberately: `forkpty` forks a multithreaded process, and
/// several tests forking at once is a genuine hazard rather than a
/// test-harness quirk.
@Suite(.serialized)
struct AbydosIcatTests {
	/// Runs the script on a pty, optionally answering the graphics query the
	/// way a terminal with the protocol would, and hands back everything it
	/// wrote.
	///
	/// `tmux` puts a stand-in for tmux on the PATH and sets `TMUX`, so the
	/// branch that asks tmux for the size can be put to a split window without
	/// one being started.
	private func run(
		on file: URL, answering: Bool = true, tmux: FakeTmux? = nil
	) async throws -> Data {
		let pty = PseudoTerminal()
		pty.callbackQueue = DispatchQueue(label: "abydos.tests.icat")
		// So the ioctl carries a pixel size and the script never has to ask the
		// terminal how large a cell is — the sizes below are then the script's
		// arithmetic rather than a race with a query.
		pty.cellPixelSize = (width: 8, height: 16)

		let collected = IcatCollector()
		pty.onOutput = { [weak pty] chunk in
			collected.append(chunk)
			guard answering, collected.takeQueryOnce() else { return }
			// `ESC _ G i=31;OK ESC \` — what a terminal with the protocol says
			// to `a=q`. Echo is off by the time this arrives, which is the only
			// reason it does not come back round as part of the output.
			pty?.write(Data("\u{1B}_Gi=31;OK\u{1B}\\".utf8))
		}
		pty.onExit = { _ in collected.noteExit() }

		var environment = ProcessInfo.processInfo.environment
		// Without TMUX the plain form is used, which is the one worth checking:
		// the passthrough form only wraps it.
		environment.removeValue(forKey: "TMUX")
		// And a `TMUX_TMPDIR` too long to make a socket, for the same reason
		// one variable along: the pane says so before the script writes a byte,
		// and what this counts is lines. Inherited from the machine, so on a
		// desk where one is set this measured the sentence as well as the
		// picture — which is how it was found.
		environment = TmuxSocketPath.honouringWhatFits(environment)
		environment["TERM"] = "xterm-256color"
		if let tmux {
			environment["PATH"] = tmux.directory.path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
		}

		// Through `env`, because a pane of this app never inherits `TMUX`: it
		// names a live server connection, and the one the app was launched from
		// is not the one any pane of it is in. Set here, past the point that
		// strips it, so a pane really can be put inside a tmux for the length of
		// a test.
		let inTmux = tmux == nil ? [] : ["TMUX=/tmp/fake,1,0"]

		#expect(pty.start(
			executable: "/usr/bin/env",
			arguments: inTmux + ["/bin/sh", icatScript.path, file.path],
			environment: environment,
			rows: 40,
			columns: 100
		))
		defer { pty.terminate() }

		let deadline = Date().addingTimeInterval(60)
		while Date() < deadline, !collected.hasExited {
			try? await Task.sleep(nanoseconds: 20_000_000)
		}
		// The last write and the exit are two different events, and the exit can
		// win the race by a few milliseconds.
		try? await Task.sleep(nanoseconds: 200_000_000)
		return collected.data
	}

	/// The base64 carried by every `_G` sequence in what it wrote, minus the
	/// query, which carries four bytes of its own and is not the picture.
	private func payload(of output: Data) -> Data {
		var joined = Data()
		var index = output.startIndex
		let start = Data([0x1B, 0x5F])          // ESC _
		let terminator = Data([0x1B, 0x5C])     // ESC \

		while let opening = output[index...].range(of: start) {
			guard let closing = output[opening.upperBound...].range(of: terminator) else { break }
			let body = output[opening.upperBound..<closing.lowerBound]
			if let semicolon = body.firstIndex(of: 0x3B) {
				let keys = String(decoding: body[body.startIndex..<semicolon], as: UTF8.self)
				if !keys.contains("a=q") {
					joined.append(contentsOf: body[body.index(after: semicolon)...])
				}
			}
			index = closing.upperBound
		}
		return joined
	}

	private func temporaryImage(bytes: Data) throws -> URL {
		let file = FileManager.default.temporaryDirectory
			.appendingPathComponent("icat-\(UUID().uuidString).png")
		try bytes.write(to: file)
		return file
	}

	/// Everything the script was given arrives, to the byte.
	///
	/// The size is chosen so the base64 does *not* divide into whole 4096-byte
	/// chunks — which is every real picture, and was the bug. `fold` ends its
	/// last line without a newline, `read` returns false on a line with no
	/// newline even though it read one, and the loop body was skipped: the last
	/// chunk was never sent. It went unnoticed because the one image it was
	/// tried on happened to encode to exactly fifty-seven whole chunks.
	@Test func everyByteOfThePictureIsSent() async throws {
		// Not a real PNG: the script passes a `.png` through untouched, and
		// what is being checked is the transport rather than the picture.
		var bytes = Data(count: 0)
		for index in 0..<100_003 { bytes.append(UInt8(index % 251)) }
		let file = try temporaryImage(bytes: bytes)
		defer { try? FileManager.default.removeItem(at: file) }

		let base64 = payload(of: try await run(on: file))
		#expect(base64.count % 4 == 0)
		// The property that matters, and the one that would have caught it.
		#expect(base64.count % 4096 != 0, "pick a size that does not divide evenly")

		let decoded = try #require(Data(base64Encoded: base64))
		#expect(decoded.count == bytes.count)
		#expect(decoded == bytes)
	}

	/// A picture small enough for one chunk is sent in one, with the keys and
	/// the end marker on it.
	@Test func aSmallPictureIsOneChunkWithTheKeysOnIt() async throws {
		let file = try temporaryImage(bytes: Data([UInt8](repeating: 0x7A, count: 300)))
		defer { try? FileManager.default.removeItem(at: file) }

		let output = try await run(on: file)
		let text = String(decoding: output, as: UTF8.self)
		#expect(text.contains("f=100,a=T,U=1"))
		#expect(text.contains("m=0"))
		#expect(payload(of: output).count == 400)
	}

	/// The picture is shown by writing placeholder cells, and there are exactly
	/// as many of them as the size it told the terminal.
	///
	/// This is what stops the picture being followed by a field of blank lines
	/// or scrolling away before it can be looked at: the rows written are the
	/// rows it covers, so there is no second number that has to agree.
	@Test func thePlaceholderCellsMatchTheSizeItAskedFor() async throws {
		let file = try temporaryImage(bytes: Data([UInt8](repeating: 0x7A, count: 5_000)))
		defer { try? FileManager.default.removeItem(at: file) }

		let output = try await run(on: file)
		let text = String(decoding: output, as: UTF8.self)

		let keys = try #require(transmitKeys(in: text), "no control data")
		let columns = try #require(value(of: "c", in: keys))
		let rows = try #require(value(of: "r", in: keys))
		#expect(columns > 0 && rows > 0)

		// Scalars, not characters: the first cell of a row carries combining
		// marks, and base-plus-mark is one Character that is not the bare one.
		let placeholders = text.unicodeScalars.filter { $0.value == 0x10EEEE }.count
		#expect(placeholders == columns * rows)
		// One line per row of the picture, and no more: anything extra is the
		// gap after the image. A pty turns each into CR LF, so the LFs are
		// counted and the CRs ignored.
		#expect(text.unicodeScalars.filter { $0 == "\n" }.count == rows)
	}

	/// The whole point of asking first: a terminal that says nothing is told
	/// so, in one sentence, instead of being sent a picture it cannot draw.
	///
	/// What it used to do here was write the lot — the escape sequences and
	/// three thousand placeholder cells — and exit zero, which reads as a
	/// broken command rather than as a terminal that has no graphics protocol.
	@Test func aSilentTerminalIsToldSoInsteadOfDrawnAt() async throws {
		let file = try temporaryImage(bytes: Data([UInt8](repeating: 0x7A, count: 5_000)))
		defer { try? FileManager.default.removeItem(at: file) }

		let output = try await run(on: file, answering: false)
		let text = String(decoding: output, as: UTF8.self)

		#expect(text.contains("did not answer the graphics query"))
		#expect(!text.contains("f=100,a=T"), "it drew the picture anyway")
		#expect(!text.unicodeScalars.contains { $0.value == 0x10EEEE }, "placeholder cells")
		// The query itself is all it should have put on the terminal, and it is
		// forty bytes rather than fourteen thousand.
		#expect(text.contains("a=q"))
	}

	/// A picture in a tmux pane is sized to the pane, not to the window it is
	/// one of.
	///
	/// This is what "icat does not scale an image inside tmux" turned out to be.
	/// The script asked tmux for `#{window_width}`, which is the whole window
	/// however many panes it is split into, so in a split every picture was
	/// worked out for a screen twice the width it had: it ran off the right-hand
	/// edge of the pane and tmux wrapped the cells carrying it, which tore the
	/// picture across the rows. Unsplit it looked perfect, because a lone pane
	/// *is* the window — which is why it read as tmux breaking the protocol
	/// rather than as one word in a format string.
	@Test func aPictureIsSizedToItsPaneAndNotToTheWholeWindow() async throws {
		let tmux = try FakeTmux(
			cell: (width: 8, height: 16), window: (columns: 100, rows: 40),
			pane: (columns: 40, rows: 20)
		)
		defer { tmux.remove() }

		// Twice as wide as it is tall, and far wider than either the window or
		// the pane, so both of them clamp it and the two answers differ.
		let file = try temporaryImage(bytes: try pngData(width: 1600, height: 800))
		defer { try? FileManager.default.removeItem(at: file) }

		let output = try await run(on: file, tmux: tmux)
		let text = String(decoding: output, as: UTF8.self)
		let keys = try #require(transmitKeys(in: text), "no control data")
		let columns = try #require(value(of: "c", in: keys))
		let rows = try #require(value(of: "r", in: keys))

		#expect(columns == 40, "sized to the window's 100 columns rather than the pane's 40")
		// The proportions kept: 40 cells of 8 pixels by 10 of 16 is 320×160,
		// which is the picture's own 2:1.
		#expect(rows == 10)
		// And the cells written are the size it asked for, so nothing wraps.
		let placeholders = text.unicodeScalars.filter { $0.value == 0x10EEEE }.count
		#expect(placeholders == columns * rows)
	}

	/// The keys of the transmit command — the first `_G` that is not the query.
	private func transmitKeys(in text: String) -> String? {
		var rest = Substring(text)
		while let opening = rest.range(of: "\u{1B}_G") {
			let body = rest[opening.upperBound...]
			guard let semicolon = body.firstIndex(of: ";") else { return nil }
			let keys = String(body[body.startIndex..<semicolon])
			if !keys.contains("a=q") { return keys }
			rest = body[semicolon...]
		}
		return nil
	}

	/// The value of one key in the control data.
	private func value(of key: String, in keys: String) -> Int? {
		for pair in keys.split(separator: ",") {
			let parts = pair.split(separator: "=")
			guard parts.count == 2, parts[0].hasSuffix(key), parts[0].count <= 3 else { continue }
			if String(parts[0]).hasSuffix(key) { return Int(parts[1]) }
		}
		return nil
	}
}

/// A tmux that is not tmux, answering the three things the script asks it.
///
/// A real one would need a server, a client on a pty and a split — and then the
/// sizes would be whatever that machine's window happened to be. This is a
/// script on the PATH that says a window is one size and the pane inside it
/// another, which is the whole of what the case needs.
private struct FakeTmux {
	let directory: URL

	init(cell: (width: Int, height: Int), window: (columns: Int, rows: Int), pane: (columns: Int, rows: Int)) throws {
		directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("icat-tmux-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		let script = """
		#!/bin/sh
		# `show -Apv allow-passthrough`, and `display -p <format>`.
		case "$1" in
			show) echo on ;;
			display)
				printf '%s\\n' "$3" \\
					| sed -e 's/#{client_cell_width}/\(cell.width)/g' \\
						-e 's/#{client_cell_height}/\(cell.height)/g' \\
						-e 's/#{window_width}/\(window.columns)/g' \\
						-e 's/#{window_height}/\(window.rows)/g' \\
						-e 's/#{pane_width}/\(pane.columns)/g' \\
						-e 's/#{pane_height}/\(pane.rows)/g' \\
						-e 's/#{client_termname}/xterm-256color/g'
				;;
		esac
		exit 0
		"""
		let path = directory.appendingPathComponent("tmux")
		try script.write(to: path, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
	}

	func remove() {
		try? FileManager.default.removeItem(at: directory)
	}
}

/// A real PNG of a given size, since the size is what the script reads back out
/// of it with `sips`.
private func pngData(width: Int, height: Int) throws -> Data {
	let context = try #require(CGContext(
		data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
		space: CGColorSpaceCreateDeviceRGB(),
		bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
	))
	context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
	context.fill(CGRect(x: 0, y: 0, width: width, height: height))
	let image = try #require(context.makeImage())

	let data = NSMutableData()
	let destination = try #require(
		CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
	)
	CGImageDestinationAddImage(destination, image, nil)
	#expect(CGImageDestinationFinalize(destination))
	return data as Data
}

/// Where the script is, from wherever the tests were built.
private var icatScript: URL {
	URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent()   // AbydosKitTests
		.deletingLastPathComponent()   // Tests
		.deletingLastPathComponent()   // repository
		.appendingPathComponent("Scripts/abydos-icat")
}

/// Accumulates the pty's output, and answers the graphics query exactly once.
private final class IcatCollector: @unchecked Sendable {
	private var collected = Data()
	private var answeredQuery = false
	private var exited = false
	private let lock = NSLock()

	func append(_ chunk: Data) {
		lock.lock(); defer { lock.unlock() }
		collected.append(chunk)
	}

	var data: Data {
		lock.lock(); defer { lock.unlock() }
		return collected
	}

	func noteExit() {
		lock.lock(); defer { lock.unlock() }
		exited = true
	}

	var hasExited: Bool {
		lock.lock(); defer { lock.unlock() }
		return exited
	}

	/// True the first time the query has arrived, and never again — a second
	/// reply would land after the script had put the terminal back, where it
	/// would be echoed into the output as though the script had written it.
	func takeQueryOnce() -> Bool {
		lock.lock(); defer { lock.unlock() }
		guard !answeredQuery, collected.range(of: Data("a=q".utf8)) != nil else { return false }
		answeredQuery = true
		return true
	}
}
