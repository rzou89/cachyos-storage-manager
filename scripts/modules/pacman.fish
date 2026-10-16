#!/usr/bin/env fish
# ============================================================
# CachyOS Storage Manager - Pacman module
#
# Strategi: dua entri CacheDir di /etc/pacman.conf.
#   1. cache di drive target  -> tujuan unduhan baru
#   2. /var/cache/pacman/pkg/ -> fallback bila drive target tidak mounted
#
# Butuh sudo. Tidak menyentuh paket terpasang.
# ============================================================

# ------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------

# Direktori cache pacman bawaan.
function __csm_pacman_source_dir
    echo "/var/cache/pacman/pkg"
end

# Direktori cache pacman di drive target.
function __csm_pacman_target_dir
    if not set -q CSM_PACMAN_DIR
        echo "ERROR: CSM_PACMAN_DIR is not configured." >&2
        return 1
    end
    echo "$CSM_PACMAN_DIR/pkg"
end

# Symlink legacy: $CSM_TARGET/csm -> $CSM_ROOT.
# Dibuat oleh versi lama karena nama folder CSM dulu mengandung spasi.
# Tidak lagi dibuat, hanya dibersihkan saat revert.
function __csm_pacman_legacy_symlink
    if not set -q CSM_TARGET
        return 1
    end
    echo "$CSM_TARGET/csm"
end

function __csm_pacman_conf
    echo "/etc/pacman.conf"
end

function __csm_pacman_marker
    echo "# Added by CachyOS Storage Manager"
end

# Cek apakah pacman / AUR helper sedang jalan.
function __csm_pacman_is_running
    for proc in pacman paru yay
        if csm_is_running $proc
            return 0
        end
    end
    return 1
end

# Pacman tidak mendukung spasi di CacheDir.
function __csm_pacman_validate_no_spaces
    set -l dir (__csm_pacman_target_dir); or return 1

    if string match -q '* *' "$dir"
        csm_error "Pacman cache path contains spaces: $dir"
        csm_error "Pacman CacheDir does not support spaces."
        csm_error "Choose a CSM_TARGET / CSM_PACMAN_DIR path without spaces."
        return 1
    end
    return 0
end

# Pastikan target siap: terkonfigurasi, ada, mounted.
function __csm_pacman_require_target
    csm_require_config; or return 1
    csm_validate_target; or return 1
    return 0
end

# Apakah blok CacheDir CSM sudah ada di /etc/pacman.conf?
function __csm_pacman_is_configured
    grep -qF (__csm_pacman_marker) (__csm_pacman_conf) 2>/dev/null
end

# Hitung jumlah file paket di sebuah direktori.
function __csm_pacman_count_pkg
    set -l dir "$argv[1]"
    if not test -d "$dir"
        echo 0
        return 0
    end
    find "$dir" -maxdepth 1 -name '*.pkg.tar.zst*' -type f 2>/dev/null | wc -l | string trim
end

# Ukuman direktori yang mudah dibaca.
function __csm_pacman_size
    set -l dir "$argv[1]"
    if not test -d "$dir"
        echo "0"
        return 0
    end
    set -l size (du -sh "$dir" 2>/dev/null | awk '{print $1}')
    if test -z "$size"
        echo "0"
        return 0
    end
    echo "$size"
end

# Jalankan helper Python untuk menambah / menghapus blok CacheDir.
# Argumen: <add|remove> [cache-dir]
function __csm_pacman_edit_conf
    set -l mode "$argv[1]"
    set -l cache_dir "$argv[2]"
    set -l conf (__csm_pacman_conf)
    set -l marker (__csm_pacman_marker)

    set -l script (mktemp /tmp/csm-pacman-XXXXXX.py)
    set -l py_marker (string escape --style=var -- $marker)

    begin
        echo 'import pathlib, re, sys'
        echo ''
        echo 'CONF = pathlib.Path(sys.argv[1])'
        echo 'MARKER = sys.argv[2]'
        echo 'MODE = sys.argv[3]'
        echo 'TARGET = sys.argv[4] if len(sys.argv) > 4 else ""'
        echo ''
        echo 'lines = CONF.read_text().split("\n")'
        echo ''
        echo '# Strip any block previously added by CSM.'
        echo 'out = []'
        echo 'i = 0'
        echo 'removed = 0'
        echo 'while i < len(lines):'
        echo '    if lines[i].strip() == MARKER:'
        echo '        i += 1'
        echo '        while i < len(lines) and re.match(r"^\s*CacheDir\s*=", lines[i]):'
        echo '            i += 1'
        echo '            removed += 1'
        echo '        continue'
        echo '    out.append(lines[i])'
        echo '    i += 1'
        echo ''
        echo 'if MODE == "remove":'
        echo '    if removed == 0:'
        echo '        print("SKIP: no CSM CacheDir block found")'
        echo '        sys.exit(0)'
        echo '    CONF.write_text("\n".join(out))'
        echo '    print("OK: removed %d CacheDir line(s)" % removed)'
        echo '    sys.exit(0)'
        echo ''
        echo 'lines = out'
        echo 'idx = None'
        echo 'for i, line in enumerate(lines):'
        echo '    if re.match(r"^\s*#\s*CacheDir\s*=", line):'
        echo '        idx = i'
        echo '        break'
        echo 'if idx is None:'
        echo '    for i, line in enumerate(lines):'
        echo '        if line.strip() == "[options]":'
        echo '            idx = i'
        echo '            break'
        echo 'if idx is None:'
        echo '    print("FAIL: no CacheDir anchor found in %s" % CONF)'
        echo '    sys.exit(1)'
        echo ''
        echo 'block = [MARKER, "CacheDir = " + TARGET + "/",'
        echo '         "CacheDir = /var/cache/pacman/pkg/"]'
        echo 'lines[idx + 1:idx + 1] = block'
        echo 'CONF.write_text("\n".join(lines))'
        echo 'print("OK: added CacheDir " + TARGET)'
    end > "$script"

    chmod 644 "$script"
    sudo python3 "$script" "$conf" "$marker" "$mode" "$cache_dir"
    set -l result $status
    rm -f "$script"
    return $result
end

# ------------------------------------------------------------
# Status (read-only)
# ------------------------------------------------------------

function csm_pacman_status
    csm_require_config; or return 1

    csm_section "Pacman Module Status"

    set -l source (__csm_pacman_source_dir)
    set -l target (__csm_pacman_target_dir); or return 1
    set -l conf (__csm_pacman_conf)

    set -l src_count (__csm_pacman_count_pkg "$source")
    set -l src_size (__csm_pacman_size "$source")
    set -l tgt_count (__csm_pacman_count_pkg "$target")
    set -l tgt_size (__csm_pacman_size "$target")

    echo "Source cache : $source ($src_size, $src_count files)"
    echo "Target cache : $target ($tgt_size, $tgt_count files)"
    echo "Config       : $conf"
    echo ""

    if __csm_pacman_is_configured
        csm_ok "CSM CacheDir terdaftar di $conf"
    else
        csm_warn "CSM CacheDir belum terdaftar."
        echo "      Jalankan: csm pacman migrate"
    end

    echo ""
    echo "CacheDir aktif di $conf:"
    set -l cachedirs (grep -E '^\s*CacheDir' "$conf" 2>/dev/null)
    if test (count $cachedirs) -eq 0
        echo "  (tidak ada)"
    else
        printf '  %s\n' $cachedirs
    end

    if __csm_pacman_is_running
        echo ""
        csm_warn "pacman / AUR helper sedang berjalan."
    end

    echo ""
end

# ------------------------------------------------------------
# Migrate
# ------------------------------------------------------------

function csm_pacman_migrate
    csm_section "Pacman Cache Migration"

    __csm_pacman_require_target; or return 1
    __csm_pacman_validate_no_spaces; or return 1

    if __csm_pacman_is_running
        csm_error "pacman / AUR helper sedang berjalan. Tutup dulu, lalu ulangi."
        return 1
    end

    if not csm_have rsync
        csm_error "rsync tidak ditemukan. Install: sudo pacman -S rsync"
        return 1
    end

    set -l source (__csm_pacman_source_dir)
    set -l target (__csm_pacman_target_dir); or return 1
    set -l conf (__csm_pacman_conf)

    set -l count (__csm_pacman_count_pkg "$source")
    set -l size (__csm_pacman_size "$source")

    echo "Source : $source ($size, $count files)"
    echo "Target : $target"
    echo "Config : $conf"
    echo ""
    echo "Langkah:"
    echo "  1. Salin paket dari source ke target (rsync)"
    echo "  2. Tambah dua baris CacheDir ke $conf"
    echo "     - target lebih dulu (untuk unduhan baru)"
    echo "     - source sebagai fallback"
    echo "  3. TIDAK menghapus apa pun dari source"
    echo ""

    if not csm_confirm "Lanjut? (sudo required)" "N"
        echo "Cancelled."
        return 1
    end

    echo ""
    echo "Requesting sudo..."
    sudo -v
    if test $status -ne 0
        csm_error "sudo access required."
        return 1
    end

    # Backup /etc/pacman.conf
    set -l timestamp (date '+%Y%m%d-%H%M%S')
    set -l conf_backup "$conf.bak.$timestamp"
    sudo cp "$conf" "$conf_backup"
    if test $status -ne 0
        csm_error "Gagal backup $conf"
        return 1
    end
    csm_ok "Config backup: $conf_backup"

    # Siapkan target
    if not mkdir -p "$target"
        csm_error "Gagal membuat target: $target"
        return 1
    end

    # Salin paket
    echo ""
    echo "Menyalin paket (ini bisa memakan waktu)..."
    sudo rsync -aHAX --info=progress2 "$source/" "$target/"
    if test $status -ne 0
        csm_error "rsync gagal. $conf tidak diubah."
        return 1
    end

    # Verifikasi
    set -l target_count (__csm_pacman_count_pkg "$target")
    if test "$target_count" -lt "$count"
        csm_error "Verifikasi gagal:"
        echo "  file di source: $count"
        echo "  file di target: $target_count"
        echo ""
        echo "$conf tidak diubah. Periksa lalu ulangi."
        return 1
    end
    csm_ok "Tersalin: $target_count file di target"

    # Update /etc/pacman.conf
    if not __csm_pacman_edit_conf add "$target"
        csm_error "Gagal memperbarui $conf"
        echo "Mengembalikan dari backup..."
        sudo cp "$conf_backup" "$conf"
        return 1
    end
    csm_ok "Diperbarui: $conf"

    # Pastikan CSM_PACMAN_DIR tercatat di config CSM
    set -l csm_cfg (csm_config_path)
    if test -f "$csm_cfg"
        if not grep -q '^set -g CSM_PACMAN_DIR' "$csm_cfg"
            echo "set -g CSM_PACMAN_DIR \"\$CSM_ROOT/cache/pacman\"" >> "$csm_cfg"
            csm_ok "CSM_PACMAN_DIR ditambahkan ke $csm_cfg"
        end
    end

    # Bersihkan symlink legacy bila ada
    set -l legacy (__csm_pacman_legacy_symlink)
    if test -n "$legacy"; and test -L "$legacy"
        csm_log "Symlink legacy ditemukan: $legacy -> "(readlink "$legacy")
        if csm_confirm "Hapus symlink legacy ini?" "N"
            sudo rm "$legacy"
            csm_ok "Symlink legacy dihapus"
        end
    end

    echo ""
    echo "========================================"
    echo " Migrasi selesai"
    echo "========================================"
    echo ""
    echo "Uji dulu sebelum menghapus file lama:"
    echo ""
    echo "  1. Cek kedua cache terdeteksi:"
    echo "       csm pacman status"
    echo ""
    echo "  2. Update DB paket (aman, tidak install apa-apa):"
    echo "       sudo pacman -Sy"
    echo ""
    echo "  3. Lihat file baru muncul di target:"
    echo "       ls \"$target\" | head"
    echo ""
    echo "  4. Kalau semua OK dan Anda yakin:"
    echo "       csm pacman cleanup-old"
    echo ""
    echo "Untuk membatalkan:"
    echo "       csm pacman revert"
    echo ""
end

# ------------------------------------------------------------
# Cleanup old (hapus .pkg.tar.zst* di source)
# ------------------------------------------------------------

function csm_pacman_cleanup_old
    csm_section "Pacman Cache Cleanup"

    set -l source (__csm_pacman_source_dir)
    if not test -d "$source"
        csm_ok "Source cache tidak ada. Tidak ada yang dibersihkan."
        return 0
    end

    set -l count (__csm_pacman_count_pkg "$source")
    set -l size (__csm_pacman_size "$source")

    if test "$count" -eq 0
        csm_ok "Tidak ada file paket di $source"
        return 0
    end

    if not __csm_pacman_is_configured
        csm_warn "CacheDir CSM belum terdaftar di "(__csm_pacman_conf)"."
        csm_warn "Menghapus source sekarang berarti kehilangan semua cache."
    end

    echo "File yang akan dihapus (pola '*.pkg.tar.zst*'):"
    echo "  Direktori : $source"
    echo "  Jumlah    : $count"
    echo "  Ukuran    : $size"
    echo ""
    echo "Hanya file yang cocok dengan pola itu yang dihapus."
    echo ""
    read -P "Ketik 'HAPUS' untuk konfirmasi: " confirm
    if test "$confirm" != "HAPUS"
        echo "Dibatalkan."
        return 0
    end

    sudo find "$source" -maxdepth 1 -name '*.pkg.tar.zst*' -type f -delete
    if test $status -ne 0
        csm_error "Sebagian file tidak bisa dihapus."
        return 1
    end

    echo ""
    csm_ok "Dihapus $count file"
    echo ""
end

# ------------------------------------------------------------
# Revert
# ------------------------------------------------------------

function csm_pacman_revert
    csm_section "Pacman Cache Revert"

    set -l source (__csm_pacman_source_dir)
    set -l target (__csm_pacman_target_dir); or return 1
    set -l conf (__csm_pacman_conf)

    echo "Langkah:"
    echo "  1. Hapus baris CacheDir CSM dari $conf"
    echo "  2. Hapus symlink legacy bila ada"
    echo "  3. Opsional: pindahkan data dari $target kembali ke $source"

    if not csm_confirm "Lanjut? (sudo required)" "N"
        echo "Cancelled."
        return 1
    end

    sudo -v
    if test $status -ne 0
        csm_error "sudo access required."
        return 1
    end

    set -l timestamp (date '+%Y%m%d-%H%M%S')
    sudo cp "$conf" "$conf.bak.$timestamp"
    csm_ok "Config backup: $conf.bak.$timestamp"

    if not __csm_pacman_edit_conf remove
        csm_error "Gagal memperbarui $conf"
        return 1
    end
    csm_ok "Baris CacheDir CSM dihapus dari $conf"

    # Symlink legacy
    set -l legacy (__csm_pacman_legacy_symlink)
    if test -n "$legacy"; and test -L "$legacy"
        if sudo rm "$legacy"
            csm_ok "Symlink legacy dihapus: $legacy"
        else
            csm_warn "Tidak bisa menghapus symlink: $legacy"
        end
    end

    # Data
    if test -d "$target"
        set -l count (__csm_pacman_count_pkg "$target")
        if test "$count" -gt 0
            echo ""
            if csm_confirm "Pindahkan $count file dari target kembali ke source?" "N"
                sudo mkdir -p "$source"
                sudo rsync -aHAX "$target/" "$source/"
                if test $status -eq 0
                    csm_ok "Data dikembalikan"
                else
                    csm_warn "Sebagian file tidak bisa dipindahkan"
                end
            else
                echo "Data di target TIDAK dipindahkan."
                echo "Lokasi: $target"
            end
        end
    end

    csm_ok "Revert selesai"
end

# ------------------------------------------------------------
# Help
# ------------------------------------------------------------

function csm_pacman_help
    echo "CachyOS Storage Manager - pacman module"
    echo ""
    echo "Usage:"
    echo "  csm pacman status         Tampilkan kedua cache + status /etc/pacman.conf"
    echo "  csm pacman migrate        Salin cache ke target dan daftarkan CacheDir"
    echo "  csm pacman cleanup-old    Hapus .pkg.tar.zst* lama di source"
    echo "  csm pacman revert         Hapus CacheDir dan opsional kembalikan data"
    echo ""
    echo "Strategi: dua entri CacheDir. Target lebih dulu untuk unduhan baru,"
    echo "source kedua sebagai fallback bila drive target tidak mounted."
    echo ""
    echo "Catatan: pacman.conf tidak mendukung spasi di CacheDir."
    echo "Pastikan CSM_TARGET / CSM_PACMAN_DIR tidak mengandung spasi."
    echo ""
    echo "Butuh sudo. Jangan dijalankan saat pacman/paru/yay berjalan."
end
