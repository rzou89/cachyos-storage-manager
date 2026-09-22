#!/usr/bin/env bash
# ============================================================
# CachyOS Storage Manager - v0.4.1 init.fish fix
#   - setup: mkdir pakai layout baru (Flatpak/Flatpak Core, Flatpak/Flatpak Data)
#   - setup: teks echo struktur folder
#   - setup: prompt migrate pindah ke folder baru
#   - relocate: pakai layout baru
# ============================================================
set -euo pipefail

REPO="${1:-/mnt/DataCachyOS/Projects/cachyos-storage-manager}"
cd "$REPO"

python3 - << 'PYEOF'
import pathlib, re
p = pathlib.Path("scripts/modules/init.fish")
s = p.read_text()

changes = []

# ---------- 1. setup: echo struktur + mkdir ----------
old = '''    echo "Struktur folder yang akan dibuat:"
    echo "  $root/"
    echo "    ├── flatpak/"
    echo "    ├── paru/"
    echo "    ├── pacman/        (reserved)"
    echo "    └── data cache/    (reserved)"
    echo ""

    if not csm_confirm "Lanjut?" "Y"
        return 1
    end

    mkdir -p "$root/flatpak" "$root/paru" "$root/pacman" "$root/data cache"
    csm_ok "Folder dibuat"'''

new = '''    echo "Struktur folder yang akan dibuat:"
    echo "  $root/"
    echo "    ├── Flatpak/"
    echo "    │   ├── Flatpak Core/   (installation, isi manual dengan sudo)"
    echo "    │   └── Flatpak Data/   (data user)"
    echo "    ├── paru/"
    echo "    ├── pacman/             (reserved)"
    echo "    └── data cache/         (reserved)"
    echo ""

    if not csm_confirm "Lanjut?" "Y"
        return 1
    end

    mkdir -p "$root/Flatpak/Flatpak Core" \\
             "$root/Flatpak/Flatpak Data" \\
             "$root/paru" \\
             "$root/pacman" \\
             "$root/data cache"
    csm_ok "Folder dibuat"'''

if old in s:
    s = s.replace(old, new, 1)
    changes.append("setup folder creation")
else:
    # Fallback: only replace the mkdir line
    old_line = '    mkdir -p "$root/flatpak" "$root/paru" "$root/pacman" "$root/data cache"'
    new_line = '''    mkdir -p "$root/Flatpak/Flatpak Core" \\
             "$root/Flatpak/Flatpak Data" \\
             "$root/paru" \\
             "$root/pacman" \\
             "$root/data cache"'''
    if old_line in s:
        s = s.replace(old_line, new_line, 1)
        changes.append("setup folder creation (mkdir only — echo block manual)")
    else:
        changes.append("WARN: setup folder block not found")

# ---------- 2. relocate: variable definitions ----------
old = '''    set -l new_flatpak "$new_root/flatpak"
    set -l new_paru "$new_root/paru"'''

new = '''    set -l new_flatpak "$new_root/Flatpak/Flatpak Data"
    set -l new_flatpak_core "$new_root/Flatpak/Flatpak Core"
    set -l new_paru "$new_root/paru"'''

if old in s:
    s = s.replace(old, new, 1)
    changes.append("relocate variables")
else:
    changes.append("WARN: relocate variable block not found")

# ---------- 3. relocate: mkdir ----------
old = '''    # Prepare new folders
    mkdir -p "$new_flatpak" "$new_paru"'''

new = '''    # Prepare new folders
    mkdir -p "$new_flatpak" "$new_flatpak_core" "$new_paru"'''

if old in s:
    s = s.replace(old, new, 1)
    changes.append("relocate mkdir")
else:
    changes.append("WARN: relocate mkdir block not found")

p.write_text(s)

for c in changes:
    print(c)
PYEOF

echo
echo "==> Syntax check"
fish -n scripts/modules/init.fish && echo "OK: init.fish" || { echo "FAIL"; exit 1; }

echo
echo "==> Done"