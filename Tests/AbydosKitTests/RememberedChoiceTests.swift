import Foundation
import Testing
@testable import AbydosKit

/// Where a "do not ask again" answer is filed.
struct RememberedChoiceTests {
	/// The failure this is keyed to prevent: an answer given while looking at
	/// one submodule becoming a decision about two hundred.
	@Test func anAnswerGivenForOneRepositoryIsNotAnAnswerForAnother() {
		let defaults = TestDefaults.make()
		let one = URL(fileURLWithPath: "/tmp/super/svc-3")
		let other = URL(fileURLWithPath: "/tmp/super/svc-47")

		RememberedChoice.remember(operation: "switch", in: one, writing: defaults)

		#expect(RememberedChoice.isRemembered(operation: "switch", in: one, reading: defaults))
		#expect(!RememberedChoice.isRemembered(operation: "switch", in: other, reading: defaults))
	}

	/// Two submodules can be called the same thing in different parts of an
	/// estate, so the path is the key and the name is not.
	@Test func twoRepositoriesWithTheSameNameAreDifferentRepositories() {
		let defaults = TestDefaults.make()
		let one = URL(fileURLWithPath: "/tmp/super/platform/common")
		let other = URL(fileURLWithPath: "/tmp/super/billing/common")

		RememberedChoice.remember(operation: "switch", in: one, writing: defaults)
		#expect(!RememberedChoice.isRemembered(operation: "switch", in: other, reading: defaults))
	}

	@Test func anAnswerAboutOneOperationIsNotAnAnswerAboutAnother() {
		let defaults = TestDefaults.make()
		let root = URL(fileURLWithPath: "/tmp/super")

		RememberedChoice.remember(operation: "switch", in: root, writing: defaults)
		#expect(!RememberedChoice.isRemembered(operation: "discard", in: root, reading: defaults))
	}

	@Test func nothingIsRememberedUntilItIs() {
		let defaults = TestDefaults.make()
		#expect(!RememberedChoice.isRemembered(
			operation: "switch", in: URL(fileURLWithPath: "/tmp/super"), reading: defaults
		))
	}

	@Test func anAnswerCanBeTakenBack() {
		let defaults = TestDefaults.make()
		let root = URL(fileURLWithPath: "/tmp/super")
		RememberedChoice.remember(operation: "switch", in: root, writing: defaults)
		RememberedChoice.forget(operation: "switch", in: root, writing: defaults)
		#expect(!RememberedChoice.isRemembered(operation: "switch", in: root, reading: defaults))
	}

	/// The same directory spelled two ways is one repository.
	@Test func theSpellingOfAPathDoesNotChangeWhichRepositoryItIs() {
		let defaults = TestDefaults.make()
		RememberedChoice.remember(
			operation: "switch", in: URL(fileURLWithPath: "/tmp/super/svc-3"), writing: defaults
		)
		#expect(RememberedChoice.isRemembered(
			operation: "switch",
			in: URL(fileURLWithPath: "/tmp/super/./svc-3"),
			reading: defaults
		))
	}
}
