# Build with the toolchain the SDK belongs to

`ee8a5ba8a` · 2026-08-04

A toolchain manager puts its own `swift` in front on the PATH, and that one
is pinned to a release older than the SDK. The morning macOS 27 arrived it
could no longer compile Foundation, and every target here failed with "this
SDK is not supported by the compiler" — which reads as a problem with this
program and is not one.

`xcrun swift` asks the selected Xcode, which is the toolchain that shipped
the SDK.
