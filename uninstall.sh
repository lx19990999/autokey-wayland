#!/usr/bin/env bash
# Remove a user-prefix install created by ./install.sh
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: uninstall.sh [options]

  --prefix DIR       User prefix (default: ~/.local)
  --purge-system     Also remove udev rules, uinput modules-load, and the
                     input group membership (requires sudo)
  -h, --help
EOF
}

PREFIX=${PREFIX:-"$HOME/.local"}
PURGE_SYSTEM=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX=$2; shift 2 ;;
        --purge-system) PURGE_SYSTEM=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$SCRIPT_DIR
if [[ $(basename "$SCRIPT_DIR") == scripts ]]; then
    REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
fi

"$REPO_ROOT/install.sh" --prefix "$PREFIX" --uninstall

if [[ "$PURGE_SYSTEM" -eq 1 ]]; then
    echo "==> removing system udev/uinput configuration"
    sudo rm -f /etc/udev/rules.d/10-autokey.rules /etc/modules-load.d/uinput.conf
    sudo udevadm control --reload-rules || true
    sudo udevadm trigger --subsystem-match=misc --action=add || true
    if id -nG "$(id -un)" | grep -qw input; then
        sudo gpasswd -d "$(id -un)" input || sudo usermod -r -G input "$(id -un)" || true
        echo "warning: removed from group 'input'; log out for it to take effect" >&2
    fi
    if command -v gnome-extensions >/dev/null 2>&1; then
        gnome-extensions uninstall autokey-gnome-extension@autokey 2>/dev/null || true
    fi
fi
