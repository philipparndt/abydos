```scad
module cube(size, center=false)
```
---


Creates a cube in the first octant. When center is true, the cube is
centered on the origin. Argument names are optional if given in the
order shown here.

```scad
cube(size = [ x, y, z ], center = true / false);
cube(size = x, center = true / false);

```

**parameters**:

**size**

single value, cube with all sides this length

3 value array [x,y,z], cube with dimensions x, y and z.

**center**

**false** (default), 1st (positive) octant, one corner at (0,0,0)

**true**, cube is centered at (0,0,0)

```scad
default values: cube();
yields : cube(size = [ 1, 1, 1 ], center = false);

```

**examples**:

<a href="https://en.wikibooks.org/wiki/File:OpenSCAD_example_Cube.jpg" class="image"><img src=https://upload.wikimedia.org/wikipedia/commons/thumb/5/55/OpenSCAD_example_Cube.jpg/150px-OpenSCAD_example_Cube.jpg width=150 height=143/></a>

```scad
// equivalent scripts for this example
cube(size = 18);
cube(18);
cube([ 18, 18, 18 ]);
.
cube(18, false);
cube([ 18, 18, 18 ], false);
cube([ 18, 18, 18 ], center = false);
cube(size = [ 18, 18, 18 ], center = false);
cube(center = false, size = [ 18, 18, 18 ]);

```

<a href="https://en.wikibooks.org/wiki/File:OpenSCAD_example_Box.jpg" class="image"><img src=https://upload.wikimedia.org/wikipedia/commons/thumb/2/29/OpenSCAD_example_Box.jpg/150px-OpenSCAD_example_Box.jpg width=150 height=126/></a>

```scad
// equivalent scripts for this example
cube([ 18, 28, 8 ], true);
box = [ 18, 28, 8 ];
cube(box, true);

```

