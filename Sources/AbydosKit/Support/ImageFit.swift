import Foundation

/// Where a picture goes in the pane showing it.
///
/// Kept out of the view so the rule can be checked without a window: a picture
/// larger than the pane is fitted to it, and one smaller is left at its own
/// size. Blowing a sixteen-pixel icon up to fill a window is a blurry lie about
/// what is in the file, and it is the first thing anybody notices.
///
/// That is what a picture is *opened* at, and it is a default rather than a
/// ceiling. Somebody who asks for 400% is asking to see the pixels, and 0532 is
/// what it cost to have no way of asking: the pane fitted every picture and the
/// one gesture that left the fit drew it at its own size inside a document
/// pinned to the pane, so the picture was cropped instead of pannable. What the
/// zoom is bounded by is `clamp`, and where it is applied is `zoomed`.
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

	/// How large a picture is drawn in a pane that **scrolls** and shows all of
	/// it: fitted in both directions, times the app's own zoom.
	///
	/// The width rule below is for something that is *read*. A PDF and a diagram
	/// are scrolled down, so their height is not a constraint and fitting it as
	/// well is how a page ends up a stamp in the middle of a window. A picture is
	/// not read, it is looked at, and the question anybody opening one has is
	/// "what is in this file" — so 1× is the whole of it, and a portrait
	/// photograph opens as a photograph rather than as the top third of one.
	///
	/// That is the only thing a picture wants differently, and it is the *basis*
	/// alone. Everything after the basis — the zoom multiplying it, and the
	/// bounds — is `zoomed`, shared with the width rule, because ⌘+ must not come
	/// to mean two things in one window.
	///
	/// **Uncapped, which is the whole of item 0532.** There used to be a second
	/// rule here that took `min(zoom, room)`: the zoom capped at what the pane
	/// could hold, for a pane that could not scroll. Nothing is that pane any
	/// more — the PDF pane scrolls, the diagram pane scrolls, and the picture pane
	/// turned out only to *look* as though it did. The cap is exactly wrong for
	/// all three, because ⌘+ stops having any effect the moment the picture fills
	/// the pane, which is precisely when somebody presses it. So the capped rule
	/// is gone rather than left beside this one: two answers to ⌘+ in one file is
	/// how the wrong one comes to be called.
	public static func paneScale(image: CGSize, in pane: CGSize, zoom: CGFloat) -> CGFloat {
		guard image.width > 0, image.height > 0, pane.width > 0, pane.height > 0 else { return 1 }
		return zoomed(fitScale(image: image, in: pane), by: zoom)
	}

	/// The app's zoom on a basis somebody else worked out, within the bounds.
	///
	/// The one place the zoom multiplies, so the three panes that follow ⌘+ agree
	/// about what pressing it does and about where it stops. A negative zoom is
	/// nothing anybody can mean, so it is read as none.
	public static func zoomed(_ basis: CGFloat, by zoom: CGFloat) -> CGFloat {
		clamp(basis * max(zoom, 0))
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
		return zoomed(min(1, paneWidth / width), by: zoom)
	}

	/// How large the thing a scrolling pane scrolls has to be, for a picture
	/// being drawn at `picture` size in a hole of `visible` size.
	///
	/// The picture plus its margin, or the hole — whichever is larger in each
	/// direction — so a small picture is centred in the pane and a large one is
	/// pannable in exactly the direction it overflows.
	///
	/// **This is the line item 0532 was about.** The picture pane had a scroll
	/// view with both scrollers and a document resized to the *content* size on
	/// every frame change, so the document was never larger than the hole it was
	/// seen through and the scrollers never had anything to scroll. A screenshot
	/// at its own size was therefore cropped rather than pannable, which is worse
	/// than fitting it and is the opposite of what a scroll view is for.
	public static func documentSize(picture: CGSize, visible: CGSize, margin: CGFloat) -> CGSize {
		CGSize(
			width: max(visible.width, picture.width + margin * 2),
			height: max(visible.height, picture.height + margin * 2)
		)
	}

	/// The same bounds, for a scale that was arrived at some other way — the
	/// drawing's own size, times the zoom.
	public static func clamp(_ scale: CGFloat) -> CGFloat { min(max(scale, 0.1), 8) }

	/// What to say a picture is: its size in pixels, how large it is being drawn,
	/// and whether that size was chosen or arrived at by fitting the pane.
	///
	/// The percentage is of the picture's **own stated size**, which is the size
	/// in points a file declares itself to be: 100% of a 144-dpi screenshot puts
	/// one of its pixels on one pixel of a Retina screen, and 100% of a 72-dpi
	/// picture puts one of its pixels on one point. That is what every viewer on
	/// this machine means by 100% and what the PDF pane already meant by it, and
	/// it is why the pixel count is said as well: the percentage alone cannot tell
	/// somebody how much detail is in the file.
	///
	/// `Fit` is said out loud for the same reason the diagram pane says it: 100%
	/// while fitted and 100% at the picture's own size are the same number
	/// arrived at two different ways, and only one of them is still 100% when the
	/// window is made narrower. A size somebody chose says only the number, and a
	/// picture at exactly its own size says nothing at all — there is no
	/// percentage worth reading there.
	public static func caption(image: CGSize, scale: CGFloat, fitted: Bool = false) -> String {
		let pixels = "\(Int(image.width)) × \(Int(image.height))"
		guard scale > 0 else { return pixels }
		let percent = "\(Int((scale * 100).rounded()))%"
		if fitted { return "\(pixels) · Fit · \(percent)" }
		guard abs(scale - 1) > 0.005 else { return pixels }
		return "\(pixels) · \(percent)"
	}
}
