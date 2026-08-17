import Foundation

/// One way of naming a file, used wherever two parts of the app have to agree
/// that they mean the same one.
public enum FilePath {
	/// A path that compares equal however it was reached, and that other tools
	/// can be handed.
	///
	/// `realpath(3)` rather than `standardizedFileURL` or
	/// `resolvingSymlinksInPath`: both of Foundation's versions have a special
	/// case that rewrites a leading `/private` *back* to `/tmp`, which is the
	/// opposite of resolving. Two paths compared with them still match each
	/// other, so bookkeeping inside the app looks fine — the damage shows only
	/// when the path is handed to something outside it, which knows the file by
	/// its real name. A breakpoint keyed `/tmp/x` never matched the `/private/
	/// tmp/x` the debugger reported, so it was set and never hit.
	public static func canonical(_ url: URL) -> String {
		canonical(url.path)
	}

	public static func canonical(_ path: String) -> String {
		var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
		guard realpath(path, &buffer) != nil else {
			return (path as NSString).standardizingPath
		}
		return String(cString: buffer)
	}

	/// The same, for a path that need not be there yet.
	///
	/// `realpath` answers only about files that exist, and much of what this app
	/// names does not exist when it is named: a program about to be built, a
	/// directory a launch configuration points into, a Dockerfile nobody has
	/// written. `canonical` falls back to `standardizingPath` for those, and
	/// that resolves no symlinks at all — so a path under `/tmp` compared
	/// against a canonical root matched nothing, which is the very fault the
	/// canonical form exists to prevent, arriving by the back door.
	///
	/// So the deepest part that does exist is canonicalised and the rest is put
	/// back on: `/tmp/x/build/out` with no `build` yet becomes
	/// `/private/tmp/x/build/out`, which is the name that directory will have
	/// the moment it is made.
	public static func canonicalEvenIfMissing(_ path: String) -> String {
		var missing: [String] = []
		var cursor = path
		while cursor != "/", !cursor.isEmpty {
			var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
			if realpath(cursor, &buffer) != nil {
				let found = String(cString: buffer)
				guard !missing.isEmpty else { return found }
				let rest = missing.reversed().joined(separator: "/")
				return found == "/" ? "/" + rest : found + "/" + rest
			}
			missing.append((cursor as NSString).lastPathComponent)
			cursor = (cursor as NSString).deletingLastPathComponent
		}
		return path
	}

	public static func canonicalEvenIfMissing(_ url: URL) -> String {
		canonicalEvenIfMissing(url.path)
	}

	/// Every name a directory holds, or nil when it is not one.
	///
	/// For the question "is there a `WORKSPACE` in here", which
	/// `fileExists(atPath:)` does not answer on a Mac. A disk is formatted
	/// case-insensitively by default, so `fileExists` on `…/WORKSPACE` returns
	/// true for an ordinary `workspace/` directory — and a marker checked that
	/// way turns every folder with an Eclipse or Gradle workspace in it into a
	/// Bazel one. It is not hypothetical and it is not only `WORKSPACE`:
	/// `Makefile` matches `makefile` the same way, and did, silently, on every
	/// Mac and on no Linux.
	///
	/// So the names are read once and compared exactly. One `readdir` in place
	/// of a dozen `stat`s, which for the two callers — deciding whether a folder
	/// is a subproject, and which build systems a root has — is the same order
	/// of cost on a directory of any ordinary size, and is the difference
	/// between a right answer and a plausible one.
	///
	/// Hidden names are included: `.git` is a marker.
	public static func entryNames(in directory: URL) -> Set<String>? {
		guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
		else { return nil }
		return Set(names)
	}

	/// Whether a directory holds a file of exactly one of these names.
	public static func directory(_ directory: URL, holdsAnyOf names: [String]) -> Bool {
		guard let held = entryNames(in: directory) else { return false }
		return names.contains { held.contains($0) }
	}
}
