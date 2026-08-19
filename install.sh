#!/usr/bin/env bash
# Install AutoKey for Wayland as a normal user application:
#   ~/.local/bin/autokey{,-qt,-gtk,-run,-shell,-headless}
#   application menu entries, icons, udev/uinput access
#
# This is the distribution path for machines without a distro package
# (Fedora COPR / Debian). Runtime does not depend on the git checkout.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: install.sh [options]

Install AutoKey for Wayland into the current user's ~/.local prefix so it
can be launched from the application menu or as `autokey` / `autokey-qt`
/ `autokey-gtk`, without activating a venv by hand.

Options:
  --prefix DIR     User prefix (default: ~/.local)
  --ui auto|qt|gtk|both
                   Frontends to install (default: auto)
  --venv DIR       Virtualenv path (default: PREFIX/share/autokey/venv)
  --skip-system    Do not install udev rules / uinput / input group (no sudo)
  --skip-packages  Do not install distro packages with dnf/apt
  --dev            Editable install into <repo>/.venv (for developing)
  --uninstall      Remove a previous user install (see also uninstall.sh)
  -h, --help       Show this help

Examples:
  ./install.sh
  ./install.sh --ui qt
  ./install.sh --dev
EOF
}

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$SCRIPT_DIR
# Allow calling as scripts/install.sh in the future
if [[ $(basename "$SCRIPT_DIR") == scripts ]]; then
    REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
fi

PREFIX=${PREFIX:-"$HOME/.local"}
UI=auto
VENV=
SKIP_SYSTEM=0
SKIP_PACKAGES=0
DEV=0
DO_UNINSTALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX=$2; shift 2 ;;
        --ui) UI=$2; shift 2 ;;
        --venv) VENV=$2; shift 2 ;;
        --skip-system) SKIP_SYSTEM=1; shift ;;
        --skip-packages) SKIP_PACKAGES=1; shift ;;
        --dev) DEV=1; shift ;;
        --uninstall) DO_UNINSTALL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
done

PREFIX=${PREFIX/#\~/$HOME}
BINDIR=$PREFIX/bin
DATADIR=$PREFIX/share
APPDIR=$DATADIR/applications
ICONDIR=$DATADIR/icons
STATEDIR=$DATADIR/autokey
MANIFEST=$STATEDIR/install-manifest.txt

if [[ -z "$VENV" ]]; then
    if [[ "$DEV" -eq 1 ]]; then
        VENV=$REPO_ROOT/.venv
    else
        VENV=$STATEDIR/venv
    fi
fi

detect_pm() {
    if command -v dnf >/dev/null 2>&1; then
        echo dnf
    elif command -v apt-get >/dev/null 2>&1; then
        echo apt
    else
        echo none
    fi
}

pkg_installed() {
    case "$PM" in
        dnf) rpm -q "$1" >/dev/null 2>&1 ;;
        apt) dpkg -s "$1" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

pkg_available() {
    pkg_installed "$1" && return 0
    case "$PM" in
        dnf) dnf repoquery --quiet --available --qf '%{name}' "$1" 2>/dev/null | grep -qx "$1" ;;
        apt) apt-cache show "$1" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

install_pkgs() {
    local wanted=() p
    for p in "$@"; do
        if pkg_available "$p"; then
            wanted+=("$p")
        else
            warn "distro package not available, skipping: $p"
        fi
    done
    [[ ${#wanted[@]} -eq 0 ]] && return 0
    log "installing packages: ${wanted[*]}"
    case "$PM" in
        dnf) sudo dnf install -y "${wanted[@]}" ;;
        apt) sudo apt-get update -qq && sudo apt-get install -y "${wanted[@]}" ;;
    esac
}

have_sudo() {
    command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null
}

detect_desktop() {
    local d
    d=$(printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')
    case "$d" in
        *kde*|*plasma*) echo kde ;;
        *gnome*) echo gnome ;;
        *) echo other ;;
    esac
}

python_ok() {
    command -v python3 >/dev/null 2>&1 || die "python3 is required"
    if ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)'; then
        die "Python 3.9+ is required (found $(python3 -V))"
    fi
}

record() {
    mkdir -p "$STATEDIR"
    printf '%s\n' "$1" >> "$MANIFEST"
}

write_desktop() {
    local dest=$1 name=$2 comment=$3 exec_path=$4 extra_cats=$5
    mkdir -p "$(dirname "$dest")"
    cat > "$dest" <<EOF
[Desktop Entry]
Name=$name
GenericName=Keyboard Automation
Comment=$comment
Keywords=macros;keyboard;auto;key;autokey;ak;automation;shortcuts;bind;hotkey;autohotkey;mouse;customization;
Exec=$exec_path -c
TryExec=$exec_path
Terminal=false
Type=Application
Icon=autokey
Categories=$extra_cats Utility;
StartupNotify=false
EOF
    record "$dest"
}

install_icons() {
    local src=$REPO_ROOT/config
    install -Dm644 "$src/autokey.svg" "$ICONDIR/hicolor/scalable/apps/autokey.svg"
    install -Dm644 "$src/autokey-status.svg" "$ICONDIR/hicolor/scalable/apps/autokey-status.svg"
    install -Dm644 "$src/autokey-status-dark.svg" "$ICONDIR/hicolor/scalable/apps/autokey-status-dark.svg"
    install -Dm644 "$src/autokey-status-error.svg" "$ICONDIR/hicolor/scalable/apps/autokey-status-error.svg"
    install -Dm644 "$src/autokey.png" "$ICONDIR/hicolor/96x96/apps/autokey.png"
    record "$ICONDIR/hicolor/scalable/apps/autokey.svg"
    record "$ICONDIR/hicolor/scalable/apps/autokey-status.svg"
    record "$ICONDIR/hicolor/scalable/apps/autokey-status-dark.svg"
    record "$ICONDIR/hicolor/scalable/apps/autokey-status-error.svg"
    record "$ICONDIR/hicolor/96x96/apps/autokey.png"
    if [[ -d "$src/Humanity" ]]; then
        mkdir -p "$ICONDIR/Humanity/scalable/apps"
        cp -a "$src/Humanity/." "$ICONDIR/Humanity/scalable/apps/"
        record "$ICONDIR/Humanity/scalable/apps"
    fi
    for theme in ubuntu-mono-dark ubuntu-mono-light; do
        if [[ -d "$src/$theme" ]]; then
            mkdir -p "$ICONDIR/$theme/apps/48"
            cp -a "$src/$theme/." "$ICONDIR/$theme/apps/48/"
            record "$ICONDIR/$theme/apps/48"
        fi
    done
    command -v gtk-update-icon-cache >/dev/null 2>&1 && \
        gtk-update-icon-cache -f -t "$ICONDIR/hicolor" >/dev/null 2>&1 || true
    command -v xdg-icon-resource >/dev/null 2>&1 || true
}

link_cmd() {
    local name=$1 src=$2
    mkdir -p "$BINDIR"
    ln -sfn "$src" "$BINDIR/$name"
    record "$BINDIR/$name"
}

write_dispatcher() {
    local dest=$BINDIR/autokey
    mkdir -p "$BINDIR"
    cat > "$dest" <<EOF
#!/bin/sh
# Prefer the frontend that matches the running desktop.
desktop=\$(printf '%s' "\${XDG_CURRENT_DESKTOP-}" | tr '[:upper:]' '[:lower:]')
bindir=\$(dirname "\$0")
case "\$desktop" in
    *kde*|*plasma*)
        if [ -x "\$bindir/autokey-qt" ]; then exec "\$bindir/autokey-qt" "\$@"; fi
        ;;
esac
if [ -x "\$bindir/autokey-gtk" ]; then exec "\$bindir/autokey-gtk" "\$@"; fi
if [ -x "\$bindir/autokey-qt" ]; then exec "\$bindir/autokey-qt" "\$@"; fi
echo "No AutoKey frontend is installed in \$bindir" >&2
exit 1
EOF
    chmod +x "$dest"
    record "$dest"
}

setup_system() {
    [[ "$SKIP_SYSTEM" -eq 1 ]] && { log "skipping system configuration"; return 0; }
    if ! command -v sudo >/dev/null 2>&1; then
        warn "sudo not found; skip udev/uinput. Wayland injection will not work."
        return 0
    fi
    log "installing udev rule and uinput module (sudo)"
    sudo install -m644 "$REPO_ROOT/config/10-autokey.rules" /etc/udev/rules.d/10-autokey.rules
    printf 'uinput\n' | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
    sudo modprobe uinput 2>/dev/null || warn "could not load uinput now; it will load on next boot"
    sudo udevadm control --reload-rules || true
    sudo udevadm trigger --subsystem-match=misc --action=add || true

    local me
    me=$(id -un)
    if ! id -nG "$me" | grep -qw input; then
        sudo usermod -aG input "$me"
        warn "added $me to group 'input'; log out and back in before using hotkeys"
    fi

    local desktop
    desktop=$(detect_desktop)
    if [[ "$desktop" == gnome ]] && command -v gnome-extensions >/dev/null 2>&1; then
        log "building GNOME Shell extension"
        if [[ -f "$REPO_ROOT/autokey-gnome-extension/Makefile" ]]; then
            make -C "$REPO_ROOT/autokey-gnome-extension" >/dev/null
            local zip
            zip=$(ls "$REPO_ROOT/autokey-gnome-extension/"*.shell-extension.zip 2>/dev/null | head -n1 || true)
            if [[ -n "$zip" ]]; then
                gnome-extensions install --force "$zip" || warn "gnome-extensions install failed"
                gnome-extensions enable autokey-gnome-extension@autokey 2>/dev/null || \
                    warn "enable the AutoKey GNOME extension from Extension Manager after login"
            fi
        fi
    fi
}

compile_qt_resources() {
    command -v pyrcc5 >/dev/null 2>&1 || { warn "pyrcc5 not found; Qt UI will load .ui files from disk"; return 0; }
    local qtui src
    qtui=$("$VENV/bin/python" -c "import autokey.qtui, pathlib; print(pathlib.Path(autokey.qtui.__file__).resolve().parent)")
    src=$REPO_ROOT/lib/autokey/qtui/resources
    [[ -f "$src/resources.qrc" ]] || return 0
    mkdir -p "$qtui/resources/icons"
    cp -a "$src/ui" "$qtui/resources/"
    cp -a "$src/resources.qrc" "$qtui/resources/"
    local ic
    for ic in autokey.png autokey.svg autokey-status.svg autokey-status-dark.svg autokey-status-error.svg; do
        cp "$REPO_ROOT/config/$ic" "$qtui/resources/icons/"
    done
    if ( cd "$qtui/resources" && pyrcc5 resources.qrc > "$qtui/compiled_resources.py" ); then
        log "compiled Qt resources"
    else
        warn "pyrcc5 failed; Qt UI will load .ui files from disk"
        rm -f "$qtui/compiled_resources.py"
    fi
}

ensure_gnome_extension_zip() {
    # setup.py always packages this zip; build a default (GNOME 46) archive
    # even on KDE so the user install does not depend on gnome-shell.
    local dir=$REPO_ROOT/autokey-gnome-extension
    local zip=$dir/autokey-gnome-extension@autokey.shell-extension.zip
    [[ -f "$zip" ]] && return 0
    local ver_dir=46
    if command -v gnome-shell >/dev/null 2>&1; then
        local major
        major=$(gnome-shell --version 2>/dev/null | awk '{print int($3)}')
        case "$major" in
            40|41|42|43|44) ver_dir=44 ;;
        esac
    fi
    command -v zip >/dev/null 2>&1 || die "zip is required to package the GNOME extension"
    ( cd "$dir" && zip -q --junk-paths "$(basename "$zip")" \
        "$ver_dir/extension.js" "$ver_dir/metadata.json" )
    [[ -f "$zip" ]] || die "failed to build $zip"
}

ensure_qsci() {
    local py=$1
    if "$py" -c "from PyQt5 import Qsci" >/dev/null 2>&1; then
        log "QScintilla already available"
        return 0
    fi
    # Distro packages (names differ)
    if [[ "$SKIP_PACKAGES" -eq 0 ]]; then
        case "$PM" in
            dnf) install_pkgs python3-qscintilla-qt5 python3-QScintilla || true ;;
            apt) install_pkgs python3-pyqt5.qsci || true ;;
        esac
        if "$py" -c "from PyQt5 import Qsci" >/dev/null 2>&1; then
            log "QScintilla provided by distro package"
            return 0
        fi
    fi
    local cached
    cached=$(ls "$REPO_ROOT"/.qscintilla-build/dist/qscintilla-*.whl 2>/dev/null | head -n1 || true)
    if [[ -n "$cached" ]]; then
        log "installing cached wheel $(basename "$cached")"
        if "$py" -m pip install --force-reinstall --no-deps "$cached" \
            && "$py" -c "from PyQt5 import Qsci" >/dev/null 2>&1; then
            return 0
        fi
        warn "cached QScintilla wheel did not import; building from source"
    fi
    log "building QScintilla against system Qt"
    bash "$REPO_ROOT/scripts/build-qscintilla.sh" "$py" "$REPO_ROOT/.qscintilla-build/dist"
}

uninstall_user() {
    log "removing user install (prefix=$PREFIX)"
    if [[ -f "$MANIFEST" ]]; then
        while IFS= read -r path; do
            [[ -z "$path" ]] && continue
            if [[ -L "$path" || -f "$path" ]]; then
                rm -f "$path"
            elif [[ -d "$path" ]]; then
                rm -rf "$path"
            fi
        done < "$MANIFEST"
        rm -f "$MANIFEST"
    fi
    rm -rf "$STATEDIR/venv"
    rm -f "$BINDIR/autokey" "$BINDIR/autokey-qt" "$BINDIR/autokey-gtk" \
          "$BINDIR/autokey-run" "$BINDIR/autokey-shell" "$BINDIR/autokey-headless"
    rm -f "$APPDIR/autokey-qt.desktop" "$APPDIR/autokey-gtk.desktop" "$APPDIR/autokey.desktop"
    command -v update-desktop-database >/dev/null 2>&1 && \
        update-desktop-database "$APPDIR" >/dev/null 2>&1 || true
    log "user files removed. System udev/uinput left in place (use uninstall.sh --purge-system)."
}

# ---------- main ----------
if [[ "$DO_UNINSTALL" -eq 1 ]]; then
    uninstall_user
    exit 0
fi

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    die "do not run as root; sudo is used only for udev/uinput"
fi

[[ -f "$REPO_ROOT/setup.py" ]] || die "run this from the autokey-wayland tree"
python_ok

PM=$(detect_pm)
DESKTOP=$(detect_desktop)
SESSION=${XDG_SESSION_TYPE:-unknown}
log "prefix=$PREFIX  ui=$UI  desktop=$DESKTOP  session=$SESSION  pm=$PM"

if [[ "$SKIP_PACKAGES" -eq 0 ]]; then
    case "$PM" in
        dnf)
            pkgs=(
                python3-devel python3-pip python3-setuptools
                python3-qt5-base python3-qt5-devel qt5-qtbase-devel
                python3-gobject python3-dbus python3-pyudev python3-file-magic
                gtksourceview3 libayatana-appindicator-gtk3
                wmctrl wl-clipboard zenity kdialog zip
                python3-pydbus
            )
            if [[ "$DESKTOP" == gnome ]]; then
                pkgs+=(gnome-extensions-app)
            fi
            install_pkgs "${pkgs[@]}"
            ;;
        apt)
            install_pkgs \
                python3-dev python3-pip python3-setuptools python3-venv \
                python3-pyqt5 python3-pyqt5.qsci python3-pyqt5.qtsvg pyqt5-dev-tools \
                python3-gi python3-dbus python3-pyudev python3-pydbus \
                gir1.2-gtk-3.0 gir1.2-gtksource-3.0 gir1.2-notify-0.7 \
                gir1.2-ayatanaappindicator3-0.1 \
                wmctrl wl-clipboard zenity kdialog
            ;;
        none)
            warn "no dnf/apt; assuming build dependencies are already installed"
            ;;
    esac
fi

# qmake name differs across distros
if ! command -v qmake >/dev/null 2>&1 && command -v qmake-qt5 >/dev/null 2>&1; then
    mkdir -p "$BINDIR"
    ln -sfn "$(command -v qmake-qt5)" "$BINDIR/qmake"
    record "$BINDIR/qmake"
    export PATH="$BINDIR:$PATH"
fi

if [[ "$DEV" -eq 1 ]]; then
    log "creating development venv at $VENV"
    if [[ -e "$VENV" && ! -O "$VENV" ]]; then
        warn "$VENV is not owned by $(id -un); taking ownership"
        sudo chown -R "$(id -un):$(id -gn)" "$VENV"
    fi
    python3 -m venv --system-site-packages "$VENV"
else
    log "creating runtime venv at $VENV"
    python3 -m venv --system-site-packages "$VENV"
fi
# shellcheck disable=SC1091
source "$VENV/bin/activate"
python -m pip install -U pip setuptools wheel

# Distro Python packages (PyQt5, PyGObject, dbus, pyinotify) come from
# system-site-packages. Do not pip-install PyQt5/QScintilla extras — those
# wheels bundle a private Qt and break against distro PyQt5.
pip_pkgs=(packaging evdev pydbus python-xlib python-magic pyhamcrest)
if python -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 12) else 1)'; then
    pip_pkgs+=(pyasyncore)
fi
python -m pip install "${pip_pkgs[@]}"

WANT_QT=0
WANT_GTK=0
case "$UI" in
    qt) WANT_QT=1 ;;
    gtk) WANT_GTK=1 ;;
    both) WANT_QT=1; WANT_GTK=1 ;;
    auto)
        if python -c "from PyQt5 import QtWidgets" >/dev/null 2>&1; then WANT_QT=1; fi
        if python -c "from gi.repository import Gtk" >/dev/null 2>&1; then WANT_GTK=1; fi
        if [[ "$WANT_QT" -eq 0 && "$WANT_GTK" -eq 0 ]]; then
            die "neither PyQt5 nor GTK (PyGObject) is importable"
        fi
        if [[ "$DESKTOP" == kde && "$WANT_QT" -eq 1 ]]; then
            : # keep both if present; launcher prefers Qt
        fi
        ;;
    *) die "invalid --ui $UI" ;;
esac

if [[ "$WANT_QT" -eq 1 ]]; then
    python -c "from PyQt5 import QtWidgets" >/dev/null 2>&1 || \
        die "PyQt5 is required for the Qt UI (install python3-qt5-base / python3-pyqt5)"
    ensure_qsci "$(command -v python)"
fi

log "installing AutoKey into the venv"
ensure_gnome_extension_zip
if [[ "$DEV" -eq 1 ]]; then
    python -m pip install --no-deps -e "$REPO_ROOT"
else
    python -m pip install --no-deps "$REPO_ROOT"
fi
compile_qt_resources

mkdir -p "$BINDIR" "$APPDIR" "$STATEDIR"
: > "$MANIFEST"
record "$VENV"

write_dispatcher
[[ -x "$VENV/bin/autokey-qt" ]] && link_cmd autokey-qt "$VENV/bin/autokey-qt"
[[ -x "$VENV/bin/autokey-gtk" ]] && link_cmd autokey-gtk "$VENV/bin/autokey-gtk"
[[ -x "$VENV/bin/autokey-run" ]] && link_cmd autokey-run "$VENV/bin/autokey-run"
[[ -x "$VENV/bin/autokey-shell" ]] && link_cmd autokey-shell "$VENV/bin/autokey-shell"
[[ -x "$VENV/bin/autokey-headless" ]] && link_cmd autokey-headless "$VENV/bin/autokey-headless"

install_icons
if [[ "$WANT_QT" -eq 1 && -x "$BINDIR/autokey-qt" ]]; then
    write_desktop "$APPDIR/autokey-qt.desktop" \
        "AutoKey (Qt)" "Program keyboard shortcuts" "$BINDIR/autokey-qt" "Qt;"
fi
if [[ "$WANT_GTK" -eq 1 && -x "$BINDIR/autokey-gtk" ]]; then
    write_desktop "$APPDIR/autokey-gtk.desktop" \
        "AutoKey (GTK)" "Program keyboard shortcuts" "$BINDIR/autokey-gtk" "GTK;"
fi
# Generic name that follows the desktop
write_desktop "$APPDIR/autokey.desktop" \
    "AutoKey" "Program keyboard shortcuts" "$BINDIR/autokey" "GTK;Qt;"

command -v update-desktop-database >/dev/null 2>&1 && \
    update-desktop-database "$APPDIR" >/dev/null 2>&1 || true

if [[ -d "$REPO_ROOT/doc/man" ]]; then
    mkdir -p "$DATADIR/man/man1"
    for man in autokey-qt.1 autokey-gtk.1 autokey-run.1; do
        if [[ -f "$REPO_ROOT/doc/man/$man" ]]; then
            install -m644 "$REPO_ROOT/doc/man/$man" "$DATADIR/man/man1/$man"
            record "$DATADIR/man/man1/$man"
        fi
    done
fi

setup_system

deactivate || true

log "installed"
printf '\n'
printf '  Commands:  %s/autokey   %s/autokey-qt   %s/autokey-gtk\n' "$BINDIR" "$BINDIR" "$BINDIR"
printf '  Menu:      AutoKey / AutoKey (Qt)\n'
if ! printf '%s' ":$PATH:" | grep -q ":$BINDIR:"; then
    warn "$BINDIR is not on PATH. Add this to ~/.bashrc or ~/.profile:"
    printf '    export PATH="%s:\$PATH"\n' "$BINDIR"
fi
if [[ ! -e /dev/uinput ]]; then
    warn "/dev/uinput is missing; reboot or: sudo modprobe uinput"
fi
printf '\nStart with:\n  autokey\n  autokey-qt\n  autokey-gtk -v\n'
printf '\nUninstall:\n  %s/install.sh --uninstall\n' "$REPO_ROOT"
