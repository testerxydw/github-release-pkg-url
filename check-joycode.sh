#!/usr/bin/env bash
# ============================================================================
# JoyCode（京东云 JoyCode IDE）更新探测器 —— 公有 CI 仓库专用
#
# 与 check-update.sh（WorkBuddy）并行工作，互不干扰：
#   - 只维护本仓库的 latest-joycode-exe.txt
#   - 检测到新版本后，在【本仓库】打 tag joycode-vX.Y.Z-1 并推送，
#     触发本仓库 build-deb.yml 的 build-joycode job（必须用 PAT 推送，GITHUB_TOKEN 不触发 workflow）
#
# 三条探测路径（按优先级）：
#   ① 手动：JOYCODE_EXE_URL（workflow_dispatch 注入）→ 直接用给定地址与版本
#   ② 枚举（默认，无需任何凭据）：JoyCode 安装包地址是「按版本号拼接」的固定路径 ——
#        https://aichat.s3-ipv6.cn-north-1.jdcloud-oss.com/joycoder-ide/init/win32-x64/<版本>/JoyCodeSetup.exe
#      OSS 禁止 List（403）但允许匿名 GET/HEAD 具体对象，且不存在的版本返回 404，
#      因此按候选版本号逐个 HEAD 即可判定该版本是否已发布，取命中版本里的最大值即最新版。
#   ③ 接口（需登录态）：GET https://joycode-api.jd.com/api/saas/ideVersion/v1/version/joycoder-ide
#      匿名固定返回 {"code":401,"data":null,"msg":"账号未登录"}；配置 Secret JOYCODE_COOKIE 后可用。
#
# 依赖：curl / git / python3（仅接口路径用到）
# 用法：
#   bash check-joycode.sh                  # 枚举探测（默认，无需凭据）
#   DRY_RUN=1 bash check-joycode.sh        # 只打印将要执行的动作
#   JOYCODE_EXE_URL='https://.../X.exe' JOYCODE_VERSION=3.0.11 bash check-joycode.sh   # 手动指定
# 可调环境变量：
#   JOYCODE_URL_TPL    自定义地址模板（用 {V} 作版本占位），默认从记录 URL 推导或内置默认
#   JOYCODE_SCAN_PATCH 当前 minor 下向前扫描的 patch 数（默认 30）
#   JOYCODE_SCAN_MINOR 向前扫描的 minor 数（默认 5）
#   JOYCODE_SCAN_MAJOR 向前扫描的 major 数（默认 2）
#   JOYCODE_DEB_REV    deb 修订号（默认 1）
# ============================================================================
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

API="https://joycode-api.jd.com/api/saas/ideVersion/v1/version/joycoder-ide"
PLATFORM="win32-x64"
DEFAULT_TPL="https://aichat.s3-ipv6.cn-north-1.jdcloud-oss.com/joycoder-ide/init/win32-x64/{V}/JoyCodeSetup.exe"
URL_FILE="latest-joycode-exe.txt"
DRY_RUN="${DRY_RUN:-0}"
DEB_REV="${JOYCODE_DEB_REV:-1}"
SCAN_PATCH="${JOYCODE_SCAN_PATCH:-30}"
SCAN_MINOR="${JOYCODE_SCAN_MINOR:-5}"
SCAN_MAJOR="${JOYCODE_SCAN_MAJOR:-2}"
HTTP_TIMEOUT="${JOYCODE_HTTP_TIMEOUT:-10}"

log() { echo "[check-joycode] $*"; }
die() { echo "[check-joycode][错误] $*" >&2; exit 1; }

# 版本比较：ver_gt <new> <cur> —— new 严格大于 cur 返回 0
ver_gt() {
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

[[ -f "$URL_FILE" ]] || die "缺少 $URL_FILE"

# ---------- 1. 读取当前记录（URL 行 + `# version:` 注释行） ----------
CUR_URL=$(grep -v '^[[:space:]]*#' "$URL_FILE" | grep -m1 -oE 'https?://[^[:space:]]+' || true)
CUR_VER=$(grep -m1 -oE '^#[[:space:]]*version:[[:space:]]*[0-9][0-9.]*' "$URL_FILE" | grep -oE '[0-9][0-9.]*' || true)
if [[ -z "$CUR_VER" && -n "$CUR_URL" ]]; then
    CUR_VER=$(basename "${CUR_URL%%\?*}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
fi
log "当前记录: version=${CUR_VER:-（无）} url=${CUR_URL:-（无）}"

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
    log "路径①手动指定: version=$NEW_VER"
else
    # ---------- 3. 路径③：官方接口（需 Cookie，可选） ----------
    if [[ -n "${JOYCODE_COOKIE:-}" ]]; then
        LOGIN_Q=""
        [[ -n "${JOYCODE_X_USER_ID:-}" ]] && LOGIN_Q="&x-user-id=${JOYCODE_X_USER_ID}"
        FEED_URL="${API}?platform=${PLATFORM}&version=${CUR_VER:-0.0.0}${LOGIN_Q}"
        log "路径③接口探测（带登录态）: platform=$PLATFORM version=${CUR_VER:-0.0.0}"
        RESP=$(curl -s --max-time 25 -H "Cookie: ${JOYCODE_COOKIE}" \
                    -H 'Accept: application/json' "$FEED_URL" || true)
        if [[ -n "$RESP" ]]; then
            PARSED=$(printf '%s' "$RESP" | python3 -c '
import json, re, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
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
print(ver, url)
' || true)
            NEW_VER=$(echo "$PARSED" | awk '{print $1}')
            NEW_URL=$(echo "$PARSED" | awk '{print $2}')
            [[ -n "$NEW_VER" ]] && log "接口返回版本: $NEW_VER"
            [[ -z "$NEW_URL" ]] && NEW_URL=""
        else
            log "接口无响应（Cookie 可能已过期），改用枚举探测。"
        fi
    fi

    # ---------- 4. 路径②：OSS 路径枚举探测（默认，无需凭据） ----------
    if [[ -z "$NEW_VER" ]]; then
        URL_TPL="${JOYCODE_URL_TPL:-}"
        if [[ -z "$URL_TPL" && -n "$CUR_URL" && -n "$CUR_VER" ]]; then
            URL_TPL="${CUR_URL//$CUR_VER/{V}}"      # 从记录 URL 推导模板（仅替换路径中的版本段）
        fi
        [[ "$URL_TPL" == *"{V}"* ]] || URL_TPL="$DEFAULT_TPL"
        log "路径②枚举探测: 模板=$URL_TPL"

        BASE="${CUR_VER:-0.0.0}"
        IFS='.' read -r BM bm bp <<< "$BASE"
        BM=${BM:-0}; bm=${bm:-0}; bp=${bp:-0}

        cands=()
        for i in $(seq 1 "$SCAN_PATCH"); do cands+=("$BM.$bm.$((bp + i))"); done
        for k in $(seq 1 "$SCAN_MINOR"); do
            for j in 0 1 2; do cands+=("$BM.$((bm + k)).$j"); done
        done
        for k in $(seq 1 "$SCAN_MAJOR"); do cands+=("$((BM + k)).0.0"); done

        BEST=""
        HIT=0
        for v in "${cands[@]}"; do
            # 跳过不比当前新的候选
            ver_gt "$v" "$BASE" || continue
            code=$(curl -s -o /dev/null -I --max-time "$HTTP_TIMEOUT" -w '%{http_code}' "${URL_TPL//\{V\}/$v}" || echo 000)
            if [[ "$code" == "200" ]]; then
                log "  命中已发布版本: $v"
                HIT=$((HIT + 1))
                if [[ -z "$BEST" ]] || ver_gt "$v" "$BEST"; then BEST="$v"; fi
            fi
        done
        log "枚举完成：候选 ${#cands[@]} 个，命中 $HIT 个，最高=${BEST:-无}"

        if [[ -z "$BEST" ]]; then
            log "未枚举到比当前更新的版本 —— 视为无更新。"
            log "（若确认上游已发新版，可能是大版本跳跃或下载路径变更，"
            log "  可用 Actions 手动运行并填写 joycode_exe_url 指定安装包。）"
            exit 0
        fi
        NEW_VER="$BEST"
        NEW_URL="${URL_TPL//\{V\}/$BEST}"
    elif [[ -z "$NEW_URL" ]]; then
        # 接口给了版本但没给地址 → 用模板拼
        URL_TPL="${JOYCODE_URL_TPL:-$DEFAULT_TPL}"
        NEW_URL="${URL_TPL//\{V\}/$NEW_VER}"
        log "接口未返回地址，按模板拼接: $NEW_URL"
    fi
fi

# ---------- 5. 版本比较与去重 ----------
if [[ -n "$CUR_VER" ]] && ! ver_gt "$NEW_VER" "$CUR_VER"; then
    log "最新版本($NEW_VER)未高于当前记录($CUR_VER) —— 无更新。"
    exit 0
fi

TAG="joycode-v${NEW_VER}-${DEB_REV}"
log "发现新版本！version=$NEW_VER  tag=$TAG"
log "下载地址: $NEW_URL"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
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

# ---------- 6. 落地：写记录 + 打 tag + 推送（触发 build-joycode） ----------
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
