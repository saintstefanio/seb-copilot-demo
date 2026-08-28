# SEB Copilot workshop

Try GitHub Copilot's customisation surface — instructions, prompts, custom
agents, skills, MCP — on real SEB open source code instead of a toy app.

## Install

```sh
git clone https://github.com/saintstefanio/seb-copilot-demo.git
cd seb-copilot-demo
./verify.sh
```

Done. `verify.sh` fetches the two SEB repos, installs everything, runs the tests,
starts the servers and opens the browser. Ctrl-C stops it. First run pulls ~2 GB
and takes several minutes; after that it is ~2 min.

|                                |                 |
| ------------------------------ | --------------- |
| http://localhost:5173          | payments UI     |
| http://localhost:3001/accounts | payments API    |
| http://localhost:4400          | green Storybook |

Needs Node 22 or 24. Re-running skips whatever is already there.

## The repos

```
green                FE — Lit web components + React wrappers (Nx)
Spark-packages       BE — OpenAPI typegen / express / client (Turborepo)
seb-demo-payments    glue — a runnable API + UI so the ticket has somewhere to land
jira-connector       the ticket source — stdlib-only Jira client + skill
```

**green** is hostile to a naive LLM, in the useful way: a Lit element in
`libs/core` with a `gds-` prefix, design tokens instead of hex values, a
Storybook story, a changeset *and* a matching React wrapper. None of it is
guessable — which is what the instruction files are for.

**Spark-packages** gives a tool-enforced FE/BE contract. Change the OpenAPI spec
and the type system breaks on both sides.

## Working the ticket

You work inside `green/` or `Spark-packages/`, never in this repo. Each is left
on a `workshop-base` branch with the trim already committed, so branch off it:

```sh
cd green
git checkout -b feat/gds-your-component
git add -A && git commit -m "feat(core): add gds-your-component"
git push -u origin feat/gds-your-component
```

Open the PR against **`workshop-base`**, so the diff is only your work.

Pushing needs a fork. `verify.sh` makes one automatically if the [GitHub
CLI](https://cli.github.com) is installed and logged in; otherwise fork
[green](https://github.com/seb-oss/green) when you get there and
`git remote set-url origin git@github.com:<you>/green.git`.

## Jira

Only the skill needs credentials, not `verify.sh`. They are read from the
environment — a `.env` file is not picked up on its own:

```sh
export JIRA_BASE_URL="https://<you>.atlassian.net"
export JIRA_EMAIL="you@example.com"
export JIRA_API_TOKEN="<token>"
```

Details in `jira-connector/README.md`.

## Copilot config

| Surface                  | Where                                                | Status                  |
| ------------------------ | ---------------------------------------------------- | ----------------------- |
| Repo instructions        | `Spark-packages/.github/copilot-instructions.md`   | upstream                |
| Path-scoped instructions | `green/.github/instructions/green.instructions.md` | upstream                |
| MCP                      | `green/.vscode/mcp.json`                           | upstream                |
| Jira skill               | `jira-connector/.github/skills/jira/SKILL.md`      | Copilot and Claude Code |

## Gotchas

- **Node 23** — green's `jest-diff` refuses to install. `verify.sh` passes
  `--ignore-engines`; Node 22 or 24 fixes it properly.
- **Jira lives in project `KAN`.** `KAN-1`–`KAN-6` are connector fixtures, not
  workshop tickets. File your own.
- **Claude Code doesn't read `.github/skills/`.** Symlink it:
  `mkdir -p jira-connector/.claude/skills && ln -s ../../.github/skills/jira jira-connector/.claude/skills/jira`
- **Changing the trim** — edit `green/package.json`, then
  `git -C green diff -- . ':!yarn.lock' > patches/green.patch`.

<details>
<summary><b>What was changed in the forks</b></summary>

Both forks were trimmed so install is bearable. **No source was deleted** — only
workspace globs and dependency lists, all revertable with `git checkout`.

|                       | before | after  |
| --------------------- | ------ | ------ |
| green`node_modules` | 2.1 GB | 998 MB |
| Spark`node_modules` | 1.0 GB | 636 MB |
| green cold install    | 466s   | 181s\* |

\* measured with a matching lockfile committed. `verify.sh` resolves the lock
fresh from the trimmed `package.json`, so a first run is slower than this.

- `green/package.json` — 220 → 132 deps (dropped Angular, Next, mermaid,
  webpack, web-test-runner, charts). Workspaces narrowed to `core, react, tokens, chlorophyll, extract, fonts, repo-tools`. Dropping mermaid means the
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
