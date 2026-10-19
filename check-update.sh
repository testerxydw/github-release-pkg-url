#!/usr/bin/env bash
# ============================================================================
# WorkBuddy 更新探测器（公有 CI 仓库专用精简版）· win 通道 + 混合构建
#
# 与旧版的区别（2026-10 混合构建改造）：
#   - 探测通道从【官方 Linux deb】改为【Windows 安装包】（platform=workbuddy-win32-x64-user）：
#     win 通道新版发布最早、无「推荐版挡板」，linux deb 仅作混合构建的基座来源。
#   - 打包方式：私有仓库 win-to-linux 分支 build.sh（--base hybrid 默认）——
#     win 5.8.3 JS 层 + 官方 Linux deb 腾讯定制基座（含 workbuddyStorage 定制 API）。
#   - 版本基准：latest-windows-exe.txt（win 安装包直链，本脚本维护）
#   - 基座来源：latest-workbuddy-deb.txt（官方 Linux deb 直链，长期固定即可，
#     仅作基座；不再驱动版本比较/打 tag）
#
# 检测到 win 新版后，在【本仓库】打 tag 并推送，触发本仓库 build-deb.yml
# （检出/推送必须用 PAT：GITHUB_TOKEN 推 tag 不会触发其它 workflow）
#
# 依赖：curl / git
# 用法：bash check-update.sh                        # 探测(接口+直链监控) + 有更新则写文件/打 tag/推送
#       bash check-update.sh --url <直链>            # 直链模式：录入人工/社区发现的新版直链(校验可达+解析版本+写latest+打tag)
#       bash check-update.sh --url <直链> --force    # 强制录入(即使版本不高于当前，用于修正/重录)
#       DRY_RUN=1 bash check-update.sh               # 只打印将要执行的动作，不落盘/不推送
#
# 灰度探测（可选，默认匿名只探测 GA 版）：
#   接口 v2/update 按 x-user-id 做灰度分桶，带真实 userId 才能看到该账号被灰度到的版本。
#   userId 来源：环境变量 WB_X_USER_ID（CI 用 repo secret 注入）
# ============================================================================
set -uo pipefail

# ---------- 0. 参数解析 ----------
URL_OVERRIDE=""; FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)   URL_OVERRIDE="$2"; shift 2;;
    --force) FORCE=1; shift;;
    *) shift;;
  esac
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

API="https://copilot.tencent.com/v2/update"
PLATFORM="workbuddy-win32-x64-user"
URL_FILE="latest-windows-exe.txt"          # win 安装包直链（版本基准，本脚本维护）
BASE_FILE="latest-workbuddy-deb.txt"       # 官方 Linux deb 直链（hybrid 基座，仅构建用）
DRY_RUN="${DRY_RUN:-0}"

log() { echo "[check-update] $*"; }
die() { echo "[check-update][错误] $*" >&2; exit 1; }

[[ -f "$URL_FILE" ]] || die "缺少 $URL_FILE（win 安装包直链，首次需用 --url 录入或手工写入）"
[[ -f "$BASE_FILE" ]] || log "提示：缺少 $BASE_FILE（hybrid 基座直链），构建阶段将无法下载官方基座"

# ---------- 1. 读取本仓库当前 Windows 版本 ----------
CUR_EXE=$(grep -oE 'WorkBuddy-win32-x64-user-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9a-f]+\.exe' "$URL_FILE" | head -1 || true)
CUR_FULL=$(echo "$CUR_EXE" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
[[ -n "$CUR_FULL" ]] || die "无法解析当前 Windows 版本（$URL_FILE）"
log "当前仓库 Windows 版本: $CUR_FULL"

# ---------- 1.2 下载站直链可达性监控 ----------
# 下载站（download.codebuddy.cn）无目录列举、无 latest 别名，文件名必须带精确 commit hash，
# 故仅校验「当前记录直链是否仍可访问」，不可达时告警但不自动改写。
CUR_URL=$(head -1 "$URL_FILE" | tr -d '[:space:]')
# 用 Range 头只取 1 字节，避免下载整个安装包导致超时；接受 200/206 视为可达
HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -r 0-0 "$CUR_URL" 2>/dev/null)
HTTP="${HTTP:-000}"
if [[ "$HTTP" == "200" || "$HTTP" == "206" ]]; then
    log "当前下载站直链可达 (HTTP $HTTP)。"
else
    log "警告——当前直链 HTTP=$HTTP（不可达/失效），请人工核查 $URL_FILE；脚本不自动改写。"
fi

# ---------- 1.5 解析登录态（灰度 cohort 探测用） ----------
WB_X_USER_ID="${WB_X_USER_ID:-}"
AUTH_Q=""
[[ -n "$WB_X_USER_ID" ]] && AUTH_Q="${AUTH_Q}&x-user-id=${WB_X_USER_ID}"
log "登录态: $([[ -n "$WB_X_USER_ID" ]] && echo "已带 x-user-id（灰度探测）" || echo "匿名（仅 GA 版）")"

# ---------- 2. 探测更新（直链模式 / 接口模式） ----------
if [[ -n "$URL_OVERRIDE" ]]; then
    # 直链模式（源C）：人工/社区发现的新版直链。校验可达 + 解析版本，跳过接口探测。
    NEW_URL="$URL_OVERRIDE"
    NEW_EXE="$(basename "${NEW_URL%%\?*}")"
    NEW_FULL="$(echo "$NEW_EXE" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)"
    [[ -n "$NEW_FULL" ]] || die "无法从直链解析版本号: $NEW_URL"
    HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 -r 0-0 "$NEW_URL" 2>/dev/null)
    HTTP="${HTTP:-000}"
    if [[ "$HTTP" != "200" && "$HTTP" != "206" ]]; then
        die "直链不可达 (HTTP $HTTP)，拒绝录入: $NEW_URL"
    fi
    log "直链模式：录入用户直链 版本=$NEW_FULL 可达性OK"
else
    # 接口模式（源A）：win 通道 v2/update 探测（新版发布最早，无 linux 通道推荐版挡板）
    FEED_URL="${API}?platform=${PLATFORM}&version=${CUR_FULL}${AUTH_Q}"
    if [[ -n "$WB_X_USER_ID" ]]; then
        MASKED="${WB_X_USER_ID:0:8}***"
        log "探测更新接口（带登录态）: ${API}?platform=${PLATFORM}&version=${CUR_FULL}&x-user-id=${MASKED}"
    else
        log "探测更新接口（匿名）: $FEED_URL"
    fi
    RESP=$(curl -s --max-time 20 "$FEED_URL" || true)
    if [[ -z "$RESP" || "$RESP" == "{}" || "$RESP" == "[]" ]]; then
        log "接口返回空 —— 当前已是最新，无需更新。"
        exit 0
    fi
    NEW_FULL=$(echo "$RESP" | grep -oE '"version":"[0-9][0-9.]*"' | head -1 | sed -E 's/"version":"//; s/"//' || true)
    NEW_URL=$( echo "$RESP" | grep -oE '"url":"https?://[^"]+"'     | head -1 | sed -E 's/"url":"//; s/"//' || true)
    [[ -n "$NEW_FULL" && -n "$NEW_URL" ]] || {
        log "接口返回缺少 version/url 字段，视为无更新。原始响应: $RESP"
        exit 0
    }
    log "接口返回最新版本: $NEW_FULL"
fi

# ---------- 3. 版本比较（4 段整数，逐段比较） ----------
ver_gt() {  # ver_gt <new> <cur> —— new 严格大于 cur 时返回 0
    local IFS='.'
    read -ra a <<< "$1"; read -ra b <<< "$2"
    local n=${#a[@]} m=${#b[@]} i
    for (( i=0; i < (n>m?n:m); i++ )); do
        local x=${a[i]:-0} y=${b[i]:-0}
        (( x > y )) && return 0
        (( x < y )) && return 1
    done
    return 1
}
if [[ "$FORCE" != "1" ]] && ! ver_gt "$NEW_FULL" "$CUR_FULL"; then
    log "版本($NEW_FULL)未高于当前($CUR_FULL) —— 无更新（直链模式可用 --force 强制录入）。"
    exit 0
fi
[[ "$FORCE" == "1" ]] && log "已用 --force，强制录入 $NEW_FULL（覆盖当前 $CUR_FULL）。"

# ---------- 4. 有更新：计算版本与 tag ----------
APP_V="$(echo "$NEW_FULL" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')"
DEB_REV=1
NEW_TAG="v${APP_V}-${DEB_REV}"
log "发现新版本！app=$APP_V  tag=$NEW_TAG"

# 已存在该 tag 则跳过（幂等）
if git rev-parse -q --verify "refs/tags/$NEW_TAG" >/dev/null; then
    log "tag $NEW_TAG 已存在，跳过（避免重复）。"
    exit 0
fi

if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY_RUN] 将写入 $URL_FILE: $NEW_URL"
    log "[DRY_RUN] 将打 tag $NEW_TAG 并推送 ${GITHUB_REF_NAME:-master} + tag"
    exit 0
fi

# ---------- 5. 落地：写版本记录 + 打 tag + 推送（触发本仓库 build-deb） ----------
printf '%s\n' "$NEW_URL" > "$URL_FILE"
log "已写入 $URL_FILE"

git add "$URL_FILE"
git commit -m "chore: 上游更新至 WorkBuddy ${NEW_FULL} (win 通道)" >/dev/null
git tag -a "$NEW_TAG" -m "WorkBuddy ${APP_V} Linux 打包 (${NEW_TAG})

基于上游 Windows 安装包 JS 层 + 官方 Linux deb 定制基座（hybrid 混合构建）:
  win: $(basename "${NEW_URL%%\?*}")
  win 下载: ${NEW_URL}
  基座: $(head -1 "$BASE_FILE" 2>/dev/null | tr -d '[:space:]')"
# 推送分支：分支名取 CI 提供的 GITHUB_REF_NAME
# （本仓库默认分支是 master 而非 main，不能写死 main，否则会误建 main 分支）
TARGET_BRANCH="${GITHUB_REF_NAME:-master}"
git push origin "HEAD:${TARGET_BRANCH}"
# 若配置了 github remote（本地调试场景：origin 为 Gitee 镜像、GitHub Actions 跑在
# github remote 仓库），需同步推送才能触发 build-deb；CI 内无此 remote 自动跳过。
if git remote get-url github >/dev/null 2>&1; then
    git push github "HEAD:${TARGET_BRANCH}" || true
    git push github "$NEW_TAG" || true
fi
git push origin "$NEW_TAG"
log "已推送 ${TARGET_BRANCH} 与 tag $NEW_TAG —— 本仓库 build-deb 将自动构建并发布 Release。"
