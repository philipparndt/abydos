# ideai
#
# Common entry points. `make` builds and launches the app.

APP     := build/ideai.app
BINARY  := $(APP)/Contents/MacOS/ideai
CONFIG  ?= release

.DEFAULT_GOAL := run

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: build
build: devpod-chart ## Build the .app bundle (CONFIG=debug|release, default release)
	@Scripts/bundle.sh $(CONFIG)

.PHONY: run
run: build ## Build and launch the app
	@echo "==> Launching $(APP)"
	@open $(APP)

.PHONY: dev
dev: ## Build debug and run in the foreground, with logs on the terminal
	@$(MAKE) build CONFIG=debug
	@echo "==> Running $(BINARY) (ctrl-c to stop)"
	@$(BINARY)

.PHONY: open
open: build ## Build and open a specific project: make open PROJECT=~/dev/foo
	@test -n "$(PROJECT)" || { echo "usage: make open PROJECT=<dir>"; exit 1; }
	@open -a $(abspath $(APP)) $(PROJECT)

.PHONY: test
test: ## Run the test suite
	@swift test

.PHONY: perf
perf: ## Run the performance suite in release and print timings
	@swift test -c release --filter PerformanceTests 2>&1 | grep -E '^PERF|Test run with'

.PHONY: fire
fire: ## Burn the DOOM fire in this terminal, whichever it is (SECONDS=20)
	@swift build -c release --product firebench
	@.build/release/firebench --mode fire --seconds $(or $(SECONDS),20)

.PHONY: matrix
matrix: ## The same benchmark on the glyph cache instead of the colours
	@swift build -c release --product firebench
	@.build/release/firebench --mode matrix --seconds $(or $(SECONDS),20)

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
release: build ## Sign with Developer ID, notarise and package a DMG
	@Scripts/release.sh

.PHONY: sign-check
sign-check: ## Show the signing identity and notary profile the release will use
	@security find-identity -v -p codesigning | grep "Developer ID Application" \
		|| echo "no Developer ID Application certificate in the keychain"
	@xcrun notarytool history --keychain-profile $(or $(NOTARY_PROFILE),notarytool) \
		>/dev/null 2>&1 && echo "  notary profile: $(or $(NOTARY_PROFILE),notarytool) ✓" \
		|| echo "  notary profile $(or $(NOTARY_PROFILE),notarytool) is not stored yet — see Scripts/release.sh"

.PHONY: install
install: build ## Copy the app into /Applications
	@rm -rf /Applications/ideai.app
	@cp -R $(APP) /Applications/
	@echo "==> Installed /Applications/ideai.app"

.PHONY: install-cli
install-cli: ## Put the `ideai` command on the PATH (PREFIX=/usr/local)
	@mkdir -p $(or $(PREFIX),/usr/local)/bin
	@install -m 755 Scripts/ideai $(or $(PREFIX),/usr/local)/bin/ideai
	@echo "==> Installed $(or $(PREFIX),/usr/local)/bin/ideai"

# The development pod has a Makefile of its own; these are the two goals
# somebody standing in the repository root wants from it.
# The app ships the chart, so the copy it ships has to be the chart.
.PHONY: devpod-chart
devpod-chart: ## Copy the dev pod chart into the app's resources
	@rsync -a --delete DevPod/chart/ideai-devpod/ Sources/ideai/Resources/devpod-chart/
	@echo "==> Synced the dev pod chart"

.PHONY: devpod-image
devpod-image: ## Build the dev pod image tarball (ARCH=arm64|amd64)
	@$(MAKE) -C DevPod image

.PHONY: devpod-publish
devpod-publish: ## Push a multi-arch dev pod image (REPOSITORY, VERSION)
	@$(MAKE) -C DevPod publish

.PHONY: clean
clean: ## Remove build output
	@rm -rf .build build
	@echo "==> Cleaned"
