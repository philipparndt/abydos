import Foundation
import Testing
@testable import AbydosKit

/// Recognising a go3mf recipe, which is the one preview in this app whose name
/// cannot say what it is.
///
/// GoSTL builds and shows a recipe already. All that is here is the question Abydos
/// has to answer before offering that: is this `.yaml` a recipe, or is it the CI
/// workflow every other `.yaml` in a repository turns out to be?
struct Go3mfRecipeTests {
	// MARK: - The rule

	/// The recipe this item came from, near enough verbatim — 1,091 bytes of German
	/// comments, commented-out options and two objects of one part each.
	private let realRecipe = """
		# Adapter und Feder-Adapter zusammen auf eine Platte.
		# Documentation: https://github.com/philipparndt/go3mf
		#
		#   go3mf combine adapter-set.yaml

		output: adapter-set.3mf

		# Packing distance between objects in mm (default: 10.0)
		packing_distance: 10.0

		objects:
		  - name: Adapter
		    # count: 1
		    parts:
		      - name: adapter
		        file: ./adapter.scad
		        rotation_x: -90
		"""

	@Test func knowsARecipe() {
		#expect(Go3mfRecipe.looksLikeRecipe(yaml: realRecipe))
	}

	/// The signature is both keys at the top level. Either alone is a coincidence
	/// waiting to happen.
	@Test func needsBothKeys() {
		#expect(!Go3mfRecipe.looksLikeRecipe(yaml: "output: adapter-set.3mf\n"))
		#expect(!Go3mfRecipe.looksLikeRecipe(yaml: "objects:\n  - name: Adapter\n"))
		#expect(Go3mfRecipe.looksLikeRecipe(yaml: "objects:\n  - name: A\noutput: a.3mf\n"))
	}

	/// The YAML a repository is actually full of. None of it is offered the 3D
	/// viewer, which is the whole reason this reads the file at all.
	@Test func leavesTheRestOfARepositorysYamlAlone() {
		// A GitHub workflow. `on:` and `jobs:`, and an `output` three levels down.
		#expect(!Go3mfRecipe.looksLikeRecipe(yaml: """
			name: CI
			on:
			  push:
			    branches: [main]
			jobs:
			  build:
			    runs-on: macos-15
			    outputs:
			      output: ${{ steps.build.outputs.path }}
			    steps:
			      - uses: actions/checkout@v4
			"""))
		// A compose file.
		#expect(!Go3mfRecipe.looksLikeRecipe(yaml: """
			services:
			  web:
			    image: nginx
			    ports:
			      - "8080:80"
			volumes:
			  data:
			"""))
		// A Helm chart.
		#expect(!Go3mfRecipe.looksLikeRecipe(yaml: """
			apiVersion: v2
			name: devpod
			version: 0.1.0
			"""))
		// A Kubernetes manifest, whose `metadata:` and `spec:` are the closest thing
		// in common use to a list of objects.
		#expect(!Go3mfRecipe.looksLikeRecipe(yaml: """
			apiVersion: apps/v1
			kind: Deployment
			metadata:
			  name: api
			spec:
			  replicas: 2
			"""))
	}

	/// Top level means column zero. A build pipeline's `output:` nested under a step
	/// is a step's output, and its `objects:` under a bucket is a bucket's.
	@Test func onlyTopLevelKeysCount() {
		#expect(!Go3mfRecipe.looksLikeRecipe(yaml: """
			pipeline:
			  output: thing.3mf
			  objects:
			    - one
			"""))
		#expect(!Go3mfRecipe.looksLikeRecipe(yaml: "\toutput: a.3mf\n\tobjects:\n"))
	}

	/// A comment is not a signature, and the strongest hint in the real file is in
	/// one. A recipe written from scratch has no header, and a header copied into
	/// something else is not a recipe.
	@Test func ignoresComments() {
		#expect(!Go3mfRecipe.looksLikeRecipe(yaml: """
			# Documentation: https://github.com/philipparndt/go3mf
			#   go3mf combine adapter-set.yaml
			# output: adapter-set.3mf
			# objects:
			name: something else entirely
			"""))
	}

	/// A word is not a key. `---` between documents, and a bare scalar, have no colon.
	@Test func needsAColon() {
		#expect(!Go3mfRecipe.looksLikeRecipe(yaml: "---\noutput\nobjects\n"))
	}

	/// A file written on Windows is the same file.
	@Test func readsCarriageReturns() {
		#expect(Go3mfRecipe.looksLikeRecipe(yaml: "output: a.3mf\r\nobjects:\r\n  - name: A\r\n"))
	}

	// MARK: - What it costs

	/// The name decides whether anything is read at all, and the name alone is never
	/// an answer.
	@Test func onlyLooksInsideAYaml() {
		#expect(Go3mfRecipe.hasRecipeExtension(URL(fileURLWithPath: "/tmp/a.yaml")))
		#expect(Go3mfRecipe.hasRecipeExtension(URL(fileURLWithPath: "/tmp/a.yml")))
		#expect(Go3mfRecipe.hasRecipeExtension(URL(fileURLWithPath: "/tmp/A.YAML")))
		#expect(!Go3mfRecipe.hasRecipeExtension(URL(fileURLWithPath: "/tmp/a.json")))
		#expect(!Go3mfRecipe.hasRecipeExtension(URL(fileURLWithPath: "/tmp/a.scad")))
	}

	/// A recipe on disk, recognised; the same bytes under another name, not — the
	/// extension gates the read, so a `.txt` is never opened to find out.
	@Test func readsARecipeFromDisk() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("go3mf-recipe-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let recipe = directory.appendingPathComponent("adapter-set.yaml")
		try realRecipe.write(to: recipe, atomically: true, encoding: .utf8)
		#expect(Go3mfRecipe.looksLikeRecipe(recipe))

		let disguised = directory.appendingPathComponent("adapter-set.txt")
		try realRecipe.write(to: disguised, atomically: true, encoding: .utf8)
		#expect(!Go3mfRecipe.looksLikeRecipe(disguised))

		let workflow = directory.appendingPathComponent("ci.yml")
		try "name: CI\non: push\n".write(to: workflow, atomically: true, encoding: .utf8)
		#expect(!Go3mfRecipe.looksLikeRecipe(workflow))
	}

	/// A file that is not there, and a directory that happens to be named like one,
	/// answer no rather than throwing.
	@Test func saysNoToWhatItCannotRead() throws {
		#expect(!Go3mfRecipe.looksLikeRecipe(URL(fileURLWithPath: "/tmp/nothing-\(UUID()).yaml")))

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("looks-like-a-recipe-\(UUID().uuidString).yaml")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		#expect(!Go3mfRecipe.looksLikeRecipe(directory))
	}

	/// **The bound, said out loud.** 8 KB from the head of the file and not a byte
	/// more, so the answer is one page of one file however large the file is. What
	/// that costs: a recipe whose two keys are past 8 KB of leading comment is not
	/// recognised. A recipe's top level comes first — the one this came from is 1,091
	/// bytes whole — so the trade is a bounded read against a file nobody has.
	@Test func readsOnlyTheHeadOfTheFile() throws {
		#expect(Go3mfRecipe.inspectedBytes == 8 * 1024)

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("go3mf-bound-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let padding = String(repeating: "# a comment line, thirty-two ch\n", count: 400)
		#expect(padding.utf8.count > Go3mfRecipe.inspectedBytes)

		let late = directory.appendingPathComponent("late.yaml")
		try (padding + realRecipe).write(to: late, atomically: true, encoding: .utf8)
		#expect(!Go3mfRecipe.looksLikeRecipe(late))

		// The same keys inside the bound, with megabytes of file after them.
		let early = directory.appendingPathComponent("early.yaml")
		try (realRecipe + "\n" + String(repeating: padding, count: 40))
			.write(to: early, atomically: true, encoding: .utf8)
		#expect(Go3mfRecipe.looksLikeRecipe(early))
	}

	// MARK: - Which door it opens

	/// A recipe is a model *once somebody has looked*. The question a name can answer
	/// still answers no, and that is what keeps a tree walk from reading anything.
	@Test func isAModelOnlyWhenTheContentsSayIt() {
		let recipe = URL(fileURLWithPath: "/tmp/adapter-set.yaml")
		#expect(FilePreview.kind(for: recipe) == nil)
		#expect(!FilePreview.hasPreview(recipe))
		#expect(FilePreview.availableModes(for: recipe).isEmpty)

		#expect(FilePreview.kind(for: recipe, looksLikeRecipe: true) == .model)
		#expect(FilePreview.hasPreview(recipe, looksLikeRecipe: true))
	}

	/// **An option, not a default.** A recipe opens as its text, and the preview
	/// control offers the viewer beside it — unlike a mesh, which has no source worth
	/// reading, and unlike a `.scad`, whose one render is one shape where a recipe's
	/// is every part's render plus a `go3mf build` on top.
	@Test func opensAsTextAndOffersTheViewer() {
		let recipe = URL(fileURLWithPath: "/tmp/adapter-set.yaml")
		#expect(FilePreview.defaultMode(for: recipe, looksLikeRecipe: true) == .source)
		#expect(FilePreview.hasReadableSource(recipe))
		#expect(FilePreview.availableModes(for: recipe, looksLikeRecipe: true) == PreviewMode.allCases)
	}

	/// A session that remembered the split gets the split back; one that remembered
	/// nothing gets the text.
	@Test func comesBackInTheModeItWasLeftIn() {
		let recipe = URL(fileURLWithPath: "/tmp/adapter-set.yaml")
		#expect(FilePreview.restoredMode(.splitRight, for: recipe, looksLikeRecipe: true) == .splitRight)
		#expect(FilePreview.restoredMode(nil, for: recipe, looksLikeRecipe: true) == .source)
		// And a mode remembered against a `.yaml` that is no longer a recipe — or
		// never was — is dropped rather than obeyed.
		#expect(FilePreview.restoredMode(.splitRight, for: recipe) == .source)
	}

	/// The flag is about a `.yaml` and nothing else. Told yes about a mesh, the answer
	/// is still a mesh's: it opens rendered, because it has no source.
	@Test func doesNotChangeWhatAMeshDoes() {
		let mesh = URL(fileURLWithPath: "/tmp/part.stl")
		#expect(FilePreview.kind(for: mesh, looksLikeRecipe: true) == .model)
		#expect(FilePreview.defaultMode(for: mesh, looksLikeRecipe: true) == .preview)
	}

	// MARK: - The other door: the navigator's Preview in GoSTL

	/// `canPreview` is the question about the name and `holdsAModel` the question
	/// about the contents, the same split `DiagramExport` has. A `.yaml` is never in
	/// the extension set, so nothing that runs over a tree can be made to read one.
	@Test func theExtensionSetStaysFreeOfYaml() {
		#expect(!ModelPreview.previewableExtensions.contains("yaml"))
		#expect(!ModelPreview.previewableExtensions.contains("yml"))
		#expect(!ModelPreview.canPreview(URL(fileURLWithPath: "/tmp/adapter-set.yaml")))
	}

	@Test func offersTheStandaloneViewerForARecipe() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("go3mf-menu-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let recipe = directory.appendingPathComponent("adapter-set.yaml")
		try realRecipe.write(to: recipe, atomically: true, encoding: .utf8)
		#expect(ModelPreview.holdsAModel(recipe))
		#expect(!ModelPreview.canPreview(recipe))

		let workflow = directory.appendingPathComponent("ci.yaml")
		try "name: CI\non: push\njobs:\n  build:\n".write(to: workflow, atomically: true, encoding: .utf8)
		#expect(!ModelPreview.holdsAModel(workflow))

		// A mesh needs no reading and gets the same answer from both.
		let mesh = directory.appendingPathComponent("part.stl")
		try Data().write(to: mesh)
		#expect(ModelPreview.holdsAModel(mesh))
		#expect(ModelPreview.canPreview(mesh))
	}
}
