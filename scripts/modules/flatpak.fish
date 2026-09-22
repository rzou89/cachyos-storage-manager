#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Flatpak module
#
# Ported from flatpak-data-manager v1.0.5:
#   scripts/move-flatpak-data.fish
#   scripts/flatpak-data-watcher.fish
#
# Sourced by csm.fish after common.fish and the user config.
# Requires: CSM_TARGET, CSM_FLATPAK_DATA_DIR, CSM_FLATPAK_INSTALLATION
#
# Public entry point: csm_flatpak <subcommand>
# ============================================================

# ------------------------------------------------------------
# Internal config accessors
# ------------------------------------------------------------

function __csm_flatpak_source_dir
    echo "$HOME/.var/app"
end

function __csm_flatpak_core_dir
    echo "/var/lib/flatpak"
end

function __csm_flatpak_data_dir
    if set -q CSM_FLATPAK_DIR
        echo "$CSM_FLATPAK_DIR"
        return 0
    end
    if set -q CSM_FLATPAK_DATA_DIR
        echo "$CSM_FLATPAK_DATA_DIR"
        return 0
    end
    echo "ERROR: CSM_FLATPAK_DIR is not configured." >&2
    return 1
end

function __csm_flatpak_installation
    if set -q CSM_FLATPAK_INSTALLATION
        echo "$CSM_FLATPAK_INSTALLATION"
    else
        echo "cachyos"
    end
end

# Abort if the target drive is not mounted.
# Design principle: never migrate to an unmounted target.
# Uses csm_is_mounted() from common.fish.
function __csm_flatpak_require_target
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

# ------------------------------------------------------------
# Ported helpers (from move-flatpak-data.fish)
# ------------------------------------------------------------

function __csm_flatpak_is_backup_name
    set name "$argv[1]"

    string match -q '*.backup*' "$name"
    or string match -q '*.bak*' "$name"
end

function __csm_flatpak_is_running
    set app_id "$argv[1]"

    flatpak ps --columns=application 2>/dev/null \
        | string match -q -- "$app_id"
end

# ------------------------------------------------------------
# Application data migration
# (ported from migrate_app_data)
# ------------------------------------------------------------

function csm_flatpak_migrate

    set -l SOURCE (__csm_flatpak_source_dir)
    set -l DEST (__csm_flatpak_data_dir); or return 1

    echo ""
    echo "========================================"
    echo " Flatpak Application Data"
    echo "========================================"
    echo "Source : $SOURCE"
    echo "Target : $DEST"
    echo ""

    if not test -d "$SOURCE"
        echo "ERROR: source directory does not exist:"
        echo "  $SOURCE"
        return 1
    end

    mkdir -p "$DEST"

    for app_dir in "$SOURCE"/*

        if not test -e "$app_dir"; and not test -L "$app_dir"
            continue
        end

        set app_id (basename "$app_dir")

        # Symlink handling: adopt, relink, or move
        if test -L "$app_dir"
            set -l current_target (readlink "$app_dir")
            set -l desired_target "$DEST/$app_id"

            # Correct: symlink already points to target
            if test "$current_target" = "$desired_target"
                echo "SKIP linked (correct): $app_id"
                continue
            end

            # Data already at new target, only the symlink is stale
            if test -d "$desired_target"
                echo "RELINK: $app_id"
                echo "  from: $current_target"
                echo "  to  : $desired_target"
                rm "$app_dir"
                ln -s "$desired_target" "$app_dir"
                if test $status -eq 0
                    echo "  OK: $app_id"
                else
                    echo "  ERROR: relink failed"
                end
                continue
            end

            # Data still at old target: move then relink
            if test -d "$current_target"
                echo "MOVE+RELINK: $app_id"
                echo "  from: $current_target"
                echo "  to  : $desired_target"
                mkdir -p (dirname "$desired_target")
                mv "$current_target" "$desired_target"
                if test $status -ne 0
                    echo "  ERROR: move failed, symlink untouched"
                    continue
                end
                rm "$app_dir"
                ln -s "$desired_target" "$app_dir"
                if test $status -eq 0
                    echo "  OK: $app_id"
                else
                    echo "  ERROR: relink failed, data is at $desired_target"
                end
                continue
            end

            # Broken symlink
            echo "SKIP broken symlink: $app_id -> $current_target"
            continue
        end

        # Backup directories
        if __csm_flatpak_is_backup_name "$app_id"
            echo "SKIP backup: $app_id"
            continue
        end

        # Only directories
        if not test -d "$app_dir"
            echo "SKIP non-directory: $app_id"
            continue
        end

        # Must be a Flatpak application
        if not flatpak info "$app_id" >/dev/null 2>&1
            echo "SKIP not Flatpak: $app_id"
            continue
        end

        # Don't move data of a running app
        if __csm_flatpak_is_running "$app_id"
            echo "SKIP running: $app_id"
            continue
        end

        set target "$DEST/$app_id"

        echo ""
        echo "----------------------------------------"
        echo "Found: $app_id"

        # Don't overwrite existing target
        if test -e "$target"
            echo "SKIP target already exists:"
            echo "  $target"
            continue
        end

        echo "Moving:"
        echo "  FROM: $app_dir"
        echo "  TO  : $target"

        mv "$app_dir" "$target"

        if test $status -ne 0
            echo "ERROR: failed to move $app_id"
            continue
        end

        ln -s "$target" "$app_dir"

        if test $status -ne 0
            echo "ERROR: failed to create symlink"
            echo "Data remains safely at:"
            echo "  $target"
            continue
        end

        echo "OK: $app_id"
    end

    echo ""
    echo "========================================"
    echo " Application data migration finished"
    echo "========================================"
end

# ------------------------------------------------------------
# Core migration
# (ported from migrate_core)
# ------------------------------------------------------------

function csm_flatpak_migrate_core

    set -l INSTALLATION (__csm_flatpak_installation)

    echo ""
    echo "========================================"
    echo " Flatpak Core Migration"
    echo "========================================"
    echo "From : system (/var/lib/flatpak)"
    echo "To   : $INSTALLATION"
    echo ""

    # Check target installation
    if not flatpak --installation="$INSTALLATION" list >/dev/null 2>&1
        echo "ERROR: Flatpak installation not available:"
        echo "  $INSTALLATION"
        echo ""
        echo "Available installations:"
        flatpak --installations
        return 1
    end

    # Get apps from default system installation
    set apps (flatpak --system list --app --columns=application 2>/dev/null)

    if test (count $apps) -eq 0
        echo "No applications are installed in /var/lib/flatpak."
        echo ""
        return 0
    end

    for app_id in $apps

        echo ""
        echo "----------------------------------------"
        echo "Application: $app_id"

        # If already on target, just remove old default copy
        if flatpak --installation="$INSTALLATION" info "$app_id" >/dev/null 2>&1

            echo "Already exists on $INSTALLATION."
            echo "Removing default copy..."

            flatpak --system uninstall --app -y "$app_id"

            if test $status -eq 0
                echo "OK: old default copy removed."
            else
                echo "WARNING: could not remove old default copy."
            end

            continue
        end

        # Find origin
        set origin (flatpak --system info --show-origin "$app_id" 2>/dev/null | string trim)

        if test -z "$origin"
            echo "ERROR: could not determine origin for $app_id"
            echo "Default copy will remain untouched."
            continue
        end

        echo "Origin: $origin"
        echo "Installing into $INSTALLATION..."

        flatpak --installation="$INSTALLATION" \
            install -y "$origin" "$app_id"

        if test $status -ne 0
            echo "ERROR: installation failed."
            echo "Default copy will remain untouched."
            continue
        end

        # Verify target installation
        if not flatpak --installation="$INSTALLATION" \
            info "$app_id" >/dev/null 2>&1

            echo "ERROR: verification failed."
            echo "Default copy will remain untouched."
            continue
        end

        echo "Verified on $INSTALLATION."

        # IMPORTANT: we do NOT use --delete-data.
        echo "Removing default copy..."

        flatpak --system uninstall --app -y "$app_id"

        if test $status -ne 0
            echo "WARNING:"
            echo "Application is now on $INSTALLATION,"
            echo "but the old default copy could not be removed."
            continue
        end

        echo "OK: $app_id migrated."
    end

    echo ""
    echo "Cleaning unused refs from default installation..."

    flatpak --system uninstall --unused -y

    echo ""
    echo "========================================"
    echo " Core migration finished"
    echo "========================================"
end

# ------------------------------------------------------------
# Cleanup default installation
# (ported from cleanup_core)
# ------------------------------------------------------------

function csm_flatpak_cleanup

    echo ""
    echo "========================================"
    echo " Flatpak Core Cleanup"
    echo "========================================"
    echo ""

    flatpak --system uninstall --unused
end

# ------------------------------------------------------------
# Status
# (ported from show_status)
# ------------------------------------------------------------

function csm_flatpak_status

    set -l INSTALLATION (__csm_flatpak_installation)
    set -l DEST ""
    if set -q CSM_FLATPAK_DIR
        set DEST "$CSM_FLATPAK_DIR"
    else if set -q CSM_FLATPAK_DATA_DIR
        set DEST "$CSM_FLATPAK_DATA_DIR"
    end

    echo ""
    echo "========================================"
    echo " Flatpak Module Status"
    echo "========================================"
    echo ""

    echo "=== Installations ==="
    flatpak --installations

    echo ""
    echo "=== Default System Applications ==="
    flatpak --system list \
        --app \
        --columns=application,name,version

    echo ""
    echo "=== $INSTALLATION Applications ==="
    flatpak --installation="$INSTALLATION" list \
        --app \
        --columns=application,name,version

    echo ""
    echo "=== Paths ==="
    echo "App data:"
    echo "  $DEST"

    echo ""
    echo "=== Disk Usage ==="

    if test -d /var/lib/flatpak
        sudo -n du -sh /var/lib/flatpak 2>/dev/null
        or du -sh /var/lib/flatpak 2>/dev/null
    end

    if test -n "$DEST"; and test -d "$DEST"
        du -sh "$DEST"
    end
end

# ------------------------------------------------------------
# Watcher
# (ported from flatpak-data-watcher.fish)
# ------------------------------------------------------------

function __csm_flatpak_wait_for_core_changes
    set -l core_source "$argv[1]"

    echo "  Waiting for Flatpak installation to finish..."

    while true
        set before (find "$core_source" -type f -printf "%T@\n" 2>/dev/null | sort -nr | head -1)
        sleep 2
        set after (find "$core_source" -type f -printf "%T@\n" 2>/dev/null | sort -nr | head -1)

        if test "$before" = "$after"
            break
        end
    end

    echo "  Flatpak core changes finished."
end

function csm_flatpak_watch

    set -l SOURCE (__csm_flatpak_source_dir)
    set -l CORE_SOURCE (__csm_flatpak_core_dir)

    echo ""
    echo "========================================"
    echo " Flatpak Data Watcher"
    echo "========================================"
    echo "Watching: $SOURCE"
    echo "========================================"
    echo ""

    # Ensure config
    if not set -q CSM_FLATPAK_DATA_DIR
        echo "ERROR: CSM_FLATPAK_DATA_DIR is not configured."
        return 1
    end

    if not set -q CSM_TARGET
        echo "ERROR: CSM_TARGET is not set."
        return 1
    end

    # Ensure sources exist
    if not test -d "$SOURCE"
        echo "ERROR: source directory does not exist:"
        echo "  $SOURCE"
        return 1
    end

    if not test -d "$CORE_SOURCE"
        echo "ERROR: Flatpak core directory does not exist:"
        echo "  $CORE_SOURCE"
        return 1
    end

    # Ensure inotifywait is available
    if not csm_have inotifywait
        echo "ERROR: inotifywait not found."
        echo "Install inotify-tools: sudo pacman -S inotify-tools"
        return 1
    end

    # Target drive may not be mounted yet when systemd starts the service.
    # Wait until it appears instead of failing (and being restarted by systemd).
    while not csm_is_mounted "$CSM_TARGET"
        echo "Target not mounted: $CSM_TARGET"
        echo "Waiting 30s for target drive to be mounted..."
        sleep 30
    end

    # Proses folder yang sudah ada terlebih dahulu (idempotent).
    csm_flatpak_migrate

    echo ""
    echo "Watcher is now waiting for new Flatpak data..."
    echo ""

    while true

        set event (inotifywait \
            -r \
            -q \
            -e create \
            -e moved_to \
            --format '%w|%f' \
            "$SOURCE" "$CORE_SOURCE")

        if test $status -ne 0
            sleep 1
            continue
        end

        set event_parts (string split '|' "$event")
        set event_source "$event_parts[1]"
        set event_name "$event_parts[2]"

        # Perubahan pada core Flatpak
        if string match -q "$CORE_SOURCE/*" "$event_source"
            echo ""
            echo "Watcher detected Flatpak core change:"
            echo "  $event_name"

            __csm_flatpak_wait_for_core_changes "$CORE_SOURCE"

            echo "  Running core migration..."
            csm_flatpak_migrate_core

            echo ""
            echo "Watcher: waiting..."
            continue
        end

        # Perubahan pada app-data
        if test "$event_source" = "$SOURCE/"
            set app_id "$event_name"
            set app_dir "$SOURCE/$app_id"
        else
            continue
        end

        if not test -d "$app_dir"
            continue
        end

        if test -L "$app_dir"
            continue
        end

        if __csm_flatpak_is_backup_name "$app_id"
            echo "Watcher: SKIP backup: $app_id"
            continue
        end

        if not flatpak info "$app_id" >/dev/null 2>&1
            echo "Watcher: SKIP not Flatpak: $app_id"
            continue
        end

        echo ""
        echo "Watcher detected:"
        echo "  $app_id"

        while true
            set running_apps (flatpak ps --columns=application 2>/dev/null)

            if not contains -- "$app_id" $running_apps
                break
            end

            echo "  $app_id is running. Waiting for application to close..."
            sleep 2
        end

        echo "  $app_id is closed."
        echo "  Running migration..."

        csm_flatpak_migrate

        echo ""
        echo "Watcher: waiting..."
    end
end

# ------------------------------------------------------------
# Help + dispatcher
# ------------------------------------------------------------

function __csm_flatpak_help
    echo "CachyOS Storage Manager - flatpak module"
    echo ""
    echo "Usage:"
    echo "  csm flatpak migrate        Migrate ~/.var/app data to target drive"
    echo "  csm flatpak migrate-core   Move apps from /var/lib/flatpak to custom installation"
    echo "  csm flatpak cleanup        Remove unused refs from default installation"
    echo "  csm flatpak status         Show installation status and disk usage"
    echo "  csm flatpak watch          Run the watcher in foreground (normally via systemd)"
    echo "  csm flatpak help           Show this help"
    echo ""
    echo "Aliases (compat): --data, --migrate-core, --cleanup-core, --status"
end

function csm_flatpak
    switch "$argv[1]"

        case "migrate" "--data"
            __csm_flatpak_require_target; or return 1
            csm_flatpak_migrate

        case "migrate-core" "--migrate-core"
            __csm_flatpak_require_target; or return 1
            csm_flatpak_migrate_core

        case "cleanup" "cleanup-core" "--cleanup-core"
            __csm_flatpak_require_target; or return 1
            csm_flatpak_cleanup

        case "status" "--status"
            csm_flatpak_status

        case "watch"
            csm_flatpak_watch

        case "help" "-h" "--help" ""
            __csm_flatpak_help

        case "*"
            echo "ERROR: unknown flatpak subcommand: $argv[1]"
            echo ""
            __csm_flatpak_help
            return 1
    end
end

# ------------------------------------------------------------
# Relocate support (used by 'csm relocate')
# ------------------------------------------------------------

# Report module state as a single pipe-delimited line.
# Format: name|source_dir|target_dir
function csm_flatpak_info
    set -l source "$HOME/.var/app"
    set -l target ""
    if set -q CSM_FLATPAK_DIR
        set target "$CSM_FLATPAK_DIR"
    else if set -q CSM_FLATPAK_DATA_DIR
        set target "$CSM_FLATPAK_DATA_DIR"
    end
    echo "flatpak|$source|$target"
end

# Move flatpak data from old_target to new_target and relink.
# Args: <old_target> <new_target>
function csm_flatpak_relocate
    set -l old_target "$argv[1]"
    set -l new_target "$argv[2]"
    set -l source "$HOME/.var/app"

    if test -z "$old_target"; or test -z "$new_target"
        echo "  ERROR: relocate requires old and new targets"
        return 1
    end

    if test "$old_target" = "$new_target"
        echo "  SKIP: target unchanged"
        return 0
    end

    mkdir -p "$new_target"

    # Move contents
    if test -d "$old_target"
        for entry in "$old_target"/* "$old_target"/.*
            set -l name (basename "$entry")
            if test "$name" = "."; or test "$name" = ".."
                continue
            end
            if not test -e "$entry"; and not test -L "$entry"
                continue
            end
            set -l dest "$new_target/$name"
            if test -e "$dest"; or test -L "$dest"
                echo "  WARN: destination already exists: $name"
                continue
            end
            mv "$entry" "$dest"
            if test $status -eq 0
                echo "  moved: $name"
            else
                echo "  ERROR: failed to move: $name"
            end
        end
    end

    # Relink every per-app symlink that pointed into old_target
    if test -d "$source"
        for app_link in "$source"/*
            if not test -L "$app_link"
                continue
            end
            set -l app_id (basename "$app_link")
            set -l current (readlink "$app_link")
            if string match -q "$old_target/*" "$current"
                rm "$app_link"
                ln -s "$new_target/$app_id" "$app_link"
                echo "  relinked: $app_id"
            end
        end
    end

    return 0
end
