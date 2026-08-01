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
	};

	struct Varying {
		float4 position [[position]];
		float2 uv;
		// Where this pixel falls inside the glyph, 0 to 1. Outside that range
		// the pixel belongs to the cell but not to the glyph.
		float2 withinGlyph;
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
		// The glyph's own slot in the atlas. Samples are held inside it: the
		// atlas is packed tight, so a sample that wanders outside picks up
		// whichever letter happens to be next door, and one that wanders off
		// the edge comes back empty and takes the whole channel with it.
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

		// The quad covers the cell, or the glyph when there is one — a glyph may
		// reach outside its cell, as descenders and accents do.
		float hasGlyph = cell.uvSize.x > 0 ? 1.0 : 0.0;
		float2 origin = hasGlyph > 0 ? min(cell.origin, cell.glyphOrigin) : cell.origin;
		float2 far = hasGlyph > 0
			? max(cell.origin + cell.size, cell.glyphOrigin + cell.glyphSize)
			: cell.origin + cell.size;
		float2 pixel = mix(origin, far, corner);

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
		out.isColour = cell.isColour;
		out.bell = uniforms.bell;
		out.uvShift = cell.uvSize.x * 0.035 * uniforms.bell;
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

		if (hasGlyph && in.isColour > 0) {
			// An emoji brings its colours with it, already multiplied by its
			// own alpha, and sits on top of whatever the cell is painted.
			float4 glyph = colourAtlas.sample(atlasSampler, in.uv);
			float3 blended = glyph.rgb + in.background.rgb * (1.0 - glyph.a);
			return float4(blended, max(in.background.a, glyph.a));
		}

		// Chromatic aberration: the three channels are sampled a little apart,
		// so the glyph fringes red on one side and blue on the other. Done on
		// the coverage rather than on a finished image — each channel gets its
		// own idea of where the ink is, which is what the lens error actually
		// looks like, and it costs two extra samples instead of a second pass.
		if (hasGlyph && in.bell > 0.0) {
			float2 offset = float2(in.uvShift, 0.0);
			float2 uvR = clamp(in.uv + offset, in.uvMin, in.uvMax);
			float2 uvB = clamp(in.uv - offset, in.uvMin, in.uvMax);
			float coverageR = coverageAtlas.sample(atlasSampler, uvR).r;
			float coverageG = coverageAtlas.sample(atlasSampler, in.uv).r;
			float coverageB = coverageAtlas.sample(atlasSampler, uvB).r;

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
		float4 colour = mix(in.background, in.foreground, coverage * in.foreground.a);
		return float4(colour.rgb, max(in.background.a, coverage * in.foreground.a));
	}
	"""
}
