# Abydos
#
# Common entry points. `make` builds and launches the app.

APP     := build/Abydos.app
BINARY  := $(APP)/Contents/MacOS/Abydos
CONFIG  ?= release

# The verbs somebody types while working build debug; the ones that produce
# something to keep build release.
#
# Measured, after touching one file: 98 seconds optimised against 9.2 not, and
# `run` and `open` were paying it every time somebody wanted to look at the
# app. `build` and `install` keep release, because what they make is a thing to
# use rather than a thing to try — an unoptimised Metal renderer and terminal
# emulator are slower to *use*, not merely slower to start.
#
# `$(origin CONFIG)` rather than a plain default so that saying it out loud
# still works: `make run CONFIG=release` builds release, and only an unsaid
# CONFIG becomes debug here.
DEV_CONFIG = $(if $(filter command line,$(origin CONFIG)),$(CONFIG),debug)

# Xcode's Swift, not whichever one is first on the PATH.
#
# A toolchain manager such as swiftly puts its own `swift` in front, and that
# one is pinned to a release older than the SDK: on the morning macOS 27
# arrived it could no longer compile Foundation, and every target here failed
# with "this SDK is not supported by the compiler" rather than anything to do
# with this program. `xcrun` asks the selected Xcode, which is the toolchain
# the SDK belongs to.
SWIFT   := xcrun swift

# How many compiler processes a build may run at once.
#
# SwiftPM takes every core by default, which is right for one build on an idle
# machine and wrong for everything else: two cold builds side by side put this
# project's ~150 files into ~140 concurrent `swift-frontend` processes, 26 GB
# resident, and a load average in the hundreds — measured, on a ten-core
# machine, while somebody was trying to work on it.
#
# Four is polite rather than optimal. Say otherwise when a build is the only
# thing happening and speed is what matters:
#
#     make build JOBS=10        # or any number, or JOBS= for SwiftPM's default
JOBS    ?= 4
SWIFT_JOBS := $(if $(JOBS),-j $(JOBS),)

.DEFAULT_GOAL := run

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: build
build: devpod-chart ## Build the .app bundle (CONFIG=debug|release, BUNDLE_ID=... to override the identifier)
	@BUNDLE_ID="$(BUNDLE_ID)" SWIFT_JOBS="$(SWIFT_JOBS)" Scripts/bundle.sh $(CONFIG)

.PHONY: run
run: ## Build and launch the app (debug; CONFIG=release to override)
	@$(MAKE) build CONFIG=$(DEV_CONFIG)
	@echo "==> Launching $(APP)"
	@open $(APP)

.PHONY: dev
dev: ## Build debug and run in the foreground, with logs on the terminal
	@$(MAKE) build CONFIG=$(DEV_CONFIG)
	@echo "==> Running $(BINARY) (ctrl-c to stop)"
	@$(BINARY)

.PHONY: open
open: ## Build and open a project (debug; CONFIG=release to override): make open PROJECT=~/dev/foo
	@test -n "$(PROJECT)" || { echo "usage: make open PROJECT=<dir>"; exit 1; }
	@$(MAKE) build CONFIG=$(DEV_CONFIG)
	@open -a $(abspath $(APP)) $(PROJECT)

# No test run may go on for ever. The suite is a couple of minutes on a cold
# build and seconds on a warm one, so five is a ceiling nothing legitimate
# reaches — and a run that does reach it is a hang, which is worth being told
# about rather than waited on.
TEST_TIMEOUT ?= 300

.PHONY: test
test: ## Run the test suite (FILTER=name, TEST_TIMEOUT=seconds)
	@Scripts/run-tests.sh $(TEST_TIMEOUT) $(SWIFT) test $(SWIFT_JOBS) $(if $(FILTER),--filter $(FILTER))

.PHONY: perf
perf: ## Run the performance suite in release and print timings
	@$(SWIFT) test $(SWIFT_JOBS) -c release --filter PerformanceTests 2>&1 | grep -E '^PERF|Test run with'

.PHONY: fire
fire: ## Burn the DOOM fire in this terminal (SECONDS=20, FPS=60 to just watch)
	@$(SWIFT) build $(SWIFT_JOBS) -c release --product firebench
	@.build/release/firebench --mode fire --seconds $(or $(SECONDS),20) $(if $(FPS),--fps $(FPS))

.PHONY: matrix
matrix: ## The same on the glyph cache (SECONDS=20, FPS=60 to just watch)
	@$(SWIFT) build $(SWIFT_JOBS) -c release --product firebench
	@.build/release/firebench --mode matrix --seconds $(or $(SECONDS),20) $(if $(FPS),--fps $(FPS))

# The documentation's pictures, taken from the examples repository rather than
# staged: every shot is the app doing the thing the page claims, on a project
# anybody can clone. EXAMPLES, OUT, SIZE and SHOT are all overridable.
.PHONY: screenshots
screenshots: ## Photograph the app for the docs (EXAMPLES=../ideai-examples, SHOT=one)
	@$(MAKE) --no-print-directory build CONFIG=debug
	@Scripts/screenshots.sh

.PHONY: shot
shot: ## Render the window to a PNG without Screen Recording permission
	@$(MAKE) build CONFIG=debug
	@mkdir -p build
	@$(BINARY) --open $(or $(PROJECT),$(CURDIR)) --expand \
		--screenshot build/screenshot.png --delay 3 2>/dev/null
	@echo "==> build/screenshot.png"

.PHONY: grammars
icon: ## Regenerate the app icon from Scripts/make-icon.py
	@python3 Scripts/make-icon.py

grammars: ## Re-vendor the grammars whose upstream manifests are broken
	@Scripts/vendor-grammars.sh

.PHONY: xcode
xcode: ## Generate the Xcode project and open it (needs xcodegen)
	@command -v xcodegen >/dev/null || { echo "xcodegen not found — brew install xcodegen"; exit 1; }
	@xcodegen generate
	@open ideai.xcodeproj

.PHONY: xcode-build
xcode-build: ## Build the app the way Xcode does, as a check on the package
	@command -v xcodegen >/dev/null || { echo "xcodegen not found — brew install xcodegen"; exit 1; }
	@xcodegen generate
	@xcodebuild build -project ideai.xcodeproj -scheme ideai \
		-destination 'platform=macOS' -derivedDataPath build/xcode | tail -3

.PHONY: release
release: ## Sign with Developer ID, notarise and package a DMG
	@$(MAKE) --no-print-directory build PIN_UUID=0
	@Scripts/release.sh

# The whole of cutting a release, in the one order that keeps the tag and the
# download honest: stamp the version, tag it, build *from* the tag, notarise,
# then upload. See Scripts/publish-release.sh for why each step is where it is.
.PHONY: release-publish
release-publish: ## Tag VERSION, build, notarise and upload the signed DMG to GitHub
	@test -n "$(VERSION)" || { echo "usage: make release-publish VERSION=0.2.0"; exit 1; }
	@Scripts/publish-release.sh $(VERSION)

.PHONY: sign-check
sign-check: ## Show the signing identity and notary profile the release will use
	@security find-identity -v -p codesigning | grep "Developer ID Application" \
		|| echo "no Developer ID Application certificate in the keychain"
	@xcrun notarytool history --keychain-profile $(or $(NOTARY_PROFILE),notarytool) \
		>/dev/null 2>&1 && echo "  notary profile: $(or $(NOTARY_PROFILE),notarytool) ✓" \
		|| echo "  notary profile $(or $(NOTARY_PROFILE),notarytool) is not stored yet — see Scripts/release.sh"

.PHONY: install
install: build ## Copy the app into /Applications
	@Scripts/install.sh $(APP)

.PHONY: install-cli
install-cli: ## Put the `abydos` commands on the PATH (PREFIX=/usr/local)
	@mkdir -p $(or $(PREFIX),/usr/local)/bin
	@install -m 755 Scripts/abydos $(or $(PREFIX),/usr/local)/bin/abydos
	@echo "==> Installed $(or $(PREFIX),/usr/local)/bin/abydos"
	@install -m 755 Scripts/abydos-icat $(or $(PREFIX),/usr/local)/bin/abydos-icat
	@echo "==> Installed $(or $(PREFIX),/usr/local)/bin/abydos-icat"
	@$(SWIFT) build $(SWIFT_JOBS) -c release --product firebench >/dev/null
	@install -m 755 .build/release/firebench $(or $(PREFIX),/usr/local)/bin/abydos-bench
	@echo "==> Installed $(or $(PREFIX),/usr/local)/bin/abydos-bench"
	@# Also as `icat`, but only when nothing else answers to it: kitty ships
	@# one, and taking a name somebody's tools already use is not this app's
	@# business.
	@if command -v icat >/dev/null 2>&1; then \
		echo "    icat is already something else; use abydos-icat"; \
	else \
		ln -sf abydos-icat $(or $(PREFIX),/usr/local)/bin/icat; \
		echo "    also as icat, since nothing else answered to it"; \
	fi

# The development pod has a Makefile of its own; these are the two goals
# somebody standing in the repository root wants from it.
# The app ships the chart, so the copy it ships has to be the chart.
.PHONY: devpod-chart
devpod-chart: ## Copy the dev pod chart into the app's resources
	@rsync -a --delete DevPod/chart/abydos-devpod/ Sources/AbydosApp/Resources/devpod-chart/
	@echo "==> Synced the dev pod chart"

.PHONY: devpod-image
devpod-image: ## Build the dev pod image tarball (ARCH=arm64|amd64)
	@$(MAKE) -C DevPod image

.PHONY: devpod-publish
devpod-publish: ## Push a multi-arch dev pod image (REPOSITORY, VERSION)
	@$(MAKE) -C DevPod publish

# The images a tool can come from, for a machine that would rather not install
# the toolchain behind a language server. Built with a real builder rather than
# assembled the way the pod image is: gopls needs the Go toolchain beside it, so
# there is a base image under it and no way around a build.
.PHONY: tool-image-gopls
tool-image-gopls: ## Build the gopls image (TAG=abydos/gopls:dev)
	@docker build -t $(or $(TAG),abydos/gopls:dev) ToolImages/gopls
	@echo "==> $(or $(TAG),abydos/gopls:dev)"
	@echo "    name it for a project in .abydos/tools.json: {\"gopls\": \"$(or $(TAG),abydos/gopls:dev)\"}"

# Publishing one of them takes the pod's two words — REPOSITORY and VERSION —
# and one more. TOOL, because each tool is its own repository: a goal that
# looped over ToolImages/*/Dockerfile would push six different servers to
# whichever one name it was given. The default repository is named after the
# tool for the same reason.
.PHONY: toolimage-publish
toolimage-publish: ## Push a multi-arch tool image (TOOL=gopls, REPOSITORY, VERSION; DRY_RUN=1 to build both and stop)
	@Scripts/publish-tool-image.sh $(or $(TOOL),gopls) \
		$(or $(REPOSITORY),pharndt/abydos-$(or $(TOOL),gopls)) $(or $(VERSION),dev)

.PHONY: clean
clean: ## Remove build output
	@rm -rf .build build
	@echo "==> Cleaned"
