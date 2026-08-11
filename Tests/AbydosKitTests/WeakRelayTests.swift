import Foundation
import Testing

@testable import AbydosKit

/// The two hops behind `EditorViewController.withText(of:send:)`: a document's
/// text decoded off the main queue and handed back on it.
///
/// 0465. The compiler was right about this one — `[weak self]` on the inner hop
/// only, with the outer closure holding `self` strongly to build it — and the
/// first test here is the claim the old shape could not make.
struct WeakRelayTests {
	private final class Owner {
		let name: String
		init(_ name: String) { self.name = name }
	}

	private func queue(_ name: String) -> DispatchQueue {
		DispatchQueue(label: "abydos-weak-relay-\(name)-\(UUID().uuidString)")
	}

	/// The behaviour 0465 changed, and the reason it is not a tidy-up.
	///
	/// The build is held open, the last strong reference to the owner is dropped
	/// while it is open, and the owner has to be gone at that moment. With the
	/// two nested `async` calls this replaced it was still there, because the
	/// outer closure captured it strongly to build the inner one — so an editor
	/// closed halfway through decoding a megabyte of UTF-8 lived until the decode
	/// finished.
	@Test func anOwnerDroppedWhileTheValueIsBuiltGoesAtOnce() {
		let building = DispatchSemaphore(value: 0)
		let carryOn = DispatchSemaphore(value: 0)
		var owner: Owner? = Owner("the editor")
		weak let watch = owner

		WeakRelay.build(on: queue("held"), for: owner!) {
			building.signal()
			carryOn.wait()
		} then: { _, _ in }

		building.wait()
		owner = nil
		#expect(watch == nil, "a build in flight held its owner alive")
		carryOn.signal()
	}

	/// And nothing is handed to an owner that has gone: the main queue is not
	/// troubled at all, which is what the guard in the editor is there to say
	/// about a document rather than about the editor itself.
	@Test func nothingIsHandedBackToAnOwnerThatHasGone() async {
		let carryOn = DispatchSemaphore(value: 0)
		let used = Counter()
		var owner: Owner? = Owner("the editor")
		// Serial and shared with the relay, which is what makes the wait below
		// exact rather than a guess about timing.
		let building = queue("gone")

		// The `wait` is inside the build closure and not in this test: a
		// `DispatchSemaphore` may not be waited on from an asynchronous context,
		// so the handshake that says "the build has begun" is a continuation.
		await withCheckedContinuation { (begun: CheckedContinuation<Void, Never>) in
			WeakRelay.build(on: building, for: owner!) {
				begun.resume()
				carryOn.wait()
			} then: { _, _ in used.add() }
		}

		owner = nil
		carryOn.signal()

		// Two hops of our own, each behind one of the relay's, on the two queues
		// it uses. The relay's build is ahead of this block on the serial queue,
		// so whatever it put on the main queue is ahead of what this block puts
		// there — and if `then` were going to run at all, it has run by now.
		await withCheckedContinuation { (behind: CheckedContinuation<Void, Never>) in
			building.async { DispatchQueue.main.async { behind.resume() } }
		}
		#expect(used.count == 0)
	}

	@Test func theOwnerAndTheValueArriveTogetherWhenItIsStillThere() async {
		let owner = Owner("still here")
		let said = await withCheckedContinuation { (waiting: CheckedContinuation<String, Never>) in
			WeakRelay.build(on: queue("alive"), for: owner) { 40 + 2 } then: { owner, value in
				waiting.resume(returning: "\(owner.name) \(value)")
			}
		}
		#expect(said == "still here 42")
		// Nothing below reads it, and the point of the test is that something above
		// did while it was still in scope.
		withExtendedLifetime(owner) {}
	}

	/// The property the editor's serial queue was chosen for. A `didChange`
	/// carries a version number and a whole file, so the older of two arriving
	/// last leaves a language server describing text nobody has — and the order
	/// has to survive *both* hops, not just the queue.
	///
	/// The builds take descending amounts of time on purpose: on a concurrent
	/// queue this order would come back reversed.
	@Test func aSerialQueueKeepsTheOrderThroughBothHops() async {
		let owner = Owner("the editor")
		let arriving = Arrivals()
		let asked = Array(1 ... 10)
		let serial = queue("order")

		await withCheckedContinuation { (waiting: CheckedContinuation<Void, Never>) in
			for number in asked {
				WeakRelay.build(on: serial, for: owner) {
					Thread.sleep(forTimeInterval: Double(11 - number) * 0.002)
					return number
				} then: { _, value in
					arriving.append(value, andWhenFull: asked.count) { waiting.resume() }
				}
			}
		}

		#expect(arriving.seen == asked)
		withExtendedLifetime(owner) {}
	}

	/// Counted on the main queue, which is the only place the relay adds to it.
	private final class Counter: @unchecked Sendable {
		private(set) var count = 0
		func add() { count += 1 }
	}

	/// Likewise: appended to on the main queue and read after the wait.
	private final class Arrivals: @unchecked Sendable {
		private(set) var seen: [Int] = []
		func append(_ value: Int, andWhenFull wanted: Int, _ finished: () -> Void) {
			seen.append(value)
			if seen.count == wanted { finished() }
		}
	}

}
