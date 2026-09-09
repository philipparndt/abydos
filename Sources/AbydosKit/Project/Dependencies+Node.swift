import Foundation

/// npm, pnpm and yarn: one ecosystem, three lock files, and no two of them the
/// same shape.
///
/// The largest section here by a long way, and every line of it is somebody
/// else's format decision. pnpm and yarn share enough that what they share is
/// written once, above the two of them.
extension ExternalDependencies {
	// MARK: - npm

	/// One row of a lock file, as the file writes it — path and all.
	struct NpmLockEntry: Equatable {
		/// The lock file's own key: the path **relative to the project root**,
		/// `node_modules/lodash`. This is the whole of why npm needs no cache
		/// locator: the sources are already named.
		let path: String
		/// Everything after the last `node_modules/`, which is the name somebody
		/// wrote in an `import`.
		let name: String
		let version: String?
		/// The tarball or repository it was fetched from. Absent in a lock file
		/// written without one — see `npmOrigin`.
		let resolved: String?
	}

	/// The four lock files a `package.json` project can be resolved by, in the
	/// order npm itself prefers them, each with the tool that writes it.
	///
	/// **All four are read as of 0525**; 514 read npm's two and named this item on
	/// the rows of the other two. `package.json` is the marker for all three
	/// tools, so a pnpm or a yarn project reaches this reader whatever it does,
	/// and the row 514 replaced said `run npm install` — an instruction to
	/// install a second, conflicting tree over a project that is already
	/// installed.
	///
	/// The **order** outlives that, and is npm's own preference rather than a
	/// choice made here. A repository that has been installed twice — a
	/// `package-lock.json` somebody committed and a `yarn.lock` somebody else did
	/// — has to be answered by one of them and by the *same* one twice running,
	/// or the section's expansion state means nothing between two reads.
	static let npmLockFiles: [(name: String, tool: String)] = [
		("npm-shrinkwrap.json", "npm"),
		("package-lock.json", "npm"),
		("pnpm-lock.yaml", "pnpm"),
		("yarn.lock", "yarn"),
	]

	/// Which of the four resolved this root, or nil for a project nobody has
	/// installed.
	static func npmLockFile(at root: URL) -> (name: String, tool: String)? {
		let manager = FileManager.default
		return npmLockFiles.first {
			manager.fileExists(atPath: root.appendingPathComponent($0.name).path)
		}
	}

	/// `package-lock.json`, which is JSON and is the resolved tree.
	///
	/// **The easiest kind so far, because the lock file's keys are the paths.**
	/// The `packages` object of a version 2 or 3 lock file is keyed by path
	/// relative to the project root — `node_modules/lodash`,
	/// `node_modules/@types/node`, `node_modules/jest/node_modules/chalk` for a
	/// nested conflicting copy — so `localPath` is the key appended to the root
	/// and there is no cache to locate at all. Every other kind here has one.
	///
	/// `npm ls --json` is the subprocess this does not run: it is `cargo
	/// metadata` wearing a different name, it costs a node launch per project on
	/// open and again on every write of the lock file, and it answers with
	/// whichever npm is first on the PATH — which on a machine with `fnm` or
	/// `nvm` is whichever shell last set it. See the rule on this type.
	///
	/// The sources being *inside* the project is the case no other kind has, and
	/// it needs no code: `node_modules` is already in
	/// `FileNode.defaultExcludedDirectoryNames` and in `Subprojects.skipped`, and
	/// a reveal already asks the section before the ordinary tree.
	static func readNpm(at root: URL) -> DependencySet.Contents {
		let manager = FileManager.default
		guard let lock = npmLockFile(at: root) else {
			if let workspace = npmWorkspaceAbove(root) {
				return .unresolved("resolved in the workspace at \(workspace.lastPathComponent)")
			}
			return .unresolved("no package-lock.json — run npm install")
		}
		// The kind is one and the tools are three, so this is where they part.
		// 514 wrote a sentence naming this item here instead; the sentence is
		// gone and the two readers below are what it was promising.
		switch lock.name {
		case "pnpm-lock.yaml": return readPnpm(at: root)
		case "yarn.lock": return readYarn(at: root)
		default: break
		}

		let file = root.appendingPathComponent(lock.name)
		guard let data = try? Data(contentsOf: file),
			let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		else {
			return .unresolved("\(lock.name) could not be read")
		}

		// `fileExists` per entry, and a real `node_modules` has hundreds to a few
		// thousand of them — the same shape as the per-pin stat in
		// `readSwiftPackages`, paid on open and again whenever the lock file is
		// written. Measured on a real project on this machine: 992 entries, 7.4 ms
		// warm. That is what makes a `stat` per package affordable and a directory
		// walk of `node_modules` — which is where the "npm is slow" reputation
		// comes from — not worth considering.
		let packages = npmEntries(in: top).map { entry -> ExternalDependency in
			let directory = root.appendingPathComponent(entry.path)
			var isDirectory: ObjCBool = false
			let installed = manager.fileExists(atPath: directory.path, isDirectory: &isDirectory)
				&& isDirectory.boolValue
			return ExternalDependency(
				name: entry.name,
				version: entry.version,
				origin: npmOrigin(of: entry.resolved),
				// A package in the lock file and not on disk is resolved and not
				// installed — a fresh checkout with no `npm install` run — and
				// pointing at the directory anyway would draw a package with no
				// files in it.
				localPath: installed ? directory : nil
			)
		}
		return byName(packages)
	}

	/// The external packages a lock file names, whichever layout it is in.
	///
	/// Version 2 and 3 key `packages` by path; version 1 has no `packages` at all
	/// and instead a `dependencies` tree keyed by name, nested where two
	/// packages need different versions of a third. Version 2 carries both, for
	/// tools that only understand version 1, and `packages` wins — it is the one
	/// with the paths in it. Reading only the newer layout would empty the
	/// section on any project last installed by npm 6, which is the same failure
	/// `readSwiftPackages` refuses for `Package.resolved`'s two layouts.
	static func npmEntries(in top: [String: Any]) -> [NpmLockEntry] {
		if let packages = top["packages"] as? [String: Any] {
			return packages.compactMap { path, value in
				guard let entry = value as? [String: Any] else { return nil }
				return npmEntry(path: path, entry: entry)
			}
		}
		var entries: [NpmLockEntry] = []
		func walk(_ tree: [String: Any], under prefix: String) {
			for (name, value) in tree {
				guard let entry = value as? [String: Any] else { continue }
				let path = prefix + "node_modules/" + name
				if let found = npmEntry(path: path, entry: entry) { entries.append(found) }
				if let nested = entry["dependencies"] as? [String: Any] {
					walk(nested, under: path + "/")
				}
			}
		}
		walk(top["dependencies"] as? [String: Any] ?? [:], under: "")
		return entries
	}

	/// One entry, or nil for one that is not an external dependency.
	///
	/// Two kinds are dropped, both for 508's rule that what the section lists is
	/// what came from outside:
	///
	/// - a key with no `node_modules` in it — `""` is the project itself, and
	///   `packages/app` is a workspace member, which is a directory the tree
	///   already has a row for;
	/// - `"link": true`, which is that same member *symlinked* into
	///   `node_modules` so an import can find it. Its `resolved` is a path
	///   inside the project, so listing it would show the project's own source
	///   twice under a heading saying it came from elsewhere.
	static func npmEntry(path: String, entry: [String: Any]) -> NpmLockEntry? {
		guard entry["link"] as? Bool != true else { return nil }
		guard let name = npmPackageName(inPath: path) else { return nil }
		return NpmLockEntry(
			path: path, name: name,
			version: entry["version"] as? String,
			resolved: entry["resolved"] as? String
		)
	}

	/// `node_modules/jest/node_modules/@types/node` → `@types/node`.
	///
	/// Everything after the **last** `node_modules/`, which is one rule that gets
	/// both hard cases right: a scoped name keeps its `@scope/`, and a nested
	/// copy — the second version of a package, installed under whichever package
	/// needs it — is named after itself rather than after the package it is
	/// buried in. Nil when there is no `node_modules` in the key at all, which is
	/// how the project and its workspace members are left out.
	static func npmPackageName(inPath path: String) -> String? {
		guard let marker = path.range(of: "node_modules/", options: .backwards) else { return nil }
		let name = String(path[marker.upperBound...])
		return name.isEmpty ? nil : name
	}

	/// Where a package came from, from the `resolved` URL the lock file writes.
	///
	///     https://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz  → npmjs.com
	///     https://npm.pkg.github.com/@acme/thing/-/thing-1.0.tgz  → npm.pkg.github.com
	///     git+https://github.com/tomasf/thing.git#5aa45a1        → the URL, whole
	///
	/// The host and not the tarball. `shortOrigin` cuts a URL back to everything
	/// but its last component, which for a registry tarball is
	/// `registry.npmjs.org/lodash/-` — three quarters of it noise, on eight
	/// hundred rows. So the registry is named instead, and named `npmjs.com` on
	/// 513's `crates.io` precedent: the default registry is what almost every row
	/// says, and saying it as a host somebody could paste into a browser is the
	/// version of it that carries information. `registry.yarnpkg.com` is a mirror
	/// of that same registry and reads the same — 513's "two spellings of one
	/// registry" again, and here it is in a lock file npm itself wrote.
	///
	/// A git dependency keeps the whole URL, revision included, because that is
	/// what says *which* one of it; `shortOrigin` cuts it to the owner for the
	/// row and the tooltip has all of it. The `git+` prefix is dropped so that
	/// `shortOrigin` can recognise the scheme underneath — and it is what tells a
	/// git dependency from a tarball, since both are `https://` once it is gone
	/// and the host is the wrong answer for one of them: `github.com` on its own
	/// says a package came from GitHub and not which repository.
	///
	/// **A lock file with no `resolved` anywhere is real**, and not only the
	/// bundled-dependency case the format documents: one of the projects on this
	/// machine has 990 entries of 992 without one, from an install through a
	/// registry proxy. Those rows are version-only, which `DependencyNode`
	/// already draws, rather than rows claiming an origin nothing wrote down.
	static func npmOrigin(of resolved: String?) -> String {
		guard var location = resolved, !location.isEmpty else { return "" }
		let isRepository = location.hasPrefix("git+") || location.hasPrefix("git://")
			|| location.contains("#")
		if location.hasPrefix("git+") { location = String(location.dropFirst(4)) }
		guard !isRepository else { return location }
		guard location.hasPrefix("https://") || location.hasPrefix("http://"),
			let host = URL(string: location)?.host
		else { return location }
		return isNpmRegistry(host) ? "npmjs.com" : host
	}

	/// The registry every npm project uses, by either of the two hosts that
	/// serve it: npm's own, and yarn's mirror of it.
	static func isNpmRegistry(_ host: String) -> Bool {
		host == "registry.npmjs.org" || host == "registry.yarnpkg.com"
	}

	/// The workspace that resolves for this package, if it is a member of one.
	///
	/// 513's finding in npm's spelling, and the commoner half of it: an npm
	/// workspace has **one** lock file, at its root, and hoists every dependency
	/// into the root's `node_modules`. Each member has a `package.json`, so each
	/// member is a subproject with a row of its own — and `run npm install` in a
	/// member is worse advice than cargo's was, because npm will do it: it
	/// installs a second `node_modules` inside the member and the workspace's
	/// hoisting stops meaning anything.
	///
	/// The ancestor has to *declare* the workspace — `workspaces` in its
	/// `package.json`, or a `pnpm-workspace.yaml` beside it — and not merely
	/// have a lock file. A `docs` folder with a `package.json` of its own inside
	/// a repository that is not a workspace is a project that genuinely has not
	/// been installed, and `run npm install` is the right thing to tell it.
	///
	/// The workspace's own list is deliberately not borrowed down into the
	/// member, for 513's reason: it is the whole workspace's resolved set, and
	/// copying it under five members would print it five times and claim each
	/// member depends on all of it.
	static func npmWorkspaceAbove(_ root: URL) -> URL? {
		let manager = FileManager.default
		var directory = root.deletingLastPathComponent()
		for _ in 0..<6 {
			guard directory.path != "/", directory.path != root.path else { return nil }
			let manifest = directory.appendingPathComponent("package.json")
			let hasLock = npmLockFiles.contains {
				manager.fileExists(atPath: directory.appendingPathComponent($0.name).path)
			}
			if hasLock, manager.fileExists(atPath: manifest.path), declaresNpmWorkspaces(manifest) {
				return directory
			}
			directory = directory.deletingLastPathComponent()
		}
		return nil
	}

	/// The version an installed package says it is, from its own manifest.
	///
	/// One file read, and only asked where it settles something — see `readYarn`,
	/// which is the only caller and asks it for a handful of names out of a
	/// couple of thousand.
	static func npmInstalledVersion(of name: String, under modules: URL) -> String? {
		let manifest = modules.appendingPathComponent(name).appendingPathComponent("package.json")
		guard let data = try? Data(contentsOf: manifest),
		      let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		else { return nil }
		return top["version"] as? String
	}

	// MARK: - pnpm and yarn: the shapes both lock files are made of

	/// One package a `pnpm-lock.yaml` or a `yarn.lock` names.
	///
	/// The two files look nothing like each other and come out as the same three
	/// facts, which are the whole of what a row draws.
	struct NodeLockEntry: Equatable {
		let name: String
		let version: String?
		/// Empty where the lock file writes no locator at all — which for pnpm is
		/// **most rows**, and is left empty rather than filled in with a guess.
		/// See `readPnpm`.
		let origin: String
	}

	/// The `@` that separates a package's name from what follows it, which is the
	/// **first** one past a leading `@scope/` and never the last.
	///
	/// Found the hard way in pnpm's store, where a directory is
	/// `@babel+helper-module-transforms@7.25.2_@babel+core@7.25.2`: the last `@`
	/// in that is inside the *peer* it was built against, and splitting there
	/// names a package `@babel+helper-module-transforms@7.25.2_@babel+core` at
	/// version `7.25.2`. The same shape turns up in yarn berry's descriptors and
	/// in a `patch:` locator, so the rule is written once.
	static func nodeNameAndRest(_ text: some StringProtocol) -> (name: String, rest: String)? {
		let whole = String(text)
		guard !whole.isEmpty else { return nil }
		let start = whole.hasPrefix("@") ? whole.index(after: whole.startIndex) : whole.startIndex
		guard let at = whole[start...].firstIndex(of: "@") else { return nil }
		let name = String(whole[..<at])
		guard !name.isEmpty else { return nil }
		return (name, String(whole[whole.index(after: at)...]))
	}

	/// A scalar as these two generators write one: bare, single-quoted or
	/// double-quoted.
	///
	/// Nothing else, and that is the point — no block scalars, no anchors, no
	/// tags. See `readPnpm` for why a reader that understands only what these
	/// files contain is the right size of tool for them.
	static func unquotedNodeScalar(_ text: some StringProtocol) -> String {
		var value = String(text).trimmingCharacters(in: .whitespaces)
		for quote in ["'", "\""]
		where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
			value = String(value.dropFirst().dropLast())
			// A single-quoted scalar escapes its own quote by doubling it, and
			// pnpm writes `'@scope/it''s'` rather than switching to double quotes.
			if quote == "'" { value = value.replacingOccurrences(of: "''", with: "'") }
			break
		}
		return value
	}

	/// One key out of a one-line flow mapping — `{integrity: sha512-…, tarball:
	/// https://…}` — which is the only nesting either of these files puts on a
	/// line of its own.
	///
	/// The character in front of a key in a flow mapping is `{`, `,` or a space,
	/// and requiring it is what stops `repo:` being found inside
	/// `https://my-repo:8080/…`.
	static func nodeFlowValue(_ key: String, in text: some StringProtocol) -> String? {
		let whole = String(text)
		var search = whole.startIndex..<whole.endIndex
		while let range = whole.range(of: key + ":", range: search) {
			search = range.upperBound..<whole.endIndex
			if range.lowerBound > whole.startIndex {
				let before = whole[whole.index(before: range.lowerBound)]
				guard before == "{" || before == "," || before == " " else { continue }
			}
			let rest = whole[range.upperBound...]
			let end = rest.firstIndex { $0 == "," || $0 == "}" } ?? rest.endIndex
			let value = unquotedNodeScalar(rest[..<end])
			return value.isEmpty ? nil : value
		}
		return nil
	}

	// MARK: - pnpm

	/// `pnpm-lock.yaml`, which is the resolved set and is YAML.
	///
	/// **There is no YAML reader in this repository, and this item does not add
	/// one.** That is 513's "there is no TOML reader" a second time, and 0525 was
	/// filed insisting the argument be made again rather than inherited, because
	/// 513's reason — `Cargo.lock` is generated and *flat* — plainly does not
	/// carry over: this file has `importers:`, `packages:` and `snapshots:` at the
	/// top level and two more levels under each.
	///
	/// It is made again, and it comes out the same way, on a different reason.
	/// What this section wants out of the file is **the keys of one block**. The
	/// `packages:` block is a mapping whose keys are `name@version` and whose
	/// values this reader looks at exactly one line of. It never descends into
	/// `importers:`, which is the ranges somebody wrote rather than what was
	/// resolved; it must never descend into `snapshots:`, which repeats every one
	/// of those keys with its peers attached and would draw the whole project
	/// twice. So the nesting a YAML library would earn its keep on is nesting
	/// this reader is required to *skip*.
	///
	/// Against that: a library is Yams, which vendors libyaml, for a file that is
	/// machine-written by `js-yaml` with fixed options and is never hand-edited —
	/// so the constructs a hand-written reader is bad at (anchors, tags, block
	/// scalars, flow sequences spanning lines) are constructs that do not occur in
	/// it. It would also build the whole document — twenty thousand lines, most of
	/// it `snapshots:` — to be asked for two thousand keys, on a path that runs
	/// when a project opens and again on every write of the lock file. `project.md`
	/// asks for a reason that survives being written down, and "one block's keys,
	/// out of a generated file" is not one.
	///
	/// What is bought instead is the guard below: a file this reader does not
	/// understand says so, rather than coming out as a project that depends on
	/// nothing. That is the failure a hand-written reader can actually cause, and
	/// it is the failure the section exists to prevent, so it is answered
	/// explicitly — `readConanPackages` makes the same move for a Conan 1 lock.
	static func readPnpm(at root: URL) -> DependencySet.Contents {
		let file = root.appendingPathComponent("pnpm-lock.yaml")
		guard let text = try? String(contentsOf: file, encoding: .utf8) else {
			return .unresolved("pnpm-lock.yaml could not be read")
		}
		// Guarded on a key and not on the parse. Every pnpm lock from 5.x to 9.x
		// opens with `lockfileVersion`, so a file without one is not a shape this
		// reader knows, and `.packages([])` over it would read as "no
		// dependencies" — the one claim this section must never make by accident.
		guard text.hasPrefix("lockfileVersion:") || text.contains("\nlockfileVersion:") else {
			return .unresolved("pnpm-lock.yaml could not be read")
		}

		let store = pnpmStoreDirectories(at: root)
		let manager = FileManager.default
		let packages = parsePnpmLock(text).map { entry -> ExternalDependency in
			let directory = entry.version
				.flatMap { store[pnpmStoreKey(name: entry.name, version: $0)] }?
				.appendingPathComponent("node_modules")
				.appendingPathComponent(entry.name)
			let installed = directory.map { manager.fileExists(atPath: $0.path) } ?? false
			return ExternalDependency(
				name: entry.name, version: entry.version, origin: entry.origin,
				localPath: installed ? directory : nil
			)
		}
		return byName(packages)
	}

	/// The keys of the `packages:` block, and the one line under each worth
	/// reading.
	///
	/// **`snapshots:` is the trap.** A 9.x lock lists every package twice: once
	/// under `packages:`, which is what was resolved, and again under
	/// `snapshots:`, which is the same key with the peers it was built against in
	/// parentheses and the graph beneath it. A reader that took every indented key
	/// ending in a colon would draw a project of two thousand packages as four
	/// thousand rows, half of them named after a peer set. So the top-level block
	/// is tracked and only one of them is read.
	static func parsePnpmLock(_ text: String) -> [NodeLockEntry] {
		var entries: [NodeLockEntry] = []
		var block = ""
		var keyIndent: Int?
		var current: NodeLockEntry?

		func finish() {
			if let current { entries.append(current) }
			current = nil
		}

		for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
			let line = String(rawLine)
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
			let indent = line.prefix { $0 == " " }.count

			if indent == 0 {
				finish()
				keyIndent = nil
				block = trimmed.hasSuffix(":") ? String(trimmed.dropLast()) : ""
				continue
			}
			guard block == "packages" else { continue }
			if keyIndent == nil { keyIndent = indent }
			guard let depth = keyIndent else { continue }

			if indent == depth {
				finish()
				current = pnpmPackage(fromKey: trimmed)
				continue
			}
			guard let package = current, indent > depth, trimmed.hasPrefix("resolution:") else {
				continue
			}
			let flow = trimmed.dropFirst("resolution:".count)
			// `{directory: ../shared, type: directory}` is a `file:` or `link:`
			// dependency: a directory inside the project, which the tree already
			// has rows for. 513's Cargo `path` dependency in pnpm's spelling.
			if nodeFlowValue("type", in: flow) == "directory" {
				current = nil
				continue
			}
			guard let locator = pnpmResolutionLocator(in: flow) else { continue }
			current = NodeLockEntry(
				name: package.name, version: package.version, origin: npmOrigin(of: locator)
			)
		}
		finish()
		return entries
	}

	/// Where a `resolution:` says a package came from, when it says at all.
	///
	/// A registry package's resolution is `{integrity: sha512-…}` and nothing
	/// else — see `readPnpm` on why that is left as no origin rather than filled
	/// in. A tarball and a git checkout do write a locator, and it is the answer.
	static func pnpmResolutionLocator(in flow: some StringProtocol) -> String? {
		if let repository = nodeFlowValue("repo", in: flow) {
			guard let commit = nodeFlowValue("commit", in: flow) else { return repository }
			return repository + "#" + commit
		}
		return nodeFlowValue("tarball", in: flow)
	}

	/// One key of the `packages:` block, across every layout still on disk.
	///
	/// Three of them, and they are not tellable apart by the lock file's version
	/// number alone because a repository holds whichever one it was last
	/// installed with:
	///
	///     lodash@4.17.21                     9.x, and 6.x with a leading slash
	///     /@abandonware/bleno/0.6.1          5.x: a path, the version last
	///     registry.example.com/lodash/4.17.21   5.x, from another registry
	///
	/// **The layouts are told apart by counting slashes**, not by the leading one:
	/// the `name@version` form has exactly one slash when the name is scoped and
	/// none when it is not, and anything with more of them is a path. A leading
	/// slash alone would get `registry.example.com/lodash/4.17.21` wrong, and
	/// splitting on the first `@` would get it wrong the other way, by finding the
	/// `@` of `@babel` in the middle of the host.
	///
	/// The registry in front of a 5.x path is kept as the origin, which is the
	/// only layout of the three that records one at all.
	static func pnpmPackage(fromKey rawKey: String) -> NodeLockEntry? {
		guard rawKey.hasSuffix(":") else { return nil }
		var key = unquotedNodeScalar(rawKey.dropLast())
		// `…@7.25.2(@babel/core@7.25.2)` — the peers it was built against, which
		// are not part of what the package is called or which version of it this
		// is. `snapshots:` is where those matter and `snapshots:` is not read.
		if let peers = key.firstIndex(of: "(") { key = String(key[..<peers]) }
		if key.hasPrefix("/") { key = String(key.dropFirst()) }
		guard !key.isEmpty else { return nil }

		// A directory inside the project, dropped for the reason above. Caught
		// here as well as at `resolution:` because 5.x wrote no resolution for one.
		guard !key.contains("@file:"), !key.contains("@link:") else { return nil }

		if key.contains("://") {
			// `foo@https://codeload.github.com/…`: the version is a URL, which is
			// where it came from and is not a version anybody could type.
			guard let split = nodeNameAndRest(key) else { return nil }
			return NodeLockEntry(name: split.name, version: nil, origin: npmOrigin(of: split.rest))
		}

		let slashes = key.filter { $0 == "/" }.count
		guard slashes > (key.hasPrefix("@") ? 1 : 0) else {
			guard let split = nodeNameAndRest(key) else { return nil }
			return NodeLockEntry(name: split.name, version: split.rest, origin: "")
		}

		var parts = key.split(separator: "/").map(String.init)
		guard parts.count >= 2 else { return nil }
		let version = parts.removeLast()
		let scoped = parts.count >= 2 && parts[parts.count - 2].hasPrefix("@")
		let name = parts.suffix(scoped ? 2 : 1).joined(separator: "/")
		guard !name.isEmpty else { return nil }
		return NodeLockEntry(
			name: name, version: version,
			origin: parts.dropLast(scoped ? 2 : 1).joined(separator: "/")
		)
	}

	/// `@babel/core`, `7.25.2` → `@babel+core@7.25.2`, which is what the store
	/// calls the directory.
	static func pnpmStoreKey(name: String, version: String) -> String {
		name.replacingOccurrences(of: "/", with: "+") + "@" + version
	}

	/// The store, **listed rather than computed** — cargo's registry hash and
	/// Bazel's separator, a third time.
	///
	/// pnpm's `node_modules` is a tree of symlinks into
	/// `node_modules/.pnpm/<name>@<version>/node_modules/<name>`, and *that* is
	/// what a package row is rooted at: it is a real directory, so nothing has to
	/// follow a symlink and the tree lists it like any other folder. The
	/// top-level `node_modules/<name>` symlink is deliberately not used instead —
	/// it exists only for a project's direct dependencies, and points at one
	/// version of a package a lock file may hold three of.
	///
	/// The directory name carries the peers a package was built against, after an
	/// underscore: `@babel+helper-module-transforms@7.25.2_@babel+core@7.25.2`.
	/// Those are cut off here rather than reproduced, because pnpm's own escaping
	/// of them has changed across releases and a package name may itself contain
	/// an underscore — so the cut is made at the first underscore *after* the
	/// version, which semver cannot contain one of.
	///
	/// One listing per project and then a dictionary, not a scan per package: a
	/// real store has hundreds to a few thousand entries and the linear form
	/// would be that many comparisons per package, on a path that runs when a
	/// project opens. Measured on a real pnpm 9 project on this machine: 234
	/// packages against a store of 200 directories, 29 ms for the whole section.
	static func pnpmStoreDirectories(at root: URL) -> [String: URL] {
		let store = root.appendingPathComponent("node_modules/.pnpm")
		let entries = ((try? FileManager.default.contentsOfDirectory(
			at: store, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }

		var found: [String: URL] = [:]
		for entry in entries {
			let key = pnpmStoreName(withoutPeers: entry.lastPathComponent)
			// One package at one version can be in the store several times, once
			// per peer set, and the sources under each are the same. Sorted and
			// first-wins so that two reads of one project show the same path.
			if found[key] == nil { found[key] = entry }
		}
		return found
	}

	/// `@babel+core@7.25.2_typescript@5.3.3` → `@babel+core@7.25.2`.
	static func pnpmStoreName(withoutPeers directory: String) -> String {
		guard let at = nodeNameAndRest(directory) else { return directory }
		guard let underscore = at.rest.firstIndex(of: "_") else { return directory }
		let version = at.rest[..<underscore]
		return at.name + "@" + version
	}

	// MARK: - yarn

	/// `yarn.lock`, in **both** of the syntaxes yarn has written.
	///
	/// The item that filed this called it three formats. It is two, and the third
	/// is a version number: yarn 1 writes a bespoke file — a header naming one or
	/// more ranges, then fields indented under it — and every yarn since 2 writes
	/// YAML. The YAML one has been through four `__metadata.version` numbers and
	/// the two fields this reads, the entry's header and its `version`, are the
	/// same in all of them, so there is nothing to tell apart there.
	///
	/// And the two syntaxes are the same *shape*: a top-level entry, then indented
	/// fields, differing in `version "4.17.21"` against `version: 4.17.21`. One
	/// reader covers both, which is why this is shorter than pnpm's and not
	/// longer.
	///
	/// **What is not covered**: reading *inside* a Plug'n'Play zip. A berry
	/// project with the pnp linker has no `node_modules` at all — its packages are
	/// zip files under `.yarn/cache` — so those rows name the archive and cannot
	/// be opened, exactly as a Maven dependency names its jar. Browsing a zip is a
	/// different capability from reading a lock file and it is not this item's.
	static func readYarn(at root: URL) -> DependencySet.Contents {
		let file = root.appendingPathComponent("yarn.lock")
		guard let text = try? String(contentsOf: file, encoding: .utf8) else {
			return .unresolved("yarn.lock could not be read")
		}
		// The same guard `readPnpm` and `readConanPackages` make, and yarn needs it
		// as much as either: a lock file for a project that depends on nothing is
		// a header and no entries, and so is a file this reader does not
		// understand. Every yarn.lock ever written stamps one of these two.
		guard text.contains("yarn lockfile v1") || text.contains("__metadata") else {
			return .unresolved("yarn.lock could not be read")
		}

		let entries = parseYarnLock(text)
		let modules = root.appendingPathComponent("node_modules")
		let archives = yarnCacheArchives(at: root)
		let manager = FileManager.default

		// **A yarn.lock does not say where anything was installed.** npm's keys are
		// paths and this file has none, so the sources have to be found rather than
		// read off. A name the lock resolves once is the copy hoisted to
		// `node_modules/<name>`, and needs nothing checked. A name it resolves
		// several times has one copy at the root and the rest nested under whoever
		// needed them, and only the root copy's own manifest says which version it
		// is — so that manifest is read, for those names alone.
		//
		// Measured on a real yarn 1 project on this machine: 883 packages, of
		// which 96 names are resolved more than once, so 96 manifests are read
		// and they cost 6 ms of the 40 ms the whole section takes. Reading every
		// package's manifest instead would be 883 of them, and dropping the
		// sources of every duplicated name would lose a tenth of the rows.
		var counts: [String: Int] = [:]
		for entry in entries { counts[entry.name, default: 0] += 1 }
		var hoisted: [String: String] = [:]
		for (name, count) in counts where count > 1 {
			hoisted[name] = npmInstalledVersion(of: name, under: modules)
		}

		let packages = entries.map { entry -> ExternalDependency in
			var localPath: URL?
			if counts[entry.name] == 1 || (entry.version != nil && hoisted[entry.name] == entry.version) {
				let directory = modules.appendingPathComponent(entry.name)
				var isDirectory: ObjCBool = false
				if manager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
				   isDirectory.boolValue {
					localPath = directory
				}
			}
			// Plug'n'Play: no directory anywhere, and a zip in the cache that is
			// this package and can be named without being browsed. 0515's `artefact`
			// exactly — a jar is not a directory either — and the row's tooltip
			// already says the archive rather than `not fetched`.
			let archive = localPath == nil
				? entry.version.flatMap { archives[yarnCacheKey(name: entry.name, version: $0)] }
				: nil
			return ExternalDependency(
				name: entry.name, version: entry.version, origin: entry.origin,
				localPath: localPath, artefact: archive
			)
		}
		return byName(packages)
	}

	/// Every entry of a `yarn.lock`, whichever syntax it is in.
	///
	/// An entry starts at column zero and its fields are indented, in both. What
	/// is dropped is what is not a package from outside — 508's rule, in yarn's
	/// four spellings of it: `workspace:` is a member of this repository,
	/// `link:` and `portal:` are directories in it, and `file:` is one of those
	/// two under yarn 1.
	static func parseYarnLock(_ text: String) -> [NodeLockEntry] {
		var entries: [NodeLockEntry] = []
		var seen: Set<String> = []
		var name: String?
		var locator: String?
		var version: String?
		var resolved: String?

		func finish() {
			defer { name = nil; locator = nil; version = nil; resolved = nil }
			guard let name else { return }
			// `patch:` writes the same package and version a second time, wrapping
			// the entry it patches — so the pair is collapsed here rather than
			// dropped by protocol, which would lose a package that is *only*
			// reachable through its patch. Two versions of one package stay two
			// rows, the way npm's nested copies do.
			guard seen.insert(name + "@" + (version ?? "")).inserted else { return }
			let origin = resolved.map { yarnResolvedOrigin(of: $0) }
				?? locator.map { yarnOrigin(ofLocator: $0) }
				?? ""
			entries.append(NodeLockEntry(name: name, version: version, origin: origin))
		}

		for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
			let line = String(rawLine)
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

			if line.first != " " && line.first != "\t" {
				finish()
				guard trimmed.hasSuffix(":"), trimmed != "__metadata:" else { continue }
				guard let split = nodeNameAndRest(yarnFirstDescriptor(in: trimmed.dropLast())),
				      !yarnIsInProject(locator: split.rest)
				else { continue }
				name = split.name
				locator = split.rest
				continue
			}
			guard name != nil else { continue }

			if trimmed.hasPrefix("version ") || trimmed.hasPrefix("version:") {
				version = unquotedNodeScalar(
					trimmed.dropFirst("version".count).drop { $0 == ":" || $0 == " " }
				)
			} else if trimmed.hasPrefix("resolved ") {
				// yarn 1, and the one field that names a URL outright.
				resolved = unquotedNodeScalar(trimmed.dropFirst("resolved".count))
			} else if trimmed.hasPrefix("resolution:") {
				// berry, and more trustworthy than the header: the header carries
				// the *range* somebody asked for and this carries what it resolved
				// to. A `workspace:` here is the project's own root entry.
				let value = unquotedNodeScalar(trimmed.dropFirst("resolution:".count))
				guard let split = nodeNameAndRest(value) else { continue }
				if yarnIsInProject(locator: split.rest) { name = nil; continue }
				locator = split.rest
			}
		}
		finish()
		return entries
	}

	/// The first of the ranges an entry's header names, unquoted.
	///
	/// **The two syntaxes put the quotes in different places, and that is the one
	/// place they had to be told apart.** yarn 1 writes a list of quoted
	/// descriptors — `"@babel/code-frame@^7.0.0", "@babel/code-frame@^7.16.7":` —
	/// and berry writes *one* quoted string with the commas inside it:
	/// `"@babel/code-frame@npm:^7.0.0, @babel/code-frame@npm:^7.22.13":`. So the
	/// comma is found first and the quotes are trimmed off whatever is left of
	/// it, either way. Unquoting before splitting reads berry's key as a package
	/// called `"`, which is what this comment is here to stop somebody
	/// re-introducing.
	///
	/// The first is as good as any: the ranges differ and what they resolved to
	/// is one package.
	static func yarnFirstDescriptor(in head: some StringProtocol) -> String {
		let whole = String(head)
		let first = whole.firstIndex(of: ",").map { String(whole[..<$0]) } ?? whole
		return first.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
	}

	/// Whether a yarn locator names something inside this repository rather than
	/// a package from outside it.
	static func yarnIsInProject(locator: String) -> Bool {
		guard let colon = locator.firstIndex(of: ":") else { return false }
		return ["workspace", "link", "portal", "file"].contains(String(locator[..<colon]))
	}

	/// yarn 1's `resolved`, which is **not** an npm `resolved` however much it
	/// looks like one.
	///
	/// Found by a test, and it would have spoiled every row of every yarn 1
	/// project: yarn writes the tarball's sha1 as a fragment on the end of the
	/// URL — `…/lodash-4.17.21.tgz#679591c5` — and npm never does. `npmOrigin`
	/// reads a `#` as *this came from a repository and the fragment says which
	/// revision*, which is right for npm and turns a registry package's origin
	/// into the whole tarball URL here. So the fragment comes off first, and the
	/// two spellings that really are repositories keep theirs.
	static func yarnResolvedOrigin(of resolved: String) -> String {
		guard !resolved.hasPrefix("git+"), !resolved.hasPrefix("git://"),
		      !resolved.contains(".git#")
		else { return npmOrigin(of: resolved) }
		return npmOrigin(of: resolved.firstIndex(of: "#").map { String(resolved[..<$0]) } ?? resolved)
	}

	/// Where a berry entry came from, from the protocol its locator names.
	///
	/// `npm:` is the npm registry, which is the one protocol that is a *statement*
	/// rather than a path — so it reads `npmjs.com`, the way a crates.io index URL
	/// does. Everything else is a locator `npmOrigin` already knows how to shorten:
	/// a `https://…#commit` keeps the whole of itself, a `github:owner/repo` keeps
	/// its own spelling.
	///
	/// **pnpm gets no equivalent of this and that is deliberate.** A
	/// `pnpm-lock.yaml` records no registry at all for an ordinary package — the
	/// resolution is an integrity hash and nothing else — and the registry it was
	/// installed from lives in somebody's `.npmrc`, which says what the *next*
	/// install would use rather than what this one did. 514 met the same question
	/// as a `package-lock.json` with no `resolved` and answered it the same way:
	/// a row with a version and no origin, rather than a row claiming an origin
	/// nobody wrote down.
	static func yarnOrigin(ofLocator locator: String) -> String {
		guard let colon = locator.firstIndex(of: ":") else { return "" }
		let scheme = String(locator[..<colon])
		let rest = String(locator[locator.index(after: colon)...])
		switch scheme {
		case "npm": return "npmjs.com"
		// `foo@patch:foo@npm%3A1.0.0#./p.patch` — the patched package came from
		// wherever the entry it wraps did, and that is written inside it, encoded.
		case "patch": return rest.contains("npm%3A") || rest.contains("npm:") ? "npmjs.com" : ""
		default: return npmOrigin(of: locator)
		}
	}

	/// `@babel/core`, `7.23.0` → `@babel-core-npm-7.23.0`.
	static func yarnCacheKey(name: String, version: String) -> String {
		name.replacingOccurrences(of: "/", with: "-") + "-npm-" + version
	}

	/// The Plug'n'Play cache, **listed rather than computed** for the third time
	/// in this file.
	///
	/// An archive is `<name>-npm-<version>-<hash>-<cacheKey>.zip`, where the hash
	/// is of the file's contents and the cache key is berry's own — neither
	/// computable from outside yarn. So the list is read and both truncations are
	/// registered: older berry wrote no cache key, and guessing which of the two a
	/// project uses would be a lookup that silently found nothing.
	static func yarnCacheArchives(at root: URL) -> [String: URL] {
		let cache = root.appendingPathComponent(".yarn/cache")
		let entries = ((try? FileManager.default.contentsOfDirectory(
			at: cache, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		)) ?? [])
			.filter { $0.pathExtension == "zip" }
			.sorted { $0.lastPathComponent < $1.lastPathComponent }

		var found: [String: URL] = [:]
		for entry in entries {
			let stem = entry.deletingPathExtension().lastPathComponent
			let parts = stem.split(separator: "-", omittingEmptySubsequences: false)
			for drop in [2, 1] where parts.count > drop {
				let key = parts.dropLast(drop).joined(separator: "-")
				if found[key] == nil { found[key] = entry }
			}
		}
		return found
	}
}
