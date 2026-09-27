# Abydos 0.23.2

## A 3D pane no longer takes the app down

Opening an STL, 3MF or OpenSCAD file in a 3D pane quit Abydos on every Mac
except the one it was built on, on Apple silicon and Intel alike. The viewer now
finds its shaders where the app ships them. If they are ever missing, the pane
says so and the rest of the window carries on.
