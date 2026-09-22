#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Setup
# ============================================================

set -l APP_NAME "CachyOS Storage Manager"
set -l INSTALL_DIR "$HOME/.local/bin"
set -l SHARE_DIR "$HOME/.local/share/cachyos-storage-manager"
set -l CONFIG_DIR "$HOME/.config/cachyos-storage-manager"
set -l CONFIG_FILE "$CONFIG_DIR/config.fish"
set -l SYSTEMD_USER_DIR "$HOME/.config/systemd/user"
set -l SERVICE_NAME "csm-flatpak-watcher.service"
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
# Copy scripts + modules
# ------------------------------------------------------------

set -l SOURCE_MAIN    "$PROJECT_DIR/scripts/csm.fish"
set -l SOURCE_MODULES "$PROJECT_DIR/scripts/modules"

if not test -f "$SOURCE_MAIN"
    echo "ERROR: missing $SOURCE_MAIN"
    exit 1
end

if not test -d "$SOURCE_MODULES"
    echo "ERROR: missing $SOURCE_MODULES"
    exit 1
end

# Layout:
#   ~/.local/bin/csm
#   ~/.local/share/cachyos-storage-manager/modules/*.fish

mkdir -p "$SHARE_DIR/modules"

cp "$SOURCE_MAIN" "$INSTALL_DIR/csm"
chmod +x "$INSTALL_DIR/csm"

for module in "$SOURCE_MODULES"/*.fish
    set -l name (basename "$module")
    cp "$module" "$SHARE_DIR/modules/$name"
    echo "OK: module -> $SHARE_DIR/modules/$name"
end

echo "OK: installed csm -> $INSTALL_DIR/csm"

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
# systemd user service (Flatpak watcher)
# ------------------------------------------------------------

echo ""
echo "Flatpak watcher service:"

set -l SOURCE_SERVICE "$PROJECT_DIR/systemd/$SERVICE_NAME"
set -l TARGET_SERVICE "$SYSTEMD_USER_DIR/$SERVICE_NAME"

if not test -f "$SOURCE_SERVICE"
    echo "WARN: missing $SOURCE_SERVICE (skipping service setup)"
else
    mkdir -p "$SYSTEMD_USER_DIR"
    cp "$SOURCE_SERVICE" "$TARGET_SERVICE"
    echo "OK: installed $TARGET_SERVICE"

    if command -sq systemctl
        systemctl --user daemon-reload
        echo "OK: systemctl --user daemon-reload"

        # Decide whether to enable based on config
        set -l enable_watch 1
        if test -f "$CONFIG_FILE"
            source "$CONFIG_FILE"
            if set -q CSM_FLATPAK_WATCH
                set enable_watch $CSM_FLATPAK_WATCH
            end
        end

        if test "$enable_watch" = "1"
            if not command -sq inotifywait
                echo "WARN: inotifywait not found."
                echo "      Install inotify-tools to use the watcher:"
                echo "        sudo pacman -S inotify-tools"
            end
            systemctl --user enable --now "$SERVICE_NAME"
            if test $status -eq 0
                echo "OK: $SERVICE_NAME enabled and started"
            else
                echo "WARN: failed to enable $SERVICE_NAME"
            end
        else
            echo "OK: watcher disabled in config (CSM_FLATPAK_WATCH=$enable_watch)"
        end
    else
        echo "WARN: systemctl not found, skipping service activation"
    end
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
echo "       csm doctor"
echo ""
