#!/usr/bin/env bash
# First-time setup of a new macOS or Fedora machine, before the dotfiles are on it:
#   1. git and the GitHub CLI (gh)
#   2. an SSH key, a GitHub login through the browser, and the key uploaded to GitHub for
#      pushing and for signing commits
#   3. git's name and email (defaults read from your GitHub account) and commit signing
#   4. the dotfiles, cloned over SSH into ~/.dotfiles
#   5. ~/.dotfiles/install.sh, which takes it from there
# Safe to re-run: what's already in place is skipped, and a clone made over HTTPS earlier is
# switched to SSH. Skipping the SSH step clones over HTTPS and leaves signing off.
#
#   curl -fsSL https://raw.githubusercontent.com/thebaconfate/dotfiles/main/bootstrap.sh | bash
#
# Arguments go to install.sh: `| bash -s -- --yes`. Set DOTFILES_DIR to clone elsewhere.
# Written for bash 3.2, the version macOS ships. All the work happens in main(), called on the
# last line: piped in, bash reads the script while running it, so nothing runs before it's all read.
set -euo pipefail

REPO=thebaconfate/dotfiles
DEST="${DOTFILES_DIR:-$HOME/.dotfiles}"
KEY="$HOME/.ssh/id_ed25519"
SCOPES="user:email,admin:public_key,admin:ssh_signing_key"
USE_SSH=0
AGENT_STARTED=0 # read by the EXIT trap in main()

log() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
has() { command -v "$1" >/dev/null 2>&1; }

# ask <question> <y|n>: true for yes
ask() {
    local question="$1" default="${2:-y}" hint reply
    [[ "$default" == y ]] && hint="[Y/n]" || hint="[y/N]"
    read -r -p "    $question $hint " reply
    reply="${reply:-$default}"
    [[ "$reply" =~ ^[Yy] ]]
}

load_brew() {
    local brew_bin
    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "$brew_bin" ]]; then
            eval "$("$brew_bin" shellenv)"
            return 0
        fi
    done
    return 1
}

# 1. git and gh -----------------------------------------------------------------------------

install_tools() {
    log "git and the GitHub CLI"
    if [[ "$OS" == macos ]]; then
        # Homebrew's installer also brings the Xcode command line tools, and git with them
        has brew || load_brew || true
        if has brew; then
            info "homebrew: already installed"
        else
            info "homebrew: installing (it brings git along)"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            load_brew
        fi
        if has gh; then info "gh: already installed"; else brew install gh; fi
    else
        local missing=()
        has git || missing+=(git-core)
        has gh || missing+=(gh)
        if ((${#missing[@]})); then
            info "installing ${missing[*]}"
            sudo dnf install -y "${missing[@]}"
        else
            info "git and gh: already installed"
        fi
    fi
}

# 2. SSH key and GitHub ---------------------------------------------------------------------

setup_ssh_key() {
    log "SSH key"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    if [[ -f "$KEY" ]]; then
        info "$KEY: already exists"
    else
        info "creating $KEY; a passphrase is recommended (you type it once per login)"
        ssh-keygen -t ed25519 -C "$(whoami)@$(uname -n | cut -d. -f1)" -f "$KEY"
    fi

    # macOS: keep the passphrase in the Keychain, so ssh never asks for it again
    if [[ "$OS" == macos ]] && ! grep -qs 'UseKeychain' "$HOME/.ssh/config"; then
        info "ssh config: storing the passphrase in the Keychain for github.com"
        printf '\nHost github.com\n    AddKeysToAgent yes\n    UseKeychain yes\n    IdentityFile %s\n' \
            "$KEY" >>"$HOME/.ssh/config"
        chmod 600 "$HOME/.ssh/config"
    fi

    # Load the key into an agent, so the clone and the submodules ask for the passphrase once
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        eval "$(ssh-agent -s)" >/dev/null
        # shellcheck disable=SC2034 # read by the EXIT trap in main()
        AGENT_STARTED=1
    fi
    local fingerprint
    fingerprint="$(ssh-keygen -lf "$KEY.pub" | awk '{print $2}')"
    if ssh-add -l 2>/dev/null | grep -qF "$fingerprint"; then
        info "ssh agent: key already loaded"
    elif [[ "$OS" == macos ]]; then
        ssh-add --apple-use-keychain "$KEY"
    else
        ssh-add "$KEY"
    fi
}

github_login() {
    log "GitHub login"
    # user:email reads your verified emails; the admin scopes upload the SSH key
    if gh auth status -h github.com >/dev/null 2>&1; then
        local status scope scopes_missing=0
        status="$(gh auth status -h github.com 2>&1)"
        for scope in ${SCOPES//,/ }; do
            [[ "$status" == *"'$scope'"* ]] || scopes_missing=1
        done
        if ((scopes_missing)); then
            info "logged in, but adding the permissions for emails and SSH keys (opens the browser)"
            gh auth refresh -h github.com -s "$SCOPES"
        else
            info "already logged in"
        fi
    else
        info "logging in through the browser"
        gh auth login -h github.com -p ssh --skip-ssh-key -w -s "$SCOPES"
    fi
}

upload_ssh_key() {
    log "SSH key on GitHub"
    local key title
    key="$(awk '{print $1" "$2}' "$KEY.pub")"
    title="$(uname -n | cut -d. -f1)"
    if gh api --paginate user/keys --jq '.[].key' | grep -qxF "$key"; then
        info "authentication key: already uploaded"
    else
        gh ssh-key add "$KEY.pub" --title "$title" --type authentication
    fi
    if gh api --paginate user/ssh_signing_keys --jq '.[].key' | grep -qxF "$key"; then
        info "signing key: already uploaded"
    else
        gh ssh-key add "$KEY.pub" --title "$title" --type signing
    fi

    # GitHub's host keys, fetched over the authenticated API instead of trusted on first use
    if ssh-keygen -F github.com >/dev/null 2>&1; then
        info "known_hosts: github.com already known"
    else
        info "known_hosts: adding github.com's host keys"
        gh api meta --jq '.ssh_keys[]' | sed 's/^/github.com /' >>"$HOME/.ssh/known_hosts"
    fi
}

# 3. git config -----------------------------------------------------------------------------

# set_if_unset <key> <value>: leaves a value you've set yourself alone
set_if_unset() {
    local current
    current="$(git config --global --get "$1" || true)"
    if [[ -z "$current" ]]; then
        git config --global "$1" "$2"
        info "$1: $2"
    elif [[ "$current" != "$2" ]]; then
        info "$1: keeping $current"
    fi
}

configure_git() {
    log "git config"
    local name email
    name="$(git config --global --get user.name || true)"
    email="$(git config --global --get user.email || true)"
    if [[ -n "$name" && -n "$email" ]]; then
        info "identity: already set ($name <$email>)"
    else
        local default_name="" emails=() line reply i
        if ((USE_SSH)); then
            default_name="$(gh api user --jq '.name // .login')"
            # Verified addresses only, primary first: GitHub marks a signed commit Verified only
            # when its email is verified on the account
            while IFS= read -r line; do
                [[ -n "$line" ]] && emails+=("$line")
            done < <(gh api user/emails --jq 'sort_by(.primary | not) | .[] | select(.verified) | .email')
        fi

        read -r -p "    Name${default_name:+ [$default_name]}: " reply
        name="${reply:-$default_name}"
        while [[ -z "$name" ]]; do read -r -p "    Name: " name; done

        if ((${#emails[@]})); then
            for i in "${!emails[@]}"; do info "$((i + 1)). ${emails[i]}"; done
            read -r -p "    Email (number or address) [1]: " reply
            reply="${reply:-1}"
            if [[ "$reply" =~ ^[0-9]+$ ]] && ((reply >= 1 && reply <= ${#emails[@]})); then
                email="${emails[reply - 1]}"
            else
                email="$reply"
                info "$email isn't verified on GitHub, so signed commits will show as Unverified"
            fi
        else
            email=""
            while [[ -z "$email" ]]; do read -r -p "    Email: " email; done
        fi
        git config --global user.name "$name"
        git config --global user.email "$email"
        info "identity: $name <$email>"
    fi

    if ((USE_SSH)); then
        set_if_unset gpg.format ssh
        set_if_unset user.signingkey "$KEY.pub"
        set_if_unset commit.gpgsign true
    fi
    set_if_unset core.editor nvim
}

# 4. Clone ----------------------------------------------------------------------------------

clone_dotfiles() {
    log "dotfiles"
    if [[ -d "$DEST/.git" ]]; then
        info "$DEST: already cloned"
        if ((USE_SSH)); then switch_to_ssh; fi
    elif [[ -e "$DEST" ]]; then
        echo "$DEST exists but isn't a git clone; move it aside and re-run" >&2
        exit 1
    elif ((USE_SSH)); then
        git clone "git@github.com:$REPO.git" "$DEST"
    else
        git clone "https://github.com/$REPO.git" "$DEST"
    fi
}

# A clone made over HTTPS (before there was a key) gets its remotes pointed at SSH
switch_to_ssh() {
    local url
    url="$(git -C "$DEST" remote get-url origin)"
    if [[ "$url" == https://github.com/* ]]; then
        git -C "$DEST" remote set-url origin "git@github.com:${url#https://github.com/}"
        info "dotfiles: origin switched to SSH"
    fi
    # shellcheck disable=SC2016 # expanded by `submodule foreach`, per submodule
    git -C "$DEST" submodule foreach --quiet '
        url="$(git remote get-url origin)"
        case "$url" in https://github.com/*)
            git remote set-url origin "git@github.com:${url#https://github.com/}"
            echo "    $sm_path: origin switched to SSH" ;;
        esac'
}

# -------------------------------------------------------------------------------------------

main() {
    # Piped through curl, stdin is this script: give the prompts, gh, ssh-keygen and sudo the
    # terminal instead
    if [[ ! -t 0 ]]; then
        if [[ -r /dev/tty ]] && (: </dev/tty) 2>/dev/null; then
            exec </dev/tty
        else
            echo "bootstrap.sh needs a terminal to ask its questions" >&2
            exit 1
        fi
    fi

    case "$(uname -s)" in
        Darwin) OS=macos ;;
        Linux)
            # shellcheck disable=SC1091
            if [[ "$(. /etc/os-release 2>/dev/null && echo "${ID:-}")" == fedora ]]; then
                OS=fedora
            else
                echo "bootstrap.sh supports macOS and Fedora; on other systems, clone $REPO and run install.sh" >&2
                exit 1
            fi
            ;;
        *)
            echo "bootstrap.sh supports macOS and Fedora, not $(uname -s)" >&2
            exit 1
            ;;
    esac
    trap 'if ((AGENT_STARTED)); then ssh-agent -k >/dev/null; fi' EXIT
    echo "Bootstrapping $OS: git, an SSH key for GitHub, then the dotfiles in $DEST"

    install_tools
    log "SSH"
    if ask "Set up an SSH key and log in to GitHub (for pushing and signed commits)?" y; then
        USE_SSH=1
        setup_ssh_key
        github_login
        upload_ssh_key
    else
        info "skipped: cloning over HTTPS, and commits won't be signed. Re-run this to set it up later."
    fi
    configure_git
    clone_dotfiles

    if [[ ! -x "$DEST/install.sh" ]]; then
        echo "$DEST/install.sh is missing; pull the latest dotfiles and run it by hand" >&2
        exit 1
    fi
    log "Handing over to install.sh"
    "$DEST/install.sh" "$@"
}

main "$@"; exit
