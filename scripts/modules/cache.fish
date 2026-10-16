#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - User cache module
#
# Strategi: symlink per-folder.
#   ~/.cache/<name> -> $CSM_CACHE_DIR/<name>
#   ~/.cache/<shader>-> $CSM_SHADERCACHE_DIR/<shader>
#
# Hanya folder yang masuk CSM_CACHE_WHITELIST yang disentuh, dan
# CSM_CACHE_BLACKLIST selalu menang (jadi folder yang pernah bikin
# masalah tetap di dalam meski masuk whitelist).
#
# Entry point publik (dipanggil lewat csm_dispatch):
#   csm cache status / migrate / revert / help
# ============================================================

# ------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------

# Folder cache yang berisi shader: jangan ditaruh di $CSM_CACHE_DIR,
# melainkan di $CSM_SHADERCACHE_DIR supaya 'csm status' rapi.
function __csm_cache_is_shader
    set -l name "$argv[1]"
    switch "$name"
        case mesa_shader_cache mesa_shader_cache_db dxvk dxvk-state-cache \
             vkd3d-proton nv nvidia nv_shader_cache
            return 0
    end
    return 1
end

# Tujuan migrasi untuk satu nama folder cache.
function __csm_cache_dest
    set -l name "$argv[1]"

    if not set -q CSM_ROOT
        csm_error "CSM_ROOT is not configured. Run 'csm setup'."
        return 1
    end

    if __csm_cache_is_shader "$name"
        echo "$CSM_SHADERCACHE_DIR/$name"
    else
        echo "$CSM_CACHE_DIR/$name"
    end
    return 0
end

# Apakah folder ini masuk whitelist dan tidak diblacklist?
function __csm_cache_is_eligible
    set -l name "$argv[1]"

    if set -q CSM_CACHE_BLACKLIST
        if contains -- "$name" $CSM_CACHE_BLACKLIST
            return 1
        end
    end

    if set -q CSM_CACHE_WHITELIST
        if contains -- "$name" $CSM_CACHE_WHITELIST
            return 0
        end
    end

    return 1
end

# Daftar nama folder di ~/.cache yang layak dimigrasikan (whitelist, ada).
function __csm_cache_candidates
    if not test -d "$HOME/.cache"
        return 0
    end

    if not set -q CSM_CACHE_WHITELIST
        return 0
    end

    for name in $CSM_CACHE_WHITELIST
        if not __csm_cache_is_eligible "$name"
            continue
        end
        set -l src "$HOME/.cache/$name"
        if test -e "$src"; or test -L "$src"
            echo "$name"
        end
    end
    return 0
end

# Semua symlink di ~/.cache yang menunjuk ke dalam root CSM.
function __csm_cache_migrated_links
    if not test -d "$HOME/.cache"
        return 0
    end

    # Penting: glob TANPA trailing slash. Kalau pakai "*/" fish
    # mengembalikan "path/" dan 'test -L' akan mengikuti symlink
    # sehingga symlink ke direktori tidak pernah terdeteksi.
    for entry in "$HOME"/.cache/* "$HOME"/.cache/.*
        set -l name (basename "$entry")
        if test "$name" = "."; or test "$name" = ".."; or test "$name" = "*"
            continue
        end
        if not test -L "$entry"
            continue
        end
        set -l target (readlink "$entry")
        if string match -q "$CSM_ROOT/*" -- "$target"
            echo "$entry"
        end
    end
    return 0
end

# ------------------------------------------------------------
# Status (read-only)
# ------------------------------------------------------------

function csm_cache_status
    csm_require_config; or return 1

    csm_section "User Cache Status"

    echo "Source  : $HOME/.cache"
    echo "Target  : $CSM_CACHE_DIR"
    echo "Shaders : $CSM_SHADERCACHE_DIR"
    echo ""

    if not test -d "$HOME/.cache"
        csm_warn "~/.cache tidak ada. Tidak ada yang bisa dimigrasikan."
        echo ""
        return 0
    end

    set -l candidates (__csm_cache_candidates)
    set -l links (__csm_cache_migrated_links)

    echo "Migrated (symlink -> drive target):"
    if test (count $links) -eq 0
        echo "  (tidak ada)"
    else
        for entry in $links
            set -l name (basename "$entry")
            printf "  %-28s %-10s -> %s\n" \
                "$name" (csm_dir_size "$entry") (readlink "$entry")
        end
    end

    echo ""
    echo "Belum dimigrasikan (masuk whitelist):"
    set -l pending
    for name in $candidates
        set -l src "$HOME/.cache/$name"
        if not test -L "$src"
            set pending $pending "$name"
        end
    end
    if test (count $pending) -eq 0
        echo "  (tidak ada)"
    else
        for name in $pending
            printf "  %-28s %s\n" "$name" (csm_dir_size "$HOME/.cache/$name")
        end
    end

    echo ""
    echo "Dilewati (blacklist):"
    set -l skipped 0
    if set -q CSM_CACHE_BLACKLIST
        for name in $CSM_CACHE_BLACKLIST
            set -l src "$HOME/.cache/$name"
            if test -e "$src"; or test -L "$src"
                printf "  %-28s %s\n" "$name" (csm_dir_size "$src")
                set skipped (math $skipped + 1)
            end
        end
    end
    if test $skipped -eq 0
        echo "  (tidak ada)"
    end

    echo ""
    if test (count $links) -gt 0
        echo "Untuk mengembalikan: csm cache revert"
    else
        echo "Untuk memigrasikan : csm cache migrate"
    end
    echo ""
end

# ------------------------------------------------------------
# Migrate
# ------------------------------------------------------------

function csm_cache_migrate
    csm_require_config; or return 1
    csm_validate_target; or return 1

    csm_section "User Cache Migration"

    if not test -d "$HOME/.cache"
        csm_warn "~/.cache tidak ada. Tidak ada yang dimigrasikan."
        return 0
    end

    set -l candidates (__csm_cache_candidates)

    if test (count $candidates) -eq 0
        csm_ok "Tidak ada folder cache yang perlu dimigrasikan."
        echo ""
        echo "Whitelist saat ini:"
        if set -q CSM_CACHE_WHITELIST
            printf '  %s\n' $CSM_CACHE_WHITELIST
        end
        echo ""
        echo "Tambah folder lewat: csm edit open"
        echo ""
        return 0
    end

    echo "Folder yang akan dipindah ke drive target:"
    echo ""
    for name in $candidates
        set -l src "$HOME/.cache/$name"
        set -l dest (__csm_cache_dest "$name"); or return 1
        if test -L "$src"
            printf "  %-28s %-10s (sudah symlink)\n" "$name" (csm_dir_size "$src")
        else
            printf "  %-28s %-10s -> %s\n" "$name" (csm_dir_size "$src") "$dest"
        end
    end
    echo ""
    echo "Source asli diganti symlink. Data diverifikasi dulu sebelum"
    echo "sumber dihapus."
    echo ""

    if not csm_confirm "Lanjut?" "N"
        echo "Dibatalkan."
        return 1
    end

    echo ""
    set -l ok 0
    set -l failed 0

    for name in $candidates
        set -l src "$HOME/.cache/$name"
        set -l dest (__csm_cache_dest "$name")
        if test -z "$dest"
            set failed (math $failed + 1)
            continue
        end

        csm_link_migrate "$name" "$src" "$dest"
        switch $status
            case 0
                set ok (math $ok + 1)
            case 2
                # tidak ada yang perlu dilakukan
            case '*'
                set failed (math $failed + 1)
        end
    end

    echo ""
    csm_ok "Selesai: $ok berhasil, $failed gagal"
    echo ""
    if test $ok -gt 0
        echo "Cek hasilnya:"
        echo "  csm cache status"
        echo ""
        echo "Untuk mengembalikan:"
        echo "  csm cache revert"
        echo ""
    end
end

# ------------------------------------------------------------
# Revert
# ------------------------------------------------------------

function csm_cache_revert
    csm_require_config; or return 1

    csm_section "User Cache Revert"

    set -l links (__csm_cache_migrated_links)

    if test (count $links) -eq 0
        csm_ok "Tidak ada folder cache yang dimigrasikan."
        echo ""
        return 0
    end

    echo "Symlink yang akan dikembalikan:"
    echo ""
    for entry in $links
        set -l name (basename "$entry")
        printf "  %-28s %-10s <- %s\n" "$name" (csm_dir_size "$entry") (readlink "$entry")
    end
    echo ""
    echo "Data dipindah balik ke ~/.cache/<nama>, symlink dihapus."
    echo "Drive target hanya dibersihkan setelah data terverifikasi kembali."
    echo ""

    if not csm_confirm "Lanjut?" "N"
        echo "Dibatalkan."
        return 1
    end

    echo ""
    set -l ok 0
    set -l failed 0

    for entry in $links
        set -l name (basename "$entry")
        set -l dest (readlink "$entry")

        csm_link_revert "$name" "$entry" "$dest"
        if test $status -eq 0
            set ok (math $ok + 1)
        else
            set failed (math $failed + 1)
        end
    end

    echo ""
    csm_ok "Selesai: $ok dikembalikan, $failed gagal"
    echo ""
end

# ------------------------------------------------------------
# Help
# ------------------------------------------------------------

function csm_cache_help
    echo "CachyOS Storage Manager - cache module"
    echo ""
    echo "Usage:"
    echo "  csm cache status     Tampilkan folder cache & status migrasinya"
    echo "  csm cache migrate    Pindah folder whitelist ke drive target"
    echo "  csm cache revert     Kembalikan folder ke ~/.cache"
    echo ""
    echo "Strategi: symlink per folder."
    echo "  ~/.cache/<name>       -> \$CSM_CACHE_DIR/<name>"
    echo "  ~/.cache/<shader>     -> \$CSM_SHADERCACHE_DIR/<shader>"
    echo ""
    echo "Yang dipindah hanya folder di CSM_CACHE_WHITELIST."
    echo "CSM_CACHE_BLACKLIST selalu menang atas whitelist."
    echo ""
    echo "Ubah daftar lewat: csm edit open"
end
