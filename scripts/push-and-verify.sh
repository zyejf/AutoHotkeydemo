#!/usr/bin/env bash
# 推送当前分支到远端，以「远端 sha == 本地 sha」核验推送，随后核查 CI 结论。
#
# 为什么需要这个脚本（TD-028）：
#   1. `git push` 的退出码不可靠 —— 实测出现过「打印 PUSH_OK、但 rc 取到的是上一条命令
#      的残留值、远端根本没动」；而 `git push ... | tail` 更是恒 0（取的是 tail 的退出码）。
#   2. 本机出网走代理时，`git push` 常撞 `CONNECT tunnel failed, response 502`，
#      但**直连也不总是通** —— 实测交替重试的成功率明显高于单一模式。
#      （2026-09-17 实测过一次网络中断：连续 20 次重试全失败，过几分钟再试即成功。）
#   3. **推送成功 ≠ 验证通过**。本地四闸门绿不代表 CI 绿（平台与检查项都不同），
#      而「推完就走」会让 CI 红几天没人知道 —— 2026-09-16 实测连续 9 次 main 推送 CI 全红、
#      跨度约 3 小时无人发现。所以推送成功后必须看结论。
#
# 用法：
#   bash scripts/push-and-verify.sh            # 推送当前分支，并等 CI 结论
#   bash scripts/push-and-verify.sh main       # 显式指定分支
#   CI_CHECK=0 bash scripts/push-and-verify.sh # 只推送，不等 CI
#
# 环境变量：
#   MAX_ATTEMPTS  推送重试次数（默认 8）
#   CI_CHECK      1=推送后等 CI 结论（默认）；0=跳过
#   CI_TIMEOUT    等 CI 完成的上限秒数（默认 900）
#   CI_POLL       轮询间隔秒数（默认 20）
#
# 退出码：
#   0 = 已推送且远端已核验（CI 通过，或按 CI_CHECK=0 跳过，或没找到对应 run）
#   1 = 重试耗尽仍未推送成功
#   2 = 已推送成功，但 CI 结论不是 success

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

REMOTE_URL="https://github.com/zyejf/AutoHotkeydemo.git"
BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"
LOCAL="$(git rev-parse HEAD)"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-8}"
CI_CHECK="${CI_CHECK:-1}"
CI_TIMEOUT="${CI_TIMEOUT:-900}"
CI_POLL="${CI_POLL:-20}"

command -v gh >/dev/null 2>&1 || { echo "需要 gh（用于取 token）"; exit 1; }
TOKEN="$(gh auth token 2>/dev/null)"
[ -n "$TOKEN" ] || { echo "gh 未登录：先 gh auth login"; exit 1; }
PUSH_URL="https://x-access-token:${TOKEN}@github.com/zyejf/AutoHotkeydemo.git"

# ⚠️ 本机 `gh auth status` 会报「not logged into any GitHub hosts」，但 `gh auth token`
#    能拿到有效 token。显式导出 GH_TOKEN，`gh run *` 才工作。
export GH_TOKEN="$TOKEN"

# 读远端 sha。查询本身也要绕开坏代理，否则「远端没这个 refs」会被误判成没推送。
remote_sha() {
  env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
    git ls-remote "$REMOTE_URL" "$BRANCH" 2>/dev/null | awk '{print $1}'
}

# 推送成功后核查 CI 结论。找不到 run / 等超时都不算失败（可能没触发 CI），
# 只有「确实跑完了且结论不是 success」才返回 1。
check_ci() {
  local sha="$1" rid="" waited=0 status="" concl=""

  # 1) 找 run。GitHub 建 run 有几秒延迟，最多等 60s。
  while [ "$waited" -lt 60 ]; do
    rid="$(gh run list --limit 20 --json databaseId,headSha \
             --jq "[.[] | select(.headSha == \"$sha\")][0].databaseId" 2>/dev/null)"
    [ -n "$rid" ] && [ "$rid" != "null" ] && break
    sleep 5; waited=$((waited + 5))
  done
  if [ -z "$rid" ] || [ "$rid" = "null" ]; then
    echo "   ⚠️  60s 内没找到 head=${sha:0:8} 的 CI run（可能未触发 CI），跳过结论核查"
    return 0
  fi
  echo "   CI run: $rid —— 等待结论（最多 ${CI_TIMEOUT}s）…"

  # 2) 等跑完
  waited=0
  while [ "$waited" -lt "$CI_TIMEOUT" ]; do
    status="$(gh run view "$rid" --json status --jq '.status' 2>/dev/null)"
    concl="$(gh run view "$rid" --json conclusion --jq '.conclusion // "-"' 2>/dev/null)"
    [ "$status" = "completed" ] && break
    sleep "$CI_POLL"; waited=$((waited + CI_POLL))
  done
  if [ "$status" != "completed" ]; then
    echo "   ⚠️  CI run $rid 在 ${CI_TIMEOUT}s 内未完成（当前 status=${status:-未知}），不再等待"
    return 0
  fi

  if [ "$concl" = "success" ]; then
    echo "   ✅ CI 全绿（run $rid）"
    return 0
  fi

  echo "   ❌ CI 未通过：conclusion=$concl（run $rid）"
  echo "      失败的 job："
  gh run view "$rid" --json jobs \
    --jq '.jobs[] | select(.conclusion != "success" and .conclusion != "skipped") | "        - \(.conclusion)  \(.name)"' 2>/dev/null
  echo "      关键日志（--log-failed 尾部 25 行，已截断到 200 列）："
  gh run view "$rid" --log-failed 2>/dev/null | tail -25 | cut -c1-200 | sed 's/^/        /'
  echo "      完整日志：gh run view $rid --log-failed"
  return 1
}

# 只核查某个 sha 的 CI 结论、不推送。便于人工复核，也让「失败路径」可被自测覆盖
# （否则只能等 CI 真红才能验证这段代码 —— 那是最不该靠运气的地方）。
if [ -n "${CI_ONLY_SHA:-}" ]; then
  echo "仅核查 CI 结论：sha=${CI_ONLY_SHA:0:8}"
  if check_ci "$CI_ONLY_SHA"; then exit 0; else exit 2; fi
fi

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
    if [ "$CI_CHECK" -eq 1 ]; then
      echo "   按 TD-028 纪律核查 CI 结论…"
      if ! check_ci "$LOCAL"; then
        echo "   → 推送已成功，但 CI 未通过。修完再推；不要靠重跑掩盖。"
        exit 2
      fi
    else
      echo "   （CI_CHECK=0，跳过结论核查；手工查：gh run list --limit 1）"
    fi
    exit 0
  fi

  echo "尝试 $i/$MAX_ATTEMPTS 模式=$MODE 未成功（远端=${R:0:8}），8s 后重试…"
  tail -1 /tmp/push-verify.log
  sleep 8
done

echo "❌ ${MAX_ATTEMPTS} 次尝试后远端仍未更新到 ${LOCAL:0:8}。最后一次输出："
tail -3 /tmp/push-verify.log
exit 1
