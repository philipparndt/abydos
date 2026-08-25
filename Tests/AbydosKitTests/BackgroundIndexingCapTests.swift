import Foundation
import Testing
@testable import AbydosKit

/// The cap the app puts on sourcekit-lsp's background indexing.
///
/// It is written into `~/.sourcekit-lsp/config.json`, which is a file the app
/// does not own: other editors read it and a person may have written it
/// themselves. So every claim here is about what it does *not* touch — the one
/// kind of fault that would otherwise be found by somebody losing settings they
/// had put there on purpose.
struct BackgroundIndexingCapTests {
	private func object(_ data: Data) throws -> [String: Any] {
		let parsed = try JSONSerialization.jsonObject(with: data)
		return try #require(parsed as? [String: Any])
	}

	@Test func noFileYetIsWrittenWithNothingButTheCap() throws {
		let written = try #require(LanguageServers.cappedConfiguration(from: nil))
		let index = try #require(try object(written)["index"] as? [String: Any])
		#expect(
			index["maxCoresPercentageToUseForBackgroundIndexing"] as? Double
				== LanguageServers.backgroundIndexingCoreShare
		)
	}

	/// The value is theirs, whatever it is. A person who has decided their
	/// indexing may have the machine has said so, and this is not a better idea
	/// than what they said.
	@Test func aValueSomebodySetIsNotOverwritten() throws {
		let existing = Data(#"{"index":{"maxCoresPercentageToUseForBackgroundIndexing":1}}"#.utf8)
		#expect(LanguageServers.cappedConfiguration(from: existing) == nil)
	}

	/// Including one that is lower than ours, which is the case a "clamp to at
	/// most a quarter" would get wrong.
	@Test func aLowerValueSomebodySetIsAlsoLeftAlone() throws {
		let existing = Data(#"{"index":{"maxCoresPercentageToUseForBackgroundIndexing":0.1}}"#.utf8)
		#expect(LanguageServers.cappedConfiguration(from: existing) == nil)
	}

	/// The rest of the file survives — both the keys beside `index` and the ones
	/// inside it. This is the fault that would cost somebody their settings.
	@Test func everythingElseInTheFileIsWrittenBackUntouched() throws {
		let existing = Data("""
		{
		  "backgroundIndexing": true,
		  "swiftPM": { "configuration": "release" },
		  "index": { "indexStorePath": "/somewhere/index" }
		}
		""".utf8)
		let written = try #require(LanguageServers.cappedConfiguration(from: existing))
		let parsed = try object(written)

		#expect(parsed["backgroundIndexing"] as? Bool == true)
		#expect((parsed["swiftPM"] as? [String: Any])?["configuration"] as? String == "release")

		let index = try #require(parsed["index"] as? [String: Any])
		#expect(index["indexStorePath"] as? String == "/somewhere/index")
		#expect(
			index["maxCoresPercentageToUseForBackgroundIndexing"] as? Double
				== LanguageServers.backgroundIndexingCoreShare
		)
	}

	/// A file that does not parse is somebody's, and rewriting it as ours would
	/// take away the only copy of whatever they meant.
	@Test func aFileThatDoesNotParseIsLeftExactlyAsItIs() throws {
		let existing = Data("{ this is not json".utf8)
		#expect(LanguageServers.cappedConfiguration(from: existing) == nil)
	}

	/// JSON, but not an object — `[]`, or a bare string. Same rule.
	@Test func aFileThatIsJsonButNotAnObjectIsLeftAlone() throws {
		#expect(LanguageServers.cappedConfiguration(from: Data("[]".utf8)) == nil)
	}

	/// An empty file is not a configuration anybody wrote, but it is also not
	/// JSON — so it falls under the rule above rather than being replaced.
	@Test func anEmptyFileIsLeftAlone() throws {
		#expect(LanguageServers.cappedConfiguration(from: Data()) == nil)
	}
}
