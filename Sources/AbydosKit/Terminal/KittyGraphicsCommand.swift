import Foundation


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
	/// `U` — a virtual placement, shown by writing placeholder characters
	/// rather than at the cursor. This is what kitty's own `icat` sends, and
	/// ignoring it drew the picture at the cursor for the moment before the
	/// placeholders were written over it.
	public var isVirtual = false

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
		case 0x55: isVirtual = integer() == 1                  // U
		default: break
		}
	}
}
