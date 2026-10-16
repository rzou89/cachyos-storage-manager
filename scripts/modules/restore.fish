#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Restore / rollback
#
# Mengembalikan SEMUA item yang dimigrasikan kembali ke lokasi aslinya
# di $HOME. Dipakai sebelum uninstall, atau kalau drive target mau
# dilepas.
#
# Catatan: ini hanya menyentuh item yang masih berupa symlink ke drive
# target. Item yang tidak dimigrasikan tidak disentuh.
# ============================================================

# ------------------------------------------------------------
# Internal helper
# ------------------------------------------------------------

# Wrapper tipis di atas csm_link_revert.
# Argumen: <label> <src> <dest>
function _csm_restore_app
    csm_link_revert "$argv[1]" "$argv[2]" "$argv[3]"
    return $status
end

# ------------------------------------------------------------
# Restore
# ------------------------------------------------------------

function csm_restore
    csm_require_config; or return 1

    csm_section "CSM Rollback & Restore"

    echo "Target root: $CSM_ROOT"
    echo ""
    echo "Yang akan dikembalikan:"
    echo ""

    set -l pending
    for item in (csm_managed_items)
        set -l parts (string split "|" -- $item)
        set -l label $parts[2]
        set -l src   $parts[3]
        set -l dest  $parts[4]

        if test -L "$src"; and test (readlink "$src") = "$dest"
            set pending $pending "$item"
            printf "  %-28s %-10s <- %s\n" "$label" (csm_dir_size "$src") "$dest"
        end
    end

    echo ""
    if test (count $pending) -eq 0
        csm_ok "Tidak ada item yang perlu dikembalikan."
        echo ""
        return 0
    end

    echo "Item di atas akan dipindah balik ke $HOME dan symlink-nya dihapus."
    echo "Data di drive target hanya dibersihkan setelah terverifikasi."
    echo ""
    echo "Modul lain (cache, steam, pacman, paru, flatpak) punya perintah"
    echo "revert sendiri dan TIDAK disentuh di sini."
    echo ""

    if not csm_confirm "Yakin ingin mengembalikan?" "N"
        echo "[CANCELLED] Restore dibatalkan."
        echo ""
        return 0
    end

    echo ""
    set -l ok 0
    set -l failed 0

    for item in $pending
        set -l parts (string split "|" -- $item)
        set -l label $parts[2]
        set -l src   $parts[3]
        set -l dest  $parts[4]

        _csm_restore_app "$label" "$src" "$dest"
        if test $status -eq 0
            set ok (math $ok + 1)
        else
            set failed (math $failed + 1)
        end
    end

    echo ""
    csm_ok "Restore selesai: $ok dikembalikan, $failed gagal"
    echo ""
    echo "Periksa hasilnya:"
    echo "  csm status"
    echo ""
end
