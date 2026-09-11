# GitHub Release 安装包说明

本目录记录了以下 GitHub Release 发布的 `.deb` 安装包及其简要介绍。

---

## 1. WorkBuddy CN（腾讯 CodeBuddy AI 编程工作台 · Linux 重打包版）

- **包名**：`com.xydw.workbuddy`
- **架构**：`amd64`
- **适用系统**：Deepin 23 / UOS v25 / Debian 12+（amd64）
- **产品**：腾讯 CodeBuddy 的 AI 编程工作台（`codebuddy` / `cbc-prewarm`，UI 为 Electron 工作台）

### 产品简介

**WorkBuddy** 是腾讯 **CodeBuddy** 的 AI 编程工作台产品，提供 AI Agent、智能编程辅助、工作台多模态创作等能力。官方仅发布 Windows / macOS 安装包，**无官方 Linux 版**。

本 `.deb` 包为**非官方重打包版**：拆解官方 **Windows NSIS 安装包**（`WorkBuddy-win32-x64-user-5.4.7.exe`），保留跨平台的 JS 资源层（`app.asar` / `app.asar.unpacked`），替换为 Linux 平台的 Electron 运行时与原生二进制后重新打包，使其可在 Deepin / UOS / Debian 系 Linux 上运行。仅供学习交流使用。

### 转制原理

| 组件 | 来源 | 作用 |
| --- | --- | --- |
| `app.asar` + `app.asar.unpacked` | 官方 **Windows** 安装包 | 应用 JS 层、UI、内置插件、CLI 代理 |
| Electron **39.2.7** Linux x64 运行时 | Electron 官方/镜像下载 | Chromium 运行时、主进程二进制（ELF） |
| 顶层资源（`*.pak`/`icudtl.dat`/`snapshot_blob.bin`） | Windows 安装包 | Chromium 资源文件（跨平台共用） |
| Linux 原生 `.node`/`.so` 模块 | Windows 包内置 + 重编译 | 终端、koffi、sqlite 等原生能力 |

### 已落地的关键修复

1. **Electron 版本锁定 39.2.7**：Windows 包内置 Linux 原生模块的 ABI 与 Electron 39 对齐；若误用 37 会导致 `better-sqlite3` ABI 不匹配、daemon 子进程崩溃、页面空白。
2. **重编译 `better-sqlite3@12.8.0`**：target=39.2.7，覆盖 `app.asar.unpacked` 内的 `.node`，并补齐 `bindings` / `file-uri-to-path`。
3. **标题栏自绘**：`--title-bar-style=custom` + main.js `titleBarOverlay` 守卫，避免 Linux 下标题栏白块/丢失。
4. **沙箱回退**：无 root 或 `chrome-sandbox` 未 setuid 时，启动脚本自动追加 `--no-sandbox`。
5. **补齐运行时依赖**：复制 `chrome_crashpad_handler` 避免启动 FATAL，`ulimit -n 65535` 提高文件描述符上限。
6. **Windows/macOS 专属模块安全降级**：`qimei-node` / `turing-sdk` / `wechat-copydata-decoder` 等按代码逻辑降级，不影响主流程。

### 安装与运行

```bash
sudo dpkg -i com.xydw.workbuddy_*.deb
sudo apt-get install -f   # 若提示缺少运行时依赖，自动补齐
```

- 应用菜单搜索 **WorkBuddy** 并点击；
- 或终端执行 `workbuddy`（软链至 `/usr/bin/workbuddy`，指向 `/opt/workbuddy/workbuddy`）。

### 版本历史

| 版本 | 安装包 | 下载地址 |
| --- | --- | --- |
| `5.5.6-1` | `com.xydw.workbuddy_5.5.6-1_amd64.deb` | <https://github.com/testerxydw/github-release-pkg-url/releases/download/v5.5.6-1/com.xydw.workbuddy_5.5.6-1_amd64.deb> |
| `5.4.7-10` | `com.xydw.workbuddy_5.4.7-10_amd64.deb` | <https://github.com/testerxydw/github-release-pkg-url/releases/download/2026-09-02/com.xydw.workbuddy_5.4.7-10_amd64.deb> |

---

## 2. Trae SOLO 国内版（字节跳动 AI 原生 IDE）

- **包名**：`trae-solo-cn`
- **版本**：`0.1.63-3`
- **架构**：`amd64`
- **安装包**：`trae-solo-cn_0.1.63-3_amd64.deb`
- **下载地址**：<https://github.com/testerxydw/github-release-pkg-url/releases/download/traework/trae-solo-cn_0.1.63-3_amd64.deb>

### 产品简介

**Trae SOLO** 是字节跳动推出的 **AI 原生集成开发环境（IDE）** 中的独立工作台形态，定位为"AI 主导的自动驾驶式开发工具"。工程师只需用自然语言描述需求，AI 即可自主完成需求拆解、代码生成、运行验证、Bug 修复、测试与部署等完整开发流程，工程师只需确认结果。

国内版（`-cn`）默认使用"豆包"系列模型，可切换至 DeepSeek 等国内模型，并针对中文技术术语做了深度适配。

### 主要功能

- **自然语言秒变可运行代码**：输入中文指令直接生成完整代码，无需手动查 API 文档
- **Builder 模式**：描述需求即可端到端生成完整项目（前后端、依赖清单、可运行原型）
- **Chat 模式**：结合项目上下文的代码级问答、Bug 定位与修复建议
- **SOLO 模式**：输入需求，AI 自主完成 PRD → 编码 → 测试 → 部署全流程
- **多模态输入**：支持文本、语音、截图、设计稿、PRD 文档等
- **规则引擎**：通过 `.trae/rules` 固化团队代码规范，AI 生成代码自动合规
- **内置工具链**：终端、Webview 预览、数据处理、SQL 生成、Excel 处理等开箱即用
- **隐私与安全**：支持隐私模式与沙箱运行，控制数据使用范围

### 三种协作模式

| 模式 | 定位 | 典型场景 |
| --- | --- | --- |
| **Chat** | 对话式助手，AI 给建议、人工决策 | 代码解释、局部优化、技术答疑 |
| **Builder** | 项目构建者，快速搭建框架 | 初始化项目结构、原型开发 |
| **SOLO** | 全流程 AI 工程师，自主执行 | 复杂功能开发、系统性 Bug 修复、从零构建应用 |

---

## 3. Navicat Premium Lite（Navicat 免费版数据库管理工具 · deepin 规范重打包版）

- **包名**：`com.navicat.premiumlite`
- **版本**：`17.3.10-2`
- **架构**：`amd64`
- **安装包**：`com.navicat.premiumlite_17.3.10-2_amd64.deb`
- **适用系统**：Deepin 23 / UOS v25 / Debian 12+（amd64）
- **上游**：官方 Navicat Premium Lite 17 Linux AppImage
- **下载地址**：<https://github.com/testerxydw/github-release-pkg-url/releases/download/2026-09-02/com.navicat.premiumlite_17.3.10-2_amd64.deb>

### 产品简介

**Navicat Premium Lite** 是 Navicat 官方推出的**免费版**数据库管理与开发工具，可从单一应用同时连接 MySQL、MariaDB、PostgreSQL、SQLite、SQL Server、Oracle、Snowflake、Redis 等多种数据库平台，提供查询、数据编辑、数据传输等核心功能。官方 Linux 版以 **AppImage** 格式发布。

本 `.deb` 包为**非官方重打包版**：将官方 AppImage 按 **deepin 应用打包规范**（`/opt/apps` 结构）重打包，安装后自动接入系统应用菜单，并兼容非 deepin 桌面环境。仅供学习交流使用。

### 打包要点与关键修复

| 项 | 说明 |
| --- | --- |
| 打包结构 | deepin 规范 `/opt/apps/com.navicat.premiumlite/`，AppImage 载荷约 711M，自包含加载 |
| 桌面/图标 | 软链至标准 XDG 路径，兼容非 deepin 桌面环境 |
| 启动脚本 | `cd` 到应用根目录（对齐官方 AppRun），修复相对路径 `dlopen` 导致的驱动库加载失败 |
| 退出看门狗 | `xprop -spy` 事件驱动（零轮询）：窗口全部关闭而进程未退出时，宽限 10 秒后 TERM，仍不退则 KILL；正常退出零动作，无 `xprop` 环境自动退化为官方行为 |
| postinst | 仅做桌面/图标软链，不再向 `/usr/lib` 复制库文件（省约 240M） |

### 安装与运行

```bash
sudo dpkg -i com.navicat.premiumlite_*.deb
sudo apt-get install -f   # 若提示缺少运行时依赖，自动补齐
```

- 应用菜单搜索 **Navicat Premium Lite**；
- 包内更新说明：`cat /usr/share/doc/com.navicat.premiumlite/changelog`

### 版本历史

| 版本 | 发布日期 | 下载地址 |
| --- | --- | --- |
| `17.3.10-2` | 2026-09-11 | <https://github.com/testerxydw/github-release-pkg-url/releases/download/2026-09-02/com.navicat.premiumlite_17.3.10-2_amd64.deb> |
| `17.3.10-1` | 2026-09-10 | 首次按 deepin 规范打包（未单独发布，已被 `-2` 取代） |

---

## 备注

- 本文件为对下载地址的整理与说明，原始下载链接见同目录下的 `github-release-pkg.txt`。
- 三个安装包均为 `amd64` 架构的 `.deb` 格式，适用于 Debian / Ubuntu / deepin / UOS 等系统，可通过 `sudo dpkg -i <包名>.deb` 安装。