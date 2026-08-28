#!/usr/bin/env bash
# Bring the whole Copilot demo up and prove each repo works.
# Runs each repo's own checks, then starts every server and opens the browser.
# Ctrl-C to stop everything.
set -uo pipefail
cd "$(dirname "$0")"
root=$(pwd)
logs=/tmp/seb-verify
mkdir -p "$logs"

skip_tests=0 skip_servers=0 reinstall=0
while [ $# -gt 0 ]; do
  case $1 in
    --skip-tests)   skip_tests=1 ;;
    --skip-servers) skip_servers=1 ;;
    --reinstall)    reinstall=1 ;;
    --fork-owner)   FORK_OWNER=${2:-}; shift ;;
    -h|--help)      sed -n '2,4s/^# //p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
export FORK_OWNER="${FORK_OWNER:-}"

# kill 0 signals the whole process group, so vite/nx children die too. Only do
# that once servers are up -- on a clean early exit it would kill this script.
servers_running=0
stop_all() { kill 0 2>/dev/null || true; }
on_exit() { [ "$servers_running" = 1 ] && stop_all; return 0; }
trap stop_all INT TERM
trap on_exit EXIT

failed=0
check() { # name, log-slug, command...
  local name=$1 slug=$2; shift 2
  printf '  %-32s' "$name"
  if "$@" >"$logs/$slug.log" 2>&1; then
    echo "ok"
  else
    echo "FAIL  -> $logs/$slug.log"
    failed=1
  fi
}

# Same contract as check(), but queued and run concurrently — the repos are
# independent. wait_checks blocks and prints in the order queued.
bg_pids=() bg_names=() bg_slugs=()
start_check() { # name, log-slug, command...
  local name=$1 slug=$2; shift 2
  "$@" >"$logs/$slug.log" 2>&1 &
  bg_pids+=("$!") bg_names+=("$name") bg_slugs+=("$slug")
}

wait_checks() {
  (( ${#bg_pids[@]} )) || return 0
  local i
  for i in "${!bg_pids[@]}"; do
    printf '  %-32s' "${bg_names[$i]}"
    if wait "${bg_pids[$i]}"; then
      echo "ok"
    else
      echo "FAIL  -> $logs/${bg_slugs[$i]}.log"
      failed=1
    fi
  done
  bg_pids=() bg_names=() bg_slugs=()
}

serve() { # name, log-slug, dir, command...
  local name=$1 slug=$2 dir=$3; shift 3
  ( cd "$dir" && "$@" ) >"$logs/$slug.log" 2>&1 &
  echo "  started $name  -> $logs/$slug.log"
}

wait_for() { # url, seconds
  local url=$1 deadline=$(( SECONDS + $2 ))
  until curl -sfo /dev/null "$url"; do
    (( SECONDS > deadline )) && return 1
    sleep 2
  done
}

open_url() { # url...
  if command -v open >/dev/null 2>&1; then open "$@"
  elif command -v xdg-open >/dev/null 2>&1; then for u; do xdg-open "$u"; done
  elif command -v powershell.exe >/dev/null 2>&1; then
    for u; do powershell.exe -NoProfile -Command "Start-Process '$u'" >/dev/null 2>&1; done
  fi
}

# Storybook's telemetry cache file throws EBUSY on Windows from inside an async
# handler, taking the dev server down seconds after it starts serving.
export STORYBOOK_DISABLE_TELEMETRY=1 DO_NOT_TRACK=1

# ---------------------------------------------------------------- proxy
# npm and yarn 1 read HTTP_PROXY themselves; corepack (Node's fetch) and yarn 4
# do not, and fail with ENOTFOUND instead. If TLS is intercepted, point
# NODE_EXTRA_CA_CERTS at the corporate CA bundle — yarn 4 picks it up from here.
if [ -n "${HTTPS_PROXY:-${HTTP_PROXY:-}}" ]; then
  export NODE_USE_ENV_PROXY=1
  [ -n "${HTTP_PROXY:-}" ]  && export YARN_HTTP_PROXY="$HTTP_PROXY"
  [ -n "${HTTPS_PROXY:-}" ] && export YARN_HTTPS_PROXY="$HTTPS_PROXY"
  [ -n "${NODE_EXTRA_CA_CERTS:-}" ] &&
    export YARN_HTTPS_CA_FILE_PATH="$NODE_EXTRA_CA_CERTS"
fi

# nx shells out to `yarn` for green's dependent tasks, so the shim has to be a
# real file on PATH -- `corepack yarn` being resolvable is not enough.
command -v yarn >/dev/null 2>&1 || corepack enable >/dev/null 2>&1 || true

# ---------------------------------------------------------------- clone
# green and Spark-packages are not vendored here. Clone them at the pinned
# commit, apply the trim from patches/, and commit it as "workshop-base" so a
# feature branch diffs clean against it.
clone_fork() { # repo
  local repo=$1 sha; sha=$(cat "$root/patches/$repo.sha")
  git clone --filter=blob:none --no-checkout \
    "https://github.com/${FORK_OWNER:-seb-oss}/$repo.git" "$repo" || return 1
  git -C "$repo" checkout -q "$sha" || return 1
  git -C "$repo" apply "$root/patches/$repo.patch" || return 1
  baseline "$repo" || return 1
  # Pushing needs a fork. Do it here if gh is authenticated, otherwise skip —
  # you only need it at PR time, and the README says how.
  if [ -z "${FORK_OWNER:-}" ] && gh auth status >/dev/null 2>&1; then
    ( cd "$repo" && gh repo fork --remote --remote-name origin ) >/dev/null 2>&1 || true
  fi
}

# Put the trim on a real branch and commit it, so the worktree reads clean and
# your ticket shows up as your changes, not the trim's. Also repairs an older
# clone that still has the trim sitting uncommitted on a detached HEAD.
baseline() { # repo
  local repo=$1
  # a real branch — commits on a detached HEAD go unreachable
  git -C "$repo" checkout -q -B workshop-base || return 1
  git -C "$repo" diff --quiet ||
    git -C "$repo" -c user.name=workshop -c user.email=workshop@localhost \
      commit -aqm "Workshop trim - base for the ticket, not for upstream" || return 1
  # yarn.lock is tracked, so info/exclude cannot hide it — skip-worktree can
  git -C "$repo" update-index --skip-worktree yarn.lock
}

echo
echo "Repos"
for repo in green Spark-packages; do
  if [ ! -d "$repo" ]; then
    start_check "clone + trim $repo" "clone-$repo" clone_fork "$repo"
  elif ! git -C "$repo" rev-parse --verify -q workshop-base >/dev/null; then
    start_check "baseline $repo" "baseline-$repo" baseline "$repo"
  fi
done
wait_checks

# ---------------------------------------------------------------- install
# nx's postinstall rebuilds the project graph and can spin at 100% CPU for the
# better part of an hour on Windows. It is redundant — nx rebuilds on demand —
# and the hook no-ops without an nx.json, so park the file for the install.
install_green() {
  local parked= rc=0
  [ -f "$root/green/nx.json" ] &&
    mv "$root/green/nx.json" "$root/green/nx.json.parked" && parked=1
  ( cd "$root/green" && corepack yarn@1.22.22 install \
      --ignore-engines --network-timeout 600000 --network-concurrency 16 ) || rc=$?
  [ -n "$parked" ] && mv "$root/green/nx.json.parked" "$root/green/nx.json"
  return $rc
}

echo
echo "Dependencies (installing all three in parallel; green is the slow one)"
if [ $reinstall -eq 1 ] || [ ! -d seb-demo-payments/node_modules ]; then
  start_check "seb-demo-payments (npm)" install-glue \
    npm --prefix seb-demo-payments install --no-audit --no-fund
fi
if [ $reinstall -eq 1 ] ||
   { [ ! -d Spark-packages/.yarn/cache ] && [ ! -d Spark-packages/node_modules ]; }; then
  start_check "Spark-packages (yarn 4)" install-spark \
    bash -c "cd '$root/Spark-packages' && corepack yarn install"
fi
if [ $reinstall -eq 1 ] || [ ! -d green/node_modules ]; then
  start_check "green (yarn 1)" install-green install_green
fi
wait_checks

# ---------------------------------------------------------------- tests
if [ $skip_tests -eq 0 ]; then
  echo
  echo "Tests"
  start_check "Spark-packages  openapi-*" test-spark \
    bash -c "cd '$root/Spark-packages' && corepack yarn turbo run test --filter='./packages/openapi-*'"
  start_check "green           core (node)" test-green \
    bash -c "cd '$root/green' && npx nx run core:test:node"
  start_check "seb-demo-payments api" test-glue \
    npm --prefix seb-demo-payments test
  wait_checks
fi

if [ $skip_servers -eq 1 ]; then
  echo
  if [ $failed -eq 0 ]; then
    echo "All three repos are working."
  else
    echo "Something failed above - see the logs in $logs"
  fi
  exit $failed
fi

# ---------------------------------------------------------------- servers
echo
echo "Servers"
# Ctrl-C leaves this cache half-written and the next run dies on it with EBUSY.
# Dropping it only costs the rebuild we are about to wait for anyway.
rm -rf green/node_modules/.cache/storybook/default/dev-server 2>/dev/null
servers_running=1
serve "payments api    :3001" api  seb-demo-payments npm run dev -w api
serve "payments web    :5173" web  seb-demo-payments npm run dev -w web
serve "green storybook :4400" book green npx nx run core:storybook

echo
echo "Waiting for servers (storybook builds green first, give it a few minutes)"
wait_for http://localhost:3001/accounts 60 &&
  echo "  payments api    http://localhost:3001/accounts" ||
  { echo "  payments api    TIMEOUT -> $logs/api.log"; failed=1; }
wait_for http://localhost:5173/ 60 &&
  echo "  payments web    http://localhost:5173" ||
  { echo "  payments web    TIMEOUT -> $logs/web.log"; failed=1; }
wait_for http://localhost:4400/ 600 &&
  echo "  green storybook http://localhost:4400" ||
  { echo "  green storybook TIMEOUT -> $logs/book.log"; failed=1; }

# ---------------------------------------------------------------- browser
open_url http://localhost:5173 http://localhost:4400

echo
if [ $failed -eq 0 ]; then
  echo "All three repos are working. Ctrl-C to stop."
else
  echo "Something failed above — see the logs in $logs. Servers still up; Ctrl-C to stop."
fi
wait
exit $failed
