import Foundation

/// Runs something once a burst of events has gone quiet — but not later than a
/// cap, so a ten-minute build still gets an answer every few seconds.
///
/// **The first event after a quiet spell runs at once.** A single saved file is
/// the ordinary case, and settling it would make every save show up in the
/// changes pane `quiet` seconds later than it used to. Only what follows within
/// `quiet` of a run waits: those are the events that are a burst.
///
/// Waiting is from the last event, so a burst runs once after it ends; the cap
/// is from the first event that had to wait, so a burst that never ends still
/// runs every `cap` seconds rather than never.
///
/// The clock and the scheduling are given rather than read, because what is
/// worth testing is which events run and when, and a test that waited for real
/// timers would be a test about the machine's load.
@MainActor
public final class Settler {
	/// Cancels a scheduled run.
	public typealias Cancel = () -> Void
	/// Runs the block after the delay, and hands back how to cancel it.
	public typealias Schedule = (TimeInterval, @escaping @MainActor () -> Void) -> Cancel

	private let quiet: TimeInterval
	private let cap: TimeInterval
	private let now: () -> Date
	private let schedule: Schedule
	private let fire: () -> Void

	private var lastFire: Date?
	private var firstWaiting: Date?
	private var cancelScheduled: Cancel?

	/// - Parameters:
	///   - quiet: how long without an event before a burst counts as over.
	///   - cap: how long an event may wait at most, however long the burst goes on.
	public init(
		quiet: TimeInterval = 0.6,
		cap: TimeInterval = 3,
		now: @escaping () -> Date = Date.init,
		schedule: @escaping Schedule = Settler.onMainQueue,
		fire: @escaping () -> Void
	) {
		self.quiet = quiet
		self.cap = cap
		self.now = now
		self.schedule = schedule
		self.fire = fire
	}

	/// Whether a run is scheduled and has not happened yet.
	public var isWaiting: Bool { firstWaiting != nil }

	/// Says an event happened.
	public func poke() {
		let time = now()
		if firstWaiting == nil, lastFire.map({ time.timeIntervalSince($0) >= quiet }) ?? true {
			run(at: time)
			return
		}

		let first = firstWaiting ?? time
		firstWaiting = first
		cancelScheduled?()
		let due = min(time.addingTimeInterval(quiet), first.addingTimeInterval(cap))
		cancelScheduled = schedule(max(0, due.timeIntervalSince(time))) { [weak self] in
			guard let self else { return }
			self.run(at: self.now())
		}
	}

	/// Forgets anything waiting: the window closed, or the project changed.
	public func cancel() {
		cancelScheduled?()
		cancelScheduled = nil
		firstWaiting = nil
	}

	private func run(at time: Date) {
		cancelScheduled = nil
		firstWaiting = nil
		lastFire = time
		fire()
	}

	/// The real thing: a work item on the main queue.
	public nonisolated static func onMainQueue(
		_ delay: TimeInterval, _ block: @escaping @MainActor () -> Void
	) -> Cancel {
		let item = DispatchWorkItem { MainActor.assumeIsolated { block() } }
		DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
		return { item.cancel() }
	}
}
