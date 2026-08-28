# SEB Copilot workshop

Try GitHub Copilot's customisation surface — instructions, prompts, custom
agents, skills, MCP — on real SEB open source code instead of a toy app.

## Install

**macOS / Linux**

```sh
git clone https://github.com/saintstefanio/seb-copilot-demo.git
cd seb-copilot-demo
./verify.sh
```

**Windows** — from PowerShell or Windows Terminal:

```powershell
git clone https://github.com/saintstefanio/seb-copilot-demo.git
cd seb-copilot-demo
powershell -ExecutionPolicy Bypass -File .\verify.ps1
```

Done. The script fetches the two SEB repos, installs everything, runs the tests,
starts the servers and opens the browser. Ctrl-C stops it. First run pulls ~2 GB
and takes several minutes; after that it is ~2 min.

|                                |                 |
| ------------------------------ | --------------- |
| http://localhost:5173          | payments UI     |
| http://localhost:3001/accounts | payments API    |
| http://localhost:4400          | green Storybook |

Re-running skips whatever is already there.

`verify.sh` needs Node 22 or 24 already installed. `verify.ps1` needs nothing —
it installs its own Node and Git, per-user and without admin, under
`%LOCALAPPDATA%\Programs\seb-workshop`, and picks up a corporate proxy and the
Windows certificate store on its own. It is a separate file rather than a flag
on `verify.sh` because PowerShell refuses to run any script without a `.ps1`
extension, so one file cannot serve both shells — the same reason Maven ships
`mvnw` and `mvnw.cmd`.

Both scripts take the same switches, in each platform's convention:
`-SkipTests` / `--skip-tests`, `-SkipServers` / `--skip-servers`,
`-Reinstall` / `--reinstall`, `-ForkOwner <you>` / `--fork-owner <you>`.
Aside from the bootstrapping that only `verify.ps1` can do, the two behave
identically and print the same output.

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
- **Windows** — use `verify.ps1`; it handles all of this for you. If you would
  rather run `verify.sh` under Git Bash, two things bite:
  - *Behind a corporate proxy*, npm and yarn 1 read `HTTP_PROXY` but corepack
    and yarn 4 do not, so they die with `ENOTFOUND`. Both scripts wire that up
    for you from `HTTP_PROXY`/`HTTPS_PROXY`. If TLS is intercepted you also get
    `UNABLE_TO_GET_ISSUER_CERT_LOCALLY` — `verify.ps1` exports the Windows
    certificate store itself; for `verify.sh`, point `NODE_EXTRA_CA_CERTS` at a
    PEM of the corporate root CA before running.
  - *Defender* — nothing to do about it without admin, but excluding the repo
    and the npm/yarn caches from real-time scanning roughly halves install time.
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
- `nx` — the `post-install` hook rebuilds the project graph, and on Windows it
  pins a core at 100% for 40+ minutes (measured: 2320s of CPU, zero read ops —
  it spins rather than doing I/O). The work is redundant, since nx rebuilds the
  graph on demand. `verify.sh` parks `nx.json` for the length of the install so
  the hook no-ops. Worth an issue upstream.
- `green` — `gds-filter-chips` emits `change`, but green-core's generated React
  wrapper binds `onChange` to `input`, so the prop never fires. Affects every
  React consumer. `seb-demo-payments/web/src/App.tsx` works around it with a ref.
- `@sebspark/openapi-client` can't be bundled for a browser — it pulls the
  Node-only OTel SDK. The demo UI uses `fetch` against the same generated types.

Each is a decent first target for "Copilot, open an issue for this".

</details>
