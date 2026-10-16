#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Common Helpers
#
# Fungsi-fungsi dasar yang dipakai oleh semua modul:
# logging, pengecekan, konfirmasi, config, dan diagnostik.
#
# Di-source sebelum modul lain oleh build/csm.
# ============================================================

# ------------------------------------------------------------
# Versi
# ------------------------------------------------------------

function csm_version
    echo "1.1.2"
end

# Nama folder akar seluruh data CSM di dalam drive target.
function csm_root_name
    echo "CachyOS-Storage-Data-Migration"
end

# CSM_TARGET harus berupa drive / titik mount, BUKAN folder migrasinya.
#
# Config dari wizard versi lama ada yang menyimpan
#   CSM_TARGET = /mnt/DataCachyOS/CachyOS-Storage-Data-Migration
# sehingga CSM_ROOT (yang diturunkan sebagai $CSM_TARGET/<nama>) menjadi
# bersarang dua kali: /mnt/DataCachyOS/<nama>/<nama>.
#
# Fungsi ini memotong segmen folder migrasi di ujung path apa pun yang
# diberikan, sehingga nilai lama otomatis diperbaiki.
# Argumen: <path>
function csm_target_normalize
    set -l path "$argv[1]"
    set -l name (csm_root_name)

    if test -z "$path"
        echo ""
        return 0
    end

    while test -n "$path"; and test "$path" != "/"
        if test (basename "$path") = "$name"
            set path (dirname "$path")
            continue
        end
        break
    end

    echo "$path"
end

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

# Pastikan path berada di filesystem yang sudah dipasang (mounted),
# dan bukan sekadar subfolder di dalam root filesystem yang sama.
# Argumen: <path>
function csm_is_mounted
    set -l path $argv[1]
    if not test -d "$path"
        return 1
    end

    # Preferred check: ask the system directly which mountpoint owns this path.
    if csm_have findmnt
        set -l mount_target (findmnt -T "$path" -no TARGET 2>/dev/null | string trim)
        if test -n "$mount_target"
            if test "$mount_target" != "/"
                return 0
            end
            return 1
        end
    end

    # Fallback: compare device ids until we hit the nearest mounted boundary.
    set -l dev_self (stat -c %d "$path" 2>/dev/null)
    set -l current "$path"

    while test -n "$current"
        set -l parent (dirname "$current")
        if test "$parent" = "$current"
            break
        end

        set -l dev_parent (stat -c %d "$parent" 2>/dev/null)
        if test "$dev_self" != "$dev_parent"
            return 0
        end

        set current "$parent"
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

    read -P "$prompt $hint " answer

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

# Isi nilai default untuk satu variabel bila belum di-set.
# Argumen: <nama-variabel> [nilai...]
function __csm_default
    set -l name $argv[1]
    set -l value $argv[2..-1]

    if test (count $value) -eq 0
        return 1
    end

    if not set -q $name
        set -gx $name $value
    end
    return 0
end

# Samakan nama & nilai variabel config.
#
# Variabel kanonik yang dipakai kode aktif:
#   CSM_TARGET, CSM_ROOT, CSM_FLATPAK_DIR, CSM_FLATPAK_CORE_DIR,
#   CSM_FLATPAK_INSTALLATION, CSM_FLATPAK_WATCH,
#   CSM_PARU_DIR, CSM_PACMAN_DIR, CSM_CACHE_DIR,
#   CSM_CACHE_WHITELIST, CSM_CACHE_BLACKLIST,
#   CSM_WINEPREFIX_DIR, CSM_SHADERCACHE_DIR,
#   CSM_BACKUP_BEFORE_MIGRATE
#
# Nama lama tetap diterima sebagai alias kompatibilitas.
# Aman dipanggil berulang kali (idempotent).
function csm_normalize_config
    set -l root_name (csm_root_name)

    # 1. CSM_TARGET harus berupa drive, bukan folder migrasinya.
    #    Potong segmen <nama> di ujung path (bisa lebih dari satu kali).
    if set -q CSM_TARGET; and test -n "$CSM_TARGET"
        set -gx CSM_TARGET (csm_target_normalize "$CSM_TARGET")
    end

    # 2. Rapikan CSM_ROOT yang sudah telanjur bersarang: <drive>/<nama>/<nama>
    if set -q CSM_ROOT; and test -n "$CSM_ROOT"
        while test (basename "$CSM_ROOT") = "$root_name"
            and test (basename (dirname "$CSM_ROOT")) = "$root_name"
            set -gx CSM_ROOT (dirname "$CSM_ROOT")
        end
    end

    if not set -q CSM_ROOT; and set -q CSM_TARGET
        set -gx CSM_ROOT "$CSM_TARGET/"$root_name
    end

    # Perbaiki config dari wizard versi lama: CSM_ROOT pernah diset sama
    # dengan CSM_TARGET, sehingga seluruh data jatuh langsung di akar drive.
    if set -q CSM_ROOT; and set -q CSM_TARGET
        if test "$CSM_ROOT" = "$CSM_TARGET"
            set -gx CSM_ROOT "$CSM_TARGET/"$root_name
        end
    end

    if not set -q CSM_ROOT
        return 0
    end

    # --- Flatpak ---
    if not set -q CSM_FLATPAK_DIR
        if set -q CSM_FLATPAK_DATA_DIR
            set -gx CSM_FLATPAK_DIR "$CSM_FLATPAK_DATA_DIR"
        else
            set -gx CSM_FLATPAK_DIR "$CSM_ROOT/flatpak/flatpak-data"
        end
    end

    __csm_default CSM_FLATPAK_CORE_DIR "$CSM_ROOT/flatpak/flatpak-core/system"
    __csm_default CSM_FLATPAK_INSTALLATION "datacachyos"
    __csm_default CSM_FLATPAK_WATCH 1

    # --- AUR / package caches ---
    if not set -q CSM_PARU_DIR
        if set -q CSM_PARU_CLONE_DIR
            set -gx CSM_PARU_DIR "$CSM_PARU_CLONE_DIR"
        else
            set -gx CSM_PARU_DIR "$CSM_ROOT/cache/paru"
        end
    end

    if not set -q CSM_PACMAN_DIR
        if set -q CSM_PACMAN_CACHE_DIR
            set -gx CSM_PACMAN_DIR "$CSM_PACMAN_CACHE_DIR"
        else
            set -gx CSM_PACMAN_DIR "$CSM_ROOT/cache/pacman"
        end
    end

    # --- User cache ---
    if not set -q CSM_CACHE_DIR
        if set -q CSM_CACHE_TARGET
            set -gx CSM_CACHE_DIR "$CSM_CACHE_TARGET"
        else
            set -gx CSM_CACHE_DIR "$CSM_ROOT/cache"
        end
    end

    # --- Steam / gaming ---
    __csm_default CSM_WINEPREFIX_DIR "$CSM_ROOT/apps/wine-prefixes"
    __csm_default CSM_SHADERCACHE_DIR "$CSM_ROOT/shader-cache"

    # --- Global ---
    __csm_default CSM_BACKUP_BEFORE_MIGRATE 1

    # --- Cache whitelist / blacklist ---
    # Nama lama CSM_CACHE_MIGRATE / CSM_CACHE_SKIP tetap diterima.
    if not set -q CSM_CACHE_WHITELIST; and set -q CSM_CACHE_MIGRATE
        set -gx CSM_CACHE_WHITELIST $CSM_CACHE_MIGRATE
    end
    if not set -q CSM_CACHE_BLACKLIST; and set -q CSM_CACHE_SKIP
        set -gx CSM_CACHE_BLACKLIST $CSM_CACHE_SKIP
    end

    # Catatan: 'paru'/'yay' sengaja TIDAK masuk daftar ini.
    # ~/.cache/paru/clone ditangani modul paru sendiri; kalau folder
    # induknya ikut disymlink, symlink clone-nya akan rusak.
    __csm_default CSM_CACHE_WHITELIST \
        mozilla google-chrome chromium zen pip yarn npm go-build \
        cargo thumbnails electron node-gyp clangd

    __csm_default CSM_CACHE_BLACKLIST \
        fontconfig mesa_shader_cache mesa_shader_cache_db nvidia \
        pipewire wireplumber systemd dconf ibus fcitx5 ksycoca5 \
        plasmashell gnome-shell

    return 0
end

# Load config. Tidak pernah gagal: kalau file belum ada, variabel
# tetap dinormalisasi agar CSM_ROOT punya nilai default yang aman.
function csm_load_config
    set -l cfg (csm_config_path)

    if test -f "$cfg"
        source "$cfg" 2>/dev/null
    end

    csm_normalize_config
    return 0
end

# Versi ketat: gagal bila config atau CSM_ROOT belum siap.
function csm_require_config
    set -l cfg (csm_config_path)

    if not test -f "$cfg"
        csm_error "Configuration not found: $cfg"
        csm_error "Run 'csm setup' first, or copy config/config.fish.example"
        return 1
    end

    csm_load_config

    if not set -q CSM_ROOT; or test -z "$CSM_ROOT"
        csm_error "CSM_ROOT is not configured. Run 'csm setup'."
        return 1
    end

    return 0
end

# Validasi target: absolute, exists, mounted.
# Argumen: [path] (default: $CSM_TARGET)
function csm_validate_target
    set -l target $argv[1]
    if test -z "$target"
        if not set -q CSM_TARGET
            csm_error "CSM_TARGET is not set."
            return 1
        end
        set target "$CSM_TARGET"
    end

    if not string match -q '/*' "$target"
        csm_error "Target must be an absolute path: $target"
        return 1
    end

    if not test -d "$target"
        csm_error "Target does not exist: $target"
        return 1
    end

    if not csm_is_mounted "$target"
        # 'csm setup' memanggil banyak modul berturut-turut. Tanpa cache ini,
        # user ditanya hal yang sama berkali-kali dalam satu sesi.
        if set -q __CSM_TARGET_ACCEPTED; and test "$__CSM_TARGET_ACCEPTED" = "$target"
            return 0
        end

        csm_warn "Target is not on a separate filesystem: $target"
        csm_warn "This may defeat the purpose of migration."
        if not csm_confirm "Continue anyway?" "N"
            return 1
        end
        set -g __CSM_TARGET_ACCEPTED "$target"
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
    if cp "$cfg" "$backup"
        echo "$backup"
        return 0
    end
    echo ""
    return 1
end

# ------------------------------------------------------------
# Doctor
# ------------------------------------------------------------

function csm_doctor
    echo "========================================"
    echo " CachyOS Storage Manager - Doctor"
    echo "========================================"
    echo ""

    set -l issues 0

    set -l cfg (csm_config_path)
    if test -f "$cfg"
        csm_ok "Config file: $cfg"
    else
        csm_error "Config file missing: $cfg"
        csm_log "Run 'csm setup' to create it."
        set issues (math $issues + 1)
    end

    if set -q CSM_ROOT; and test -d "$CSM_ROOT"
        csm_ok "Target root: $CSM_ROOT"
    else
        csm_error "Target root is not configured or does not exist."
        set issues (math $issues + 1)
    end

    if set -q CSM_TARGET
        if csm_is_mounted "$CSM_TARGET"
            csm_ok "Target is a separate mount point: $CSM_TARGET"
        else
            csm_warn "Target is not a separate mount point: $CSM_TARGET"
        end
    end

    if contains -- "$HOME/.local/bin" $PATH
        csm_ok "~/.local/bin is in \$PATH."
    else
        csm_warn "~/.local/bin is not in \$PATH. Run: fish_add_path ~/.local/bin"
    end

    echo ""
    echo "Dependencies:"
    for dep in fish rsync findmnt flatpak pacman paru inotifywait
        if csm_have $dep
            csm_ok "$dep"
        else
            csm_warn "$dep not found"
        end
    end

    echo ""
    if csm_have systemctl
        if systemctl --user is-active --quiet csm-flatpak-watcher.service 2>/dev/null
            csm_ok "Flatpak watcher service is active."
        else
            csm_log "Flatpak watcher service is inactive."
        end
    else
        csm_log "systemd user session is not available."
    end

    echo ""
    if test $issues -eq 0
        csm_ok "System status: healthy."
        return 0
    end

    csm_error "System status: $issues issue(s) detected."
    return 1
end

# ------------------------------------------------------------
# Managed items
#
# Satu sumber kebenaran untuk semua item yang dipindah CSM.
# Format: <grup>|<label>|<src>|<dest>
#
# Grup: apps, dev, system, shader.
# Modul cache & steam pakai daftar sendiri (dinamis / butuh perlakuan
# khusus), jadi tidak ada di sini.
# ------------------------------------------------------------

function csm_managed_items
    if not set -q CSM_ROOT; or test -z "$CSM_ROOT"
        return 1
    end

    echo "apps|Heroic Games Launcher|$HOME/.config/heroic|$CSM_ROOT/apps/heroic"
    echo "apps|UMU Proton Runtime|$HOME/.local/share/umu|$CSM_ROOT/apps/umu"
    echo "apps|Hydra Launcher Config|$HOME/.config/hydralauncher|$CSM_ROOT/apps/hydralauncher"
    echo "apps|Goverlay / MangoHud|$HOME/.local/share/goverlay|$CSM_ROOT/apps/goverlay"
    echo "apps|Lutris Config & Runners|$HOME/.local/share/lutris|$CSM_ROOT/apps/lutris"
    echo "shader|DXVK Shader Cache|$HOME/.cache/dxvk|$CSM_SHADERCACHE_DIR/dxvk"
    echo "dev|VS Code - OSS Config|$HOME/.config/Code - OSS|$CSM_ROOT/dev/code-oss"
    echo "dev|VS Code Extensions|$HOME/.vscode|$CSM_ROOT/dev/vscode-extensions"
    echo "dev|Python UV Cache|$HOME/.local/share/uv|$CSM_ROOT/dev/uv"
    echo "dev|Python Pip Cache|$HOME/.cache/pip|$CSM_ROOT/cache/pip"
    echo "dev|Rust Cargo|$HOME/.cargo|$CSM_ROOT/dev/cargo"
    echo "dev|NPM Cache|$HOME/.npm|$CSM_ROOT/cache/npm"
    echo "system|Desktop Icon Themes|$HOME/.local/share/icons|$CSM_ROOT/system/icons"
    return 0
end

# ------------------------------------------------------------
# Safe migration primitives
#
# Semua modul yang memindahkan data HARUS memakai fungsi ini, jangan
# memanggil rm -rf sendiri. Sumber hanya dihapus setelah verifikasi.
# ------------------------------------------------------------

# Hitung entri langsung di dalam sebuah direktori (tanpa hidden filter).
# Dipakai untuk verifikasi sebelum/ sesudah salin.
# Argumen: <dir>
function csm_count_entries
    set -l dir "$argv[1]"
    if not test -d "$dir"
        echo 0
        return 0
    end
    find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | string trim
end

# Ukuran direktori dalam format human-readable.
# Argumen: <dir>
function csm_dir_size
    set -l dir "$argv[1]"
    if not test -d "$dir"; and not test -L "$dir"
        echo "-"
        return 0
    end
    set -l size (du -sh "$dir" 2>/dev/null | cut -f1)
    if test -z "$size"
        set size "0"
    end
    echo "$size"
end

# Pindahkan <src> ke <dest>, lalu ganti <src> dengan symlink ke <dest>.
#
# Sumber TIDAK pernah dihapus sebelum isinya terverifikasi ada di target.
# Return code:
#   0 = berhasil (atau sudah dalam kondisi benar)
#   1 = gagal
#   2 = tidak ada yang perlu dilakukan (src tidak ada)
#
# Argumen: <label> <src> <dest>
function csm_link_migrate
    set -l label "$argv[1]"
    set -l src   "$argv[2]"
    set -l dest  "$argv[3]"

    if test -z "$src"; or test -z "$dest"
        csm_error "$label: src/dest tidak boleh kosong"
        return 1
    end

    # Tidak ada sumber: bukan error, cukup lewati.
    if not test -e "$src"; and not test -L "$src"
        return 2
    end

    # Sudah symlink?
    if test -L "$src"
        set -l current (readlink "$src")
        if test "$current" = "$dest"
            csm_log "SKIP  $label: sudah symlink -> $dest"
            return 0
        end
        csm_warn "$label: symlink menunjuk ke $current (bukan $dest)"
        if not csm_confirm "Ganti symlink ke $dest?" "N"
            return 1
        end
        rm -f "$src"
        mkdir -p "$dest"
        ln -s "$dest" "$src"
        csm_ok "$label: symlink diganti -> $dest"
        return 0
    end

    if not test -d "$src"
        csm_warn "$label: $src bukan direktori, dilewati"
        return 1
    end

    # Jangan pernah menjadikan target di dalam sumber (symlink loop).
    if string match -q "$src/*" "$dest"
        csm_error "$label: dest berada di dalam src ($dest)"
        return 1
    end

    if not mkdir -p "$dest"
        csm_error "$label: gagal membuat $dest"
        return 1
    end

    set -l before (csm_count_entries "$src")

    echo "-> $label"
    echo "     $src"
    echo "  -> $dest"

    if csm_have rsync
        rsync -aHAX "$src/" "$dest/"
    else
        cp -a "$src/." "$dest/"
    end
    if test $status -ne 0
        csm_error "$label: gagal menyalin. Sumber TIDAK dihapus."
        return 1
    end

    # Verifikasi sebelum menghapus sumber.
    set -l after (csm_count_entries "$dest")
    if test "$after" -lt "$before"
        csm_error "$label: verifikasi gagal (sumber=$before entri, target=$after entri)"
        csm_error "Sumber TIDAK dihapus: $src"
        return 1
    end

    if not rm -rf "$src"
        csm_error "$label: gagal menghapus sumber: $src"
        return 1
    end

    if not ln -s "$dest" "$src"
        csm_error "$label: gagal membuat symlink $src -> $dest"
        csm_warn "Data sudah aman di: $dest"
        return 1
    end

    csm_ok "$label: OK ($before entri)"
    return 0
end

# Kebalikan dari csm_link_migrate: hapus symlink, kembalikan data ke lokasi
# asal. Data di <dest> hanya dihapus setelah terverifikasi sudah ada di <src>.
#
# Argumen: <label> <src> <dest>
function csm_link_revert
    set -l label "$argv[1]"
    set -l src   "$argv[2]"
    set -l dest  "$argv[3]"

    if not test -L "$src"
        csm_log "SKIP  $label: bukan symlink"
        return 0
    end

    set -l current (readlink "$src")
    if test "$current" != "$dest"
        csm_warn "$label: symlink -> $current (bukan $dest)"
        if not csm_confirm "Tetap kembalikan?" "N"
            return 1
        end
    end

    if not rm -f "$src"
        csm_error "$label: gagal menghapus symlink $src"
        return 1
    end

    if not mkdir -p "$src"
        csm_error "$label: gagal membuat $src"
        return 1
    end

    if test -d "$dest"
        set -l before (csm_count_entries "$dest")

        if csm_have rsync
            rsync -aHAX "$dest/" "$src/"
        else
            cp -a "$dest/." "$src/"
        end
        if test $status -ne 0
            csm_error "$label: gagal mengembalikan data. Target TIDAK dihapus: $dest"
            return 1
        end

        set -l after (csm_count_entries "$src")
        if test "$after" -lt "$before"
            csm_error "$label: verifikasi gagal (target=$before, kembali=$after)"
            csm_error "Target TIDAK dihapus: $dest"
            return 1
        end

        if not rm -rf "$dest"
            csm_warn "$label: gagal menghapus $dest (hapus manual)"
        end
        csm_ok "$label: dikembalikan ($after entri)"
    else
        csm_ok "$label: symlink dihapus (target kosong)"
    end

    return 0
end

# ------------------------------------------------------------
# Symlink hygiene
# ------------------------------------------------------------

# Perbaiki symlink Steam yang putus dan tautkan ulang bila data
# sudah ada di drive target tetapi symlink-nya hilang.
function csm_sync_symlinks
    csm_require_config; or return 1

    csm_section "Validating & Re-syncing Symlinks"

    set -l sync_targets \
        "$HOME/.local/share/Steam/steamapps/compatdata:$CSM_WINEPREFIX_DIR/steam-compatdata-native" \
        "$HOME/.local/share/Steam/steamapps/shadercache:$CSM_SHADERCACHE_DIR/steam-shadercache-native" \
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/compatdata:$CSM_WINEPREFIX_DIR/steam-compatdata-flatpak" \
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/shadercache:$CSM_SHADERCACHE_DIR/steam-shadercache-flatpak"

    for entry in $sync_targets
        set -l parts (string split ":" -- $entry)
        set -l src $parts[1]
        set -l dest $parts[2]

        # 1. Bersihkan broken symlink
        if test -L "$src"; and not test -e "$src"
            echo "[FIX] Cleaning broken symlink: $src"
            rm -f "$src"
        end

        # 2. Re-sync bila data sudah ada di target tetapi symlink-nya hilang
        if test -d "$dest"; and not test -e "$src"; and not test -L "$src"
            echo "[SYNC] Re-linking $src -> $dest"
            ln -s "$dest" "$src"
        end
    end

    csm_ok "Symlink validation & sync complete."
end
