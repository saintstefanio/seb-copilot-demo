# SEB Copilot workshop

Three repos wired together so you can try GitHub Copilot's customisation
surface — instructions, prompts, custom agents, skills, MCP — on real SEB open
source code instead of a toy app.

Fork it, run it, work the ticket.

## Run it

```sh
./verify.sh
```

Installs everything, runs each repo's tests, starts all three servers, opens the
browser. Ctrl-C stops everything.

| | |
|---|---|
| http://localhost:5173 | payments UI |
| http://localhost:3001/accounts | payments API |
| http://localhost:4400 | green Storybook |

First run ~4 min (mostly green), after that ~2 min. Storybook's cold build is
slow — start it before you need it.

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

This is one repo: `README.md`, `verify.sh`, `jira-connector`, `seb-demo-payments`
and `patches/`. The two forks are **not** in it — `.gitignore` skips them, since
staging a directory that has its own `.git` makes a broken gitlink rather than a
submodule, and a clone would come back with two empty folders.

`verify.sh` reconstitutes them instead. It clones each fork from `seb-oss` at the
exact commit in `patches/*.sha`, then applies `patches/*.patch` — the workspace
and dependency trim. Pinning the commit is what keeps the patch applying as
upstream moves on.

```sh
git init
git add .
git status         # .env, green/ and Spark-packages/ must NOT be listed
git commit -m "SEB Copilot workshop"
git remote add origin https://github.com/saintstefanio/seb-copilot-demo.git
git push -u origin main
```

That is the whole thing. Cloning it fresh and running `./verify.sh` rebuilds all
four directories from scratch.

### Changing the trim

Edit `green/package.json` (or `.nxignore`) in place, then regenerate its patch:

```sh
git -C green diff -- . ':!yarn.lock' > patches/green.patch
```

`yarn.lock` is deliberately excluded — 800 KB of churn that goes stale on every
upstream bump. `yarn install` regenerates it from the trimmed `package.json`.

To take an upstream update, bump `patches/green.sha` to the new commit, delete
`green/`, re-run `./verify.sh`, and fix the patch if it rejects.

To drop the trim entirely and get the full monorepo back:

```sh
git -C green checkout package.json .nxignore
git -C green yarn install
```

### Forking

You only need forks to *push ticket work* — branches, PRs, Actions and issues all
need your own copy, not `seb-oss`:

```sh
gh repo fork seb-oss/green --remote=false
git -C green remote set-url origin git@github.com:<you>/green.git
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
  copy, not `seb-oss` — see [Git](#git).
- **Jira lives in project `KAN`** (*Front-End Dev*). `KAN-1`–`KAN-6` are
  connector fixtures — a story with subtasks and two bugs — there to give the
  skill something to read. File your own ticket for whatever you want the
  workshop to build.
- **Claude Code doesn't read `.github/skills/`.** Symlink it:
  `ln -s ../../.github/skills/jira jira-connector/.claude/skills/jira`.

<details>
<summary><b>What was changed in the forks</b></summary>

Both forks were trimmed so install is bearable. **No source was deleted** — only
workspace globs and dependency lists, all revertable with `git checkout`.

| | before | after |
|---|---|---|
| green `node_modules` | 2.1 GB | 998 MB |
| Spark `node_modules` | 1.0 GB | 636 MB |
| green cold install | 466s | 181s |

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
