# CachyOS Storage Manager — Tutorial

A step-by-step guide for non-programmers.

## Table of Contents

1. [What this tool does](#1-what-this-tool-does)
2. [First-time setup](#2-first-time-setup)
3. [Daily use](#3-daily-use)
4. [Checking status](#4-checking-status)
5. [Changing the target drive](#5-changing-the-target-drive)
6. [Editing the config](#6-editing-the-config)
7. [Uninstalling](#7-uninstalling)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. What this tool does

CachyOS Storage Manager (CSM) moves large, growing application data off your
main drive and onto a second drive, without breaking the applications that
use it.

| Module | What it moves | Where it goes |
|---|---|---|
| flatpak | `~/.var/app` — Flatpak app data | `<target>/CachyOS Storage Data Migration/flatpak/` |
| paru | `~/.cache/paru/clone` — AUR build dirs | `<target>/CachyOS Storage Data Migration/paru/` |
| pacman | `/var/cache/pacman/pkg` — package cache | planned |
| cache | `~/.cache` (selected folders) | planned |

Data is moved with a **symlink**: the original location still looks the same
to the application, but the bytes live on the second drive.

---

## 2. First-time setup

### 2.1 Install CSM

```fish
git clone git@github.com:rzou89/cachyos-storage-manager.git
cd cachyos-storage-manager
./setup.fish
```

This copies `csm` to `~/.local/bin/csm` and modules to
`~/.local/share/cachyos-storage-manager/`.

Make sure `~/.local/bin` is in your `$PATH`. `setup.fish` will tell you if
it is not.

### 2.2 Run the setup wizard

```fish
csm setup
```

You will be asked for the **target drive** — the path where you want your
data to live. Example: `/mnt/DataCachyOS`.

The wizard will:

1. Check that the path is absolute, exists, is a separate filesystem, and is writable.
2. Create a `CachyOS Storage Data Migration/` folder inside it, with subfolders `flatpak/`, `paru/`, `pacman/`, `data cache/`.
3. Write a config file to `~/.config/cachyos-storage-manager/config.fish`.
4. Optionally migrate existing data (flatpak, paru) to the new location.
5. Enable the flatpak watcher service.

### 2.3 Verify

```fish
csm status
csm flatpak status
csm paru status
```

Everything should report `[ OK ]`.

---

## 3. Daily use

Once setup is complete, you do not need to run anything. The **watcher**
service runs in the background and automatically migrates any new Flatpak
data that appears.

For paru, the symlink handles it: any new AUR clone is written directly
to the target drive.

### Manual migration

```fish
csm flatpak migrate
csm paru migrate
```

Both commands are safe to run repeatedly.

### Undo

```fish
csm paru revert
```

This moves data back to `~/.cache/paru/clone` and removes the symlink.

---

## 4. Checking status

```fish
csm status            # overall
csm flatpak status    # flatpak installations, apps, disk usage
csm paru status       # paru symlink state
csm doctor            # dependency + service health
```

---

## 5. Changing the target drive

If you want to move everything to a different drive:

```fish
csm relocate /mnt/NewDrive
```

What happens:

1. CSM verifies the new path.
2. It **stops the watcher** temporarily.
3. It **backs up** your current config.
4. It **moves** every module's data from the old target to the new target.
5. It **updates** all symlinks.
6. It **writes** a new config pointing at the new drive.
7. It **restarts** the watcher.
8. It asks whether to delete the old data. Default: **no**.

> If you say "no" to the last question, your old data stays where it was.
> Delete it manually once you are sure everything works:
> `rm -rf "/mnt/OldDrive/CachyOS Storage Data Migration"`

---

## 6. Editing the config

```fish
csm edit             # show current config
csm edit open        # open in $EDITOR
csm edit validate    # check that all required paths are set
```

The config file is a normal fish script. After editing, the next `csm`
command will pick up the new values automatically.

---

## 7. Uninstalling

Before uninstalling, revert your modules so that no broken symlinks remain:

```fish
csm paru revert
```

Then run the uninstaller:

```fish
./uninstall.fish
```

Your data on the target drive is **not** deleted by the uninstaller.

---

## 8. Troubleshooting

### `csm` command not found

Add `~/.local/bin` to your path:

```fish
fish_add_path ~/.local/bin
```

### `Watcher is not running`

```fish
systemctl --user status csm-flatpak-watcher.service
journalctl --user -u csm-flatpak-watcher.service -n 50
```

Restart it:

```fish
systemctl --user restart csm-flatpak-watcher.service
```

### Target not mounted after a reboot

If your target drive is not auto-mounted, `csm flatpak migrate` will refuse
to run. Mount the drive first, or add it to `/etc/fstab`.

The watcher will wait (and retry) until the target becomes available.

### `Config not found`

```fish
csm setup
```

### Reverting an accidental move

```fish
csm paru revert
```

### Everything is broken

1. Stopping the watcher: `systemctl --user stop csm-flatpak-watcher.service`
2. Reverting: `csm paru revert`
3. Re-running setup: `csm setup`

Your data on the target drive is never deleted without asking.