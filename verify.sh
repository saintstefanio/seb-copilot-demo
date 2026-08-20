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
# The forks are separate repos, not vendored here. We clone upstream at the exact
# commit the trim was built against, then apply it from patches/. Pinning is what
# keeps the patch applying — upstream moves, the pinned commit does not.
# ponytail: patches carry package.json/.nxignore only, not yarn.lock (800 KB of
# churn that rots). yarn regenerates the lock from the trimmed package.json.
# To refresh after an upstream bump: bump the .sha, re-run, regenerate the patch.
clone_fork() { # dir
  local repo=$1 sha; sha=$(cat "$root/patches/$repo.sha")
  [ -d "$repo" ] && return 0
  git clone --filter=blob:none --no-checkout \
      "https://github.com/seb-oss/$repo.git" "$repo" >/dev/null 2>&1 &&
    git -C "$repo" checkout -q "$sha" &&
    git -C "$repo" apply "$root/patches/$repo.patch"
}
for repo in green Spark-packages; do
  [ -d "$repo" ] || check "clone + trim $repo" "clone-$repo" clone_fork "$repo"
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
