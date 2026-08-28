import Foundation

/// The breakpoints a project has, as a list somebody can read.
///
/// A breakpoint is drawn in the gutter of the file it is in and nowhere else,
/// which answers "is there one on this line" and never "where are they all".
/// Six across four files can presently be established only by opening four
/// files — and the app already has a verb about all of them at once, silence
/// every breakpoint but one, reachable only by right-clicking one of them in a
/// gutter.
///
/// Here rather than in the view because this is the only part of the list that
/// can be tested: the ordering, and the name each row carries.
public enum BreakpointRows {
	/// One breakpoint, named for a list.
	///
	/// The code the line holds is deliberately absent. It is read when the row is
	/// drawn — from the editor's own document when the file is open, so an
	/// unsaved edit shows the line as it now reads — and a value that carried it
	/// would be carrying an answer that was true when the list was built.
	public struct Row: Equatable, Sendable {
		/// Canonical path, which is how the debugger and the gutter both key one.
		public var path: String
		/// What to show for the file: relative to the project inside it, in full
		/// outside it.
		public var name: String
		public var line: Int
		public var isEnabled: Bool
		/// Whether an adapter has bound it. Nothing has while nothing is running,
		/// and a marker drawn solid where execution can never stop is a lie.
		public var isVerified: Bool
		public var condition: String?
		public var hitCondition: String?
		public var logMessage: String?

		public init(
			path: String,
			name: String,
			line: Int,
			isEnabled: Bool = true,
			isVerified: Bool = false,
			condition: String? = nil,
			hitCondition: String? = nil,
			logMessage: String? = nil
		) {
			self.path = path
			self.name = name
			self.line = line
			self.isEnabled = isEnabled
			self.isVerified = isVerified
			self.condition = condition
			self.hitCondition = hitCondition
			self.logMessage = logMessage
		}

		/// Whether the row has anything to say beyond where it is.
		public var isConditional: Bool {
			condition?.isEmpty == false || hitCondition?.isEmpty == false || logMessage?.isEmpty == false
		}
	}

	/// Every breakpoint, in file order and then line order.
	///
	/// The same set in the same order every time it is opened: a list that
	/// reordered itself as a dictionary felt like it would be a list nobody could
	/// find anything in twice.
	public static func rows(from breakpoints: [String: [Breakpoint]], in root: URL?) -> [Row] {
		breakpoints
			.sorted { $0.key < $1.key }
			.flatMap { path, list in
				let name = self.name(for: path, in: root)
				return list.sorted { $0.line < $1.line }.map { breakpoint in
					Row(
						path: path,
						name: name,
						line: breakpoint.line,
						isEnabled: breakpoint.isEnabled,
						isVerified: breakpoint.isVerified,
						condition: breakpoint.condition,
						hitCondition: breakpoint.hitCondition,
						logMessage: breakpoint.logMessage
					)
				}
			}
	}

	/// What to call a file in the list.
	///
	/// Relative to the project for a file inside it, and in full for one outside
	/// — a dependency's source, a standard library. The part of the path that
	/// says which is which is the part worth showing, and for a file the project
	/// does not contain that is all of it.
	static func name(for path: String, in root: URL?) -> String {
		guard let root else { return path }
		let outer = FilePath.canonicalEvenIfMissing(root)
		let inner = FilePath.canonicalEvenIfMissing(path)
		guard inner.hasPrefix(outer + "/") else { return path }
		return String(inner.dropFirst(outer.count + 1))
	}
}
