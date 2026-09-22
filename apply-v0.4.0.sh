#!/usr/bin/env bash
# ============================================================
# CachyOS Storage Manager - apply v0.4.0
# Setup wizard + relocate + edit + docs/tutorial.md
# ============================================================
set -euo pipefail

REPO="${1:-/mnt/DataCachyOS/Projects/cachyos-storage-manager}"
cd "$REPO"

if [ ! -d .git ]; then
    echo "ERROR: not a git repo: $REPO" >&2
    exit 1
fi

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "ERROR: you have uncommitted changes to tracked files."
    git status --short --untracked-files=no
    exit 1
fi

echo "==> Repo: $REPO"
echo

# ------------------------------------------------------------
# 1. scripts/modules/init.fish (NEW)
# ------------------------------------------------------------
cat > scripts/modules/init.fish << 'INIT_EOF'
#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Setup / Relocate / Edit
#
# Wizard-style helpers for first-time setup and for changing
# the target drive without editing config by hand.
#
# Public entry points (called from csm.fish):
#   csm_setup       -> csm setup
#   csm_relocate    -> csm relocate <path>
#   csm_edit        -> csm edit [show|open|validate]
# ============================================================

# ------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------

function __csm_init_watcher_active
    if not command -sq systemctl
        return 1
    end
    systemctl --user is-active csm-flatpak-watcher.service >/dev/null 2>&1
end

function __csm_init_watcher_stop
    if command -sq systemctl
        systemctl --user stop csm-flatpak-watcher.service 2>/dev/null
    end
end

function __csm_init_watcher_start
    if command -sq systemctl
        systemctl --user start csm-flatpak-watcher.service 2>/dev/null
    end
end

function __csm_init_validate_drive
    set -l path "$argv[1]"

    if test -z "$path"
        csm_error "Path kosong."
        return 1
    end

    if not string match -q '/*' "$path"
        csm_error "Path harus absolut: $path"
        return 1
    end
    csm_ok "Path absolut"

    if not test -d "$path"
        csm_warn "Direktori tidak ada: $path"
        if not csm_confirm "Buat sekarang?" "Y"
            return 1
        end
        mkdir -p "$path"
        or begin
            csm_error "Gagal membuat direktori."
            return 1
        end
    end
    csm_ok "Direktori ada"

    if not csm_is_mounted "$path"
        csm_warn "Bukan filesystem terpisah: $path"
        csm_warn "Ini mengurangi manfaat migrasi."
        if not csm_confirm "Lanjut saja?" "N"
            return 1
        end
    else
        csm_ok "Mounted (separate filesystem)"
    end

    if not test -w "$path"
        csm_error "Tidak bisa ditulis: $path"
        return 1
    end
    csm_ok "Bisa ditulis"

    return 0
end

# Write a fresh config file from template, preserving values
# that user may have customised (installation, watch flag).
function __csm_init_write_config
    set -l target "$argv[1]"
    set -l cfg (csm_config_path)

    set -l installation "datacachyos"
    if set -q CSM_FLATPAK_INSTALLATION
        set installation "$CSM_FLATPAK_INSTALLATION"
    end

    set -l watch "1"
    if set -q CSM_FLATPAK_WATCH
        set watch "$CSM_FLATPAK_WATCH"
    end

    set -l backup_before "1"
    if set -q CSM_BACKUP_BEFORE_MIGRATE
        set backup_before "$CSM_BACKUP_BEFORE_MIGRATE"
    end

    set -l timestamp (date '+%Y-%m-%d %H:%M:%S')

    mkdir -p (dirname "$cfg")

    begin
        echo "# ============================================================"
        echo "# CachyOS Storage Manager - Configuration"
        echo "#"
        echo "# Generated on $timestamp by 'csm setup' / 'csm relocate'."
        echo "#"
        echo "# Edit manually with: csm edit open"
        echo "# ============================================================"
        echo ""
        echo "# Drive target"
        echo "set -g CSM_TARGET \"$target\""
        echo ""
        echo "# Base folder for all CSM data on the target drive."
        echo "set -g CSM_ROOT \"\$CSM_TARGET/CachyOS Storage Data Migration\""
        echo ""
        echo "# ------------------------------------------------------------"
        echo "# Flatpak"
        echo "# ------------------------------------------------------------"
        echo ""
        echo "set -g CSM_FLATPAK_DIR \"\$CSM_ROOT/flatpak\""
        echo "set -g CSM_FLATPAK_INSTALLATION \"$installation\""
        echo "set -g CSM_FLATPAK_WATCH $watch"
        echo ""
        echo "# ------------------------------------------------------------"
        echo "# Paru"
        echo "# ------------------------------------------------------------"
        echo ""
        echo "set -g CSM_PARU_DIR \"\$CSM_ROOT/paru\""
        echo ""
        echo "# ------------------------------------------------------------"
        echo "# Pacman (reserved, not used yet)"
        echo "# ------------------------------------------------------------"
        echo ""
        echo "set -g CSM_PACMAN_DIR \"\$CSM_ROOT/pacman\""
        echo ""
        echo "# ------------------------------------------------------------"
        echo "# User Cache (reserved, not used yet)"
        echo "# ------------------------------------------------------------"
        echo ""
        echo "set -g CSM_CACHE_DIR \"\$CSM_ROOT/data cache\""
        echo "set -g CSM_CACHE_MIGRATE paru yay thumbnails mozilla chromium \\"
        echo "    BraveSoftware spotify discord telegram Code JetBrains \\"
        echo "    pip npm yarn go-build"
        echo "set -g CSM_CACHE_SKIP mesa_shader_cache mesa_shader_cache_db \\"
        echo "    fontconfig dconf ibus fcitx5"
        echo ""
        echo "# ------------------------------------------------------------"
        echo "# Global"
        echo "# ------------------------------------------------------------"
        echo ""
        echo "set -g CSM_BACKUP_BEFORE_MIGRATE $backup_before"
    end > "$cfg"
end

function __csm_init_module_list
    # Modules that participate in relocate.
    # Add to this list as new modules get relocate support.
    echo flatpak
    echo paru
end

# ------------------------------------------------------------
# csm setup
# ------------------------------------------------------------

function csm_setup

    csm_section "CachyOS Storage Manager - Setup"

    set -l cfg (csm_config_path)
    echo "Config : $cfg"

    if test -f "$cfg"
        echo ""
        csm_warn "Config sudah ada."
        if not csm_confirm "Overwrite? (backup akan dibuat)" "N"
            echo "Dibatalkan."
            return 1
        end
        set -l backup (csm_config_backup)
        if test -n "$backup"
            csm_ok "Backup: $backup"
        end
    end

    echo ""
    echo "Drive target (contoh: /mnt/DataCachyOS)"
    read -P "> " target

    if test -z "$target"
        csm_error "Tidak ada input."
        return 1
    end

    echo ""
    if not __csm_init_validate_drive "$target"
        return 1
    end

    set -l root "$target/CachyOS Storage Data Migration"

    echo ""
    echo "Struktur folder yang akan dibuat:"
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
    csm_ok "Folder dibuat"

    __csm_init_write_config "$target"
    csm_ok "Config ditulis ke $cfg"

    # Reload in current process so migrate below uses new paths.
    source "$cfg"
    csm_normalize_config

    echo ""
    if csm_confirm "Migrate data yang ada sekarang?" "Y"
        echo ""
        csm_flatpak_migrate
        echo ""
        csm_paru_migrate
    end

    echo ""
    echo "Flatpak watcher service:"
    if command -sq systemctl
        systemctl --user daemon-reload 2>/dev/null
        systemctl --user enable --now csm-flatpak-watcher.service 2>/dev/null
        if test $status -eq 0
            csm_ok "Watcher diaktifkan"
        else
            csm_warn "Watcher tidak bisa diaktifkan (mungkin belum di-install via setup.fish)"
        end
    else
        csm_warn "systemctl tidak ada, watcher dilewati"
    end

    echo ""
    csm_ok "Setup selesai"
    echo ""
    echo "Langkah berikutnya:"
    echo "  csm status"
    echo "  csm flatpak status"
    echo "  csm edit open"
end

# ------------------------------------------------------------
# csm relocate
# ------------------------------------------------------------

function csm_relocate

    set -l new_drive "$argv[1]"

    if test -z "$new_drive"
        csm_error "Usage: csm relocate <path>"
        return 1
    end

    if not csm_load_config
        return 1
    end

    set -l old_drive "$CSM_TARGET"
    if test "$old_drive" = "$new_drive"
        csm_error "Target sama dengan yang sekarang: $new_drive"
        return 1
    end

    csm_section "Pindah Target"

    echo "Dari : $old_drive"
    echo "Ke   : $new_drive"
    echo ""

    if not __csm_init_validate_drive "$new_drive"
        return 1
    end

    set -l old_root "$CSM_ROOT"
    if test -z "$old_root"
        set old_root "$old_drive/CachyOS Storage Data Migration"
    end
    set -l new_root "$new_drive/CachyOS Storage Data Migration"

    set -l old_flatpak "$CSM_FLATPAK_DIR"
    set -l old_paru "$CSM_PARU_DIR"
    set -l new_flatpak "$new_root/flatpak"
    set -l new_paru "$new_root/paru"

    echo ""
    echo "Data yang akan dipindah:"
    echo "  flatpak : $old_flatpak"
    if test -d "$old_flatpak"
        du -sh "$old_flatpak" 2>/dev/null
    end
    echo "  paru    : $old_paru"
    if test -d "$old_paru"
        du -sh "$old_paru" 2>/dev/null
    end

    echo ""
    if not csm_confirm "Lanjut?" "N"
        return 1
    end

    # Stop watcher
    set -l watcher_was_active 0
    if __csm_init_watcher_active
        set watcher_was_active 1
        __csm_init_watcher_stop
        csm_ok "Watcher di-stop sementara"
    end

    # Backup config
    set -l backup (csm_config_backup)
    if test -n "$backup"
        csm_ok "Config backup: $backup"
    end

    # Prepare new folders
    mkdir -p "$new_flatpak" "$new_paru"

    # Relocate modules
    echo ""
    echo "[ 1/2 ] flatpak"
    csm_flatpak_relocate "$old_flatpak" "$new_flatpak"

    echo ""
    echo "[ 2/2 ] paru"
    csm_paru_relocate "$old_paru" "$new_paru"

    # Update config
    __csm_init_write_config "$new_drive"
    csm_ok "Config di-update"

    # Restart watcher
    if test "$watcher_was_active" = "1"
        __csm_init_watcher_start
        csm_ok "Watcher di-restart"
    end

    # Ask about old data
    echo ""
    if test -d "$old_root"
        if csm_confirm "Hapus data lama di \"$old_root\"?" "N"
            rm -rf "$old_root"
            csm_ok "Data lama dihapus"
        else
            echo "Data lama TIDAK dihapus."
            echo "Hapus manual kalau sudah yakin:"
            echo "  rm -rf \"$old_root\""
        end
    end

    echo ""
    csm_ok "Relocate selesai"
end

# ------------------------------------------------------------
# csm edit
# ------------------------------------------------------------

function csm_edit

    set -l cfg (csm_config_path)
    set -l action ""
    if test (count $argv) -gt 0
        set action "$argv[1]"
    end

    switch "$action"

        case "" "show"
            if not test -f "$cfg"
                csm_error "Config tidak ada: $cfg"
                echo "Jalankan: csm setup"
                return 1
            end
            echo "Config: $cfg"
            echo ""
            cat "$cfg"

        case "open" "edit"
            if not test -f "$cfg"
                csm_error "Config tidak ada: $cfg"
                echo "Jalankan: csm setup"
                return 1
            end
            set -l editor "$EDITOR"
            if test -z "$editor"
                if command -sq nano
                    set editor nano
                else if command -sq vi
                    set editor vi
                else
                    csm_error "Tidak ada editor. Set \$EDITOR."
                    return 1
                end
            end
            $editor "$cfg"

        case "validate"
            if not test -f "$cfg"
                csm_error "Config tidak ada: $cfg"
                return 1
            end
            source "$cfg"
            csm_normalize_config

            echo "Validasi config:"
            echo ""
            echo "  CSM_TARGET       : $CSM_TARGET"
            echo "  CSM_ROOT         : $CSM_ROOT"
            echo "  CSM_FLATPAK_DIR  : $CSM_FLATPAK_DIR"
            echo "  CSM_PARU_DIR     : $CSM_PARU_DIR"
            echo ""

            set -l fail 0
            for var in CSM_TARGET CSM_ROOT CSM_FLATPAK_DIR CSM_PARU_DIR
                if not set -q $var
                    csm_warn "$var tidak di-set"
                    set fail 1
                end
            end

            if test "$fail" = "0"
                csm_ok "Semua variabel wajib terisi"
            end

            if set -q CSM_TARGET
                if csm_is_mounted "$CSM_TARGET"
                    csm_ok "Target mounted"
                else
                    csm_warn "Target tidak mounted: $CSM_TARGET"
                end
            end

        case "help" "-h" "--help"
            echo "Usage:"
            echo "  csm edit              Tampilkan config"
            echo "  csm edit open         Buka di \$EDITOR"
            echo "  csm edit validate     Validasi config"

        case "*"
            csm_error "Unknown action: $action"
            return 1
    end
end
INIT_EOF

echo "==> wrote scripts/modules/init.fish"

# ------------------------------------------------------------
# 2. Patch common.fish
#    - bump version 0.3.0 -> 0.4.0
#    - add csm_normalize_config + csm_config_backup
#    - hook normalize into csm_load_config
# ------------------------------------------------------------
python3 - << 'PYEOF'
import pathlib
p = pathlib.Path("scripts/modules/common.fish")
s = p.read_text()

# Version bump
if 'echo "0.4.0"' in s:
    print("SKIP: version already 0.4.0")
else:
    s = s.replace('echo "0.3.0"', 'echo "0.4.0"', 1)
    print("OK: version bumped to 0.4.0")

# Hook normalize into load_config
old = """    if not set -q CSM_TARGET
        csm_error "CSM_TARGET is not set in $cfg"
        return 1
    end

    return 0
end"""
new = """    if not set -q CSM_TARGET
        csm_error "CSM_TARGET is not set in $cfg"
        return 1
    end

    csm_normalize_config

    return 0
end"""
if new in s:
    print("SKIP: normalize hook already present")
elif old in s:
    s = s.replace(old, new, 1)
    print("OK: normalize hook added")
else:
    raise SystemExit("ERROR: could not find csm_load_config tail")

# Append new functions before version function
anchor = "function csm_version"
addition = """# ------------------------------------------------------------
# Config compatibility
# ------------------------------------------------------------

# Migrate old config variable names to new ones (in-memory only).
# New : CSM_ROOT, CSM_FLATPAK_DIR, CSM_PARU_DIR, CSM_PACMAN_DIR, CSM_CACHE_DIR
# Old : CSM_FLATPAK_DATA_DIR, CSM_PARU_CLONE_DIR, CSM_PACMAN_CACHE_DIR, CSM_CACHE_TARGET
function csm_normalize_config

    if not set -q CSM_ROOT
        if set -q CSM_TARGET
            set -g CSM_ROOT "$CSM_TARGET/CachyOS Storage Data Migration"
        end
    end

    if not set -q CSM_FLATPAK_DIR
        if set -q CSM_FLATPAK_DATA_DIR
            set -g CSM_FLATPAK_DIR "$CSM_FLATPAK_DATA_DIR"
        else if set -q CSM_ROOT
            set -g CSM_FLATPAK_DIR "$CSM_ROOT/flatpak"
        end
    end

    if not set -q CSM_PARU_DIR
        if set -q CSM_PARU_CLONE_DIR
            set -g CSM_PARU_DIR "$CSM_PARU_CLONE_DIR"
        else if set -q CSM_ROOT
            set -g CSM_PARU_DIR "$CSM_ROOT/paru"
        end
    end

    if not set -q CSM_PACMAN_DIR
        if set -q CSM_PACMAN_CACHE_DIR
            set -g CSM_PACMAN_DIR "$CSM_PACMAN_CACHE_DIR"
        else if set -q CSM_ROOT
            set -g CSM_PACMAN_DIR "$CSM_ROOT/pacman"
        end
    end

    if not set -q CSM_CACHE_DIR
        if set -q CSM_CACHE_TARGET
            set -g CSM_CACHE_DIR "$CSM_CACHE_TARGET"
        else if set -q CSM_ROOT
            set -g CSM_CACHE_DIR "$CSM_ROOT/data cache"
        end
    end

    return 0
end

# Backup the config file. Prints the backup path, or empty string.
function csm_config_backup
    set -l cfg (csm_config_path)
    if not test -f "$cfg"
        echo ""
        return 0
    end
    set -l timestamp (date '+%Y%m%d-%H%M%S')
    set -l backup "$cfg.bak.$timestamp"
    cp "$cfg" "$backup"
    echo "$backup"
end

"""

if "function csm_normalize_config" in s:
    print("SKIP: normalize_config already present")
elif anchor in s:
    s = s.replace(anchor, addition + anchor, 1)
    print("OK: normalize_config + config_backup added")
else:
    raise SystemExit("ERROR: could not find csm_version anchor")

p.write_text(s)
PYEOF

echo "==> patched common.fish"

# ------------------------------------------------------------
# 3. Patch flatpak.fish
#    - prefer CSM_FLATPAK_DIR over CSM_FLATPAK_DATA_DIR
#    - add csm_flatpak_info and csm_flatpak_relocate
# ------------------------------------------------------------
python3 - << 'PYEOF'
import pathlib
p = pathlib.Path("scripts/modules/flatpak.fish")
s = p.read_text()

old = """function __csm_flatpak_data_dir
    if not set -q CSM_FLATPAK_DATA_DIR
        echo "ERROR: CSM_FLATPAK_DATA_DIR is not configured." >&2
        return 1
    end
    echo "$CSM_FLATPAK_DATA_DIR"
end"""
new = """function __csm_flatpak_data_dir
    if set -q CSM_FLATPAK_DIR
        echo "$CSM_FLATPAK_DIR"
        return 0
    end
    if set -q CSM_FLATPAK_DATA_DIR
        echo "$CSM_FLATPAK_DATA_DIR"
        return 0
    end
    echo "ERROR: CSM_FLATPAK_DIR is not configured." >&2
    return 1
end"""
if new in s:
    print("SKIP: data_dir already updated")
elif old in s:
    s = s.replace(old, new, 1)
    print("OK: data_dir updated for CSM_FLATPAK_DIR")
else:
    raise SystemExit("ERROR: could not find __csm_flatpak_data_dir")

if "function csm_flatpak_info" in s:
    print("SKIP: info/relocate already present")
else:
    addition = """

# ------------------------------------------------------------
# Relocate support (used by 'csm relocate')
# ------------------------------------------------------------

# Report module state as a single pipe-delimited line.
# Format: name|source_dir|target_dir
function csm_flatpak_info
    set -l source "$HOME/.var/app"
    set -l target ""
    if set -q CSM_FLATPAK_DIR
        set target "$CSM_FLATPAK_DIR"
    else if set -q CSM_FLATPAK_DATA_DIR
        set target "$CSM_FLATPAK_DATA_DIR"
    end
    echo "flatpak|$source|$target"
end

# Move flatpak data from old_target to new_target and relink.
# Args: <old_target> <new_target>
function csm_flatpak_relocate
    set -l old_target "$argv[1]"
    set -l new_target "$argv[2]"
    set -l source "$HOME/.var/app"

    if test -z "$old_target"; or test -z "$new_target"
        echo "  ERROR: relocate requires old and new targets"
        return 1
    end

    if test "$old_target" = "$new_target"
        echo "  SKIP: target unchanged"
        return 0
    end

    mkdir -p "$new_target"

    # Move contents
    if test -d "$old_target"
        for entry in "$old_target"/* "$old_target"/.*
            set -l name (basename "$entry")
            if test "$name" = "."; or test "$name" = ".."
                continue
            end
            if not test -e "$entry"; and not test -L "$entry"
                continue
            end
            set -l dest "$new_target/$name"
            if test -e "$dest"; or test -L "$dest"
                echo "  WARN: destination already exists: $name"
                continue
            end
            mv "$entry" "$dest"
            if test $status -eq 0
                echo "  moved: $name"
            else
                echo "  ERROR: failed to move: $name"
            end
        end
    end

    # Relink every per-app symlink that pointed into old_target
    if test -d "$source"
        for app_link in "$source"/*
            if not test -L "$app_link"
                continue
            end
            set -l app_id (basename "$app_link")
            set -l current (readlink "$app_link")
            if string match -q "$old_target/*" "$current"
                rm "$app_link"
                ln -s "$new_target/$app_id" "$app_link"
                echo "  relinked: $app_id"
            end
        end
    end

    return 0
end
"""
    s = s.rstrip() + addition
    print("OK: info + relocate added")

p.write_text(s)
PYEOF

echo "==> patched flatpak.fish"

# ------------------------------------------------------------
# 4. Patch paru.fish
#    - prefer CSM_PARU_DIR over CSM_PARU_CLONE_DIR
#    - add csm_paru_info and csm_paru_relocate
# ------------------------------------------------------------
python3 - << 'PYEOF'
import pathlib
p = pathlib.Path("scripts/modules/paru.fish")
s = p.read_text()

old = """function __csm_paru_clone_dir
    if not set -q CSM_PARU_CLONE_DIR
        echo "ERROR: CSM_PARU_CLONE_DIR is not configured." >&2
        return 1
    end
    echo "$CSM_PARU_CLONE_DIR"
end"""
new = """function __csm_paru_clone_dir
    if set -q CSM_PARU_DIR
        echo "$CSM_PARU_DIR"
        return 0
    end
    if set -q CSM_PARU_CLONE_DIR
        echo "$CSM_PARU_CLONE_DIR"
        return 0
    end
    echo "ERROR: CSM_PARU_DIR is not configured." >&2
    return 1
end"""
if new in s:
    print("SKIP: clone_dir already updated")
elif old in s:
    s = s.replace(old, new, 1)
    print("OK: clone_dir updated for CSM_PARU_DIR")
else:
    raise SystemExit("ERROR: could not find __csm_paru_clone_dir")

if "function csm_paru_info" in s:
    print("SKIP: info/relocate already present")
else:
    addition = """

# ------------------------------------------------------------
# Relocate support (used by 'csm relocate')
# ------------------------------------------------------------

function csm_paru_info
    set -l source "$HOME/.cache/paru/clone"
    set -l target ""
    if set -q CSM_PARU_DIR
        set target "$CSM_PARU_DIR"
    else if set -q CSM_PARU_CLONE_DIR
        set target "$CSM_PARU_CLONE_DIR"
    end
    echo "paru|$source|$target"
end

function csm_paru_relocate
    set -l old_target "$argv[1]"
    set -l new_target "$argv[2]"
    set -l source "$HOME/.cache/paru/clone"

    if test -z "$old_target"; or test -z "$new_target"
        echo "  ERROR: relocate requires old and new targets"
        return 1
    end

    if test "$old_target" = "$new_target"
        echo "  SKIP: target unchanged"
        return 0
    end

    mkdir -p "$new_target"

    if test -d "$old_target"
        for entry in "$old_target"/* "$old_target"/.*
            set -l name (basename "$entry")
            if test "$name" = "."; or test "$name" = ".."
                continue
            end
            if not test -e "$entry"; and not test -L "$entry"
                continue
            end
            set -l dest "$new_target/$name"
            if test -e "$dest"; or test -L "$dest"
                echo "  WARN: destination already exists: $name"
                continue
            end
            mv "$entry" "$dest"
            if test $status -eq 0
                echo "  moved: $name"
            else
                echo "  ERROR: failed to move: $name"
            end
        end
    end

    if test -L "$source"
        set -l current (readlink "$source")
        if test "$current" = "$old_target"
            rm "$source"
            ln -s "$new_target" "$source"
            echo "  relinked: $source -> $new_target"
        end
    end

    return 0
end
"""
    s = s.rstrip() + addition
    print("OK: info + relocate added")

p.write_text(s)
PYEOF

echo "==> patched paru.fish"

# ------------------------------------------------------------
# 5. scripts/csm.fish
#    - source init.fish
#    - dispatch setup/relocate/edit
#    - update usage text
#    - update csm_cmd_status to use new var names
# ------------------------------------------------------------
python3 - << 'PYEOF'
import pathlib
p = pathlib.Path("scripts/csm.fish")
s = p.read_text()

# 5a. source init.fish
old = 'source "$MODULES_DIR/paru.fish"'
new = 'source "$MODULES_DIR/paru.fish"\nsource "$MODULES_DIR/init.fish"'
if new in s:
    print("SKIP: init.fish source line already present")
elif old in s:
    s = s.replace(old, new, 1)
    print("OK: added init.fish source")
else:
    raise SystemExit("ERROR: could not find paru source line")

# 5b. update usage text
old = '''    echo "Commands:"
    echo "  csm status          Show overall status"
    echo "  csm doctor          Check system health"
    echo "  csm version         Show version"
    echo "  csm help            Show this help"'''
new = '''    echo "Commands:"
    echo "  csm setup           First-time setup wizard"
    echo "  csm relocate <path> Move all data to a new target drive"
    echo "  csm edit [action]   Show/open/validate config"
    echo "  csm status          Show overall status"
    echo "  csm doctor          Check system health"
    echo "  csm version         Show version"
    echo "  csm help            Show this help"'''
if new in s:
    print("SKIP: usage text already updated")
elif old in s:
    s = s.replace(old, new, 1)
    print("OK: usage text updated")
else:
    print("WARN: usage text pattern not found, skipping")

# 5c. csm_cmd_status: prefer new variable name
old = '''            echo ""
            echo "Flatpak"
            if set -q CSM_FLATPAK_DATA_DIR
                echo "  Data dir       : $CSM_FLATPAK_DATA_DIR"
            end'''
new = '''            echo ""
            echo "Paths"
            if set -q CSM_ROOT
                echo "  CSM_ROOT       : $CSM_ROOT"
            end
            if set -q CSM_FLATPAK_DIR
                echo "  Flatpak dir    : $CSM_FLATPAK_DIR"
            else if set -q CSM_FLATPAK_DATA_DIR
                echo "  Flatpak dir    : $CSM_FLATPAK_DATA_DIR"
            end
            if set -q CSM_PARU_DIR
                echo "  Paru dir       : $CSM_PARU_DIR"
            else if set -q CSM_PARU_CLONE_DIR
                echo "  Paru dir       : $CSM_PARU_CLONE_DIR"
            end
            echo ""
            echo "Flatpak"
            if set -q CSM_FLATPAK_DATA_DIR
                echo "  Data dir       : $CSM_FLATPAK_DATA_DIR"
            end'''
# Actually simpler: just replace the flatpak config block cleanly
old_simple = '''            echo ""
            echo "Flatpak"
            if set -q CSM_FLATPAK_DATA_DIR
                echo "  Data dir       : $CSM_FLATPAK_DATA_DIR"
            end
            if set -q CSM_FLATPAK_INSTALLATION
                echo "  Installation   : $CSM_FLATPAK_INSTALLATION"
            end
            if set -q CSM_FLATPAK_WATCH
                echo "  Watcher        : $CSM_FLATPAK_WATCH"
            end'''
new_simple = '''            echo ""
            echo "Paths"
            if set -q CSM_ROOT
                echo "  CSM_ROOT       : $CSM_ROOT"
            end
            if set -q CSM_FLATPAK_DIR
                echo "  Flatpak dir    : $CSM_FLATPAK_DIR"
            else if set -q CSM_FLATPAK_DATA_DIR
                echo "  Flatpak dir    : $CSM_FLATPAK_DATA_DIR"
            end
            if set -q CSM_PARU_DIR
                echo "  Paru dir       : $CSM_PARU_DIR"
            else if set -q CSM_PARU_CLONE_DIR
                echo "  Paru dir       : $CSM_PARU_CLONE_DIR"
            end
            echo ""
            echo "Flatpak"
            if set -q CSM_FLATPAK_INSTALLATION
                echo "  Installation   : $CSM_FLATPAK_INSTALLATION"
            end
            if set -q CSM_FLATPAK_WATCH
                echo "  Watcher        : $CSM_FLATPAK_WATCH"
            end'''
if new_simple in s:
    print("SKIP: status block already updated")
elif old_simple in s:
    s = s.replace(old_simple, new_simple, 1)
    print("OK: status block updated")
else:
    print("WARN: status block pattern not found, skipping")

# 5d. dispatch: add setup / relocate / edit
old = '''        case flatpak'''
new = '''        case setup
            csm_setup
        case relocate
            csm_relocate $rest
        case edit
            csm_edit $rest
        case flatpak'''
if "case setup" in s:
    print("SKIP: setup/relocate/edit dispatch already present")
elif old in s:
    s = s.replace(old, new, 1)
    print("OK: added setup/relocate/edit dispatch")
else:
    raise SystemExit("ERROR: could not find 'case flatpak' in dispatcher")

p.write_text(s)
PYEOF

echo "==> patched csm.fish"

# ------------------------------------------------------------
# 6. config/config.fish.example (rewrite)
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

# Where Flatpak application user data is stored.
set -g CSM_FLATPAK_DIR "$CSM_ROOT/flatpak"

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
# 7. docs/tutorial.md (NEW)
# ------------------------------------------------------------
mkdir -p docs

cat > docs/tutorial.md << 'TUT_EOF'
# CachyOS Storage Manager — Tutorial

A step-by-step guide for non-programmers.

## Table of Contents

1. [What this tool does](#1-what-this-tool-does)
2. [First-time setup](#2-first-time-setup)
3. [Daily use](#3-daily-use)
4. [Checking status](#4-checking-status)
5. [Changing the target drive](#5-changing-the-target-drive)
6. [Editing the config](#6-editing-the-config)
7. [Uninstalling](#7-uninstalling)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. What this tool does

CachyOS Storage Manager (CSM) moves large, growing application data off your
main drive and onto a second drive, without breaking the applications that
use it.

It handles three kinds of data:

| Module | What it moves | Where it goes |
|---|---|---|
| flatpak | `~/.var/app` — Flatpak app data | `<target>/CachyOS Storage Data Migration/flatpak/` |
| paru | `~/.cache/paru/clone` — AUR build dirs | `<target>/CachyOS Storage Data Migration/paru/` |
| pacman | `/var/cache/pacman/pkg` — package cache | planned |
| cache | `~/.cache` (selected folders) | planned |

Data is moved with a **symlink**: the original location still looks the same
to the application, but the bytes live on the second drive.

---

## 2. First-time setup

### 2.1 Install CSM

```fish
git clone git@github.com:rzou89/cachyos-storage-manager.git
cd cachyos-storage-manager
./setup.fish