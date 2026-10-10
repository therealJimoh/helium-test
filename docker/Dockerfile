# syntax=docker/dockerfile:1.7
# Build from repo root: docker build -f docker/Dockerfile -t helium-test:dev .

ARG GO_VERSION=1.24

FROM golang:${GO_VERSION}-alpine AS build
WORKDIR /src

# Dependency layer cached separately from source (stdlib-only today, so no go.sum yet).
COPY app/go.mod ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY app/ ./
ARG VERSION=dev
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build \
      -trimpath \
      -ldflags="-s -w -X main.version=${VERSION}" \
      -o /out/helium-test .

# Distroless static: no shell or package manager; :nonroot runs as UID 65532.
FROM gcr.io/distroless/static-debian12:nonroot

ARG VERSION=dev
LABEL org.opencontainers.image.title="helium-test" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://github.com/helium-test/helium-test"

COPY --from=build /out/helium-test /helium-test

USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/helium-test"]
