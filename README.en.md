# github-release-pkg-url

This repository collects Linux `.deb` installers published via GitHub Releases, with a download index and notes.

## Packages

- **Navicat Premium Lite** (Navicat free database management tool) `com.navicat.premiumlite_17.3.10-2_amd64.deb`
- **Trae SOLO CN** (ByteDance AI-native IDE) `trae-solo-cn_0.1.63-3_amd64.deb`
- **WorkBuddy CN** (Tencent CodeBuddy AI workstation · Linux repack) `com.xydw.workbuddy_5.5.6-1_amd64.deb`
- **JoyCode** (JD Cloud JoyCode IDE · Linux repack) `joycode_3.0.10-1_amd64.deb`

## Automated pipeline

This repository also hosts the full pipeline: upstream version detection → build from the private source repo → publish Release → maintain the download index → notify.

| Project | Detector / tag | Build job | Artifact |
| --- | --- | --- | --- |
| WorkBuddy CN | `check-update.sh` → tag `vX.Y.Z-1` | `build` (x64 / arm64) in `build-deb.yml` | `com.xydw.workbuddy_*_<arch>.deb` |
| JoyCode | `check-joycode.sh` → tag `joycode-vX.Y.Z-1` | `build-joycode` (amd64) in `build-deb.yml` | `joycode_*_amd64.deb` |

- Detection runs 6 times a day; the `check-update` workflow can also be run manually from the Actions tab.
- JoyCode's download/version API **requires a login**: set the `JOYCODE_COOKIE` secret for automatic detection, or pass `joycode_exe_url` when triggering the workflow manually.
- After a build, `update-index` appends the new deb links to [`github-release-pkg.txt`](github-release-pkg.txt) and `notify` pushes the release info to the configured channels.

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
