import Foundation

/// A run the app was driven through from outside, rather than used.
///
/// The window layer has no test target, so the app's launch-option verbs — 191
/// of them — are the only way anything there is proved at all, and they are run
/// dozens of times a day. Every one of them used to run against the real thing:
/// the preferences somebody had chosen, the projects they were working in, the
/// session they had left open. Item 0522 is what that cost in one evening — a
/// preference destroyed, a line of `C-ircle` typed into a source file nobody
/// was editing, and characters that arrived in somebody's shell history.
///
/// So a driven run is *told apart from a used one*, automatically, and then
/// kept away from anything that belongs to whoever is at the keyboard. What
/// isolation actually means is in the two places that read this: `Settings`,
/// which sends its writes to a throwaway domain, and `SessionStore`, which
/// neither restores what a project had open nor writes what this run left in
/// it.
///
/// ## Automatic, not asked for
///
/// A flag that has to be remembered will be forgotten, and the proof of that is
/// already in the repository: `Scripts/bundle.sh` has said for months that "an
/// agent building a copy to drive should use" `BUNDLE_ID=` to get a throwaway
/// preferences domain, and all three of the incidents above happened anyway. So
/// the question is not asked. A run is driven when it was given any `--verb` at
/// all beyond the two that only say what to open.
///
/// The rule is stated as "everything except these two" rather than as a list of
/// verbs, which is the only version of it that stays true: a verb written
/// tomorrow is isolated on the day it is written, without its author having to
/// find this file. And it is safe in the direction it can be wrong — the
/// predicate only ever *adds* isolation, so being too eager costs a driven run
/// the ability to write somebody's preferences, which is the entire point.
///
/// Nothing a person types can trip it. `Scripts/abydos`, which is the command
/// line people actually use, sends paths and never a flag; a launch from the
/// Dock or through LaunchServices sends none either; and the single-dash
/// arguments the system adds — `-psn_…`, `-NSDocumentRevisionsDebugMode` — are
/// not `--` and are not counted.
public enum DrivenRun {
	/// The flags that only say what to open, and so are not driving anything.
	///
	/// Both have an exact equivalent a person can type — `abydos <dir>` and
	/// `abydos <file>` — which is what makes them ordinary. Everything else in
	/// `LaunchOptions` exists to make the app do something on its own.
	public static let openingFlags: Set<String> = ["--open", "--file"]

	/// Whether these arguments drive the app rather than merely open something.
	///
	/// A value that happens to look like a flag cannot cause a false negative,
	/// only a false positive — `--file --wat` is a nonsense path, and reading it
	/// as driving is the safe way to be wrong about it.
	public static func isDriven(arguments: [String]) -> Bool {
		arguments.dropFirst().contains { $0.hasPrefix("--") && !openingFlags.contains($0) }
	}

	/// Whether *this* process is one. False until `begin` says otherwise.
	///
	/// Read rather than recomputed, so that the answer cannot differ between two
	/// places in the same run, and so that the test suite and the two
	/// command-line tools — which link this library and are given flags of their
	/// own — are never mistaken for a driven app.
	public private(set) static var isActive = false

	/// Where preferences go. The real domain until a driven run says otherwise.
	public private(set) static var defaults: UserDefaults = .standard

	/// Decides, once, whether this process is driving the app.
	///
	/// Called as the first statement of `main`, before anything can touch
	/// `Settings.shared` — which is a `static let` and therefore built on first
	/// use, so the order is what decides which domain it gets.
	public static func begin(arguments: [String] = CommandLine.arguments) {
		guard isDriven(arguments: arguments) else { return }
		isActive = true

		// Seeded from the user's own domain rather than started empty. The line
		// 0522 draws is *writing* and not reading: a driven run is meant to be a
		// run of the app somebody actually has, and one that began at factory
		// settings would be photographing a program nobody uses.
		let identifier = Bundle.main.bundleIdentifier
		let real = identifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
		defaults = VolatileDefaults(copying: real)
	}

	/// Puts it back, for a test that has just pretended to be a driven run.
	public static func endForTesting() {
		isActive = false
		defaults = .standard
	}
}

/// A `UserDefaults` that keeps everything in memory and writes nothing.
///
/// `UserDefaults(suiteName:)` is not this, and the difference is the whole
/// reason this class exists. A suite is *added to* the standard search list
/// rather than replacing it, and the app's own domain — the user's real
/// preferences — is still in front of it. A driven run built that way would
/// write `appearance` into the suite, read it back from the user's domain, and
/// so both fail to change the setting it was asked to change and go on
/// answering with the real one.
///
/// `NSUserDefaults` names `object(forKey:)`, `set(_:forKey:)`,
/// `removeObject(forKey:)`, `dictionaryRepresentation()` and the domain methods
/// as the ones a subclass overrides. The typed accessors are built on those, but
/// they are overridden here as well rather than trusted to be: a `double` that
/// quietly reached the real store would be a silent hole in exactly the thing
/// this is for, and there is no version of that failure anybody would notice.
public final class VolatileDefaults: UserDefaults {
	/// What has been set, or seeded.
	private var stored: [String: Any]
	/// What `register(defaults:)` was told, which is only ever a fallback.
	private var registered: [String: Any] = [:]

	/// `suiteName: nil` is `NSUserDefaults`'s designated initializer and means
	/// "the ordinary search list" — which this then overrides its way out of,
	/// every method of it. Force-unwrapped because the only documented failure
	/// is a suite name that is the app's own identifier, and this passes none.
	public init(copying seed: [String: Any]) {
		stored = seed
		super.init(suiteName: nil)!
	}

	// MARK: - The primitives

	public override func object(forKey key: String) -> Any? {
		stored[key] ?? registered[key]
	}

	public override func set(_ value: Any?, forKey key: String) {
		if let value {
			stored[key] = value
		} else {
			stored.removeValue(forKey: key)
		}
	}

	public override func removeObject(forKey key: String) {
		stored.removeValue(forKey: key)
	}

	public override func register(defaults: [String: Any]) {
		registered.merge(defaults) { _, new in new }
	}

	public override func dictionaryRepresentation() -> [String: Any] {
		registered.merging(stored) { _, new in new }
	}

	/// Nothing to write, so nothing to wait for.
	public override func synchronize() -> Bool { true }

	// MARK: - Domains

	/// Reading another domain is reading, which is allowed: `Settings.migrate`
	/// asks what the app's previous identifier still holds.
	public override func persistentDomain(forName name: String) -> [String: Any]? {
		UserDefaults.standard.persistentDomain(forName: name)
	}

	/// Writing one is not. Both of these are how a driven run would reach the
	/// real preferences without ever calling `set`.
	public override func setPersistentDomain(_ domain: [String: Any], forName name: String) {}
	public override func removePersistentDomain(forName name: String) {}

	// MARK: - The typed accessors

	public override func string(forKey key: String) -> String? {
		switch object(forKey: key) {
		case let text as String: return text
		case let number as NSNumber: return number.stringValue
		default: return nil
		}
	}

	public override func array(forKey key: String) -> [Any]? { object(forKey: key) as? [Any] }

	public override func stringArray(forKey key: String) -> [String]? {
		object(forKey: key) as? [String]
	}

	public override func dictionary(forKey key: String) -> [String: Any]? {
		object(forKey: key) as? [String: Any]
	}

	public override func data(forKey key: String) -> Data? { object(forKey: key) as? Data }

	public override func url(forKey key: String) -> URL? {
		switch object(forKey: key) {
		case let url as URL: return url
		case let path as String: return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
		default: return nil
		}
	}

	/// A missing number is zero and a missing flag is false, which is what the
	/// real one answers and what every caller here is written against.
	private func number(forKey key: String) -> NSNumber? {
		switch object(forKey: key) {
		case let number as NSNumber: return number
		case let text as String: return NSNumber(value: (text as NSString).doubleValue)
		default: return nil
		}
	}

	public override func bool(forKey key: String) -> Bool {
		if let text = object(forKey: key) as? String { return (text as NSString).boolValue }
		return number(forKey: key)?.boolValue ?? false
	}

	public override func integer(forKey key: String) -> Int { number(forKey: key)?.intValue ?? 0 }
	public override func double(forKey key: String) -> Double { number(forKey: key)?.doubleValue ?? 0 }
	public override func float(forKey key: String) -> Float { number(forKey: key)?.floatValue ?? 0 }

	// MARK: - The typed setters

	// Each of these is a separate Objective-C method rather than sugar over
	// `setObject:forKey:`, so each is a separate way out to the real store.

	public override func set(_ value: Bool, forKey key: String) { set(value as Any, forKey: key) }
	public override func set(_ value: Int, forKey key: String) { set(value as Any, forKey: key) }
	public override func set(_ value: Double, forKey key: String) { set(value as Any, forKey: key) }
	public override func set(_ value: Float, forKey key: String) { set(value as Any, forKey: key) }
	public override func set(_ url: URL?, forKey key: String) { set(url as Any?, forKey: key) }
}
