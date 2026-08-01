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
build: ## Build the .app bundle (CONFIG=debug|release, default release)
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
fire: ## Run the DOOM fire benchmark in the app's terminal (SECONDS=20)
	@$(MAKE) build
	@swift build -c release --product firebench
	@mkdir -p build
	@rm -f build/firebench.txt
	@echo "==> Burning for $(or $(SECONDS),20)s"
	@$(BINARY) --open $(or $(PROJECT),$(CURDIR)) --terminal \
		--run "$(CURDIR)/.build/release/firebench --seconds $(or $(SECONDS),20) --report $(CURDIR)/build/firebench.txt" \
		--screenshot build/firebench.png --delay $$(( $(or $(SECONDS),20) + 7 )) 2>/dev/null || true
	@cat build/firebench.txt 2>/dev/null || echo "no result — see build/firebench.png"
	@echo "==> build/firebench.png"
	@echo "    For a full-screen figure, run it in a maximised terminal yourself:"
	@echo "    .build/release/firebench --seconds 20"

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

.PHONY: install
install: build ## Copy the app into /Applications
	@rm -rf /Applications/ideai.app
	@cp -R $(APP) /Applications/
	@echo "==> Installed /Applications/ideai.app"

.PHONY: clean
clean: ## Remove build output
	@rm -rf .build build
	@echo "==> Cleaned"
