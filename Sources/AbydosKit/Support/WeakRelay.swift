import Foundation

/// Building something expensive off the main queue for an owner that may not be
/// there when it is finished.
///
/// Two hops: build on a queue of your own, use the result on the main one. The
/// trap is in the first hop, and it was written the obvious way here:
///
///     queue.async {
///         let text = decode(snapshot)
///         DispatchQueue.main.async { [weak self] in … }
///     }
///
/// That `[weak self]` buys nothing at all. The outer closure has to capture
/// `self` strongly to build the inner one, so the owner is held alive for the
/// whole of the build whatever the inner capture says — and the compiler says
/// so: *'weak' ownership of capture 'self' differs from implicitly-captured
/// strong reference in outer scope*. It is a delay rather than a leak, since the
/// owner does go once the build finishes, but a view controller freed a megabyte
/// of decoding after its window closed is one that outlived the window.
///
/// So: weak at both hops and strong nowhere in between. No strong reference to
/// the owner is made on the building queue at all, which is worth more than
/// tidiness — the last release of a view controller would otherwise happen on
/// whatever thread that queue is using, and AppKit deallocates on the main
/// thread for a living.
///
/// **The order values arrive in is the order they were asked for**, given a
/// serial queue. Both hops keep it: a serial queue runs the builds in the order
/// they were submitted, and each hands to the main queue as it finishes, so the
/// main queue receives them in that same order. That is not a nicety for the
/// caller this was written for — a language server's `didChange` carries a
/// version number and a whole file, and the older of two arriving last leaves
/// the server describing text that nobody has.
public enum WeakRelay {
	/// - Parameters:
	///   - queue: where the value is built. Serial, if the order matters.
	///   - owner: held weakly, and never strongly. Gone by the time the value is
	///     built means `use` is not called and the main queue is not troubled.
	///   - make: the expensive part, on `queue`.
	///   - use: the owner and the value, on the main queue.
	public static func build<Owner: AnyObject, Value>(
		on queue: DispatchQueue,
		for owner: Owner,
		_ make: @escaping () -> Value,
		then use: @escaping (Owner, Value) -> Void
	) {
		let waiting = Waiting(owner)
		let work = Work(make: make, use: use)
		queue.async {
			let value = work.make()
			DispatchQueue.main.async {
				guard let owner = waiting.owner else { return }
				work.use(owner, value)
			}
		}
	}

	/// The weak reference, in a box.
	///
	/// A box rather than a `weak var` local because a `var` cannot be captured by
	/// a concurrently-executing closure, and this one has to be read on the main
	/// queue after being written on the caller's. `@unchecked` because that is
	/// the whole of the sharing: the reference is written once, before the queue
	/// is touched, and read afterwards — and a weak read is atomic in any case,
	/// which is what makes it safe for ARC to be zeroing it at the same moment.
	private final class Waiting<Owner: AnyObject>: @unchecked Sendable {
		weak var owner: Owner?
		init(_ owner: Owner) { self.owner = owner }
	}

	/// The two closures, likewise boxed.
	///
	/// They are the caller's, so they capture the caller's things — a document, a
	/// rope, a completion — and none of that is `Sendable`. Which queue each one
	/// runs on is stated above and enforced by this file being the only thing
	/// that calls them: `make` on `queue`, `use` on the main queue, never both at
	/// once and never twice.
	private final class Work<Owner: AnyObject, Value>: @unchecked Sendable {
		let make: () -> Value
		let use: (Owner, Value) -> Void
		init(make: @escaping () -> Value, use: @escaping (Owner, Value) -> Void) {
			self.make = make
			self.use = use
		}
	}
}
