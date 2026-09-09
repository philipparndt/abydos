import AppKit
import CryptoKit
import QuickLookUI
import GoSTL
import AbydosKit
import SwiftUI

/// SOPS: a file that is encrypted on disk and readable in the editor, and the
/// passphrase that stands between the two.
extension EditorViewController {
	// MARK: - SOPS


	/// What the status bar's chip shows for the front tab.
	enum SopsState: Equatable {
		case none
		case unavailable
		case encrypted
		case decrypted(edited: Bool)
		/// Plaintext, and a creation rule in the project's `.sops.yaml` says
		/// this path should be encrypted. An offer, not a warning: most files
		/// are not meant to be encrypted, and a chip on each of them would be
		/// answered by rote.
		case offer
	}

	var sopsState: SopsState {
		guard let tab = activeTab else { return .none }
		guard tab.isSopsFile else { return tab.sopsOffer ? .offer : .none }
		if tab.isDecrypted { return .decrypted(edited: tab.isDirty) }
		return Sops.isAvailable ? .encrypted : .unavailable
	}

	/// What git can see of the front tab's file, for the bar.
	var exposureState: SecretExposure.State { activeTab?.exposure ?? .fine }

	/// Asks git about a file whose values are covered, off the main thread, and
	/// tells the bar when the answer comes back. Which files those are — and
	/// why a SOPS file, decrypted buffer included, is not one — is
	/// `SecretExposure.asksGit(fileNamed:isSops:)`; either flag answers its
	/// `isSops`. Only inside a project: two `git` runs of one path each, and
	/// none at all for the ordinary file somebody is editing.
	func askWhatGitCanSee(of tab: Tab) {
		let sops = tab.isSopsFile || tab.isDecrypted
		let conceals = SecretExposure.asksGit(fileNamed: tab.url.lastPathComponent, isSops: sops)
		guard conceals, let root = project?.root else {
			guard tab.exposure != .fine else { return }
			tab.exposure = .fine
			onStatusChanged?(self)
			return
		}
		let url = tab.url
		Task { @MainActor [weak self, weak tab] in
			let state = await SecretExposure.state(of: url, in: root, conceals: true)
			guard let self, let tab, tab.exposure != state else { return }
			tab.exposure = state
			self.onStatusChanged?(self)
		}
	}

	/// Asked again for every open tab: a line added to `.gitignore`, or a file
	/// added to the index, changes what git can see without changing the file.
	func refreshWhatGitCanSee() {
		for tab in tabs { askWhatGitCanSee(of: tab) }
	}

	/// The change marks again, now that the repository is known.
	///
	/// **Because the first ask happens before there is an estate.** A tab is
	/// opened and its gutter asks at once, and `Project.loadGit` — which reads
	/// the submodule inventory — finishes a second or two later. Until it does,
	/// `place(of:)` has nothing to place a file with and falls back to the
	/// project's own root, which is the right answer for a repository with no
	/// submodules and the wrong one for every file inside a submodule: the
	/// superproject answers that diff with nothing, and the gutter drew no
	/// marks at all. Nothing re-asked, because
	/// `.abydosRepositoryChanged` is posted by things people do — a branch
	/// switch, a pull, a stage — and not by the first read finishing.
	///
	/// So the window says when it knows. A plain project runs this and gets
	/// the same answer twice, which is one `git diff` per open tab, once.
	func refreshChangeMarks() {
		for tab in tabs { refreshChangedLines(for: tab) }
	}

	/// The notice's one action: the front tab's file written into the
	/// project's `.gitignore`.
	///
	/// The pattern is the file's own path from the repository root — the most
	/// predictable of the suggestions the tree's dialog offers, and the one
	/// nobody has to read a syntax guide to check. The tree's dialog stays
	/// where it is for the fancier patterns; a status-bar press is for the
	/// file in front of somebody.
	func ignoreActiveFile() {
		guard let tab = activeTab, let root = project?.root else { return }
		let path = tab.url.standardizedFileURL.path
		let rootPath = root.standardizedFileURL.path
		guard path.hasPrefix(rootPath + "/") else {
			Toast.post("Not in this project", detail: "\(tab.url.lastPathComponent) is outside \(root.lastPathComponent).")
			return
		}
		let pattern = String(path.dropFirst(rootPath.count + 1))
		do {
			_ = try GitIgnore.add(pattern, toRepositoryAt: root)
			Toast.post("Ignoring \(pattern)", detail: "Written to .gitignore.", kind: .information)
			NotificationCenter.default.post(name: .abydosRepositoryChanged, object: root)
			refreshWhatGitCanSee()
		} catch {
			Toast.post("Could not write .gitignore", detail: error.localizedDescription)
		}
	}

	/// The chip, pressed: decrypt an encrypted file, encrypt and save an
	/// edited decrypted one, and nothing for a decrypted buffer with nothing
	/// to save — its tooltip says ⌘S is the save.
	func pressSops() {
		guard let tab = activeTab else { return }
		guard tab.isSopsFile else {
			if tab.sopsOffer { Task { @MainActor in await self.encryptPlaintext(tab) } }
			return
		}
		if tab.isDecrypted {
			if tab.isDirty {
				Task { @MainActor in await self.encryptAndSave(tab) }
			} else {
				// ⌥ on *Lock* forgets the passphrases kept for the sitting, for
				// somebody leaving the machine to someone else.
				if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
					Passphrases.shared.forgetAll()
					Toast.post("Forgot the passphrases kept for this sitting", kind: .information)
				}
				lockAgain(tab)
			}
		} else {
			Task { @MainActor in await self.decrypt(tab) }
		}
	}



	/// What a passphrase is kept under: the key gpg named, else the project,
	/// since one key unlocks every file in it.
	private func passphraseKey(for tab: Tab, stderr: String) -> String {
		Sops.keyNamed(in: stderr) ?? project?.root.path ?? tab.url.deletingLastPathComponent().path
	}

	/// `sops --decrypt`, and what comes back on stdout into the buffer as one
	/// edit — so the caret, folds and scroll come back, and ⌘Z would give the
	/// ciphertext back, which is a way of re-locking a buffer and harmless.
	/// Nothing is written anywhere: no `.dec`, no temp file, no scratch.
	///
	/// The first attempt is the one there was: no passphrase, so an agent
	/// that holds it, a working pinentry and an age key see no question.
	/// Only a failure in gpg's passphrase words leads to the kept one, then
	/// to the field; any other failure keeps the toast.
	private func decrypt(_ tab: Tab, passphrase: String? = nil, keptFor key: String? = nil) async {
		guard let document = tab.document, let codeView = tab.codeView else { return }
		let result: GitRepository.ProcessResult
		if let passphrase {
			result = await Sops.decrypt(tab.url, passphrase: passphrase)
		} else {
			result = await Sops.decrypt(tab.url)
		}
		guard result.exitCode == 0 else {
			let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
			guard Sops.needsPassphrase(stderr: stderr) else {
				Toast.post("Could not decrypt \(tab.url.lastPathComponent)", detail: stderr)
				return
			}
			let keyName = Sops.keyNamed(in: stderr)
			let key = key ?? passphraseKey(for: tab, stderr: stderr)
			if passphrase == nil, let kept = Passphrases.shared.passphrase(for: key) {
				// Asked once a sitting: the kept one first.
				await decrypt(tab, passphrase: kept, keptFor: key)
				return
			}
			if passphrase != nil { Passphrases.shared.forget(key) }
			let wrong = passphrase != nil && Sops.wrongPassphrase(stderr: stderr)
			let placeholder = wrong
				? "Wrong passphrase — try again"
				: "Passphrase for \(keyName.map { "key \($0)" } ?? tab.url.lastPathComponent)"
			onPassphraseNeeded?(placeholder, stderr) { [weak self] answer in
				guard let self, let answer, !answer.isEmpty else { return }
				Task { @MainActor in await self.decrypt(tab, passphrase: answer, keptFor: key) }
			}
			return
		}
		if let passphrase, let key { Passphrases.shared.remember(passphrase, for: key) }
		// The server is told the file is closed *before* the buffer changes:
		// from here on `serverRoot(for:)` answers nil for this tab, so this is
		// the last announcement it will ever make about it.
		announceClosed(tab)
		codeView.replaceAllText(with: result.stdout)
		document.markClean()
		tab.isDecrypted = true
		tab.decryptedBaseline = result.stdout
		document.declinesAutoSave = true
		// A decrypted buffer is a `.dec` that never touched disk: it conceals,
		// whatever the file is called — and stands revealed from the start,
		// with the lock open, because pressing *decrypt* is the explicit act
		// the lock exists to demand; a second press to see what was just asked
		// for would be the same question twice. The idle re-conceal still
		// shuts it, and the lock shuts it at once.
		codeView.setConcealsSecrets(Settings.shared.concealsSecrets)
		codeView.setSecretsRevealed(true)
		// No marks while it is decrypted, and the ciphertext's marks back when
		// it is locked: both go through the one place that asks git.
		refreshChangedLines(for: tab)
		refreshTabBar()
		onStatusChanged?(self)
	}

	/// The ciphertext back into the buffer, and the tab an ordinary one again:
	/// after a save, from what `sops` just wrote; from the chip on an unedited
	/// decrypted buffer, from the file. Either way the plaintext is gone from
	/// the buffer and the chip reads *encrypted*, so the file can be decrypted
	/// again in place rather than closed and reopened.
	private func lockAgain(_ tab: Tab, ciphertext: String? = nil) {
		guard let document = tab.document, let codeView = tab.codeView else { return }
		let text = ciphertext ?? (try? String(contentsOf: tab.url, encoding: .utf8))
		guard let text else { return }
		codeView.replaceAllText(with: text)
		document.markClean()
		tab.isDecrypted = false
		tab.decryptedBaseline = nil
		document.declinesAutoSave = false
		codeView.setSecretsRevealed(false)
		codeView.setConcealsSecrets(
			Settings.shared.concealsSecrets
				&& DotenvSecrets.conceals(fileNamed: tab.url.lastPathComponent)
		)
		// The server hears about the file again, as ciphertext, which is what
		// it had before the decrypt.
		if let languageId = document.languageId, let root = serverRoot(for: tab) {
			LanguageService.shared.opened(
				url: tab.url, languageId: languageId, text: self.text(of: document), project: root
			)
		}
		// And the gutter says what git says about the ciphertext — which for a
		// decrypt that changed nothing is nothing at all.
		refreshChangedLines(for: tab)
		refreshTabBar()
		onStatusChanged?(self)
	}

	/// The buffer through `sops --encrypt` on stdin, the ciphertext over the
	/// file. The buffer stays decrypted and becomes clean. Refused when the
	/// file moved on disk since the decrypt: a stale save is a stale save.
	/// A buffer still holding the decrypt's own plaintext skips the encrypt
	/// — `lockIfUnchanged(_:)` below.
	@discardableResult
	func encryptAndSave(_ tab: Tab) async -> Bool {
		guard let document = tab.document, tab.isDecrypted else { return false }
		guard !document.hasChangedOnDisk else {
			Toast.post(
				"\(tab.url.lastPathComponent) changed on disk",
				detail: "Nothing was written. Close the tab and open the file again to see the new version."
			)
			return false
		}
		if lockIfUnchanged(tab) { return true }
		let result = await Sops.encrypt(text(of: document), for: tab.url)
		return finishEncrypt(result, for: tab)
	}

	/// The offer taken: a plaintext file this project's rules say should be
	/// encrypted, encrypted in place.
	///
	/// The same `sops --encrypt` the save path runs, under the file's own name
	/// so the project's `.sops.yaml` picks the keys, and the ciphertext written
	/// over the file. The tab is then what opening an already-encrypted file
	/// gives: the chip reading *encrypted*, the ciphertext in the buffer, and
	/// nothing decrypted held anywhere — the plaintext was never a *decrypted
	/// buffer* and there is nothing to park or to ask about at quit.
	///
	/// An unsaved buffer is written first, because what `sops` is handed is
	/// what is on the screen: encrypting the file under an edited buffer would
	/// leave the edit outside the ciphertext and unrecoverable.
	func encryptPlaintext(_ tab: Tab) async {
		guard let document = tab.document, !tab.isSopsFile, !tab.isDecrypted else { return }
		if document.isDirty { save() }
		let result = await Sops.encrypt(text(of: document), for: tab.url)
		guard result.exitCode == 0, !result.stdout.isEmpty else {
			Toast.post(
				"Could not encrypt \(tab.url.lastPathComponent)",
				detail: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
			)
			return
		}
		do {
			try document.replaceOnDisk(with: Data(result.stdout.utf8))
		} catch {
			Toast.post("Could not save \(tab.url.lastPathComponent)", detail: error.localizedDescription)
			return
		}
		tab.codeView?.replaceAllText(with: result.stdout)
		document.markClean()
		tab.isSopsFile = true
		tab.sopsOffer = false
		refreshChangedLines(for: tab)
		refreshTabBar()
		askWhatGitCanSee(of: tab)
		onStatusChanged?(self)
	}

	/// The same on the calling thread, for a close dialog and for quitting,
	/// where there is no run loop left to come back to.
	func encryptAndSaveSync(_ tab: Tab) -> Bool {
		guard let document = tab.document, tab.isDecrypted else { return false }
		guard !document.hasChangedOnDisk else {
			Toast.post("\(tab.url.lastPathComponent) changed on disk", detail: "Nothing was written.")
			return false
		}
		if lockIfUnchanged(tab) { return true }
		return finishEncrypt(Sops.encryptSync(text(of: document), for: tab.url), for: tab)
	}

	/// The save's first question, asked on every route to one: whether the
	/// buffer still holds exactly what the decrypt returned. Such a save
	/// costs the file nothing — the ciphertext on disk already *is* this
	/// text's version, while `sops --encrypt` would mint a fresh one, the
	/// same plaintext going in and a file sharing not one line coming out —
	/// so the encrypt is skipped and the buffer locked back, the same lock
	/// the chip gives an unedited buffer. `isDirty` could not answer this:
	/// undo marks a buffer dirty on the way back to the decrypt's own text,
	/// and ⌘S never asked at all. Called only after the changed-on-disk
	/// refusal, because a file that moved is not the file this baseline came
	/// from, and its answer is the refusal.
	@discardableResult
	private func lockIfUnchanged(_ tab: Tab) -> Bool {
		guard let document = tab.document else { return false }
		guard text(of: document) == tab.decryptedBaseline else { return false }
		lockAgain(tab)
		return true
	}

	private func finishEncrypt(_ result: GitRepository.ProcessResult, for tab: Tab) -> Bool {
		guard let document = tab.document else { return false }
		guard result.exitCode == 0, !result.stdout.isEmpty else {
			Toast.post(
				"Could not encrypt \(tab.url.lastPathComponent)",
				detail: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
			)
			return false
		}
		do {
			try document.replaceOnDisk(with: Data(result.stdout.utf8))
		} catch {
			Toast.post("Could not save \(tab.url.lastPathComponent)", detail: error.localizedDescription)
			return false
		}
		lockAgain(tab, ciphertext: result.stdout)
		refreshChangedLines(for: tab)
		return true
	}

	/// Parks every decrypted tab and takes it out without asking, ahead of the
	/// switch closing the rest. The switch is not a close: the buffer goes to
	/// memory and comes back with the project, and a dialog on every switch
	/// would make working on something else meanwhile a question.
	func parkDecryptedTabs() {
		for index in tabs.indices.reversed() where tabs[index].isDecrypted {
			let tab = tabs[index]
			guard let document = tab.document else { continue }
			parkDecrypted?(tab.url, DecryptedBuffer(
				text: text(of: document), isEdited: tab.isDirty,
				caretLine: tab.codeView?.caretLine ?? 0,
				baseline: tab.decryptedBaseline
			))
			removeTab(at: index)
		}
	}

	func restoreDecrypted(_ parked: DecryptedBuffer, into tab: Tab) {
		guard let document = tab.document, let codeView = tab.codeView else { return }
		codeView.replaceAllText(with: parked.text)
		if !parked.isEdited { document.markClean() }
		tab.isDecrypted = true
		// The park carried the baseline or it never existed; re-deriving it
		// from the parked text when `isEdited` is false would lose exactly
		// the edited-then-undone buffer the skip exists for.
		tab.decryptedBaseline = parked.baseline
		document.declinesAutoSave = true
		codeView.setConcealsSecrets(Settings.shared.concealsSecrets)
		refreshTabBar()
	}

	/// The decrypted tabs with edits in them — what quitting has to ask about.
	var editedDecryptedTabs: [Tab] { tabs.filter { $0.isDecrypted && $0.isDirty } }

	/// Drives the chip from outside: `report` (the state, what git can see, the
	/// line count and a digest of the text — never the text, since a driven
	/// run's log must not be a secret), `decrypt` or `press`, `encrypt`,
	/// `type:<text>`, `undo`, `refresh`, `ignore`, `settle`.
	func sopsForTesting(_ steps: String) {
		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			if step.hasPrefix("settle") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.sopsForTesting(rest)
				}
				return
			}
			let argument = String(step.drop(while: { $0 != ":" }).dropFirst())
			switch step.prefix(while: { $0 != ":" }) {
			case "report": print("SOPS: \(sopsReportForTesting())")
			// What the gutter is marking, which is a different question from
			// what git says: a decrypted buffer differs from HEAD in every
			// line and has changed nothing.
			case "marks":
				print("SOPS marks: "
					+ (activeTab?.codeView?.changedLinesReportForTesting ?? "no editor"))
			// `press` and `decrypt` are the same door — the chip — and the
			// second name is what it does on an encrypted file. On a plaintext
			// file a creation rule matches, the same press encrypts it.
			case "decrypt", "press": pressSops()
			case "passphrase":
				if let answer = passphraseAnswerForTesting { answer(argument) } else { print("SOPS: no passphrase was asked for") }
			case "cancel-passphrase":
				passphraseAnswerForTesting?(nil)
			case "forget": Passphrases.shared.forgetAll()
			case "encrypt": save()
			// What git can see, asked again: `.gitignore` gained a line, or the
			// file was added, and neither touches the file itself.
			case "refresh": refreshWhatGitCanSee()
			// The notice's one action, through the same door its menu item
			// goes through.
			case "ignore": ignoreActiveFile()
			case "type": simulateTyping(argument)
			case "undo": undoForTesting()
			default: print("SOPS: unknown step \(step)")
			}
		}
		fflush(stdout)
	}

	private func sopsReportForTesting() -> String {
		guard let tab = activeTab else { return "no editor" }
		let state: String
		switch sopsState {
		case .none: state = "not-sops"
		case .unavailable: state = "sops-missing"
		case .encrypted: state = "encrypted"
		case .decrypted: state = "decrypted"
		case .offer: state = "offer"
		}
		let exposure: String
		switch tab.exposure {
		case .fine: exposure = "fine"
		case .notIgnored: exposure = "not-ignored"
		case .tracked: exposure = "tracked"
		}
		let text = tab.document.map { self.text(of: $0) } ?? ""
		let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16)
		return "file=\(tab.url.lastPathComponent) state=\(state) git=\(exposure) edited=\(tab.isDirty)"
			+ " ask=\(passphraseAskForTesting.map { "“\($0)”" } ?? "none") kept=\(Passphrases.shared.count)"
			+ " lines=\(tab.document?.rope.lineCount ?? 0) sha256=\(digest)"
			+ " covers=\(tab.codeView?.showsSecretCovers ?? false)"
			+ " revealed=\(tab.codeView?.secretsRevealedAll ?? false)"
	}
}
