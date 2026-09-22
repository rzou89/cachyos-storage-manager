#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Uninstall
# ============================================================

set -l APP_NAME "CachyOS Storage Manager"
set -l INSTALL_DIR "$HOME/.local/bin"
set -l SHARE_DIR "$HOME/.local/share/cachyos-storage-manager"
set -l CONFIG_DIR "$HOME/.config/cachyos-storage-manager"

echo ""
echo "========================================"
echo " $APP_NAME - Uninstall"
echo "========================================"
echo ""

read -P "Remove $APP_NAME? [y/N]: " confirm
if not string match -qi "y*" "$confirm"
    echo "Uninstall cancelled."
    exit 0
end

# ------------------------------------------------------------
# Remove scripts
# ------------------------------------------------------------

if test -f "$INSTALL_DIR/csm"
    rm -f "$INSTALL_DIR/csm"
    echo "Removed: $INSTALL_DIR/csm"
end

if test -d "$SHARE_DIR"
    rm -rf "$SHARE_DIR"
    echo "Removed: $SHARE_DIR"
end

# ------------------------------------------------------------
# Configuration (opsional)
# ------------------------------------------------------------

if test -d "$CONFIG_DIR"
    echo ""
    read -P "Remove configuration at $CONFIG_DIR? [y/N]: " remove_config
    if string match -qi "y*" "$remove_config"
        rm -rf "$CONFIG_DIR"
        echo "Removed: $CONFIG_DIR"
    else
        echo "Kept: $CONFIG_DIR"
    end
end

echo ""
echo "$APP_NAME has been removed."
echo ""
echo "Your data on the target drive was NOT deleted."
echo ""