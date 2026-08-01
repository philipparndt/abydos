# The image a development pod runs.
#
# It contains no application: the application is pushed into it, which is the
# whole point. What it does contain is the supervisor that receives one and the
# debugger that can be put in front of it, so a pod is ready to run whatever
# somebody just built without another image being made.
#
# Debian rather than distroless or Alpine: the pod is for development, glibc is
# what most binaries are linked against, and having a shell in it the one time
# something is wrong is worth more than the eighty megabytes.
FROM --platform=$BUILDPLATFORM golang:1.24-bookworm AS build

ARG TARGETARCH
ARG DELVE_VERSION=v1.26.2
ENV CGO_ENABLED=0 GOOS=linux

WORKDIR /src
COPY supervisor/ ./supervisor/
RUN cd supervisor && GOARCH=$TARGETARCH go build -trimpath -o /out/ideai-supervisor .

# Delve is fetched rather than vendored: it tracks the Go release, and a
# development image is rebuilt often enough that pinning it here is the right
# place to say which one.
RUN GOARCH=$TARGETARCH go install github.com/go-delve/delve/cmd/dlv@${DELVE_VERSION} \
	&& cp "$(find /go/bin -name dlv -type f | head -1)" /out/dlv

FROM debian:bookworm-slim

# ca-certificates because the program under development talks to things;
# procps and curl because when a pod misbehaves somebody will want to look.
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates procps curl \
	&& rm -rf /var/lib/apt/lists/*

COPY --from=build /out/ideai-supervisor /usr/local/bin/ideai-supervisor
COPY --from=build /out/dlv /usr/local/bin/dlv

# Writable by whichever user the chart runs as: a pod that runs as non-root
# still has to receive a binary.
RUN mkdir -p /app && chmod 1777 /app

ENV IDEAI_BINARY=/app/current \
	IDEAI_WORKDIR=/app \
	IDEAI_CONTROL_ADDR=:7999 \
	IDEAI_DEBUG_ADDR=:2345

EXPOSE 7999 2345
ENTRYPOINT ["/usr/local/bin/ideai-supervisor"]
