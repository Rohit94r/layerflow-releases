#!/usr/bin/env bash
set -euo pipefail

# LayerFlow CLI installer — one line:
#   curl -fsSL https://layerflow.dev/install | bash
# or from GitHub directly:
#   curl -fsSL https://raw.githubusercontent.com/Rohit94r/layerflow-releases/main/install.sh | bash
#
# Works on macOS, Linux, and Windows (Git Bash / MSYS2 / WSL). Downloads the
# prebuilt `lf` binary for your OS/arch from the public layerflow-releases
# repo, verifies its SHA-256 checksum, and adds it to your PATH. Also creates
# a `layerflow` alias so both `lf` and `layerflow` work.
#
# The LayerFlow source stays private — only binaries live in the public repo.

APP="lf"
ALIAS="layerflow"
REPO="Rohit94r/layerflow-releases"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
VERSION="${VERSION:-latest}"

MUTED='\033[0;2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat <<EOF
LayerFlow Installer

Usage: install.sh [options]

Options:
    -h, --help              Show this help message
    -v, --version <version> Install a specific version (e.g., 0.2.0)
        --no-modify-path    Don't modify shell config files (.zshrc, .bashrc, etc.)

Examples:
    curl -fsSL https://layerflow.dev/install | bash
    curl -fsSL https://layerflow.dev/install | bash -s -- --version 0.2.0
EOF
}

no_modify_path=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            if [[ -n "${2:-}" ]]; then
                VERSION="$2"
                shift 2
            else
                echo -e "${RED}error: --version requires an argument${NC}" >&2
                exit 1
            fi
            ;;
        --no-modify-path)
            no_modify_path=true
            shift
            ;;
        *)
            echo -e "${RED}error: unknown option '$1'${NC}" >&2
            usage
            exit 1
            ;;
    esac
done

# ── Detect OS ─────────────────────────────────────────────────────────────
raw_os="$(uname -s)"
case "$raw_os" in
    Darwin*)  os="darwin" ;;
    Linux*)   os="linux" ;;
    MINGW*|MSYS*|CYGWIN*) os="windows" ;;
    *)
        echo -e "${RED}error: unsupported OS '$raw_os' — use macOS, Linux, or Windows (Git Bash / WSL)${NC}" >&2
        exit 1
        ;;
esac

# ── Detect arch ───────────────────────────────────────────────────────────
arch="$(uname -m)"
case "$arch" in
    x86_64|amd64)  arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *)
        echo -e "${RED}error: unsupported architecture '$arch'${NC}" >&2
        exit 1
        ;;
esac

# ── Resolve the latest release tag ────────────────────────────────────────
if [ "$VERSION" = "latest" ]; then
    VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | cut -d'"' -f4 || true)"
fi
if [ -z "$VERSION" ]; then
    echo -e "${RED}error: could not resolve the latest version${NC}" >&2
    echo -e "${RED}       the public release repo has no releases yet, or GitHub is unreachable.${NC}" >&2
    exit 1
fi
VERSION="${VERSION#v}"
BASE="https://github.com/${REPO}/releases/download/v${VERSION}"

# ── Build the artifact name ───────────────────────────────────────────────
if [ "$os" = "windows" ]; then
    ARCHIVE="lf_${VERSION}_${os}_${arch}.zip"
    EXTRACT="unzip -q"
else
    ARCHIVE="lf_${VERSION}_${os}_${arch}.tar.gz"
    EXTRACT="tar -xzf"
fi

if ! command -v curl >/dev/null 2>&1; then
    echo -e "${RED}error: 'curl' is required but not installed${NC}" >&2
    exit 1
fi
if [ "$os" = "windows" ] && ! command -v unzip >/dev/null 2>&1; then
    echo -e "${RED}error: 'unzip' is required but not installed${NC}" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo -e "${MUTED}Downloading ${NC}${APP} ${VERSION} ${MUTED}(${os}/${arch})...${NC}"
if [ -t 1 ]; then
    curl -# -fSL "${BASE}/${ARCHIVE}" -o "${TMP}/${ARCHIVE}"
else
    curl -fSL "${BASE}/${ARCHIVE}" -o "${TMP}/${ARCHIVE}"
fi

# ── Verify the SHA-256 checksum against the release's checksums.txt ──────
if command -v shasum >/dev/null 2>&1; then
    SHA_CMD="shasum -a 256 -c -"
elif command -v sha256sum >/dev/null 2>&1; then
    SHA_CMD="sha256sum -c -"
else
    SHA_CMD=""
fi
if [ -n "$SHA_CMD" ]; then
    (cd "$TMP" && curl -fSL "${BASE}/checksums.txt" | grep -F "$ARCHIVE" | $SHA_CMD >/dev/null) \
        || { echo -e "${RED}error: checksum verification failed for $ARCHIVE${NC}" >&2; exit 1; }
fi

# ── Install ───────────────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
(
    cd "$TMP"
    if [ "$os" = "windows" ]; then
        unzip -q "$ARCHIVE"
        cp -f "lf.exe" "$INSTALL_DIR/lf.exe"
        cp -f "lf.exe" "$INSTALL_DIR/$ALIAS.exe"
    else
        tar -xzf "$ARCHIVE"
        install -m 0755 "lf" "$INSTALL_DIR/$APP"
        ln -sf "$APP" "$INSTALL_DIR/$ALIAS"
    fi
)

echo -e "${GREEN}✓${NC} Installed ${APP} ${VERSION} to ${INSTALL_DIR}"

# ── Add to PATH ───────────────────────────────────────────────────────────
if [ "$no_modify_path" = "false" ] && [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    add_to_path() {
        local file="$1"
        local line="$2"
        if grep -Fxq "$line" "$file" 2>/dev/null; then
            return
        fi
        printf '\n# layerflow\n%s\n' "$line" >> "$file"
        echo -e "${GREEN}✓${NC} Added ${INSTALL_DIR} to PATH in ${file}"
    }

    current_shell="$(basename "${SHELL:-}")"
    case "$current_shell" in
        fish)      add_to_path "$HOME/.config/fish/config.fish" "fish_add_path $INSTALL_DIR" ;;
        zsh)       add_to_path "${ZDOTDIR:-$HOME}/.zshrc" "export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
        bash)      add_to_path "$HOME/.bashrc" "export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
        *)         add_to_path "$HOME/.bashrc" "export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
    esac
fi

if [[ ":$PATH:" == *":$INSTALL_DIR:"* ]] || [ "$no_modify_path" = "true" ]; then
    echo -e "${CYAN}▶${NC} Restart your terminal (or run 'source ~/.zshrc' / 'source ~/.bashrc')"
    echo -e "${CYAN}▶${NC} Then run:  lf  ${MUTED}# or 'layerflow'${NC}"
fi
echo ""
echo -e "${MUTED}Run '${NC}lf version${MUTED}' to confirm, or '${NC}lf login${MUTED}' to get started.${NC}"
