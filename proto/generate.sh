#!/bin/bash
set -e

# This script generates Go code from protobuf definitions

# Check if protoc is installed
if ! command -v protoc &> /dev/null; then
    echo "Error: protoc not found. Please install it:"
    echo "  macOS: brew install protobuf"
    echo "  Linux: apt-get install protobuf-compiler"
    exit 1
fi

# Ensure GOPATH/bin is in PATH
export PATH="$PATH:$(go env GOPATH)/bin"

# Check if protoc-gen-go is installed
if ! command -v protoc-gen-go &> /dev/null; then
    echo "Installing protoc-gen-go..."
    go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
fi

# Create output directory
mkdir -p gen

# Generate Go code
echo "Generating Go code from mitori.proto..."
protoc \
  --go_out=gen \
  --go_opt=paths=source_relative \
  mitori.proto

echo "✓ Go code generated in gen/"
