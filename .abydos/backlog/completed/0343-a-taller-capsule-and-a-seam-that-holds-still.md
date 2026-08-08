# A taller capsule, and a seam that holds still

`b5b4ac46c` · 2026-08-07

The capsule was asking to be taller and being ignored: a toolbar clamps its
items to the row's height whatever their intrinsic size says, so the only
height available was the frame already given, and four points of inset at each
end were spending it. One point instead, which leaves a hairline of air against
the capsule macOS paints behind the item. 21 points drawn becomes 27.

The seam is four points rather than two, and no longer sweeps. The movement was
standing in for a percentage nothing here reports, and something crawling in
the corner of the eye for as long as a build takes is worse than something
simply being there.
