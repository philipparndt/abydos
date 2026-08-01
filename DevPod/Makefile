# The development pod: an image with a supervisor in it, and a chart that runs
# one.
#
# The image is assembled here rather than built by a daemon: it holds two
# static binaries, and requiring Docker for that means requiring Docker to
# work — which behind a corporate proxy is exactly what often does not.

ARCH        ?= arm64
DELVE       ?= v1.26.2
TAG         ?= ideai-devpod:dev
OUT         := out
ROOTFS      := $(OUT)/rootfs_$(ARCH)
IMAGE       := $(OUT)/ideai-devpod-$(ARCH).tar

CLUSTER     ?= demo1
NAMESPACE   ?= devpod
RELEASE     ?= demo

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

.PHONY: image
image: binaries ## Assemble the image tarball (no Docker needed)
	@cd tools/mkimage && go build -o ../../$(OUT)/mkimage .
	@rm -rf $(ROOTFS)
	@mkdir -p $(ROOTFS)/usr/local/bin $(ROOTFS)/app $(ROOTFS)/tmp $(ROOTFS)/etc/ssl/certs
	@cp $(OUT)/linux_$(ARCH)/ideai-supervisor $(OUT)/linux_$(ARCH)/dlv $(ROOTFS)/usr/local/bin/
	@cp /etc/ssl/cert.pem $(ROOTFS)/etc/ssl/certs/ca-certificates.crt
	@./$(OUT)/mkimage -from $(ROOTFS) -out $(IMAGE) -tag "$(TAG)" -arch $(ARCH) \
		-env "IDEAI_BINARY=/app/current,IDEAI_WORKDIR=/app,IDEAI_CONTROL_ADDR=:7999,IDEAI_DEBUG_ADDR=:2345,IDEAI_DLV=/usr/local/bin/dlv,SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"

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
	@helm --kube-context $(KUBECONTEXT) upgrade --install $(RELEASE) chart/ideai-devpod \
		--namespace $(NAMESPACE) --create-namespace $(HELM_ARGS)

.PHONY: uninstall
uninstall: ## Remove the chart
	@helm --kube-context $(KUBECONTEXT) uninstall $(RELEASE) --namespace $(NAMESPACE)

.PHONY: clean
clean: ## Remove build output
	@rm -rf $(OUT)
