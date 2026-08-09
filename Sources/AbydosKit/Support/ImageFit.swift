import Foundation

/// Where a picture goes in the pane showing it.
///
/// Kept out of the view so the rule can be checked without a window: a picture
/// larger than the pane is fitted to it, and one smaller is left at its own
/// size. Blowing a sixteen-pixel icon up to fill a window is a blurry lie about
/// what is in the file, and it is the first thing anybody notices.
public enum ImageFit {
	/// The rectangle a picture of `image` size occupies in a pane of `pane`
	/// size, centred, with its proportions kept.
	public static func rect(image: CGSize, in pane: CGSize, scale: CGFloat = 0) -> CGRect {
		guard image.width > 0, image.height > 0, pane.width > 0, pane.height > 0 else {
			return .zero
		}

		let factor = scale > 0 ? scale : fitScale(image: image, in: pane)
		let size = CGSize(width: (image.width * factor).rounded(), height: (image.height * factor).rounded())
		return CGRect(
			x: ((pane.width - size.width) / 2).rounded(),
			y: ((pane.height - size.height) / 2).rounded(),
			width: size.width,
			height: size.height
		)
	}

	/// How much a picture has to shrink to fit, never more than its own size.
	public static func fitScale(image: CGSize, in pane: CGSize) -> CGFloat {
		guard image.width > 0, image.height > 0, pane.width > 0, pane.height > 0 else { return 1 }
		return min(1, min(pane.width / image.width, pane.height / image.height))
	}

	/// How large a picture may be drawn when the interface itself is zoomed.
	///
	/// The zoom's multiple of the picture's own size, or as much of that as the
	/// pane has room for. At 1× it is `fitScale` exactly — a picture larger than
	/// the pane shrinks to fit and a smaller one is left alone — so nothing
	/// changes for a window nobody has zoomed.
	///
	/// This is only honest for something drawn from instructions. Blowing a
	/// bitmap up to follow ⌘+ gives the blur that fitting it never did.
	public static func fitScale(image: CGSize, in pane: CGSize, zoom: CGFloat) -> CGFloat {
		guard image.width > 0, image.height > 0, pane.width > 0, pane.height > 0 else { return 1 }
		let room = min(pane.width / image.width, pane.height / image.height)
		return min(max(zoom, 0), room)
	}

	/// What to say a picture is: its size in pixels, and how much of it is
	/// showing when that is not all of it.
	public static func caption(image: CGSize, scale: CGFloat) -> String {
		let pixels = "\(Int(image.width)) × \(Int(image.height))"
		guard scale > 0, abs(scale - 1) > 0.005 else { return pixels }
		return "\(pixels) · \(Int((scale * 100).rounded()))%"
	}
}
