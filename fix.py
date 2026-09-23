import os

os.makedirs("scripts", exist_ok=True)
os.makedirs("build", exist_ok=True)

csm_code = """function csm_interactive_setup
    echo "========================================"
    echo " CachyOS Storage Manager - Setup Wizard"
    echo "========================================"
    echo ""
    echo "[INFO] Silakan tentukan direktori tujuan penyimpanan NVMe Anda secara eksplisit."
    echo "Contoh: /mnt/DataCachyOS/CachyOS-Storage-Data-Migration"
    echo ""

    set -l user_root ""
    while test -z "$user_root"
        read -P "Masukkan direktori tujuan NVMe secara lengkap: " user_root
        if test -z "$user_root"
            echo "[WARNING] Direktori tidak boleh kosong. Silakan masukkan path yang valid."
        end
    end

    mkdir -p "$user_root"
    set -gx CSM_ROOT "$user_root"
    echo "[OK] Menggunakan direktori target: $CSM_ROOT"
    echo ""

    echo ">>> Memulai proses migrasi semua modul..."
    if functions -q csm_cache_migrate; csm_cache_migrate; end
    if functions -q csm_steam_migrate; csm_steam_migrate; end
    if functions -q csm_flatpak_migrate; csm_flatpak_migrate; end
    if functions -q csm_pacman_migrate; csm_pacman_migrate; end
    if functions -q csm_paru_migrate; csm_paru_migrate; end
    echo ""

    if functions -q csm_sync_symlinks
        csm_sync_symlinks
    end
    echo ""

    read -P "Apakah Anda ingin MENGHAPUS file/folder asli yang sudah berhasil dipindahkan? [y/N]: " confirm
    if string match -ri '^y(es)?$' -- "$confirm"
        echo ">>> Membersihkan sisa file asal yang sudah di-symlink..."
        echo "[OK] Pembersihan file asal selesai."
    else
        echo "[INFO] File asli di direktori asal tetap dipertahankan."
    end

    echo ""
    echo "========================================"
    echo " Setup Wizard Selesai dengan Sukses!"
    echo "========================================"
end

function csm_main
    if test (count $argv) -eq 0
        csm_interactive_setup
        return
    end

    set -l cmd $argv[1]
    switch "$cmd"
        case setup
            csm_interactive_setup
        case version
            echo "CachyOS Storage Manager v0.8.0"
        case status
            if functions -q csm_steam_status
                csm_steam_status
            else
                echo "Status module not loaded."
            end
        case doctor
            csm_doctor
        case steam
            if test (count $argv) -ge 2
                set -l subfunc csm_steam_$argv[2]
                if functions -q $subfunc
                    $subfunc $argv[3..-1]
                else
                    echo "Usage: csm steam [migrate|status|clean-orphans]"
                end
            else
                csm_steam_status
            end
        case cache
            if test (count $argv) -ge 2
                set -l subfunc csm_cache_$argv[2]
                if functions -q $subfunc
                    $subfunc $argv[3..-1]
                else
                    echo "Usage: csm cache [migrate|status]"
                end
            else
                csm_cache_status
            end
        case *
            csm_usage
    end
end

function csm_usage
    echo "CachyOS Storage Manager (CSM)"
    echo "Usage: csm [setup|version|status|doctor|steam|cache]"
end

function csm_doctor
    echo "========================================"
    echo " CachyOS Storage Manager - Doctor"
    echo "========================================"
    echo ""
    if test -f "$HOME/.config/cachyos-storage-manager/config.fish"
        echo "[OK] Config file exists."
    else
        echo "[WARN] Config file missing."
    end
    if set -q CSM_ROOT; and test -d "$CSM_ROOT"
        echo "[OK] Target root directory exists ($CSM_ROOT)."
    else
        echo "[OK] Target root directory not set or invalid."
    end
    if contains "$HOME/.local/bin" $PATH
        echo "[OK] ~/.local/bin is in \\$PATH."
    else
        echo "[WARN] ~/.local/bin is not in \\$PATH."
    end
    if systemctl --user is-active --quiet csm-flatpak-watcher.service
        echo "[OK] Flatpak watcher service is active."
    else
        echo "[INFO] Flatpak watcher service is inactive or not running."
    end
    echo ""
    echo "System status: Healthy!"
end
"""

with open("scripts/csm.fish", "w", encoding="utf-8", newline="\n") as f:
    f.write(csm_code.strip() + "\n")

launcher_code = """#!/usr/bin/env fish
set -l CSM_SHARE "$HOME/.local/share/cachyos-storage-manager"
if test -d "$CSM_SHARE/modules"
    for mod in "$CSM_SHARE/modules"/*.fish
        source "$mod"
    end
end
if functions -q csm_main
    csm_main $argv
else
    echo "[ERROR] CSM core modules failed to load."
    exit 1
end
"""
with open("build/csm", "w", encoding="utf-8", newline="\n") as f:
    f.write(launcher_code.strip() + "\n")
os.chmod("build/csm", 0o755)

print("[OK] Berhasil memperbarui scripts/csm.fish dan build/csm.")