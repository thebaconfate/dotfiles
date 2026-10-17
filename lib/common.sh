# Helpers shared by install.sh and the scripts under os/ and hardware/. Sourced, not run.
# DRY_RUN, ASSUME_YES and NOTES_FILE come from install.sh through the environment, so a
# script started on its own still works: it then runs for real and asks its own questions.

DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
NOTES_FILE="${NOTES_FILE:-/dev/null}"

log() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
has() { command -v "$1" >/dev/null 2>&1; }

# run <command...>: runs it, or only prints it with --dry-run
run() {
    if ((DRY_RUN)); then
        info "would run: $*"
    else
        "$@"
    fi
}

# ask <question> <y|n>: true for yes. Takes the default without asking under --yes, or when
# there's no terminal to ask on.
ask() {
    local question="$1" default="${2:-y}" hint reply
    [[ "$default" == y ]] && hint="[Y/n]" || hint="[y/N]"
    if ((ASSUME_YES)) || [[ ! -t 0 ]]; then
        info "$question $hint $default"
        [[ "$default" == y ]]
        return
    fi
    read -r -p "    $question $hint " reply
    reply="${reply:-$default}"
    [[ "$reply" =~ ^[Yy] ]]
}

# note <text>: something left to do by hand, shown again at the very end
note() { printf '%s\n' "$*" >>"$NOTES_FILE"; }

is_wsl() { [[ -r /proc/sys/kernel/osrelease ]] && grep -qi microsoft /proc/sys/kernel/osrelease; }

secure_boot_enabled() { has mokutil && mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot enabled'; }

# RPM Fusion: the NVIDIA driver, Steam and Discord come from there
ensure_rpmfusion() {
    if rpm -q rpmfusion-free-release rpmfusion-nonfree-release >/dev/null 2>&1; then
        info "RPM Fusion: already enabled"
        return
    fi
    local release
    release="$(rpm -E %fedora)"
    info "RPM Fusion: enabling free and nonfree"
    run sudo dnf install -y \
        "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$release.noarch.rpm" \
        "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$release.noarch.rpm"
}
