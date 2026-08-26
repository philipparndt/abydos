import Foundation

/// A number of bytes, in the units somebody reads.
///
/// One implementation, because two would drift on the boundary: the sessions
/// section rounds `10.0 MiB` to `10 MiB` and anything smaller keeps a decimal,
/// and a second copy written from the same description would put `9.95` where
/// this puts `10.0`.
///
/// **MiB and not MB, everywhere.** A binary-file notice once said `405,7 MB` in
/// its sentence and `387 MiB` beside it — the same number in two conventions,
/// which reads as a mistake because it is one. `ByteCountFormatter` is where
/// both came from: its `.file` style divides by 1000 and its `.memory` style
/// divides by 1024 and labels the result `MB` anyway. So neither is used, and
/// this is what a size looks like in this app.
public enum ByteSize {
	public static func said(_ bytes: Int64) -> String {
		let units = ["KiB", "MiB", "GiB"]
		guard bytes >= 1024 else { return "\(bytes) B" }
		var value = Double(bytes) / 1024
		var unit = 0
		while value >= 1024, unit < units.count - 1 { value /= 1024; unit += 1 }
		return value >= 10
			? "\(Int(value.rounded())) \(units[unit])"
			: String(format: "%.1f %@", value, units[unit])
	}

	/// The size of a file, or nil when there is nothing to measure.
	public static func ofFile(at url: URL) -> Int64? {
		let values = try? url.resourceValues(forKeys: [.fileSizeKey])
		return (values?.fileSize).map(Int64.init)
	}
}
