# The development pod: an image with a supervisor in it, and a chart that runs
# one.
#
# The image is assembled here rather than built by a daemon: it holds two
# static binaries, and requiring Docker for that means requiring Docker to
# work — which behind a corporate proxy is exactly what often does not.

ARCH        ?= arm64
# Which debuggers the image carries: full (both), go (Delve), native
# (gdbserver), jvm (a JRE and no debugger at all — a JVM given a flag is one).
# A pod only ever debugs one language, so a project can have the small one —
# 10 MB against 32, or 167 for the JVM, which is what a JRE costs.
#
# The tag is not derived from the variant: the editor asks for `:dev-jvm`, so
# a JVM image built to be imported locally needs VERSION=dev-jvm as well.
VARIANT     ?= full
DELVE       ?= v1.26.2
TAG         ?= $(REPOSITORY):$(VERSION)
OUT         := out
ROOTFS      := $(OUT)/rootfs_$(ARCH)_$(VARIANT)
IMAGE       := $(OUT)/ideai-devpod-$(ARCH)-$(VARIANT).tar

REPOSITORY  ?= pharndt/ideai-devpod
VERSION     ?= dev
PLATFORMS   ?= amd64 arm64

CLUSTER     ?= demo1
NAMESPACE   ?= devpod
RELEASE     ?= demo

# What the supervisor needs to know, and where its parts are.
IMAGE_ENV   := IDEAI_BINARY=/app/current,IDEAI_WORKDIR=/app,IDEAI_CONTROL_ADDR=:7999,IDEAI_DEBUG_ADDR=:2345,IDEAI_DLV=/usr/local/bin/dlv,IDEAI_JAVA=/opt/java/bin/java,SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: test
test: ## Run the supervisor's tests
	@cd supervisor && go test ./...

.PHONY: binaries
binaries: ## Cross-compile the supervisor and delve for linux/$(ARCH)
	@mkdir -p $(OUT)/linux_$(ARCH)
	@cd supervisor && GOOS=linux GOARCH=$(ARCH) CGO_ENABLED=0 \
		go build -trimpath -o ../$(OUT)/linux_$(ARCH)/ideai-supervisor .
	@GOOS=linux GOARCH=$(ARCH) CGO_ENABLED=0 go install github.com/go-delve/delve/cmd/dlv@$(DELVE)
	@cp "$$(go env GOPATH)/bin/linux_$(ARCH)/dlv" $(OUT)/linux_$(ARCH)/dlv
	@echo "==> $(OUT)/linux_$(ARCH)"

.PHONY: rootfs
rootfs: binaries ## Lay out the image's files (ARCH, VARIANT=full|go|native)
	@rm -rf $(ROOTFS)
	@mkdir -p $(ROOTFS)/usr/local/bin $(ROOTFS)/app $(ROOTFS)/tmp $(ROOTFS)/etc/ssl/certs
	@cp $(OUT)/linux_$(ARCH)/ideai-supervisor $(ROOTFS)/usr/local/bin/
	@cp /etc/ssl/cert.pem $(ROOTFS)/etc/ssl/certs/ca-certificates.crt
	@if [ "$(VARIANT)" = "jvm" ]; then ./tools/fetch-jre.sh $(ARCH) $(ROOTFS); fi
	@if [ "$(VARIANT)" != "native" ] && [ "$(VARIANT)" != "jvm" ]; then cp $(OUT)/linux_$(ARCH)/dlv $(ROOTFS)/usr/local/bin/; fi
	@if [ "$(VARIANT)" != "go" ] && [ "$(VARIANT)" != "jvm" ]; then ./tools/fetch-gdbserver.sh $(ARCH) $(ROOTFS); fi
	@printf '  %s image for linux/%s: %s\n' "$(VARIANT)" "$(ARCH)" "$$(du -sh $(ROOTFS) | cut -f1)"

.PHONY: mkimage
mkimage: ## Build the image assembler
	@cd tools/mkimage && go build -o ../../$(OUT)/mkimage .

.PHONY: image
image: rootfs mkimage ## Assemble the image tarball (no Docker needed)
	@./$(OUT)/mkimage -from $(ROOTFS) -out $(IMAGE) -tag "$(TAG)" -arch $(ARCH) \
		-env "$(IMAGE_ENV)"

# Everything in the image is a static binary — the supervisor and delve are
# both built with CGO_ENABLED=0 — so there is no base image to match and each
# architecture is one layer of two files. That is why this can push a real
# multi-architecture image without Docker or buildx: it is a few blob uploads
# and an index. Credentials come from `docker login`'s keychain entry, or from
# DOCKER_USERNAME and DOCKER_PASSWORD.
.PHONY: publish
publish: mkimage ## Push a multi-arch image (REPOSITORY, VERSION, VARIANT)
	@$(foreach arch,$(PLATFORMS),$(MAKE) --no-print-directory rootfs ARCH=$(arch) VARIANT=$(VARIANT) &&) true
	@./$(OUT)/mkimage -push "$(REPOSITORY):$(VERSION)" \
		$(foreach arch,$(PLATFORMS),-layer $(arch)=$(OUT)/rootfs_$(arch)_$(VARIANT)) \
		-env "$(IMAGE_ENV)"
	@echo "==> $(REPOSITORY):$(VERSION)"

.PHONY: publish-all
publish-all: ## Push the full image plus the per-language ones
	@$(MAKE) --no-print-directory publish VARIANT=full VERSION=$(VERSION)
	@$(MAKE) --no-print-directory publish VARIANT=go VERSION=$(VERSION)-go
	@$(MAKE) --no-print-directory publish VARIANT=native VERSION=$(VERSION)-native
	@$(MAKE) --no-print-directory publish VARIANT=jvm VERSION=$(VERSION)-jvm

.PHONY: import-k3c
import-k3c: image ## Put the image in a k3c cluster (CLUSTER=demo1)
	@cp $(IMAGE) $$HOME/.config/k3c/clusters/$(CLUSTER)/images/ideai-devpod.tar
	@echo "==> staged; k3s imports it on start. If the cluster is already up:"
	@echo "    k3c cluster stop $(CLUSTER) && k3c cluster start $(CLUSTER)"

.PHONY: import-k3d
import-k3d: image ## Put the image in a k3d cluster (CLUSTER=name)
	@k3d image import $(IMAGE) -c $(CLUSTER)

.PHONY: install
install: ## Install the chart (CLUSTER, NAMESPACE, RELEASE)
	@helm --kube-context $(KUBECONTEXT) upgrade --install $(RELEASE) chart/abydos-devpod \
		--namespace $(NAMESPACE) --create-namespace $(HELM_ARGS)

.PHONY: uninstall
uninstall: ## Remove the chart
	@helm --kube-context $(KUBECONTEXT) uninstall $(RELEASE) --namespace $(NAMESPACE)

.PHONY: clean
clean: ## Remove build output
	@rm -rf $(OUT)
