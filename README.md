# github-release-pkg-url

本仓库整理从 GitHub Release 发布的 Linux `.deb` 安装包，提供下载索引与说明。

## 包含的软件包

- **Navicat Premium Lite**（Navicat 免费版数据库管理工具）`com.navicat.premiumlite_17.3.10-2_amd64.deb`
- **Trae SOLO 国内版**（字节跳动 AI 原生 IDE）`trae-solo-cn_0.1.69-7_amd64.deb`
- **WorkBuddy CN**（腾讯 CodeBuddy AI 编程工作台 · Linux 重打包版）`com.xydw.workbuddy_5.5.6-1_amd64.deb`
- **JoyCode**（京东云 JoyCode IDE · Linux 重打包版）`joycode_3.0.10-1_amd64.deb`

## 自动构建流程

本仓库同时承载「上游版本探测 → 拉取私有源码构建 → 发布 Release → 维护下载索引 → 通知」全流程：

| 子项目 | 探测脚本 / tag | 构建 job | 产物 |
| --- | --- | --- | --- |
| WorkBuddy CN | `check-update.sh` → tag `vX.Y.Z-1` | `build-deb.yml` 的 `build`（x64 / arm64） | `com.xydw.workbuddy_*_<arch>.deb` |
| JoyCode | `check-joycode.sh` → tag `joycode-vX.Y.Z-1` | `build-deb.yml` 的 `build-joycode`（amd64） | `joycode_*_amd64.deb` |

- 定时探测每日 6 次；也可在 Actions 页面手动运行 `check-update` 工作流。
- JoyCode 安装包地址按版本号拼接（`.../init/win32-x64/<版本>/JoyCodeSetup.exe`）：探测脚本用**候选版本号 HEAD 枚举**自动发现新版与下载地址，**无需任何凭据**；若枚举漏检（大版本跳跃），可配置 Secret `JOYCODE_COOKIE` 走官方接口，或手动运行并填写 `joycode_exe_url`。
- 构建完成后 `update-index` 会自动把新 deb 链接追加进 [`github-release-pkg.txt`](github-release-pkg.txt)，`notify` 会把发布信息推到已配置的通知通道。

## 下载

统一发布在 GitHub Releases：

- <https://github.com/testerxydw/github-release-pkg-url/releases/tag/2026-09-02>

全部版本（含 WorkBuddy 新版本 `v*` tag）的下载索引与发布时间见 [`github-release-pkg.txt`](github-release-pkg.txt)。

## 详细说明

各软件包的产品简介、转制原理、关键修复与安装方法见 [`github-release-pkg.md`](github-release-pkg.md)。

## 安装

```bash
sudo dpkg -i <包名>.deb
sudo apt-get install -f   # 缺少运行时依赖时自动补齐
```
