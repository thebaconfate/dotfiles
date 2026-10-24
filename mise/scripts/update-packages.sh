#!/usr/bin/env bash
# Upgrades system packages without asking: the Brewfile on macOS, dnf on Fedora.
# Run by `mise run update:packages` (mise/global.toml), from the dotfiles folder.
set -euo pipefail

echo "==> Upgrading system packages"
if [[ "$(uname)" == Darwin ]]; then
    brew update
    # Installs what the Brewfile gained and upgrades what's in it; other formulae stay as they are.
    # brew bundle has no --yes; HOMEBREW_NO_ASK is the one its brew install/upgrade calls follow
    HOMEBREW_NO_ASK=1 brew bundle install --file packages/Brewfile
elif command -v dnf >/dev/null 2>&1; then
    sudo dnf upgrade --refresh --assumeyes
    # The NVIDIA driver (RPM Fusion's akmod-nvidia) is built per kernel, at boot otherwise:
    # build it now for the newest kernel, so the first boot into it doesn't come up without
    # it. akmods skips what's already built, so this is quick when nothing changed.
    if rpm -q akmod-nvidia >/dev/null 2>&1; then
        kernel="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | sort -V | tail -n 1)"
        sudo akmods --kernels "$kernel"
    fi
else
    echo "packages: no Homebrew or dnf here, skipped"
fi
