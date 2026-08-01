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

		Varying out;
		// Pixels to clip space, with y running down the screen as the grid does.
		float2 unit = pixel / uniforms.viewport;
		out.position = float4(unit.x * 2.0 - 1.0, 1.0 - unit.y * 2.0, 0.0, 1.0);
		out.foreground = cell.foreground;
		out.background = cell.background;
		out.hasGlyph = hasGlyph;
		out.isColour = cell.isColour;

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

		float coverage = hasGlyph ? coverageAtlas.sample(atlasSampler, in.uv).r : 0.0;
		// Otherwise the glyph is coverage, not colour: the cell's own colours
		// show through it, which is what keeps a palette meaning what it says.
		float4 colour = mix(in.background, in.foreground, coverage);
		return float4(colour.rgb, max(in.background.a, coverage * in.foreground.a));
	}
	"""
}
