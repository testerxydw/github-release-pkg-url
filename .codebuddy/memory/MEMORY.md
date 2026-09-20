# 长期记忆 MEMORY

## 项目约定
- `github-release-pkg.txt` 采用**增量更新**：每次更新**追加新行**（不覆盖旧记录），每条带日期时间，格式为 `# YYYY-MM-DD HH:MM <说明>` 后跟下载链接；最新条目追加在文件末尾。
- 本仓库双远程：`origin`=gitee(xiyidaiwa/github-releaase-pkg-url)，`github`=github(testerxydw/github-releaase-pkg-url)。
- GitHub Release 统一发布在 tag `2026-09-02`（仓库 github-releaase-pkg-url）。
- 本环境访问 github 直连不稳定（git push 443 超时），无本地代理；推送 github 常需代理或重试。

## 记忆分库
- 本项目（codebuddy / github-releaase-pkg-url）记忆独立入库于此目录，与 **buddywork**（workbuddy-win-to-linux）项目记忆**分库管理、互不混用**（规则详见知识库「项目记忆分库规则」）。

## 仓库拓扑与实际 remote（2026-09-15 复核）
- 本地目录名 `github-release-pkg-url`（**不是**记忆里的旧名 `github-releaase-pkg-url`，注意拼写）。
- 远程：`origin` = gitee(`xiyidaiwa/github-release-pkg-url`)，`github` = github(`testerxydw/github-release-pkg-url`)；
  默认分支 **master**（不是 main）。CI 与发布都在 GitHub 侧，推送需 `git push github master`。
- GitHub Secrets：`PRIVATE_REPO_PAT`（读私有源码 + 本仓库写）、`WB_X_USER_ID`（WorkBuddy 灰度探测）；
  可选通知类 secrets 见 2026-09-14 记忆。

## 两个子项目共用一套流水线（2026-09-15 起）
| 子项目 | 探测 | tag | 构建 job | 产物 |
| --- | --- | --- | --- | --- |
| WorkBuddy CN | `check-update.sh`（匿名可探测） | `vX.Y.Z-1` | `build`（矩阵 x64/arm64） | `com.xydw.workbuddy_*` |
| JoyCode | `check-joycode.sh`（**需登录**） | `joycode-vX.Y.Z-1` | `build-joycode`（amd64） | `joycode_*` |
- `build-deb.yml` 内所有 job 按 tag 前缀用 `if` 分流；`update-index`/`notify` 用 `always()` + `needs.*.result` 判定，
  避免"另一个 job 被 skip 导致收尾 job 一并 skip"的坑。
- tag 前缀必须显式写进 `on.push.tags`（`v*` 不会匹配 `joycode-v*`）。
- `github-release-pkg.txt` 索引由 `update-index` 自动追加；资产名解析规则靠 `NAME_MAP`（已加 `joycode: JoyCode`）。
- 私有源码仓库 `testerxydw/workbuddy-linux` 现已包含两个子项目：`build.sh`（WorkBuddy）与
  `joycode-win-to-linux/build-joycode.sh`（JoyCode）。

## 上游探测的坑（JoyCode）
- JoyCode（京东云）的版本接口 `https://joycode-api.jd.com/api/saas/ideVersion/v1/version/joycoder-ide`
  与官网下载页**均需登录**，匿名返回 401；其 OSS（`joycode.s3.cn-north-1.jdcloud-oss.com`）禁止 List（403）。
- 故 JoyCode 探测采用「Secret `JOYCODE_COOKIE` 自动」+「workflow_dispatch 手动传 `joycode_exe_url`」双路径，
  安装包来源记在 `latest-joycode-exe.txt`（支持直链或 `release:owner/repo@tag/asset` 从私有仓库 Release 取）。
- 写 workflow 内嵌 `python3 -c '...'` 时，**python 代码里绝不能出现单引号**（会提前结束 bash 字符串），
  否则该 step 必失败；用双引号 + 转义替代（详见 2026-09-15 记忆，已修 notify 的两处历史遗留）。

## WorkBuddy 每版双包（2026-09-20 起，commit eb6fb25）
- `build` job 每次同时产出**两个包**（每架构各一）：
  - 默认**补丁版**：`com.xydw.workbuddy_<ver>_<arch>.deb` —— 打 A/B/C 三段 app.asar UI 补丁，UI 与 Windows 对齐
  - **原味版**：`com.xydw.workbuddy_<ver2>-nopatch_<arch>.deb` —— `build.sh --no-patch`，仅观感差异、功能一致
- 两次构建按 `deb-pkg/DEBIAN/control` 里的版本**自动错开 revision**（实测 `5.6.0-2` / `5.6.0-3`），两包可共存；
  补丁版先 `mv` 到 `/tmp/deb-patched/` 暂存，避免被第二次构建覆盖。
- `update-index` **无需改动**：资产名仍满足 `包名_版本_架构.deb` 解析规则（`-nopatch` 后缀不含下划线），
  会自动为两个包各追加一条索引，说明形如 `WorkBuddy CN 5.6.0-3-nopatch (amd64)`。
- Release 上传 glob 保持 `src/com.xydw.workbuddy_*_<debarch>.deb`，两个包都匹配。
- **手动验证法**：`gh workflow run build-deb.yml -R testerxydw/github-release-pkg-url --ref master`
  → 只跑 `build`（x64/arm64 并行），`build-joycode` / `update-index` / `notify` 全部 skip（它们要求 `refs/tags/`）
  → **只构建、不发布、不写索引**，安全。实测 run `35484664219` 全绿，约 3.5 分钟/架构。
- 手工发布"本地构建包"（如原味包）时，**tag 必须避开 `v*` / `joycode-v*`**（例：`nopatch-v5.6.0-2`），
  否则会触发 CI 构建并产出**同名资产**覆盖上传的文件。
