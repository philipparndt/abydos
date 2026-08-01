import Foundation
import Testing
@testable import IdeaiKit

/// Saying where a program's pprof handlers are.
struct PprofEndpointTests {
	@Test func acceptsJustAPort() {
		let endpoint = PprofEndpoint(text: "6060")
		#expect(endpoint?.base.absoluteString == "http://localhost:6060/debug/pprof")
		#expect(endpoint?.displayName == "localhost:6060")
	}

	@Test func acceptsAHostAndPort() {
		#expect(PprofEndpoint(text: "10.0.0.4:8080")?.base.absoluteString
			== "http://10.0.0.4:8080/debug/pprof")
	}

	/// A URL that already names the handlers is taken as it is, including one
	/// mounted somewhere other than the default.
	@Test func keepsAPathThatAlreadyNamesTheHandlers() {
		#expect(PprofEndpoint(text: "http://box:6060/debug/pprof")?.base.absoluteString
			== "http://box:6060/debug/pprof")
		#expect(PprofEndpoint(text: "http://box:6060/admin/debug/pprof/")?.base.absoluteString
			== "http://box:6060/admin/debug/pprof")
	}

	@Test func rejectsWhatIsNotAnAddress() {
		#expect(PprofEndpoint(text: "") == nil)
		#expect(PprofEndpoint(text: "   ") == nil)
		#expect(PprofEndpoint(text: "99999") != nil) // a host named 99999 is legal
	}

	/// A CPU profile is collected over a window, and asks for it by name.
	@Test func buildsProfileURLs() {
		let endpoint = try! #require(PprofEndpoint(text: "6060"))
		#expect(endpoint.url(for: "heap").absoluteString
			== "http://localhost:6060/debug/pprof/heap?debug=0")
		#expect(endpoint.url(for: "profile", seconds: 30).absoluteString
			== "http://localhost:6060/debug/pprof/profile?debug=0&seconds=30")
	}

	/// The index page is the list of what this program actually registered,
	/// which is not always all of them and is sometimes more.
	@Test func readsTheIndexPage() {
		let html = """
		<html><body>
		<table>
		<tr><td><a href="allocs?debug=1">allocs</a></td></tr>
		<tr><td><a href="goroutine?debug=1">goroutine</a></td></tr>
		<tr><td><a href="heap?debug=1">heap</a></td></tr>
		<tr><td><a href="ourown?debug=1">ourown</a></td></tr>
		</table>
		<a href="cmdline">cmdline</a>
		<a href="profile">profile</a>
		<a href="trace?seconds=5">trace</a>
		</body></html>
		"""
		let kinds = PprofEndpoint.kinds(inIndexPage: html)
		#expect(kinds.map(\.name) == ["allocs", "goroutine", "heap", "ourown", "profile"])

		// Ours has no description to give; the standard ones do.
		#expect(kinds.first { $0.name == "heap" }?.summary == "What is holding memory now")
		#expect(kinds.first { $0.name == "ourown" }?.summary == "Registered by the program")
		#expect(kinds.first { $0.name == "profile" }?.isTimed == true)
	}

	@Test func findsNothingInAPageThatIsNotTheIndex() {
		#expect(PprofEndpoint.kinds(inIndexPage: "<html>404 page not found</html>").isEmpty)
	}
}
