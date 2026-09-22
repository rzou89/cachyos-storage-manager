#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Main CLI
#
# Entry point untuk semua perintah csm.
# ============================================================

set -l SCRIPT_DIR (dirname (status --current-filename))
set -l MODULES_DIR "$SCRIPT_DIR/modules"

# Load common helpers
source "$MODULES_DIR/common.fish"

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
    echo "  csm status          Show overall status"
    echo "  csm doctor          Check system health"
    echo "  csm version         Show version"
    echo "  csm help            Show this help"
    echo ""
    echo "Modules (available in later versions):"
    echo "  csm flatpak ...     Manage Flatpak data"
    echo "  csm pacman  ...     Manage pacman cache"
    echo "  csm paru    ...     Manage paru cache"
    echo "  csm cache   ...     Manage user cache"
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
    for cmd in fish flatpak pacman paru systemctl
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

    echo ""
end

# ------------------------------------------------------------
# Dispatch
# ------------------------------------------------------------

function csm_main
    set -l argv_copy $argv

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
        case flatpak pacman paru cache
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