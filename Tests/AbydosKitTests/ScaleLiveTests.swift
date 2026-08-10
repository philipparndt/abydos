import Testing
import Foundation
@testable import AbydosKit

/// What the engine costs on a project the size of the one this app is meant for.
///
/// `PerformanceTests` measures a synthetic 200,000-line file in one directory,
/// which is the right subject for the rope and the highlighter and the wrong one
/// for everything 0428 is about: half a million lines spread over a thousand
/// bundles is a shape, not a size, and the parts that hurt at that shape — the
/// tree, `git status`, the language-server scan, search — never see a large file
/// at all.
///
/// A `…LiveTests` in the house sense — it needs something this machine may not
/// have, and skips rather than fails without it — with one difference from the
/// others, which is that it also has to be *asked for*. `make scale` does both:
/// `Scripts/corpus.sh` puts the corpus beside the checkout, and `SCALE=1` says
/// this is the run that wants it. See `asked` for why the second is needed.
///
/// **Nothing here asserts a duration.** These are baselines to be compared
/// against, not gates: the numbers are minutes on a large corpus, the corpus is
/// whatever upstream tagged this month, and a bound on any of that would be a
/// test that fails for reasons that are nobody's fault. Every timing is printed
/// with the load average beside it, which is what makes it worth reading later.
struct ScaleLiveTests {
	static var corpus: URL {
		URL(fileURLWithPath: ProcessInfo.processInfo.environment["CORPUS"]
			?? NSString(string: "~/dev/abydos-corpus").expandingTildeInPath)
	}

	/// The three subjects the item asks for: the Platform aggregate, one Tycho
	/// repository for the inner loop, and this repository for contrast.
	static var subjects: [(name: String, url: URL)] {
		var found: [(String, URL)] = []
		let platform = corpus.appendingPathComponent("platform")
		let sirius = corpus.appendingPathComponent("sirius")
		if FileManager.default.fileExists(atPath: platform.path) { found.append(("platform", platform)) }
		if FileManager.default.fileExists(atPath: sirius.path) { found.append(("sirius", sirius)) }
		// This repository, found from the test bundle rather than from the
		// working directory: `swift test` runs from wherever it was started.
		var here = URL(fileURLWithPath: #filePath)
		for _ in 0..<3 { here.deleteLastPathComponent() }
		found.append(("abydos", here))
		return found
	}

	static func report(_ subject: String, _ label: String, _ value: String) {
		print(String(format: "SCALE %-10s %-30s %@", (subject as NSString).utf8String!,
			(label as NSString).utf8String!, value))
	}

	/// Wall clock and processor time for the same piece of work.
	///
	/// Both, always. Wall clock is what a person waits through and is the honest
	/// answer to "how long did opening take"; processor time is what changes when
	/// the code does and is the only one of the two worth comparing across runs
	/// taken at different loads. 0416 established the second; this item is the
	/// first place where the gap between them is large enough to matter, because
	/// most of what is being timed here waits on a disk.
	@discardableResult
	static func timed(_ subject: String, _ label: String, _ body: () -> String) -> TimeInterval {
		var cpuStart = timespec(), cpuEnd = timespec()
		clock_gettime(CLOCK_THREAD_CPUTIME_ID, &cpuStart)
		let start = DispatchTime.now().uptimeNanoseconds
		let said = body()
		let wall = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
		clock_gettime(CLOCK_THREAD_CPUTIME_ID, &cpuEnd)
		let cpu = Double(cpuEnd.tv_sec - cpuStart.tv_sec)
			+ Double(cpuEnd.tv_nsec - cpuStart.tv_nsec) / 1_000_000_000
		report(subject, label, String(format: "%8.1f ms wall, %8.1f ms cpu  %@  [%@]",
			wall * 1000, cpu * 1000, said, MachineLoad.said))
		return wall
	}

	/// Asked for, rather than merely possible.
	///
	/// The other `…LiveTests` skip themselves when the thing they need is
	/// missing and run whenever it is there, and this one started that way. It
	/// cannot: walking 22,680 directories of Eclipse is visible to the rest of
	/// the suite, because `FileNode.directoryReadsForTesting` is process-wide
	/// and `FileNodeReloadTests` zeroes it and then asserts it is still zero.
	/// Beside this suite that test fails, on a true claim about its own tree
	/// that this one had quietly added to. `LanguageServers.DirectoryIndex`
	/// argues the same point in a comment and keeps its count on the index; the
	/// tree's counter is older and does not.
	///
	/// So: opt in. `make scale` sets it. That also suits what this is — a dozen
	/// seconds of measurement over 763 MB of somebody else's source, asserting
	/// nothing, wanted when somebody is taking a baseline and not on every run.
	///
	/// Read through a `guard … else { return }` at each test rather than a
	/// `#require`, which is how every other live test here skips: `#require` on
	/// a Bool *fails*, and a red suite on a machine that simply has no Eclipse
	/// on it is the thing the convention exists to avoid.
	static var asked: Bool {
		guard ProcessInfo.processInfo.environment["SCALE"] != nil else { return false }
		guard FileManager.default.fileExists(atPath: corpus.path) else {
			print("SCALE no corpus at \(corpus.path) — run Scripts/corpus.sh")
			return false
		}
		return true
	}

	// MARK: - The tree

	/// What opening a project costs the tree, and what walking all of it would.
	///
	/// Two numbers because the tree is lazy and the whole design depends on it:
	/// opening lists the root and nothing else, which is why a thousand-bundle
	/// project opens at all. The second number is what it would cost if
	/// something walked the lot — which is what `handleFilesystemChange` used to
	/// do a directory at a time, and what `loadedNode(for:)` exists to stop.
	@Test func theTreeListsWhatOpeningAProjectNeedsAndNoMore() throws {
		guard Self.asked else { return }
		for (name, url) in Self.subjects {
			let root = FileNode(url: url, isDirectory: true)
			Self.timed(name, "tree: list the root") {
				"\(root.children.count) rows, 1 listing"
			}

			// Counted here rather than read from `FileNode.directoryReadsForTesting`.
			// That counter is process-wide, and `FileNodeReloadTests` zeroes it
			// and then asserts it is still zero — so running beside this suite
			// it failed, on a claim about its own tree that this one had
			// quietly added to. `DirectoryIndex` says the same thing in a
			// comment; this is the suite that proved it. A directory visited on
			// a tree nothing has listed yet is a directory listed once, so the
			// walk can count itself and owes nobody any shared state.
			Self.timed(name, "tree: walk everything") {
				var listings = 0
				func walk(_ node: FileNode) {
					listings += 1
					for child in node.children where child.isDirectory { walk(child) }
				}
				walk(root)
				return "\(root.loadedNodeCount) nodes, \(listings) listings"
			}
		}
	}

	// MARK: - The language server scan

	/// What deciding which servers a project wants costs at this scale.
	///
	/// 0437 made this one listing per directory rather than one per definition.
	/// It was measured then on this repository, where the difference was 42
	/// listings against 6; the question 0428 asks is what the remaining walk
	/// costs on a project with a thousand bundles in it, since it runs at open,
	/// on the queue the keyboard shares.
	@Test func decidingWhichServersAProjectWantsIsOneWalkOfIt() throws {
		guard Self.asked else { return }
		for (name, url) in Self.subjects {
			let index = LanguageServers.DirectoryIndex()
			Self.timed(name, "language server scan") {
				let suited = LanguageServers.known.filter {
					!$0.rootMarkers.isEmpty
						&& LanguageServers.markerDirectory(for: $0, in: url, maxDepth: 2, index: index) != nil
				}
				return "\(index.listingCount) listings, \(suited.count) servers: "
					+ suited.map(\.command).joined(separator: " ")
			}
		}
	}

	// MARK: - Version control

	/// `git status` on a repository this size, cold and warm.
	///
	/// The tree asks for this on every filesystem event. Coalescing made that
	/// affordable here — one at a time with at most one queued — and the item's
	/// suspicion is that coalescing is not enough when each one takes as long as
	/// these do.
	@Test func gitStatusOnARepositoryThisSize() async throws {
		guard Self.asked else { return }
		// The aggregate has no repository at its root, so the largest single
		// Tycho repository stands in for it. Both are named, because the number
		// that matters for the aggregate is that there is no number: nothing
		// colours that tree at all.
		let repositories = [
			("sirius", Self.corpus.appendingPathComponent("sirius")),
			("platform.ui", Self.corpus.appendingPathComponent("platform/eclipse.platform.ui")),
			("abydos", Self.subjects.last!.url),
		]
		for (name, url) in repositories {
			guard FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
			else { continue }
			let git = GitRepository(root: url)
			var cold: TimeInterval = 0
			var warm: TimeInterval = 0
			for round in 0..<2 {
				let start = DispatchTime.now().uptimeNanoseconds
				await git.refresh()
				let changed = await git.changedFileCount()
				let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
				if round == 0 { cold = elapsed } else { warm = elapsed }
				if round == 1 {
					Self.report(name, "git status", String(format:
						"%8.1f ms cold, %8.1f ms warm, %d changed  [%@]",
						cold * 1000, warm * 1000, changed, MachineLoad.said))
				}
			}
		}
	}

	// MARK: - Search

	/// First result and all results, which are the two numbers a person feels.
	///
	/// The first is when the pane stops being empty and the second is when the
	/// count stops moving; on this repository they are close enough to be one
	/// number, and the item's guess is that at a thousand bundles they are not.
	@Test func searchingAProjectThisSize() async throws {
		guard Self.asked else { return }
		for (name, url) in Self.subjects {
			let search = ProjectSearch(root: url)
			// A word that is everywhere in Java and nowhere in this repository's
			// Swift would measure two different things, so the query is one both
			// have in quantity.
			let query = "public"
			let start = DispatchTime.now().uptimeNanoseconds
			// Both stamps are taken inside the search's own callbacks, not after
			// awaiting it: a continuation resumes on whichever thread is free,
			// and on a loaded machine that hop is tens of milliseconds of
			// somebody else's scheduling attributed to the search.
			let run = await withCheckedContinuation {
				(continuation: CheckedContinuation<(first: Double, all: Double, files: Int, scanned: Int), Never>) in
				var first: Double?
				var files = 0
				func since() -> Double {
					Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
				}
				search.search(query: query, options: SearchOptions()) { results in
					files += results.count
					if first == nil { first = since() }
				} onFinished: { _, scanned in
					let all = since()
					continuation.resume(returning: (first ?? all, all, files, scanned))
				}
			}
			Self.report(name, "search \"\(query)\"", String(format:
				"%8.1f ms to first, %8.1f ms to all, %d files matched of %d scanned  [%@]",
				run.first * 1000, run.all * 1000, run.files, run.scanned, MachineLoad.said))
		}
	}
}
