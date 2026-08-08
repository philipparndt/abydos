# Every Mach-O in the bundle is signed, not only the ones with a suffix

`e66a4634b` · 2026-08-05

Notarisation came back Invalid with three errors, all about one file:
Contents/MacOS/ideai-hook was not signed with a Developer ID, had no secure
timestamp, and had no hardened runtime. It is a second executable beside the
main one, and it is not a framework, an xpc service, a bundle, a dylib or a
.so — so the signing loop, which looks for those five, never saw it. Signing
the app around it seals it as it is rather than re-signing it, and it kept the
ad-hoc signature the bundler gives every build.

The helpers in Contents/MacOS are now signed too, all but the main executable,
which is signed last with the app itself.

And a check before Apple's: every executable in the bundle is asked whether it
carries a Developer ID and the hardened runtime, which takes a second. The same
question asked by uploading takes several minutes and comes back as a
submission id and a log you have to go and fetch.
