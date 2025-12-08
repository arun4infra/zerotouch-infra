# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /workspace

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY main.go ./

# Build the function
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o function .

# Runtime stage
FROM gcr.io/distroless/static:nonroot

WORKDIR /

# Copy the binary from builder
COPY --from=builder /workspace/function .

USER 65532:65532

ENTRYPOINT ["/function"]
