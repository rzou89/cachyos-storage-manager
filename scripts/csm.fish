#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Main CLI
#
# Entry point untuk semua perintah csm.
# ============================================================

set -l SCRIPT_DIR (dirname (status --current-filename))
set -l MODULES_DIR "$SCRIPT_DIR/modules"

# Fallback ke layout install (setup.fish):
#   ~/.local/share/cachyos-storage-manager/modules/
if not test -d "$MODULES_DIR"
    set MODULES_DIR "$HOME/.local/share/cachyos-storage-manager/modules"
end

# Load common helpers
source "$MODULES_DIR/common.fish"

# Load modules
source "$MODULES_DIR/flatpak.fish"
source "$MODULES_DIR/paru.fish"
source "$MODULES_DIR/init.fish"
source "$MODULES_DIR/flatpak-core.fish"
source "$MODULES_DIR/pacman.fish"

# ------------------------------------------------------------
# Bantuan
# ------------------------------------------------------------

function csm_usage
    echo "CachyOS Storage Manager v"(csm_version)
    echo ""
    echo "Usage:"
    echo "  csm <module> <action> [options]"
    echo "  csm <command>"
    echo ""
    echo "Commands:"
    echo "  csm setup           First-time setup wizard"
    echo "  csm relocate <path> Move all data to a new target drive"
    echo "  csm edit [action]   Show/open/validate config"
    echo "  csm status          Show overall status"
    echo "  csm doctor          Check system health"
    echo "  csm version         Show version"
    echo "  csm help            Show this help"
    echo ""
    echo "Modules:"
    echo "  csm flatpak ...     Manage Flatpak data       (v0.2.0+)"
    echo "  csm pacman  ...     Manage pacman cache       (v0.6.0)"
    echo "  csm paru    ...     Manage paru cache         (planned)"
    echo "  csm cache   ...     Manage user cache         (planned)"
    echo ""
end

# ------------------------------------------------------------
# Command: version
# ------------------------------------------------------------

function csm_cmd_version
    csm_version
end

# ------------------------------------------------------------
# Command: help
# ------------------------------------------------------------

function csm_cmd_help
    csm_usage
end

# ------------------------------------------------------------
# Command: status
# ------------------------------------------------------------

function csm_cmd_status
    csm_section "CachyOS Storage Manager - Status"

    echo "Version : "(csm_version)
    echo "Config  : "(csm_config_path)

    if test -f (csm_config_path)
        csm_ok "Configuration file exists"

        if csm_load_config
            echo ""
            echo "Target  : $CSM_TARGET"

            if test -d "$CSM_TARGET"
                csm_ok "Target directory exists"

                if csm_is_mounted "$CSM_TARGET"
                    csm_ok "Target is on a separate filesystem"
                else
                    csm_warn "Target is NOT on a separate filesystem"
                end
            else
                csm_error "Target directory does not exist: $CSM_TARGET"
            end

            echo ""
            echo "Paths"
            if set -q CSM_ROOT
                echo "  CSM_ROOT       : $CSM_ROOT"
            end
            if set -q CSM_FLATPAK_DIR
                echo "  Flatpak dir    : $CSM_FLATPAK_DIR"
            else if set -q CSM_FLATPAK_DATA_DIR
                echo "  Flatpak dir    : $CSM_FLATPAK_DATA_DIR"
            end
            if set -q CSM_PARU_DIR
                echo "  Paru dir       : $CSM_PARU_DIR"
            else if set -q CSM_PARU_CLONE_DIR
                echo "  Paru dir       : $CSM_PARU_CLONE_DIR"
            end
            echo ""
            echo "Flatpak"
            if set -q CSM_FLATPAK_INSTALLATION
                echo "  Installation   : $CSM_FLATPAK_INSTALLATION"
            end
            if set -q CSM_FLATPAK_WATCH
                echo "  Watcher        : $CSM_FLATPAK_WATCH"
            end
        end
    else
        csm_warn "Configuration file not found"
        echo ""
        echo "Run 'csm setup' (not yet implemented) or copy:"
        echo "  config/config.fish.example"
        echo "to:"
        echo "  "(csm_config_path)
    end

    echo ""
end

# ------------------------------------------------------------
# Command: doctor
# ------------------------------------------------------------

function csm_cmd_doctor
    csm_section "CachyOS Storage Manager - Doctor"

    # Dependencies
    echo "Dependencies:"
    for cmd in fish flatpak pacman paru systemctl inotifywait
        if csm_have $cmd
            csm_ok "$cmd"
        else
            csm_warn "$cmd (not found)"
        end
    end

    # Config
    echo ""
    echo "Configuration:"
    if test -f (csm_config_path)
        csm_ok "config file present"
        if csm_load_config
            echo "  target = $CSM_TARGET"
        end
    else
        csm_warn "config file missing"
    end

    # Flatpak watcher service
    echo ""
    echo "Flatpak watcher service:"
    if csm_have systemctl
        if systemctl --user is-enabled csm-flatpak-watcher.service >/dev/null 2>&1
            csm_ok "csm-flatpak-watcher.service is enabled"
            if systemctl --user is-active csm-flatpak-watcher.service >/dev/null 2>&1
                csm_ok "csm-flatpak-watcher.service is active"
            else
                csm_warn "csm-flatpak-watcher.service is not running"
            end
        else
            csm_warn "csm-flatpak-watcher.service is not enabled"
        end
    end

    echo ""
end

# ------------------------------------------------------------
# Dispatch
# ------------------------------------------------------------

function csm_main
    if test (count $argv) -eq 0
        csm_usage
        return 0
    end

    set -l cmd $argv[1]
    set -l rest $argv[2..-1]

    switch $cmd
        case version --version -v
            csm_cmd_version
        case help --help -h
            csm_cmd_help
        case status
            csm_cmd_status
        case doctor
            csm_cmd_doctor
        case setup
            csm_setup
        case relocate
            csm_relocate $rest
        case edit
            csm_edit $rest
        case flatpak
            set -l sub ""
            if test (count $rest) -gt 0
                set sub $rest[1]
            end
            switch "$sub"
                case "" help -h --help
                    csm_flatpak $rest
                case "status" "--status" "core-status"
                    # Status works even without config (degraded mode)
                    if test -f (csm_config_path)
                        csm_load_config
                    end
                    if test "$sub" = "core-status"
                        csm_flatpak_core_status
                    else
                        csm_flatpak $rest
                    end
                case "core-help"
                    __csm_flatpak_core_help
                case "relocate-core"
                    csm_load_config; or return 1
                    csm_flatpak_core_relocate $rest[2..-1]
                case '*'
                    csm_load_config; or return 1
                    csm_flatpak $rest
            end
        case paru
            set -l sub ""
            if test (count $rest) -gt 0
                set sub $rest[1]
            end
            switch "$sub"
                case "" help -h --help
                    csm_paru $rest
                case "status" "--status"
                    if test -f (csm_config_path)
                        csm_load_config
                    end
                    csm_paru $rest
                case '*'
                    csm_load_config; or return 1
                    csm_paru $rest
            end
        case pacman
            set -l sub ""
            if test (count $rest) -gt 0
                set sub $rest[1]
            end
            switch "$sub"
                case "" help -h --help
                    csm_pacman $rest
                case "status" "--status"
                    if test -f (csm_config_path)
                        csm_load_config
                    end
                    csm_pacman $rest
                case '*'
                    csm_load_config; or return 1
                    csm_pacman $rest
            end
        case cache
            csm_error "Module '$cmd' is not implemented yet."
            echo ""
            echo "Planned for a future version. See 'csm help'."
            return 1
        case '*'
            csm_error "Unknown command: $cmd"
            echo ""
            csm_usage
            return 1
    end
end

# ------------------------------------------------------------
# Entry
# ------------------------------------------------------------

csm_main $argv
