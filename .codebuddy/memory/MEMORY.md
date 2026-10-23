# 长期记忆 MEMORY

## 项目约定
- `github-release-pkg.txt` 采用**增量更新**：每次更新**追加新行**（不覆盖旧记录），每条带日期时间，格式为 `# YYYY-MM-DD HH:MM <说明>` 后跟下载链接；最新条目追加在文件末尾。
- 本仓库远程（2026-10-23 复核，**旧记忆的"gitee+github 双远程"已不成立**）：仅 `origin` = `git@github.com:testerxydw/github-release-pkg-url.git`（SSH），分支 `master`，推送 `git push origin master`。
- 私有源码仓库 `testerxydw/workbuddy-linux` 同样仅 `origin` = `git@github.com:testerxydw/workbuddy-linux.git`（SSH）；SSH 22 端口可用（HTTPS 443 反而不稳）。
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

## WorkBuddy 每版双包（2026-09-20 起，commit eb6fb25）—— ⚠️ 已于 2026-10-23 废弃，见下一节
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

## WorkBuddy 只出原味版单包（2026-10-23 起，取代上一节的双包方案）
- **决策**：不再打前端补丁（标题栏对齐 Windows 那套 app.asar 补丁），每版每架构**只出一个原味包**。
- `build.sh`（私有仓库 `testerxydw/workbuddy-linux` · `win-to-linux` 分支）：`DO_PATCH` 默认由 `1` 改为 `0`；
  `--patch` / `--no-patch` 开关与 `stage_patch_app` 函数**保留**（仅作对比用），主流程 `if [[ DO_PATCH -eq 1 ]]` 守卫不变。
  **未引入任何包名/路径后缀机制** —— 产物即 `com.xydw.workbuddy_<版本>_<架构>.deb`（如 `com.xydw.workbuddy_5.9.0-1_amd64.deb`），
  安装路径 `/opt/workbuddy`、入口 `workbuddy`，与 2026-09 之前的形态一致。
- `build-deb.yml`：`build` job 的双构建合并为**一次** `bash build.sh --arch X --no-install`（不传 patch 参数，靠新默认）；
  删除补丁版 step、`/tmp/deb-patched` 暂存与 `-nopatch` 改名；发布 glob 保持 `src/com.xydw.workbuddy_*_<debarch>.deb`。
- 版本号逻辑**未动**（仍按 exe 主版本变化归 1 / 同版本 revision+1），注意别再把"原味版沿用版本号"的分支加回来
  （那只在"先构建补丁版再构建原味版"的双包场景下才成立，单包场景会导致版本号永不递增）。
- `update-index` / `NAME_MAP` **无需改动**（不再有 `workbuddy-nopatch` 资产）；历史索引条目保留不改。
- 已本地验证：默认构建不执行 `阶段 3.2/5`，单产物 `com.xydw.workbuddy_5.9.0-1_amd64.deb`，
  `Package=com.xydw.workbuddy`、`Version=5.9.0-1`，bin/desktop/图标/postinst 全部为标准命名无 `-nopatch` 残留。

## 分支统一：win-to-linux 已合并入 main，CI 全走 main（2026-10-23）
- **最终方案 = hybrid（win JS 层 + 官方 Linux deb 基座）+ main 上的改进**。用户否决了 main 上
  `b17cc2d`「移除 win 路线、纯官方 Linux deb 整体转制」的方向，明确要 win+linux 基座方案。
- 做法：**没有 rebase**（rebase 会把 `b17cc2d` 大重构带到 hybrid 上且需 force push 改写 main 历史），
  而是 `git merge --no-ff win-to-linux` 进 main，冲突解决策略：
  - `build.sh` / `deb-pkg/DEBIAN/control` → 取 **win-to-linux** 版（hybrid 主体；control Version 5.8.3-4）
  - `.gitignore` → 取 **main** 版（更完整），再追加 `.linux-base/`（hybrid 的基座解包目录，必须忽略）
- 从 main 移植进 hybrid 的两项改进（commit `86c3b32`）：
  1. **CPU 限核**：`--limit-cpu N` / `--limit-cpu=N`（默认 50% 核数，taskset re-exec 自身）；
     新增 `ORIG_ARGS`/`LIMIT_CPU`/`apply_cpu_limit`；`total` 用 `nproc`（考虑 cgroup/affinity，
     容器里 `/proc/cpuinfo` 是宿主机核数会算错）
  2. **官方基座 deb 架构守卫**：`stage_fetch_linux_base` 里校验 `dpkg-deb -f Architecture` 与目标
     `DEB_ARCH` 一致，避免把 x64 内容打进 arm64 包（与 CI 侧守卫双保险）
- `build-deb.yml`：build job 源码检出 `ref: win-to-linux` → **`main`**（与 build-joycode 统一）；
  **win 安装包下载步骤保留**（hybrid 的 JS 层来源，不能删）。
- 合并后 main 的 build.sh 默认值：`DO_SLIM=1`（hybrid 既有设计，未采纳 main 的"默认关闭精简"）、
  `DO_PATCH=0`（不打前端补丁）、`LIMIT_CPU=0`（即默认 50%）。
- ⚠️ 本地 shell 的 affinity 可能是宿主机的 0-7 而 `nproc` 受 cgroup 限制，验证限核时别被"看起来没限"骗了。
