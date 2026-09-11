# github-release-pkg-url

This repository collects three Linux `.deb` installers published via GitHub Releases, with a download index and notes.

## Packages

- **Navicat Premium Lite** (Navicat free database management tool) `com.navicat.premiumlite_17.3.10-2_amd64.deb`
- **Trae SOLO CN** (ByteDance AI-native IDE) `trae-solo-cn_0.1.63-3_amd64.deb`
- **WorkBuddy CN** (Tencent CodeBuddy AI workstation · Linux repack) `com.xydw.workbuddy_5.5.6-1_amd64.deb`

## Download

Published together on GitHub Releases:

- <https://github.com/testerxydw/github-release-pkg-url/releases/tag/2026-09-02>

For the full download index of all versions (including newer WorkBuddy builds under `v*` tags) with publish timestamps, see [`github-release-pkg.txt`](github-release-pkg.txt).

## Details

Product intro, repackaging approach, key fixes and install steps: see [`github-release-pkg.md`](github-release-pkg.md).

## Install

```bash
sudo dpkg -i <package>.deb
sudo apt-get install -f   # auto-resolve missing runtime dependencies
```
