# syntax=docker/dockerfile:1

# Build go
FROM --platform=$BUILDPLATFORM golang:1.25.3-alpine AS builder
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT
WORKDIR /app
ENV CGO_ENABLED=0
RUN apk --no-cache add ca-certificates tzdata
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN set -eux; \
    GOOS="${TARGETOS:-linux}" \
    GOARCH="${TARGETARCH:-amd64}" \
    GOARM="${TARGETVARIANT#v}" \
    go build -v -o XrayR -trimpath -ldflags "-s -w -buildid="

# Release
FROM  alpine
LABEL org.opencontainers.image.source="https://github.com/6Kmfi6HP/XrayR"
LABEL org.opencontainers.image.description="XrayR backend service"
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
COPY --from=builder /app/XrayR /usr/local/bin
WORKDIR /etc/XrayR

ENTRYPOINT [ "XrayR", "--config", "/etc/XrayR/config.yml"]
