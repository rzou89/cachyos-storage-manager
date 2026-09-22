#!/usr/bin/env bash
# ============================================================
# CachyOS Storage Manager - v0.4.1 patch B
# Fix bugs:
#   #1 csm setup: create new layout subfolders
#   #2 csm flatpak migrate: adopt existing symlinks + move data
#   #3 csm flatpak status: show CSM_FLATPAK_DIR
#   #4 common.fish: CSM_FLATPAK_CORE_DIR normalize
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
# 1. common.fish - add CSM_FLATPAK_CORE_DIR to normalize
# ------------------------------------------------------------
python3 - << 'PYEOF'
import pathlib
p = pathlib.Path("scripts/modules/common.fish")
s = p.read_text()

anchor = """    if not set -q CSM_PARU_DIR
        if set -q CSM_PARU_CLONE_DIR
            set -g CSM_PARU_DIR "$CSM_PARU_CLONE_DIR"
        else if set -q CSM_ROOT
            set -g CSM_PARU_DIR "$CSM_ROOT/paru"
        end
    end"""

addition = """    if not set -q CSM_FLATPAK_CORE_DIR
        if set -q CSM_ROOT
            set -g CSM_FLATPAK_CORE_DIR "$CSM_ROOT/Flatpak/Flatpak Core"
        else if set -q CSM_TARGET
            set -g CSM_FLATPAK_CORE_DIR "$CSM_TARGET/CachyOS Storage Data Migration/Flatpak/Flatpak Core"
        end
    end

""" + anchor

if "CSM_FLATPAK_CORE_DIR" in s and "not set -q CSM_FLATPAK_CORE_DIR" in s:
    print("SKIP: CSM_FLATPAK_CORE_DIR normalize already present")
elif anchor in s:
    s = s.replace(anchor, addition, 1)
    p.write_text(s)
    print("OK: CSM_FLATPAK_CORE_DIR added to normalize_config")
else:
    raise SystemExit("ERROR: could not find CSM_PARU_DIR anchor in common.fish")
PYEOF

echo "==> patched common.fish"

# ------------------------------------------------------------
# 2. flatpak.fish
#    2a. status: show CSM_FLATPAK_DIR
#    2b. migrate: adopt existing symlinks + move data if needed
# ------------------------------------------------------------
python3 - << 'PYEOF'
import pathlib
p = pathlib.Path("scripts/modules/flatpak.fish")
s = p.read_text()

# --- 2a: status block ---
old = """    set -l INSTALLATION (__csm_flatpak_installation)
    set -l DEST ""
    if set -q CSM_FLATPAK_DATA_DIR
        set DEST "$CSM_FLATPAK_DATA_DIR"
    end"""

new = """    set -l INSTALLATION (__csm_flatpak_installation)
    set -l DEST ""
    if set -q CSM_FLATPAK_DIR
        set DEST "$CSM_FLATPAK_DIR"
    else if set -q CSM_FLATPAK_DATA_DIR
        set DEST "$CSM_FLATPAK_DATA_DIR"
    end"""

if new in s:
    print("SKIP: status block already updated")
elif old in s:
    s = s.replace(old, new, 1)
    print("OK: status block updated")
else:
    print("WARN: status block pattern not found, skipping")

# --- 2b: migrate symlink handling ---
old = """        # Already migrated
        if test -L "$app_dir"
            echo "SKIP linked: $app_id"
            continue
        end"""

new = """        # Symlink handling: adopt, relink, or move
        if test -L "$app_dir"
            set -l current_target (readlink "$app_dir")
            set -l desired_target "$DEST/$app_id"

            # Correct: symlink already points to target
            if test "$current_target" = "$desired_target"
                echo "SKIP linked (correct): $app_id"
                continue
            end

            # Data already at new target, only the symlink is stale
            if test -d "$desired_target"
                echo "RELINK: $app_id"
                echo "  from: $current_target"
                echo "  to  : $desired_target"
                rm "$app_dir"
                ln -s "$desired_target" "$app_dir"
                if test $status -eq 0
                    echo "  OK: $app_id"
                else
                    echo "  ERROR: relink failed"
                end
                continue
            end

            # Data still at old target: move then relink
            if test -d "$current_target"
                echo "MOVE+RELINK: $app_id"
                echo "  from: $current_target"
                echo "  to  : $desired_target"
                mkdir -p (dirname "$desired_target")
                mv "$current_target" "$desired_target"
                if test $status -ne 0
                    echo "  ERROR: move failed, symlink untouched"
                    continue
                end
                rm "$app_dir"
                ln -s "$desired_target" "$app_dir"
                if test $status -eq 0
                    echo "  OK: $app_id"
                else
                    echo "  ERROR: relink failed, data is at $desired_target"
                end
                continue
            end

            # Broken symlink
            echo "SKIP broken symlink: $app_id -> $current_target"
            continue
        end"""

if "adopt, relink, or move" in s:
    print("SKIP: migrate symlink handling already updated")
elif old in s:
    s = s.replace(old, new, 1)
    print("OK: migrate symlink handling updated")
else:
    raise SystemExit("ERROR: could not find migrate 'Already migrated' block")

p.write_text(s)
PYEOF

echo "==> patched flatpak.fish"

# ------------------------------------------------------------
# 3. init.fish
#    3a. setup: create new subfolders (Flatpak/Flatpak Core, Flatpak/Flatpak Data)
#    3b. write_config: emit CSM_FLATPAK_DIR + CSM_FLATPAK_CORE_DIR
# ------------------------------------------------------------
python3 - << 'PYEOF'
import pathlib
p = pathlib.Path("scripts/modules/init.fish")
s = p.read_text()

# --- 3a: folder creation in csm_setup ---
old = """    echo "Struktur folder yang akan dibuat:"
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
    csm_ok "Folder dibuat" """

new = """    echo "Struktur folder yang akan dibuat:"
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
    csm_ok "Folder dibuat" """

if "Flatpak/Flatpak Core" in s and "Flatpak/Flatpak Data" in s and "mkdir -p" in s:
    if old in s:
        s = s.replace(old, new, 1)
        print("OK: setup folder creation updated")
    else:
        print("SKIP/WARN: setup folder block already updated or not matched")
elif old in s:
    s = s.replace(old, new, 1)
    print("OK: setup folder creation updated")
else:
    print("WARN: setup folder creation pattern not found")

# --- 3b: write_config emits new vars ---
old = """        echo "set -g CSM_FLATPAK_DIR \\"\\$CSM_ROOT/flatpak\\""
        echo "set -g CSM_FLATPAK_INSTALLATION \\"$installation\\""
        echo "set -g CSM_FLATPAK_WATCH $watch\""""

new = """        echo "set -g CSM_FLATPAK_DIR \\"\\$CSM_ROOT/Flatpak/Flatpak Data\\""
        echo "set -g CSM_FLATPAK_CORE_DIR \\"\\$CSM_ROOT/Flatpak/Flatpak Core\\""
        echo "set -g CSM_FLATPAK_INSTALLATION \\"$installation\\""
        echo "set -g CSM_FLATPAK_WATCH $watch\""""

if "CSM_FLATPAK_CORE_DIR" in s:
    print("SKIP: write_config already emits CSM_FLATPAK_CORE_DIR")
elif old in s:
    s = s.replace(old, new, 1)
    print("OK: write_config updated")
else:
    # Try a looser search
    old_loose = 'echo "set -g CSM_FLATPAK_DIR \\"\\$CSM_ROOT/flatpak\\""'
    if old_loose in s:
        s = s.replace(
            old_loose,
            'echo "set -g CSM_FLATPAK_DIR \\"\\$CSM_ROOT/Flatpak/Flatpak Data\\""\n'
            '        echo "set -g CSM_FLATPAK_CORE_DIR \\"\\$CSM_ROOT/Flatpak/Flatpak Core\\""',
            1)
        print("OK: write_config updated (loose match)")
    else:
        print("WARN: write_config flatpak line not found, skipping")

p.write_text(s)
PYEOF

echo "==> patched init.fish"

# ------------------------------------------------------------
# 4. syntax checks
# ------------------------------------------------------------
echo
echo "==> Syntax checks"
for f in scripts/csm.fish scripts/modules/common.fish scripts/modules/flatpak.fish scripts/modules/paru.fish scripts/modules/init.fish; do
    if fish -n "$f"; then
        echo "OK: $f"
    else
        echo "FAIL: $f"
        exit 1
    fi
done

echo
echo "==> Done. Next: v041-c.sh"