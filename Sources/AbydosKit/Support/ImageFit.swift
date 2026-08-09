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

	/// How large something is drawn in a pane that **scrolls**: fitted to the
	/// width, times the app's own zoom.
	///
	/// The rule above caps the zoom at what the pane can hold, because a picture
	/// that outgrows a pane which cannot scroll is a picture with its edges cut
	/// off. Where the pane scrolls, that cap is exactly wrong: ⌘+ would stop
	/// having any effect the moment the drawing filled the pane, which is
	/// precisely when somebody presses it. It fits to the *width* alone for the
	/// same reason — a tall diagram is read by scrolling down it, and fitting its
	/// height as well is how a page ends up as a stamp in the middle of a window.
	///
	/// One rule with two callers rather than two rules that agree today. The PDF
	/// pane worked this out first and `PdfPreview.scale` is now this function
	/// under its own name; the diagram pane wants the identical arithmetic, and a
	/// second copy of it is how ⌘+ comes to mean two things in one window.
	///
	/// The bounds are the ones that stop the arithmetic being silly: below a
	/// tenth the drawing is a dot, and above eight the renderer is being asked
	/// for a bitmap it should not be.
	public static func widthScale(width: CGFloat, paneWidth: CGFloat, zoom: CGFloat) -> CGFloat {
		guard width > 0, paneWidth > 0 else { return 1 }
		return clamp(min(1, paneWidth / width) * max(zoom, 0))
	}

	/// The same bounds, for a scale that was arrived at some other way — the
	/// drawing's own size, times the zoom.
	public static func clamp(_ scale: CGFloat) -> CGFloat { min(max(scale, 0.1), 8) }

	/// What to say a picture is: its size in pixels, and how much of it is
	/// showing when that is not all of it.
	public static func caption(image: CGSize, scale: CGFloat) -> String {
		let pixels = "\(Int(image.width)) × \(Int(image.height))"
		guard scale > 0, abs(scale - 1) > 0.005 else { return pixels }
		return "\(pixels) · \(Int((scale * 100).rounded()))%"
	}
}
