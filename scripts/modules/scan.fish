# ------------------------------------------------------------
# Scan interaktif
#
# Memindai folder-folder besar di $HOME yang bisa dipindah ke drive
# target, lalu menawarkan migrasi berdasarkan pilihan pengguna.
#
# Inventori dibangun dari sumber kebenaran tunggal:
#   csm_managed_items        -> apps / dev / system / shader
#   __csm_cache_candidates   -> folder cache (whitelist)
#   __csm_flatpak_*          -> data per-aplikasi Flatpak
#   __csm_paru_clone_dir     -> clone AUR
#   __csm_pacman_*           -> cache paket pacman
#
# Semua pemindahan lewat csm_link_migrate, jadi sumber hanya dihapus
# setelah jumlah entri sumber dan target cocok.
# ------------------------------------------------------------

# Folder cache yang aman dihapus karena bisa dibuat ulang sendiri.
function __csm_scan_safe_cache_names
    printf '%s\n' \
        pip npm yarn go-build thumbnails \
        mozilla google-chrome chromium zen BraveSoftware \
        electron node-gyp \
        mesa_shader_cache mesa_shader_cache_db dxvk dxvk-state-cache
end

# ------------------------------------------------------------
# Inventory
# ------------------------------------------------------------

# Satu baris entri: id \t risk \t label \t source \t target \t handler \t state \t size
# Argumen: <id> <risk> <label> <source> <target> <handler> [blocked_state]
function __csm_scan_add
    set -l id "$argv[1]"
    set -l risk "$argv[2]"
    set -l label "$argv[3]"
    set -l source "$argv[4]"
    set -l target "$argv[5]"
    set -l handler "$argv[6]"
    set -l blocked_state "$argv[7]"

    if test -z "$source"; or test -z "$target"
        return 0
    end
    if not test -e "$source"; and not test -L "$source"
        return 0
    end

    set -l state "SIAP"
    set -l size "-"

    if test -L "$source"
        set -l current_target (readlink -f "$source" 2>/dev/null)
        set -l expected_target (readlink -m "$target" 2>/dev/null)
        if test -n "$current_target"; and test "$current_target" = "$expected_target"
            set state "SUDAH"
        else
            set state "CEK-SYMLINK"
        end
    else if test -d "$source"
        if not find "$source" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | string match -rq '.'
            set state "KOSONG"
        end
        set size (csm_dir_size "$source")
    else
        set state "BUKAN-DIREKTORI"
    end

    if test -n "$blocked_state"
        set state "$blocked_state"
    end

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$id" "$risk" "$label" "$source" "$target" "$handler" "$state" "$size"
    return 0
end

function __csm_scan_inventory
    set -l entries

    # Fallback bila config belum dinormalisasi.
    set -q CSM_WINEPREFIX_DIR; or set -l CSM_WINEPREFIX_DIR "$CSM_ROOT/apps/wine-prefixes"
    set -q CSM_SHADERCACHE_DIR; or set -l CSM_SHADERCACHE_DIR "$CSM_ROOT/shader-cache"

    # ---------------- Cache (berbasis CSM_CACHE_WHITELIST) ----------------
    #
    # Target diambil dari __csm_cache_dest supaya shader cache otomatis
    # masuk ke CSM_SHADERCACHE_DIR, sama seperti `csm cache migrate`.
    set -l safe_names (__csm_scan_safe_cache_names)

    if functions -q __csm_cache_candidates; and functions -q __csm_cache_dest
        for name in (__csm_cache_candidates)
            # ~/.cache/paru ditangani modul paru: kalau folder induknya
            # ikut di-symlink, symlink clone di dalamnya akan putus.
            if contains -- "$name" paru
                continue
            end

            set -l dest (__csm_cache_dest "$name")
            if test -z "$dest"
                continue
            end

            set -l risk "HATI-HATI"
            if contains -- "$name" $safe_names
                set risk "AMAN"
            end

            set entries $entries (__csm_scan_add "cache:$name" "$risk" "Cache $name" \
                "$HOME/.cache/$name" "$dest" migrate)
        end
    end

    # ---------------- Item terkelola (apps / dev / system / shader) ----------------
    set -l item_index 0
    for item in (csm_managed_items)
        set item_index (math $item_index + 1)
        set -l fields (string split '|' -- "$item")

        set -l group "$fields[1]"
        set -l label "$fields[2]"
        set -l src   "$fields[3]"
        set -l dest  "$fields[4]"

        set -l risk "HATI-HATI"
        if test "$group" = "shader"
            set risk "AMAN"
        end

        set entries $entries (__csm_scan_add "item:$item_index" "$risk" "$label" \
            "$src" "$dest" migrate)
    end

    # ---------------- Steam ----------------
    set -l steam_blocked ""
    if csm_is_running steam
        set steam_blocked "STEAM-AKTIF"
    end

    set entries $entries (__csm_scan_add steam:native-compatdata "HATI-HATI" \
        "Steam Proton prefixes (native)" \
        "$HOME/.local/share/Steam/steamapps/compatdata" \
        "$CSM_WINEPREFIX_DIR/steam-compatdata-native" steam "$steam_blocked")
    set entries $entries (__csm_scan_add steam:native-shadercache "AMAN" \
        "Steam shader cache (native)" \
        "$HOME/.local/share/Steam/steamapps/shadercache" \
        "$CSM_SHADERCACHE_DIR/steam-shadercache-native" steam "$steam_blocked")
    set entries $entries (__csm_scan_add steam:flatpak-compatdata "HATI-HATI" \
        "Steam Proton prefixes (Flatpak)" \
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/compatdata" \
        "$CSM_WINEPREFIX_DIR/steam-compatdata-flatpak" steam "$steam_blocked")
    set entries $entries (__csm_scan_add steam:flatpak-shadercache "AMAN" \
        "Steam shader cache (Flatpak)" \
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/shadercache" \
        "$CSM_SHADERCACHE_DIR/steam-shadercache-flatpak" steam "$steam_blocked")

    # ---------------- Data per-aplikasi Flatpak ----------------
    if command -sq flatpak
        and functions -q __csm_flatpak_source_dir
        and functions -q __csm_flatpak_data_dir
        and functions -q __csm_flatpak_is_backup_name
        and functions -q __csm_flatpak_is_running

        set -l flatpak_source (__csm_flatpak_source_dir)
        set -l flatpak_target (__csm_flatpak_data_dir)

        if test -n "$flatpak_source"; and test -n "$flatpak_target"; and test -d "$flatpak_source"
            for app_dir in "$flatpak_source"/*
                if not test -d "$app_dir"; or test -L "$app_dir"
                    continue
                end

                set -l app_id (basename "$app_dir")
                if __csm_flatpak_is_backup_name "$app_id"
                    continue
                end
                if not flatpak info "$app_id" >/dev/null 2>&1
                    continue
                end

                set -l blocked_state ""
                if __csm_flatpak_is_running "$app_id"
                    set blocked_state "APP-AKTIF"
                else if test -e "$flatpak_target/$app_id"
                    set blocked_state "TARGET-ADA"
                end

                set entries $entries (__csm_scan_add "flatpak:$app_id" "HATI-HATI" \
                    "Flatpak data: $app_id" "$app_dir" "$flatpak_target/$app_id" \
                    flatpak "$blocked_state")
            end
        end
    end

    # ---------------- Clone AUR paru ----------------
    if functions -q __csm_paru_clone_dir
        set -l paru_target (__csm_paru_clone_dir 2>/dev/null)
        if test -n "$paru_target"
            set entries $entries (__csm_scan_add paru:clone "HATI-HATI" "Paru AUR clones" \
                "$HOME/.cache/paru/clone" "$paru_target" paru)
        end
    end

    # ---------------- Cache paket pacman ----------------
    if functions -q __csm_pacman_source_dir
        and functions -q __csm_pacman_target_dir
        and functions -q __csm_pacman_count_pkg
        and functions -q __csm_pacman_is_running

        set -l pacman_source (__csm_pacman_source_dir)
        set -l pacman_target (__csm_pacman_target_dir)

        if test -n "$pacman_target"; and test -d "$pacman_source"
            if test (__csm_pacman_count_pkg "$pacman_source") -gt 0
                set -l blocked_state ""
                if __csm_pacman_is_running
                    set blocked_state "PACKAGE-MANAGER-AKTIF"
                end
                set entries $entries (__csm_scan_add pacman:pkg "HATI-HATI" \
                    "Cache paket pacman (perlu sudo & ubah /etc/pacman.conf)" \
                    "$pacman_source" "$pacman_target" pacman "$blocked_state")
            end
        end
    end

    printf '%s\n' $entries
    return 0
end

# ------------------------------------------------------------
# Eksekusi
# ------------------------------------------------------------

# Argumen: <satu baris entri>
function __csm_scan_execute
    set -l fields (string split (printf '\t') -- "$argv[1]")
    set -l id      "$fields[1]"
    set -l label   "$fields[3]"
    set -l source  "$fields[4]"
    set -l target  "$fields[5]"
    set -l handler "$fields[6]"

    switch "$handler"

        case migrate
            csm_link_migrate "$label" "$source" "$target"

        case flatpak
            # csm_flatpak_migrate memproses seluruh aplikasi sekaligus.
            set -l app_id (string replace 'flatpak:' '' -- "$id")
            csm_flatpak_migrate "$app_id"

        case steam
            csm_steam_migrate

        case paru
            csm_paru migrate

        case pacman
            csm_pacman migrate

        case '*'
            csm_error "Tidak ada handler migrasi untuk $id"
            return 1
    end
end

# ------------------------------------------------------------
# Antarmuka utama
# ------------------------------------------------------------

function csm_scan_help
    echo "Usage:"
    echo "  csm scan           Pindai dan tawarkan migrasi interaktif"
    echo "  csm scan --list    Pindai saja, tanpa menawarkan migrasi"
    echo ""
    echo "Menampilkan folder besar di \$HOME yang bisa dipindah ke drive target,"
    echo "dikelompokkan berdasarkan risiko: AMAN (bisa dibuat ulang) dan"
    echo "HATI-HATI (bisa berisi konfigurasi, save, atau state aplikasi)."
end

function csm_scan
    csm_require_config; or return 1

    if test -z "$CSM_ROOT"
        csm_error "CSM_ROOT belum dikonfigurasi. Jalankan 'csm setup' terlebih dahulu."
        return 1
    end

    if contains -- --help $argv; or contains -- -h $argv
        csm_scan_help
        return 0
    end

    set -l entries (__csm_scan_inventory)
    set -l eligible
    set -l safe_entries
    set -l caution_entries

    csm_section "CSM Storage Scan"

    printf "%-3s %-12s %-10s %-34s %s\n" "No" "Risiko" "Status" "Kategori" "Ukuran"
    echo "--------------------------------------------------------------------------"

    set -l number 0
    for entry in $entries
        set -l fields (string split (printf '\t') -- "$entry")
        set -l state "$fields[7]"
        set -l risk  "$fields[2]"
        set -l display_number "-"

        if test "$state" = "SIAP"
            set number (math $number + 1)
            set display_number "$number"
            set eligible $eligible "$entry"
            if test "$risk" = "AMAN"
                set safe_entries $safe_entries "$entry"
            else
                set caution_entries $caution_entries "$entry"
            end
        end

        printf "%-3s %-12s %-10s %-34s %s\n" \
            "$display_number" "$risk" "$state" "$fields[3]" "$fields[8]"

        if test "$state" != "SIAP"
            echo "    $fields[4] -> $fields[5]"
        end
    end

    if test (count $eligible) -eq 0
        echo ""
        echo "Tidak ada folder siap migrasi yang ditemukan."
        return 0
    end

    echo ""
    echo "AMAN: cache yang dikenal dapat dibuat ulang."
    echo "HATI-HATI: data bisa memuat konfigurasi, save, atau state aplikasi."
    echo "Folder kosong tidak ditawarkan. Tutup aplikasi terkait sebelum migrasi."

    if contains -- --list $argv
        return 0
    end

    echo ""
    echo "[1] Pindahkan semua kandidat (AMAN + HATI-HATI)"
    echo "[2] Pindahkan hanya kandidat AMAN"
    echo "[3] Pindahkan AMAN dan pilih kandidat HATI-HATI"
    echo "[q] Batal"
    read -P "Pilihan: " choice

    set -l selected
    switch "$choice"

        case 1
            set selected $eligible

        case 2
            set selected $safe_entries

        case 3
            set selected $safe_entries
            if test (count $caution_entries) -gt 0
                echo ""
                echo "Folder HATI-HATI:"
                for index in (seq (count $caution_entries))
                    set -l fields (string split (printf '\t') -- "$caution_entries[$index]")
                    printf "%d. %s (%s)\n    %s -> %s\n" \
                        "$index" "$fields[3]" "$fields[8]" "$fields[4]" "$fields[5]"
                end
                read -P "Pilih nomor dipisahkan koma (Enter untuk lewati): " requested
                set requested (string replace -a ',' ' ' -- "$requested")
                for index in (string split ' ' -- "$requested")
                    if string match -rq '^[0-9]+$' -- "$index"; and test "$index" -ge 1; and test "$index" -le (count $caution_entries)
                        set selected $selected "$caution_entries[$index]"
                    end
                end
            end

        case q Q
            echo "Dibatalkan."
            return 0

        case '*'
            csm_error "Pilihan tidak dikenal. Tidak ada perubahan dilakukan."
            return 1
    end

    if test (count $selected) -eq 0
        echo "Tidak ada kandidat yang dipilih."
        return 0
    end

    if not set -q CSM_TARGET; or not test -d "$CSM_TARGET"; or not csm_is_mounted "$CSM_TARGET"
        csm_error "Target belum ter-mount sebagai filesystem terpisah; tidak ada migrasi dilakukan."
        return 1
    end

    echo ""
    echo "Preview migrasi:"
    for entry in $selected
        set -l fields (string split (printf '\t') -- "$entry")
        printf "[%s] %s\n    %s -> %s\n" \
            "$fields[2]" "$fields[3]" "$fields[4]" "$fields[5]"
    end

    if not csm_confirm "Lanjutkan migrasi terpilih?" "N"
        echo "Dibatalkan."
        return 0
    end

    # Handler steam / flatpak / paru / pacman memproses seluruh kategori
    # sekaligus, jadi cukup dijalankan satu kali.
    set -l batch_handlers steam flatpak paru pacman
    set -l done_batch
    set -l failed 0

    for entry in $selected
        set -l fields (string split (printf '\t') -- "$entry")
        set -l handler "$fields[6]"

        if contains -- "$handler" $batch_handlers
            if contains -- "$handler" $done_batch
                continue
            end
            set done_batch $done_batch "$handler"
            echo ""
            echo "Migrasi: kategori $handler (diproses sekaligus untuk semua item terpilih)"
            __csm_scan_execute "$entry"
            set -l rc $status
            if test $rc -ne 0
                set failed (math $failed + 1)
            end
            continue
        end

        echo ""
        echo "Migrasi: $fields[3]"
        __csm_scan_execute "$entry"
        set -l rc $status
        # rc 2 dari csm_link_migrate = sumber tidak ada, bukan kegagalan.
        if test $rc -ne 0; and test $rc -ne 2
            set failed (math $failed + 1)
        end
    end

    if test $failed -gt 0
        csm_error "Selesai dengan $failed migrasi gagal. Data sumber yang gagal tetap dipertahankan."
        return 1
    end

    csm_ok "Semua migrasi terpilih selesai."
    return 0
end
