# Mitori Agent

Lightweight monitoring agent for Mitori. Collects system metrics and Docker container stats.

## Building

```bash
# Install protoc (one-time setup)
brew install protobuf  # macOS
apt-get install protobuf-compiler  # Linux

# Generate protobuf code
cd internal/proto
bash generate.sh
cd ../..

# Build
go build -o mitori-agent ./cmd/agent

# Run
./mitori-agent
```

## What it collects

- CPU usage (per-core and aggregate)
- Memory usage
- Disk usage
- Network I/O
- Docker container stats

## Configuration

Requires config at platform-specific location with `ingestor_url` and `host_id`. API key stored in system keyring.
