#!/usr/bin/env bash
# NVIDIA driver on Fedora, from RPM Fusion: https://rpmfusion.org/Howto/NVIDIA and, with
# Secure Boot on, https://rpmfusion.org/Howto/Secure%20Boot. install.sh only runs this when
# lspci shows an NVIDIA GPU. Safe to re-run. Ends with a reboot left to you.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
. "$DOTFILES/lib/common.sh"
KEY=/etc/pki/akmods/certs/public_key.der

((DRY_RUN)) || sudo -v
ensure_rpmfusion

if rpm -q akmod-nvidia >/dev/null 2>&1; then
    info "nvidia: driver already installed"
    exit 0
fi

# With Secure Boot on, the kernel only loads modules signed with an enrolled key: make a
# signing key for akmods and queue it for enrolment at the next boot
if secure_boot_enabled; then
    info "secure boot: on, so the driver gets signed"
    run sudo dnf install -y kmodtool akmods mokutil openssl
    [[ -f "$KEY" ]] || run sudo kmodgenca -a
    if mokutil --test-key "$KEY" 2>/dev/null | grep -q 'already enrolled'; then
        info "secure boot: signing key already enrolled"
    else
        info "secure boot: queueing the signing key; pick a one-time password to confirm it after the reboot"
        run sudo mokutil --import "$KEY"
        note "NVIDIA: at the reboot, choose 'Enroll MOK' in the blue MOK manager and enter the password you just set"
    fi
fi

info "nvidia: installing the driver and CUDA support"
run sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
# Build the module now, for the newest installed kernel: that's the one the next boot starts,
# and it's often newer than the running one after os/fedora.sh's dnf upgrade. Otherwise the
# build only happens during that boot, without the NVIDIA driver until it's done.
kernel="$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | tail -n 1)" ||
    kernel="$(uname -r)"
info "nvidia: building the kernel module for $kernel (takes a few minutes)"
run sudo akmods --force --kernels "$kernel"
if ((!DRY_RUN)) && ! modinfo -k "$kernel" -F version nvidia >/dev/null 2>&1; then
    info "nvidia: the module isn't built yet; run 'sudo akmods --force --kernels $kernel' before rebooting"
fi
note "NVIDIA: reboot, then check that nvidia-smi lists the GPU"
