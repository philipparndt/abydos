import AppKit
import AbydosKit
import UniformTypeIdentifiers

/// Whether the Finder opens source files with this app, and the one time it
/// offers to.
///
/// **The declaration is in the bundle; this is the asking.** `Info.plist` says
/// what this editor can open, as an *Alternate* — an offer in the *Open With*
/// menu, claiming nothing. Becoming the default is somebody's decision, taken
/// once, and Launch Services rather than this app is the record of it.
@MainActor
enum DefaultEditor {
	/// The kinds this bundle declares it can edit, read from the bundle itself
	/// so that adding one is a single edit rather than two lists to keep in
	/// step — which is the failure `DeclaredFileTypesTests` exists for.
	static var declaredTypes: [UTType] {
		let documents = Bundle.main.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]]
		let identifiers = (documents ?? [])
			.filter { ($0["CFBundleTypeRole"] as? String) == "Editor" }
			.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
		return identifiers.compactMap(UTType.init)
	}

	/// Of the kinds declared, the ones Launch Services says this app opens.
	///
	/// **Asked rather than remembered.** An app that stored "I am the default"
	/// tells somebody that after another editor has taken it back, which is the
	/// one moment the page is being read.
	static func typesThisAppOpens() -> [UTType] {
		guard let mine = Bundle.main.bundleURL.standardizedFileURL.path as String? else { return [] }
		return declaredTypes.filter { type in
			guard let handler = NSWorkspace.shared.urlForApplication(toOpen: type) else {
				return false
			}
			return handler.standardizedFileURL.path == mine
		}
	}

	/// Of the kinds declared, the ones this app may take the default of. See
	/// `TypeFamilies.belongToAnotherKindOfApp`, which is why the two lists
	/// differ.
	static var claimableTypes: [UTType] {
		TypeFamilies.claimable(declaredTypes)
	}

	/// Against what it may claim, not against everything it declares —
	/// otherwise this is never true, and the offer is made again every time.
	static var isDefaultForEverythingDeclared: Bool {
		let claimable = Set(claimableTypes.map(\.identifier))
		guard !claimable.isEmpty else { return false }
		return typesThisAppOpens().filter { claimable.contains($0.identifier) }.count
			== claimable.count
	}

	/// Takes the declared kinds: the roots first, then only what is still not
	/// this app's.
	///
	/// macOS puts a confirmation of its own in front of every call — *Do you
	/// want all "Source Code" documents to open with Abydos?* — and one call
	/// per declared kind was sixteen of them in a row. Launch Services resolves
	/// a kind through its parents when nothing binds it directly, so the
	/// bundle declares `public.text` and that one call covers the family; the
	/// second pass asks again only for a kind another application holds by
	/// name, which is a question worth its dialog. What came back is what the
	/// page reads afterwards, rather than what was asked for.
	/// **`public.html` is not among what it takes**, only among what it
	/// declares: taking that one makes this the default browser, and the
	/// scheme handlers follow. `TypeFamilies.belongToAnotherKindOfApp` has the
	/// whole of it.
	static func makeDefault() async {
		let declared = claimableTypes
		for type in TypeFamilies.roots(of: declared) {
			try? await NSWorkspace.shared.setDefaultApplication(
				at: Bundle.main.bundleURL, toOpen: type
			)
		}
		let taken = Set(typesThisAppOpens().map(\.identifier))
		for type in declared where !taken.contains(type.identifier) {
			try? await NSWorkspace.shared.setDefaultApplication(
				at: Bundle.main.bundleURL, toOpen: type
			)
		}
	}

	/// Hands them back to whatever the system chooses next.
	///
	/// There is no "unset" — `setDefaultApplication` with the app the system
	/// would otherwise pick is the whole of it — so this asks Launch Services
	/// for the next-best handler of each kind and gives it there.
	static func handBack() async {
		for type in typesThisAppOpens() {
			let others = NSWorkspace.shared.urlsForApplications(toOpen: type)
				.filter { $0.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL }
			guard let next = others.first else { continue }
			try? await NSWorkspace.shared.setDefaultApplication(at: next, toOpen: type)
		}
	}

	/// Gives back a claim this app should never have taken, once, at launch.
	///
	/// **An older build made this machine's default browser an editor.** The
	/// second pass of `makeDefault` claimed every declared type by name,
	/// `public.html` among them, and taking HTML is how macOS is told which
	/// application is the browser — so `open https://…` went to a program with
	/// no URL handling at all, which dropped the link and exited 0. The taking
	/// is fixed above; this is for the machines it already happened on, which
	/// cannot be reached by fixing it.
	///
	/// Narrow on purpose. It hands back only the types
	/// `TypeFamilies.belongToAnotherKindOfApp` names, only when this app
	/// actually holds one, and it never touches the source-code kinds somebody
	/// chose deliberately. Nothing happens on the overwhelming majority of
	/// launches, and what it costs then is one Launch Services lookup.
	static func handBackWhatWasNeverOurs() async {
		guard !DrivenRun.isActive else { return }
		let mine = Bundle.main.bundleURL.standardizedFileURL
		let wrong = TypeFamilies.belongToAnotherKindOfApp
			.compactMap(UTType.init)
			.filter { NSWorkspace.shared.urlForApplication(toOpen: $0)?.standardizedFileURL == mine }
		guard !wrong.isEmpty else { return }

		for type in wrong {
			let others = NSWorkspace.shared.urlsForApplications(toOpen: type)
				.filter { $0.standardizedFileURL != mine }
			guard let next = others.first else { continue }
			try? await NSWorkspace.shared.setDefaultApplication(at: next, toOpen: type)
		}

		// Said, because it changes something about the machine rather than
		// about this app, and somebody who has been wondering why links stopped
		// opening deserves the sentence.
		let handler = NSWorkspace.shared
			.urlForApplication(toOpen: URL(string: "https://example.com")!)?
			.deletingPathExtension().lastPathComponent
		Toast.post(
			"Links open in your browser again",
			detail: "An earlier version of this app had taken the default for web pages, "
				+ "which is how macOS is told which application is the browser. "
				+ (handler.map { "They go to \($0) now." } ?? "It has been handed back."),
			kind: .information
		)
	}

	// MARK: - The ask

	/// Whether this file is one of the kinds the bundle declares.
	static func isDeclared(_ url: URL) -> Bool {
		let name = url.pathExtension.lowercased()
		guard !name.isEmpty else { return false }
		// The registry's own answer, through its public door: a file it can
		// colour is a file this editor reads, which is the claim the bundle
		// makes.
		if LanguageRegistry.shared.languageId(for: url) != nil { return true }
		guard let type = UTType(filenameExtension: name) else { return false }
		return declaredTypes.contains { type.conforms(to: $0) }
	}

	/// Asks, once, the first time a source file is opened in a window.
	///
	/// **Not at first launch**, which is a question about nothing that has
	/// happened yet and is answered by reflex to get rid of it. The first
	/// source file somebody opens is the moment the question is about something
	/// they are doing.
	///
	/// Never in a driven run: a capture run must not change which application
	/// this machine opens `.swift` files with, and must not put a sheet in
	/// front of the window it is photographing.
	static func considerAsking(about url: URL, in window: NSWindow?) {
		guard !DrivenRun.isActive else { return }
		guard Settings.shared.defaultEditorAsked == .unasked else { return }
		guard isDeclared(url) else { return }
		guard !isDefaultForEverythingDeclared else {
			// Already the default — nothing to offer, and nothing to ask again.
			Settings.shared.defaultEditorAsked = .neverAsk
			return
		}

		let alert = NSAlert()
		alert.messageText = "Open source files with Abydos?"
		alert.informativeText = "The Finder can open them with this editor when you "
			+ "double-click them. It is offered under Open With either way — this makes it "
			+ "the one that opens by default.\n\n"
			+ "You can change it later in Settings ▸ Tools."
		alert.addButton(withTitle: "Make Default")
		alert.addButton(withTitle: "Not Now")
		alert.addButton(withTitle: "Never Ask")

		let act: (NSApplication.ModalResponse) -> Void = { response in
			switch response {
			case .alertFirstButtonReturn:
				Settings.shared.defaultEditorAsked = .neverAsk
				Task { @MainActor in
					await makeDefault()
					let taken = typesThisAppOpens().count
					Toast.post(
						taken == 0 ? "The system kept the current default" : "Abydos opens source files",
						detail: taken == 0
							? "Nothing changed. macOS decides this one, and it can be set per file kind in the Finder's Get Info."
							: "\(taken) kind\(taken == 1 ? "" : "s") of file. Settings ▸ Tools hands them back.",
						kind: .information
					)
				}
			case .alertSecondButtonReturn:
				Settings.shared.defaultEditorAsked = .notNow
			default:
				Settings.shared.defaultEditorAsked = .neverAsk
			}
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: act)
		} else {
			act(alert.runModal())
		}
	}
}
