import Foundation
import Testing
@testable import AbydosKit

/// Against a real container, because the numbers are the whole point.
///
/// The parsing is settled in `ToolInventoryTests` from transcripts, and that
/// leaves the one thing a transcript cannot say: whether the commands asked
/// here are the commands the runtime on this machine actually answers. A view
/// of what a session is costing that quietly shows a dash for every container
/// is worse than none — it says the containers are free.
///
/// Skipped unless docker has `alpine:3` already, the same way every other live
/// test in this suite is:
///
///     docker pull alpine:3
@Suite(.serialized) struct ToolInventoryLiveTests {
	@Test func readsWhatARunningContainerCostsAndWhenItStarted() async throws {
		guard let runtime = ContainerRuntime.discover(preference: .docker),
		      hasAlpine(runtime)
		else { return }

		let name = ToolContainers.mint("probe")
		defer {
			_ = RuntimeCommand.run(
				ToolContainers.removal(of: [name], using: runtime), deadline: 20
			)
		}
		let started = RuntimeCommand.run(
			(runtime.path, ["run", "-d", "--name", name, "alpine:3", "sleep", "60"]),
			deadline: 60
		)
		try #require(started.succeeded, "could not start a probe container: \(started.output)")

		let facts = ContainerInventory.facts(named: [name], using: runtime)
		try #require(facts.count == 1)
		let fact = facts[0]

		#expect(fact.name == name)
		#expect(fact.image == "alpine:3")
		#expect(fact.status.hasPrefix("Up"))
		#expect(fact.isRunning)

		// The two numbers the list exists to show. A sleeping alpine is a few
		// hundred kilobytes, so the assertion is that there is a number at all
		// and that it is not absurd — a specific figure would be a test of
		// busybox rather than of this.
		let resident = try #require(fact.residentBytes, "the runtime said nothing about memory")
		#expect(resident > 0)
		#expect(resident < 256 * 1_048_576)

		let startedAt = try #require(fact.startedAt, "the runtime said nothing about when it started")
		#expect(abs(startedAt.timeIntervalSinceNow) < 120)
	}

	/// Both runtimes, asked whether these are commands they accept at all.
	///
	/// The transcripts in `ToolInventoryTests` settle the reading and cannot
	/// settle the asking: a flag this runtime has never heard of parses to
	/// nothing in exactly the way an empty machine does, and the view would show
	/// a dash for every container without anything failing. Apple's runtime is
	/// the one that needs this — no live test in this suite drives it, and
	/// nothing else in the app calls `stats` at all.
	///
	/// Nothing is started here. Each runtime is asked only if its own listing
	/// answers, because a runtime whose service is down is not this app's fault
	/// and not this test's subject.
	@Test func asksBothRuntimesOnlyWhatTheyUnderstand() {
		for runtime in [
			ContainerRuntime.discover(preference: .docker),
			ContainerRuntime.discover(preference: .apple),
		].compactMap({ $0 }) {
			let listed = RuntimeCommand.run(
				ContainerInventory.listing(using: runtime),
				deadline: ContainerInventory.deadline
			)
			guard listed.succeeded else { continue }
			// No names: every runtime answers about whatever is running, which
			// is all this needs — that the subcommand and the flags are ones it
			// knows.
			let measured = RuntimeCommand.run(
				ContainerInventory.stats(of: [], using: runtime),
				deadline: ContainerInventory.deadline
			)
			#expect(measured.succeeded, "\(runtime.path) refused stats: \(measured.output)")
		}
	}

	/// Every process on this machine includes this one, and this one has a
	/// parent and a size — which is the whole of what a server's row reads.
	@Test func measuresThisVeryProcessOutOfPs() {
		let table = ProcessTable.sample()
		let mine = ProcessInfo.processInfo.processIdentifier
		let cost = table.cost(of: mine)
		#expect(cost != nil)
		#expect((cost?.residentBytes ?? 0) > 1_048_576)
		#expect((cost?.elapsed ?? -1) >= 0)
	}

	private func hasAlpine(_ runtime: ContainerRuntime) -> Bool {
		let listed = RuntimeCommand.run(
			(runtime.path, ["image", "inspect", "alpine:3"]), deadline: 20
		)
		return listed.succeeded
	}
}
