# jira-connector

A standalone, zero-dependency Jira connector for agents — a fallback for reading,
updating, and commenting on Jira Cloud issues when an MCP server isn't available.
Stdlib only (`urllib`), so it drops into any agent runtime with no `pip install`.

- `jira_connector.py` — the `JiraConnector` class + a CLI.
- `jira_tools.py` — a framework-neutral tool wrapper (`TOOLS` + `dispatch`).

## Setup

No install step — copy the two `.py` files wherever your agent runs. You only need
three environment variables.

### `JIRA_BASE_URL`

Your Jira site root. Open Jira in a browser and keep everything before the first
`/` after the domain:

```
https://acme.atlassian.net/jira/software/projects/PROJ/boards/1
└──── this part ─────────┘
```

No `/jira`, no `/rest`, trailing slash optional. If your org uses a custom domain,
the `.atlassian.net` form is the safer bet.

### `JIRA_EMAIL`

The email of the Atlassian account that owns the token — not a display name or
username. Exact string is at
[id.atlassian.com/manage-profile/profile-and-visibility](https://id.atlassian.com/manage-profile/profile-and-visibility).
It must match the account the token was created under, or auth 401s.

### `JIRA_API_TOKEN`

1. Go to [id.atlassian.com/manage-profile/security/api-tokens](https://id.atlassian.com/manage-profile/security/api-tokens).
2. Click **Create API token** — the classic, unscoped kind, which is what this
   connector targets.
3. Name it something recognizable, e.g. `jira-connector-cli`.
4. Set an expiry. Mandatory: 1 day to 1 year, defaults to a year. Set a reminder —
   when it lapses, every call starts returning 401.
5. **Copy it immediately.** Shown once, unrecoverable afterwards.

The page also offers **Create API token with scopes**. That's tighter (you'd grant
read + write on Jira work items), but scoped tokens may need Atlassian's
`api.atlassian.com/ex/jira/{cloudId}` gateway rather than your site URL, which is
not what this connector builds. Start classic; if policy requires scoped, expect to
adjust `base_url`.

### Set them

```sh
export JIRA_BASE_URL="https://acme.atlassian.net"
export JIRA_EMAIL="you@example.com"
export JIRA_API_TOKEN="paste-here"
```

Put them in `~/.zshrc` to persist. If you'd rather use a `.env` file, add it to
`.gitignore` first. For Copilot's cloud agent, they go in repository secrets, not
your shell.

The token is full API access as you, with your permissions — treat it like a
password, never commit it, and revoke it on the tokens page if it leaks.

### Verify

Offline, no network or credentials needed:

```sh
python3 jira_connector.py selfcheck
python3 jira_tools.py
```

Then check the three values are actually right:

```sh
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_BASE_URL/rest/api/3/myself" | head -c 200
```

Account JSON means all three are good. `401` means the email/token pair is wrong;
`404` or HTML means the base URL is. Finally, end to end:

```sh
python3 jira_connector.py search 'assignee = currentUser()'
```

> Targets Jira **Cloud** (REST API v3, Basic auth). For Server/Data Center, switch
> the path to `/rest/api/2` and the auth header to `Bearer <PAT>`.

## Usage — as a library

```python
from jira_connector import JiraConnector

j = JiraConnector()                      # reads the env vars above
j.get_issue("PROJ-123")
j.search('project = PROJ AND status = "In Progress"')
j.add_comment("PROJ-123", "Looking into this.")
j.update_fields("PROJ-123", {"summary": "New summary"})

# Status changes go through transitions, not a field write:
j.list_transitions("PROJ-123")          # find the transition id
j.transition("PROJ-123", "31")
```

## Usage — as agent tools

```python
from jira_tools import TOOLS, dispatch

# Give TOOLS (JSON-schema tool specs) to your model as tool definitions.
# On a tool call from the model:
result = dispatch(call.name, call.arguments)
```

`dispatch(name, args)` takes a tool name and an arguments dict, so any
function/tool-calling loop can route through it. Available tools:
`jira_get_issue`, `jira_search`, `jira_add_comment`, `jira_update_fields`,
`jira_list_transitions`, `jira_transition`.

## Usage — as an agent skill

`.github/skills/jira/SKILL.md` packages the CLI as an [Agent Skill](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills) —
an open format read by GitHub Copilot, Claude Code, and others. The agent loads it
on its own when a prompt mentions a Jira key or JQL; you don't invoke it by name.

**GitHub Copilot** — supported in the cloud agent, code review, Copilot CLI, the
Copilot app, and agent mode in VS Code and JetBrains.

- *This repo, for the whole team:* nothing to do. Commit `.github/skills/` and
  everyone who clones it gets the skill.
- *Every repo, just you:* copy the folder to your personal skills directory:

  ```sh
  mkdir -p ~/.copilot/skills/jira
  cp .github/skills/jira/SKILL.md jira_connector.py jira_tools.py ~/.copilot/skills/jira/
  ```

  Then edit the copied `SKILL.md` — it says to run the commands "from the repo
  root", which is no longer true once the scripts sit beside it.

**Claude Code** — same file, same layout, at `.claude/skills/jira/` (project) or
`~/.claude/skills/jira/` (personal).

The env vars above must be set wherever the agent runs. For Copilot's cloud agent
that means repository secrets, not your shell.

## Usage — as a CLI

```sh
python3 jira_connector.py get PROJ-123
python3 jira_connector.py search 'assignee = currentUser()'
python3 jira_connector.py comment PROJ-123 "Deploying now."
python3 jira_connector.py update PROJ-123 '{"summary": "New summary"}'
python3 jira_connector.py transitions PROJ-123
python3 jira_connector.py transition PROJ-123 31
```
