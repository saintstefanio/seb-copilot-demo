# SEB Copilot workshop

Four directories wired together so you can try GitHub Copilot's customisation
surface — instructions, prompts, custom agents, skills, MCP — on real SEB open
source code instead of a toy app.

Clone it, run it, work the ticket.

## Install

You need **Node 22 or 24** (23 works but warns — see [Gotchas](#gotchas)),
**Python 3.9+**, git, and about 4 GB of free disk.

First fork the two upstream repos to your own account — `verify.sh` clones from
your forks, so this is required, not optional:

```sh
gh repo fork seb-oss/green --clone=false
gh repo fork seb-oss/Spark-packages --clone=false
```

No `gh`? Hit **Fork** on [seb-oss/green](https://github.com/seb-oss/green) and
[seb-oss/Spark-packages](https://github.com/seb-oss/Spark-packages). Then:

```sh
git clone https://github.com/saintstefanio/seb-copilot-demo.git
cd seb-copilot-demo
./verify.sh          # forked under another name? FORK_OWNER=<you> ./verify.sh
```

That is the whole install. `verify.sh` clones the two upstream repos at pinned
commits and applies the trim, installs every dependency, runs each repo's tests,
starts three servers and opens the browser. Ctrl-C stops all of it.

| | |
|---|---|
| http://localhost:5173 | payments UI |
| http://localhost:3001/accounts | payments API |
| http://localhost:4400 | green Storybook |

First run pulls ~2 GB and takes several minutes — green dominates it, and its
lockfile is resolved fresh against the trimmed `package.json`. After that it is
~2 min. Storybook's cold build is the slow part; start it before you need it.

Re-running is safe: anything already on disk is skipped. To start clean, delete
`green/`, `Spark-packages/` and the `node_modules` folders and run it again.

### Jira credentials

Only the Jira skill needs these — `verify.sh` does not. The connector reads the
environment directly, so a `.env` file is **not** picked up on its own:

```sh
export JIRA_BASE_URL="https://<you>.atlassian.net"
export JIRA_EMAIL="you@example.com"
export JIRA_API_TOKEN="<token>"
```

Put them in `~/.zshrc` to persist. Token scope and handling:
`jira-connector/README.md`.

### Using Claude Code instead of Copilot

Claude Code does not read `.github/skills/`. Symlink it once:

```sh
mkdir -p jira-connector/.claude/skills
ln -s ../../.github/skills/jira jira-connector/.claude/skills/jira
```

## The repos

```
green                fork   FE — Lit web components + React wrappers (Nx)
Spark-packages       fork   BE — OpenAPI typegen / express / client (Turborepo)
seb-demo-payments    new    glue — a runnable API + UI so the ticket has somewhere to land
jira-connector       new    where the ticket comes from — stdlib-only Jira client + skill
```

**green** is hostile to a naive LLM, in the useful way. It wants a Lit element
in `libs/core` with a `gds-` prefix, design tokens instead of hex values, a
Storybook story, a changeset *and* a matching React wrapper. None of that is
guessable — which is exactly what the instruction files are for.

**Spark-packages** gives a tool-enforced FE/BE contract. `openapi-typegen`
generates types from a spec, `openapi-express` implements against them,
`openapi-client` consumes them. Change the spec and the type system breaks on
both sides. Nothing about the cross-repo dependency is staged.

**seb-demo-payments** exists because neither fork has a running app. ~310 lines,
both halves typed off the same OpenAPI spec, so a finished ticket is something
you can actually look at.

**jira-connector** is the ticket source, and the answer to the security question
you will get asked. Zero dependencies, six commands, no `create` and no delete —
a file you can read end to end before you let an agent near your Jira. Same
`SKILL.md` works in Copilot and Claude Code. Setup is three env vars; see
`jira-connector/README.md`.

## Git

This repo tracks `README.md`, `verify.sh`, `jira-connector/`,
`seb-demo-payments/` and `patches/` — about 8 000 lines. `green` and
`Spark-packages` are **not** in it. `.gitignore` skips them: staging a directory
that carries its own `.git` produces a broken gitlink rather than a submodule,
and a clone would come back with two empty folders.

`verify.sh` reconstitutes them instead. For each, it clones **your fork** at the
exact commit in `patches/<repo>.sha`, applies `patches/<repo>.patch` — the
workspace and dependency trim — and commits that as a branch called
`workshop-base`. Pinning the commit is what keeps the patch applying as upstream
moves on; cloning your fork rather than `seb-oss` is what lets you push.

Forked under a different account? `FORK_OWNER=<you> ./verify.sh`.

`.env` is gitignored too. Recreate it after a fresh clone; see
[Jira credentials](#jira-credentials).

### Changing the trim

Edit `green/package.json` or `green/.nxignore` in place, then regenerate the
patch:

```sh
git -C green diff -- . ':!yarn.lock' > patches/green.patch
```

`yarn.lock` is deliberately excluded — 800 KB of churn that goes stale on every
upstream bump. `yarn install` regenerates it from the trimmed `package.json`.

To take an upstream update: put the new commit in `patches/green.sha`, delete
`green/`, re-run `./verify.sh`, and fix the patch if it rejects.

To drop the trim and get the full monorepo back:

```sh
git -C green checkout package.json .nxignore
cd green && yarn install
```

### Working the ticket

Prerequisite: fork both repos to your own account, once. `verify.sh` clones from
there, and you cannot push to `seb-oss`.

```sh
gh repo fork seb-oss/green --clone=false
gh repo fork seb-oss/Spark-packages --clone=false
```

The ticket is implemented **inside `green/` or `Spark-packages/`** — not in this
repo. This one only ships `verify.sh` and `patches/`, so nothing you build for
the ticket belongs here and no PR is ever opened against it.

`verify.sh` leaves each fork on a `workshop-base` branch with the trim committed.
Branch off that:

```sh
cd green
git checkout -b feat/gds-your-component
# ... implement, including the story, the React wrapper and the changeset
git add -A && git commit -m "feat(core): add gds-your-component"
git push -u origin feat/gds-your-component
```

Open the PR **against `workshop-base` in your own fork**, not against `main` and
not against `seb-oss`. That is the point of the base branch: the trim is already
in it, so the PR diff is exactly your work. Target `main` instead and the PR also
proposes deleting Angular, Next and 88 dependencies.

`yarn.lock` is added to `.git/info/exclude` in each clone, since `yarn install`
rewrites it and the ticket does not need it.

If you genuinely want to send something upstream — one of the bugs below, say —
branch from the pinned commit rather than from `workshop-base`:

```sh
git checkout -b fix/upstream-thing $(cat ../patches/green.sha)
```

## Copilot config

| Surface | Where | Status |
|---|---|---|
| Repo instructions | `Spark-packages/.github/copilot-instructions.md` | upstream |
| Path-scoped instructions | `green/.github/instructions/green.instructions.md` | upstream |
| MCP | `green/.vscode/mcp.json` (green's own MCP server) | upstream |
| Jira skill | `jira-connector/.github/skills/jira/SKILL.md` | works — Copilot and Claude Code |

## Gotchas

- **Node 23** — green's `jest-diff` refuses to install (it allows 18/20/22/24+).
  `verify.sh` passes `--ignore-engines`; Node 22 or 24 fixes it properly.
- **Fork before you push.** Issues, branches, Actions and PRs all need your own
  copy, not `seb-oss` — see [Working the ticket](#working-the-ticket).
- **Jira lives in project `KAN`** (*Front-End Dev*). `KAN-1`–`KAN-6` are
  connector fixtures — a story with subtasks and two bugs — there to give the
  skill something to read. File your own ticket for whatever you want the
  workshop to build.

<details>
<summary><b>What was changed in the forks</b></summary>

Both forks were trimmed so install is bearable. **No source was deleted** — only
workspace globs and dependency lists, all revertable with `git checkout`.

| | before | after |
|---|---|---|
| green `node_modules` | 2.1 GB | 998 MB |
| Spark `node_modules` | 1.0 GB | 636 MB |
| green cold install | 466s | 181s\* |

\* measured with a matching lockfile committed. `verify.sh` resolves the lock
fresh from the trimmed `package.json`, so a first run is slower than this.

- `green/package.json` — 220 → 132 deps (dropped Angular, Next, mermaid,
  webpack, web-test-runner, charts). Workspaces narrowed to `core, react,
  tokens, chlorophyll, extract, fonts, repo-tools`. Dropping mermaid means the
  two Storybook docs pages that embed diagrams show the diagram source instead
  (`libs/core/.storybook/blocks/Mermaid.jsx`).
- `green/.nxignore` — hides the unused libs and `apps/` from the Nx graph. To
  bring one back: delete its line here and re-add it to `workspaces`.
- `Spark-packages/package.json` — workspaces narrowed from all 35 packages to
  the 9 in the openapi chain. All 35 are still on disk.

</details>

<details>
<summary><b>Upstream bugs found while building this</b></summary>

- `green` — `libs/react/rollup.config.mjs` calls `glob.sync` (the v10 API) but
  `glob` was never declared as a dependency; it rode on hoisting. Fixed here by
  declaring `glob: ^10.4.5`. Worth an issue.
- `green` — `gds-filter-chips` emits `change`, but green-core's generated React
  wrapper binds `onChange` to `input`, so the prop never fires. Affects every
  React consumer. `seb-demo-payments/web/src/App.tsx` works around it with a ref.
- `@sebspark/openapi-client` can't be bundled for a browser — it pulls the
  Node-only OTel SDK. The demo UI uses `fetch` against the same generated types.

Each is a decent first target for "Copilot, open an issue for this".

</details>
