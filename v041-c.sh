#!/usr/bin/env bash
# ============================================================
# CachyOS Storage Manager - v0.4.1 patch C
# Update README + refresh install + commit + tag + push
# ============================================================
set -euo pipefail

REPO="${1:-/mnt/DataCachyOS/Projects/cachyos-storage-manager}"
cd "$REPO"

if [ ! -d .git ]; then
    echo "ERROR: not a git repo: $REPO" >&2
    exit 1
fi

echo "==> Repo: $REPO"
echo

# ------------------------------------------------------------
# 1. README - update config table + folder layout
# ------------------------------------------------------------
python3 - << 'PYEOF'
import pathlib
p = pathlib.Path("README.md")
s = p.read_text()

# --- 1a. folder layout block ---
old = """    <target>/CachyOS Storage Data Migration/
      ├── flatpak/
      ├── paru/
      ├── pacman/        (reserved)
      └── data cache/    (reserved)"""

new = """    <target>/CachyOS Storage Data Migration/
      ├── Flatpak/
      │   ├── Flatpak Core/   (installation, see below)
      │   └── Flatpak Data/   (user data)
      ├── paru/
      ├── pacman/             (reserved)
      └── data cache/         (reserved)

The Flatpak **core** (application binaries, runtime, repo) is a separate
Flatpak installation, registered in `/etc/flatpak/installations.d/`.
By default `csm setup` does not move it — it only creates the folder
placeholder. See the tutorial for moving it manually."""

if old in s:
    s = s.replace(old, new, 1)
    print("OK: README folder layout")
else:
    print("SKIP: README folder layout not found (maybe already updated)")

# --- 1b. config table: CSM_FLATPAK_DIR ---
old = "`CSM_FLATPAK_DIR` | `$CSM_ROOT/flatpak` | Flatpak user data location."
new = "`CSM_FLATPAK_DIR` | `$CSM_ROOT/Flatpak/Flatpak Data` | Flatpak user data location."
if old in s:
    s = s.replace(old, new, 1)
    print("OK: README CSM_FLATPAK_DIR row")
else:
    print("SKIP: CSM_FLATPAK_DIR row already updated or not found")

# --- 1c. config table: add CSM_FLATPAK_CORE_DIR row ---
old = "`CSM_FLATPAK_INSTALLATION` | `datacachyos` | Custom Flatpak installation name."
new = ("`CSM_FLATPAK_CORE_DIR` | `$CSM_ROOT/Flatpak/Flatpak Core` | Flatpak installation path (reserved; `csm setup` only creates the folder).\n"
       "`CSM_FLATPAK_INSTALLATION` | `datacachyos` | Custom Flatpak installation name.")
if "CSM_FLATPAK_CORE_DIR` | `$CSM_ROOT" in s:
    print("SKIP: CSM_FLATPAK_CORE_DIR row already present")
elif old in s:
    s = s.replace(old, new, 1)
    print("OK: README CSM_FLATPAK_CORE_DIR row added")
else:
    print("SKIP: CSM_FLATPAK_INSTALLATION row not found")

# --- 1d. bump badge version ---
s = s.replace("badge/version-0.4.0-blue", "badge/version-0.4.1-blue", 1)

p.write_text(s)
PYEOF

echo "==> patched README.md"

# ------------------------------------------------------------
# 2. Refresh install
# ------------------------------------------------------------
echo
echo "==> Refresh install (./setup.fish)"
./setup.fish

# ------------------------------------------------------------
# 3. Smoke tests
# ------------------------------------------------------------
echo
echo "==> Smoke tests"
echo "-- csm version --"
csm version
echo
echo "-- csm flatpak status --"
csm flatpak status
echo
echo "-- csm paru status --"
csm paru status

# ------------------------------------------------------------
# 4. Commit + tag + push
# ------------------------------------------------------------
echo
echo "==> Commit + tag + push"

git add -A

if git diff --cached --quiet; then
    echo "Nothing to commit."
else
    git commit -m "fix(v0.4.1): adopt new layout, fix status, relink on migrate

- csm flatpak status now shows CSM_FLATPAK_DIR (was legacy only)
- csm flatpak migrate now relinks existing symlinks, moves data if
  needed (adopt/relink/move)
- csm setup creates Flatpak/Flatpak Core and Flatpak/Flatpak Data
  subfolders, writes CSM_FLATPAK_DIR and CSM_FLATPAK_CORE_DIR
- common.fish normalizes CSM_FLATPAK_CORE_DIR
- config.fish.example reflects the new layout
- README updated"
fi

# Tag (recreate if exists)
if git rev-parse -q --verify "refs/tags/v0.4.1" >/dev/null; then
    echo "==> tag v0.4.1 exists, moving to HEAD"
    git tag -d v0.4.1
fi
git tag -a v0.4.1 -m "v0.4.1 - Layout adoption and fixes"

echo
echo "==> Pushing main..."
git push origin main

echo
echo "==> Pushing tag v0.4.1..."
if ! git push origin v0.4.1 2>/dev/null; then
    echo "==> tag on remote exists, deleting and re-pushing"
    git push origin --delete v0.4.1
    git push origin v0.4.1
fi

echo
echo "========================================"
echo " DONE - v0.4.1"
echo "========================================"
echo
git log --oneline -6
echo
git tag
echo
echo "Next: publish release v0.4.1 at"
echo "  https://github.com/rzou89/cachyos-storage-manager/releases/new"