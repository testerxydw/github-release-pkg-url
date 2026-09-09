#!/usr/bin/env bash
# ============================================================================
# WorkBuddy 更新探测器（公有 CI 仓库专用精简版）
#
# 与私有源码仓库 check-update.sh 的区别：
#   - 只维护本仓库的 latest-windows-exe.txt，不改动任何 RELEASE_NOTES.md
#   - 检测到新版本后，在【本仓库】打 tag 并推送，触发本仓库 build-deb.yml
#     （因此检出/推送必须用 PAT：GITHUB_TOKEN 推 tag 不会触发其它 workflow）
#
# 依赖：curl / git
# 用法：bash check-update.sh            # 探测 + 有更新则写文件/打 tag/推送
#       DRY_RUN=1 bash check-update.sh  # 只打印将要执行的动作，不落盘/不推送
# ============================================================================
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

API="https://copilot.tencent.com/v2/update"
PLATFORM="workbuddy-win32-x64-user"
URL_FILE="latest-windows-exe.txt"
DRY_RUN="${DRY_RUN:-0}"

log() { echo "[check-update] $*"; }
die() { echo "[check-update][错误] $*" >&2; exit 1; }

[[ -f "$URL_FILE" ]] || die "缺少 $URL_FILE"

# ---------- 1. 读取本仓库当前 Windows 版本 ----------
CUR_EXE=$(grep -oE 'WorkBuddy-win32-x64-user-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9a-f]+\.exe' "$URL_FILE" | head -1 || true)
CUR_FULL=$(echo "$CUR_EXE" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
[[ -n "$CUR_FULL" ]] || die "无法解析当前 Windows 版本（$URL_FILE）"
log "当前仓库 Windows 版本: $CUR_FULL"

# ---------- 2. 探测更新接口 ----------
FEED_URL="${API}?platform=${PLATFORM}&version=${CUR_FULL}"
log "探测更新接口: $FEED_URL"
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
if ! ver_gt "$NEW_FULL" "$CUR_FULL"; then
    log "接口版本($NEW_FULL)未高于当前($CUR_FULL) —— 无更新。"
    exit 0
fi

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
    log "[DRY_RUN] 将打 tag $NEW_TAG 并推送 main + tag"
    exit 0
fi

# ---------- 5. 落地：写版本记录 + 打 tag + 推送（触发本仓库 build-deb） ----------
printf '%s\n' "$NEW_URL" > "$URL_FILE"
log "已写入 $URL_FILE"

git add "$URL_FILE"
git commit -m "chore: 上游更新至 WorkBuddy ${NEW_FULL}" >/dev/null
git tag -a "$NEW_TAG" -m "WorkBuddy ${APP_V} Linux 打包 (${NEW_TAG})

基于上游 Windows 安装包转制:
  $(basename "${NEW_URL%%\?*}")
下载:
  ${NEW_URL}"
# 推送分支：分支名取 CI 提供的 GITHUB_REF_NAME
# （本仓库默认分支是 master 而非 main，不能写死 main，否则会误建 main 分支）
TARGET_BRANCH="${GITHUB_REF_NAME:-master}"
git push origin "HEAD:${TARGET_BRANCH}"
git push origin "$NEW_TAG"
log "已推送 ${TARGET_BRANCH} 与 tag $NEW_TAG —— 本仓库 build-deb 将自动构建并发布 Release。"
