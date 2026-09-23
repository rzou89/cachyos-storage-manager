#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Pacman module
#
# Strategy: two CacheDir entries in /etc/pacman.conf
#   1. $CSM_PACMAN_DIR/pkg/    (target) -- first, for new downloads
#   2. /var/cache/pacman/pkg/  (original, fallback)
#
# If the target drive is not mounted, pacman automatically falls
# back to the original path. No symlink, no bind mount.
#
# Public entry points (called from csm.fish):
#   csm_pacman_status
#   csm_pacman_migrate
#   csm_pacman_cleanup_old
#   csm_pacman_revert
#   __csm_pacman_help
# ============================================================

# ------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------

function __csm_pacman_source_dir
    echo "/var/cache/pacman/pkg"
end

# Pacman's CacheDir does not support paths with spaces (each space is
# treated as a list separator). We create a symlink without spaces under
# CSM_TARGET and reference that in /etc/pacman.conf.
function __csm_pacman_safe_root
    if not set -q CSM_TARGET
        echo "ERROR: CSM_TARGET is not set." >&2
        return 1
    end
    echo "$CSM_TARGET/csm"
end

function __csm_pacman_target_dir
    if not set -q CSM_PACMAN_DIR
        echo "ERROR: CSM_PACMAN_DIR is not configured." >&2
        return 1
    end
    set -l safe_root (__csm_pacman_safe_root); or return 1
    echo "$safe_root/pacman/pkg"
end

function __csm_pacman_real_target_dir
    echo "$CSM_PACMAN_DIR/pkg"
end

function __csm_pacman_symlink_path
    __csm_pacman_safe_root
end

function __csm_pacman_symlink_target
    if set -q CSM_ROOT
        echo "$CSM_ROOT"
    else if set -q CSM_TARGET
        echo "$CSM_TARGET/CachyOS-Storage-Data-Migration"
    else
        echo ""
    end
end

function __csm_pacman_validate_no_spaces
    if set -q CSM_TARGET
        if string match -q '* *' "$CSM_TARGET"
            csm_error "CSM_TARGET contains spaces: $CSM_TARGET"
            csm_error "Pacman CacheDir does not support spaces."
            csm_error "Choose a target path without spaces."
            return 1
        end
    end
    return 0
end

function __csm_pacman_conf
    echo "/etc/pacman.conf"
end

function __csm_pacman_is_running
    pgrep -x pacman >/dev/null 2>&1
    or pgrep -x paru >/dev/null 2>&1
    or pgrep -x yay >/dev/null 2>&1
end

function __csm_pacman_require_target
    if not set -q CSM_TARGET
        echo "ERROR: CSM_TARGET is not set." >&2
        return 1
    end
    if not test -d "$CSM_TARGET"
        echo "ERROR: target directory does not exist:"
        echo "  $CSM_TARGET"
        return 1
    end
    if not csm_is_mounted "$CSM_TARGET"
        echo "ERROR: target is not on a separate filesystem:"
        echo "  $CSM_TARGET"
        echo ""
        echo "Refusing to proceed. Mount the target drive first."
        return 1
    end
    return 0
end

function __csm_pacman_is_configured
    # Match either the old (with spaces) or new (symlink) path
    grep -qE "CacheDir = .*/csm/pacman/pkg|CacheDir = .*CachyOS-Storage-Data-Migration/pacman" /etc/pacman.conf 2>/dev/null
end

function __csm_pacman_count_pkg
    set -l dir "$argv[1]"
    if not test -d "$dir"
        echo 0
        return 0
    end
    find "$dir" -maxdepth 1 -name '*.pkg.tar.zst*' -type f 2>/dev/null | wc -l | string trim
end

# ------------------------------------------------------------
# Status
# ------------------------------------------------------------

function csm_pacman_status
    csm_section "Pacman Module Status"

    set -l source (__csm_pacman_source_dir)
    set -l real_target (__csm_pacman_real_target_dir); or return 1
    set -l safe_root (__csm_pacman_safe_root); or return 1
    set -l safe_target "$safe_root/pacman/pkg"
    set -l symlink_target (__csm_pacman_symlink_target)

    echo "Source     : $source"
    echo "Real target: $real_target"
    echo "Symlink    : $safe_root"
    echo "CacheDir   : $safe_target"
    echo ""

    echo "=== Symlink ==="
    if test -L "$safe_root"
        set -l current (readlink "$safe_root")
        echo "  $safe_root -> $current"
        if test "$current" = "$symlink_target"
            csm_ok "symlink correct"
        else
            csm_warn "symlink points elsewhere (expected: $symlink_target)"
        end
    else if test -e "$safe_root"
        csm_warn "path exists but is not a symlink: $safe_root"
    else
        echo "  not present (run 'csm pacman migrate')"
    end
    echo ""

    echo "=== Source cache ==="
    if test -d "$source"
        set -l size (du -sh "$source" 2>/dev/null | awk '{print $1}')
        echo "  size  : $size"
        echo "  files : "(__csm_pacman_count_pkg "$source")
    else
        echo "  not present"
    end
    echo ""

    echo "=== Target cache (real) ==="
    if test -d "$real_target"
        set -l size (du -sh "$real_target" 2>/dev/null | awk '{print $1}')
        echo "  size  : $size"
        echo "  files : "(__csm_pacman_count_pkg "$real_target")
    else
        echo "  not present (not migrated yet)"
    end
    echo ""

    echo "=== /etc/pacman.conf ==="
    set -l conf (__csm_pacman_conf)
    if __csm_pacman_is_configured
        csm_ok "CSM CacheDir is configured"
        echo ""
        echo "Active CacheDir entries:"
        grep -n "^CacheDir" "$conf" | sed 's/^/  /'
    else
        csm_warn "CSM CacheDir NOT configured (using default)"
        echo ""
        echo "Current config (commented out = default):"
        grep -n "CacheDir" "$conf" | sed 's/^/  /'
    end
    echo ""
end

# ------------------------------------------------------------
# Migrate
# ------------------------------------------------------------

function csm_pacman_migrate
    csm_section "Pacman Cache Migration"

    if not __csm_pacman_require_target
        return 1
    end

    if not __csm_pacman_validate_no_spaces
        return 1
    end

    if __csm_pacman_is_running
        csm_error "pacman/paru/yay is running. Stop it first."
        return 1
    end

    if __csm_pacman_is_configured
        csm_ok "Already configured. Nothing to migrate."
        echo ""
        echo "If you want to move the data again, use:"
        echo "  csm pacman cleanup-old   (remove old files)"
        echo "  csm pacman revert        (undo migration)"
        return 0
    end

    set -l source (__csm_pacman_source_dir)
    set -l real_target (__csm_pacman_real_target_dir); or return 1
    set -l safe_root (__csm_pacman_safe_root); or return 1
    set -l safe_target "$safe_root/pacman/pkg"
    set -l conf (__csm_pacman_conf)
    set -l symlink_target (__csm_pacman_symlink_target)

    if not test -d "$source"
        csm_error "Source cache does not exist: $source"
        return 1
    end

    set -l count (__csm_pacman_count_pkg "$source")
    set -l size (du -sh "$source" 2>/dev/null | awk '{print $1}')

    echo "Source     : $source ($size, $count files)"
    echo "Real target: $real_target"
    echo "Symlink    : $safe_root -> $symlink_target"
    echo "CacheDir   : $safe_target (no spaces — pacman.conf limitation)"
    echo "Config     : $conf"
    echo ""
    echo "This will:"
    echo "  1. Create symlink $safe_root"
    echo "  2. Copy packages from source to target (via rsync)"
    echo "  3. Add two CacheDir lines to $conf (using the symlink path)"
    echo "     - target first (for new downloads)"
    echo "     - original second (fallback)"
    echo "  4. NOT delete anything from source"
    echo ""

    if not csm_confirm "Proceed? (sudo required)" "N"
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
        csm_error "Failed to backup $conf"
        return 1
    end
    csm_ok "Config backup: $conf_backup"

    # Create symlink (no spaces) if missing
    if not test -L "$safe_root"
        if test -e "$safe_root"
            csm_error "Path exists but is not a symlink: $safe_root"
            csm_error "Remove it manually, then retry."
            return 1
        end
        sudo ln -s "$symlink_target" "$safe_root"
        if test $status -ne 0
            csm_error "Failed to create symlink: $safe_root"
            return 1
        end
        csm_ok "Symlink created: $safe_root -> $symlink_target"
    else
        set -l current (readlink "$safe_root")
        if test "$current" != "$symlink_target"
            csm_error "Existing symlink points elsewhere:"
            echo "  $safe_root -> $current"
            echo "Expected: $symlink_target"
            return 1
        end
        csm_ok "Symlink already present: $safe_root"
    end

    # Prepare real target
    mkdir -p "$real_target"
    if test $status -ne 0
        csm_error "Failed to create target: $real_target"
        return 1
    end

    # rsync
    echo ""
    echo "Copying packages (this may take a minute)..."
    sudo rsync -aHAX --info=progress2 "$source/" "$real_target/"
    if test $status -ne 0
        csm_error "rsync failed"
        return 1
    end

    # Verify
    set -l target_count (__csm_pacman_count_pkg "$real_target")
    if test "$target_count" -lt "$count"
        csm_error "Verification failed:"
        echo "  source files: $count"
        echo "  target files: $target_count"
        echo ""
        echo "Not updating $conf. You may retry after investigating."
        return 1
    end
    csm_ok "Copied: $target_count files at target"

    # Update /etc/pacman.conf via Python
    set -l tmpscript (mktemp /tmp/csm-pacman-XXXXXX.py)
    begin
        echo 'import pathlib, sys'
        echo 'conf = pathlib.Path("/etc/pacman.conf")'
        echo 's = conf.read_text()'
        echo 'target = sys.argv[1]'
        echo 'marker = "#CacheDir    = /var/cache/pacman/pkg/"'
        echo 'if "CachyOS-Storage-Data-Migration/pacman" in s:'
        echo '    print("SKIP: already configured")'
        echo '    sys.exit(0)'
        echo 'if marker not in s:'
        echo '    print("FAIL: marker not found in /etc/pacman.conf")'
        echo '    sys.exit(1)'
        echo 'addition = marker + "\n# Added by CachyOS Storage Manager"'
        echo 'addition += "\nCacheDir = " + target + "/"'
        echo 'addition += "\nCacheDir = /var/cache/pacman/pkg/"'
        echo 's = s.replace(marker, addition, 1)'
        echo 'conf.write_text(s)'
        echo 'print("OK")'
    end > "$tmpscript"

    sudo python3 "$tmpscript" "$safe_target"
    set -l pyresult $status
    rm -f "$tmpscript"

    if test $pyresult -ne 0
        csm_error "Failed to update $conf"
        echo "Restoring from backup..."
        sudo cp "$conf_backup" "$conf"
        return 1
    end
    csm_ok "Updated $conf"

    # Update CSM config if CSM_PACMAN_DIR not set
    set -l csm_cfg (csm_config_path)
    if test -f "$csm_cfg"
        if not grep -q '^set -g CSM_PACMAN_DIR' "$csm_cfg"
            echo "set -g CSM_PACMAN_DIR \"\$CSM_ROOT/pacman\"" >> "$csm_cfg"
            csm_ok "Added CSM_PACMAN_DIR to $csm_cfg"
        end
    end

    # Tutorial
    echo ""
    echo "========================================"
    echo " Migrasi selesai"
    echo "========================================"
    echo ""
    echo "Test dulu sebelum hapus file lama:"
    echo ""
    echo "  1. Cek kedua cache terdeteksi:"
    echo "       csm pacman status"
    echo ""
    echo "  2. Update DB paket (aman, tidak install apa-apa):"
    echo "       sudo pacman -Sy"
    echo ""
    echo "  3. Lihat file baru muncul di target:"
    echo "       ls \"$safe_target\" | head"
    echo ""
    echo "  4. Kalau semua OK dan Anda yakin, hapus file lama:"
    echo "       csm pacman cleanup-old"
    echo ""
    echo "Untuk membatalkan migrasi:"
    echo "       csm pacman revert"
    echo ""
end

# ------------------------------------------------------------
# Cleanup old (delete .pkg.tar.zst* at /var/cache/pacman/pkg)
# ------------------------------------------------------------

function csm_pacman_cleanup_old
    csm_section "Pacman Cache Cleanup"

    if not __csm_pacman_is_configured
        csm_error "No migration found. Run 'csm pacman migrate' first."
        return 1
    end

    set -l source (__csm_pacman_source_dir)

    if not test -d "$source"
        csm_ok "Source cache does not exist. Nothing to clean."
        return 0
    end

    set -l count (__csm_pacman_count_pkg "$source")
    set -l size (du -sh "$source" 2>/dev/null | awk '{print $1}')

    if test "$count" -eq 0
        csm_ok "No package files to clean in $source"
        return 0
    end

    echo "Files to delete (pattern '*.pkg.tar.zst*'):"
    echo "  Directory : $source"
    echo "  Count     : $count"
    echo "  Total size: $size"
    echo ""
    echo "Only files matching '*.pkg.tar.zst*' will be deleted."
    echo "Other files in the directory are left untouched."
    echo ""

    read -P "Ketik 'HAPUS' untuk konfirmasi: " confirm
    if test "$confirm" != "HAPUS"
        echo "Dibatalkan."
        return 0
    end

    sudo find "$source" -maxdepth 1 -name '*.pkg.tar.zst*' -type f -delete
    if test $status -ne 0
        csm_error "Some files could not be deleted."
        return 1
    end

    echo ""
    csm_ok "Deleted $count files"

    echo ""
    echo "Remaining files in $source:"
    ls -la "$source" | head -10
    echo ""
end

# ------------------------------------------------------------
# Revert
# ------------------------------------------------------------

function csm_pacman_revert
    csm_section "Pacman Cache Revert"

    if not __csm_pacman_is_configured
        csm_ok "Nothing to revert. Not configured."
        return 0
    end

    set -l source (__csm_pacman_source_dir)
    set -l real_target (__csm_pacman_real_target_dir); or return 1
    set -l safe_root (__csm_pacman_safe_root); or return 1
    set -l conf (__csm_pacman_conf)

    echo "This will:"
    echo "  1. Remove CSM CacheDir lines from $conf"
    echo "  2. Remove symlink $safe_root"
    echo "  3. Optionally move data from $real_target back to $source"
    echo ""

    if not csm_confirm "Proceed?" "N"
        echo "Cancelled."
        return 1
    end

    sudo -v
    if test $status -ne 0
        csm_error "sudo access required."
        return 1
    end

    # Backup
    set -l timestamp (date '+%Y%m%d-%H%M%S')
    sudo cp "$conf" "$conf.bak.$timestamp"
    csm_ok "Config backup: $conf.bak.$timestamp"

    # Remove our lines via Python
    set -l tmpscript (mktemp /tmp/csm-pacman-XXXXXX.py)
    begin
        echo 'import pathlib, sys'
        echo 'conf = pathlib.Path("/etc/pacman.conf")'
        echo 's = conf.read_text()'
        echo 'target = sys.argv[1]'
        echo 'needle = "# Added by CachyOS Storage Manager"'
        echo 'if needle not in s:'
        echo '    print("SKIP: marker not found")'
        echo '    sys.exit(0)'
        echo 'lines = s.split("\n")'
        echo 'out = []'
        echo 'skip_next = 0'
        echo 'for i, line in enumerate(lines):'
        echo '    if line.strip() == needle:'
        echo '        skip_next = 2'
        echo '        continue'
        echo '    if skip_next > 0 and line.strip().startswith("CacheDir"):'
        echo '        skip_next -= 1'
        echo '        continue'
        echo '    out.append(line)'
        echo 'conf.write_text("\n".join(out))'
        echo 'print("OK")'
    end > "$tmpscript"

    sudo python3 "$tmpscript" "$real_target"
    set -l pyresult $status
    rm -f "$tmpscript"

    if test $pyresult -ne 0
        csm_error "Failed to update $conf"
        return 1
    end
    csm_ok "Removed CacheDir lines from $conf"

    # Remove symlink
    if test -L "$safe_root"
        sudo rm "$safe_root"
        if test $status -eq 0
            csm_ok "Symlink removed: $safe_root"
        else
            csm_warn "Could not remove symlink: $safe_root"
        end
    end

    # Ask about data
    if test -d "$real_target"
        set -l count (__csm_pacman_count_pkg "$real_target")
        if test "$count" -gt 0
            echo ""
            if csm_confirm "Move $count files from target back to source?" "N"
                mkdir -p "$source"
                sudo rsync -aHAX "$real_target/" "$source/"
                if test $status -eq 0
                    csm_ok "Data moved back"
                else
                    csm_warn "Some files could not be moved"
                end
            else
                echo "Data on target NOT moved."
                echo "Location: $real_target"
            end
        end
    end

    csm_ok "Revert complete"
end

# ------------------------------------------------------------
# Help + dispatcher
# ------------------------------------------------------------

function __csm_pacman_help
    echo "CachyOS Storage Manager - pacman module"
    echo ""
    echo "Usage:"
    echo "  csm pacman status         Show both caches + /etc/pacman.conf state"
    echo "  csm pacman migrate        Copy cache to target and add CacheDir"
    echo "  csm pacman cleanup-old    Delete old .pkg.tar.zst* from source"
    echo "  csm pacman revert         Remove CacheDir and optionally move data back"
    echo "  csm pacman help           Show this help"
    echo ""
    echo "Strategy: two CacheDir entries. Target first for new downloads,"
    echo "source second as fallback if the target drive is not mounted."
    echo ""
    echo "Note: pacman.conf does not support spaces in CacheDir. CSM creates"
    echo "a symlink \$CSM_TARGET/csm -> \$CSM_ROOT and uses it in the config."
    echo ""
    echo "Requires sudo. Do not run while pacman/paru/yay is running."
end

function csm_pacman
    switch "$argv[1]"

        case "status" "--status"
            csm_pacman_status

        case "migrate" "--migrate"
            csm_pacman_migrate

        case "cleanup-old" "cleanup" "--cleanup-old"
            csm_pacman_cleanup_old

        case "revert" "--revert"
            csm_pacman_revert

        case "help" "-h" "--help" ""
            __csm_pacman_help

        case "*"
            echo "ERROR: unknown pacman subcommand: $argv[1]"
            echo ""
            __csm_pacman_help
            return 1
    end
end
