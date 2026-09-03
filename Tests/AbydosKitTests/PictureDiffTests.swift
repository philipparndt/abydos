import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import AbydosKit

/// Where two pictures differ, as the diff view will draw it.
struct PictureDiffTests {
	private typealias Bitmap = PictureDiff.Bitmap

	private func grey(_ width: Int = 64, _ height: Int = 64) -> Bitmap {
		Bitmap(width: width, height: height, fill: (128, 128, 128, 255))
	}

	/// Paints a block red, which is an edit anybody would call one.
	private func paint(_ bitmap: inout Bitmap, x: Int, y: Int, width: Int, height: Int) {
		for py in y..<(y + height) {
			for px in x..<(x + width) { bitmap.set(x: px, y: py, r: 255, g: 0, b: 0) }
		}
	}

	@Test func identicalPicturesHaveNoRegions() {
		let picture = grey()
		#expect(PictureDiff.compare(picture, picture) == .regions([]))
	}

	/// The threshold is what tells an edit from a re-encode: one channel of
	/// one pixel moving by one is the second, and nobody wants a box on it.
	@Test func onePixelChangedByOneIsNotAChange() {
		let old = grey()
		var new = old
		new.set(x: 10, y: 10, r: 129, g: 128, b: 128)
		#expect(PictureDiff.compare(old, new) == .regions([]))
	}

	@Test func onePixelChangedOutrightIsOneRegionOfOneCell() {
		let old = grey()
		var new = old
		new.set(x: 20, y: 36, r: 255, g: 0, b: 0)
		#expect(PictureDiff.compare(old, new) == .regions([
			PictureDiff.Region(x: 16, y: 32, width: 16, height: 16),
		]))
	}

	/// Two edits well apart are two regions, each covering its own area and
	/// no more, in reading order.
	@Test func twoSeparateEditsAreTwoRegions() {
		let old = grey(128, 128)
		var new = old
		paint(&new, x: 4, y: 4, width: 8, height: 8)
		paint(&new, x: 100, y: 90, width: 20, height: 10)
		guard case let .regions(found) = PictureDiff.compare(old, new) else {
			Issue.record("declined")
			return
		}
		#expect(found.count == 2)
		#expect(found[0] == PictureDiff.Region(x: 0, y: 0, width: 16, height: 16))
		// 100…119 spans cells 6 and 7 (96…127); 90…99 spans cells 5 and 6 (80…111).
		#expect(found[1] == PictureDiff.Region(x: 96, y: 80, width: 32, height: 32))
	}

	/// An edit across a cell boundary is still one region: the cells touch.
	@Test func anEditAcrossCellsIsOneRegion() {
		let old = grey()
		var new = old
		paint(&new, x: 12, y: 12, width: 10, height: 10)
		guard case let .regions(found) = PictureDiff.compare(old, new) else {
			Issue.record("declined")
			return
		}
		#expect(found == [PictureDiff.Region(x: 0, y: 0, width: 32, height: 32)])
	}

	/// A region at the picture's edge is clipped to the picture, so a box is
	/// never drawn past it.
	@Test func aRegionIsClippedToThePicture() {
		let old = grey(40, 40)
		var new = old
		paint(&new, x: 36, y: 36, width: 4, height: 4)
		#expect(PictureDiff.compare(old, new) == .regions([
			PictureDiff.Region(x: 32, y: 32, width: 8, height: 8),
		]))
	}

	@Test func differentSizesAreDeclinedNamingBoth() {
		let outcome = PictureDiff.compare(grey(640, 480), grey(1280, 960))
		#expect(outcome == .declined("The sizes differ: 640×480 against 1280×960."))
	}

	@Test func aPictureOverTheBoundIsDeclined() {
		let outcome = PictureDiff.compare(grey(200, 200), grey(200, 200), pixelBound: 100)
		#expect(outcome == .declined("Too large to compare: 200×200."))
	}

	/// A picture ImageIO can read comes back at its own pixel size; bytes that
	/// are not a picture come back as nothing rather than a crash or a blank.
	@Test func bytesDecodeToTheirOwnSizeOrNotAtAll() throws {
		// A 2×3 PNG made by ImageIO here, rather than pasted bytes somebody has
		// to trust: the claim is about reading, and this is a picture for sure.
		var red = Bitmap(width: 2, height: 3, fill: (255, 0, 0, 255))
		red.set(x: 1, y: 2, r: 0, g: 0, b: 255)
		let png = try #require(Self.png(of: red))
		let decoded = try #require(Bitmap(data: png))
		#expect(decoded.width == 2)
		#expect(decoded.height == 3)
		#expect(PictureDiff.compare(red, decoded) == .regions([]), "a round trip through PNG is not a change")
		#expect(Bitmap(data: Data("not a picture".utf8)) == nil)
	}

	/// Encodes a bitmap as PNG, the way a test fixture would be made.
	private static func png(of bitmap: Bitmap) -> Data? {
		let data = NSMutableData()
		guard let provider = CGDataProvider(data: Data(bitmap.rgba) as CFData),
		      let image = CGImage(
			      width: bitmap.width, height: bitmap.height, bitsPerComponent: 8, bitsPerPixel: 32,
			      bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
			      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
			      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
		      ),
		      let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
		else { return nil }
		CGImageDestinationAddImage(destination, image, nil)
		guard CGImageDestinationFinalize(destination) else { return nil }
		return data as Data
	}
}
