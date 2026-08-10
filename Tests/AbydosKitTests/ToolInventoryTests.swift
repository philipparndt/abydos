import Foundation
import Testing
@testable import AbydosKit

/// Reading what a language server and a container are costing.
///
/// The arithmetic and the parsing only — what is on screen is 0427's list, and
/// what makes it worth looking at is that the numbers in it are real. The one
/// that matters is the subtree: the server whose row would have said 32 MB had
/// fifteen gigabytes of compiler underneath it.
struct ToolInventoryTests {
	// MARK: - What a process and its children come to

	/// The number 0427 was opened by, in miniature: a small server with a large
	/// child, and the row has to show the pair.
	@Test func countsWhatAServerStartedAsPartOfTheServer() {
		let table = ProcessTable.parse("""
			  100     1  32000 01:23 /usr/bin/sourcekit-lsp
			  101   100 900000 01:20 /usr/bin/swift-frontend
			  102   101  40000 01:19 /usr/bin/swift-frontend
			  200     1   5000 10:00 /bin/zsh
			""")

		let cost = table.cost(of: 100)
		// The arithmetic is spelled `Int64` rather than left to inference: an
		// `Int64?` compared with an `Int` expression takes the `AnyHashable`
		// overload, which is false however equal the two numbers look.
		#expect(cost?.residentBytes == Int64((32_000 + 900_000 + 40_000) * 1024))
		#expect(cost?.descendants == 2)
		#expect(cost?.elapsed == 83)

		// And nothing of the shell beside it leaks in.
		#expect(table.cost(of: 200)?.descendants == 0)
	}

	/// A process that has gone is nil rather than zero: a row saying "0 MB"
	/// would be claiming it measured something.
	@Test func saysNothingRatherThanZeroAboutAProcessThatIsGone() {
		let table = ProcessTable.parse("  100     1  32000 01:23 /usr/bin/sourcekit-lsp")
		#expect(table.cost(of: 999) == nil)
	}

	/// `ps` is a snapshot, and a parent that exited while it was being read can
	/// leave a line pointing at its own descendant. Walking that must end.
	@Test func survivesAParentThatPointsBackIntoItsOwnChildren() {
		let table = ProcessTable.parse("""
			  100   101  1 00:01 a
			  101   100  1 00:01 b
			""")
		#expect(table.cost(of: 100)?.descendants == 1)
	}

	/// The path is read off the running process, which is the only thing that
	/// says which toolchain a server actually came from — 0427's second fault.
	@Test func keepsThePathTheProcessIsRunningFrom() {
		let table = ProcessTable.parse(
			"  100     1  32000 01:23 /Applications/Xcode-beta.app/Contents/Developer/"
				+ "Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp"
		)
		#expect(table.entries[100]?.command.hasSuffix("XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp") == true)
	}

	/// `ps` writes elapsed time four ways depending on how long it has been.
	@Test func readsEveryShapeOfElapsedTime() {
		#expect(ProcessTable.seconds(elapsed: "05.00") == 5)
		#expect(ProcessTable.seconds(elapsed: "01:23") == 83)
		#expect(ProcessTable.seconds(elapsed: "02:03:04") == 7_384)
		#expect(ProcessTable.seconds(elapsed: "3-04:05:06") == TimeInterval(3 * 86_400 + 14_706))
		#expect(ProcessTable.seconds(elapsed: "later") == nil)
	}

	// MARK: - What a container is costing

	/// Docker answers `stats` with the container's use and the machine's
	/// capacity on one line, and only the first half is about this container.
	@Test func takesTheContainersHalfOfDockersMemoryLine() {
		let parsed = ContainerInventory.parseStats(
			"abydos-devcontainer-9-1\t1.427GiB / 15.66GiB\n"
				+ "abydos-plantuml-server-9-2\t120.5MiB / 15.66GiB\n",
			using: .docker("/usr/bin/docker")
		)
		#expect(parsed["abydos-devcontainer-9-1"] == Int64(1.427 * 1_073_741_824))
		#expect(parsed["abydos-plantuml-server-9-2"] == Int64(120.5 * 1_048_576))
	}

	@Test func readsWhateverUnitsARuntimeFeelsLikePrinting() {
		#expect(ContainerInventory.bytes(fromRuntimeSize: "512B") == 512)
		#expect(ContainerInventory.bytes(fromRuntimeSize: "1.5 GB") == Int64(1.5 * 1_073_741_824))
		#expect(ContainerInventory.bytes(fromRuntimeSize: "800kB") == Int64(800 * 1_024))
		#expect(ContainerInventory.bytes(fromRuntimeSize: "quite a lot") == nil)
	}

	/// The listing says what each container is and how long it has been up, and
	/// nothing on the machine that is not ours comes through it — docker's
	/// `--filter name=` is a substring match rather than a promise.
	@Test func keepsOnlyOurOwnContainersOutOfTheListing() {
		let parsed = ContainerInventory.parseListing(
			"abydos-devcontainer-9-1\tmcr.microsoft.com/devcontainers/go\tUp 4 minutes"
				+ "\t2026-08-09 21:58:12 +0200 CEST\n"
				+ "someone-elses-abydos-lookalike\tbusybox\tUp 2 days\t2026-08-01 09:00:00 +0200 CEST\n",
			using: .docker("/usr/bin/docker")
		)
		#expect(parsed.count == 1)
		#expect(parsed["abydos-devcontainer-9-1"]?.image == "mcr.microsoft.com/devcontainers/go")
		#expect(parsed["abydos-devcontainer-9-1"]?.status == "Up 4 minutes")
		#expect(parsed["abydos-devcontainer-9-1"]?.startedAt
			== ContainerInventory.date(fromDockerTimestamp: "2026-08-09 21:58:12 +0200 CEST"))
	}

	/// Docker writes the offset and then repeats it as an abbreviation; the
	/// offset is the half that means the same thing everywhere.
	@Test func readsDockersOwnTimestamp() {
		let parsed = ContainerInventory.date(fromDockerTimestamp: "2026-08-09 21:58:12 +0200 CEST")
		#expect(parsed == Date(timeIntervalSince1970: 1_786_305_492))
		#expect(ContainerInventory.date(fromDockerTimestamp: "not a time") == nil)
	}

	/// Apple's runtime answers both questions as JSON, in a different shape and
	/// in different units — bytes rather than `MiB`, and an ISO time rather than
	/// docker's. Both transcripts are off `container` 1.2.2.
	@Test func readsApplesOwnShapeOfTheSameTwoAnswers() {
		let runtime = ContainerRuntime.apple("/usr/local/bin/container")
		let listed = ContainerInventory.parseListing("""
			[{"configuration":{"id":"abydos-devcontainer-9-1",
			  "creationDate":"2026-08-09T18:15:31Z",
			  "image":{"reference":"mcr.microsoft.com/devcontainers/base:alpine-3.21"}},
			  "status":{"state":"running","startedDate":"2026-08-09T18:15:33Z","networks":[]}},
			 {"configuration":{"id":"mycluster","creationDate":"2026-08-09T11:45:41Z",
			  "image":{"reference":"docker.io/kindest/node"}},"status":{"state":"running"}}]
			""", using: runtime)

		// Its listing has no `--filter`, so everything else on the machine
		// arrives with it and is dropped here.
		#expect(listed.count == 1)
		#expect(listed["abydos-devcontainer-9-1"]?.status == "running")
		#expect(listed["abydos-devcontainer-9-1"]?.image
			== "mcr.microsoft.com/devcontainers/base:alpine-3.21")
		// When it started, which this runtime reports beside the state, rather
		// than when it was made — two seconds apart here and the same distance
		// apart in the transcript this is taken from.
		#expect(listed["abydos-devcontainer-9-1"]?.startedAt
			== ContainerInventory.date(fromISOTimestamp: "2026-08-09T18:15:33Z"))

		let stats = ContainerInventory.parseStats("""
			[{"id":"abydos-devcontainer-9-1","memoryUsageBytes":32800768,
			  "memoryLimitBytes":1073741824,"numProcesses":3}]
			""", using: runtime)
		// The container's own use, not the limit beside it.
		#expect(stats["abydos-devcontainer-9-1"] == Int64(32_800_768))
	}

	/// A container that has stopped is still registered here until something
	/// releases it, and `docker stats` answers `0B / 0B` about one rather than
	/// refusing — measured on docker 29.1.4. So whether it is running has to be
	/// read off the status, and the two runtimes do not spell it the same way.
	@Test func knowsEachRuntimesWordForStillRunning() {
		let docker = ContainerRuntime.docker("/usr/bin/docker")
		#expect(ContainerInventory.isRunning(status: "Up 4 minutes", using: docker))
		#expect(ContainerInventory.isRunning(status: "Up 2 hours (healthy)", using: docker))
		#expect(!ContainerInventory.isRunning(status: "Exited (0) 3 seconds ago", using: docker))
		#expect(!ContainerInventory.isRunning(status: "Created", using: docker))

		let apple = ContainerRuntime.apple("/usr/local/bin/container")
		#expect(ContainerInventory.isRunning(status: "running", using: apple))
		#expect(!ContainerInventory.isRunning(status: "stopped", using: apple))
		// And neither runtime's word is read with the other's rule.
		#expect(!ContainerInventory.isRunning(status: "running", using: docker))
		#expect(!ContainerInventory.isRunning(status: "Up 4 minutes", using: apple))
	}

	/// Neither command is ever asked to keep answering: `docker stats` without
	/// `--no-stream` never returns, which is the exact shape of process 0406
	/// and 0427 exist to stop this app leaving behind.
	@Test func asksForOneAnswerRatherThanAStream() {
		for runtime in [ContainerRuntime.docker("/usr/bin/docker"), .apple("/usr/local/bin/container")] {
			let stats = ContainerInventory.stats(of: ["abydos-plantuml-server-9-1"], using: runtime)
			#expect(stats.arguments.contains("stats"))
			#expect(stats.arguments.contains("--no-stream"))
			#expect(stats.arguments.contains("abydos-plantuml-server-9-1"))
		}
	}

	/// Nothing registered means nothing launched. A session with no containers
	/// at all is the common one, and it must cost nothing to look at.
	@Test func launchesNothingWhenThereAreNoContainers() {
		#expect(ContainerInventory.facts(
			named: [], using: .docker("/nonexistent/docker")
		).isEmpty)
	}

	// MARK: - Who started a container

	/// A name carries what started it, between the prefix and the two numbers
	/// `mint` puts on the end.
	@Test func readsTheRoleBackOutOfAMintedName() {
		#expect(ToolContainers.role(of: ToolContainers.mint("devcontainer")) == "devcontainer")
		#expect(ToolContainers.role(of: ToolContainers.mint("plantuml-server")) == "plantuml-server")
		#expect(ToolContainers.role(of: ToolContainers.mint("lsp-sourcekit-lsp")) == "lsp-sourcekit-lsp")
		// Not ours, and one of ours whose shape an older version wrote.
		#expect(ToolContainers.role(of: "some-other-container") == nil)
		#expect(ToolContainers.role(of: "abydos-old") == nil)
	}
}
