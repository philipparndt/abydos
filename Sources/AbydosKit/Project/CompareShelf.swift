import Foundation

/// The sources a compare page holds, and which two of them are its sides.
///
/// A page is opened over two things and can be handed more — a third draft
/// dropped on it, a commit picked off the history rail — and which two are
/// compared is a choice made on the page, not the pair it was opened with. So
/// the sources are a list, and A and B are two positions in it.
public struct CompareShelf: Equatable, Sendable {
	public private(set) var sources: [CompareSource]
	public private(set) var a: Int
	public private(set) var b: Int

	public init(a: CompareSource, b: CompareSource) {
		sources = [a, b]
		self.a = 0
		self.b = 1
	}

	public var left: CompareSource { sources[a] }
	public var right: CompareSource { sources[b] }
	public var isFolderDiff: Bool { left.isFolder }

	/// Adds a source without changing the comparison. A source already on
	/// the shelf is not added twice; its position is answered instead.
	@discardableResult
	public mutating func add(_ source: CompareSource) -> Int {
		if let index = sources.firstIndex(of: source) { return index }
		sources.append(source)
		return sources.count - 1
	}

	/// Why a source cannot take a chip, or nil when it can.
	public func refusal(making index: Int, sideA: Bool) -> String? {
		guard sources.indices.contains(index) else { return "No such source." }
		let other = sideA ? right : left
		guard sources[index].canBeComparedWith(other) else {
			return sources[index].isFolder
				? "A folder is compared with a folder; the other side is a file."
				: "A file is compared with a file; the other side is a folder."
		}
		return nil
	}

	/// Makes a source side A or side B. Refused, with the reason, when the
	/// two sides would not be the same kind.
	///
	/// **A chip on the card that holds the other side swaps the sides.** The
	/// first version moved one chip and left the other where it was, so
	/// pressing A on the B card made one card A and B at once and the page a
	/// diff of nothing — which read as a control that had done something
	/// strange rather than what was asked. Two cards, two chips, and a press
	/// on the other card's chip is the one gesture that means "the other way
	/// round".
	@discardableResult
	public mutating func choose(_ index: Int, sideA: Bool) -> String? {
		if let refusal = refusal(making: index, sideA: sideA) { return refusal }
		if sideA, index == b {
			b = a
			a = index
		} else if !sideA, index == a {
			a = b
			b = index
		} else if sideA {
			a = index
		} else {
			b = index
		}
		return nil
	}

	/// The other way round.
	public mutating func swap() {
		(a, b) = (b, a)
	}

	/// Puts a source on the shelf and makes it a side in one move.
	@discardableResult
	public mutating func take(_ source: CompareSource, sideA: Bool) -> String? {
		let index = add(source)
		return choose(index, sideA: sideA)
	}

	/// What the tab is called: the two names, `A | B`.
	public var title: String { "\(left.name) | \(right.name)" }
}

/// A compare page, as the session remembers it: its two sides, in a string
/// an `OpenPage` identifier can carry and a later launch can read back.
///
/// The sources are JSON, then base64 with the URL-safe alphabet, so the
/// identifier is one path component with no slash in it — which is what
/// `openPage` builds a tab's URL from.
public enum ComparePageIdentity {
	public static let prefix = "compare:"

	private struct Side: Codable {
		var kind: String
		var path: String
		var repository: String?
		var commit: String?
	}

	public static func identifier(left: CompareSource, right: CompareSource) -> String {
		let sides = [left, right].map { source -> Side in
			switch source {
			case .file(let url): return Side(kind: "file", path: url.path)
			case .folder(let url): return Side(kind: "folder", path: url.path)
			case .blob(let repository, let commit, let path):
				return Side(kind: "blob", path: path, repository: repository.path, commit: commit)
			case .tree(let repository, let commit, let path):
				return Side(kind: "tree", path: path, repository: repository.path, commit: commit)
			}
		}
		let data = (try? JSONEncoder().encode(sides)) ?? Data()
		let encoded = data.base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
		return prefix + encoded
	}

	public static func sides(of identifier: String) -> (left: CompareSource, right: CompareSource)? {
		guard identifier.hasPrefix(prefix) else { return nil }
		var encoded = String(identifier.dropFirst(prefix.count))
			.replacingOccurrences(of: "-", with: "+")
			.replacingOccurrences(of: "_", with: "/")
		while encoded.count % 4 != 0 { encoded += "=" }
		guard let data = Data(base64Encoded: encoded),
		      let sides = try? JSONDecoder().decode([Side].self, from: data), sides.count == 2
		else { return nil }
		let sources = sides.compactMap { side -> CompareSource? in
			switch side.kind {
			case "file": return .file(URL(fileURLWithPath: side.path))
			case "folder": return .folder(URL(fileURLWithPath: side.path, isDirectory: true))
			case "blob":
				guard let repository = side.repository, let commit = side.commit else { return nil }
				return .blob(repository: URL(fileURLWithPath: repository, isDirectory: true), commit: commit, path: side.path)
			case "tree":
				guard let repository = side.repository, let commit = side.commit else { return nil }
				return .tree(repository: URL(fileURLWithPath: repository, isDirectory: true), commit: commit, path: side.path)
			default: return nil
			}
		}
		guard sources.count == 2 else { return nil }
		return (sources[0], sources[1])
	}
}
