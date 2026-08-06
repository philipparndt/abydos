import Foundation

/// Which scratches a project had open, remembered between launches.
///
/// Without this, coming back to a project either reopens every scratch it has
/// ever had — which after a few weeks is a window full of tabs nobody asked
/// for — or none of them, which loses the half-written note you quit in the
/// middle of. What is wanted is the ones that were actually open.
///
/// Only the list is stored here. The scratches themselves are files, and stay
/// files whether or not they appear in this: forgetting which tabs were open
/// can cost you a tab, never a note.
public struct OpenScratches {
	private let defaults: UserDefaults

	public init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
	}

	private func key(for projectRoot: URL?) -> String {
		let name = projectRoot.map(ScratchFiles.directoryName(for:)) ?? ScratchFiles.globalDirectoryName
		return "openScratches.\(name)"
	}

	/// What was open, or nil if this project has never said.
	///
	/// The difference matters: nil means "no record", which a caller may treat
	/// as "show me what is there", while an empty array means "none were open"
	/// and is to be obeyed.
	public func paths(forProject projectRoot: URL?) -> [String]? {
		defaults.stringArray(forKey: key(for: projectRoot))
	}

	public func record(_ paths: [String], forProject projectRoot: URL?) {
		defaults.set(paths, forKey: key(for: projectRoot))
	}

	/// Which of the recorded scratches still exist, in the order they were in.
	///
	/// One deleted from the pane, or by hand, simply stops coming back.
	public func existing(forProject projectRoot: URL?) -> [URL]? {
		paths(forProject: projectRoot)?
			.map { URL(fileURLWithPath: $0) }
			.filter { FileManager.default.fileExists(atPath: $0.path) }
	}
}
