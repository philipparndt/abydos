import Foundation
import Testing
@testable import AbydosKit

/// Which way round a diagram is drawn, and — the half that matters more —
/// whether the file has already said.
///
/// 0429's ruling is that the file wins and the app's theme is the default, so
/// "does this file state a theme?" is the question everything else hangs off.
/// It is a question about a *language*, so there are three answers here rather
/// than one, and each is tested against the way people actually write that
/// language.
struct DiagramThemeTests {
	// MARK: - PlantUML

	/// `!theme` is the plain case, and the phrase comes back so the pane can
	/// quote it at somebody rather than saying "this file has a theme".
	@Test func plantUMLNoticesItsOwnTheme() {
		let source = """
		@startuml
		!theme reddress-darkblue
		Alice -> Bob: hello
		@enduml
		"""
		#expect(PlantUML.statedLook(in: source) == "!theme reddress-darkblue")
	}

	/// A diagram that sets only a background colour has still chosen — 0429 says
	/// so outright, and it is the case somebody would most easily leave out.
	@Test func plantUMLNoticesABackgroundColourOnItsOwn() {
		let plain = """
		@startuml
		skinparam backgroundColor #1E1E1E
		Alice -> Bob: hello
		@enduml
		"""
		#expect(PlantUML.statedLook(in: plain) == "skinparam backgroundColor")

		// The block spelling of the same thing, which is what a diagram with
		// several skinparams in it looks like.
		let block = """
		@startuml
		skinparam {
		  BackgroundColor #1E1E1E
		  Shadowing false
		}
		@enduml
		"""
		#expect(PlantUML.statedLook(in: block) == "skinparam backgroundColor")

		// And the newer style language, which is a third spelling of one choice.
		let styled = """
		@startuml
		<style>
		BackgroundColor #1E1E1E
		</style>
		@enduml
		"""
		#expect(PlantUML.statedLook(in: styled) == "<style> BackgroundColor")
	}

	/// Colouring one thing is not choosing how the diagram is lit. If it were,
	/// most real diagrams would lose the app's theme for having tinted an arrow.
	@Test func plantUMLLeavesAnOrdinaryDiagramAlone() {
		let source = """
		@startuml
		' skinparam backgroundColor #000000 — considered and not done
		skinparam sequenceArrowColor #FF0000
		skinparam monochrome false
		Alice -> Bob: hello
		note right: skinparam backgroundColor is not set here
		@enduml
		"""
		#expect(PlantUML.statedLook(in: source) == nil)
	}

	/// Dark is a flag on the process, because PlantUML has no way to say it in a
	/// diagram — measured against `plantuml/plantuml:1.2026.6`, which is what
	/// decided that nothing is injected into anybody's source.
	@Test func plantUMLIsDrawnDarkByItsOwnFlag() {
		let tool = PlantUML.Tool.command("/opt/homebrew/bin/plantuml")
		#expect(PlantUML.invocation(for: tool, format: .svg).arguments
			== ["-pipe", "-tsvg", "-charset", "UTF-8"])
		#expect(PlantUML.invocation(for: tool, format: .svg, theme: .light).arguments
			== ["-pipe", "-tsvg", "-charset", "UTF-8"])
		#expect(PlantUML.invocation(for: tool, format: .svg, theme: .dark).arguments
			== ["-pipe", "-tsvg", "-charset", "UTF-8", "--dark-mode"])
	}

	/// And the same flag on the kept-warm server, because its render route
	/// carries the source and nothing else — so the theme is fixed when the
	/// container starts and one is kept per theme.
	@Test func aKeptServerIsStartedInTheThemeItWillDrawIn() {
		let light = PlantUMLServers.startCommand(
			image: "plantuml/plantuml", name: "abydos-plantuml-server-1-1",
			using: .docker("/usr/bin/docker"), theme: .light
		)
		#expect(!light.arguments.contains("--dark-mode"))
		let dark = PlantUMLServers.startCommand(
			image: "plantuml/plantuml", name: "abydos-plantuml-server-1-1",
			using: .docker("/usr/bin/docker"), theme: .dark
		)
		// The one flag and nothing else: the same container, the same published
		// port, the same image, drawn the other way up.
		#expect(dark.arguments.last == "--dark-mode")
		#expect(Array(dark.arguments.dropLast()) == light.arguments)

		// Two themes of one image are two servers, and a theme of nil is the
		// same server as light — nothing is imposed either way.
		#expect(PlantUMLServers.key(image: "p/p", theme: .dark) == "p/p#dark")
		#expect(PlantUMLServers.key(image: "p/p", theme: .light) == "p/p")
		#expect(PlantUMLServers.key(image: "p/p", theme: nil) == "p/p")
	}

	// MARK: - Mermaid

	/// Front matter is Mermaid's newer spelling, and `themeVariables` counts as
	/// much as `theme` does: somebody who has set the node fill by hand has
	/// chosen how their diagram is lit.
	@Test func mermaidNoticesFrontMatter() {
		let named = """
		---
		config:
		  theme: forest
		---
		flowchart TD
		  A --> B
		"""
		#expect(Mermaid.statedLook(in: named) == "front matter theme: forest")

		let varied = """
		---
		config:
		  themeVariables:
		    primaryColor: '#333'
		---
		flowchart TD
		  A --> B
		"""
		#expect(Mermaid.statedLook(in: varied)?.hasPrefix("front matter themeVariables") == true)

		// A title in front matter is not a look.
		let titled = """
		---
		title: The deployment
		---
		flowchart TD
		  A --> B
		"""
		#expect(Mermaid.statedLook(in: titled) == nil)
	}

	/// The older spelling, which is still the commoner one in the wild.
	@Test func mermaidNoticesAnInitDirective() {
		let source = "%%{init: {'theme': 'dark'}}%%\nflowchart TD\n  A --> B\n"
		#expect(Mermaid.statedLook(in: source) == "%%{init: … theme … }%%")
		#expect(Mermaid.statedLook(in: "flowchart TD\n  A --> B\n") == nil)
		// A directive that is not about the look leaves the theme to the app.
		#expect(Mermaid.statedLook(in: "%%{init: {'flowchart': {'curve': 'linear'}}}%%\nflowchart TD\n  A --> B") == nil)
	}

	/// Only two of Mermaid's five, because the only question being asked is
	/// whether the window is light or dark.
	@Test func mermaidIsToldWhichOfItsThemes() {
		#expect(Mermaid.themeName(.light) == "default")
		#expect(Mermaid.themeName(.dark) == "dark")
	}

	/// Mermaid emits no background at all, so a dark drawing written to disk is
	/// light lines on whatever the reader paints — which is white, everywhere.
	/// The rectangle covers the `viewBox`, not a percentage of a box that may be
	/// translated out from under it.
	@Test func aMermaidDrawingIsPutOnPaperOfItsOwn() throws {
		let drawn = "<svg width=\"200\" height=\"100\" viewBox=\"0 0 200 100\"><g/></svg>"
		let onPaper = Mermaid.onPaper(drawn, colour: "#1b1b1b")
		#expect(onPaper.contains(
			"<rect x=\"0\" y=\"0\" width=\"200\" height=\"100\" fill=\"#1b1b1b\" stroke=\"none\"/>"
		))
		// First, so it is under everything.
		let rect = try #require(onPaper.range(of: "<rect"))
		let group = try #require(onPaper.range(of: "<g/>"))
		#expect(rect.lowerBound < group.lowerBound)

		// A box that does not start at the origin, which is what Mermaid emits
		// for a diagram with a title above it.
		let offset = "<svg viewBox=\"-8 -12 200 100\"><g/></svg>"
		#expect(Mermaid.onPaper(offset, colour: "#fff").contains("x=\"-8\" y=\"-12\""))

		// Nothing to hang it on is nothing changed, rather than a broken file.
		#expect(Mermaid.onPaper("not an svg", colour: "#fff") == "not an svg")
	}

	// MARK: - draw.io

	/// draw.io has no `!theme` and no front matter. The one thing in the
	/// document that is a decision about how the whole picture is lit is the
	/// page's own background — and it is exactly the value the renderer already
	/// paints, so the two cannot disagree.
	@Test func drawioNoticesAPageBackground() {
		func document(_ model: String) -> Drawio.Document {
			Drawio.Document(
				mxfile: "<mxfile><diagram>\(model)</diagram></mxfile>",
				pages: [Drawio.Page(name: "Page-1", id: "a", model: model, wasCompressed: false)]
			)
		}
		#expect(Drawio.statedLook(in: document(
			"<mxGraphModel dx=\"100\" background=\"#000000\" grid=\"1\"><root/></mxGraphModel>"
		)) == "a page background of #000000")

		#expect(Drawio.statedLook(in: document(
			"<mxGraphModel dx=\"100\" grid=\"1\"><root/></mxGraphModel>"
		)) == nil)
		// draw.io writes `none` for "no background", which is not a choice of
		// colour and must not take the app's theme away.
		#expect(Drawio.statedLook(in: document(
			"<mxGraphModel background=\"none\"><root/></mxGraphModel>"
		)) == nil)
	}

	// MARK: - What is asked, and what is imposed

	/// The rule itself, in one line: what the menu asked for, unless the file
	/// has spoken.
	@Test func theFileOverrulesWhatWasAskedFor() {
		#expect(DiagramExport.imposed(.dark, when: nil) == .dark)
		#expect(DiagramExport.imposed(.light, when: nil) == .light)
		#expect(DiagramExport.imposed(.dark, when: "!theme cyborg") == nil)
		#expect(DiagramExport.imposed(nil, when: nil) == nil)
	}

	/// One question with one answer, whichever language the file is in — the
	/// same reason `isDiagram` is one function rather than three.
	@Test func oneQuestionAsksWhicheverRendererOwnsTheFile() {
		#expect(DiagramExport.statedLook(
			of: URL(fileURLWithPath: "/p/a.puml"), source: "@startuml\n!theme mars\n@enduml"
		) == "!theme mars")
		#expect(DiagramExport.statedLook(
			of: URL(fileURLWithPath: "/p/a.mmd"), source: "%%{init: {'theme':'neutral'}}%%\nflowchart TD\nA-->B"
		) == "%%{init: … theme … }%%")
		#expect(DiagramExport.statedLook(
			of: URL(fileURLWithPath: "/p/a.drawio"),
			source: "<mxfile><diagram><mxGraphModel background=\"#101010\"><root/>"
				+ "</mxGraphModel></diagram></mxfile>"
		) == "a page background of #101010")
	}

	/// The sentence somebody actually reads, which is the whole point of
	/// noticing at all.
	@Test func theNoticeQuotesTheFileBackAtWhoeverWroteIt() {
		let said = DiagramLook.notice(stated: "!theme reddress-darkblue")
		#expect(said.contains("!theme reddress-darkblue"))
		#expect(said.contains("its own look"))
		#expect(DiagramLook.exportNotice(for: "flow.puml", stated: "!theme mars").contains("flow.puml"))
	}
}
