# Read-only SSH checks and explicit client-package installation.

show_ssh_status() {
    local service_state

    print_section "SSH"

    if has_command ssh; then
        printf 'SSH client: '
        ssh -V 2>&1
    else
        echo "SSH client: not installed"
    fi

    if has_command sshd; then
        echo "SSH server binary: installed"
    else
        echo "SSH server binary: not installed"
    fi

    if has_command systemctl; then
        service_state=$(systemctl is-active ssh 2>/dev/null || true)
        case "$service_state" in
            active|inactive|failed|activating|deactivating)
                printf 'ssh.service: %s\n' "$service_state"
                ;;
            *)
                echo "ssh.service: state unavailable"
                ;;
        esac
    fi

    if has_command ss; then
        printf '\nListening TCP port 22:\n'
        ss -ltn 'sport = :22' 2>/dev/null || true
    fi

    echo
    echo "This check never enables, starts, or exposes the SSH server."
}

show_ssh_keys() {
    local key
    local found=0

    print_section "SSH public keys"

    if ! has_command ssh-keygen; then
        echo "ssh-keygen is not installed."
        return 127
    fi

    for key in "$HOME"/.ssh/*.pub; do
        [ -f "$key" ] || continue
        found=1
        printf '%s: ' "$(basename -- "$key")"
        ssh-keygen -lf "$key" || true
    done

    if [ "$found" -eq 0 ]; then
        echo "No public keys found in $HOME/.ssh"
        echo "Create one manually when needed: ssh-keygen -t ed25519"
    fi
}

install_ssh_client() {
    if [ "${1:-}" != "--yes" ]; then
        echo "This updates APT metadata and installs the SSH client." >&2
        echo "Run: system ssh install-client --yes" >&2
        return 2
    fi

    sudo apt update &&
        sudo apt install -y openssh-client &&
        echo "OpenSSH client installed."
}
