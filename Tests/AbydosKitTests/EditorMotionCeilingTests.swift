import Foundation
import Testing
@testable import AbydosKit

/// How many motions the editor could be asked for and does not have.
///
/// **The ceiling is the argument.** Naming every unhandled selector would be
/// unbounded noise — `noop:` alone would drown it — while `move…` and `select…`
/// are a family AppKit fixes at compile time, so the worst case is a number
/// that can be counted. This counts it, against the SDK the build is using and
/// the switch as it stands, so that "fourteen possible lines" cannot quietly
/// become four hundred.
///
/// It was fourteen when the item was written on 2026-08-16 and four two days
/// later, because ten were taken in between. That movement is the point: this
/// test says what the number is today rather than what somebody remembered.
struct EditorMotionCeilingTests {
	@Test func theUnhandledMotionsAreACountableFew() throws {
		let sdk = try #require(run("xcrun", ["--sdk", "macosx", "--show-sdk-path"]))
		let header = sdk.trimmingCharacters(in: .whitespacesAndNewlines)
			+ "/System/Library/Frameworks/AppKit.framework/Headers/NSResponder.h"
		guard let text = try? String(contentsOfFile: header, encoding: .utf8) else { return }

		let declared = Set(matches(of: "-[ ]*\\(void\\)((move|select)[A-Za-z]*):", in: text))
		#expect(declared.count > 30, "the header stopped looking like it used to")

		let view = try #require(sourceOfCodeView())
		let unhandled = declared.filter { !view.contains("\($0)(_:)") }

		// A ceiling, not a target. If this fails because it grew, either the
		// editor lost a case or AppKit gained a family — and either is worth
		// somebody looking rather than a number being edited.
		#expect(unhandled.count <= 14, "unhandled motions: \(unhandled.sorted())")
	}

	private func sourceOfCodeView() -> String? {
		// From this file, up to the package root, across to the app target.
		var directory = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		directory.appendPathComponent("Sources/AbydosApp/Editor/CodeView.swift")
		return try? String(contentsOf: directory, encoding: .utf8)
	}

	private func matches(of pattern: String, in text: String) -> [String] {
		guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
		let range = NSRange(text.startIndex..., in: text)
		return expression.matches(in: text, range: range).compactMap { match in
			Range(match.range(at: 1), in: text).map { String(text[$0]) }
		}
	}

	private func run(_ tool: String, _ arguments: [String]) -> String? {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = [tool] + arguments
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return String(data: data, encoding: .utf8)
	}
}
