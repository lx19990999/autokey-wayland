#!/usr/bin/env bash
# Build QScintilla against the PyQt5/Qt already visible to $PYTHON.
# Needed when the distro has PyQt5 but no matching QScintilla package
# (PyPI wheels are linked to Riverbank's bundled Qt and will fail to import).
set -euo pipefail

PYTHON=${1:?usage: build-qscintilla.sh PYTHON [wheel-dir]}
WHEEL_DIR=${2:-}

QSCINTILLA_VERSION=${QSCINTILLA_VERSION:-2.14.1}

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

"$PYTHON" -c "from PyQt5 import Qsci" >/dev/null 2>&1 && {
    log "PyQt5.Qsci already importable; skipping QScintilla build"
    exit 0
}

BINDINGS=$("$PYTHON" - <<'PY'
import os
from pathlib import Path
try:
    import PyQt5
except ImportError:
    raise SystemExit("")
roots = [Path(PyQt5.__file__).resolve().parent / "bindings"]
# system-site-packages venv: sip looks in the venv, bindings live under /usr
import sys
for p in sys.path:
    cand = Path(p) / "PyQt5" / "bindings"
    if cand.is_dir():
        roots.append(cand)
for r in roots:
    if (r / "QtCore" / "QtCoremod.sip").is_file():
        print(r)
        break
PY
)
[[ -n "$BINDINGS" ]] || die "PyQt5 SIP bindings not found (install python3-qt5-devel / pyqt5-dev)"

QMAKE=${QMAKE:-}
if [[ -z "$QMAKE" ]]; then
    for c in qmake-qt5 qmake; do
        if command -v "$c" >/dev/null 2>&1; then
            QMAKE=$(command -v "$c")
            break
        fi
    done
fi
[[ -n "$QMAKE" && -x "$QMAKE" ]] || die "qmake not found (install qt5-qtbase-devel / qtbase5-dev)"

ABI=$("$PYTHON" - <<PY
from pathlib import Path
toml = Path(r"$BINDINGS") / "QtCore" / "QtCore.toml"
text = toml.read_text(encoding="utf-8") if toml.is_file() else ""
abi = "12.15"
for line in text.splitlines():
    if line.startswith("sip-abi-version"):
        abi = line.split("=", 1)[1].strip().strip("\"'")
        break
print(abi)
PY
)

log "QScintilla $QSCINTILLA_VERSION  (qmake=$QMAKE  bindings=$BINDINGS  abi=$ABI)"

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/qscintilla-build.XXXXXX")
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

TARBALL="$WORKDIR/QScintilla-${QSCINTILLA_VERSION}.tar.gz"
URLS=(
    "https://pypi.tuna.tsinghua.edu.cn/packages/a9/f6/a7aa4b495dcee4c521b87205de9363fb62ee5fdc8eab91d4ddb97257c85b/QScintilla-${QSCINTILLA_VERSION}.tar.gz"
    "https://files.pythonhosted.org/packages/a9/f6/a7aa4b495dcee4c521b87205de9363fb62ee5fdc8eab91d4ddb97257c85b/QScintilla-${QSCINTILLA_VERSION}.tar.gz"
)
downloaded=0
for url in "${URLS[@]}"; do
    log "downloading $url"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$TARBALL" "$url" && downloaded=1 && break
    else
        wget -q -O "$TARBALL" "$url" && downloaded=1 && break
    fi
done
[[ "$downloaded" -eq 1 ]] || die "failed to download QScintilla sdist"

tar -xzf "$TARBALL" -C "$WORKDIR"
SRC="$WORKDIR/QScintilla-${QSCINTILLA_VERSION}"
[[ -d "$SRC" ]] || die "unexpected sdist layout"

# sip-build only searches venv/PyQt5/bindings, not system-site-packages.
cat >> "$SRC/pyproject.toml" <<EOF

[tool.sip.project]
sip-include-dirs = ["$BINDINGS"]
abi-version = "$ABI"

[tool.sip.builder]
qmake = "$QMAKE"
EOF

# sip >= 6.10 defaults to ABI v13; PyQt5.sip is ABI 12.x.
if ! grep -q '%MinimumABIVersion' "$SRC/sip/qscimod5.sip"; then
    python3 - <<PY
from pathlib import Path
p = Path(r"$SRC/sip/qscimod5.sip")
text = p.read_text(encoding="utf-8")
needle = '%Module(name=PyQt5.Qsci, keyword_arguments="Optional", use_limited_api=True)'
insert = needle + '\n\n// Keep ABI 12 to match system PyQt5.sip\n%MinimumABIVersion "12.0"'
if needle not in text:
    raise SystemExit("qscimod5.sip %Module line not found")
p.write_text(text.replace(needle, insert, 1), encoding="utf-8")
PY
fi

"$PYTHON" -m pip install -q "sip>=6.7,<7" "PyQt-builder>=1.6,<2"

export PATH="$(dirname "$QMAKE"):${PATH:-}"
export QMAKE
export MAKEFLAGS="${MAKEFLAGS:--j$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"

DIST=${WHEEL_DIR:-"$WORKDIR/dist"}
mkdir -p "$DIST"
log "compiling QScintilla (this can take a minute)"
( cd "$SRC" && "$PYTHON" -m pip wheel --no-build-isolation --no-deps --no-cache-dir -w "$DIST" . )

WHEEL=$(ls "$DIST"/qscintilla-"${QSCINTILLA_VERSION}"-*.whl 2>/dev/null | head -n1)
[[ -n "$WHEEL" ]] || die "wheel was not produced"
log "installing $(basename "$WHEEL")"
"$PYTHON" -m pip install --force-reinstall --no-deps "$WHEEL"
"$PYTHON" -c "from PyQt5.Qsci import QsciScintilla; print('Qsci OK', QsciScintilla)"
