# File: scripts/csm.fish - Core interactive CLI and orchestration (v1.1.0)

function csm_interactive_setup
    echo "========================================"
    echo " CachyOS Storage Manager - Setup Wizard "
    echo "========================================"
    echo ""

    set -l target_dir ""
    set -l config_file "$HOME/.config/cachyos-storage-manager/config.fish"

    if test -f "$config_file"
        source "$config_file" 2>/dev/null
    end

    if test -n "$CSM_ROOT"; and test -d "$CSM_ROOT"
        echo "[INFO] Direktori target NVMe yang terkonfigurasi saat ini:"
        echo "       $CSM_ROOT"
        echo ""
        echo "Pilih opsi direktori tujuan:"
        echo "  [1] Gunakan folder yang sudah disetting sebelumnya (Default)"
        echo "  [2] Pindahkan ke folder tujuan baru"
        echo ""
        read -P "Pilihan Anda [1/2] (ketik 1/Enter untuk lanjut, 2 untuk baru, q untuk batal): " opt_choice

        if test "$opt_choice" = "q"; or test "$opt_choice" = "cancel"; or test "$opt_choice" = "exit"
            echo "[CANCELLED] Proses wizard dibatalkan oleh pengguna."
            return 0
        else if test "$opt_choice" = "2"
            read -P "Masukkan direktori tujuan NVMe baru secara lengkap (ketik q/Enter untuk batal): " input_path
            if test -z "$input_path"; or test "$input_path" = "q"; or test "$input_path" = "cancel"; or test "$input_path" = "exit"
                echo "[CANCELLED] Proses wizard dibatalkan oleh pengguna."
                return 0
            end
            set target_dir "$input_path"
        else
            set target_dir "$CSM_ROOT"
        end
    else
        echo "[INFO] Silakan tentukan direktori tujuan penyimpanan NVMe Anda secara eksplisit."
        read -P "Masukkan direktori tujuan NVMe secara lengkap (ketik q atau tekan Enter untuk batal): " input_path
        if test -z "$input_path"; or test "$input_path" = "q"; or test "$input_path" = "cancel"; or test "$input_path" = "exit"
            echo "[CANCELLED] Proses wizard dibatalkan oleh pengguna."
            return 0
        end
        set target_dir "$input_path"
    end

    set -g CSM_ROOT "$target_dir"
    set -g CSM_TARGET "$target_dir"
    set -g CSM_PARU_DIR "$target_dir/cache/paru"

    mkdir -p "$HOME/.config/cachyos-storage-manager"
    echo "# CachyOS Storage Manager Configuration" > "$config_file"
    echo "set -g CSM_ROOT "$target_dir"" >> "$config_file"
    echo "set -g CSM_TARGET "$target_dir"" >> "$config_file"
    echo "set -g CSM_PARU_DIR "$target_dir/cache/paru"" >> "$config_file"

    echo "[OK] Menggunakan direktori target: $CSM_ROOT"
    echo ""

    echo ">>> Memulai proses migrasi semua modul..."
    if functions -q csm_cache_migrate; csm_cache_migrate; end
    if functions -q csm_apps_migrate; csm_apps_migrate; end
    if functions -q csm_system_migrate; csm_system_migrate; end
    if functions -q csm_dev_migrate; csm_dev_migrate; end
    if functions -q csm_steam_migrate; csm_steam_migrate; end
    if functions -q csm_flatpak_migrate; csm_flatpak_migrate; end
    if functions -q csm_pacman_migrate; csm_pacman_migrate; end
    if functions -q csm_paru_migrate; csm_paru_migrate; end

    echo ""
    if functions -q csm_sync_symlinks
        csm_sync_symlinks
    end

    echo ""
    echo "========================================"
    echo " Setup Wizard Selesai dengan Sukses! "
    echo "========================================"
end

function csm_usage
    echo "Usage: csm [setup|version|status|doctor|analyze|restore|steam|flatpak|cache]"
end

function csm_doctor
    echo "========================================"
    echo " CachyOS Storage Manager - Doctor"
    echo "========================================"
    echo ""
    if test -f "$HOME/.config/cachyos-storage-manager/config.fish"
        echo "[OK] File konfigurasi ada."
    else
        echo "[WARN] File konfigurasi tidak ditemukan."
    end

    if set -q CSM_ROOT; and test -d "$CSM_ROOT"
        echo "[OK] Direktori target NVMe ditemukan ($CSM_ROOT)."
    else
        echo "[WARN] Direktori target NVMe belum terkonfigurasi atau tidak valid."
    end

    if contains -- "$HOME/.local/bin" $PATH
        echo "[OK] ~/.local/bin terdaftar di $PATH."
    else
        echo "[WARN] ~/.local/bin tidak ada di $PATH."
    end

    if systemctl --user is-active --quiet csm-flatpak-watcher.service
        echo "[OK] Layanan Flatpak watcher aktif."
    else
        echo "[INFO] Layanan Flatpak watcher tidak aktif."
    end

    echo ""
    echo "System status: Healthy!"
end

function csm_load_config
    set -l config_file "$HOME/.config/cachyos-storage-manager/config.fish"
    if test -f "$config_file"
        source "$config_file" 2>/dev/null
    end

    if functions -q csm_normalize_config
        csm_normalize_config
    end
end

function csm_main
    csm_load_config
    if test (count $argv) -eq 0
        csm_interactive_setup
        return
    end

    set -l cmd $argv[1]
    switch "$cmd"
        case setup
            csm_interactive_setup
        case version
            echo "CachyOS Storage Manager v1.1.0"
        case status analyze info
            if functions -q csm_analyze
                csm_analyze
            else
                echo "Modul analisis belum dimuat."
            end
        case doctor
            csm_doctor
        case restore
            if functions -q csm_restore
                csm_restore
            else
                echo "Modul restore belum dimuat."
            end
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
        case flatpak
            if test (count $argv) -ge 2
                switch "$argv[2]"
                    case migrate status watch
                        set -l subfunc csm_flatpak_$argv[2]
                        if functions -q $subfunc
                            $subfunc $argv[3..-1]
                        else
                            echo "Usage: csm flatpak [migrate|status|watch]"
                        end
                    case core-status
                        csm_flatpak_core_status
                    case relocate-core
                        csm_flatpak_core_relocate $argv[3..-1]
                    case core-help
                        __csm_flatpak_core_help
                    case migrate-core
                        csm_flatpak_migrate_core $argv[3..-1]
                    case cleanup
                        csm_flatpak_cleanup
                    case "*"
                        echo "Usage: csm flatpak [migrate|status|watch|core-status|relocate-core|core-help|migrate-core|cleanup]"
                end
            else
                csm_flatpak_status
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
        case '*'
            csm_usage
    end
end
