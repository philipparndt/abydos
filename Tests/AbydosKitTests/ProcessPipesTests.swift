import Foundation
import Testing
@testable import AbydosKit

/// Collecting a subprocess's output without deadlocking against it.
///
/// These run a real `git`, deliberately: the bug they exist for is in the
/// plumbing between two processes, and a fake on this side of it would have
/// gone on passing while the suite hung.
/// Somewhere for the worker thread to leave what it produced.
private final class ResultBox<T: Sendable>: @unchecked Sendable {
	var value: T?
}

struct ProcessPipesTests {
	private func repository() throws -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("pipes-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		_ = GitRepository.runSync(["init", "-q", "-b", "main", "."], in: root)
		return root
	}

	/// Runs something on another thread and says whether it finished.
	///
	/// A deadlock has to fail rather than hang — a test that hangs takes the
	/// whole suite with it, which is exactly how this bug went unnoticed for a
	/// day. The blocked thread is left behind when it times out, which is the
	/// right trade for a run that is failing anyway.
	private func finished<T: Sendable>(
		within seconds: Int, _ work: @escaping @Sendable () -> T
	) -> T? {
		let box = ResultBox<T>()
		let done = DispatchSemaphore(value: 0)
		DispatchQueue.global(qos: .userInitiated).async {
			box.value = work()
			done.signal()
		}
		guard done.wait(timeout: .now() + .seconds(seconds)) == .success else { return nil }
		return box.value
	}

	/// A program that says more on stderr than a pipe holds.
	///
	/// This is the deadlock itself. Reading stdout to the end and stderr
	/// afterwards means the first read only returns when the program exits, and
	/// the program cannot exit while it is blocked writing to the pipe nobody
	/// is reading. `git push` with no upstream printing its advice was enough
	/// to do it; two hundred kilobytes leaves no doubt.
	@Test func aProgramThatFillsStderrDoesNotDeadlock() throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		let result = finished(within: 30) {
			GitRepository.runSync([
				"-c", "alias.spew=!sh -c 'yes x | head -c 200000 >&2; echo done'",
				"spew",
			], in: root)
		}
		let finishedResult = try #require(
			result, "runSync deadlocked against a program writing to stderr"
		)
		#expect(finishedResult.stderr.count == 200_000)
		#expect(finishedResult.stdout.contains("done"))
	}

	/// And the same from the other end: input larger than a pipe, written while
	/// the program is busy filling its own output.
	@Test func inputLargerThanAPipeDoesNotDeadlock() throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		let blob = Data(repeating: UInt8(ascii: "x"), count: 300_000)
		let result = finished(within: 30) {
			GitRepository.runSync(["hash-object", "-w", "--stdin"], in: root, input: blob)
		}
		let hashed = try #require(result, "runSync deadlocked writing input larger than the pipe")
		#expect(hashed.exitCode == 0)
		#expect(hashed.stdout.trimmingCharacters(in: .whitespacesAndNewlines).count == 40)
	}

	/// git reads its input from the pipe it is given rather than from whatever
	/// the app was started with, whether or not there is anything to send. A
	/// command that reads stdin and is given none used to inherit ours and wait
	/// for an end that never came.
	@Test func aCommandThatReadsStandardInputIsGivenAnEndToIt() throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		let result = finished(within: 30) {
			GitRepository.runSync(["hash-object", "--stdin"], in: root)
		}
		#expect(result != nil, "runSync waited for input nobody was going to send")
	}

	/// A stray process holding the pipe open does not hang the caller.
	///
	/// Foundation does not mark a pipe's descriptors close-on-exec, so a
	/// subprocess started while this one was being set up inherits them and
	/// holds them open for as long as it runs. Waiting for end of file then
	/// means waiting for a stranger to quit. Two `/bin/cat` processes left
	/// behind by another test did exactly that and hung the suite for twenty
	/// minutes.
	@Test func aStrayHolderOfThePipeDoesNotHangTheCaller() throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		// A `cat` that outlives the command, holding the write end.
		let stray = Process()
		stray.executableURL = URL(fileURLWithPath: "/bin/sh")
		stray.arguments = ["-c", "sleep 60 &"]

		let result = finished(within: 30) {
			// The stray is started from inside the same window the command's
			// pipes live in.
			try? stray.run()
			return GitRepository.runSync(["rev-parse", "--is-inside-work-tree"], in: root)
		}
		stray.terminate()
		let answered = try #require(result, "runSync waited on a process that was not its own")
		#expect(answered.stdout.contains("true"))
	}

	/// The caller's environment reaches git. It used to be merged and then
	/// thrown away by a second assignment a few lines below, so nothing that
	/// passed one ever had it applied.
	@Test func theCallersEnvironmentIsNotThrownAway() throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try "one\n".write(
			to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8
		)
		_ = GitRepository.runSync(["add", "-A"], in: root)
		_ = GitRepository.runSync(
			["commit", "-qm", "first"],
			in: root,
			environment: [
				"GIT_AUTHOR_NAME": "Someone Else",
				"GIT_AUTHOR_EMAIL": "else@example.com",
				"GIT_COMMITTER_NAME": "Someone Else",
				"GIT_COMMITTER_EMAIL": "else@example.com",
			]
		)

		let author = GitRepository.runSync(["log", "-1", "--format=%an <%ae>"], in: root)
		#expect(author.stdout.contains("Someone Else <else@example.com>"))
	}
}

/// Giving up on a read, and the crash that came out of how it used to be done.
///
/// A crash report from a real session, in the code that makes the drain robust:
///
///     _NSFileHandleRaiseOperationExceptionWhileReading
///     -[NSConcreteFileHandle readDataOfLength:]
///     closure #1 in static ProcessPipes.drain (ProcessPipes.swift:43)
///
/// `readDataToEndOfFile()` *raises* an Objective-C exception when its read
/// fails, and Swift cannot catch one — so a failed read in a background drain
/// went to the uncaught handler and aborted the app. The read is `read(2)` now,
/// which returns -1 and sets `errno`, so no read here can end the process
/// however it fails.
///
/// **What these do not do is reproduce that crash.** Three attempts, all of
/// which pass against the old code and are written down so nobody spends the
/// afternoon again: closing the descriptor under a reader blocked in
/// `readDataToEndOfFile` (the read simply ends), the same with a process
/// writing continuously so the reader is between reads rather than inside one,
/// and letting the `Pipe` go out of scope so its `FileHandle` closes the
/// descriptor in `deinit` under an abandoned reader. None raises on this
/// machine.
///
/// So the condition is still unknown, and the fix is not aimed at it: it
/// removes the API that can raise at all, which is a stronger claim than
/// patching whichever read failed. What is tested below is the path the crash
/// was on — a drain that gives up on a reader and returns what it had.
struct DrainGivingUpTests {
	/// Runs something whose pipes are local, exactly as every caller here does.
	///
	/// That the pipes are local is the whole point: `drain` gives up after four
	/// seconds and returns, and the reader thread it gave up on is still
	/// running. The caller then goes out of scope, the `Pipe` is released, its
	/// `FileHandle`s close the descriptors in `deinit` — and the read still
	/// blocked on one of them raises.
	private func runWithLocalPipes() -> String {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		// A writer that outlives the shell, so end of file never comes and the
		// reader is still there to be surprised.
		process.arguments = ["-c", "(while :; do echo hello; sleep 0.02; done) &"]
		let out = Pipe(), err = Pipe()
		process.standardOutput = out
		process.standardError = err
		process.standardInput = FileHandle.nullDevice
		guard (try? process.run()) != nil else { return "" }
		return ProcessPipes.drainText(process, out: out, err: err).stdout
	}

	@Test func aReadThatIsGivenUpOnReturnsWhatItHad() {
		let said = runWithLocalPipes()
		// The point of giving up: a truncated capture from a program that has
		// already exited, rather than waiting for a stranger to quit.
		#expect(said.contains("hello"))
		// The pipes are gone by now, and an abandoned reader is still running
		// on their descriptors. It must not take the process with it.
		Thread.sleep(forTimeInterval: 3)
	}
}
