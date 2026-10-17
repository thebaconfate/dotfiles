#!/usr/bin/env bash
# linux-surface kernel on Fedora, for the touchscreen, pen and cameras of a Surface:
# https://github.com/linux-surface/linux-surface/wiki/Installation-and-Setup. install.sh only
# runs this on a Microsoft Surface. Safe to re-run. Ends with a reboot left to you.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
. "$DOTFILES/lib/common.sh"

((DRY_RUN)) || sudo -v

# linux-surface publishes per Fedora release, often weeks after it ships. Its repo is marked
# skip_if_unavailable, so without this check dnf would only fail with "No match".
release="$(rpm -E %fedora)"
if ! curl -fsI -o /dev/null "https://pkg.surfacelinux.com/fedora/f$release/repodata/repomd.xml"; then
    info "linux-surface: no packages for Fedora $release yet, skipping"
    note "Surface: linux-surface has no Fedora $release packages yet; re-run ./hardware/surface.sh once it does"
    exit 0
fi

if [[ -f /etc/yum.repos.d/linux-surface.repo ]]; then
    info "linux-surface repo: already added"
else
    info "linux-surface repo: adding"
    run sudo dnf config-manager addrepo --from-repofile=https://pkg.surfacelinux.com/fedora/linux-surface.repo
fi

# The kernel, iptsd (touchscreen and pen) and libwacom-surface, which replaces Fedora's libwacom
if rpm -q kernel-surface iptsd libwacom-surface >/dev/null 2>&1; then
    info "linux-surface: kernel and touch support already installed"
else
    info "linux-surface: installing the kernel and touch support"
    run sudo dnf install -y --allowerasing kernel-surface iptsd libwacom-surface
fi

# Without its key enrolled, Secure Boot refuses to start the Surface kernel
if secure_boot_enabled; then
    if rpm -q surface-secureboot >/dev/null 2>&1; then
        info "secure boot: surface key already installed"
    else
        info "secure boot: on, installing the linux-surface signing key"
        run sudo dnf install -y surface-secureboot
        note "Surface: at the reboot, choose 'Enroll MOK' in the blue MOK manager; the password is 'surface' (typed on QWERTY)"
    fi
fi

# Kernel updates from Fedora would otherwise become the default boot entry again
if rpm -q kernel-surface-default-watchdog >/dev/null 2>&1; then
    info "default-kernel watchdog: already installed"
else
    run sudo dnf install -y kernel-surface-default-watchdog
fi
run sudo systemctl enable --now linux-surface-default-watchdog.path

note "Surface: reboot, then check that 'uname -r' contains 'surface'"
