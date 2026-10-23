import Foundation

/// The `vboard.server` setting, read as what a board tab can do with it.
///
/// Stored as typed and judged here, where the tab asks. The settings window
/// has no place to refuse a value with a reason, and a field that silently
/// threw away what somebody typed would be worse than one that keeps it and
/// lets the tab say what is wrong with it the moment it matters.
public enum VboardServerAddress: Equatable {
	/// Nothing named. A `.vboard` opens as it always did, with a sentence.
	case none
	/// Something named that is not a server address, and why.
	case unusable(String)
	/// A server. `isPlainOverNetwork` is plain `http` to anything but this
	/// machine: the board's key would cross the network readable, and the tab
	/// says so beside the server's name.
	case server(URL, isPlainOverNetwork: Bool)

	public init(_ typed: String) {
		let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { self = .none; return }
		guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
		      let host = url.host, !host.isEmpty
		else {
			self = .unusable("“\(trimmed)” is not an address. It needs to look like https://boards.example.org.")
			return
		}
		guard scheme == "https" || scheme == "http" else {
			self = .unusable("“\(trimmed)” is not a web address. A vboard server is reached over https.")
			return
		}
		guard url.query == nil, url.fragment == nil, url.user == nil else {
			self = .unusable("“\(trimmed)” has more in it than a server. Only the address the board pages live under.")
			return
		}
		let loopback = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
		self = .server(url, isPlainOverNetwork: scheme == "http" && !loopback)
	}
}
