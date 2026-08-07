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
