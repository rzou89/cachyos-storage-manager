#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Flatpak core relocate
#
# Moves the custom Flatpak installation ("core") to a new path.
# Touches /etc/flatpak/installations.d/*.conf and the flatpak
# system helper service. Requires sudo.
#
# Public entry points (called from csm.fish):
#   csm_flatpak_core_status
#   csm_flatpak_core_relocate
#   __csm_flatpak_core_help
# ============================================================

# ------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------

function __csm_flatpak_core_installation_name
    if set -q CSM_FLATPAK_INSTALLATION
        echo "$CSM_FLATPAK_INSTALLATION"
    else
        echo "datacachyos"
    end
end

function __csm_flatpak_core_conf_path
    echo "/etc/flatpak/installations.d/"(__csm_flatpak_core_installation_name)".conf"
end

function __csm_flatpak_core_current_path
    if set -q CSM_FLATPAK_CORE_DIR
        echo "$CSM_FLATPAK_CORE_DIR"
        return 0
    end
    set -l conf (__csm_flatpak_core_conf_path)
    if test -f "$conf"
        set -l line (grep '^Path=' "$conf" 2>/dev/null | head -1)
        if test -n "$line"
            echo (string replace 'Path=' '' "$line")
            return 0
        end
    end
    echo "ERROR: cannot determine current core path" >&2
    return 1
end

function __csm_flatpak_core_apps_count
    set -l inst (__csm_flatpak_core_installation_name)
    flatpak --installation="$inst" list --columns=application 2>/dev/null \
        | wc -l | string trim
end

# ------------------------------------------------------------
# Status
# ------------------------------------------------------------

function csm_flatpak_core_status
    csm_section "Flatpak Core Status"

    set -l inst (__csm_flatpak_core_installation_name)
    set -l conf (__csm_flatpak_core_conf_path)
    set -l current (__csm_flatpak_core_current_path); or return 1

    echo "Installation : $inst"
    echo "Config file  : $conf"
    echo "Core path    : $current"

    if test -d "$current"
        set -l size (du -sh "$current" 2>/dev/null | awk '{print $1}')
        if test -n "$size"
            echo "Size         : $size"
        end
    else
        csm_warn "Path does not exist: $current"
    end

    echo "Apps         : "(__csm_flatpak_core_apps_count)
    echo ""

    echo "All flatpak installations:"
    flatpak --installations
    echo ""
end

# ------------------------------------------------------------
# Help
# ------------------------------------------------------------

function __csm_flatpak_core_help
    echo "CachyOS Storage Manager - Flatpak core"
    echo ""
    echo "Usage:"
    echo "  csm flatpak core-status                     Show current core status"
    echo "  csm flatpak relocate-core <path>            Move core to <path>"
    echo "  csm flatpak relocate-core --dry-run <path>  Preview only"
    echo "  csm flatpak core-help                       Show this help"
    echo ""
    echo "<path> must be a full absolute path, e.g."
    echo "  /mnt/NewDrive/CachyOS Storage Data Migration/Flatpak/Flatpak Core"
    echo ""
    echo "Requires sudo. All running flatpak apps must be closed first."
end

# ------------------------------------------------------------
# Relocate
# ------------------------------------------------------------

function csm_flatpak_core_relocate

    set -l dry_run 0
    set -l assume_yes 0
    set -l new_path ""

    for arg in $argv
        switch "$arg"
            case "--dry-run"
                set dry_run 1
            case "--yes" "-y"
                set assume_yes 1
            case "*"
                if test -z "$new_path"
                    set new_path "$arg"
                end
        end
    end

    if test -z "$new_path"
        csm_error "Usage: csm flatpak relocate-core <path> [--dry-run] [--yes]"
        return 1
    end

    csm_section "Flatpak Core Relocate"

    # --- Current path ---
    set -l current_path (__csm_flatpak_core_current_path)
    if test $status -ne 0
        return 1
    end

    # --- Validate new path ---
    if not string match -q '/*' "$new_path"
        csm_error "Path must be absolute: $new_path"
        return 1
    end

    if test "$current_path" = "$new_path"
        csm_ok "Already at target path. Nothing to do."
        return 0
    end

    if test -e "$new_path"
        csm_error "Destination already exists: $new_path"
        echo "Remove it or choose another path."
        return 1
    end

    set -l parent (dirname "$new_path")
    if not test -d "$parent"
        csm_error "Parent directory does not exist: $parent"
        return 1
    end

    # --- Running apps ---
    set -l running (flatpak ps --columns=application 2>/dev/null)
    if test (count $running) -gt 0
        csm_error "Flatpak apps are running:"
        printf '  %s\n' $running
        echo ""
        echo "Close them first, then retry."
        return 1
    end

    # --- Summary ---
    echo "From : $current_path"
    echo "To   : $new_path"
    echo ""

    if test "$dry_run" = "1"
        echo "[DRY RUN] No changes will be made."
        echo ""
        echo "Would:"
        echo "  1. sudo mv \"$current_path\" \"$new_path\""
        echo "  2. sudo sed -i update "( __csm_flatpak_core_conf_path)
        echo "  3. sudo systemctl restart flatpak-system-helper.service"
        echo "  4. Verify and update CSM config"
        return 0
    end

    if test "$assume_yes" = "0"
        if not csm_confirm "Proceed? (sudo required)" "N"
            echo "Cancelled."
            return 1
        end
    end

    # --- Sudo once ---
    echo ""
    echo "Requesting sudo..."
    sudo -v
    if test $status -ne 0
        csm_error "sudo access required."
        return 1
    end

    # --- Gather info ---
    set -l current_size "?"
    if test -d "$current_path"
        set current_size (sudo du -sh "$current_path" 2>/dev/null | awk '{print $1}')
    end
    set -l apps_count (__csm_flatpak_core_apps_count)

    echo "Size : $current_size"
    echo "Apps : $apps_count"
    echo ""

    # --- Stop watcher ---
    set -l watcher_was_active 0
    if command -sq systemctl
        if systemctl --user is-active csm-flatpak-watcher.service >/dev/null 2>&1
            set watcher_was_active 1
            systemctl --user stop csm-flatpak-watcher.service
            csm_ok "Watcher stopped"
        end
    end

    # --- Backup flatpak config ---
    set -l conf (__csm_flatpak_core_conf_path)
    set -l timestamp (date '+%Y%m%d-%H%M%S')
    set -l conf_backup "$conf.bak.$timestamp"

    if not test -f "$conf"
        csm_error "Config file not found: $conf"
        if test "$watcher_was_active" = "1"
            systemctl --user start csm-flatpak-watcher.service
        end
        return 1
    end

    sudo cp "$conf" "$conf_backup"
    if test $status -ne 0
        csm_error "Failed to backup config."
        if test "$watcher_was_active" = "1"
            systemctl --user start csm-flatpak-watcher.service
        end
        return 1
    end
    csm_ok "Config backup: $conf_backup"

    # --- Move ---
    echo ""
    echo "Moving core..."
    sudo mv "$current_path" "$new_path"
    if test $status -ne 0
        csm_error "Move failed. No changes made to config."
        if test "$watcher_was_active" = "1"
            systemctl --user start csm-flatpak-watcher.service
        end
        return 1
    end
    csm_ok "Moved"

    # --- Update flatpak config ---
    sudo sed -i "s|^Path=.*|Path=$new_path|" "$conf"
    if test $status -ne 0
        csm_error "Failed to update config. Rolling back..."
        sudo mv "$new_path" "$current_path"
        sudo cp "$conf_backup" "$conf"
        if test "$watcher_was_active" = "1"
            systemctl --user start csm-flatpak-watcher.service
        end
        return 1
    end
    csm_ok "Config updated"

    # --- Restart helper ---
    sudo systemctl restart flatpak-system-helper.service
    csm_ok "flatpak-system-helper restarted"

    # --- Verify ---
    sleep 1
    set -l inst (__csm_flatpak_core_installation_name)
    set -l verify_count (flatpak --installation="$inst" list --columns=application 2>/dev/null | wc -l | string trim)

    if test "$verify_count" -lt 1
        csm_error "Verification failed - no apps found at new path."
        csm_warn "Rolling back automatically..."
        sudo sed -i "s|^Path=.*|Path=$current_path|" "$conf"
        sudo mv "$new_path" "$current_path"
        sudo systemctl restart flatpak-system-helper.service
        if test "$watcher_was_active" = "1"
            systemctl --user start csm-flatpak-watcher.service
        end
        csm_error "Rollback complete."
        return 1
    end
    csm_ok "Verified: $verify_count apps found at new path"

    # --- Update CSM config ---
    set -l csm_cfg (csm_config_path)
    if test -f "$csm_cfg"
        cp "$csm_cfg" "$csm_cfg.bak.relocate-core.$timestamp"
        if grep -q '^set -g CSM_FLATPAK_CORE_DIR' "$csm_cfg"
            sed -i "s|^set -g CSM_FLATPAK_CORE_DIR .*|set -g CSM_FLATPAK_CORE_DIR \"$new_path\"|" "$csm_cfg"
        else
            echo "set -g CSM_FLATPAK_CORE_DIR \"$new_path\"" >> "$csm_cfg"
        end
        csm_ok "CSM config updated"
    end

    # --- Restart watcher ---
    if test "$watcher_was_active" = "1"
        systemctl --user start csm-flatpak-watcher.service
        csm_ok "Watcher restarted"
    end

    # --- Ask about old folder ---
    if test -d "$current_path"
        echo ""
        if csm_confirm "Remove old folder \"$current_path\"?" "N"
            sudo rm -rf "$current_path"
            csm_ok "Old folder removed"
        else
            echo "Old folder NOT removed."
            echo "Remove manually when sure:"
            echo "  sudo rm -rf \"$current_path\""
        end
    end

    echo ""
    csm_ok "Relocate core complete"
end
