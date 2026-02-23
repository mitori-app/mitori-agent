# Release & Versioning Guide

This document explains how to create new releases for the Mitori Agent.

## Overview

The Mitori Agent uses:
- **Semantic Versioning**: `vMAJOR.MINOR.PATCH` (e.g., `v1.0.0`, `v1.2.3`)
- **Git Tags**: Pushing a tag triggers automated builds via GitHub Actions
- **GitHub Releases**: Binaries are automatically built and attached to releases

## Quick Release Process

### 1. Update Code
Make your changes on a feature branch or `main`.

### 2. Create and Push a Git Tag
```bash
# Example: releasing v1.0.0
git tag v1.0.0
git push origin v1.0.0
```

### 3. Automated Build Kicks Off
GitHub Actions will automatically:
- Build binaries for all platforms (Linux, macOS, Windows × amd64/arm64)
- Generate SHA256 checksums
- Create a GitHub Release with all binaries attached
- Include installation instructions in the release notes

### 4. Release is Live
Users can now install via:
```bash
# Linux/macOS
curl -sSL https://raw.githubusercontent.com/mitori-app/mitori-agent/v1.0.0/install.sh | bash

# Or download binaries directly from:
# https://github.com/mitori-app/mitori-agent/releases/tag/v1.0.0
```

## Versioning Guidelines

Follow [Semantic Versioning](https://semver.org/):

- **MAJOR** (`v2.0.0`): Breaking changes (incompatible protobuf changes, removed features)
- **MINOR** (`v1.1.0`): New features (backward compatible)
- **PATCH** (`v1.0.1`): Bug fixes (backward compatible)

### Examples

- `v1.0.0` → `v1.0.1`: Fixed a bug in CPU collection
- `v1.0.0` → `v1.1.0`: Added new disk metrics
- `v1.0.0` → `v2.0.0`: Changed protobuf schema in a breaking way

## Protobuf Versioning

When changing `proto/mitori.proto`:

### ✅ Safe (Minor/Patch version bump)
- Add new **optional** fields
- Add new message types
- Add fields to `reserved` list

### ❌ Breaking (Major version bump required)
- Change field numbers
- Remove fields (without reserving)
- Change field types
- Rename fields

See `proto/README.md` for detailed protobuf versioning rules.

## Build System Details

### Version Injection
The version is injected at build time via Go ldflags:
```bash
go build -ldflags "-X main.version=v1.0.0" ./cmd/agent
```

The GitHub Actions workflow automatically extracts the version from the git tag.

### Build Targets
Binaries are built for:
- **Linux**: amd64, arm64
- **macOS**: amd64 (Intel), arm64 (Apple Silicon)
- **Windows**: amd64

## Testing a Release Locally

Before pushing a tag, test the build locally:

```bash
# Build with a test version
go build -ldflags "-X main.version=v1.0.0-test" -o mitori-agent ./cmd/agent

# Run it
./mitori-agent
# Should log: "Mitori agent starting" version="v1.0.0-test"
```

## Hotfix Process

For urgent bug fixes:

1. Create a hotfix branch from the tagged release:
   ```bash
   git checkout -b hotfix/v1.0.1 v1.0.0
   ```

2. Fix the bug and commit

3. Tag the hotfix:
   ```bash
   git tag v1.0.1
   git push origin v1.0.1
   ```

4. Merge back to main:
   ```bash
   git checkout main
   git merge hotfix/v1.0.1
   git push origin main
   ```

## Rollback a Release

If a release has critical issues:

1. **Delete the GitHub Release** (via GitHub UI or CLI)
2. **Delete the git tag:**
   ```bash
   git tag -d v1.0.1
   git push origin :refs/tags/v1.0.1
   ```

3. Users on the bad version should downgrade:
   ```bash
   # Manual download of previous version
   curl -L -o mitori-agent https://github.com/mitori-app/mitori-agent/releases/download/v1.0.0/mitori-agent-linux-amd64
   ```

## Pre-releases / Beta Versions

For testing before official release:

```bash
# Tag as pre-release
git tag v1.1.0-beta.1
git push origin v1.1.0-beta.1
```

The GitHub Actions workflow will mark it as a pre-release automatically.

## Viewing Release History

```bash
# List all tags
git tag -l

# View a specific release on GitHub
# https://github.com/mitori-app/mitori-agent/releases
```

## Troubleshooting

### Build failed in GitHub Actions
- Check the Actions tab: https://github.com/mitori-app/mitori-agent/actions
- Common issues:
  - Go version mismatch (update `.github/workflows/release.yml`)
  - Protobuf generation failed (ensure `proto/generate.sh` works locally)

### Binary won't run on user's system
- Check they downloaded the correct binary for their OS/arch
- Verify checksums match
- Check GitHub release page for error messages

---

## Summary Checklist

Before creating a release:
- [ ] All tests pass locally
- [ ] Version follows semver (MAJOR.MINOR.PATCH)
- [ ] Protobuf changes are backward compatible (or MAJOR bump)
- [ ] Commit all changes to main
- [ ] Create and push git tag: `git tag vX.Y.Z && git push origin vX.Y.Z`
- [ ] Wait for GitHub Actions to complete
- [ ] Verify release appears on GitHub with all binaries
- [ ] Test installation on at least one platform
