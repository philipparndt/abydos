import Darwin
import Foundation
import Testing
@testable import AbydosKit

/// How long a tmux socket path may be, and how that was established.
///
/// The number was not taken from anybody's memory. `sizeof(sun_path)` is asked
/// of the platform, and the test below binds a real socket at the limit and one
/// byte past it — so if a future macOS changes the field, the suite says so
/// rather than the app quietly refusing directories that would have worked.
struct TmuxSocketPathTests {
	/// The claim, checked against the kernel rather than against itself.
	///
	/// A socket bound at exactly the limit works; one byte more is
	/// `ENAMETOOLONG`, which is the errno behind tmux's `File name too long`.
	@Test func theLimitIsWhereTheKernelActuallyStops() throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(atPath: directory) }

		let atTheLimit = try path(in: directory, ofLength: TmuxSocketPath.limit)
		#expect(bind(atTheLimit) == 0, "a socket path of \(TmuxSocketPath.limit) bytes should bind")

		let oneTooMany = try path(in: directory, ofLength: TmuxSocketPath.limit + 1)
		#expect(bind(oneTooMany) == ENAMETOOLONG)
	}

	/// tmux appends two components of its own: the per-user directory and the
	/// socket's name, which is `default` unless `-L` says otherwise. For uid 501
	/// that is `/tmux-501/default`, seventeen bytes, so a `TMUX_TMPDIR` has 86
	/// to spend.
	@Test func aDirectoryPaysForWhatTmuxAppendsToIt() {
		#expect(TmuxSocketPath.path(under: "/private/tmp/x", uid: 501) == "/private/tmp/x/tmux-501/default")

		let longest = "/private/tmp/" + String(repeating: "d", count: 73)
		#expect(longest.utf8.count == 86)
		#expect(TmuxSocketPath.fits(longest, uid: 501))
		#expect(!TmuxSocketPath.fits(longest + "d", uid: 501))
	}

	/// tmux resolves the directory before it measures, and this is where a
	/// plausible-looking value goes wrong: `/tmp` is a symlink to
	/// `/private/tmp`, so eight bytes appear that were never typed. Measuring
	/// what somebody wrote rather than what it points at would pass a directory
	/// tmux then refuses — which is what tmux 3.7b does with this exact value.
	@Test func measuresWhereTheDirectoryPointsRatherThanHowItWasWritten() {
		let written = "/tmp/" + String(repeating: "e", count: 74)
		#expect(written.utf8.count == 79, "short enough on the face of it")
		#expect(TmuxSocketPath.path(under: written, uid: 501).hasPrefix("/private/tmp/"))
		#expect(!TmuxSocketPath.fits(written, uid: 501), "but 87 bytes once resolved")
	}

	/// And resolved the way tmux resolves it. Foundation's
	/// `resolvingSymlinksInPath` is a different function: it strips a leading
	/// `/private` whenever the shorter form exists, so it answers `/tmp/…` —
	/// eight bytes under what tmux measures, in the direction that would let a
	/// doomed directory through.
	@Test func resolvesTheWayRealpathDoesRatherThanTheWayFoundationDoes() {
		#expect(TmuxSocketPath.resolved("/private/tmp") == "/private/tmp")
		#expect(TmuxSocketPath.resolved("/tmp") == "/private/tmp")
		#expect(
			URL(fileURLWithPath: "/private/tmp").resolvingSymlinksInPath().path == "/tmp",
			"the answer this deliberately does not use"
		)
		// Nothing there yet: as far as it goes, and the rest kept.
		#expect(TmuxSocketPath.resolved("/tmp/not-there-448/either") == "/private/tmp/not-there-448/either")
	}

	/// Nothing to refuse is not a refusal: no variable, or an empty one, leaves
	/// the environment exactly as it was.
	@Test func saysNothingWhenThereIsNothingToSay() {
		#expect(TmuxSocketPath.refusal(for: nil) == nil)
		#expect(TmuxSocketPath.refusal(for: "") == nil)
		#expect(TmuxSocketPath.refusal(for: "/private/tmp/sockets") == nil)

		let kept = ["TMUX_TMPDIR": "/private/tmp/sockets", "PATH": "/usr/bin"]
		#expect(TmuxSocketPath.honouringWhatFits(kept) == kept)
	}

	/// The sentence somebody is left with. It has to name the variable — the
	/// one thing tmux's own message never did — and the number, so the value
	/// can be shortened rather than guessed at.
	@Test func theSentenceNamesTheVariableAndTheNumber() throws {
		let tooLong = "/private/tmp/" + String(repeating: "d", count: 120)
		let said = try #require(TmuxSocketPath.refusal(for: tooLong, uid: 501))
		#expect(said.contains("TMUX_TMPDIR"))
		#expect(said.contains("150"), "the length it would have come to")
		#expect(said.contains("\(TmuxSocketPath.limit)"))
	}

	/// The invariant the app's own tmux commands rely on, checked against
	/// whatever environment the suite happens to be running in. On the machine
	/// this was written on that environment carried the 116-byte value from the
	/// report, so this was not a hypothetical while it was being written.
	@Test func whatIsHandedToTmuxNeverCarriesADirectoryThatCannotWork() {
		guard let directory = TmuxSocketPath.environment["TMUX_TMPDIR"] else { return }
		#expect(TmuxSocketPath.fits(directory))
	}

	// MARK: - Asking the kernel

	private func temporaryDirectory() throws -> String {
		// Short on purpose: the test needs room to build a path of exactly the
		// limit inside it, and anything under `NSTemporaryDirectory()` on macOS
		// is a 49-byte container path with no room left.
		let directory = "/private/tmp/abydos-socket-\(getpid())"
		try FileManager.default.createDirectory(
			atPath: directory, withIntermediateDirectories: true
		)
		return directory
	}

	private func path(in directory: String, ofLength length: Int) throws -> String {
		let padding = length - directory.utf8.count - 1
		try #require(padding > 0, "the temporary directory is too long to test in")
		return directory + "/" + String(repeating: "s", count: padding)
	}

	/// Binds a socket at a path and returns 0, or the errno that stopped it.
	private func bind(_ path: String) -> Int32 {
		var address = sockaddr_un()
		address.sun_family = sa_family_t(AF_UNIX)
		address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

		let capacity = MemoryLayout.size(ofValue: address.sun_path)
		let bytes = Array(path.utf8)
		// The check the app is making, made here against the field itself: a
		// path that needs the terminator's byte is one tmux's `strlcpy` would
		// truncate, and truncation is a socket somewhere else entirely.
		guard bytes.count < capacity else { return ENAMETOOLONG }

		withUnsafeMutablePointer(to: &address.sun_path) { field in
			field.withMemoryRebound(to: CChar.self, capacity: capacity) { characters in
				for (index, byte) in bytes.enumerated() { characters[index] = CChar(bitPattern: byte) }
				characters[bytes.count] = 0
			}
		}

		let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
		guard descriptor >= 0 else { return errno }
		defer { close(descriptor); unlink(path) }

		let result = withUnsafePointer(to: &address) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
			}
		}
		return result == 0 ? 0 : errno
	}
}
