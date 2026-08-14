#!/bin/bash
set -e

# LayerFlow CLI installer — one line:
#   curl -fsSL https://raw.githubusercontent.com/Rohit94r/layerflow-releases/main/install.sh | bash
#
# Downloads the prebuilt `lf` binary for your OS/arch from the public
# layerflow-releases repo. The LayerFlow source stays private — only
# binaries live in the public repo.
#
# Also installs a `layerflow` symlink so both `lf` and `layerflow` work.

REPO="Rohit94r/layerflow-releases"
BINARY="lf"
ALIAS="layerflow"
VERSION="${VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# Detect OS and arch
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "error: unsupported architecture $ARCH" >&2; exit 1 ;;
esac
case "$OS" in
  darwin|linux) ;;
  *) echo "error: unsupported OS $OS — use macOS or Linux (or WSL on Windows)" >&2; exit 1 ;;
esac

# Resolve the latest release tag
if [ "$VERSION" = "latest" ]; then
  VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)"
fi
if [ -z "$VERSION" ]; then
  echo "error: could not resolve the latest version" >&2
  echo "note:  the public release repo has no releases yet, or GitHub is unreachable." >&2
  echo "note:  make sure the repo ${REPO} exists and has at least one release." >&2
  exit 1
fi

# GoReleaser strips the leading "v" from tags in archive names, so "v0.2.0"
# becomes lf_0.2.0_darwin_arm64.tar.gz.
TAG="${VERSION#v}"
TARBALL="lf_${TAG}_${OS}_${ARCH}.tar.gz"
BASE="https://github.com/${REPO}/releases/download/${VERSION}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $BINARY ${VERSION} (${OS}/${ARCH})..."
curl -fsSL "${BASE}/${TARBALL}" -o "${TMP}/${TARBALL}"

# Verify the SHA-256 checksum against the release's checksums.txt
if command -v shasum >/dev/null 2>&1; then
  (
    cd "$TMP"
    curl -fsSL "${BASE}/checksums.txt" | grep -F "$TARBALL" | shasum -a 256 -c - >/dev/null
  ) || { echo "error: checksum verification failed for $TARBALL" >&2; exit 1; }
fi

mkdir -p "$INSTALL_DIR"
tar -xzf "${TMP}/${TARBALL}" -C "$TMP" "$BINARY"
install -m 0755 "$TMP/$BINARY" "$INSTALL_DIR/$BINARY"
ln -sf "$BINARY" "$INSTALL_DIR/$ALIAS"

echo ""
echo "Installed $BINARY ${VERSION} to $INSTALL_DIR/$BINARY (alias: $ALIAS)"
echo "Run '$BINARY version' to confirm, or '$BINARY login' to get started."
echo "Add $INSTALL_DIR to your PATH if it is not already."
