#!/bin/sh
# ============================================================
# git-ref-guard.sh —— 分支引用/索引健康护栏（只读，绝不写 .git）
# 用途：在"分支指针被清掉"造成不可逆损失之前把它拦下来。
# 用法：bash git-ref-guard.sh [--deep] [--max-added N]
# 退出码：0 健康 / 1 拦截（硬失败）/ 2 使用错误
#
# 设计原则：
#   - 只读：只用 rev-parse / ls-tree / status / worktree 等只读子命令。
#   - 判据可证伪：每条检查都有对应的阳性对照（见报告第 6 节）。
#   - 不用 head 截断：一律 wc -l 取总数（2026-09-16 的排查教训）。
# ============================================================

DEEP=0
MAX_ADDED=50
while [ $# -gt 0 ]; do
    case "$1" in
        --deep) DEEP=1 ;;
        --max-added) shift; MAX_ADDED="${1:-50}" ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "未知参数: $1" >&2; exit 2 ;;
    esac
    shift
done

rc=0
fail() { echo "[FAIL] $1"; rc=1; }
warn() { echo "[WARN] $1"; }
ok()   { echo "[ OK ] $1"; }

# ---- 0. 位置 ----
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "[FAIL] 当前不在 git 仓库内"; exit 1; }
GIT_DIR=$(git rev-parse --absolute-git-dir 2>/dev/null)
BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)
echo "仓库: $REPO_ROOT"
echo "gitdir: $GIT_DIR"
echo "分支: ${BRANCH:-<detached/unborn>}"

# ---- 1. HEAD 可解析（拦 "fatal: bad object HEAD" / unborn HEAD）----
if ! HEAD_SHA=$(git rev-parse --verify --quiet HEAD 2>/dev/null); then
    fail "HEAD 不可解析（unborn 或对象缺失）——这就是 2026-09-16 事故的核心症状"
elif ! git cat-file -e "$HEAD_SHA^{commit}" 2>/dev/null; then
    fail "HEAD 指向的提交对象 $HEAD_SHA 不存在（对象库已损，需从远端 fetch 恢复）"
else
    ok "HEAD 可解析: $HEAD_SHA"
fi

# ---- 2. 当前分支的 ref 本身存在且能解析 ----
if [ -n "$BRANCH" ]; then
    if ! REF_SHA=$(git rev-parse --verify --quiet "refs/heads/$BRANCH" 2>/dev/null); then
        fail "分支 refs/heads/$BRANCH 的引用不存在（指针已丢，提交对象通常还在）"
    else
        ok "ref refs/heads/$BRANCH 存在: $REF_SHA"
    fi
    # 嵌套 ref（分支名含 /）—— 本事故的特征形态
    case "$BRANCH" in
        */*)
            warn "当前分支名含 '/'，是嵌套 ref —— 2026-09-16 事故只发生在这类分支上"
            warn "所有 git 写操作请改到主 worktree（分支 main，顶层 ref）执行"
            ;;
    esac
fi

# ---- 3. 索引规模异常（拦 "整棵树被重新 add"）----
# 用 wc -l 取总数，绝不用 head（head 会把后面的几百行 A 截掉 → 误判索引干净）
if [ -n "$BRANCH" ] || [ "$HEAD_SHA" != "" ]; then
    TOTAL=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    ADDED=$(git status --porcelain 2>/dev/null | grep -c '^A' || true)
    MODIFIED=$(git status --porcelain 2>/dev/null | grep -c '^ M' || true)
    echo "索引规模: 总计 $TOTAL 条（新增 A $ADDED / 改动 M $MODIFIED）"
    if [ "$ADDED" -gt "$MAX_ADDED" ] 2>/dev/null; then
        fail "暂存区新增 $ADDED 个文件 > 阈值 $MAX_ADDED —— 极可能是 HEAD 变 unborn 后整棵树被重新 add，禁止提交"
    fi
fi

# ---- 4. HEAD 提交里出现无父 root commit（拦 "新提交变成 root commit"）----
if [ -n "$HEAD_SHA" ]; then
    PARENTS=$(git log -1 --format='%P' "$HEAD_SHA" 2>/dev/null | tr -d ' ')
    if [ -z "$PARENTS" ]; then
        # 全新仓库的首个提交本身就是 root commit，不能直接判失败 → 用 reflog 条数区分
        NREFL=$(git reflog 2>/dev/null | wc -l | tr -d ' ')
        if [ "${NREFL:-0}" -le 1 ] 2>/dev/null; then
            warn "HEAD 是 root commit，但 reflog 只有 $NREFL 条 —— 判定为全新仓库的首个提交，不拦截"
        else
            fail "HEAD 是无父的 root commit，且 reflog 有 $NREFL 条（历史上曾有父提交）—— 提交历史已断链（31dc567 型症状）"
        fi
    fi
fi

# ---- 5. worktree 注册与实际目录一致性 ----
PRUNABLE=$(git worktree list --porcelain 2>/dev/null | grep -c '^prunable' || true)
if [ "$PRUNABLE" -gt 0 ] 2>/dev/null; then
    warn "存在 $PRUNABLE 个 prunable worktree（工作目录已被外部删除，注册项残留）"
    git worktree list --porcelain 2>/dev/null | grep -B2 '^prunable' | sed 's/^/       /'
fi

# ---- 6. 嵌套 ref 是否有"顶层单名"备份（决定对象是否会被 gc 回收）----
if [ -n "$BRANCH" ]; then
    case "$BRANCH" in
        */*)
            if [ -n "$REF_SHA" ]; then
                BACKUP=$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null \
                         | grep -v '/' | while read -r b; do
                             [ "$(git rev-parse --verify --quiet "refs/heads/$b")" = "$REF_SHA" ] && echo "$b"
                         done | head -1)
                if [ -n "$BACKUP" ]; then
                    ok "已存在指向同一提交的顶层单名分支备份: $BACKUP（对象不会被 gc 回收）"
                else
                    warn "没有指向 $REF_SHA 的顶层单名分支做锚 —— 一旦嵌套 ref 再被清，提交将不可达，git gc --auto 可能真正删对象"
                    warn "   立即执行: git branch <单名备份> $REF_SHA"
                fi
            fi
            ;;
    esac
fi

# ---- 7. 深度检查（可选）----
if [ "$DEEP" -eq 1 ]; then
    echo "深度检查: git fsck --connectivity-only ..."
    if git fsck --connectivity-only --no-dangling 2>&1 | grep -v '^Checking' | grep -q .; then
        fail "git fsck 报告对象库问题（见上）"
    else
        ok "git fsck 连通性检查通过"
    fi
fi

echo "---------------------------------------------"
if [ "$rc" -eq 0 ]; then echo "RESULT: PASS（引用与索引健康）"; else echo "RESULT: FAIL（已拦截，禁止继续 git 写操作）"; fi
exit $rc
