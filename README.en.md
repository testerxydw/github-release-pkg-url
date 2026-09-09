# github-release-pkg-url

This repository collects two Linux repackaged `.deb` installers published via GitHub Releases, with a download index and repackaging notes.

## Packages

- **Trae SOLO CN** (ByteDance AI-native IDE) `trae-solo-cn_0.1.58-13_amd64.deb`
- **WorkBuddy CN** (Tencent CodeBuddy AI workstation · Linux repack) `com.xydw.workbuddy_5.4.7-10_amd64.deb`

## Download

Published together on GitHub Releases:

- <https://github.com/testerxydw/github-release-pkg-url/releases/tag/2026-09-02>

## Details

Product intro, repackaging approach, key fixes and install steps: see [`github-release-pkg.md`](github-release-pkg.md).

## Install

```bash
sudo dpkg -i <package>.deb
sudo apt-get install -f   # auto-resolve missing runtime dependencies
```
