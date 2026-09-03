import Foundation

/// The shaders the terminal draws its grid with.
///
/// Kept as source and compiled when the renderer starts, rather than built by
/// the packaging script. It costs a few milliseconds once, and in exchange the
/// shaders cannot fall out of step with the code that feeds them, and a build
/// needs nothing but the Swift compiler.
enum TerminalShaders {
	static let source = """
	#include <metal_stdlib>
	using namespace metal;

	// One cell of the grid: where it goes, what colour it is, and which part of
	// the glyph atlas to stamp on it.
	struct CellInstance {
		float2 origin;      // top-left of the cell, in pixels
		float2 size;        // cell size in pixels
		float2 glyphOrigin; // top-left of the glyph, in pixels
		float2 glyphSize;
		float2 uvOrigin;    // where that glyph sits in the atlas
		float2 uvSize;
		float4 foreground;
		float4 background;
		// Whether the glyph carries its own colours, as an emoji does, rather
		// than coverage for the foreground to show through.
		float isColour;
	};

	struct Uniforms {
		float2 viewport;    // drawable size in pixels
		// How much of the bell is left, 1 at the moment it rang and 0 once it
		// has faded. Everything below is scaled by it, so the effect arrives at
		// full strength and leaves without a seam.
		float bell;
		// Seconds since the bell, which drives the wobble's movement. Kept
		// separate from the decay so the wobble keeps travelling while fading
		// rather than freezing as it dims.
		float bellTime;
		// Where the visible window sits in the document the cells were built
		// in, in points.
		//
		// Cells arrive in *document* coordinates — measured from a line the
		// terminal had rather than from the top of the window — and this is
		// what turns them into the window's. Subtracted here rather than on the
		// way in for one reason: it is the only part of a cell's position that
		// changes when nothing about the cell did. Output arriving at the
		// bottom of a view that follows it moves the whole picture by a row,
		// and so does a line falling out of history. Both used to mean building
		// every cell on screen again in order to move it; both are now this one
		// number.
		float2 scroll;
		// Which of the two passes over the cells this is: 0 paints every
		// cell's background inside its own rectangle, 1 paints every glyph
		// over all of them. In one pass the next cell's background landed on
		// the part of a glyph that reached past its cell.
		float pass;
	};

	struct Varying {
		float4 position [[position]];
		float2 uv;
		// Where this pixel falls inside the glyph, 0 to 1. Outside that range
		// the pixel belongs to the cell but not to the glyph.
		float2 withinGlyph;
		// And inside the cell's own rectangle, for the background pass to
		// stop at the cell's edge.
		float2 withinCell;
		float pass;
		float4 foreground;
		float4 background;
		float hasGlyph;
		float isColour;
		float bell;
		// How far apart to sample the three channels, in atlas coordinates.
		// Worked out here because only the vertex stage knows how wide this
		// glyph is in the atlas; a fixed offset would fringe a wide glyph
		// barely at all and a narrow one into mush.
		float uvShift;
		// The glyph's own slot in the atlas. A sample outside it reads as no
		// ink at all rather than being pulled back to the edge: the channel is
		// supposed to slide off the glyph, and clamping instead smears the
		// edge pixel sideways, which looks like nothing much.
		float2 uvMin;
		float2 uvMax;
	};

	// Two triangles from six vertex ids, so nothing has to be uploaded per
	// corner — only the cells themselves.
	constant float2 corners[6] = {
		float2(0, 0), float2(1, 0), float2(0, 1),
		float2(1, 0), float2(1, 1), float2(0, 1),
	};

	vertex Varying cellVertex(
		uint vertexID [[vertex_id]],
		uint instanceID [[instance_id]],
		constant CellInstance *cells [[buffer(0)]],
		constant Uniforms &uniforms [[buffer(1)]]
	) {
		CellInstance cell = cells[instanceID];
		float2 corner = corners[vertexID];

		// Out of the document and into the window, before anything else reads a
		// position: the wobble below is a function of where a row is on screen,
		// and everything after it works in the window's coordinates as it
		// always did.
		cell.origin -= uniforms.scroll;
		cell.glyphOrigin -= uniforms.scroll;

		// The quad covers the cell, or the glyph when there is one — a glyph may
		// reach outside its cell, as descenders and accents do.
		float hasGlyph = cell.uvSize.x > 0 ? 1.0 : 0.0;
		float2 origin = hasGlyph > 0 ? min(cell.origin, cell.glyphOrigin) : cell.origin;
		float2 far = hasGlyph > 0
			? max(cell.origin + cell.size, cell.glyphOrigin + cell.glyphSize)
			: cell.origin + cell.size;
		float2 pixel = mix(origin, far, corner);
		// Where this pixel is inside the cell's own rectangle, so the
		// background pass can stop at the cell's edge: the quad reaches as far
		// as the glyph does, and a coloured cell must not colour the neighbour
		// its glyph leans into. Taken before the wobble, so the fill moves with
		// the quad rather than sliding inside it.
		float2 withinCell = (pixel - cell.origin) / max(cell.size, float2(1.0));

		// A tracking error: rows slip sideways by an amount that varies down
		// the screen and crawls upward, the way a worn tape does. Cheap here —
		// the geometry moves, so nothing has to be re-sampled to make it.
		if (uniforms.bell > 0.0) {
			float wobble =
				sin(pixel.y * 0.055 + uniforms.bellTime * 9.0) * 1.6
				+ sin(pixel.y * 0.013 - uniforms.bellTime * 3.0) * 2.6;
			pixel.x += wobble * uniforms.bell;
		}

		Varying out;
		// Pixels to clip space, with y running down the screen as the grid does.
		float2 unit = pixel / uniforms.viewport;
		out.position = float4(unit.x * 2.0 - 1.0, 1.0 - unit.y * 2.0, 0.0, 1.0);
		out.foreground = cell.foreground;
		out.background = cell.background;
		out.hasGlyph = hasGlyph;
		out.withinCell = withinCell;
		out.pass = uniforms.pass;
		out.isColour = cell.isColour;
		out.bell = uniforms.bell;
		out.uvShift = cell.uvSize.x * 0.22 * uniforms.bell;
		out.uvMin = cell.uvOrigin;
		out.uvMax = cell.uvOrigin + cell.uvSize;

		// The quad covers the cell and the glyph together, so some of it lies
		// outside the glyph. Those pixels must not be sampled: they would land
		// outside the glyph's place in the atlas and pick up whatever was
		// packed beside it, which shows as slivers of other letters.
		float2 withinGlyph = (pixel - cell.glyphOrigin) / max(cell.glyphSize, float2(1.0));
		out.withinGlyph = withinGlyph;
		out.uv = cell.uvOrigin + withinGlyph * cell.uvSize;
		return out;
	}

	fragment float4 cellFragment(
		Varying in [[stage_in]],
		texture2d<float> coverageAtlas [[texture(0)]],
		texture2d<float> colourAtlas [[texture(1)]]
	) {
		constexpr sampler atlasSampler(filter::nearest, address::clamp_to_zero);

		bool insideGlyph = all(in.withinGlyph >= 0.0) && all(in.withinGlyph <= 1.0);
		bool hasGlyph = in.hasGlyph > 0 && insideGlyph;

		// **Two passes, because the cells are drawn in order.** A glyph may
		// reach past its cell — a descender, an accent, or a symbol nearly two
		// cells wide from a fallback font — and in a single pass the next
		// cell's opaque background was painted after it and over it, which cut
		// every such glyph off at the cell's edge. swift-testing's pass and
		// fail marks came out as their left halves. So the first pass paints
		// backgrounds only, each inside its own cell, and the second paints
		// every glyph's box over all of them: the cell's own background under
		// the ink, so a coloured cell's colour follows its glyph wherever the
		// glyph reaches — a black diamond on yellow stays a black diamond on
		// yellow into the next cell, rather than turning black on black there
		// — and the glyph's coverage over it.
		bool insideCell = all(in.withinCell >= 0.0) && all(in.withinCell <= 1.0);
		if (in.pass < 0.5) {
			return insideCell ? in.background : float4(0.0);
		}
		// The box the glyph pass paints the background into: the full height
		// of the row, across the cell and as far sideways as the glyph reaches.
		// The glyph's own box is only as tall as its ink, and painting that
		// alone left dark strips above and below the overhang of a wide symbol
		// on a coloured cell. A descender below the row gets ink and no box.
		// A cell with no glyph has nothing to say in this pass — and must say
		// nothing: letting it paint its own rectangle here put the neighbour's
		// background back over the overhang, which was the fault being fixed.
		if (in.hasGlyph == 0.0) { return float4(0.0); }
		// Inside the cell the first pass has painted the background already —
		// and the underline or strikethrough over it, which painting the cell
		// again here buried. So inside the cell this pass adds ink alone, and
		// only the overhang, the part of the row beyond the cell that the
		// glyph reaches, gets the cell's colour under the ink.
		bool inRow = in.withinCell.y >= 0.0 && in.withinCell.y <= 1.0;
		bool acrossGlyph = in.withinGlyph.x >= 0.0 && in.withinGlyph.x <= 1.0;
		bool inOverhang = inRow && acrossGlyph && !insideCell;
		if (!hasGlyph) {
			return inOverhang ? in.background : float4(0.0);
		}

		if (in.isColour > 0) {
			// An emoji brings its colours with it, already multiplied by its
			// own alpha. Inside the cell it is divided back out for the
			// pipeline's straight-alpha blend, so it sits on what is there; in
			// an overhang it sits on the cell's colour.
			float4 glyph = colourAtlas.sample(atlasSampler, in.uv);
			if (!inOverhang) { return float4(glyph.rgb / max(glyph.a, 0.0001), glyph.a); }
			float3 blended = glyph.rgb + in.background.rgb * (1.0 - glyph.a);
			return float4(blended, max(in.background.a, glyph.a));
		}

		// Chromatic aberration: the three channels are sampled a little apart,
		// so the glyph fringes red on one side and blue on the other. Done on
		// the coverage rather than on a finished image — each channel gets its
		// own idea of where the ink is, which is what the lens error actually
		// looks like, and it costs two extra samples instead of a second pass.
		if (in.bell > 0.0) {
			// Each channel reads the glyph from a slightly different place, and
			// reads nothing where that lands outside the glyph — which is what
			// makes the letter separate into red and blue ghosts rather than
			// merely blurring.
			float2 offset = float2(in.uvShift, 0.0);
			float2 uvR = in.uv + offset;
			float2 uvB = in.uv - offset;
			float insideR = all(uvR >= in.uvMin) && all(uvR <= in.uvMax) ? 1.0 : 0.0;
			float insideB = all(uvB >= in.uvMin) && all(uvB <= in.uvMax) ? 1.0 : 0.0;

			float coverageR = coverageAtlas.sample(atlasSampler, uvR).r * insideR;
			float coverageG = coverageAtlas.sample(atlasSampler, in.uv).r;
			float coverageB = coverageAtlas.sample(atlasSampler, uvB).r * insideB;

			float alpha = in.foreground.a;
			float3 colour = float3(
				mix(in.background.r, in.foreground.r, coverageR * alpha),
				mix(in.background.g, in.foreground.g, coverageG * alpha),
				mix(in.background.b, in.foreground.b, coverageB * alpha)
			);
			float coverage = max(coverageR, max(coverageG, coverageB));
			return float4(colour, max(in.background.a, coverage * alpha));
		}

		float coverage = hasGlyph ? coverageAtlas.sample(atlasSampler, in.uv).r : 0.0;
		// Otherwise the glyph is coverage, not colour: the cell's own colours
		// show through it, which is what keeps a palette meaning what it says.
		//
		// The foreground's own alpha counts too. Dim text is drawn by asking for
		// a faded foreground, and ignoring that here made it identical to
		// ordinary text — which is how an editor's greyed-out suggestion came
		// out as bright as what had been typed.
		// The cell's background under the ink across the whole glyph box, so
		// the colour follows the glyph past the cell's edge. Over a picture the
		// background is transparent and only the ink is painted.
		// Ink alone everywhere but the overhang: inside the cell over what the
		// first pass painted, below the row for a descender.
		if (!inOverhang) { return float4(in.foreground.rgb, coverage * in.foreground.a); }
		float4 colour = mix(in.background, in.foreground, coverage * in.foreground.a);
		return float4(colour.rgb, max(in.background.a, coverage * in.foreground.a));
	}

	// One picture placed on the grid. Its own quad and its own texture, rather
	// than anything to do with the glyph atlas: a picture is arbitrarily large,
	// arrives and leaves at a program's whim, and there are only ever a handful
	// on screen — so packing them beside the letters would buy nothing and cost
	// a repack every time one arrived.
	struct ImageInstance {
		float2 origin;      // top-left on screen, in pixels
		float2 size;
		float2 uvOrigin;    // the part of the picture being shown
		float2 uvSize;
	};

	struct ImageVarying {
		float4 position [[position]];
		float2 uv;
	};

	vertex ImageVarying imageVertex(
		uint vertexID [[vertex_id]],
		constant ImageInstance &image [[buffer(0)]],
		constant Uniforms &uniforms [[buffer(1)]]
	) {
		float2 corner = corners[vertexID];
		float2 pixel = image.origin + image.size * corner;

		// The same tracking error the text gets. A picture that stayed rock
		// steady while the letters around it wobbled would look like it was not
		// part of the same screen.
		if (uniforms.bell > 0.0) {
			float wobble =
				sin(pixel.y * 0.055 + uniforms.bellTime * 9.0) * 1.6
				+ sin(pixel.y * 0.013 - uniforms.bellTime * 3.0) * 2.6;
			pixel.x += wobble * uniforms.bell;
		}

		ImageVarying out;
		float2 unit = pixel / uniforms.viewport;
		out.position = float4(unit.x * 2.0 - 1.0, 1.0 - unit.y * 2.0, 0.0, 1.0);
		out.uv = image.uvOrigin + image.uvSize * corner;
		return out;
	}

	fragment float4 imageFragment(
		ImageVarying in [[stage_in]],
		texture2d<float> picture [[texture(0)]]
	) {
		// Linear rather than nearest: a picture is placed on a cell grid and so
		// is usually being scaled by some fraction, and nearest sampling turns
		// that into visible stair-stepping along every edge.
		constexpr sampler pictureSampler(filter::linear, address::clamp_to_edge);
		return picture.sample(pictureSampler, in.uv);
	}
	"""
}
