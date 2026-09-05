import Foundation

/// Whether a file is one SOPS encrypted, decided by looking, once, at open.
///
/// There is no name shape for a SOPS file — `secrets.yaml`, `values-prod.yaml`,
/// `.env.enc` — so the name alone cannot say, and `DotenvSecrets`'s argument
/// against sniffing is about entropy heuristics on arbitrary files. This is a
/// literal string and a literal key, on files with five extensions: `ENC[`
/// somewhere in the values, and a top-level `sops` block, both. A YAML file
/// with a `sops:` key of its own and no ciphertext is not encrypted; a file
/// with `ENC[` inside a string and no block is somebody's fixture.
///
/// `helmsec` (the reference tool) decides by the block alone and maps the
/// extension to SOPS's format name the same way this does.
public enum SopsFile {
	/// The extensions SOPS formats, and what it calls each — the word
	/// `--input-type` and `--output-type` take.
	public static let formats: [String: String] = [
		"yaml": "yaml", "yml": "yaml", "json": "json", "env": "dotenv", "ini": "ini",
	]

	/// How much of a file is read to decide, in bytes.
	///
	/// Not a head: SOPS writes its block at the *end* of a YAML file, after
	/// every value, so eight kilobytes would miss it on any file with more than
	/// a screen of secrets. A secrets file over a quarter of a megabyte is not
	/// one, and is left alone rather than read whole.
	public static let inspectedBytes = 256 * 1024

	/// SOPS's format word for this name, or nil for a file SOPS does not format.
	public static func format(for url: URL) -> String? {
		formats[fileExtension(of: url.lastPathComponent)]
	}

	/// The extension as SOPS reads it: `.env` is a dotenv file, though to
	/// Foundation it is a name with no extension at all.
	static func fileExtension(of name: String) -> String {
		let ext = (name as NSString).pathExtension.lowercased()
		if ext.isEmpty, name.hasPrefix("."), !name.dropFirst().contains(".") {
			return String(name.dropFirst()).lowercased()
		}
		return ext
	}

	/// Whether this file is SOPS-encrypted.
	///
	/// **Reads the file** — up to `inspectedBytes` — when the extension is one
	/// SOPS formats, and nothing otherwise. Asked once, when a file is opened in
	/// the editor; never by anything walking a tree.
	public static func looksEncrypted(_ url: URL) -> Bool {
		guard format(for: url) != nil, let text = contents(of: url) else { return false }
		return looksEncrypted(name: url.lastPathComponent, contents: text)
	}

	/// The rule, on text, so it can be tested without a file.
	public static func looksEncrypted(name: String, contents: String) -> Bool {
		guard let format = formats[fileExtension(of: name)] else { return false }
		guard contents.contains("ENC[") else { return false }
		if format == "json" {
			return contents.contains("\"sops\":")
		}
		// A top-level key sits at column 0; an indented `sops:` is somebody's
		// own nested key and says nothing.
		return contents.split(separator: "\n", omittingEmptySubsequences: false)
			.contains { $0.hasPrefix("sops:") || $0 == "sops" }
	}

	private static func contents(of url: URL) -> String? {
		guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
		defer { try? handle.close() }
		guard let data = try? handle.read(upToCount: inspectedBytes) else { return nil }
		return String(decoding: data, as: UTF8.self)
	}
}
