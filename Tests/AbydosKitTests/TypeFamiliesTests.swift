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
}
