# CachyOS Storage Manager — Tutorial

A step-by-step guide for non-programmers.

## Table of Contents

1. [What this tool does](#1-what-this-tool-does)
2. [First-time setup](#2-first-time-setup)
3. [Daily use](#3-daily-use)
4. [Checking status](#4-checking-status)
5. [Changing the target drive](#5-changing-the-target-drive)
6. [Moving the Flatpak core installation](#6-moving-the-flatpak-core-installation)
7. [Pacman and paru caches](#7-pacman-and-paru-caches)
8. [Editing the config](#8-editing-the-config)
9. [Uninstalling](#9-uninstalling)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. What this tool does

CachyOS Storage Manager (CSM) moves large, growing application data off your
main drive and onto a second drive, without breaking the applications that
use it.

| Module | What it manages | Target |
|---|---|---|
| apps | Launcher configuration and related app data | `apps/` |
| cache | Selected user, paru, and pacman caches | `cache/` |
| dev | Development tools and data | `dev/` |
| flatpak | Flatpak user data and optional system installation | `flatpak/` |
| steam | Proton compatdata and shader caches | `apps/wine-prefixes/`, `shader-cache/` |
| system | Selected system/user integration data | `system/` |

Most data is exposed at its original path with a **symlink**. Some modules,
such as pacman, use their own configuration instead.

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

1. Validate the target path and show the configured storage root.
2. Write the config to `~/.config/cachyos-storage-manager/config.fish`.
3. Run the available app, cache, development, system, Steam, Flatpak, pacman, and paru migrations.
4. Enable the Flatpak watcher when configured and systemd is available.

### 2.3 Verify

```fish
csm status
csm flatpak status
csm steam status
csm cache status
```

Review the output for errors. Optional categories can be empty when you do not
use the corresponding application or module.

---

## 3. Daily use

Once setup is complete, you do not need to run anything. The **watcher**
service runs in the background and automatically migrates any new Flatpak
data that appears.

Migrated locations remain available to applications through their existing
paths. The Flatpak watcher handles new Flatpak data when enabled.

### Manual migration

```fish
csm flatpak migrate
csm steam migrate
csm cache migrate
```

These commands can be run again to migrate newly created data. Each one is
idempotent: already-migrated folders are skipped.

### Undo

```fish
csm steam revert      # Steam compatdata + shader caches
csm cache revert      # ~/.cache folders
csm paru revert       # AUR clone cache
csm pacman revert     # pacman CacheDir entries (needs sudo)
csm restore           # launchers, dev tools, system data
```

Each `revert` moves the data back and removes the symlink. The copy on the
target drive is only deleted after the data has been verified back at the
original location.

---

## 4. Checking status

```fish
csm status            # overall: usage per category + per item
csm flatpak status    # flatpak installations, apps, disk usage
csm steam status      # Steam compatdata and shader cache
csm cache status      # selected user cache entries
csm pacman status     # both package caches + /etc/pacman.conf
csm paru status       # AUR clone symlink
csm doctor            # dependency + service health
```

---

## 5. Changing the target drive

```fish
csm relocate /mnt/NewDrive
```

This will:

1. Validate the new drive (absolute path, exists, mounted, writable).
2. Stop the Flatpak watcher temporarily.
3. Back up the config.
4. Move the migrated module data to the new drive.
5. Rewrite the config to point at the new drive.
6. Ask whether to delete the old data (default: no).

The old data is **not** deleted unless you explicitly confirm it.

---

## 6. Moving the Flatpak core installation

> **Warning:** This touches `/etc/flatpak/installations.d/` and requires
> `sudo`. If something goes wrong, your Flatpak apps will not start until
> you fix it. `csm` verifies after the move and rolls back automatically
> on failure.

The **Flatpak core** is the installation directory where Flatpak stores
application binaries, runtimes, and the OSTree repo. It is registered in
`/etc/flatpak/installations.d/<name>.conf`.

Use `csm flatpak relocate-core` to move it. Preview the operation first.

### Preview first (dry run)

```fish
csm flatpak relocate-core --dry-run \
    "/mnt/NewDrive/CachyOS-Storage-Data-Migration/flatpak/flatpak-core/system"
```

## 7. Pacman and paru caches

### Paru

Paru clones AUR repositories into `~/.cache/paru/clone`. CSM moves that
folder to `$CSM_PARU_DIR` and leaves a symlink behind, so paru itself is
never modified.

```fish
csm paru status      # is the symlink in place?
csm paru migrate     # move the clone cache and symlink it
csm paru revert      # undo
```

### Pacman

> Requires `sudo`. Do not run it while `pacman`, `paru`, or `yay` is running.

Pacman cannot use a symlink for its cache, so CSM adds **two** `CacheDir`
entries to `/etc/pacman.conf`:

```ini
# Added by CachyOS Storage Manager
CacheDir = /mnt/DataCachyOS/CachyOS-Storage-Data-Migration/cache/pacman/pkg/
CacheDir = /var/cache/pacman/pkg/
```

The first one is where new downloads go. The second is the fallback, so
pacman still works if the target drive is not mounted.

```fish
csm pacman status        # both caches + the active CacheDir lines
csm pacman migrate       # copy the cache and register CacheDir
csm pacman cleanup-old   # delete the old *.pkg.tar.zst* from /var/cache
csm pacman revert        # remove CacheDir, optionally move data back
```

`csm pacman migrate` makes a timestamped backup of `/etc/pacman.conf` first
and restores it if anything fails. It does **not** delete the old cache —
verify with `csm pacman status` and `sudo pacman -Sy` first, then run
`csm pacman cleanup-old` when you are confident.

> `pacman.conf` does not allow spaces in `CacheDir`. If your `CSM_TARGET`
> contains a space, the module will refuse to run.

## 8. Editing the config

```fish
csm edit              # show the config
csm edit open         # open it in $EDITOR (falls back to nano/vi)
csm edit validate     # print every resolved variable and check them
```

You can also open `~/.config/cachyos-storage-manager/config.fish` directly in
any text editor. It is a Fish script; the next `csm` command loads its values.

To change which `~/.cache` folders are migrated, edit `CSM_CACHE_WHITELIST`.
A folder listed in `CSM_CACHE_BLACKLIST` is never migrated, even if it also
appears in the whitelist.

## 9. Uninstalling

Undo the migrations first, in this order:

```fish
csm pacman revert     # if you migrated the pacman cache (needs sudo)
csm paru revert
csm steam revert
csm cache revert
csm restore           # everything else
```

Then check that applications work from their original locations, and run:

```fish
./uninstall.fish
```

Your data on the target drive is **not** deleted by the uninstaller.

---

## 10. Troubleshooting

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

### Restoring supported data

```fish
csm restore
```

### Everything is broken

1. Stopping the watcher: `systemctl --user stop csm-flatpak-watcher.service`
2. Restoring supported data: `csm restore`
3. Re-running setup: `csm setup`

Your data on the target drive is never deleted without asking.