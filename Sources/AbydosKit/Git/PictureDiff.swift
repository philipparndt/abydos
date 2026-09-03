import Foundation
import CoreGraphics
import ImageIO

/// Where two pictures differ, as rectangles.
///
/// A changed picture used to diff as the sentence "No textual changes." — true,
/// and useless. The three ways of looking at the change in the diff view are
/// drawing; this is the arithmetic under the third of them, kept here so a test
/// can call it on two bitmaps without a window.
///
/// **Regions, not pixels.** A re-taken screenshot differs from the last one in
/// ten thousand pixels along a shadow's edge, each by a little; what a person
/// means by "what changed" is the two boxes where something moved. So a pixel
/// counts as changed only past a small threshold, changed pixels are gathered
/// into a grid of cells, and touching cells become one rectangle.
public enum PictureDiff {
	/// A decoded picture: 8-bit RGBA, row by row, top to bottom.
	public struct Bitmap: Sendable, Equatable {
		public let width: Int
		public let height: Int
		public let rgba: [UInt8]

		public init(width: Int, height: Int, rgba: [UInt8]) {
			self.width = width
			self.height = height
			self.rgba = rgba
		}

		/// A blank picture of one colour, for tests and for a side that is
		/// missing.
		public init(width: Int, height: Int, fill: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) = (0, 0, 0, 255)) {
			self.width = width
			self.height = height
			var pixels = [UInt8](repeating: 0, count: width * height * 4)
			for index in stride(from: 0, to: pixels.count, by: 4) {
				pixels[index] = fill.r
				pixels[index + 1] = fill.g
				pixels[index + 2] = fill.b
				pixels[index + 3] = fill.a
			}
			rgba = pixels
		}

		/// Decodes whatever ImageIO reads — PNG, JPEG, GIF, HEIC, WebP where the
		/// system has it — into RGBA at the picture's own pixel size. Nil for
		/// bytes that are not a picture ImageIO knows.
		public init?(data: Data) {
			guard let source = CGImageSourceCreateWithData(data as CFData, nil),
			      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
			else { return nil }
			self.init(image: image)
		}

		public init?(image: CGImage) {
			let width = image.width, height = image.height
			guard width > 0, height > 0 else { return nil }
			var pixels = [UInt8](repeating: 0, count: width * height * 4)
			let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
				guard let context = CGContext(
					data: buffer.baseAddress, width: width, height: height,
					bitsPerComponent: 8, bytesPerRow: width * 4,
					space: CGColorSpaceCreateDeviceRGB(),
					bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
				) else { return false }
				context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
				return true
			}
			guard drawn else { return nil }
			self.width = width
			self.height = height
			rgba = pixels
		}

		public var pixelCount: Int { width * height }

		/// The picture's size, said as a person says it.
		public var sizeDescription: String { "\(width)×\(height)" }

		/// Writes one pixel, for tests building a picture with an edit in it.
		public mutating func set(x: Int, y: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
			var pixels = rgba
			let index = (y * width + x) * 4
			pixels[index] = r; pixels[index + 1] = g; pixels[index + 2] = b; pixels[index + 3] = a
			self = Bitmap(width: width, height: height, rgba: pixels)
		}
	}

	/// A rectangle in the picture's own pixels, from the top-left.
	public struct Region: Sendable, Equatable {
		public let x: Int
		public let y: Int
		public let width: Int
		public let height: Int

		public init(x: Int, y: Int, width: Int, height: Int) {
			self.x = x; self.y = y; self.width = width; self.height = height
		}
	}

	/// Either the regions, or the reason there are none to be had.
	public enum Outcome: Sendable, Equatable {
		case regions([Region])
		/// Nothing could be compared — different sizes, or too large — and
		/// why, in words a caption can show.
		case declined(String)
	}

	/// How far one channel may move before a pixel counts as changed.
	///
	/// Sixteen of 255: a re-encode's rounding, a colour-profile conversion,
	/// JPEG's grain all sit under it; anything drawn differently is over it.
	public static let threshold: UInt8 = 16
	/// The cell the changed pixels are gathered by. Sixteen pixels is finer
	/// than anything somebody edits on purpose and coarser than speckle.
	public static let cell = 16
	/// Above this many pixels a side, the comparison is declined: a bitmap this
	/// size is a 4k screenshot, which is the ordinary large case, and beyond it
	/// the memory is not worth the answer.
	public static let pixelBound = 16_000_000

	/// The rectangles where `new` differs from `old`.
	public static func compare(
		_ old: Bitmap, _ new: Bitmap,
		threshold: UInt8 = threshold, cell: Int = cell, pixelBound: Int = pixelBound
	) -> Outcome {
		guard old.width == new.width, old.height == new.height else {
			return .declined("The sizes differ: \(old.sizeDescription) against \(new.sizeDescription).")
		}
		guard old.pixelCount <= pixelBound else {
			return .declined("Too large to compare: \(old.sizeDescription).")
		}
		let width = old.width, height = old.height
		guard width > 0, height > 0 else { return .regions([]) }

		// Which cells hold a changed pixel.
		let columns = (width + cell - 1) / cell
		let rows = (height + cell - 1) / cell
		var marked = [Bool](repeating: false, count: columns * rows)
		let limit = Int(threshold)
		old.rgba.withUnsafeBufferPointer { a in
			new.rgba.withUnsafeBufferPointer { b in
				for y in 0..<height {
					let rowCell = (y / cell) * columns
					var index = y * width * 4
					for x in 0..<width {
						if abs(Int(a[index]) - Int(b[index])) > limit
							|| abs(Int(a[index + 1]) - Int(b[index + 1])) > limit
							|| abs(Int(a[index + 2]) - Int(b[index + 2])) > limit
							|| abs(Int(a[index + 3]) - Int(b[index + 3])) > limit {
							marked[rowCell + x / cell] = true
						}
						index += 4
					}
				}
			}
		}

		// Touching cells become one region: a flood over the four neighbours,
		// each component's bounds clipped to the picture.
		var seen = [Bool](repeating: false, count: marked.count)
		var regions: [Region] = []
		for start in marked.indices where marked[start] && !seen[start] {
			var stack = [start]
			seen[start] = true
			var minC = Int.max, minR = Int.max, maxC = -1, maxR = -1
			while let index = stack.popLast() {
				let c = index % columns, r = index / columns
				minC = min(minC, c); maxC = max(maxC, c)
				minR = min(minR, r); maxR = max(maxR, r)
				for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
					let nc = c + dc, nr = r + dr
					guard nc >= 0, nc < columns, nr >= 0, nr < rows else { continue }
					let next = nr * columns + nc
					if marked[next], !seen[next] {
						seen[next] = true
						stack.append(next)
					}
				}
			}
			let x = minC * cell, y = minR * cell
			regions.append(Region(
				x: x, y: y,
				width: min((maxC + 1) * cell, width) - x,
				height: min((maxR + 1) * cell, height) - y
			))
		}
		regions.sort { ($0.y, $0.x) < ($1.y, $1.x) }
		return .regions(regions)
	}
}
