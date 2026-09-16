#!/usr/bin/env bash
# 推送当前分支到远端，并以「远端 sha == 本地 sha」为**唯一**成功判据。
#
# 为什么需要这个脚本（TD-028，2026-09-16 两次踩坑）：
#   1. `git push` 的退出码不可靠 —— 实测出现过「打印 PUSH_OK、但 rc 取到的是上一条命令
#      的残留值、远端根本没动」；而 `git push ... | tail` 更是恒 0（取的是 tail 的退出码）。
#   2. 本机出网走代理时，`git push` 常撞 `CONNECT tunnel failed, response 502`，
#      但**直连也不总是通** —— 实测交替重试的成功率明显高于单一模式。
# 因此：不信任退出码，只信任 `git ls-remote` 读回的远端 sha。
#
# 用法：
#   bash scripts/push-and-verify.sh            # 推送当前分支
#   bash scripts/push-and-verify.sh main       # 显式指定分支
#
# 退出码：0 = 已推送且远端已核验；1 = 重试耗尽仍未推送成功。

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

REMOTE_URL="https://github.com/zyejf/AutoHotkeydemo.git"
BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"
LOCAL="$(git rev-parse HEAD)"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-8}"

command -v gh >/dev/null 2>&1 || { echo "需要 gh（用于取 token）"; exit 1; }
TOKEN="$(gh auth token 2>/dev/null)"
[ -n "$TOKEN" ] || { echo "gh 未登录：先 gh auth login"; exit 1; }
PUSH_URL="https://x-access-token:${TOKEN}@github.com/zyejf/AutoHotkeydemo.git"

# 读远端 sha。查询本身也要绕开坏代理，否则「远端没这个 refs」会被误判成没推送。
remote_sha() {
  env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
    git ls-remote "$REMOTE_URL" "$BRANCH" 2>/dev/null | awk '{print $1}'
}

echo "分支=$BRANCH 本地=$(git rev-parse --short HEAD)"

for i in $(seq 1 "$MAX_ATTEMPTS"); do
  if [ $((i % 2)) -eq 1 ]; then
    # 直连：清掉全部代理变量
    env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy -u ALL_PROXY -u all_proxy \
      git -c credential.helper= push "$PUSH_URL" "$BRANCH" >/tmp/push-verify.log 2>&1
    MODE=direct
  else
    git -c credential.helper= push "$PUSH_URL" "$BRANCH" >/tmp/push-verify.log 2>&1
    MODE=proxy
  fi

  R="$(remote_sha)"
  if [ "$R" = "$LOCAL" ]; then
    echo "✅ 已推送并核验：远端 $BRANCH = ${R:0:8}（第 $i 次尝试，模式=$MODE）"
    echo "   下一步（TD-028 纪律：推送后必须查 CI 结论）："
    echo "   id=\$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId') && gh run watch \"\$id\""
    exit 0
  fi

  echo "尝试 $i/$MAX_ATTEMPTS 模式=$MODE 未成功（远端=${R:0:8}），8s 后重试…"
  tail -1 /tmp/push-verify.log
  sleep 8
done

echo "❌ ${MAX_ATTEMPTS} 次尝试后远端仍未更新到 ${LOCAL:0:8}。最后一次输出："
tail -3 /tmp/push-verify.log
exit 1
