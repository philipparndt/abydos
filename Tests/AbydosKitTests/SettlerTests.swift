import Foundation
import Testing
@testable import AbydosKit

/// When a burst of events gets its one run.
///
/// Driven by a clock the test moves by hand, because the claims are about
/// which events run and when — a test that waited for real timers would be a
/// test of how busy the machine was.
@MainActor
struct SettlerTests {
	/// A clock and a queue of scheduled blocks, advanced by the test.
	@MainActor
	final class Time {
		var now = Date(timeIntervalSinceReferenceDate: 0)
		private var scheduled: [(id: Int, at: Date, block: @MainActor () -> Void)] = []
		private var nextID = 0

		func schedule(_ delay: TimeInterval, _ block: @escaping @MainActor () -> Void) -> Settler.Cancel {
			nextID += 1
			let id = nextID
			scheduled.append((id, now.addingTimeInterval(delay), block))
			return { [weak self] in self?.scheduled.removeAll { $0.id == id } }
		}

		/// Moves the clock on, running whatever fell due on the way.
		func advance(by seconds: TimeInterval) {
			let end = now.addingTimeInterval(seconds)
			while let due = scheduled.min(by: { $0.at < $1.at }), due.at <= end {
				scheduled.removeAll { $0.id == due.id }
				now = due.at
				due.block()
			}
			now = end
		}
	}

	private func settler(_ time: Time, fired: @escaping () -> Void) -> Settler {
		Settler(quiet: 0.6, cap: 3, now: { time.now }, schedule: time.schedule, fire: fired)
	}

	/// A single save is the ordinary case, and must not wait at all.
	@Test func theFirstEventAfterAQuietSpellRunsAtOnce() {
		let time = Time()
		var runs = 0
		let settler = settler(time) { runs += 1 }

		settler.poke()
		#expect(runs == 1)
		time.advance(by: 5)
		#expect(runs == 1)
	}

	/// What follows within `quiet` of a run is a burst, and waits for it to end.
	@Test func aShortBurstRunsOnceMoreAfterItEnds() {
		let time = Time()
		var runs: [TimeInterval] = []
		let settler = settler(time) { runs.append(time.now.timeIntervalSinceReferenceDate) }

		settler.poke()
		for _ in 0..<4 {
			time.advance(by: 0.25)
			settler.poke()
		}
		time.advance(by: 5)

		// Once at the start, once 0.6 s after the last event at 1.0 s.
		#expect(runs.count == 2)
		#expect(abs(runs[1] - 1.6) < 0.001)
	}

	/// A burst that never ends still runs every few seconds, not never.
	@Test func aBurstThatGoesOnRunsAtTheCap() {
		let time = Time()
		var runs: [TimeInterval] = []
		let settler = settler(time) { runs.append(time.now.timeIntervalSinceReferenceDate) }

		settler.poke()
		for _ in 0..<40 {
			time.advance(by: 0.25)
			settler.poke()
		}
		time.advance(by: 5)

		// Ten seconds of batches four a second: the leading run, then one per
		// cap — not forty.
		#expect(runs.count >= 4 && runs.count <= 6)
		for (earlier, later) in zip(runs, runs.dropFirst()) {
			#expect(later - earlier <= 3.25 + 0.001)
		}
	}

	@Test func cancellingForgetsWhatWasWaiting() {
		let time = Time()
		var runs = 0
		let settler = settler(time) { runs += 1 }

		settler.poke()
		time.advance(by: 0.1)
		settler.poke()
		#expect(settler.isWaiting)
		settler.cancel()
		time.advance(by: 5)
		#expect(runs == 1)
		#expect(!settler.isWaiting)
	}
}
