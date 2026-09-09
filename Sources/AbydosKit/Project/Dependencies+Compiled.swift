import Foundation

/// The three that keep a lock file this app can read straight through: Swift
/// packages, Go modules and Cargo.
///
/// Grouped because they are the easy shape — one resolved file, one entry per
/// package, a version beside each — and because reading three of them together
/// is what shows that shape being the same.
extension ExternalDependencies {
	// MARK: - Swift packages

	/// `Package.resolved`, which is JSON and is the resolved graph.
	///
	/// Both layouts, because both are still written: version 1 keys the list
	/// `object.pins` and names a package `package` with a `repositoryURL`,
	/// versions 2 and 3 key it `pins` and name it `identity` with a `location`.
	/// A project resolved by Xcode 15 and one resolved by `swift package
	/// resolve` last week differ by exactly this, and refusing to read the older
	/// one would be a section that empties itself when somebody opens an old
	/// checkout.
	static func readSwiftPackages(at root: URL) -> DependencySet.Contents {
		let resolved = root.appendingPathComponent("Package.resolved")
		guard let data = try? Data(contentsOf: resolved) else {
			return .unresolved("no Package.resolved — run swift package resolve")
		}
		guard let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
			return .unresolved("Package.resolved could not be read")
		}
		let pins = (top["pins"] as? [[String: Any]])
			?? ((top["object"] as? [String: Any])?["pins"] as? [[String: Any]])
			?? []

		let checkouts = checkoutDirectories(for: root)
		let manager = FileManager.default
		let packages = pins.compactMap { pin -> ExternalDependency? in
			let location = (pin["location"] as? String) ?? (pin["repositoryURL"] as? String) ?? ""
			let identity = (pin["identity"] as? String) ?? (pin["package"] as? String) ?? ""
			// The repository's own name, which is what the checkout directory is
			// called and what the import says. `identity` is lowercased by SwiftPM
			// — "cadova" — so a row taken from it would match neither the folder
			// on disk nor anything somebody typed.
			let name = Self.repositoryName(from: location) ?? identity
			guard !name.isEmpty else { return nil }

			let state = pin["state"] as? [String: Any]
			let version = (state?["version"] as? String)
				?? (state?["branch"] as? String)
				?? (state?["revision"] as? String).map { String($0.prefix(7)) }

			// The checkout is named after the repository, except when SwiftPM has
			// had to disambiguate — so the identity is tried too rather than
			// assumed away.
			let names = [name, identity].filter { !$0.isEmpty }
			let found = checkouts
				.flatMap { directory in names.map(directory.appendingPathComponent) }
				.filter { manager.fileExists(atPath: $0.path) }

			return ExternalDependency(
				name: name, version: version, origin: location,
				localPath: found.first, otherPaths: Array(found.dropFirst())
			)
		}
		return byName(packages)
	}

	/// Where a Swift package's sources may have been checked out, best first.
	///
	/// **There are two copies and they are not interchangeable, which is the
	/// thing this item found out the hard way.** `swift build` in the project
	/// fetches into `.build/checkouts`. sourcekit-lsp is started with
	/// `--scratch-path` pointing at `~/Library/Caches/abydos/index/<project>-<hash>`
	/// — derived data, deliberately not in the checkout — and fetches its own
	/// copy into `checkouts` beneath *that*. So following a symbol out of
	/// somebody's model opens
	///
	///     ~/Library/Caches/abydos/index/cadova-models-mn5raibyyd7h/checkouts/
	///         Cadova/Sources/Cadova/…/Extrusion.swift
	///
	/// and not the path under `.build` that the report and this item both
	/// assumed. A section that knew only about `.build/checkouts` gave the file
	/// in the tab no home at all — the exact failure being fixed — while
	/// looking correct in every test written against a fixture.
	///
	/// The indexer's copy comes first for that reason: it is the copy *this
	/// program* opens files from, so the row somebody is revealed into is the
	/// row their tab is actually showing. A file under `.build/checkouts` is
	/// inside the project and the ordinary tree already has a row for it.
	static func checkoutDirectories(for root: URL) -> [URL] {
		[
			LanguageServers.indexScratchPath(for: root).appendingPathComponent("checkouts"),
			root.appendingPathComponent(".build/checkouts"),
		]
	}

	/// `https://github.com/tomasf/Cadova.git` → `Cadova`.
	static func repositoryName(from location: String) -> String? {
		var text = location
		if text.hasSuffix("/") { text = String(text.dropLast()) }
		if text.hasSuffix(".git") { text = String(text.dropLast(4)) }
		let last = text.split(whereSeparator: { $0 == "/" || $0 == ":" }).last
		return last.map(String.init)
	}

	// MARK: - Go modules

	/// `go.mod`, which is both the manifest and the resolved set.
	///
	/// There is no lock file to read: since Go 1.17 `go.mod` lists the whole
	/// build list, direct and indirect, each with the version the build uses. So
	/// this reads the `require` clauses — the one-line form and the block form,
	/// which are both common in the same file — and nothing else.
	///
	/// Direct and indirect are not told apart, though `// indirect` is right
	/// there. One list sorted by name is what makes the section browsable: the
	/// question being asked of it is "what is beside this file", and an answer
	/// sorted by how the dependency was reached rather than by its name is an
	/// answer nobody can scan. See item 508 for the argument.
	static func readGoModules(at root: URL) -> DependencySet.Contents {
		let manifest = root.appendingPathComponent("go.mod")
		guard let text = try? String(contentsOf: manifest, encoding: .utf8) else {
			return .unresolved("go.mod could not be read")
		}

		var requires: [(module: String, version: String)] = []
		var inBlock = false
		for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
			// The comment goes first: `// indirect` sits on most of these lines
			// and would otherwise be counted as two more fields.
			var line = Substring(rawLine)
			if let comment = line.range(of: "//") { line = line[..<comment.lowerBound] }
			line = line.trimmingCharacters(in: .whitespaces)[...]
			guard !line.isEmpty else { continue }

			if inBlock {
				if line == ")" { inBlock = false; continue }
				let fields = line.split(separator: " ").filter { !$0.isEmpty }
				if fields.count >= 2 { requires.append((String(fields[0]), String(fields[1]))) }
				continue
			}
			guard line.hasPrefix("require") else { continue }
			let rest = line.dropFirst("require".count).trimmingCharacters(in: .whitespaces)
			if rest == "(" { inBlock = true; continue }
			let fields = rest.split(separator: " ").filter { !$0.isEmpty }
			if fields.count >= 2 { requires.append((String(fields[0]), String(fields[1]))) }
		}

		let cache = goModuleCache()
		let manager = FileManager.default
		let packages = requires.map { require -> ExternalDependency in
			let directory = cache?
				.appendingPathComponent(escapeGoPath(require.module) + "@" + require.version)
			let local = directory.flatMap { manager.fileExists(atPath: $0.path) ? $0 : nil }
			return ExternalDependency(
				name: require.module,
				version: require.version,
				// A module path *is* where it came from. Go has no separate URL:
				// `github.com/spf13/cobra` is fetched by being named.
				origin: require.module,
				localPath: local
			)
		}
		return byName(packages)
	}

	/// Where the module cache is, without asking `go env`.
	///
	/// `GOMODCACHE`, then `$GOPATH/pkg/mod`, then `~/go/pkg/mod`, which is the
	/// order the toolchain itself resolves them in. A subprocess would be
	/// authoritative and would cost a process launch per project on open; these
	/// three cover every machine that has not deliberately moved it, and a
	/// package whose directory is not found simply has no sources to browse,
	/// which is a state the row already knows how to show.
	static func goModuleCache() -> URL? {
		let environment = ProcessInfo.processInfo.environment
		if let path = environment["GOMODCACHE"], !path.isEmpty {
			return URL(fileURLWithPath: path)
		}
		if let path = environment["GOPATH"], !path.isEmpty {
			return URL(fileURLWithPath: path).appendingPathComponent("pkg/mod")
		}
		return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("go/pkg/mod")
	}

	/// The module cache's escaping: an upper-case letter becomes `!` and its
	/// lower-case self.
	///
	/// `github.com/IBM/sarama` is on disk as `github.com/!i!b!m/sarama`. Case
	/// alone cannot name a directory on a case-insensitive file system, and two
	/// modules differing only in case would otherwise collide — so the toolchain
	/// escapes rather than lower-cases, and anything looking for the sources has
	/// to escape the same way. Found the hard way: without this, every module
	/// with a capital in its path had no sources and the rows looked like
	/// packages nobody had fetched.
	static func escapeGoPath(_ path: String) -> String {
		var escaped = ""
		for character in path {
			if character.isUppercase {
				escaped.append("!")
				escaped.append(contentsOf: character.lowercased())
			} else {
				escaped.append(character)
			}
		}
		return escaped
	}

	// MARK: - Cargo

	/// One `[[package]]` out of `Cargo.lock`, as the file writes it.
	struct CargoLockPackage: Equatable {
		let name: String
		let version: String?
		/// Absent for a package that is not fetched from anywhere: a workspace
		/// member — the project's own crate is in its own lock file — or a `path`
		/// dependency, which is a directory the tree already shows.
		let source: String?
	}

	/// `Cargo.lock`, which is the resolved graph and is TOML.
	///
	/// The lock file rather than `Cargo.toml`, for the same reason
	/// `Package.resolved` is read rather than `Package.swift`: the manifest says
	/// `serde = "1"` and the lock says `1.0.229`, and the row has to name the
	/// version on disk. `cargo metadata` would answer both at once and is a
	/// subprocess — see the rule on this type; it is `swift package
	/// dump-package` wearing a different name, and it writes a lock file as a
	/// side effect of being asked.
	///
	/// A lock file whose every package is a workspace member or a `path`
	/// dependency reads as `.packages([])` — "no dependencies" — which is right:
	/// those are directories inside the project and the tree already has rows
	/// for them. An *external* section listing them would show the project's own
	/// source twice.
	static func readCargoPackages(at root: URL) -> DependencySet.Contents {
		let lock = root.appendingPathComponent("Cargo.lock")
		guard let text = try? String(contentsOf: lock, encoding: .utf8) else {
			if let workspace = cargoWorkspaceAbove(root) {
				return .unresolved("resolved in the workspace at \(workspace.lastPathComponent)")
			}
			// In cargo's own words: `cargo fetch` writes the lock file and fills
			// the registry cache, which is both halves of what this row needs.
			return .unresolved("no Cargo.lock — run cargo fetch")
		}

		let registries = cargoRegistryDirectories()
		let packages = parseCargoLock(text).compactMap { entry -> ExternalDependency? in
			guard let source = entry.source else { return nil }
			return ExternalDependency(
				name: entry.name,
				version: entry.version,
				origin: cargoOrigin(of: source),
				localPath: cargoSources(
					name: entry.name, version: entry.version, source: source, registries: registries
				)
			)
		}
		return byName(packages)
	}

	/// The `[[package]]` tables of a lock file, line by line.
	///
	/// **Thirty lines instead of a TOML dependency**, which is the same call
	/// `SwiftPackage` made about `Package.swift` and `readGoModules` about
	/// `go.mod`. `Cargo.lock` is generated, never hand-written, and is a flat
	/// sequence of tables of quoted strings — no nesting, no dates, no
	/// multi-line strings, nothing a parser would earn its keep on. `project.md`
	/// asks for an argument before a dependency is added and "one file, four
	/// keys" is not one.
	///
	/// Only the four keys are taken, and only where the key is a bare word: the
	/// `dependencies = [ … ]` array under most packages holds bare strings, and
	/// in the version 1 and 2 layouts those strings are whole package ids with
	/// `git+…?branch=main#sha` inside them. A parser splitting every line on its
	/// first `=` would read that fragment as a table key.
	static func parseCargoLock(_ text: String) -> [CargoLockPackage] {
		var packages: [CargoLockPackage] = []
		var name: String?
		var version: String?
		var source: String?
		var inPackage = false

		func finish() {
			if inPackage, let name, !name.isEmpty {
				packages.append(CargoLockPackage(name: name, version: version, source: source))
			}
			name = nil; version = nil; source = nil
		}

		for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
			let line = rawLine.trimmingCharacters(in: .whitespaces)
			if line.hasPrefix("[") {
				// Any other table ends this one: `[metadata]` in the version 1
				// layout, and `[[patch.unused]]` at the end of many real files.
				finish()
				inPackage = line == "[[package]]"
				continue
			}
			guard inPackage, let equals = line.firstIndex(of: "=") else { continue }
			let key = line[..<equals].trimmingCharacters(in: .whitespaces)
			let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
			guard value.hasPrefix("\""), value.count >= 2, value.hasSuffix("\"") else { continue }
			let unquoted = String(value.dropFirst().dropLast())
			switch key {
			case "name": name = unquoted
			case "version": version = unquoted
			case "source": source = unquoted
			default: continue
			}
		}
		finish()
		return packages
	}

	/// The workspace that resolves for this crate, if it is a member of one.
	///
	/// **Found in the app, on the first Rust project it was pointed at.** A
	/// workspace has one `Cargo.lock`, at its root, and none beside its members
	/// — and a Rust repository of any size is a workspace, so every member crate
	/// is a subproject the section has a row for. Telling somebody to run `cargo
	/// fetch` in a member is telling them to run a command that will write
	/// nothing there: the resolving already happened, one directory up. So the
	/// row says where instead.
	///
	/// The list itself is not borrowed from the workspace. It is the *whole*
	/// workspace's resolved set, not this member's, and copying it under every
	/// member would print two hundred rows five times over and claim each crate
	/// depends on all of it.
	///
	/// Walked up rather than asked of cargo, and bounded: a member two or three
	/// directories down (`crates/foo`) is the usual layout and the intervening
	/// directories have no manifest of their own, so there is nothing nearer to
	/// stop at.
	static func cargoWorkspaceAbove(_ root: URL) -> URL? {
		let manager = FileManager.default
		var directory = root.deletingLastPathComponent()
		for _ in 0..<6 {
			guard directory.path != "/", directory.path != root.path else { return nil }
			let lock = directory.appendingPathComponent("Cargo.lock")
			let manifest = directory.appendingPathComponent("Cargo.toml")
			if manager.fileExists(atPath: lock.path), manager.fileExists(atPath: manifest.path) {
				return directory
			}
			directory = directory.deletingLastPathComponent()
		}
		return nil
	}

	/// Where a crate came from, from the `source` the lock file writes.
	///
	///     registry+https://github.com/rust-lang/crates.io-index   → crates.io
	///     sparse+https://index.crates.io/                         → crates.io
	///     git+https://github.com/dtolnay/anyhow#bf3ed914…         → the URL, whole
	///
	/// The default registry is named `crates.io` rather than by its index URL,
	/// which is the one place this departs from "as the lock file writes it".
	/// `github.com/rust-lang` — which is what `shortOrigin` makes of the index
	/// URL — reads as *the crate came from that repository*, and it would say it
	/// on every row of a list of two hundred, which is a column of noise saying
	/// nothing. Another registry keeps its URL, because there the host is the
	/// answer.
	///
	/// A git source keeps its query and fragment: `?branch=main` and the commit
	/// after `#` are what say *which* one of it, `shortOrigin` cuts back to
	/// `github.com/dtolnay` for the row, and the tooltip shows the whole of it.
	static func cargoOrigin(of source: String) -> String {
		guard let plus = source.firstIndex(of: "+") else { return source }
		let kind = String(source[..<plus])
		let location = String(source[source.index(after: plus)...])
		switch kind {
		case "registry", "sparse":
			return isCratesIoIndex(location) ? "crates.io" : location
		default:
			return location
		}
	}

	/// The two spellings of the one registry every Rust project uses: the git
	/// index it had until 1.68, and the sparse index it has had since.
	static func isCratesIoIndex(_ location: String) -> Bool {
		location.contains("rust-lang/crates.io-index") || location.contains("index.crates.io")
	}

	/// `$CARGO_HOME`, or `~/.cargo`.
	///
	/// The variable first, because a machine that has moved it has moved all of
	/// it, and then the documented default. No `cargo --version` and no
	/// `cargo config get`: a subprocess per project on open, for an answer that
	/// is wrong on no machine this is likely to meet, and a crate whose
	/// directory is not found simply has no sources to browse — a state the row
	/// already knows how to show.
	static func cargoHome() -> URL {
		let environment = ProcessInfo.processInfo.environment
		if let path = environment["CARGO_HOME"], !path.isEmpty {
			return URL(fileURLWithPath: path)
		}
		return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo")
	}

	/// The unpacked registry caches, **listed rather than computed**.
	///
	/// `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f`: the last part is
	/// a hash of the registry URL, made by a function inside cargo that is not
	/// specified anywhere and has changed at least once — it was
	/// `github.com-1ecc6299db9ec823` for the git index. Nothing outside cargo
	/// can compute it, so this reads the directory and takes whatever is in it.
	/// A machine with a vendored registry as well as crates.io has two, both are
	/// tried, and the order is fixed so that two reads of the same project agree.
	static func cargoRegistryDirectories() -> [URL] {
		let source = cargoHome().appendingPathComponent("registry/src")
		let entries = (try? FileManager.default.contentsOfDirectory(
			at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		)) ?? []
		return entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
	}

	/// The crate's own sources on this machine, or nil when nothing fetched them.
	///
	/// Two caches with two layouts, and neither is inside the project — the same
	/// shape as a Go module and not at all the shape of a Swift package:
	///
	///     registry:  <cargo home>/registry/src/<index-hash>/<name>-<version>
	///     git:       <cargo home>/git/checkouts/<repo>-<hash>/<short revision>
	static func cargoSources(
		name: String, version: String?, source: String, registries: [URL]
	) -> URL? {
		let manager = FileManager.default
		guard let plus = source.firstIndex(of: "+") else { return nil }
		let kind = String(source[..<plus])
		let location = String(source[source.index(after: plus)...])

		guard kind == "git" else {
			guard let version else { return nil }
			let directory = "\(name)-\(version)"
			return registries
				.map { $0.appendingPathComponent(directory) }
				.first { manager.fileExists(atPath: $0.path) }
		}

		// `git+https://github.com/dtolnay/anyhow?branch=main#bf3ed914…`: the
		// checkout is named after the *repository* and the directory inside it
		// after the revision, abbreviated by cargo to a length it does not
		// promise — so the revision is matched by prefix rather than cut to
		// seven characters and compared.
		let revision = location.firstIndex(of: "#").map { String(location[location.index(after: $0)...]) }
		var repository = location
		if let hash = repository.firstIndex(of: "#") { repository = String(repository[..<hash]) }
		if let query = repository.firstIndex(of: "?") { repository = String(repository[..<query]) }
		guard let repositoryName = repositoryName(from: repository), let revision else { return nil }

		let checkouts = cargoHome().appendingPathComponent("git/checkouts")
		let candidates = ((try? manager.contentsOfDirectory(
			at: checkouts, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		)) ?? [])
			.filter { $0.lastPathComponent.hasPrefix(repositoryName + "-") }
			.sorted { $0.lastPathComponent < $1.lastPathComponent }

		for checkout in candidates {
			let revisions = ((try? manager.contentsOfDirectory(
				at: checkout, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
			)) ?? [])
			guard let worktree = revisions.first(where: {
				revision.hasPrefix($0.lastPathComponent) || $0.lastPathComponent.hasPrefix(revision)
			}) else { continue }
			// One repository can hold several crates, and the lock file does not
			// say which directory this one is in. Its own name is the convention
			// and is worth a `stat`; the checkout root is the honest fallback,
			// since it is where the crate is when the repository is one crate.
			let inside = worktree.appendingPathComponent(name)
			return manager.fileExists(atPath: inside.path) ? inside : worktree
		}
		return nil
	}
}
