#!/usr/bin/env bash
# Fedora tools: a system upgrade, the hostname, RPM Fusion, then the groups in
# packages/fedora.txt you pick, with the extra repos and services they need. Run by
# install.sh, or on its own (./os/fedora.sh). Safe to re-run.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
. "$DOTFILES/lib/common.sh"
PACKAGES="$DOTFILES/packages/fedora.txt"
USER="${USER:-$(id -un)}"

((DRY_RUN)) || sudo -v

# 1. System upgrade
if ask "Upgrade the system first (dnf upgrade)?" y; then
    run sudo dnf upgrade --refresh -y
fi

# 2. Hostname, only when there's someone to ask
if ((!ASSUME_YES)) && [[ -t 0 ]]; then
    current="$(hostnamectl hostname 2>/dev/null || hostname)"
    read -r -p "    Hostname (Enter keeps '$current'): " new_hostname
    if [[ -n "$new_hostname" && "$new_hostname" != "$current" ]]; then
        run sudo hostnamectl set-hostname "$new_hostname"
    fi
fi

# 3. RPM Fusion, and dnf config-manager for the other repos
ensure_rpmfusion
rpm -q dnf-plugins-core >/dev/null 2>&1 || run sudo dnf install -y dnf-plugins-core

# add_repo <name> <.repo URL>
add_repo() {
    if [[ -f "/etc/yum.repos.d/$1.repo" ]]; then
        info "$1 repo: already added"
    else
        info "$1 repo: adding"
        run sudo dnf config-manager addrepo --from-repofile="$2"
    fi
}

# 4. Package groups: read packages/fedora.txt into "group:package" lines
groups=()
entries=()
group=""
while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ^\[(.+)\]$ ]]; then
        group="${BASH_REMATCH[1]}"
        groups+=("$group")
    else
        entries+=("$group:$line")
    fi
done <"$PACKAGES"

selected=()
for group in "${groups[@]}"; do
    packages=()
    for entry in "${entries[@]}"; do
        [[ "${entry%%:*}" == "$group" ]] && packages+=("${entry#*:}")
    done
    if ask "Install [$group]: ${packages[*]}?" y; then
        selected+=("${packages[@]}")
    fi
done

if ((${#selected[@]} == 0)); then
    info "no package groups picked"
    exit 0
fi

wants() {
    local package
    for package in "${selected[@]}"; do [[ "$package" == "$1" ]] && return 0; done
    return 1
}

if wants brave-browser; then
    add_repo brave-browser https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
fi
if wants docker-ce; then
    add_repo docker-ce https://download.docker.com/linux/fedora/docker-ce.repo
    # Fedora's own Docker packages conflict with Docker CE
    old=()
    for package in docker docker-client docker-client-latest docker-common docker-latest \
        docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine; do
        rpm -q "$package" >/dev/null 2>&1 && old+=("$package")
    done
    if ((${#old[@]})); then
        info "removing Fedora's Docker packages: ${old[*]}"
        run sudo dnf remove -y "${old[@]}"
    fi
fi

info "installing ${#selected[@]} packages"
run sudo dnf install -y "${selected[@]}"

# 5. What some packages need after installing
if wants docker-ce; then
    if systemctl is-enabled --quiet docker 2>/dev/null; then
        info "docker: service already enabled"
    else
        run sudo systemctl enable --now docker
    fi
    if id -nG "$USER" | grep -qw docker; then
        info "docker: $USER already in the docker group"
    else
        run sudo usermod -aG docker "$USER"
        note "Log out and back in so docker works without sudo"
    fi
fi

if wants lpf-spotify-client && ! rpm -q spotify-client >/dev/null 2>&1; then
    note "Spotify: finish the lpf build by hand (README, 'Spotify on Fedora')"
fi

# zsh-config's installer leaves the login shell alone, and Fedora starts with bash
if wants zsh; then
    zsh_path="$(command -v zsh || echo /usr/bin/zsh)"
    login_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [[ "$login_shell" == "$zsh_path" ]]; then
        info "zsh: already the login shell"
    elif ask "Make zsh your login shell?" y; then
        run sudo usermod --shell "$zsh_path" "$USER"
        note "Log out and back in to start using zsh"
    fi
fi
