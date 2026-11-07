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
    # Unlike brew bundle, dnf upgrade doesn't install what packages/fedora.txt gained since a
    # machine was set up. gh is in [core] and every machine needs it, so add it when missing.
    # (The other groups can be skipped on purpose, so they're left to os/fedora.sh.)
    if ! rpm -q gh >/dev/null 2>&1; then
        echo "gh: installing"
        sudo dnf install --assumeyes gh
    fi
    # The NVIDIA driver (RPM Fusion's akmod-nvidia) is built per kernel, at boot otherwise:
    # build it now for the newest kernel, so the first boot into it doesn't come up without
    # it. akmods skips what's already built, so this is quick when nothing changed.
    if rpm -q akmod-nvidia >/dev/null 2>&1; then
        kernel="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | sort -V | tail -n 1)"
        sudo akmods --kernels "$kernel"
    fi
    # os/qemu-stream-netdev works around a QEMU bug: say when QEMU has closed it. Quiet while
    # it's open, or when GitLab can't be reached.
    if [[ -n "${QEMU_SYSTEM_X86_64:-}" ]]; then
        state="$(curl -fsS --max-time 10 \
            "https://gitlab.com/api/v4/projects/qemu-project%2Fqemu/issues/3285" 2>/dev/null |
            jq -r '.state' 2>/dev/null || true)"
        if [[ "$state" == closed ]]; then
            echo "qemu: the netdev crash colima works around is fixed upstream" \
                "(https://gitlab.com/qemu-project/qemu/-/work_items/3285)."
            echo "    Once Fedora's QEMU has the fix: delete os/qemu-stream-netdev and" \
                "QEMU_SYSTEM_X86_64 in mise/global.toml, then run colima restart"
        fi
    fi
else
    echo "packages: no Homebrew or dnf here, skipped"
fi
