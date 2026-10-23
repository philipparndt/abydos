import Foundation
import Testing
@testable import AbydosKit

/// Signing in through the system's sheet: where it opens, what comes back,
/// and where the token is kept.
struct VboardSignInTests {
	@Test func theSheetOpensVboardsAppLoginForThisDevice() {
		let url = VboardSignIn.url(server: URL(string: "https://boards.example.org/")!, device: "Abydos on Studio")
		#expect(url.absoluteString == "https://boards.example.org/auth/app-login?device=Abydos%20on%20Studio")
	}

	@Test func theRedirectThatEndsTheSignInCarriesTheToken() {
		let back = URL(string: "vboard://signin?token=vbp_abc&id=t_1&name=Ada%20Lovelace")!
		#expect(VboardSignIn.credential(from: back) == VboardCredential(token: "vbp_abc", id: "t_1", name: "Ada Lovelace"))
	}

	@Test func anotherRedirectIsNotASignIn() {
		#expect(VboardSignIn.credential(from: URL(string: "vboard://connect?server=x&code=y")!) == nil)
		#expect(VboardSignIn.credential(from: URL(string: "https://signin?token=x")!) == nil)
		#expect(VboardSignIn.credential(from: URL(string: "vboard://signin?id=t_1")!) == nil)
	}

	@Test func aCredentialNeverPrintsItsToken() {
		let credential = VboardCredential(token: "vbp_abc", id: "t_1", name: "Ada")
		#expect(!"\(credential)".contains("vbp_abc"))
	}

	@Test func aTokenBelongsToTheServersOriginNotItsPath() {
		let kept = MemoryVboardCredentials()
		let credential = VboardCredential(token: "vbp_abc", id: "t_1", name: "Ada")
		kept.keep(credential, for: URL(string: "https://Boards.example.org/some/path")!)
		#expect(kept.credential(for: URL(string: "https://boards.example.org")!) == credential)
		#expect(kept.credential(for: URL(string: "https://boards.example.org:8443")!) == nil)
		kept.forget(for: URL(string: "https://boards.example.org/")!)
		#expect(kept.credential(for: URL(string: "https://boards.example.org")!) == nil)
	}
}
