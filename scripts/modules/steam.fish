#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Steam & Gaming module
#
# Memindahkan compatdata (Wine prefixes Proton) dan shadercache Steam
# ke drive target, lalu menggantinya dengan symlink. Steam membaca
# symlink dengan normal.
#
# Entry point publik (dipanggil lewat csm_dispatch):
#   csm steam status / migrate / revert / clean-orphans / help
# ============================================================

# ------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------

# Daftar komponen: "<src>:<dest-relative>:<label>"
# <dest-relative> dipakai bersama CSM_WINEPREFIX_DIR / CSM_SHADERCACHE_DIR.
function __csm_steam_targets
    echo "$HOME/.local/share/Steam/steamapps/compatdata|$CSM_WINEPREFIX_DIR/steam-compatdata-native|Native Steam Compatdata"
    echo "$HOME/.local/share/Steam/steamapps/shadercache|$CSM_SHADERCACHE_DIR/steam-shadercache-native|Native Steam Shadercache"
    echo "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/compatdata|$CSM_WINEPREFIX_DIR/steam-compatdata-flatpak|Flatpak Steam Compatdata"
    echo "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/shadercache|$CSM_SHADERCACHE_DIR/steam-shadercache-flatpak|Flatpak Steam Shadercache"
end

# ------------------------------------------------------------
# Status
# ------------------------------------------------------------

function csm_steam_status
    csm_require_config; or return 1

    csm_section "Steam & Gaming Storage Status"

    echo "Wine Prefixes Target : $CSM_WINEPREFIX_DIR"
    echo "Shader Cache Target  : $CSM_SHADERCACHE_DIR"
    echo ""

    set -l targets (__csm_steam_targets)

    printf "%-32s %-10s %-14s\n" "Component" "Size" "Status"
    echo "----------------------------------------------------------"

    for entry in $targets
        set -l parts (string split "|" -- $entry)
        set -l path  $parts[1]
        set -l dest  $parts[2]
        set -l label $parts[3]

        if not test -e "$path"; and not test -L "$path"
            printf "%-32s %-10s %-14s\n" "$label" "-" "[NOT FOUND]"
            continue
        end

        set -l item_status "[UNTRACKED]"
        if test -L "$path"
            set -l current (readlink "$path")
            if test "$current" = "$dest"
                set item_status "[MIGRATED]"
            else
                set item_status "[OTHER LINK]"
            end
        end

        printf "%-32s %-10s %-14s\n" "$label" (csm_dir_size "$path") "$item_status"
    end

    echo ""
end

# ------------------------------------------------------------
# Migrate
# ------------------------------------------------------------

function csm_steam_migrate
    csm_require_config; or return 1
    csm_validate_target; or return 1

    csm_section "Steam Storage Migration"

    if csm_is_running steam
        csm_warn "Steam sedang berjalan."
        csm_warn "Tutup Steam dulu supaya tidak ada file yang sedang ditulis."
        if not csm_confirm "Lanjut saja?" "N"
            return 1
        end
    end

    mkdir -p "$CSM_WINEPREFIX_DIR" "$CSM_SHADERCACHE_DIR"
    if test $status -ne 0
        csm_error "Gagal membuat folder target."
        return 1
    end

    set -l targets (__csm_steam_targets)
    set -l ok 0
    set -l failed 0
    set -l skipped 0

    for entry in $targets
        set -l parts (string split "|" -- $entry)
        set -l src   $parts[1]
        set -l dest  $parts[2]
        set -l label $parts[3]

        csm_link_migrate "$label" "$src" "$dest"
        switch $status
            case 0
                set ok (math $ok + 1)
            case 2
                set skipped (math $skipped + 1)
            case '*'
                set failed (math $failed + 1)
        end
    end

    echo ""
    csm_ok "Selesai: $ok dimigrasikan, $skipped dilewati, $failed gagal"
    echo ""
    if test $ok -gt 0
        echo "Cek dengan: csm steam status"
        echo "Kembalikan dengan: csm steam revert"
        echo ""
    end
end

# ------------------------------------------------------------
# Revert
# ------------------------------------------------------------

function csm_steam_revert
    csm_require_config; or return 1

    csm_section "Steam Storage Revert"

    if csm_is_running steam
        csm_error "Steam sedang berjalan. Tutup dulu, lalu ulangi."
        return 1
    end

    set -l targets (__csm_steam_targets)
    set -l ok 0
    set -l failed 0

    for entry in $targets
        set -l parts (string split "|" -- $entry)
        set -l src   $parts[1]
        set -l dest  $parts[2]
        set -l label $parts[3]

        # Balik urutan argumen: di sini "src" adalah lokasi asli (symlink)
        # dan "dest" adalah lokasi di drive target.
        csm_link_revert "$label" "$src" "$dest"
        if test $status -eq 0
            set ok (math $ok + 1)
        else
            set failed (math $failed + 1)
        end
    end

    echo ""
    csm_ok "Selesai: $ok dikembalikan, $failed gagal/dilewati"
    echo ""
end

# ------------------------------------------------------------
# Clean orphans (read-only report, then optional delete)
# ------------------------------------------------------------

function csm_steam_clean_orphans
    csm_require_config; or return 1

    csm_section "Orphan Steam Compatdata Prefixes"

    set -l compat_dirs \
        "$HOME/.local/share/Steam/steamapps/compatdata" \
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/compatdata"
    set -l steamapps_dirs \
        "$HOME/.local/share/Steam/steamapps" \
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps"

    set -l orphans
    set -l total 0

    for idx in 1 2
        set -l cdir $compat_dirs[$idx]
        set -l sdir $steamapps_dirs[$idx]

        if not test -d "$cdir"
            continue
        end

        set -l real_cdir (realpath "$cdir" 2>/dev/null)
        if test -z "$real_cdir"
            set real_cdir "$cdir"
        end

        for item in (/usr/bin/ls -1 "$real_cdir" 2>/dev/null)
            if not string match -rq '^[0-9]+$' -- "$item"
                continue
            end

            set -l appid "$item"
            set -l acf "$sdir/appmanifest_$appid.acf"

            # 228980 = Steam Linux Runtime, 1070560 = Proton Experimental
            if test -f "$acf"; or contains -- "$appid" 0 228980 1070560
                continue
            end

            set -l orphan_path "$real_cdir/$appid"
            set orphans $orphans "$orphan_path"
            printf "[ORPHAN] AppID %-12s %-10s %s\n" \
                "$appid" (csm_dir_size "$orphan_path") "$orphan_path"
            set total (math $total + 1)
        end
    end

    echo ""
    if test $total -eq 0
        csm_ok "Tidak ada orphan prefix."
        echo ""
        return 0
    end

    echo "Ditemukan $total orphan prefix (game sudah di-uninstall)."
    echo ""
    echo "Prefix ini aman dihapus, tapi Steam akan membangun ulang kalau"
    echo "game-nya dipasang lagi."
    echo ""

    if not csm_confirm "Hapus sekarang?" "N"
        echo "Tidak ada yang dihapus."
        echo ""
        return 0
    end

    set -l removed 0
    for path in $orphans
        if not test -d "$path"
            continue
        end
        if rm -rf "$path"
            set removed (math $removed + 1)
            csm_ok "Dihapus: $path"
        else
            csm_warn "Gagal menghapus: $path"
        end
    end

    echo ""
    csm_ok "Dihapus $removed dari $total orphan prefix"
    echo ""
end

# ------------------------------------------------------------
# Help
# ------------------------------------------------------------

function csm_steam_help
    echo "CachyOS Storage Manager - steam module"
    echo ""
    echo "Usage:"
    echo "  csm steam status           Status komponen Steam"
    echo "  csm steam migrate          Pindah compatdata & shadercache"
    echo "  csm steam revert           Kembalikan ke lokasi asli"
    echo "  csm steam clean-orphans    Hapus prefix game yang sudah uninstall"
    echo ""
    echo "Yang dipindah:"
    echo "  ~/.local/share/Steam/steamapps/compatdata     (Wine prefixes)"
    echo "  ~/.local/share/Steam/steamapps/shadercache"
    echo "  plus versi Flatpak di ~/.var/app/com.valvesoftware.Steam/"
    echo ""
    echo "Strategi: symlink. Steam tidak dimodifikasi."
    echo "Tutup Steam sebelum migrate/revert."
end
