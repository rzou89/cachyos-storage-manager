#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Setup
# ============================================================

set -l APP_NAME "CachyOS Storage Manager"
set -l INSTALL_DIR "$HOME/.local/bin"
set -l CONFIG_DIR "$HOME/.config/cachyos-storage-manager"
set -l CONFIG_FILE "$CONFIG_DIR/config.fish"
set -l PROJECT_DIR (dirname (status --current-filename))

echo ""
echo "========================================"
echo " $APP_NAME - Setup"
echo "========================================"
echo ""

# ------------------------------------------------------------
# Dependencies
# ------------------------------------------------------------

for cmd in fish
    if not command -sq $cmd
        echo "ERROR: '$cmd' is not installed."
        exit 1
    end
    echo "OK: $cmd"
end

# ------------------------------------------------------------
# Install directory
# ------------------------------------------------------------

echo ""
echo "Installing to: $INSTALL_DIR"

mkdir -p "$INSTALL_DIR"
if test $status -ne 0
    echo "ERROR: failed to create $INSTALL_DIR"
    exit 1
end

# ------------------------------------------------------------
# Copy scripts
# ------------------------------------------------------------

set -l SOURCE_MAIN "$PROJECT_DIR/scripts/csm.fish"
set -l SOURCE_COMMON "$PROJECT_DIR/scripts/modules/common.fish"

if not test -f "$SOURCE_MAIN"
    echo "ERROR: missing $SOURCE_MAIN"
    exit 1
end

if not test -f "$SOURCE_COMMON"
    echo "ERROR: missing $SOURCE_COMMON"
    exit 1
end

# Struktur di ~/.local:
#   ~/.local/bin/csm              -> entry point
#   ~/.local/share/cachyos-storage-manager/common.fish

set -l SHARE_DIR "$HOME/.local/share/cachyos-storage-manager"
mkdir -p "$SHARE_DIR"

cp "$SOURCE_COMMON" "$SHARE_DIR/common.fish"
cp "$SOURCE_MAIN"   "$INSTALL_DIR/csm"
chmod +x "$INSTALL_DIR/csm"

echo "OK: installed csm -> $INSTALL_DIR/csm"
echo "OK: helpers    -> $SHARE_DIR/common.fish"

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

echo ""
echo "Configuration:"

mkdir -p "$CONFIG_DIR"

if test -f "$CONFIG_FILE"
    echo "OK: config already exists: $CONFIG_FILE"
    echo "    (leaving it untouched)"
else
    set -l EXAMPLE "$PROJECT_DIR/config/config.fish.example"
    if not test -f "$EXAMPLE"
        echo "ERROR: missing $EXAMPLE"
        exit 1
    end
    cp "$EXAMPLE" "$CONFIG_FILE"
    echo "OK: copied example to $CONFIG_FILE"
    echo ""
    echo "IMPORTANT: edit this file and set CSM_TARGET to your"
    echo "           actual target drive before using csm."
end

# ------------------------------------------------------------
# PATH check
# ------------------------------------------------------------

echo ""
if not contains "$INSTALL_DIR" $PATH
    echo "WARNING: $INSTALL_DIR is not in your \$PATH."
    echo "         Add it to your fish config:"
    echo "           fish_add_path $INSTALL_DIR"
else
    echo "OK: $INSTALL_DIR is in \$PATH"
end

echo ""
echo "========================================"
echo " Setup completed."
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Edit config:"
echo "       $EDITOR $CONFIG_FILE"
echo "  2. Verify install:"
echo "       csm version"
echo "       csm status"
echo ""