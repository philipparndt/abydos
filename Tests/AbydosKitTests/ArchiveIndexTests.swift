import Foundation
import Testing
@testable import AbydosKit

/// Archives read to list and not to unpack, over files the system's own
/// `zip`, `tar` and `gzip` made a moment ago.
struct ArchiveIndexTests {
	/// A directory with a small tree in it: a short file, a file long enough
	/// to be deflated, a nested one, and a name longer than tar's hundred.
	private func fixture() throws -> URL {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString)")
		let tree = root.appendingPathComponent("chart")
		try FileManager.default.createDirectory(at: tree.appendingPathComponent("templates"), withIntermediateDirectories: true)
		try "apiVersion: v2\nname: chart\n".write(to: tree.appendingPathComponent("Chart.yaml"), atomically: true, encoding: .utf8)
		try String(repeating: "replicas: 1\nimage: nginx\n", count: 200).write(to: tree.appendingPathComponent("values.yaml"), atomically: true, encoding: .utf8)
		try "kind: Deployment\n".write(to: tree.appendingPathComponent("templates/deployment.yaml"), atomically: true, encoding: .utf8)
		let long = String(repeating: "a-rather-long-directory-name/", count: 5) + "leaf.txt"
		let longURL = tree.appendingPathComponent(long)
		try FileManager.default.createDirectory(at: longURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		try "deep\n".write(to: longURL, atomically: true, encoding: .utf8)
		return root
	}

	@discardableResult
	private func run(_ command: String, _ arguments: [String], in directory: URL) throws -> Int32 {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: command)
		process.arguments = arguments
		process.currentDirectoryURL = directory
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		try process.run()
		process.waitUntilExit()
		return process.terminationStatus
	}

	private func paths(_ index: ArchiveIndex) -> [String] { index.entries.map(\.path) }

	@Test func aZipIsListedFromItsCentralDirectoryAndAMemberReadsBack() throws {
		let root = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		try run("/usr/bin/zip", ["-qr", "chart.zip", "chart"], in: root)

		let index = try ArchiveIndex.read(root.appendingPathComponent("chart.zip"))
		#expect(index.kind == .zip)
		#expect(paths(index).contains("chart/Chart.yaml"))
		#expect(paths(index).contains("chart/templates/deployment.yaml"))
		#expect(index.children(of: nil).map(\.path) == ["chart"])

		let values = try #require(index.entry(at: "chart/values.yaml"))
		guard case .zip(_, let method, let compressed) = values.source else { Issue.record("not a zip member"); return }
		#expect(method == 8)
		#expect(compressed < values.size)
		#expect(try index.read(values) == Data(String(repeating: "replicas: 1\nimage: nginx\n", count: 200).utf8))
		let small = try #require(index.entry(at: "chart/Chart.yaml"))
		#expect(try String(decoding: index.read(small), as: UTF8.self) == "apiVersion: v2\nname: chart\n")
	}

	@Test func foldersComeFirstAndThenNames() throws {
		let root = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		try run("/usr/bin/zip", ["-qr", "chart.zip", "chart"], in: root)
		let index = try ArchiveIndex.read(root.appendingPathComponent("chart.zip"))
		let names = index.children(of: "chart").map(\.name)
		#expect(names == ["a-rather-long-directory-name", "templates", "Chart.yaml", "values.yaml"])
	}

	@Test func aStoredMemberIsCopiedRatherThanInflated() throws {
		let root = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		try run("/usr/bin/zip", ["-qr0", "stored.jar", "chart"], in: root)
		let index = try ArchiveIndex.read(root.appendingPathComponent("stored.jar"))
		let values = try #require(index.entry(at: "chart/values.yaml"))
		guard case .zip(_, let method, let compressed) = values.source else { Issue.record("not a zip member"); return }
		#expect(method == 0)
		#expect(compressed == values.size)
		#expect(try index.read(values).count == values.size)
	}

	/// `zip -D` writes no directory entries; the folders are implied.
	@Test func directoriesNobodyWroteAreImplied() throws {
		let root = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		try run("/usr/bin/zip", ["-qrD", "flat.zip", "chart"], in: root)
		let index = try ArchiveIndex.read(root.appendingPathComponent("flat.zip"))
		let templates = try #require(index.entry(at: "chart/templates"))
		#expect(templates.isDirectory)
		#expect(templates.source == .implied)
		#expect(index.children(of: "chart/templates").map(\.name) == ["deployment.yaml"])
	}

	@Test func aTarIsWalkedByItsHeadersWithItsLongNames() throws {
		let root = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		try run("/usr/bin/tar", ["cf", "chart.tar", "chart"], in: root)
		let index = try ArchiveIndex.read(root.appendingPathComponent("chart.tar"))
		#expect(index.kind == .tar)
		let long = "chart/" + String(repeating: "a-rather-long-directory-name/", count: 5) + "leaf.txt"
		#expect(paths(index).contains(long))
		let leaf = try #require(index.entry(at: long))
		#expect(try String(decoding: index.read(leaf), as: UTF8.self) == "deep\n")
		let directory = try #require(index.entry(at: "chart/templates"))
		#expect(directory.isDirectory)
	}

	@Test func aGzippedTarIsInflatedAndWalked() throws {
		let root = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		try run("/usr/bin/tar", ["czf", "chart-0.1.0.tgz", "chart"], in: root)
		let index = try ArchiveIndex.read(root.appendingPathComponent("chart-0.1.0.tgz"))
		#expect(index.kind == .tarGzip)
		#expect(index.children(of: "chart").map(\.name).contains("values.yaml"))
		let values = try #require(index.entry(at: "chart/values.yaml"))
		#expect(try index.read(values).count == values.size)
	}

	@Test func aLoneGzipIsOneEntryNamedForTheFile() throws {
		let root = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		try run("/usr/bin/gzip", ["-k", "chart/values.yaml"], in: root)
		let index = try ArchiveIndex.read(root.appendingPathComponent("chart/values.yaml.gz"))
		#expect(index.kind == .gzip)
		#expect(index.entries.map(\.path) == ["values.yaml"])
		#expect(try index.read(index.entries[0]).count == index.entries[0].size)
	}

	@Test func aMisnamedFileSaysItIsNotAnArchive() throws {
		let root = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		let fake = root.appendingPathComponent("fake.zip")
		try "not an archive\n".write(to: fake, atomically: true, encoding: .utf8)
		#expect(throws: ArchiveIndex.Failure.notAnArchive) { try ArchiveIndex.read(fake) }
		#expect(ArchiveKind.isOffered(forName: "fake.zip"))
		#expect(ArchiveKind.isOffered(forName: "library.jar"))
		#expect(ArchiveKind.isOffered(forName: "chart.tar.gz"))
		#expect(!ArchiveKind.isOffered(forName: "README.md"))
	}

	@Test func pastTheCapTheArchiveSaysSo() throws {
		let root = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		try run("/usr/bin/tar", ["czf", "chart.tgz", "chart"], in: root)
		#expect(throws: ArchiveIndex.Failure.self) {
			try ArchiveIndex.read(root.appendingPathComponent("chart.tgz"), cap: 1024)
		}
	}

	@Test func theKeyChangesWhenTheFileIsReplaced() throws {
		let root = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		try run("/usr/bin/zip", ["-qr", "chart.zip", "chart"], in: root)
		let url = root.appendingPathComponent("chart.zip")
		let before = try ArchiveIndex.Key.of(url)
		try "more\n".write(to: root.appendingPathComponent("chart/extra.txt"), atomically: true, encoding: .utf8)
		Thread.sleep(forTimeInterval: 0.05)
		try run("/usr/bin/zip", ["-qr", "chart.zip", "chart"], in: root)
		#expect(try ArchiveIndex.Key.of(url) != before)
	}

	@Test func anEntryIsCachedOnceOutsideTheProjectAndExtractedBesideIt() throws {
		let root = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		try run("/usr/bin/tar", ["czf", "chart.tgz", "chart"], in: root)
		let index = try ArchiveIndex.read(root.appendingPathComponent("chart.tgz"))
		let values = try #require(index.entry(at: "chart/values.yaml"))
		let caches = root.appendingPathComponent("caches")
		let cached = try ArchiveCache.file(for: values, in: index, caches: caches)
		#expect(cached.path.hasPrefix(caches.appendingPathComponent("abydos/archives").path))
		#expect(cached.lastPathComponent == "values.yaml")
		#expect(try ArchiveCache.file(for: values, in: index, caches: caches) == cached)

		let written = try ArchiveCache.extract(values, from: index, into: root, overwrite: false)
		#expect(written == root.appendingPathComponent("values.yaml"))
		#expect(throws: ArchiveCache.ExtractFailure.exists(written)) {
			try ArchiveCache.extract(values, from: index, into: root, overwrite: false)
		}
		let templates = try #require(index.entry(at: "chart/templates"))
		let folder = try ArchiveCache.extract(templates, from: index, into: root.appendingPathComponent("caches"), overwrite: false)
		#expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("deployment.yaml").path))
	}

	/// The way back: a cache file names the entry it was written from.
	///
	/// **Which is a one-directional path being walked backwards, so it is
	/// asked about here.** The tree reveals an open entry by taking the file
	/// the editor holds, stripping the archive's own cache folder off the
	/// front, and asking the archive for what is left — there is nothing in a
	/// cache path that says which archive wrote it, the digest being a digest.
	/// Both halves of that are invariants of this file rather than of the tree:
	/// that every archive's folder sits under one root, so a path can be told
	/// to have come out of *an* archive at all, and that what follows the
	/// folder is exactly the entry's path. A layout change here would leave
	/// the reveal saying a file is not in the tree, which is the report this
	/// answers, and nothing in the window layer can be tested to catch it.
	@Test func aCachedEntryNamesTheEntryItCameFrom() throws {
		let root = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		try run("/usr/bin/tar", ["czf", "chart.tgz", "chart"], in: root)
		let index = try ArchiveIndex.read(root.appendingPathComponent("chart.tgz"))
		let caches = root.appendingPathComponent("caches")

		let directory = ArchiveCache.directory(for: index, caches: caches)
		#expect(directory.path.hasPrefix(ArchiveCache.root(caches: caches).path + "/"))

		// A file at the top and one nested, because the remainder is a path
		// rather than a name and a single-level entry would not show it.
		for path in ["chart/values.yaml", "chart/templates/deployment.yaml"] {
			let entry = try #require(index.entry(at: path))
			let cached = try ArchiveCache.file(for: entry, in: index, caches: caches)
			let prefix = directory.path + "/"
			#expect(cached.path.hasPrefix(prefix))
			#expect(String(cached.path.dropFirst(prefix.count)) == entry.path)
		}
	}
}
