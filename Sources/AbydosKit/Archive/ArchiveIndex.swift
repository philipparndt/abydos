import Foundation

/// One thing inside an archive.
public struct ArchiveEntry: Sendable, Equatable, Hashable {
	public enum Member: Sendable, Equatable, Hashable {
		case regular
		case directory
		case symlink(to: String)
		/// A device, a FIFO, or something else that is not bytes to show.
		case other(String)
	}

	/// The path inside the archive, without a leading `./` or a trailing `/`.
	public let path: String
	public let member: Member
	/// Bytes when read, which for a deflated member is more than it takes up.
	public let size: Int
	/// Where the bytes are, in the format's own terms.
	let source: Source

	enum Source: Sendable, Equatable, Hashable {
		/// A zip member: its local header's offset, its method, and how many
		/// bytes it takes up compressed.
		case zip(localHeader: Int, method: UInt16, compressedSize: Int)
		/// A tar member's data, at an offset into the tar's bytes.
		case tar(offset: Int)
		/// The whole inflated gzip.
		case gzip
		/// A directory nobody wrote an entry for, implied by an entry under it.
		case implied
	}

	public var isDirectory: Bool { member == .directory }
	public var name: String { path.split(separator: "/").last.map(String.init) ?? path }
	/// The directory this is in, or nil at the top.
	public var parentPath: String? {
		guard let slash = path.lastIndex(of: "/") else { return nil }
		return String(path[..<slash])
	}
}

/// The contents of an archive, read to list and not to unpack.
///
/// A zip is read from its central directory — one record per member and no
/// data, so a 200 MB jar is a few hundred kilobytes read. A tar has no
/// directory and is walked header by header, skipping each member's data by
/// its size. A gzipped tar has to be inflated to be walked at all, and is,
/// into memory, up to a cap; a Helm chart is kilobytes and a container image
/// is not the case this is for. Members come out through `read`, one at a
/// time, when somebody opens one.
public struct ArchiveIndex: Sendable {
	/// What the file was when it was read, so a replaced archive under an
	/// open row is a different key and is read again.
	public struct Key: Equatable, Sendable, Hashable {
		public let size: Int
		public let modified: Date

		/// Through `FileManager` and not `URL.resourceValues`: `NSURL` caches
		/// the values it has been asked for, so a second key of the same URL
		/// came back equal to the first after the file had been replaced —
		/// the trap `FileNode.readingNow` records.
		public static func of(_ url: URL) throws -> Key {
			let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
			return Key(
				size: (attributes[.size] as? Int) ?? 0,
				modified: (attributes[.modificationDate] as? Date) ?? .distantPast
			)
		}
	}

	public enum Failure: Error, Equatable, Sendable {
		case notAnArchive
		/// A gzipped tar that inflates past the cap.
		case tooLarge(declared: Int, cap: Int)
		case corrupt(String)
		/// A zip member compressed with something the platform cannot inflate.
		case unsupportedMethod(UInt16)
		case notAFile(String)

		public var said: String {
			switch self {
			case .notAnArchive: return "This is not an archive this app can read."
			case .tooLarge(let declared, let cap):
				return "This archive inflates to \(ByteSize.said(Int64(declared))), past the \(ByteSize.said(Int64(cap))) this app shows inline."
			case .corrupt(let what): return "The archive is damaged: \(what)."
			case .unsupportedMethod(let method):
				return "This member is compressed with method \(method), which is not one this app can inflate."
			case .notAFile(let what): return "\(what) is not a file that can be opened."
			}
		}
	}

	/// How much a gzipped tar may inflate to and still be shown inline.
	public static let inflatedCap = 256 * 1024 * 1024

	public let url: URL
	public let kind: ArchiveKind
	public let key: Key
	/// Every entry, sorted by path, directories included — those the archive
	/// wrote and those implied by what is under them.
	public let entries: [ArchiveEntry]
	/// The bytes members are read from: the mapping for a zip or a tar, the
	/// inflated tar for a tgz, the inflated file for a gz.
	let bytes: Data
	private let childrenByParent: [String?: [ArchiveEntry]]

	// MARK: - Reading the listing

	public static func read(_ url: URL, cap: Int = inflatedCap) throws -> ArchiveIndex {
		let key = try Key.of(url)
		let mapped = try Data(contentsOf: url, options: .mappedIfSafe)
		guard var kind = ArchiveKind.detect(mapped.prefix(512), name: url.lastPathComponent) else {
			throw Failure.notAnArchive
		}
		var bytes = mapped
		var listed: [ArchiveEntry]
		switch kind {
		case .zip:
			listed = try zipEntries(in: mapped)
		case .tar:
			listed = try tarEntries(in: mapped)
		case .tarGzip, .gzip:
			do {
				bytes = try Gzip.inflate(mapped, cap: cap)
			} catch Gzip.Failure.tooLarge(let declared, let cap) {
				throw Failure.tooLarge(declared: declared, cap: cap)
			} catch {
				throw Failure.corrupt("the gzip stream does not inflate")
			}
			// A `.gz` whose name did not say may still hold a tar.
			if kind == .gzip, ArchiveKind.looksLikeTar(bytes) { kind = .tarGzip }
			if kind == .tarGzip {
				listed = try tarEntries(in: bytes)
			} else {
				let name = Gzip.storedName(mapped) ?? String(url.lastPathComponent.dropLast(3))
				listed = [ArchiveEntry(path: name, member: .regular, size: bytes.count, source: .gzip)]
			}
		}
		return ArchiveIndex(url: url, kind: kind, key: key, entries: listed, bytes: bytes)
	}

	init(url: URL, kind: ArchiveKind, key: Key, entries: [ArchiveEntry], bytes: Data) {
		self.url = url
		self.kind = kind
		self.key = key
		self.bytes = bytes
		// Directories nobody wrote an entry for — a zip made by `zip -D`, a
		// tar of files — are implied by what is under them.
		var byPath: [String: ArchiveEntry] = [:]
		for entry in entries where !entry.path.isEmpty { byPath[entry.path] = entry }
		for entry in entries {
			var parent = entry.parentPath
			while let directory = parent, byPath[directory] == nil {
				byPath[directory] = ArchiveEntry(path: directory, member: .directory, size: 0, source: .implied)
				parent = byPath[directory]?.parentPath
			}
		}
		let all = byPath.values.sorted { $0.path < $1.path }
		self.entries = all
		var children: [String?: [ArchiveEntry]] = [:]
		for entry in all { children[entry.parentPath, default: []].append(entry) }
		// Folders first, then names, as the tree sorts.
		for (parent, list) in children {
			children[parent] = list.sorted {
				if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
				return $0.name.localizedStandardCompare($1.name) == .orderedAscending
			}
		}
		childrenByParent = children
	}

	/// What is directly inside a directory, or at the top for nil.
	public func children(of directory: String?) -> [ArchiveEntry] {
		childrenByParent[directory] ?? []
	}

	public func entry(at path: String) -> ArchiveEntry? {
		entries.first { $0.path == path }
	}

	// MARK: - Zip

	private static func le16(_ data: Data, _ at: Int) -> Int {
		Int(data[data.startIndex + at]) | Int(data[data.startIndex + at + 1]) << 8
	}

	private static func le32(_ data: Data, _ at: Int) -> Int {
		le16(data, at) | le16(data, at + 2) << 16
	}

	/// The central directory, found from the end-of-central-directory record
	/// that the last 64 KB and 22 bytes must hold.
	static func zipEntries(in data: Data) throws -> [ArchiveEntry] {
		let count = data.count
		guard count >= 22 else { throw Failure.corrupt("shorter than an end record") }
		var eocd = -1
		var position = count - 22
		let floor = max(0, count - 22 - 65535)
		while position >= floor {
			if data[data.startIndex + position] == 0x50, data[data.startIndex + position + 1] == 0x4B,
			   data[data.startIndex + position + 2] == 0x05, data[data.startIndex + position + 3] == 0x06 {
				eocd = position
				break
			}
			position -= 1
		}
		guard eocd >= 0 else { throw Failure.corrupt("no end of central directory") }
		let total = le16(data, eocd + 10)
		let directoryOffset = le32(data, eocd + 16)
		guard directoryOffset != 0xFFFF_FFFF, total != 0xFFFF else {
			throw Failure.corrupt("a ZIP64 directory, which this does not read")
		}

		var entries: [ArchiveEntry] = []
		var at = directoryOffset
		for _ in 0..<total {
			guard at + 46 <= count, le32(data, at) == 0x0201_4B50 else {
				throw Failure.corrupt("a central directory entry out of place")
			}
			let method = UInt16(le16(data, at + 10))
			let compressedSize = le32(data, at + 20)
			let size = le32(data, at + 24)
			let nameLength = le16(data, at + 28)
			let extraLength = le16(data, at + 30)
			let commentLength = le16(data, at + 32)
			let attributes = le32(data, at + 38)
			let localHeader = le32(data, at + 42)
			guard at + 46 + nameLength <= count else { throw Failure.corrupt("a name past the end") }
			let nameBytes = data[(data.startIndex + at + 46)..<(data.startIndex + at + 46 + nameLength)]
			let rawName = String(data: nameBytes, encoding: .utf8) ?? String(decoding: nameBytes, as: UTF8.self)
			let isDirectory = rawName.hasSuffix("/") || attributes & 0x10 != 0
			// The Unix mode lives in the high half of the external attributes.
			let mode = (attributes >> 16) & 0xF000
			let member: ArchiveEntry.Member = isDirectory ? .directory : mode == 0xA000 ? .symlink(to: "") : .regular
			let path = normalised(rawName)
			if !path.isEmpty {
				entries.append(ArchiveEntry(
					path: path, member: member, size: isDirectory ? 0 : size,
					source: .zip(localHeader: localHeader, method: method, compressedSize: compressedSize)
				))
			}
			at += 46 + nameLength + extraLength + commentLength
		}
		return entries
	}

	// MARK: - Tar

	/// Header by header, the data skipped by size. GNU long names and pax
	/// paths are read and applied to the entry they precede.
	static func tarEntries(in data: Data) throws -> [ArchiveEntry] {
		var entries: [ArchiveEntry] = []
		var at = 0
		var longName: String?
		var paxPath: String?
		let count = data.count
		func field(_ offset: Int, _ length: Int) -> String {
			let slice = data[(data.startIndex + at + offset)..<(data.startIndex + at + offset + length)]
			let cut = slice.prefix { $0 != 0 }
			return String(decoding: cut, as: UTF8.self).trimmingCharacters(in: .whitespaces)
		}
		while at + 512 <= count {
			let header = data[(data.startIndex + at)..<(data.startIndex + at + 512)]
			if !header.contains(where: { $0 != 0 }) { break }
			let sizeText = field(124, 12)
			guard let size = Int(sizeText, radix: 8) ?? (sizeText.isEmpty ? 0 : nil) else {
				throw Failure.corrupt("a size that is not octal at 0x\(String(at, radix: 16))")
			}
			let type = data[data.startIndex + at + 156]
			var name = field(0, 100)
			let prefix = field(345, 155)
			if !prefix.isEmpty { name = prefix + "/" + name }
			let padded = (size + 511) / 512 * 512
			let dataStart = at + 512
			switch type {
			case 0x4C: // L: GNU long name for the next entry
				longName = String(decoding: data[(data.startIndex + dataStart)..<(data.startIndex + min(count, dataStart + size))].prefix { $0 != 0 }, as: UTF8.self)
			case 0x78: // x: pax header for the next entry
				let text = String(decoding: data[(data.startIndex + dataStart)..<(data.startIndex + min(count, dataStart + size))], as: UTF8.self)
				for line in text.split(separator: "\n") {
					guard let space = line.firstIndex(of: " "), let equals = line.firstIndex(of: "=") else { continue }
					if line[line.index(after: space)..<equals] == "path" { paxPath = String(line[line.index(after: equals)...]) }
				}
			case 0x67: // g: global pax header, nothing here reads it
				break
			default:
				let path = normalised(paxPath ?? longName ?? name)
				paxPath = nil
				longName = nil
				let member: ArchiveEntry.Member
				switch type {
				case 0x35: member = .directory
				case 0x32: member = .symlink(to: field(157, 100))
				case 0x30, 0x00, 0x37: member = name.hasSuffix("/") ? .directory : .regular
				case 0x31: member = .other("hard link to \(field(157, 100))")
				case 0x33, 0x34: member = .other("device")
				case 0x36: member = .other("FIFO")
				default: member = .other("type \(Character(UnicodeScalar(type)))")
				}
				if !path.isEmpty {
					entries.append(ArchiveEntry(path: path, member: member, size: member == .regular ? size : 0, source: .tar(offset: dataStart)))
				}
			}
			at = dataStart + padded
		}
		return entries
	}

	/// No `./`, no trailing slash, no doubled slashes; and a path that climbs
	/// out is kept from doing so, since it is going to name a cache file.
	static func normalised(_ raw: String) -> String {
		var parts = raw.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
		parts.removeAll { $0 == "." || $0 == ".." }
		return parts.joined(separator: "/")
	}

	// MARK: - Reading a member

	/// The member's bytes: copied for a stored zip member or a tar slice,
	/// inflated for a deflated one, refused for a method the platform cannot
	/// inflate. Sizes are checked, so a member that inflates to something
	/// else is reported rather than opened.
	public func read(_ entry: ArchiveEntry) throws -> Data {
		switch entry.member {
		case .directory: throw Failure.notAFile("A directory")
		case .symlink(let target): throw Failure.notAFile("A link to \(target)")
		case .other(let what): throw Failure.notAFile(what.prefix(1).uppercased() + what.dropFirst())
		case .regular: break
		}
		switch entry.source {
		case .gzip:
			return bytes
		case .implied:
			throw Failure.notAFile("A directory")
		case .tar(let offset):
			guard offset + entry.size <= bytes.count else { throw Failure.corrupt("\(entry.path) runs past the end") }
			return bytes.subdata(in: (bytes.startIndex + offset)..<(bytes.startIndex + offset + entry.size))
		case .zip(let localHeader, let method, let compressedSize):
			guard localHeader + 30 <= bytes.count, Self.le32(bytes, localHeader) == 0x0403_4B50 else {
				throw Failure.corrupt("\(entry.path)'s local header is not where the directory says")
			}
			// The local header's own name and extra lengths, which may differ
			// from the central directory's.
			let nameLength = Self.le16(bytes, localHeader + 26)
			let extraLength = Self.le16(bytes, localHeader + 28)
			let start = localHeader + 30 + nameLength + extraLength
			guard start + compressedSize <= bytes.count else { throw Failure.corrupt("\(entry.path) runs past the end") }
			let compressed = bytes.subdata(in: (bytes.startIndex + start)..<(bytes.startIndex + start + compressedSize))
			switch method {
			case 0:
				guard compressed.count == entry.size else { throw Failure.corrupt("\(entry.path)'s stored size disagrees with itself") }
				return compressed
			case 8:
				let inflated: Data
				do {
					inflated = try Deflate.inflate(compressed, capacity: entry.size)
				} catch {
					throw Failure.corrupt("\(entry.path) does not inflate")
				}
				guard inflated.count == entry.size else { throw Failure.corrupt("\(entry.path) inflates to \(inflated.count) bytes, not \(entry.size)") }
				return inflated
			default:
				throw Failure.unsupportedMethod(method)
			}
		}
	}
}
