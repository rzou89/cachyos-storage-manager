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

It handles three kinds of data:

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
