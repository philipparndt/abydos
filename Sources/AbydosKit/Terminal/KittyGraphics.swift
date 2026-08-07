import Compression
import CoreGraphics
import Foundation
import ImageIO

/// The kitty graphics protocol: real pictures on the character grid.
///
/// A program sends `ESC _ G <key>=<value>,… ; <base64 payload> ESC \`, which is
/// an APC sequence — the one class of escape a terminal is free to define for
/// itself. The keys say what to do (transmit an image, place one that was
/// transmitted earlier, delete one, or merely ask whether any of this works),
/// and the payload carries either the pixels or the path of a file holding
/// them.
///
/// Kept here rather than in the emulator, and free of AppKit, for the reason
/// the emulator itself gives: a picture arriving as bytes and coming out as a
/// rectangle of pixels at a known place on the grid is testable without a
/// window, and it is the part most likely to be wrong.
///
/// Animation, shared-memory transfer and the Unicode placeholder scheme are not
/// here. The first two are used by almost nothing; the third is what carries
/// images through tmux, and is a piece of work in its own right.
public enum KittyGraphics {
	/// Largest total the stored images may come to before the oldest of them are
	/// dropped.
	///
	/// A program can transmit in a loop — a plotting library redrawing, a video
	/// player — and each frame arrives as a fresh image whether or not the last
	/// one is still wanted. Without a ceiling that is unbounded growth driven by
	/// something the terminal does not control.
	public static let memoryBudget = 128 << 20

	/// Most bytes one transfer may come to, chunks included.
	///
	/// A chunked transfer is open-ended by construction: the program says "more
	/// follows" and the terminal holds what it has. A stream that never says it
	/// has finished must not be able to grow the process.
	static let largestTransfer = 32 << 20
}

// MARK: - The command

/// One `ESC _ G` sequence, split into its keys and its payload.
public struct KittyGraphicsCommand: Equatable, Sendable {
	/// The `a` key: what to do.
	public enum Action: Equatable, Sendable {
		case query        // q
		case transmit     // t
		case place        // T — transmit and place in one go
		case display      // p — place something already sent
		case delete       // d
	}

	/// The `t` key: where the bytes are.
	public enum Medium: Equatable, Sendable {
		case direct       // d — in the payload
		case file         // f — the payload is a path
		case temporaryFile // t — a path, deleted once read
		case sharedMemory // s — not supported
	}

	/// The `f` key: what the bytes mean.
	public enum Format: Equatable, Sendable {
		case rgb          // 24
		case rgba         // 32
		case png          // 100
	}

	public var action: Action = .transmit
	public var medium: Medium = .direct
	public var format: Format = .rgba
	/// `i` — the id the program refers to this image by.
	public var id: UInt32 = 0
	/// `I` — a number the terminal turns into an id, for a program that would
	/// rather not pick one.
	public var number: UInt32 = 0
	/// `p` — which of an image's placements this is.
	public var placementID: UInt32 = 0
	/// `s`, `v` — the pixel size, for the raw formats that do not carry it.
	public var pixelWidth = 0
	public var pixelHeight = 0
	/// `S`, `O` — how much of a file to read and where to start.
	public var readSize = 0
	public var readOffset = 0
	/// `m` — whether another chunk follows.
	public var hasMoreChunks = false
	/// `o` — whether the payload is compressed.
	public var isCompressed = false
	/// `x`, `y`, `w`, `h` — the part of the image to show.
	public var sourceX = 0
	public var sourceY = 0
	public var sourceWidth = 0
	public var sourceHeight = 0
	/// `X`, `Y` — where within the first cell the image starts.
	public var cellOffsetX = 0
	public var cellOffsetY = 0
	/// `c`, `r` — how many cells to draw it across, scaling it to fit.
	public var columns = 0
	public var rows = 0
	/// `z` — what it is drawn in front of and behind.
	public var z: Int32 = 0
	/// `C` — whether the cursor stays where it is.
	public var leavesCursor = false
	/// `d` — which of the ways to delete.
	public var deletion: UInt8 = 0x61 // a
	/// `q` — how much of an answer the program wants.
	public var quiet = 0

	/// The bytes after the `;`, still base64.
	public var payload: [UInt8] = []

	/// Reads a sequence's control data and payload.
	///
	/// Unknown keys are skipped rather than refused: the protocol grows, and a
	/// program that sends a key from a later version than this expects the rest
	/// of its command to be carried out anyway.
	public init(_ bytes: [UInt8]) {
		// `ESC _ G` has already been recognised; what arrives here is what
		// followed the G.
		var index = 0
		var control: [UInt8] = []
		while index < bytes.count, bytes[index] != 0x3B { // ;
			control.append(bytes[index])
			index += 1
		}
		if index < bytes.count { index += 1 } // the ; itself
		payload = Array(bytes[index...])

		for pair in control.split(separator: 0x2C) { // ,
			guard let equals = pair.firstIndex(of: 0x3D), equals > pair.startIndex else { continue }
			let key = pair[pair.startIndex]
			let value = Array(pair[pair.index(after: equals)...])
			guard !value.isEmpty else { continue }
			apply(key: key, value: value)
		}
	}

	private mutating func apply(key: UInt8, value: [UInt8]) {
		/// Values are decimal, and may be negative — only `z` ever is.
		func integer() -> Int {
			var result = 0
			var negative = false
			for byte in value {
				if byte == 0x2D { negative = true; continue }
				guard byte >= 0x30, byte <= 0x39 else { return 0 }
				// Capped for the same reason the CSI parser caps its parameters: a
				// long run of digits is not a number anybody meant to send, and it
				// must not trap.
				result = Swift.min(result * 10 + Int(byte - 0x30), 1 << 40)
			}
			return negative ? -result : result
		}

		switch key {
		case 0x61: // a
			switch value.first {
			case 0x71: action = .query   // q
			case 0x74: action = .transmit // t
			case 0x54: action = .place   // T
			case 0x70: action = .display // p
			case 0x64: action = .delete  // d
			default: break
			}
		case 0x74: // t
			switch value.first {
			case 0x64: medium = .direct
			case 0x66: medium = .file
			case 0x54, 0x74: medium = .temporaryFile
			case 0x73: medium = .sharedMemory
			default: break
			}
		case 0x66: // f
			switch integer() {
			case 24: format = .rgb
			case 32: format = .rgba
			case 100: format = .png
			default: break
			}
		case 0x69: id = UInt32(clamping: integer())            // i
		case 0x49: number = UInt32(clamping: integer())        // I
		case 0x70: placementID = UInt32(clamping: integer())   // p
		case 0x73: pixelWidth = integer()                      // s
		case 0x76: pixelHeight = integer()                     // v
		case 0x53: readSize = integer()                        // S
		case 0x4F: readOffset = integer()                      // O
		case 0x6D: hasMoreChunks = integer() == 1              // m
		case 0x6F: isCompressed = value.first == 0x7A          // o=z
		case 0x78: sourceX = integer()                         // x
		case 0x79: sourceY = integer()                         // y
		case 0x77: sourceWidth = integer()                     // w
		case 0x68: sourceHeight = integer()                    // h
		case 0x58: cellOffsetX = integer()                     // X
		case 0x59: cellOffsetY = integer()                     // Y
		case 0x63: columns = integer()                         // c
		case 0x72: rows = integer()                            // r
		case 0x7A: z = Int32(clamping: integer())              // z
		case 0x43: leavesCursor = integer() == 1               // C
		case 0x64: deletion = value.first ?? 0x61              // d
		case 0x71: quiet = integer()                           // q
		default: break
		}
	}
}

// MARK: - Pixels

/// An image a program has sent, decoded and ready to draw.
public struct TerminalImage: Equatable, Sendable {
	public let id: UInt32
	public let number: UInt32
	public let width: Int
	public let height: Int
	/// RGBA, eight bits a channel, alpha already multiplied in.
	///
	/// Premultiplied because that is the one form both drawing paths can take
	/// without converting: CoreGraphics will not build a bitmap any other way,
	/// and the GPU path blends with it directly.
	public let pixels: [UInt8]

	public var byteCount: Int { pixels.count }
}

/// Where an image is shown, and how much of it.
///
/// The row is **absolute** — an index into scrollback and grid together, the
/// same coordinate the dirty range and the selection use. That is what makes a
/// picture scroll with the text that introduced it, survive into history, and
/// come back when somebody scrolls up to it. Anchoring to a grid row instead
/// would leave it hanging in place while the output around it moved.
public struct TerminalImagePlacement: Equatable, Sendable {
	public var imageID: UInt32
	public var placementID: UInt32
	public var row: Int
	public var column: Int
	/// How many cells across and down it is drawn over.
	public var columns: Int
	public var rows: Int
	/// The part of the image to draw, in its own pixels.
	public var source: Rectangle
	/// Where inside the first cell the picture starts.
	public var offsetX: Int
	public var offsetY: Int
	public var z: Int32

	public struct Rectangle: Equatable, Sendable {
		public var x: Int
		public var y: Int
		public var width: Int
		public var height: Int

		public init(x: Int, y: Int, width: Int, height: Int) {
			self.x = x
			self.y = y
			self.width = width
			self.height = height
		}
	}

	/// The rows it covers, for marking them as needing to be drawn again.
	public var rowRange: ClosedRange<Int> { row...(row + max(1, rows) - 1) }
}

// MARK: - The store

/// What the emulator needs to tell the store about where things are.
public struct TerminalGraphicsContext {
	public var scrollbackCount: Int
	public var cursorRow: Int
	public var cursorColumn: Int
	public var rows: Int
	public var columns: Int

	public init(scrollbackCount: Int, cursorRow: Int, cursorColumn: Int, rows: Int, columns: Int) {
		self.scrollbackCount = scrollbackCount
		self.cursorRow = cursorRow
		self.cursorColumn = cursorColumn
		self.rows = rows
		self.columns = columns
	}
}

/// What carrying out a command asks the emulator to do afterwards.
public struct TerminalGraphicsResult {
	/// What to send back to the program, if anything.
	public var response: String?
	/// How far to move the cursor, in cells, after a placement.
	public var cursorAdvance: (rows: Int, columns: Int)?
	/// Rows whose appearance changed.
	public var dirtyRows: ClosedRange<Int>?
}

/// The images a terminal is holding and where they are shown.
public final class TerminalImageStore {
	/// Decoded images, by the id the program refers to them by.
	public private(set) var images: [UInt32: TerminalImage] = [:]
	/// Every placement on the screen the program is drawing on.
	public private(set) var placements: [TerminalImagePlacement] = []

	/// Bumped whenever anything changes, so a view can tell whether the textures
	/// it built are still the ones being asked for.
	public private(set) var generation = 0

	/// Cell size, needed to turn pixels into a number of cells.
	public var cellPixelSize: (width: Int, height: Int) = (0, 0)

	/// Ids the terminal handed out for programs that sent a number instead.
	private var idsByNumber: [UInt32: UInt32] = [:]
	private var nextAssignedID: UInt32 = 1 << 24
	/// Which images were used least recently, oldest first.
	private var useOrder: [UInt32] = []
	private var storedBytes = 0

	/// A transfer part-way through arriving.
	private var pendingCommand: KittyGraphicsCommand?
	private var pendingPayload: [UInt8] = []

	public init() {}

	// MARK: Screens

	/// Placements belong to the screen they were made on.
	///
	/// A full-screen program switching to the alternate screen must not find the
	/// pictures the shell left behind, and going back to the shell must find them
	/// again — the same rule the text follows.
	public func takePlacements() -> [TerminalImagePlacement] {
		defer {
			placements = []
			generation += 1
		}
		return placements
	}

	public func restorePlacements(_ restored: [TerminalImagePlacement]) {
		placements = restored
		generation += 1
	}

	public func removeAll() {
		images = [:]
		placements = []
		idsByNumber = [:]
		useOrder = []
		storedBytes = 0
		pendingCommand = nil
		pendingPayload = []
		generation += 1
	}

	/// Drops the pictures standing on rows that have just been erased.
	///
	/// Erasing the text under a picture used to leave the picture: nothing in
	/// the protocol says clearing the screen takes one away, and no program
	/// sends a delete for a picture it drew — least of all tmux, which repaints
	/// over what it does not know is there. So a picture printed inside tmux
	/// stayed on the screen through `clear` and every redraw after it, and the
	/// only way to be rid of it was to restart the terminal.
	public func removePlacements(inRows rows: ClosedRange<Int>) {
		let before = placements.count
		placements.removeAll { $0.rowRange.overlaps(rows) }
		guard placements.count != before else { return }
		generation += 1
	}

	/// Lines fell off the top of scrollback, so every absolute row moved.
	public func shiftRows(by delta: Int) {
		guard delta != 0, !placements.isEmpty else { return }
		for index in placements.indices {
			placements[index].row -= delta
		}
		// A picture whose last row has gone past the start of the buffer can
		// never be drawn again.
		placements.removeAll { $0.rowRange.upperBound < 0 }
		generation += 1
	}

	// MARK: Commands

	/// Carries out one sequence.
	public func apply(_ command: KittyGraphicsCommand, context: TerminalGraphicsContext) -> TerminalGraphicsResult {
		switch command.action {
		case .delete:
			return delete(command, context: context)
		case .display:
			return display(command, context: context)
		case .query, .transmit, .place:
			return receive(command, context: context)
		}
	}

	// MARK: Receiving

	private func receive(
		_ command: KittyGraphicsCommand,
		context: TerminalGraphicsContext
	) -> TerminalGraphicsResult {
		// A chunked transfer only carries its control data on the first chunk;
		// the rest say nothing but "more of the same".
		var command = command
		if var started = pendingCommand {
			started.hasMoreChunks = command.hasMoreChunks
			// The tail of a transfer may still choose to place what arrived.
			if command.action != .transmit { started.action = command.action }
			pendingPayload.append(contentsOf: command.payload)
			command = started
			command.payload = []
		} else if command.hasMoreChunks {
			pendingPayload = command.payload
			var started = command
			started.payload = []
			pendingCommand = started
			return .init()
		}

		if command.hasMoreChunks {
			guard pendingPayload.count <= KittyGraphics.largestTransfer else {
				pendingCommand = nil
				pendingPayload = []
				return respond(command, "EINVAL:transfer too large")
			}
			return .init()
		}

		let encoded = pendingCommand == nil ? command.payload : pendingPayload
		pendingCommand = nil
		pendingPayload = []

		switch decode(command, encoded: encoded) {
		case let .failure(message):
			return respond(command, message)
		case let .success(image):
			// A query is a rehearsal: the bytes are checked exactly as they would
			// be, and then thrown away. It is how a program finds out whether any
			// of this is worth attempting.
			if command.action == .query {
				return respond(command, "OK", force: true)
			}

			store(image)
			guard command.action == .place else {
				return respond(command, "OK")
			}
			var result = place(image: image, command: command, context: context)
			if result.response == nil {
				result.response = respond(command, "OK").response
			}
			return result
		}
	}

	private enum Decoded {
		case success(TerminalImage)
		case failure(String)
	}

	private func decode(_ command: KittyGraphicsCommand, encoded: [UInt8]) -> Decoded {
		guard var data = Self.base64(encoded) else {
			return .failure("EINVAL:payload is not base64")
		}

		switch command.medium {
		case .sharedMemory:
			return .failure("EBADF:shared memory transfer is not supported")
		case .file, .temporaryFile:
			guard let path = String(data: data, encoding: .utf8), !path.isEmpty else {
				return .failure("EINVAL:no path in the payload")
			}
			guard let contents = readFile(at: path, command: command) else {
				return .failure("EBADF:cannot read \(path)")
			}
			data = contents
			// A temporary file is the sender's way of handing over something too
			// large for an escape sequence; it is ours to remove once read, and
			// leaving it behind fills somebody's disk a picture at a time.
			if command.medium == .temporaryFile, isSafeToDelete(path) {
				try? FileManager.default.removeItem(atPath: path)
			}
		case .direct:
			break
		}

		if command.isCompressed {
			guard let inflated = inflate(data) else {
				return .failure("EINVAL:payload does not inflate")
			}
			data = inflated
		}

		let id = assignedID(for: command)
		switch command.format {
		case .png:
			guard let image = decodePNG(data, id: id, number: command.number) else {
				return .failure("EINVAL:not a readable PNG")
			}
			return .success(image)
		case .rgb, .rgba:
			let channels = command.format == .rgb ? 3 : 4
			let width = command.pixelWidth
			let height = command.pixelHeight
			guard width > 0, height > 0 else {
				return .failure("EINVAL:raw pixels need s and v")
			}
			guard width * height * channels == data.count else {
				return .failure("EINVAL:\(data.count) bytes is not \(width)x\(height)")
			}
			return .success(TerminalImage(
				id: id,
				number: command.number,
				width: width,
				height: height,
				pixels: premultiplied(Array(data), channels: channels)
			))
		}
	}

	/// Base64 as the protocol actually carries it, rather than as Foundation
	/// would like it.
	///
	/// `Data(base64Encoded:)` refuses anything whose length is not a multiple of
	/// four, and kitty leaves the padding off. That is not an edge case: `icat`
	/// sending a file path — a path is rarely a multiple of three bytes long —
	/// decoded to nothing at all, so the picture never arrived and, with `q=2`
	/// set as every real client sets it, nothing was said about why.
	///
	/// The padding is put back here instead of being demanded of the sender.
	static func base64(_ bytes: [UInt8]) -> Data? {
		// Anything outside the alphabet is dropped first — a chunked transfer may
		// carry a stray newline, and the padding has to be counted from what is
		// really there.
		var cleaned = bytes.filter {
			($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A)
				|| ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2B || $0 == 0x2F
		}
		let remainder = cleaned.count % 4
		if remainder != 0 {
			cleaned.append(contentsOf: [UInt8](repeating: 0x3D, count: 4 - remainder))
		}
		return Data(base64Encoded: Data(cleaned))
	}

	/// Reads what a transfer points at, honouring the offset and length it gave.
	private func readFile(at path: String, command: KittyGraphicsCommand) -> Data? {
		guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
		defer { try? handle.close() }
		if command.readOffset > 0 {
			try? handle.seek(toOffset: UInt64(command.readOffset))
		}
		let limit = command.readSize > 0
			? Swift.min(command.readSize, KittyGraphics.largestTransfer)
			: KittyGraphics.largestTransfer
		return try? handle.read(upToCount: limit)
	}

	/// Whether a path a program asked us to delete is one it is reasonable to
	/// delete.
	///
	/// `t=t` means "this is a scratch file, remove it when you are done", and a
	/// program can name any path it likes. Confining it to the temporary
	/// directories is what stops a mistaken — or malicious — sequence from
	/// deleting something that matters.
	private func isSafeToDelete(_ path: String) -> Bool {
		let resolved = URL(fileURLWithPath: path).standardizedFileURL.path
		let roots = [
			NSTemporaryDirectory(),
			"/tmp/",
			"/var/tmp/",
			"/var/folders/",
			"/private/tmp/",
			"/private/var/tmp/",
			"/private/var/folders/",
		]
		return roots.contains { resolved.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
	}

	/// zlib, which Foundation does not have and `Compression` almost does.
	///
	/// `COMPRESSION_ZLIB` is raw DEFLATE, so the two-byte header and the four
	/// byte checksum around it are stepped over here — the same seam
	/// `Run/Gzip.swift` works around from the other side.
	private func inflate(_ data: Data) -> Data? {
		guard data.count > 6 else { return nil }
		let body = data.subdata(in: (data.startIndex + 2)..<(data.endIndex - 4))

		// The decompressed size is not carried anywhere, so the buffer is guessed
		// at and grown. Starting from a healthy multiple means one pass for
		// almost everything.
		var capacity = Swift.max(body.count * 6, 64 << 10)
		while capacity <= KittyGraphics.largestTransfer {
			var output = Data(count: capacity)
			let written = output.withUnsafeMutableBytes { destination in
				body.withUnsafeBytes { source in
					compression_decode_buffer(
						destination.bindMemory(to: UInt8.self).baseAddress!,
						capacity,
						source.bindMemory(to: UInt8.self).baseAddress!,
						body.count,
						nil,
						COMPRESSION_ZLIB
					)
				}
			}
			guard written > 0 else { return nil }
			// A full buffer cannot be told from one that was exactly the right
			// size, so it is treated as too small and tried again.
			if written < capacity { return output.prefix(written) }
			capacity *= 4
		}
		return nil
	}

	/// PNG through ImageIO, flattened to premultiplied RGBA.
	private func decodePNG(_ data: Data, id: UInt32, number: UInt32) -> TerminalImage? {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil),
		      let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)
		else { return nil }

		let width = decoded.width
		let height = decoded.height
		guard width > 0, height > 0, width * height <= 64_000_000 else { return nil }

		var pixels = [UInt8](repeating: 0, count: width * height * 4)
		let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
			guard let context = CGContext(
				data: buffer.baseAddress,
				width: width,
				height: height,
				bitsPerComponent: 8,
				bytesPerRow: width * 4,
				space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
			) else { return false }
			context.draw(decoded, in: CGRect(x: 0, y: 0, width: width, height: height))
			return true
		}
		guard drawn else { return nil }

		return TerminalImage(id: id, number: number, width: width, height: height, pixels: pixels)
	}

	/// Widens RGB to RGBA, and multiplies alpha into the colours.
	private func premultiplied(_ bytes: [UInt8], channels: Int) -> [UInt8] {
		let count = bytes.count / channels
		var output = [UInt8](repeating: 255, count: count * 4)
		if channels == 3 {
			for pixel in 0..<count {
				output[pixel * 4] = bytes[pixel * 3]
				output[pixel * 4 + 1] = bytes[pixel * 3 + 1]
				output[pixel * 4 + 2] = bytes[pixel * 3 + 2]
			}
			return output
		}
		for pixel in 0..<count {
			let alpha = UInt32(bytes[pixel * 4 + 3])
			for channel in 0..<3 {
				output[pixel * 4 + channel] = UInt8((UInt32(bytes[pixel * 4 + channel]) * alpha + 127) / 255)
			}
			output[pixel * 4 + 3] = bytes[pixel * 4 + 3]
		}
		return output
	}

	// MARK: Storing

	private func assignedID(for command: KittyGraphicsCommand) -> UInt32 {
		if command.id != 0 { return command.id }
		if command.number != 0 {
			if let existing = idsByNumber[command.number] { return existing }
			let fresh = nextAssignedID
			nextAssignedID += 1
			idsByNumber[command.number] = fresh
			return fresh
		}
		let fresh = nextAssignedID
		nextAssignedID += 1
		return fresh
	}

	private func store(_ image: TerminalImage) {
		if let existing = images[image.id] { storedBytes -= existing.byteCount }
		images[image.id] = image
		storedBytes += image.byteCount
		touch(image.id)
		evictIfNeeded()
		generation += 1
	}

	private func touch(_ id: UInt32) {
		useOrder.removeAll { $0 == id }
		useOrder.append(id)
	}

	/// Drops the least recently used images until the total fits.
	///
	/// Only ones nothing is showing: an image on screen is being looked at, and
	/// freeing it would blank a picture somebody can see in order to make room
	/// for one they cannot.
	private func evictIfNeeded() {
		guard storedBytes > KittyGraphics.memoryBudget else { return }
		let shown = Set(placements.map(\.imageID))
		for id in useOrder where storedBytes > KittyGraphics.memoryBudget {
			guard !shown.contains(id), let image = images[id] else { continue }
			images[id] = nil
			storedBytes -= image.byteCount
		}
		useOrder.removeAll { images[$0] == nil }
	}

	// MARK: Placing

	private func display(
		_ command: KittyGraphicsCommand,
		context: TerminalGraphicsContext
	) -> TerminalGraphicsResult {
		let id = command.id != 0 ? command.id : idsByNumber[command.number] ?? 0
		guard let image = images[id] else {
			return respond(command, "ENOENT:no image with that id")
		}
		touch(id)
		var result = place(image: image, command: command, context: context)
		if result.response == nil { result.response = respond(command, "OK").response }
		return result
	}

	private func place(
		image: TerminalImage,
		command: KittyGraphicsCommand,
		context: TerminalGraphicsContext
	) -> TerminalGraphicsResult {
		guard cellPixelSize.width > 0, cellPixelSize.height > 0 else {
			return respond(command, "EINVAL:the terminal does not know its cell size yet")
		}

		// The part of the image being shown. Zero means "to the far edge", which
		// is what a program that wants all of it sends.
		let x = Swift.max(0, Swift.min(command.sourceX, image.width))
		let y = Swift.max(0, Swift.min(command.sourceY, image.height))
		let width = command.sourceWidth > 0
			? Swift.min(command.sourceWidth, image.width - x)
			: image.width - x
		let height = command.sourceHeight > 0
			? Swift.min(command.sourceHeight, image.height - y)
			: image.height - y
		guard width > 0, height > 0 else {
			return respond(command, "EINVAL:the source rectangle is empty")
		}

		// How many cells it covers. Given both, the image is scaled to fit them.
		// Given one, the other follows from the aspect ratio — which is what
		// the protocol says and what every client relies on: `icat -w 20` on a
		// square image means twenty columns and a square, not twenty columns of
		// whatever height the pixels happened to be, which draws it squashed.
		// Given neither, it is drawn at its own size and covers however many
		// cells that comes to, the offset within the first cell included.
		let columns: Int
		let rows: Int
		switch (command.columns > 0, command.rows > 0) {
		case (true, true):
			columns = command.columns
			rows = command.rows
		case (true, false):
			columns = command.columns
			let targetWidth: Double = Double(columns) * Double(cellPixelSize.width)
			let ratio: Double = targetWidth / Double(width)
			let scaledHeight: Double = Double(height) * ratio
			rows = Swift.max(1, cellsNeeded(pixels: Int(scaledHeight.rounded()), per: cellPixelSize.height))
		case (false, true):
			rows = command.rows
			let targetHeight: Double = Double(rows) * Double(cellPixelSize.height)
			let ratio: Double = targetHeight / Double(height)
			let scaledWidth: Double = Double(width) * ratio
			columns = Swift.max(1, cellsNeeded(pixels: Int(scaledWidth.rounded()), per: cellPixelSize.width))
		case (false, false):
			columns = cellsNeeded(pixels: width + command.cellOffsetX, per: cellPixelSize.width)
			rows = cellsNeeded(pixels: height + command.cellOffsetY, per: cellPixelSize.height)
		}

		let placement = TerminalImagePlacement(
			imageID: image.id,
			placementID: command.placementID,
			row: context.scrollbackCount + context.cursorRow,
			column: context.cursorColumn,
			columns: Swift.max(1, columns),
			rows: Swift.max(1, rows),
			source: .init(x: x, y: y, width: width, height: height),
			offsetX: command.cellOffsetX,
			offsetY: command.cellOffsetY,
			z: command.z
		)

		// A placement replaces the one it names rather than piling up beside it,
		// which is how a program redraws a plot in place.
		placements.removeAll {
			$0.imageID == placement.imageID && $0.placementID == placement.placementID
		}
		placements.append(placement)
		generation += 1

		var result = TerminalGraphicsResult()
		result.dirtyRows = placement.rowRange
		if !command.leavesCursor {
			// The cursor comes to rest one column past the picture's right edge on
			// its last row, which is where the next thing printed should go.
			result.cursorAdvance = (rows: placement.rows - 1, columns: placement.columns)
		}
		return result
	}

	private func cellsNeeded(pixels: Int, per size: Int) -> Int {
		guard size > 0 else { return 1 }
		return Swift.max(1, (pixels + size - 1) / size)
	}

	// MARK: Deleting

	private func delete(
		_ command: KittyGraphicsCommand,
		context: TerminalGraphicsContext
	) -> TerminalGraphicsResult {
		let selector = command.deletion
		// An upper-case selector means the image data goes too, not just the
		// placement showing it.
		let freesData = selector >= 0x41 && selector <= 0x5A
		let kind = selector | 0x20

		let before = placements
		let cursorRow = context.scrollbackCount + context.cursorRow
		// The x and y keys count from one, and describe the visible screen.
		let targetColumn = command.sourceX - 1
		let targetRow = context.scrollbackCount + command.sourceY - 1

		func covers(_ placement: TerminalImagePlacement, row: Int, column: Int) -> Bool {
			placement.rowRange.contains(row)
				&& column >= placement.column
				&& column < placement.column + placement.columns
		}

		switch kind {
		case 0x61: // a — everything on screen
			placements.removeAll()
		case 0x69: // i — by image id, and by placement if one was named
			placements.removeAll {
				$0.imageID == command.id
					&& (command.placementID == 0 || $0.placementID == command.placementID)
			}
		case 0x6E: // n — by the number the program gave instead of an id
			let id = idsByNumber[command.number] ?? 0
			placements.removeAll {
				$0.imageID == id
					&& (command.placementID == 0 || $0.placementID == command.placementID)
			}
		case 0x63: // c — whatever the cursor is standing on
			placements.removeAll { covers($0, row: cursorRow, column: context.cursorColumn) }
		case 0x70: // p — whatever covers one cell
			placements.removeAll { covers($0, row: targetRow, column: targetColumn) }
		case 0x71: // q — one cell, at one depth
			placements.removeAll {
				covers($0, row: targetRow, column: targetColumn) && $0.z == command.z
			}
		case 0x78: // x — a whole column
			placements.removeAll {
				targetColumn >= $0.column && targetColumn < $0.column + $0.columns
			}
		case 0x79: // y — a whole row
			placements.removeAll { $0.rowRange.contains(targetRow) }
		case 0x7A: // z — everything at one depth
			placements.removeAll { $0.z == command.z }
		case 0x72: // r — a range of image ids
			let low = UInt32(clamping: command.sourceX)
			let high = UInt32(clamping: command.sourceY)
			placements.removeAll { $0.imageID >= low && $0.imageID <= high }
			if freesData {
				for id in Array(images.keys) where id >= low && id <= high { forget(id) }
			}
		default:
			break
		}

		let removed = before.filter { gone in !placements.contains(gone) }
		if freesData, kind != 0x72 {
			// Only images nothing is showing any more; a second placement of the
			// same picture keeps it alive.
			let stillShown = Set(placements.map(\.imageID))
			for id in Set(removed.map(\.imageID)) where !stillShown.contains(id) {
				forget(id)
			}
			if kind == 0x61 {
				for id in Array(images.keys) where !stillShown.contains(id) { forget(id) }
			}
		}

		guard !removed.isEmpty else { return .init() }
		generation += 1

		var low = removed[0].rowRange.lowerBound
		var high = removed[0].rowRange.upperBound
		for placement in removed.dropFirst() {
			low = Swift.min(low, placement.rowRange.lowerBound)
			high = Swift.max(high, placement.rowRange.upperBound)
		}
		let dirty = low...high
		var result = TerminalGraphicsResult()
		result.dirtyRows = dirty
		return result
	}

	private func forget(_ id: UInt32) {
		guard let image = images.removeValue(forKey: id) else { return }
		storedBytes -= image.byteCount
		useOrder.removeAll { $0 == id }
		idsByNumber = idsByNumber.filter { $0.value != id }
	}

	// MARK: Answering

	/// Builds the reply, if the program asked for one and wants to hear it.
	///
	/// A reply only goes out when the command named the image it is about —
	/// otherwise the program has no way to tell which command was being answered,
	/// and an answer it cannot place ends up echoed by the shell.
	private func respond(
		_ command: KittyGraphicsCommand,
		_ message: String,
		force: Bool = false
	) -> TerminalGraphicsResult {
		var result = TerminalGraphicsResult()
		guard command.id != 0 || command.number != 0 else { return result }

		let isSuccess = message == "OK"
		if !force {
			if command.quiet >= 2 { return result }
			if command.quiet >= 1, isSuccess { return result }
		}

		var keys = ""
		if command.id != 0 { keys += "i=\(command.id)" }
		if command.number != 0 {
			if !keys.isEmpty { keys += "," }
			keys += "I=\(command.number)"
		}
		result.response = "\u{1B}_G\(keys);\(message)\u{1B}\\"
		return result
	}
}
