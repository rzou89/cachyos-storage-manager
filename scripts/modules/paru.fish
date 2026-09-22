#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Paru module
#
# Symlink-based: ~/.cache/paru/clone -> $CSM_PARU_CLONE_DIR
#
# Paru itself is not modified. The symlink is transparent to
# paru and to any tool that reads from ~/.cache/paru/clone.
#
# Sourced by csm.fish after common.fish and the user config.
# Requires: CSM_TARGET, CSM_PARU_CLONE_DIR
#
# Public entry point: csm_paru <subcommand>
# ============================================================

# ------------------------------------------------------------
# Internal config accessors
# ------------------------------------------------------------

function __csm_paru_source_dir
    echo "$HOME/.cache/paru/clone"
end

function __csm_paru_clone_dir
    if not set -q CSM_PARU_CLONE_DIR
        echo "ERROR: CSM_PARU_CLONE_DIR is not configured." >&2
        return 1
    end
    echo "$CSM_PARU_CLONE_DIR"
end

# Abort if the target drive is not mounted.
function __csm_paru_require_target
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
# Status
# ------------------------------------------------------------

function csm_paru_status

    set -l SOURCE (__csm_paru_source_dir)
    set -l DEST (__csm_paru_clone_dir); or return 1

    echo ""
    echo "========================================"
    echo " Paru Module Status"
    echo "========================================"
    echo ""
    echo "Source : $SOURCE"
    echo "Target : $DEST"
    echo ""

    echo "=== Source state ==="
    if not test -e "$SOURCE"; and not test -L "$SOURCE"
        echo "  not present (paru has not been used yet)"
        echo ""
        echo "  Run 'csm paru migrate' to create the symlink."
    else if test -L "$SOURCE"
        set -l link_target (readlink "$SOURCE")
        echo "  symlink -> $link_target"
        if test "$link_target" = "$DEST"
            csm_ok "symlink points to configured target"
        else
            csm_warn "symlink points elsewhere: $link_target"
        end
    else if test -d "$SOURCE"
        echo "  real directory (not migrated)"
    end

    echo ""
    echo "=== Sizes ==="
    if test -d "$SOURCE"; and not test -L "$SOURCE"
        du -sh "$SOURCE" 2>/dev/null
    end
    if test -d "$DEST"
        du -sh "$DEST" 2>/dev/null
    end

    echo ""
end

# ------------------------------------------------------------
# Migrate
# ------------------------------------------------------------

function csm_paru_migrate

    set -l SOURCE (__csm_paru_source_dir)
    set -l DEST (__csm_paru_clone_dir); or return 1

    echo ""
    echo "========================================"
    echo " Paru Clone Migration"
    echo "========================================"
    echo "Source : $SOURCE"
    echo "Target : $DEST"
    echo ""

    # Ensure target directory exists
    if not test -d "$DEST"
        echo "Creating target directory:"
        echo "  $DEST"
        mkdir -p "$DEST"
        or begin
            echo "ERROR: failed to create target directory"
            return 1
        end
    end

    # Case 1: already symlinked
    if test -L "$SOURCE"
        set -l link_target (readlink "$SOURCE")
        if test "$link_target" = "$DEST"
            echo "SKIP: already symlinked to target"
            echo "  $SOURCE -> $link_target"
            return 0
        else
            echo "WARNING: source is a symlink but points elsewhere:"
            echo "  $SOURCE -> $link_target"
            if not csm_confirm "Replace with symlink to $DEST?" "N"
                return 1
            end
            rm "$SOURCE"
            ln -s "$DEST" "$SOURCE"
            echo "OK: relinked"
            return 0
        end
    end

    # Case 2: source does not exist — just create symlink
    if not test -e "$SOURCE"
        mkdir -p (dirname "$SOURCE")
        ln -s "$DEST" "$SOURCE"
        if test $status -eq 0
            echo "OK: created symlink (no existing data to move)"
            echo "  $SOURCE -> $DEST"
            return 0
        else
            echo "ERROR: failed to create symlink"
            return 1
        end
    end

    # Case 3: source is a real directory — move contents
    if test -d "$SOURCE"
        set -l source_count (count (ls -A "$SOURCE" 2>/dev/null))
        set -l dest_count (count (ls -A "$DEST" 2>/dev/null))

        if test "$source_count" -eq 0
            echo "Source is empty; replacing with symlink."
            rmdir "$SOURCE"
            ln -s "$DEST" "$SOURCE"
            if test $status -eq 0
                echo "OK: $SOURCE -> $DEST"
            else
                echo "ERROR: failed to create symlink"
                return 1
            end
            return 0
        end

        if test "$dest_count" -gt 0
            echo "WARNING: target already has content:"
            echo "  $DEST ($dest_count entries)"
            echo "Source has $source_count entries."
            if not csm_confirm "Merge anyway? Existing files in target may be overwritten." "N"
                return 1
            end
        end

        echo "Moving $source_count entries:"
        echo "  FROM: $SOURCE"
        echo "  TO  : $DEST"

        for entry in "$SOURCE"/* "$SOURCE"/.*
            set -l name (basename "$entry")
            if test "$name" = "."; or test "$name" = ".."
                continue
            end
            if not test -e "$entry"
                continue
            end
            mv "$entry" "$DEST/"
            if test $status -ne 0
                echo "WARNING: failed to move: $name"
            end
        end

        if test (count (ls -A "$SOURCE" 2>/dev/null)) -eq 0
            rmdir "$SOURCE"
            ln -s "$DEST" "$SOURCE"
            if test $status -eq 0
                echo "OK: $SOURCE -> $DEST"
            else
                echo "ERROR: failed to create symlink"
                echo "Source directory still exists at $SOURCE"
                return 1
            end
        else
            echo "WARNING: source not empty after move, not removing:"
            ls -A "$SOURCE"
            return 1
        end
    end

    echo ""
    echo "========================================"
    echo " Migration finished"
    echo "========================================"
end

# ------------------------------------------------------------
# Revert
# ------------------------------------------------------------

function csm_paru_revert

    set -l SOURCE (__csm_paru_source_dir)
    set -l DEST (__csm_paru_clone_dir); or return 1

    echo ""
    echo "========================================"
    echo " Paru Revert (undo symlink)"
    echo "========================================"
    echo ""

    if not test -L "$SOURCE"
        echo "SKIP: source is not a symlink:"
        echo "  $SOURCE"
        return 0
    end

    set -l link_target (readlink "$SOURCE")
    if test "$link_target" != "$DEST"
        echo "WARNING: symlink points to $link_target, not $DEST"
        if not csm_confirm "Continue anyway?" "N"
            return 1
        end
    end

    echo "This will:"
    echo "  1. Remove symlink at $SOURCE"
    echo "  2. Move data from $DEST back to $SOURCE"
    echo ""
    if not csm_confirm "Proceed?" "N"
        echo "Cancelled."
        return 1
    end

    if test -d "$DEST"
        set -l dest_count (count (ls -A "$DEST" 2>/dev/null))
        if test "$dest_count" -gt 0
            rm "$SOURCE"
            mkdir -p "$SOURCE"
            echo "Moving $dest_count entries back..."
            for entry in "$DEST"/* "$DEST"/.*
                set -l name (basename "$entry")
                if test "$name" = "."; or test "$name" = ".."
                    continue
                end
                if not test -e "$entry"
                    continue
                end
                mv "$entry" "$SOURCE/"
            end
            echo "OK: data restored to $SOURCE"
        else
            rm "$SOURCE"
            mkdir -p "$SOURCE"
            echo "OK: symlink removed (target was empty)"
        end
    else
        rm "$SOURCE"
        mkdir -p "$SOURCE"
        echo "OK: symlink removed (target did not exist)"
    end
end

# ------------------------------------------------------------
# Help + dispatcher
# ------------------------------------------------------------

function __csm_paru_help
    echo "CachyOS Storage Manager - paru module"
    echo ""
    echo "Usage:"
    echo "  csm paru status     Show current symlink state and disk usage"
    echo "  csm paru migrate    Move ~/.cache/paru/clone to target and symlink"
    echo "  csm paru revert     Undo migration (for uninstall)"
    echo "  csm paru help       Show this help"
    echo ""
    echo "Design: symlink-based. Paru is not modified."
    echo "  ~/.cache/paru/clone -> \$CSM_PARU_CLONE_DIR"
end

function csm_paru
    switch "$argv[1]"

        case "status" "--status"
            csm_paru_status

        case "migrate" "--migrate"
            __csm_paru_require_target; or return 1
            csm_paru_migrate

        case "revert" "--revert"
            csm_paru_revert

        case "help" "-h" "--help" ""
            __csm_paru_help

        case "*"
            echo "ERROR: unknown paru subcommand: $argv[1]"
            echo ""
            __csm_paru_help
            return 1
    end
end
