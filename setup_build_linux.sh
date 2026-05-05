#!/usr/bin/env bash
# Input Leap - Linux setup and build script
# Run from the repo root: bash setup_build_linux.sh
#
# Supports: Ubuntu/Debian (apt), Fedora/RHEL (dnf), openSUSE (zypper)
# Optional env vars:
#   QT_MAJOR_VERSION  - Qt major version (default: 6)
#   BUILD_TYPE        - Release or Debug (default: Release)

set -euo pipefail

QT_MAJOR=${QT_MAJOR_VERSION:-6}
BUILD_TYPE=${BUILD_TYPE:-Release}
BUILD_DIR="build"

step() { echo -e "\n\033[0;36m==> $*\033[0m"; }
ok()   { echo -e "    \033[0;32m$*\033[0m"; }
err()  { echo -e "    \033[0;31mERROR: $*\033[0m" >&2; exit 1; }

# ── 1. Detect package manager ────────────────────────────────────────────────
step "Detecting Linux distribution"
if command -v apt-get &>/dev/null; then
    DISTRO="debian"
    ok "Debian/Ubuntu (apt)"
elif command -v dnf &>/dev/null; then
    DISTRO="fedora"
    ok "Fedora/RHEL (dnf)"
elif command -v zypper &>/dev/null; then
    DISTRO="suse"
    ok "openSUSE (zypper)"
else
    err "Unsupported distro. Install dependencies manually (see README)."
fi

# ── 2. Install dependencies ──────────────────────────────────────────────────
step "Installing build dependencies"

if [[ "$DISTRO" == "debian" ]]; then
    sudo apt-get update -y
    PKGS=(
        cmake g++ git ninja-build pkg-config
        libssl-dev
        libavahi-compat-libdnssd-dev
        libxinerama-dev libxrandr-dev libxtst-dev
        libice-dev libsm-dev
        libxkbcommon-dev libglib2.0-dev libgl-dev
        libgtest-dev libgmock-dev
    )
    if [[ "$QT_MAJOR" == "6" ]]; then
        PKGS+=(qt6-base-dev qt6-tools-dev qt6-tools-dev-tools qt6-l10n-tools)
    else
        PKGS+=(qttools5-dev qtdeclarative5-dev)
    fi
    sudo apt-get install -y "${PKGS[@]}"

elif [[ "$DISTRO" == "fedora" ]]; then
    sudo dnf install -y \
        cmake gcc-c++ git ninja-build pkg-config \
        openssl-devel \
        avahi-compat-libdns_sd-devel \
        libXinerama-devel libXrandr-devel libXtst-devel \
        libICE-devel libSM-devel \
        libxkbcommon-devel glib2-devel mesa-libGL-devel \
        gtest-devel gmock-devel \
        qt6-qtbase-devel qt6-qttools-devel

elif [[ "$DISTRO" == "suse" ]]; then
    sudo zypper install -y \
        cmake gcc-c++ git ninja pkg-config \
        libopenssl-devel \
        avahi-compat-mDNSResponder-devel \
        libXinerama-devel libXrandr-devel libXtst-devel \
        libICE-devel libSM-devel \
        libxkbcommon-devel glib2-devel Mesa-libGL-devel \
        gtest gmock \
        qt6-base-devel qt6-tools
fi

ok "Dependencies installed"

# ── 3. Init submodules ───────────────────────────────────────────────────────
step "Initializing git submodules"
git submodule update --init --recursive
ok "Submodules ready"

# ── 4. CMake configure ───────────────────────────────────────────────────────
step "Configuring CMake ($BUILD_TYPE, Qt $QT_MAJOR)"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Detect if we're on Ubuntu 20.04 which needs the bundled filesystem lib
GULRAK=0
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    if [[ "${VERSION_ID:-}" == "20.04" ]]; then
        GULRAK=1
        ok "Ubuntu 20.04 detected — using bundled gulrak-filesystem"
    fi
fi

cmake -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DQT_DEFAULT_MAJOR_VERSION="$QT_MAJOR" \
    -DINPUTLEAP_BUILD_GULRAK_FILESYSTEM="$GULRAK" \
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/input-leap-install"

# ── 5. Build ─────────────────────────────────────────────────────────────────
step "Building Input Leap"
cmake --build "$BUILD_DIR" --parallel

# ── 6. Install ───────────────────────────────────────────────────────────────
step "Installing to $BUILD_DIR/input-leap-install"
cmake --install "$BUILD_DIR"

ok "Build complete -> $BUILD_DIR/input-leap-install/"

echo -e "\n\033[0;32m[DONE]\033[0m Run \033[1m$BUILD_DIR/input-leap-install/bin/input-leap\033[0m to start the GUI."
echo "       Or run the server directly: $BUILD_DIR/input-leap-install/bin/input-leaps"
echo "       Or run the client directly: $BUILD_DIR/input-leap-install/bin/input-leapc"
