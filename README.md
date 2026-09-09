# github-releaase-pkg-url

本仓库整理从 GitHub Release 发布的两个 Linux 重打包 `.deb` 安装包，提供下载索引与转制说明。

## 包含的软件包

- **Trae SOLO 国内版**（字节跳动 AI 原生 IDE）`trae-solo-cn_0.1.58-13_amd64.deb`
- **WorkBuddy CN**（腾讯 CodeBuddy AI 编程工作台 · Linux 重打包版）`com.xydw.workbuddy_5.4.7-10_amd64.deb`

## 下载

统一发布在 GitHub Releases：

- <https://github.com/testerxydw/github-release-pkg-url/releases/tag/2026-09-02>

## 详细说明

各软件包的产品简介、转制原理、关键修复与安装方法见 [`github-release-pkg.md`](github-release-pkg.md)。

## 安装

```bash
sudo dpkg -i <包名>.deb
sudo apt-get install -f   # 缺少运行时依赖时自动补齐
```
