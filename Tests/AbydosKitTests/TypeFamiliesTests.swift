import Foundation
import Testing
import UniformTypeIdentifiers
@testable import AbydosKit

/// The roots of the kinds the bundle declares, which is how many times the
/// system asks before the rest are looked at.
struct TypeFamiliesTests {
	@Test func theRootsAreTheTypesNothingElseInTheListStandsFor() {
		let types = [UTType.plainText, .sourceCode, .shellScript, .json, .pythonScript]
		#expect(TypeFamilies.roots(of: types) == [.plainText, .json])
	}

	@Test func withTextDeclaredTheBundlesKindsHaveOneRoot() {
		let identifiers = [
			"public.text", "public.plain-text", "public.source-code", "public.script", "public.shell-script",
			"public.json", "public.xml", "public.yaml", "public.toml", "public.css", "public.html",
			"net.daringfireball.markdown", "com.microsoft.typescript", "public.make-source",
		]
		let types = identifiers.compactMap(UTType.init)
		#expect(types.count == identifiers.count)
		#expect(TypeFamilies.roots(of: types).map(\.identifier) == ["public.text"])
	}

	/// **The one claim that is somebody else's role.** Taking the handler for
	/// `public.html` is how macOS is told which application is the default
	/// browser, and the `http` and `https` schemes follow it — so an editor
	/// that took it received every link on the machine and dropped them, since
	/// it declares no URL scheme and does nothing with one. It happened.
	///
	/// The root pass never reached it, because `public.html` conforms to
	/// `public.text` and only the root is claimed there. The second pass
	/// claimed it by name, which is the pass this excludes it from.
	@Test func htmlIsDeclaredButNeverClaimed() {
		#expect(TypeFamilies.belongToAnotherKindOfApp.contains("public.html"))

		let declared = ["public.text", "public.source-code", "public.html", "public.json"]
			.compactMap(UTType.init)
		let claimable = TypeFamilies.claimable(declared).map(\.identifier)
		#expect(!claimable.contains("public.html"))
		// And nothing else is taken away: the rest of the list is untouched.
		#expect(claimable == ["public.text", "public.source-code", "public.json"])
	}

	/// The exclusion has to survive the *second* pass, which is the one that
	/// asks by name for whatever the roots did not carry — and that is where
	/// HTML was taken.
	@Test func theSecondPassWouldHaveAskedForHtmlByName() {
		let declared = ["public.text", "public.html"].compactMap(UTType.init)
		// Both passes, as `makeDefault` runs them, over the claimable list.
		let claimable = TypeFamilies.claimable(declared)
		let roots = TypeFamilies.roots(of: claimable).map(\.identifier)
		#expect(roots == ["public.text"])
		#expect(!claimable.map(\.identifier).contains("public.html"))

		// Without the filter the root pass still misses it and the by-name
		// pass finds it, which is exactly how it was taken.
		#expect(TypeFamilies.roots(of: declared).map(\.identifier) == ["public.text"])
		#expect(declared.map(\.identifier).contains("public.html"))
	}
}
