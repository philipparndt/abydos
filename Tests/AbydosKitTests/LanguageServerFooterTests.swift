import Foundation
import Testing
@testable import AbydosKit

/// What the editor's footer says about the server answering for a file.
///
/// The bar itself is in the app target and this suite cannot reach it, which is
/// why the words are a value in the engine rather than strings built where the
/// chip is drawn. What is claimed here is the half that can be: the sentence for
/// each state, and that the three origins are three different answers rather
/// than one word with a mark on it.
struct LanguageServerFooterTests {
	/// The `⬢` the titlebar pill and the terminal tab in a container wear. The
	/// app owns the glyph — `MainWindowController.containerMark` — and hands it
	/// in, so this is the same character the chip really draws.
	private let mark = "⬢"

	private func footer(
		_ origin: LanguageServerFooter.Origin,
		state: LanguageServerFooter.State = .answering,
		command: String = "rust-analyzer",
		language: String = "Rust"
	) -> LanguageServerFooter {
		LanguageServerFooter(
			command: command, languageName: language, origin: origin, state: state
		)
	}

	@Test func anInstalledServerIsNamedAndNothingElse() {
		let installed = footer(.installed(executable: "/opt/homebrew/bin/rust-analyzer"))
		#expect(installed.text(containerMark: mark) == "rust-analyzer")
		// The path is in the tool tip and not on the chip: it is 0427's question
		// — which toolchain is really answering — and it is a hundred characters
		// in a bar that has room for twenty.
		#expect(installed.detail.contains("/opt/homebrew/bin/rust-analyzer"))
	}

	/// The whole of why this exists. A Rust project was pointed at an image, the
	/// container started and the server answered, and nothing on screen was any
	/// different from nothing having happened.
	@Test func aServerFromAnImageSaysWhichImage() {
		let image = footer(.image("abydos-rust-analyzer:2f1c9d"))
		#expect(image.text(containerMark: mark) == "rust-analyzer ⬢ abydos-rust-analyzer:2f1c9d")
		#expect(image.detail.contains("abydos-rust-analyzer:2f1c9d"))
	}

	/// A devcontainer is a fact about the window, and the titlebar's pill already
	/// carries it and names it. Repeating the name on every file would be the
	/// same word over and over in the one place that has no room for it, so the
	/// chip wears the mark and the tool tip does the naming.
	@Test func aServerInTheProjectsDevcontainerWearsTheMarkWithoutTheName() {
		let inside = footer(.devcontainer(name: "abydos-examples-rust"))
		#expect(inside.text(containerMark: mark) == "rust-analyzer ⬢")
		#expect(inside.detail.contains("abydos-examples-rust"))
	}

	/// Three ways of being on the way, and they are three because 0459 found that
	/// two are not enough: somebody told their server is being *downloaded* while
	/// a compiler runs for three minutes concludes their network is broken.
	@Test func eachKindOfWaitHasItsOwnWord() {
		#expect(footer(.image("x"), state: .fetching).text(containerMark: mark)
			== "rust-analyzer — fetching")
		#expect(footer(.image("x"), state: .building).text(containerMark: mark)
			== "rust-analyzer — building")
		#expect(footer(.devcontainer(name: nil), state: .starting).text(containerMark: mark)
			== "rust-analyzer — starting")
	}

	/// The chip's tool tip and the strip above the file say the same thing while
	/// a server is on its way, because they say it out of the same function.
	/// Two copies of a sentence agreeing by eye is how they come to disagree.
	@Test func theChipAndTheStripSayTheSameThingAboutAWait() {
		for state in [LanguageServerFooter.State.fetching, .building, .starting] {
			let said = LanguageServerFooter.arrivalSentence(languageName: "Rust", state: state)
			#expect(!said.isEmpty)
			#expect(footer(.image("x"), state: state).detail.hasPrefix(said))
		}
	}

	/// A control that does not say what pressing it does is a control nobody
	/// presses.
	@Test func theToolTipSaysWhereTheClickGoes() {
		#expect(footer(.installed(executable: nil)).detail.contains("Click"))
	}

	/// The name comes first in every state, because the chip is the thing that
	/// truncates when the editor is narrow and the name is the part somebody is
	/// looking for.
	@Test func theServersNameIsAlwaysFirst() {
		let origins: [LanguageServerFooter.Origin] = [
			.installed(executable: "/usr/bin/gopls"), .image("go:1"), .devcontainer(name: "dev"),
		]
		let states: [LanguageServerFooter.State] = [.answering, .fetching, .building, .starting]
		for origin in origins {
			for state in states {
				let said = footer(origin, state: state, command: "gopls", language: "Go")
				#expect(said.text(containerMark: mark).hasPrefix("gopls"))
			}
		}
	}

	/// Where a server comes from is read off the launch that started it, once,
	/// rather than worked out again whenever somebody wants to know.
	@Test func aLaunchSaysWhereItsServerCameFrom() {
		let installed = LanguageServerLaunch.installed(
			executable: "/opt/homebrew/bin/gopls", arguments: []
		)
		#expect(installed.origin == .installed(executable: "/opt/homebrew/bin/gopls"))

		let image = LanguageServerLaunch.image(
			container: ToolContainer(image: "golang/gopls:latest", name: "abydos-lsp-gopls"),
			runtime: .docker("/usr/bin/docker"),
			paths: ContainerPaths(host: "/Users/x/go", container: "/workspace")
		)
		#expect(image.origin == .image("golang/gopls:latest"))
	}
}
