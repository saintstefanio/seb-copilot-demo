#!/usr/bin/env bash
# Bring the whole Copilot demo up and prove each repo works.
# Runs each repo's own checks, then starts every server and opens the browser.
# Ctrl-C to stop everything.
set -uo pipefail
cd "$(dirname "$0")"
root=$(pwd)
logs=/tmp/seb-verify
mkdir -p "$logs"

# kill 0 signals the whole process group, so vite/nx children die too
trap 'kill 0' EXIT INT TERM

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
      commit -aqm "Workshop trim — base for the ticket, not for upstream" || return 1
  # yarn.lock is tracked, so info/exclude cannot hide it — skip-worktree can
  git -C "$repo" update-index --skip-worktree yarn.lock
}

for repo in green Spark-packages; do
  if [ ! -d "$repo" ]; then
    check "clone + trim $repo" "clone-$repo" clone_fork "$repo"
  elif ! git -C "$repo" rev-parse --verify -q workshop-base >/dev/null; then
    check "baseline $repo" "baseline-$repo" baseline "$repo"
  fi
done

# ---------------------------------------------------------------- install
echo
echo "Dependencies (green's is the slow one, ~3 min — it is a big Nx monorepo)"
[ -d seb-demo-payments/node_modules ] ||
  check "seb-demo-payments (npm)" install-glue \
    npm --prefix seb-demo-payments install
[ -d Spark-packages/.yarn/cache ] || [ -d Spark-packages/node_modules ] ||
  check "Spark-packages (yarn 4)" install-spark \
    bash -c "cd '$root/Spark-packages' && corepack yarn install"
[ -d green/node_modules ] ||
  check "green (yarn 1)" install-green \
    bash -c "cd '$root/green' && corepack yarn@1.22.22 install --ignore-engines --network-timeout 600000"

# ---------------------------------------------------------------- tests
echo
echo "Tests"
check "Spark-packages  openapi-*" test-spark \
  bash -c "cd '$root/Spark-packages' && corepack yarn turbo run test --filter='./packages/openapi-*'"
check "green           core (node)" test-green \
  bash -c "cd '$root/green' && npx nx run core:test:node"
check "seb-demo-payments api" test-glue \
  npm --prefix seb-demo-payments test

# ---------------------------------------------------------------- servers
echo
echo "Servers"
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
command -v open >/dev/null && open http://localhost:5173 http://localhost:4400

echo
if [ $failed -eq 0 ]; then
  echo "All three repos are working. Ctrl-C to stop."
else
  echo "Something failed above — see the logs in $logs. Servers still up; Ctrl-C to stop."
fi
wait
