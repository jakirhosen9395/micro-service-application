# syntax=docker/dockerfile:1.7
FROM golang:1.26.3-alpine AS builder
WORKDIR /src
RUN apk add --no-cache ca-certificates git tzdata

# Copy only go.mod first. The uploaded archive may contain an empty go.sum;
# copying it before module download can overwrite generated checksum data in
# later layers. The build therefore regenerates go.sum inside the builder.
COPY go.mod ./
RUN --mount=type=cache,target=/go/pkg/mod     touch go.sum &&     go mod download

COPY . .
RUN --mount=type=cache,target=/go/pkg/mod     --mount=type=cache,target=/root/.cache/go-build     rm -f go.sum &&     go mod tidy &&     CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -mod=mod -trimpath -ldflags="-s -w" -o /out/user_service ./cmd/user-service

FROM alpine:3.22
WORKDIR /app
RUN apk add --no-cache ca-certificates curl tzdata     && addgroup -S appgroup     && adduser -S appuser -G appgroup
COPY --from=builder /out/user_service /app/user_service
COPY migrations /app/migrations
ENV USER_HOST=0.0.0.0
ENV USER_PORT=8080
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3   CMD curl -fsS http://127.0.0.1:8080/hello || exit 1
ENTRYPOINT ["/app/user_service"]
