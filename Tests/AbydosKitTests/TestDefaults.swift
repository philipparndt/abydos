import Foundation

/// Preferences that live in memory and nowhere else.
///
/// Tests used to take a `UserDefaults(suiteName:)` of their own and remove the
/// domain again afterwards. That empties the suite but does not delete the
/// file, and `cfprefsd` writes it back when the process exits whatever the test
/// does — which is how this machine came to hold three and a half thousand
/// empty plists in `~/Library/Preferences`, one for every test that had ever
/// run.
///
/// `UserDefaults` reads and writes everything through `object(forKey:)`, so a
/// subclass that keeps a dictionary is a real one as far as the code under test
/// is concerned, and it goes away when the test does.
final class TestDefaults: UserDefaults {
	private var values: [String: Any] = [:]
	private var registered: [String: Any] = [:]

	/// A fresh set, as a test would find on a machine nothing has run on.
	static func make() -> UserDefaults { TestDefaults(suiteName: nil)! }

	/// Runs the body against a set of its own.
	static func with<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
		try body(make())
	}

	override func object(forKey key: String) -> Any? {
		values[key] ?? registered[key]
	}

	override func set(_ value: Any?, forKey key: String) {
		guard let value else {
			values.removeValue(forKey: key)
			return
		}
		values[key] = value
	}

	override func removeObject(forKey key: String) {
		values.removeValue(forKey: key)
	}

	override func register(defaults: [String: Any]) {
		registered.merge(defaults) { _, new in new }
	}

	override func dictionaryRepresentation() -> [String: Any] {
		registered.merging(values) { _, mine in mine }
	}

	// The typed accessors, spelled out rather than inherited: `UserDefaults`
	// answers them from its own storage, which this subclass does not use.

	override func string(forKey key: String) -> String? { object(forKey: key) as? String }
	override func bool(forKey key: String) -> Bool { number(key)?.boolValue ?? false }
	override func integer(forKey key: String) -> Int { number(key)?.intValue ?? 0 }
	override func double(forKey key: String) -> Double { number(key)?.doubleValue ?? 0 }
	override func float(forKey key: String) -> Float { number(key)?.floatValue ?? 0 }
	override func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
	override func array(forKey key: String) -> [Any]? { object(forKey: key) as? [Any] }
	override func stringArray(forKey key: String) -> [String]? { object(forKey: key) as? [String] }
	override func dictionary(forKey key: String) -> [String: Any]? {
		object(forKey: key) as? [String: Any]
	}

	override func set(_ value: Bool, forKey key: String) { set(value as Any, forKey: key) }
	override func set(_ value: Int, forKey key: String) { set(value as Any, forKey: key) }
	override func set(_ value: Double, forKey key: String) { set(value as Any, forKey: key) }
	override func set(_ value: Float, forKey key: String) { set(value as Any, forKey: key) }

	/// Numbers written as `Bool` and read back as `Int` — and the other way
	/// round — which is what the real one does.
	private func number(_ key: String) -> NSNumber? {
		switch object(forKey: key) {
		case let number as NSNumber: return number
		case let bool as Bool: return NSNumber(value: bool)
		case let string as NSString: return NSNumber(value: string.doubleValue)
		default: return nil
		}
	}
}
