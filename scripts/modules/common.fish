#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Common Helpers
#
# Fungsi-fungsi dasar yang dipakai oleh semua modul.
# ============================================================

# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------

function csm_log
    set_color cyan
    echo -n "[csm] "
    set_color normal
    echo $argv
end

function csm_ok
    set_color green
    echo -n "[ OK ] "
    set_color normal
    echo $argv
end

function csm_warn
    set_color yellow
    echo -n "[WARN] "
    set_color normal
    echo $argv
end

function csm_error
    set_color red
    echo -n "[FAIL] "
    set_color normal
    echo $argv >&2
end

function csm_section
    echo ""
    set_color brblue
    echo "========================================"
    echo " $argv"
    echo "========================================"
    set_color normal
    echo ""
end

# ------------------------------------------------------------
# Checks
# ------------------------------------------------------------

# Pastikan sebuah command tersedia.
# Mengembalikan 0 kalau ada, 1 kalau tidak.
function csm_have
    command -sq $argv[1]
end

# Pastikan path adalah mount point / filesystem terpisah.
# Argumen: <path>
function csm_is_mounted
    set -l path $argv[1]
    if not test -d "$path"
        return 1
    end
    # Bandingkan device id dengan parent
    set -l dev_self (stat -c %d "$path" 2>/dev/null)
    set -l dev_parent (stat -c %d (dirname "$path") 2>/dev/null)
    if test "$dev_self" != "$dev_parent"
        return 0
    end
    return 1
end

# Cek apakah proses dengan nama tertentu sedang jalan.
# Argumen: <nama-proses>
function csm_is_running
    pgrep -x $argv[1] >/dev/null 2>&1
    return $status
end

# ------------------------------------------------------------
# Konfirmasi
# ------------------------------------------------------------

# Tanya user ya/tidak.
# Argumen: <prompt> [default: "N"]
function csm_confirm
    set -l prompt $argv[1]
    set -l default "N"
    if set -q argv[2]
        set default $argv[2]
    end

    set -l hint "[y/N]"
    if test "$default" = "Y"
        set hint "[Y/n]"
    end

    read -P "$prompt $hint " -l answer

    if test -z "$answer"
        set answer $default
    end

    string match -qi "y*" "$answer"
    return $status
end

# ------------------------------------------------------------
# Config
# ------------------------------------------------------------

# Path default config.
function csm_config_path
    echo "$HOME/.config/cachyos-storage-manager/config.fish"
end

# Load config. Abort kalau tidak ada.
function csm_load_config
    set -l cfg (csm_config_path)

    if not test -f "$cfg"
        csm_error "Configuration not found: $cfg"
        csm_error "Run 'csm setup' first, or copy config/config.fish.example"
        return 1
    end

    source "$cfg"

    if not set -q CSM_TARGET
        csm_error "CSM_TARGET is not set in $cfg"
        return 1
    end

    csm_normalize_config

    return 0
end

# Validasi target: absolute, exists, mounted.
function csm_validate_target
    if not string match -q '/*' "$CSM_TARGET"
        csm_error "CSM_TARGET must be an absolute path: $CSM_TARGET"
        return 1
    end

    if not test -d "$CSM_TARGET"
        csm_error "CSM_TARGET does not exist: $CSM_TARGET"
        return 1
    end

    if not csm_is_mounted "$CSM_TARGET"
        csm_warn "CSM_TARGET is not on a separate filesystem: $CSM_TARGET"
        csm_warn "This may defeat the purpose of migration."
        if not csm_confirm "Continue anyway?" "N"
            return 1
        end
    end

    return 0
end

# ------------------------------------------------------------
# Project root
# ------------------------------------------------------------

# Dapatkan root direktori proyek (lokasi repo).
function csm_project_root
    set -l self (status --current-filename)
    if test -z "$self"
        # Fallback: dari lokasi script utama
        set self (command which csm 2>/dev/null)
    end
    echo (realpath (dirname $self)/../..)
end

# ------------------------------------------------------------
# Versi
# ------------------------------------------------------------

# ------------------------------------------------------------
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

    if not set -q CSM_FLATPAK_CORE_DIR
        if set -q CSM_ROOT
            set -g CSM_FLATPAK_CORE_DIR "$CSM_ROOT/Flatpak/Flatpak Core"
        else if set -q CSM_TARGET
            set -g CSM_FLATPAK_CORE_DIR "$CSM_TARGET/CachyOS Storage Data Migration/Flatpak/Flatpak Core"
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

function csm_version
    echo "0.4.1"
end