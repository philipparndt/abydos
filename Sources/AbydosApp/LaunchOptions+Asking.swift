import AppKit
import AbydosKit

/// The questions asked *of* a set of options, as against the flags they were
/// read from.
///
/// Each is one sentence, and each exists because the flag it is worked out
/// from used to be asked directly at three call sites that meant three
/// different things by it.
extension LaunchOptions {
	/// Whether `--screenshot` was given, which is only ever the right question
	/// about the window capture itself and its delay.
	///
	/// **It used to be asked as though it meant three different things**, and
	/// 0534 and 0535 are two of them arriving as bug reports. Use
	/// `writesACapture` for "will this run produce a picture at all" and
	/// `isDrivenRun` for "is this being driven rather than used".
	var isScreenshotRun: Bool { screenshotPath != nil }

	/// Whether this run is going to write a picture of something, by any flag.
	///
	/// **A list rather than one flag, and that is the whole of 0535.** While
	/// `--screenshot` was the only capture flag, "a picture is coming" and
	/// "`--screenshot` was given" were the same sentence. They stopped being so
	/// and nothing noticed: `--sidebar-shot` on its own hit an `exit(0)` guarded
	/// by `isScreenshotRun`, so the process ended *before* the capture ran and
	/// wrote a blank panel — while exiting zero, which is why it was believed
	/// once already.
	///
	/// Every flag that writes an image belongs here. The next one added will
	/// belong here too, and leaving it out is the same fault again — which is
	/// the argument against widening `isScreenshotRun` in place: it would have
	/// kept the trap and only moved it.
	var writesACapture: Bool {
		screenshotPath != nil
			|| editorShotPath != nil
			|| sidebarShot != nil
			|| metalShot != nil
			|| toolbarImage != nil
	}

	/// Whether the app is being driven rather than used.
	///
	/// `DrivenRun` in `AbydosKit` is where this is decided and argued, because
	/// `Settings` and `SessionStore` have to ask the same question and neither
	/// can see this file. Stated here as well so that a reader of the options
	/// finds it: any verb but `--open` and `--file` makes a run a driven one.
	var isDrivenRun: Bool { DrivenRun.isActive }

	/// Every file this run named, as the paths they resolve to.
	///
	/// The set a driven run is allowed to put keystrokes into. `--open` is not
	/// among them: naming a project says what to show, not what to type in, and
	/// the whole of 0522's second incident was a verb typing into a file that
	/// was merely *inside* the project it was pointed at.
	var givenPaths: Set<String> {
		var paths = filePaths
		if let previewPath { paths.append(previewPath) }
		if let tearOffFile { paths.append(tearOffFile) }
		// Made by this run, in the project this run was given, so its own.
		if let newFile, let projectPath {
			paths.append((projectPath as NSString).appendingPathComponent(newFile))
		}
		return Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
	}

	/// Whether a driven run may drive the keyboard at this file.
	///
	/// The rule itself is `DrivenRun.mayType`, in `AbydosKit`, where the suite
	/// can ask it questions — there is no test target for this layer. What is
	/// here is the one thing the rule cannot know: a scratch this run asked for
	/// has a path nobody could have said in advance.
	func mayType(into url: URL?) -> Bool {
		if newScratch, let url,
		   url.standardizedFileURL.path.hasPrefix(ScratchFiles.defaultRoot.path) {
			return true
		}
		return DrivenRun.mayType(into: url?.path, given: givenPaths, driven: isDrivenRun)
	}
}
