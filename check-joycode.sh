#!/usr/bin/env bash
# ============================================================================
# JoyCode（京东云 JoyCode IDE）更新探测器 —— 公有 CI 仓库专用
#
# 与 check-update.sh（WorkBuddy）并行工作，互不干扰：
#   - 只维护本仓库的 latest-joycode-exe.txt
#   - 检测到新版本后，在【本仓库】打 tag joycode-vX.Y.Z-1 并推送，
#     触发本仓库 build-deb.yml 的 build-joycode job（必须用 PAT 推送，GITHUB_TOKEN 不触发 workflow）
#
# ⚠️ JoyCode 官方版本/下载接口需要登录态：
#      GET https://joycode-api.jd.com/api/saas/ideVersion/v1/version/joycoder-ide
#      匿名请求固定返回 {"code":401,"data":null,"msg":"账号未登录"}
#    因此探测分两条路径：
#      ① 自动：配置 Secret JOYCODE_COOKIE（浏览器登录 joycode.jd.com 后的 Cookie 串）→ 调官方接口
#      ② 手动：workflow_dispatch 传 joycode_exe_url（+ 可选 joycode_version）→ 跳过探测直接落地
#    未配置凭据时脚本安静退出，不影响定时任务。
#
# 依赖：curl / git / python3
# 用法：
#   bash check-joycode.sh                  # 自动探测（无凭据则退出）
#   DRY_RUN=1 bash check-joycode.sh        # 只打印将要执行的动作
#   JOYCODE_EXE_URL='https://.../X.exe' JOYCODE_VERSION=3.0.11 bash check-joycode.sh   # 手动指定
# ============================================================================
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

API="https://joycode-api.jd.com/api/saas/ideVersion/v1/version/joycoder-ide"
PLATFORM="win32-x64"
URL_FILE="latest-joycode-exe.txt"
DRY_RUN="${DRY_RUN:-0}"
DEB_REV="${JOYCODE_DEB_REV:-1}"

log() { echo "[check-joycode] $*"; }
die() { echo "[check-joycode][错误] $*" >&2; exit 1; }

[[ -f "$URL_FILE" ]] || die "缺少 $URL_FILE"

# ---------- 1. 读取当前记录（URL 行 + `# version:` 注释行） ----------
CUR_URL=$(grep -v '^[[:space:]]*#' "$URL_FILE" | grep -m1 -oE 'https?://[^[:space:]]+' || true)
CUR_VER=$(grep -m1 -oE '^#[[:space:]]*version:[[:space:]]*[0-9][0-9.]*' "$URL_FILE" | grep -oE '[0-9][0-9.]*' || true)
log "当前记录: version=${CUR_VER:-（无）} url=${CUR_URL:-（无）}"

# 从文件名兜底解析版本（如 JoyCodeIDE-3.0.10-xxxx.exe）
if [[ -z "$CUR_VER" && -n "$CUR_URL" ]]; then
    CUR_VER=$(basename "${CUR_URL%%\?*}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    [[ -n "$CUR_VER" ]] && log "从 URL 解析出当前版本: $CUR_VER"
fi

NEW_VER=""
NEW_URL=""

# ---------- 2. 路径①：手动指定（workflow_dispatch 注入） ----------
if [[ -n "${JOYCODE_EXE_URL:-}" ]]; then
    NEW_URL="$JOYCODE_EXE_URL"
    NEW_VER="${JOYCODE_VERSION:-}"
    if [[ -z "$NEW_VER" ]]; then
        NEW_VER=$(basename "${NEW_URL%%\?*}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    fi
    [[ -n "$NEW_VER" ]] || die "手动指定了 JOYCODE_EXE_URL，但无法确定版本号：请同时提供 JOYCODE_VERSION"
    log "手动指定安装包: version=$NEW_VER"
else
    # ---------- 3. 路径②：官方接口探测（需登录态） ----------
    if [[ -z "${JOYCODE_COOKIE:-}" ]]; then
        log "未配置 JOYCODE_COOKIE，且未手动指定安装包 —— 跳过自动探测。"
        log "提示：JoyCode 下载接口需登录；可在仓库 Secrets 配置 JOYCODE_COOKIE，"
        log "      或在 Actions 页面手动运行本 workflow 并填写 joycode_exe_url。"
        exit 0
    fi

    LOGIN_Q=""
    [[ -n "${JOYCODE_X_USER_ID:-}" ]] && LOGIN_Q="&x-user-id=${JOYCODE_X_USER_ID}"
    FEED_URL="${API}?platform=${PLATFORM}&version=${CUR_VER:-0.0.0}${LOGIN_Q}"
    log "探测官方接口（带登录态）: platform=$PLATFORM version=${CUR_VER:-0.0.0}"
    RESP=$(curl -s --max-time 25 -H "Cookie: ${JOYCODE_COOKIE}" \
                -H 'Accept: application/json' "$FEED_URL" || true)
    if [[ -z "$RESP" ]]; then
        log "接口无响应，视为无更新。"
        exit 0
    fi

    # 解析：递归查找版本号与 .exe 下载地址（兼容字段名差异，首次可看日志校正）
    PARSED=$(printf '%s' "$RESP" | python3 -c '
import json, re, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print("", "", raw[:400].replace("\n", " "))
    sys.exit(0)

def walk(o, prefix=""):
    if isinstance(o, dict):
        for k, v in o.items():
            yield from walk(v, prefix + "/" + str(k))
    elif isinstance(o, list):
        for v in o:
            yield from walk(v, prefix)
    else:
        yield prefix, o

ver = url = ""
for path, v in walk(d):
    if not isinstance(v, str):
        continue
    s = v.strip()
    low = path.lower()
    if not url and s.lower().startswith("http") and ".exe" in s.lower():
        url = s
    if not ver:
        if "version" in low and re.search(r"\d+\.\d+", s):
            m = re.search(r"(\d+\.\d+(?:\.\d+){0,2})", s)
            if m:
                ver = m.group(1)
        elif re.fullmatch(r"\d+\.\d+\.\d+(\.\d+)?", s):
            ver = s
print(ver, url, "")
' || true)
    NEW_VER=$(echo "$PARSED" | awk '{print $1}')
    NEW_URL=$(echo "$PARSED" | awk '{print $2}')
    if [[ -z "$NEW_VER" || -z "$NEW_URL" ]]; then
        log "接口响应中未找到 版本/下载地址 字段，视为无更新。"
        log "原始响应（截断）: $(printf '%s' "$RESP" | head -c 300)"
        exit 0
    fi
    log "接口返回最新版本: $NEW_VER"
fi

# ---------- 4. 版本比较（逐段整数比较） ----------
ver_gt() {  # ver_gt <new> <cur> —— new 严格大于 cur 返回 0
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
if [[ -n "$CUR_VER" ]] && ! ver_gt "$NEW_VER" "$CUR_VER"; then
    log "新版本($NEW_VER)未高于当前记录($CUR_VER) —— 无更新。"
    exit 0
fi

# ---------- 5. 计算 tag（joycode- 前缀，与 WorkBuddy 的 v* 区分） ----------
TAG="joycode-v${NEW_VER}-${DEB_REV}"
log "发现新版本！version=$NEW_VER  tag=$TAG"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    log "tag $TAG 已存在，跳过（避免重复打包）。"
    exit 0
fi

if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY_RUN] 将写入 $URL_FILE:"
    log "[DRY_RUN]   # version: $NEW_VER"
    log "[DRY_RUN]   $NEW_URL"
    log "[DRY_RUN] 将打 tag $TAG 并推送 ${GITHUB_REF_NAME:-master} + tag"
    exit 0
fi

# ---------- 6. 落地：写记录 + 打 tag + 推送（触发 build-deb.yml 的 build-joycode） ----------
{
    printf '# JoyCode Windows 安装包直链\n'
    printf '# version: %s\n' "$NEW_VER"
    printf '%s\n' "$NEW_URL"
} > "$URL_FILE"
log "已写入 $URL_FILE"

git add "$URL_FILE"
git commit -m "chore: 上游更新至 JoyCode ${NEW_VER}" >/dev/null
git tag -a "$TAG" -m "JoyCode ${NEW_VER} Linux 打包 (${TAG})

基于上游 Windows 安装包转制（VS Code 1.98.2 fork / Electron 35.6.0）:
  $(basename "${NEW_URL%%\?*}")
下载:
  ${NEW_URL}"
TARGET_BRANCH="${GITHUB_REF_NAME:-master}"
git push origin "HEAD:${TARGET_BRANCH}"
git push origin "$TAG"
log "已推送 ${TARGET_BRANCH} 与 tag $TAG —— build-deb.yml 将构建 JoyCode deb 并发布 Release。"
