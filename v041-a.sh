#!/usr/bin/env bash
# ============================================================
# CachyOS Storage Manager - v0.4.1 patch A
# Update: config/config.fish.example + CHANGELOG.md
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
# 1. config/config.fish.example
# ------------------------------------------------------------
cat > config/config.fish.example << 'CFG_EOF'
# ============================================================
# CachyOS Storage Manager - Configuration Example
#
# Copy this file to:
#   ~/.config/cachyos-storage-manager/config.fish
#
# Or simply run:
#   csm setup
#
# which generates this file interactively.
# ============================================================

# ------------------------------------------------------------
# Global
# ------------------------------------------------------------

# Drive where all CSM-managed data will live.
# Must be an absolute path, on a separate filesystem from /.
set -g CSM_TARGET "/mnt/DataCachyOS"

# Base folder for everything CSM manages on the target drive.
set -g CSM_ROOT "$CSM_TARGET/CachyOS Storage Data Migration"

# Create a backup before migrating? (1 = yes, 0 = no)
set -g CSM_BACKUP_BEFORE_MIGRATE 1

# ------------------------------------------------------------
# Flatpak
# ------------------------------------------------------------

# Flatpak application data (user data: config, cache, savegames).
# Symlinked from ~/.var/app/<app-id>.
set -g CSM_FLATPAK_DIR "$CSM_ROOT/Flatpak/Flatpak Data"

# Flatpak core installation (application binaries, runtime, repo).
# Registered with Flatpak via /etc/flatpak/installations.d/.
# Change only if you have a custom Flatpak installation on the target drive.
set -g CSM_FLATPAK_CORE_DIR "$CSM_ROOT/Flatpak/Flatpak Core"

# Name of the custom Flatpak installation.
# Find yours with: flatpak --installations
set -g CSM_FLATPAK_INSTALLATION "datacachyos"

# Enable the Flatpak data watcher? (1 = yes, 0 = no)
set -g CSM_FLATPAK_WATCH 1

# ------------------------------------------------------------
# Paru
# ------------------------------------------------------------

# Where paru clones AUR repositories.
# Will be symlinked from ~/.cache/paru/clone.
set -g CSM_PARU_DIR "$CSM_ROOT/paru"

# ------------------------------------------------------------
# Pacman (reserved, not used yet)
# ------------------------------------------------------------

set -g CSM_PACMAN_DIR "$CSM_ROOT/pacman"

# ------------------------------------------------------------
# User Cache (reserved, not used yet)
# ------------------------------------------------------------

set -g CSM_CACHE_DIR "$CSM_ROOT/data cache"

# Folders under ~/.cache to migrate.
set -g CSM_CACHE_MIGRATE paru yay thumbnails mozilla chromium \
    BraveSoftware spotify discord telegram Code JetBrains \
    pip npm yarn go-build

# Folders under ~/.cache to NEVER migrate.
set -g CSM_CACHE_SKIP mesa_shader_cache mesa_shader_cache_db \
    fontconfig dconf ibus fcitx5
CFG_EOF

echo "==> wrote config/config.fish.example"

# ------------------------------------------------------------
# 2. CHANGELOG.md - add 0.4.1 section
# ------------------------------------------------------------
python3 - << 'PYEOF'
import pathlib
p = pathlib.Path("CHANGELOG.md")
s = p.read_text()

if "## [0.4.1]" in s:
    print("SKIP: CHANGELOG already has 0.4.1")
else:
    old = "## [Unreleased]\n"
    new = """## [Unreleased]

## [0.4.1] - 2026-09-23

### Fixed

- `csm flatpak status` now correctly shows the Flatpak data directory
  (was reading only the legacy `CSM_FLATPAK_DATA_DIR` variable)
- `csm flatpak migrate` now relinks existing symlinks that point to a
  different target, so migrating to a new layout no longer requires
  manual `rm`/`ln` per app
- `csm setup` now creates the `Flatpak/Flatpak Core` and
  `Flatpak/Flatpak Data` subfolders and writes both
  `CSM_FLATPAK_DIR` and `CSM_FLATPAK_CORE_DIR`

### Added

- New config variable `CSM_FLATPAK_CORE_DIR` (Flatpak installation path,
  default `$CSM_ROOT/Flatpak/Flatpak Core`)

### Changed

- `config.fish.example` now reflects the folder layout used by `csm setup`:
  `<target>/CachyOS Storage Data Migration/Flatpak/{Flatpak Core,Flatpak Data}/`
"""
    if old not in s:
        raise SystemExit("ERROR: '## [Unreleased]' not found")
    s = s.replace(old, new, 1)
    p.write_text(s)
    print("OK: CHANGELOG updated")
PYEOF

echo "==> CHANGELOG.md updated"
echo
echo "==> Done. Next: v041-b.sh"